# Bardo Akten-Scan

**Software OCR Texterkennung — Duplex Scanner mit Verifikation für
Fälschungssicherheit.**

Auf einfachen Multifunktionsdruckern wird teure Profi-Scanner-Hardware
(Hardware-Duplex + eingebautes OCR) softwareseitig nachgebaut. Hardware-
Duplex und Hardware-OCR werden genutzt wo vorhanden.

Output landet auf der lokalen Festplatte — keine Cloud-Verbindung, kein
Telemetrie-Traffic.

Pro Scan-Auftrag entstehen:

- die unveränderte Bild-PDF (Original-Aufnahme, eingefroren)
- eine zweite PDF-Version mit OCR-Layer, durchsuchbar
- jede Seite einzeln als PDF und als reiner Text
- ein SHA256-Hash-Manifest, manipulationssicher prüfbar

## Verifiziert getestet

- **Brother ADS-4900W** — Hardware-Duplex über brscan5 oder eSCL/ipp-usb
- **Brother MFC-L5700DN** — Single-Sided ADF + Flachbett, mit Software-Duplex

Andere SANE-unterstützte ADF-Scanner (Brother DCP-/MFC-/ADS-Reihen, weitere
Hersteller über `airscan`/`escl`) funktionieren grundsätzlich.

## Installation

```bash
git clone https://github.com/Bardo-AI/bardo-akten-scan.git
cd bardo-akten-scan
./install.sh
```

`install.sh` prüft die Dependencies und installiert die Programme nach
`~/.local/`. Kein Root nötig. Deinstallation: `./install.sh --uninstall`.

## Lizenz

**MIT OR Apache-2.0** — `SPDX-License-Identifier: MIT OR Apache-2.0`.

Volltexte in [`LICENSE-MIT`](LICENSE-MIT) und [`LICENSE-APACHE`](LICENSE-APACHE).

---

[Bardo-AI](https://github.com/Bardo-AI)
