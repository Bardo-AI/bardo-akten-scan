# Bardo Akten-Scan — Code-Dokumentation

Technische Dokumentation des Programms. Für Code-Wartung, Erweiterung und
Debugging — nicht für Endnutzer.

---

## Dateien-Übersicht

Repo-Layout (`bardo-akten-scan/`):

| Pfad im Repo | Zweck |
|---|---|
| `bin/bardo-scan` | GUI-Hauptskript (Python 3 + Tkinter), ausführbar |
| `bin/bardo-duplex-merge` | CLI-Hilfstool für Manuell-Duplex-Emulation (Single-Sided-Scanner) |
| `share/applications/bardo-scan.desktop` | XDG-Desktop-Eintrag für App-Menü |
| `share/icons/bardo-scan.svg` | Icon |
| `install.sh` | Userspace-Install nach `~/.local/`, mit Dependency-Check |
| `README.md` | Projektübersicht |
| `LICENSE`, `LICENSE-MIT`, `LICENSE-APACHE` | Dual-License-Volltexte |
| `docs/Bedienungsanleitung.md` | Endnutzer-Doku |
| `docs/Code-Dokumentation.md` | Diese Datei |

Nach `install.sh` werden die Programme als Symlinks unter
`~/.local/bin/`, `~/.local/share/applications/` und
`~/.local/share/icons/` verfügbar.

---

## Architektur — Pipeline-Stufen

Das Programm ist eine GUI-Schale um eine 5-stufige Verarbeitungs-Pipeline:

```
   ┌─────────────┐
   │ Tkinter-GUI │ → User-Input: Aktenordner-Name, Optionen
   └─────────────┘
          │
          ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ subprocess.Popen(scanimage)                                  │
   │   brscan5-Backend → JPEG-Stream → /tmp-äquivalent → page*.jpg│
   │   Live-Progress wird geparsed und in Status-Box geloggt      │
   └──────────────────────────────────────────────────────────────┘
          │
          ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ _run_ocr_pipeline (5 Stufen):                                │
   │  [1/5] img2pdf          JPEGs → Beweis-PDF (image-only)      │
   │  [2/5] ocrmypdf -l deu  Beweis-PDF → searchable.pdf (PDF/A)  │
   │  [3/5] pdfseparate      searchable.pdf → pdf/page%04d.pdf    │
   │  [4/5] pdftotext        searchable.pdf → txt/page%04d.txt    │
   │  [5/5] cleanup          JPEGs entfernen (im Beweis enthalten) │
   └──────────────────────────────────────────────────────────────┘
          │
          ▼
   ┌─────────────────┐
   │ _write_manifest │ → SHA256 über alle Outputs → sha256.txt
   └─────────────────┘
```

Jede Stufe läuft als externer Prozess. Die Pipeline ist linear, kein
Multiprocessing — `ocrmypdf` parallelisiert intern via `--jobs N` mit
`N = max(1, os.cpu_count() // 2)` (dynamisch zur Hardware). Stufe [2/5]
läuft seit 2026-05-10 als `subprocess.Popen` mit Live-Progress-Stream:
ocrmypdf-Phasen (Scanning, OCR, Postprocessing) werden mit `--progress-bar
enabled` an stderr geschrieben, im Skript per `\d+%`-Pattern geparsed und
nur an 10 %-Schwellen in das Status-Fenster geloggt.

Threading: das Tkinter-Mainloop bleibt responsive. Der eigentliche Scan-Run läuft
in einem `threading.Thread` (`_run_scan`), Status-Updates gehen via `self.log()`
zurück in die GUI.

### Multi-Model-Detection

`list_all_scanners()` ruft `scanimage -L` auf und parst alle gefundenen Geräte
zu einer Liste von Dicts mit Backend-Kennzeichnung (`brother5`, `brother4`,
`escl`, `airscan`) und Priorität:

| Priorität | Kriterium |
|---|---|
| 1 | Brother ADS-Reihe (Premium, Duplex+Auto-Features) |
| 2 | brother5 anderswie |
| 3 | MFC-Reihe via eSCL (saubere ipp-usb Bridge) |
| 4 | brother4 für ältere Brother |
| 5 | escl generic |
| 6 | airscan (treiberlos, manchmal buggy) |
| 9 | unknown |

`parse_device_capabilities(device)` ruft pro Gerät `scanimage -d <dev> --help`
auf und extrahiert Modes, Sources, Resolutions, aktive Optionen, max
Scan-Bereich. Robustes Source-Parsing splittet auf `|` aber respektiert
Klammern (für Brother-Long-Strings wie
`Automatic Document Feeder(center aligned,Duplex)`).

Die GUI füllt Mode/Resolution/Source-Comboboxen dynamisch beim Geräte-Wechsel
(`_on_device_change`). Auto-Feature-Checkboxen werden je nach Verfügbarkeit
ein- oder ausgegraut (`_update_feature_availability`). Backend-spezifische
Fallbacks greifen wenn `--help` leer kommt (z.B. brother4 sagt manchmal
nichts ohne Device-Open).

---

## Manuell-Duplex-Emulation — `bardo-duplex-merge`

### Zweck

Single-Sided-Scanner (z.B. alte Brother MFCs ohne ADF-Duplex-Einheit) können
manuell als Pseudo-Duplex eingesetzt werden: erst face-up scannen, dann
Stapel umdrehen und nochmal scannen. Das Tool merget die zwei Scan-Job-Ordner
zu einem korrekt sortierten Duplex-Output.

### Architektur

Standalone-CLI-Skript (`~/.local/bin/bardo-duplex-merge`), reine
File-Operations + ein `pdfunite` für die Bulk-PDF-Konkatenation. Operiert
ausschließlich innerhalb `~/Akten-Scans/` — keine Modifikation der
Quell-Job-Ordner (immutable Beweis-Material).

```
   ┌──────────────────────────────────────────────────────┐
   │ Input: Job_A (Vorderseiten) + Job_B (Rückseiten)     │
   │   (jeweils bardo-scan-Output mit pdf/+txt/)          │
   └──────────────────────────────────────────────────────┘
              │
              ▼
   ┌──────────────────────────────────────────────────────┐
   │ Validierung: Page-Count beider Runs muss matchen     │
   └──────────────────────────────────────────────────────┘
              │
              ▼
   ┌──────────────────────────────────────────────────────┐
   │ Interleave-Loop für i = 0..N-1:                      │
   │   merged[2i+1] = front_pdfs[i]      (run1, normal)   │
   │   merged[2i+2] = back_pdfs[N-1-i]   (run2, reverse)  │
   │   plus identische Logik für TXTs                     │
   └──────────────────────────────────────────────────────┘
              │
              ▼
   ┌──────────────────────────────────────────────────────┐
   │ pdfunite alle interleaved page*.pdf → bulk.pdf        │
   │ + _merge_info.json (Provenance)                       │
   │ + sha256.txt (Manifest über alle Outputs)             │
   └──────────────────────────────────────────────────────┘
```

### Interleave-Konvention (final verifiziert)

Für Brother MFC-L5700DN mit Standard-Flip-Methode (Stapel face-up scannen,
dann face-down umdrehen ohne Reihenfolge-Änderung, nochmal scannen):

- **run1** (erster Lauf, face-up): Vorderseiten in physischer Reihenfolge
  (sheet 1, 2, ..., N) — `front_pdfs[i]` ist Vorderseite des i-ten Blatts
- **run2** (zweiter Lauf, face-down): Rückseiten in **umgekehrter** Reihenfolge
  (sheet N, N-1, ..., 1) — `back_pdfs[N-1-i]` ist Rückseite des i-ten Blatts

Pair für Blatt i (0-indexed):
```
merged[2i+1] = front_pdfs[i]     # Vorderseite
merged[2i+2] = back_pdfs[N-1-i]  # Rückseite
```

Diese Konvention wurde durch 4 Test-Iterationen (test1..test4) eingegrenzt.
Vorherige Hypothesen (front[N-1-i]+back[i], back[i]+front[N-1-i],
back[N-1-i]+front[i]) wurden alle verworfen — das User-Feedback nach jedem
Lauf hat das Pairing präzisiert.

### Andere ADF-Konventionen — Mode A-D (implementiert 2026-05-10)

Falls bei einem anderen Scanner die obige Konvention falsche Resultate
liefert (Sheet-Order und/oder Within-Pair-Order verkehrt), wählt das
`--mode`-Flag eine andere Permutation. Dict-Lookup vor der Loop:

```python
MODE_RULES = {
    "a": (("f", lambda i, n: i),         ("b", lambda i, n: n - 1 - i)),
    "b": (("f", lambda i, n: n - 1 - i), ("b", lambda i, n: i)),
    "c": (("b", lambda i, n: i),         ("f", lambda i, n: n - 1 - i)),
    "d": (("b", lambda i, n: n - 1 - i), ("f", lambda i, n: i)),
}
```

User-friendly Aliases (`MODE_ALIASES`):
- `a` ↔ `flip-short` (Standard, Karte umdrehen, MFC-L5700DN)
- `b` ↔ `flip-long` (lange Kante drehen)
- `c` ↔ `reverse-both` (beide Stapel umgekehrt)
- `d` ↔ `same-direction` (gleich-Richtung-Trick)

Im `_merge_info.json` wird das angewandte Mode-Feld als `mode` plus die
menschlich lesbare Beschreibung als `interleave_pattern` mitgeschrieben —
für nachträgliche Provenanz.

### CLI-Aufruf

```
bardo-duplex-merge <front-job-dir> <back-job-dir> [<aktenordner-name>] [--mode MODE]
```

- `<front-job-dir>`: Pfad zum bardo-scan-Job mit Vorderseiten
- `<back-job-dir>`: Pfad zum bardo-scan-Job mit Rückseiten (nach Stapel-Flip)
- `<aktenordner-name>` (optional): Zielordner-Name unter `$BARDO_SCAN_BASE`
  (Default `~/Akten-Scans/`). Default: übergeordneter Ordner des Front-Jobs.
- `--mode MODE` (optional, default `a`): Stapel-Orientierung,
  siehe `bardo-duplex-merge --help` für volle Liste.

Output: `$BARDO_SCAN_BASE/<aktenordner>/<timestamp>-duplex/`

---

## GUI-Integration der Duplex-Emulation

In `bardo-scan` ist eine zweite Sektion „Duplex-Emulation" eingebaut, die
unter dem normalen Scan-Status erscheint. Sie ruft `bardo-duplex-merge`
intern als Subprocess auf — keine Code-Duplikation der Merge-Logik.

### UX-Eigenschaften

- **Aktenordner-Name** Feld wird automatisch beim Scan-Start vorbefüllt
  (in `start_scan()` nach Validierung wird der Name in `duplex_name_entry`
  geschrieben). Der DAU muss nichts neu eintippen.
- **Stapel-Orientierungs-Combobox** (`self.duplex_mode`) mit vier
  DAU-Sprache-Optionen, die intern auf Mode A-D mappen
  (`self.duplex_mode_map`). Default: Standard-Modus (a). Bei falschem
  Ergebnis: nächste Option wählen statt nochmal zu scannen.
- **Großer Knopf** himmelblau (`bg="#5fa8d3"`), unterscheidet sich klar vom
  grünen Scan-Knopf — versehentliche Verwechslung praktisch ausgeschlossen.
- **Eigenes Status-Fenster** (zweites `ScrolledText`-Widget). Streamt die
  Subprocess-Ausgabe von `bardo-duplex-merge` Zeile für Zeile in die GUI.
  Mensch behält Kontrolle bei Wartezeit.
- **Auto-Detection** der zwei letzten Scan-Jobs im Aktenordner (sortiert
  nach Timestamp, ausgenommen `*-duplex` Verzeichnisse).
- **Klickbarer Output-Link** öffnet die durchsuchbare Duplex-PDF nach
  Fertigstellung.

### Validierung vor Trigger

```python
# in start_duplex_merge():
1. Name aus duplex_name_entry, falls leer aus name_entry (Scan-Feld)
2. Falls beide leer → MessageBox-Fehler "Eingabe fehlt"
3. Sanitize Name: re.sub(r"[^A-Za-z0-9_äöüÄÖÜß-]", "_", name)
4. Prüfe SCAN_BASE / safe_name ist directory
5. Iteriere über Sub-Dirs, ohne *-duplex, mit pdf/-Unterordner
6. len(scan_jobs) < 2 → MessageBox-Fehler
7. Bestätigungs-Dialog mit Auflistung der zwei gewählten Jobs
8. Erst dann subprocess.Popen(bardo-duplex-merge, ...)
```

DAU-Sicherheit: keine Schreibvorgänge ausserhalb `~/Akten-Scans/<name>/`,
keine Datei-Lösch-Ops, keine sudo-Calls. Worst Case bei Fehlbedienung: ein
zusätzlicher leerer Ordner ohne Konsequenzen.

### Code-Methoden in `BardoScanApp`

| Methode | Zweck |
|---|---|
| `start_duplex_merge()` | Knopf-Handler, Validierung, Dialog, Thread-Start |
| `_run_duplex_merge(front_dir, back_dir, aktenname)` | Subprocess-Aufruf mit Stream-Logging in zweites Status-Fenster |
| `duplex_log(msg)` | Logging in das Duplex-Status-Widget (analog `log()` für Scan) |
| `open_duplex_output(event)` | xdg-open auf die durchsuchbare Duplex-PDF |

State-Variablen: `self.duplex_running` (bool, lock), `self._duplex_last_output`
(Path zum letzten erzeugten -duplex-Ordner für Klick-Open).

---

## Externe Abhängigkeiten

Alles System-Pakete, kein pip-Dependency-Management nötig:

| Tool | Paket (Ubuntu) | Verwendung |
|---|---|---|
| `python3` + `tkinter` | python3, python3-tk | GUI-Framework |
| `scanimage` | sane-utils | Scan-Trigger via brscan5-Backend |
| `brscan5` | manuell von Brother | SANE-Backend für ADS-4900W |
| `img2pdf` | img2pdf | JPEGs → Multi-Page-PDF |
| `ocrmypdf` | ocrmypdf | OCR + PDF/A-Konformierung |
| `tesseract-ocr-<lang>` | tesseract-ocr-deu, -eng, -lat, etc. | Sprachmodelle. Beim Programm-Start ruft `list_tesseract_langs()` `tesseract --list-langs` auf und füllt damit das OCR-Sprache-Dropdown. `osd`/`equ` werden als Pseudo-Sprachen rausgefiltert. Wenn `deu` und `eng` beide installiert sind, erscheint `deu+eng` zusätzlich an Spitze. |
| `pdfseparate` | poppler-utils | PDF nach Seiten splitten |
| `pdftotext` | poppler-utils | Text aus PDF extrahieren |
| `xdg-open` | xdg-utils | Datei-Manager / PDF-Reader öffnen |

---

## Env-Strip — Bardo-Kontamination umgehen

Claude Code wird typischerweise in der textgenwebui-Conda-Env gestartet (Bardo-Stack).
Diese Env setzt `LD_LIBRARY_PATH` auf eigene Libraries (libcurl etc.), die mit
System-Tools wie tesseract / scanimage kollidieren — Symptom: Warnings wie
„no version information available (required by ...)" oder direkter Crash.

Das Skript hat eine `clean_env()`-Funktion die `LD_LIBRARY_PATH`, `CONDA_PREFIX`,
`PYTHONHOME` aus dem Subprocess-Environment entfernt. Jeder `subprocess.run()` /
`subprocess.Popen()` wird mit `env=clean_env()` gestartet.

```python
def clean_env():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    env.pop("CONDA_PREFIX", None)
    env.pop("PYTHONHOME", None)
    return env
```

System-Tools sehen damit nur die System-Libs unter `/usr/lib/...` — die Env-
Aktivierung gilt nur für Bardo-Code, nicht für Drucker/Scanner/OCR.

---

## brscan5-Quirks

### Option-Inactivity
Brother brscan5 markiert manche Optionen als `[inactive]` je nach
Mode/Source/Format-Kombination. Wird so eine Option per `--SkipBlankPage=yes` aktiv
gesetzt, bricht `scanimage` mit `attempted to set inactive option` ab — KEIN Scan.

Lösung: `probe_active_options(device)` ruft `scanimage --help` auf, parst alle
Optionen, filtert die mit `[inactive]` raus. Im Scan-Befehl werden nur die als
aktiv erkannten Optionen mitgegeben. Inaktive werden als Hinweis im Status geloggt
und übersprungen.

### Device-Path-Wechsel nach Power-Cycle
Der Device-String `brother5:bus2;dev3` ist USB-Bus-/Device-spezifisch und kann sich
nach Reboot oder Wieder-Anschluss ändern. `detect_scanner()` ruft beim GUI-Start
`scanimage -L` auf und sucht nach `brother5:...ADS-4900W` — aktualisiert sich also
bei jedem Programm-Start.

### Source-String exakt
Der `--source`-Wert ist case-sensitive und whitespace-sensitive. Der String für
Duplex ist exakt `"Automatic Document Feeder(center aligned,Duplex)"` — kein
Leerzeichen vor `,Duplex`, kein anderes Casing. Brother spec.

---

## Output-Format-Entscheidungen

### JPEG vs. TIFF beim Scan

JPEG verlustbehaftet, aber: 300 dpi True Gray JPEG bei guter Qualität ist visuell
nicht von TIFF unterscheidbar. Vorteil JPEG: ~3-5x kleinere Dateien, schneller IO,
direkter img2pdf-Konsum ohne Konvertierung. Für Akten-Volumen ist das relevant.

### PDF/A-2B als Searchable-Format

`ocrmypdf --output-type pdfa` erzwingt PDF/A-2B — ISO-19005-konform, deutscher
Archiv-Standard. Höhere Beweisfähigkeit als reguläres PDF, da PDF/A keine externen
Abhängigkeiten (Fonts werden eingebettet, keine Active-Content erlaubt).

### Manifest mit relativen Pfaden

Im `sha256.txt` stehen die Pfade relativ zum Job-Ordner (`pdf/page0001.pdf` statt
absolut). Vorteil: der Job-Ordner ist als Ganzes verschiebbar (auf externes
Laufwerk, in Backup, etc.), `sha256sum -c sha256.txt` funktioniert weiterhin.

---

## Erweiterungs-Punkte

### Zweiten Scanner einbinden (z.B. MFC-L5700DN als Fallback)

In `detect_scanner()` die Suche erweitern:
```python
for line in result.stdout.splitlines():
    m = re.search(r"`(brother(?:4|5):bus\d+;dev\d+)'.*ADS-4900W", line)
    if m: return m.group(1)
    m = re.search(r"`(brother4:bus\d+;dev\d+)'.*MFC-L5700DN", line)
    if m: return m.group(1)
```

Source-String muss dann pro Modell unterschiedlich sein — MFC-L5700DN nutzt andere
Source-Bezeichnungen ("FlatBed", "ADF" ohne Brother-Suffix).

### VLM-Stage einhängen (Iter-2)

Nach `_run_ocr_pipeline` einen optionalen `_run_vlm_pass(out_dir)` aufrufen, der
für jede `pdf/page*.pdf` einen Qwen3.6-VL-Call macht (über lokalen
textgenwebui-Endpoint), das Ergebnis als `txt/page*.vlm.json` speichert (mit
korrigiertem Text, Konfidenz, extrahierten Feldern). Original-TXT bleibt — VLM
ergänzt, ersetzt nicht.

Empfohlene Architektur: Watcher-Daemon getrennt vom GUI-Programm. GUI scant
schnell, Watcher arbeitet asynchron im Hintergrund (auf Workstation, GPU).

### RFC-3161-Timestamp-Service

Nach `_write_manifest` ein optionales `_request_timestamp()` das den Hash des
Manifests an FreeTSA o.ä. schickt und das Resultat als `sha256.txt.tsr` speichert.
Komplett add-on, ändert nichts am Bestand.

### Scan-Profile-Presets

Aktuell muss der Nutzer Auflösung/Modus/etc. pro Job einstellen. Erweiterung:
Dropdown „Profil" mit gespeicherten Presets (Akten-Standard, Foto-Hochauflösung,
Schwarzweiß-Mini, etc.) — gespeichert in `~/.config/bardo-scan/presets.json`.

---

## GUI-Struktur

```
BardoScanApp(root)
├── _build_ui()
│   ├── header (Label)
│   ├── device_label (rote/grüne Status-Anzeige)
│   ├── physical_hint (kontextueller Stapel-Hinweis)
│   ├── form (LabelFrame)
│   │   ├── Scanner (Combobox, Multi-Model)
│   │   ├── Aktenordner-Name (Entry)
│   │   ├── Auflösung (Combobox, dynamisch)
│   │   ├── Modus (Combobox, dynamisch)
│   │   ├── Quelle (Combobox, dynamisch)
│   │   ├── OCR-Sprache (Combobox, dynamisch via tesseract --list-langs)
│   │   └── opts (Frame mit Auto-Features-Checkbuttons + OCR-Toggle)
│   ├── scan_btn (Button, groß, grün)
│   ├── status_frame (LabelFrame mit ScrolledText)
│   ├── output_label (klickbarer Link)
│   └── duplex_frame (LabelFrame Duplex-Emulation)
│       ├── Aktenordner-Name (Entry, autoprefilled)
│       ├── Stapel-Orientierung (Combobox, Mode A-D mit DAU-Labels)
│       ├── duplex_btn (Button, groß, blau)
│       ├── duplex_status (ScrolledText)
│       └── duplex_output_label (klickbarer Link)
│
├── _detect_initial() — beim Start, Scanner-Discovery
├── _on_device_change() — Combobox-Reaktion, Capabilities neu laden
├── _update_physical_hint() — Hardware-Hinweis je nach Source
├── _update_feature_availability() — Auto-Feature-Checkboxen ein/aus
├── start_scan() — Knopf-Handler, Validierung, Thread-Start
├── _run_scan(cmd, out_dir) — Thread, Subprocess-Polling, scanimage
├── _run_ocr_pipeline(out_dir, pages) — die 5 Stufen, OCR mit
│                                       Live-Progress-Stream
├── _write_manifest(out_dir) — SHA256-Hashing
├── start_duplex_merge() — Knopf-Handler Duplex
├── _run_duplex_merge(front, back, name, mode) — Thread, Subprocess
├── log(msg), duplex_log(msg) — Status-Output je Sektion
└── open_output(event), open_duplex_output(event) — xdg-open
```

---

## Bekannte Limitierungen

- **Keine Pause/Cancel während Scan** — wenn der ADF-Stapel falsch ist, hilft nur
  Scanner physisch ausschalten. Im Skript-Status gibt's keinen Cancel-Button.
- **OCR-Timeout 1800s** für Pipeline-Lauf — bei sehr großen Stapeln (200+ Seiten
  mit langsamer CPU) kann das eng werden. Konstante in `_run_ocr_pipeline`,
  Variable `timeout=1800`.
- **Kein Retry bei Scan-Fehler** — wenn `scanimage` mittendrin abbricht, bleibt
  der Job-Ordner mit Teil-JPEGs zurück. Manuell aufzuräumen oder erneuter
  Lauf in einen neuen Timestamp-Ordner.
- **Tkinter-GUI ist plattform-unabhängig aber spartanisch** — gut genug, kein
  schöner Theme. Wenn UI-Aufwertung gewünscht: Migration zu PyGObject (Gtk) oder
  PyQt — aber dann gewinnt man Komplexität ohne fundamentalen UX-Vorteil.

---

## Test-Patterns

### Smoke-Test (kein Scan, nur Logik):
```bash
env -u LD_LIBRARY_PATH python3 -c "
import importlib.machinery, importlib.util
loader = importlib.machinery.SourceFileLoader('bs', '$HOME/.local/bin/bardo-scan')
spec = importlib.util.spec_from_loader('bs', loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
print('Scanner:', m.detect_scanner())
print('Active opts:', sorted(m.probe_active_options(m.detect_scanner())))
"
```

### Syntax-Check:
```bash
env -u LD_LIBRARY_PATH python3 -m py_compile "$HOME/.local/bin/bardo-scan"
```

### Live-Test mit minimalem Output:
GUI starten, Aktenordner-Name "test" eingeben, 1 Blatt in ADF, scannen → prüfen
ob alle 5 Pipeline-Stufen sauber durchlaufen.

---

## Konfiguration via Umgebungs-Variablen

| ENV | Default | Wirkung |
|---|---|---|
| `BARDO_SCAN_BASE` | `~/Akten-Scans` | Zielverzeichnis für alle Scan-Outputs. Beide Skripte (`bardo-scan` + `bardo-duplex-merge`) lesen die gleiche Variable, sodass externes Laufwerk konsistent eingebunden wird. Beispiel: `BARDO_SCAN_BASE=/mnt/akten-extern bardo-scan`. Persistent über `/etc/environment` oder `~/.profile`. |

Power-User-Hebel — DAU-Default unverändert.

---

## Lizenz / Status

Code wiederverwendbar — keine hardcoded Pfade außer den Standard
`~/.local/...`-Pfaden (von `install.sh` als Symlinks gesetzt). Output-Basis
ist via `BARDO_SCAN_BASE` konfigurierbar.

Lizenz: **Dual MIT OR Apache-2.0** (siehe `LICENSE`, `LICENSE-MIT`,
`LICENSE-APACHE` im Repo-Root).

Teil von [Bardo-AI](https://github.com/Bardo-AI).
