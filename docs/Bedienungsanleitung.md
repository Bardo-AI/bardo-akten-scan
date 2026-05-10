# Bardo Akten-Scan — Bedienungsanleitung

Dokumentiert: 2026-05-08 · Hardware: Brother ADS-4900W · Software: bardo-scan

---

## Was das ist

Ein Werkzeug zum schnellen Digitalisieren von Akten-Stapeln. Du legst Papier in den
Scanner, drückst einen Knopf, am Ende hast du:

- Beweis-PDF (Original-Bilder, unverändert)
- Durchsuchbare PDF (mit OCR-Text drunter, in Deutsch)
- Einzelne Seiten als PDF (jede mit OCR-Layer)
- Einzelne Seiten als Text-Datei (für Maschinen-Verarbeitung, Suche)
- Hash-Manifest (juristische Beweisbarkeit der Unverändertheit)

---

## Hardware-Voraussetzung

- **Brother ADS-4900W** ist per USB **oder** LAN angeschlossen und eingeschaltet
- Auffang-Tray ausgezogen (sonst fliegen die Blätter auf den Boden)
- ADF-Eingabefach mit Papier gefüllt — bis zu 100 Blatt pro Stapel

---

## Programm starten

**Variante 1 — Anwendungsmenü:**
„Bardo Akten-Scan" suchen oder unter Office/Grafik finden, anklicken.

**Variante 2 — Terminal:**
```
bardo-scan
```

Beim Start sucht das Programm den Scanner automatisch. Oben im Fenster steht entweder
„Scanner gefunden: brother5:bus2;dev3" (grün) oder „NICHT gefunden" (rot). Wenn rot:
Stromkabel + USB/LAN prüfen, Programm neu starten.

---

## Ein Stapel scannen

1. **Aktenordner-Name** eintragen (z.B. `Projekt_2024_Quartalsabschluss` oder
   `Steuerunterlagen_2023`). Tipp: nimm den Namen **wie er auf dem
   physischen Aktenordner steht** — keine Umbenennung nötig, das System legt ihn
   genau so an.

2. **Optionen** prüfen — die Defaults passen für deutsche Druck-Akten:
   - Auflösung 300 dpi
   - Modus: True Gray (Graustufen, beste OCR-Qualität bei kleiner Datei)
   - Duplex (beidseitig) ✓
   - **OCR-Sprache** — Default `deu`. Wenn englische Anhänge oder Mischtexte
     dabei sind, `deu+eng` wählen (nur sichtbar wenn beide Sprachpakete
     installiert sind). Weitere Sprachen via
     `sudo apt install tesseract-ocr-eng tesseract-ocr-lat ...` und Programm
     neu starten — die Combobox liest die installierten Pakete beim Start.
   - Auto-Document-Size ✓
   - Auto-Deskew (gerade rücken) ✓
   - Multifeed-Detection (warnt bei Doppeleinzug) ✓
   - Leere Seite überspringen — kann je nach Mode inaktiv sein, wird automatisch
     übersprungen falls Brother das gerade nicht zulässt
   - **OCR direkt: durchsuchbares PDF/A** ✓ (sonst entstehen nur die Roh-Bilder)

3. **Stapel in den ADF legen**, Auffang-Tray prüfen.

4. **Großen grünen Knopf „SCAN STARTEN"** drücken. Bestätigungsdialog erscheint —
   nochmal kurz prüfen, dann „Ja".

5. **Warten:**
   - Scan-Phase: ca. 1 Sek pro Blatt Duplex (110 Seiten = 1 Minute)
   - OCR-Phase: 2-4 Minuten je nach Stapelgröße (läuft 4-fach parallel auf der CPU)

6. **Fertig.** Unten erscheint ein klickbarer Pfad-Link → öffnet die durchsuchbare PDF
   direkt. Status-Fenster zeigt das Protokoll des Laufs.

---

## Wo die Dateien landen

```
~/Akten-Scans/
└── <dein-Aktenordner-Name>/
    └── <YYYYMMDD-HHMMSS>/                    ← einer pro Scan-Job
        │
        ├── 20260508-215832.pdf                ← BEWEIS (unverändert)
        ├── 20260508-215832.searchable.pdf     ← Bulk-PDF mit OCR
        ├── sha256.txt                         ← Hash-Manifest
        │
        ├── pdf/
        │   ├── page0001.pdf                   ← jede Seite einzeln
        │   ├── page0002.pdf                   ← mit OCR-Layer drin
        │   └── ...
        │
        └── txt/
            ├── page0001.txt                   ← reiner Text pro Seite
            ├── page0002.txt
            └── ...
```

**Wenn du mehrfach denselben Aktenordner scannst** (50 Blatt rein, dann nochmal 50,
weil ADF nicht alles auf einmal aufnimmt): jeder Scan-Job kriegt einen eigenen
Timestamp-Unterordner. Nichts wird überschrieben, nichts verloren.

---

## Konsumenten der Output-Dateien

| Wer | Was sie nutzen |
|---|---|
| Du selbst | `<timestamp>.searchable.pdf` — Bulk lesen, suchen mit Strg+F in Okular |
| Anwalt | `<timestamp>.searchable.pdf` — komplette Akte am Stück durchblättern |
| Mitarbeiter / Berater | `pdf/page*.pdf` — zieht Einzelseiten per Drag-Drop in einen eigenen Ordner |
| KI / Maschine | `txt/page*.txt` — direkter Volltext-Zugriff für Skripte, RAG, grep |
| Beweisführung | `<timestamp>.pdf` (Beweis) + `sha256.txt` (Manifest) |

---

## Beweisbarkeit prüfen

Falls jemand fragt „haben Sie diese Datei nachträglich verändert?" — du kannst es
beweisen. Im Job-Ordner:

```
cd ~/Akten-Scans/<aktenordner>/<timestamp>
sha256sum -c sha256.txt
```

Output: pro Datei `OK` wenn unverändert seit Scan, `FAILED` wenn modifiziert.

---

## Häufige Probleme

**„Scanner NICHT gefunden" (rot oben):**
- USB-Kabel / Strom prüfen
- Manchmal hilft Scanner aus- und wieder einschalten
- Wenn Scanner über LAN: prüfen ob die Fritz!Box ihm eine IP gibt
  (`http://fritz.box` → Heimnetz)

**„Optionen aktuell inaktiv (Brother-Quirk), übersprungen: SkipBlankPage":**
- Normal, kein Fehler. Brother lässt manche Optionen je nach Mode/Source-Combo nicht zu.
  Das Programm überspringt sie automatisch, der Scan läuft trotzdem durch.

**Scan stoppt mit „Document feeder out of documents":**
- Erwartet — heißt einfach „ADF ist leer, Stapel fertig". Steht im Log am Ende jedes
  Laufs. Nichts zu tun.

**OCR-Phase dauert lange:**
- Tesseract läuft mit `cpu_count // 2` parallelen Jobs auf der CPU
  (Laptop mit 8 Kernen → 4 Jobs, Workstation mit 96 Kernen → 48 Jobs).
  ~1-2 Sek pro Seite auf Laptop, deutlich schneller auf Workstation.
- Live-Fortschritt sichtbar im Status-Fenster („Scanning: 30 %", „OCR: 60 %"
  usw.) — bei großen Stapeln nicht mehr minutenlang im Dunkeln.
- Auf Workstation mit GPU später nochmal schneller via VLM-Pass — aber für
  den Alltag reicht Tesseract.

**Datei-Manager zeigt PDFs/TXTs nicht zusammen:**
- Sollen sie auch nicht. PDFs liegen in `pdf/`, Texte in `txt/`. Zwei Datei-Manager-
  Fenster nebeneinander oder Split-View nutzen wenn du beide brauchst.

---

## Speicher-Hinweis

Pro Stapel mit ~110 Seiten landen ca. **130 MB** in `~/Akten-Scans/`. Bei
größeren Mengen entsprechend mehr (etwa 15-30 GB pro 10000 Seiten). Vor
einem Massen-Lauf sicherstellen dass genug Platz auf der Platte ist — oder
externes Laufwerk verwenden (siehe nächster Abschnitt).

---

## Externes Laufwerk verwenden

Wenn `/home` zu klein ist (oder du einen ganzen Aktenberg auf eine externe SSD
auslagern willst), kannst du den Output-Pfad umbiegen via Umgebungs-Variable
`BARDO_SCAN_BASE`. Beide Programme (`bardo-scan` + `bardo-duplex-merge`)
lesen die selbe Variable.

**Einmalig für eine Sitzung:**
```
BARDO_SCAN_BASE=/mnt/akten-extern bardo-scan
```

**Permanent für deinen Account** — Zeile in `~/.profile` einfügen:
```
export BARDO_SCAN_BASE="/mnt/akten-extern"
```
Dann neu einloggen oder `source ~/.profile` ausführen. Beide Skripte
und alle Anwendungen, die danach gestartet werden, nutzen den neuen Pfad.

**System-weit** — als Root in `/etc/environment` (eine Zeile, ohne `export`):
```
BARDO_SCAN_BASE=/mnt/akten-extern
```

Wenn `BARDO_SCAN_BASE` nicht gesetzt ist, bleibt der Default `~/Akten-Scans/` —
keine Verhaltens-Änderung wenn du die Variable nicht setzt.

---

## Zwei Scanner parallel verfügbar

Falls der ADS-4900W mal hängt, ist auch der **MFC-L5700DN-Scanner** über `brscan4`
oder eSCL/ipp-usb verfügbar. Die GUI erkennt mehrere Scanner und lässt dich im
Dropdown auswählen. Pipeline (img2pdf + ocrmypdf + Per-Seite-Splitting) ist
scanner-unabhängig.

---

## Manuell-Duplex für Single-Sided-Scanner (z.B. alter MFC)

Wenn dein Scanner **kein eingebautes Duplex** hat (typisch für ältere
Multifunktionsgeräte wie der MFC-L5700DN), kannst du Duplex manuell emulieren:

### Workflow

1. **Stapel face-up** in den ADF legen, in `bardo-scan` einen Aktenordner-Namen
   vergeben (z.B. `Akte_Vorderseiten`), scannen → Output unter
   `~/Akten-Scans/Akte_Vorderseiten/<timestamp1>/`
2. **Stapel umdrehen** (face-down kippen, Reihenfolge oben-unten bleibt gleich)
   und in den ADF zurücklegen
3. Im `bardo-scan` denselben oder anderen Aktenordner-Namen, scannen → Output
   unter `<timestamp2>/`
4. **Mergen** mit dem Hilfstool:

   ```
   bardo-duplex-merge \
     ~/Akten-Scans/<aktenordner>/<timestamp1> \
     ~/Akten-Scans/<aktenordner>/<timestamp2> \
     <ziel-aktenordner-name>
   ```

   Beispiel:
   ```
   bardo-duplex-merge \
     ~/Akten-Scans/test4/20260508-233652 \
     ~/Akten-Scans/test4/20260508-233846 \
     test4
   ```

### Was passiert beim Merge

- Die zwei Source-Ordner bleiben **unverändert** (immutable Beweis-Material)
- Neuer Ordner `<aktenordner>/<timestamp>-duplex/` mit 2N statt N Seiten in
  korrekter Vorder-Rückseiten-Reihenfolge
- Komplettes bardo-scan-Output-Layout: pdf/, txt/, sha256.txt, _merge_info.json
- Bulk-Searchable-PDF zusammengefügt aus den Per-Seite-PDFs

### Wichtig zur Stapel-Umdreh-Konvention

Diese Pipeline geht **standardmäßig** davon aus dass:
- Erster Scan: Stapel face-up, ADF zieht von oben
- Zweiter Scan: Stapel **face-down umkippen** (Vorder-Hinterseite tauschen),
  oben-unten Reihenfolge **bleibt** wie sie war

Das ist die einfachste Hand-Bewegung: stack hochnehmen, drehen wie man eine
Karte umdreht. **Nicht** den Stapel von Oben nach Unten umsortieren.

### Falsch sortiert? — Dropdown „Stapel-Orientierung"

Wenn das Ergebnis nicht stimmt, **nicht nochmal scannen**. Im Duplex-Sektion
gibt's ein Dropdown mit vier Modi. Probier sie der Reihe nach durch:

| Auswahl | Was sie tut |
|---|---|
| Standard (Karte umdrehen, MFC-L5700DN) | Default — die einfache Hand-Drehung |
| Lange Kante drehen | Wenn der Stapel um die lange Kante gedreht wurde |
| Beide Stapel umgekehrt | Wenn beide Scans rückwärts laufen |
| Gleiche Richtung (Front zuletzt) | Front + Back im selben Lauf-Sinn |

Die Source-Ordner werden bei jedem Versuch unangetastet gelassen. Du kannst
also beliebig oft mergen mit anderen Modi, bis das Ergebnis passt — kein
Datenverlust, nur jeweils ein neuer `*-duplex`-Ordner.

CLI-Variante (für Power-User):
```
bardo-duplex-merge <front> <back> <name> --mode flip-long
```
`--mode {a|b|c|d}` oder Aliases `{flip-short|flip-long|reverse-both|same-direction}`.

## Code-Doku

Die technische Dokumentation des Programms (wie es aufgebaut ist, wie man es ändert,
welche Abhängigkeiten es hat) liegt in der Datei `Code-Dokumentation.md` neben
dieser Anleitung.
