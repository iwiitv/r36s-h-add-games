# R36S-H: eigene Spiele hinzufügen (ohne die Karte zu formatieren)

🇬🇧 [English guide](README.md)

Du hast einen **R36S**-Handheld gekauft, steckst die SD-Karte in den PC und Windows sagt:

> *„Sie müssen den Datenträger in Laufwerk X: formatieren, bevor Sie ihn verwenden können.“*

**Nicht formatieren!** Auf der Karte liegen das System und alle Spiele. Windows versteht
nur den Aufbau der Karte nicht. Hier steht, wie du trotzdem eigene Spiele draufbekommst.

---

## Ist die Anleitung für mein Gerät?

Für R36S-Nachbauten mit der Hersteller-Firmware **„R36S-H OS“**. Den Namen findest du
in den Einstellungen bzw. der Info-Seite des Geräts.

Läuft auf deinem Gerät **ArkOS / dArkOS**, oder zeigt Windows Partitionen namens `BOOT` und
`EASYROMS`, hast du ein anderes Modell. Dann helfen die üblichen ArkOS-Anleitungen.

Getestet mit: Platine `R36S-V3.0 (2026.07.20)`, Firmware `R36S-H OS V1.2`.

## Was mit der mitgelieferten Karte nicht stimmt

1. **Die Partitionstabelle fehlt.** Auf der Karte ist ein ganz normales FAT32 mit dem System
   und allen Spielen, aber im allerersten Sektor (wo die Partitionstabelle hingehört) steht
   etwas anderes. Windows findet das Dateisystem nicht und bietet das Formatieren an.
   **Formatierst du, startet das Gerät nicht mehr.**
2. **Die Karte ist gefälscht bzw. minderwertig.** Die getestete Karte war als „128 GB“ verkauft,
   hat aber nur **29,3 GB** (genau 30.000 MiB, ein einprogrammierter Wert). Nach wenigen
   Schreibvorgängen hatte sie **defekte Blöcke**, Dateien ließen sich nicht mehr lesen.
3. **Kein anderer Weg zu eigenen Spielen.** Den zweiten Kartenslot nutzt die Firmware nicht für
   Spiele, und per USB-C am PC passiert gar nichts.

Das Skript umgeht Punkt 1: Es zeigt Windows kurz, wo das Dateisystem liegt, kopiert deine
Spiele und stellt danach alles exakt wieder so her, wie es war. Für Punkt 2 kann es die ganze
Karte auf eine neue, gute Karte kopieren (Schritt 3).

---

## Der einfache Weg: Claude Code macht es für dich

Keine Lust auf PowerShell-Befehle? Wenn du [Claude Code](https://claude.com/claude-code) nutzt,
kann es alle Schritte unten für dich erledigen. Im Repo liegt eine [`CLAUDE.md`](CLAUDE.md),
in der steht, wie Claude dabei sicher vorgeht (erst Backup, nie formatieren, Datenträger
immer mit dir abklären).

1. Repo herunterladen (grüner Knopf **Code** → **Download ZIP**) und entpacken, z. B. nach `C:\R36S`
2. Ein Terminal **als Administrator** öffnen (nötig für den direkten Kartenzugriff), dann:
   ```
   cd C:\R36S
   claude
   ```
3. Claude sagen, was du willst, z. B.:
   *„Pack die Spiele aus C:\Spiele auf meinen R36S.“*

Claude bittet dich, die Karte einzustecken, klärt mit dir die Datenträgernummer, macht das
Backup und fügt deine Spiele hinzu. Nur das Umstecken der Karte zwischen Gerät und
Kartenleser musst du selbst machen.

---

## Was du brauchst

- Einen PC mit Windows 10/11
- Einen **USB-Kartenleser** für microSD-Karten
- Etwa **32 GB freien Platz** auf dem PC (für das Backup)
- Deine Spiele als Dateien (`.gb`, `.gbc`, `.gba`, `.nes`, `.sfc`/`.smc`, `.md` … oder `.zip`)
- Optional, aber empfohlen: eine **neue, gute microSD-Karte mit mindestens 32 GB**
  (SanDisk oder Samsung), siehe Schritt 3

## Schritt 1: Skript herunterladen

Oben auf den grünen Knopf **Code** → **Download ZIP**, dann entpacken, z. B. nach `C:\R36S`.

## Schritt 2: PowerShell als Administrator öffnen

1. Windows-Taste drücken, **PowerShell** tippen
2. Rechtsklick → **Als Administrator ausführen**
3. In den Ordner wechseln und das Skript für dieses Fenster erlauben:

```powershell
cd C:\R36S
Set-ExecutionPolicy -Scope Process Bypass
```

## Schritt 3: Backup der Karte (wichtig!)

R36S **ausschalten**, SD-Karte aus Slot 1 („TF1“) nehmen und in den Kartenleser stecken.
Will Windows formatieren: **Abbrechen** klicken.

Datenträgernummer der Karte herausfinden:

```powershell
.\r36s-h-tool.ps1 -Action List
```

Ausgabe zum Beispiel:

```
Disk 4: Mass Storage Device      29,30 GB   R36S-H card (hidden FAT32 at sector 63)
```

Backup machen (`4` durch deine Nummer ersetzen):

```powershell
.\r36s-h-tool.ps1 -Action Backup -DiskNumber 4 -ImagePath C:\R36S\backup.img
```

Dauert mit einem normalen Kartenleser etwa 25 Minuten. Am Ende wird das Backup geprüft.

### Empfohlen: auf eine neue Karte umziehen

Die mitgelieferten Karten sind oft schlecht. Die getestete „128-GB“-Karte hatte in Wahrheit
nur 29 GB und nach wenigen Schreibvorgängen **defekte Blöcke**. Hast du eine neue Karte
(**mindestens 32 GB**), spiel das Backup darauf und nimm ab jetzt die neue:

```powershell
.\r36s-h-tool.ps1 -Action List                 # Nummer der NEUEN Karte suchen
.\r36s-h-tool.ps1 -Action Clone -DiskNumber 5 -ImagePath C:\R36S\backup.img
```

Mit `YES` bestätigen. Nach dem Schreiben wird die neue Karte geprüft. Dann in Slot 1 stecken
und testen. Die alte Karte als Reserve aufheben.

### Nur eine kleinere Karte da (z. B. 16 GB)? *(experimentell)*

Die Original-Karte hat ~30 GB, größtenteils Spiele, die man nie spielt (tausende MAME-/Arcade-
und PlayStation-Spiele). `CloneSmall` kopiert das **System** und nur die **Spiele, die du willst**
auf eine kleinere Karte. Braucht [Python 3](https://www.python.org/downloads/).

```powershell
.\r36s-h-tool.ps1 -Action CloneSmall -DiskNumber 5 -ImagePath C:\R36S\backup.img -Games "zelda","kirby","super mario world"
```

- `-Games` sind Wörter, die im Dateinamen oder Menütitel des Spiels vorkommen. Alle passenden
  Spiele (alle Regionen/Versionen) werden kopiert. Systeme ohne Treffer behalten ein kleines Spiel,
  damit ihre Liste im Menü nie leer ist.
- System + die Spiele oben brauchen nur etwa **1,2 GB**. Eigene Spiele danach mit `-Action Add` hinzufügen.
- Bei mir mit einer 16-GB-Karte erfolgreich. Das System Datei für Datei zu kopieren ist heikel
  (kleingeschriebene Dateinamen müssen klein bleiben, sonst hängt das Gerät am Logo – das Skript
  achtet darauf). Die Original-Karte aufheben, bis die neue läuft.

## Schritt 4: Spiele hinzufügen

Auf der Karte gibt es einen Ordner pro System. Diese Namen bei `-System` angeben:

| Ordner | System |
|---|---|
| `GB` | Game Boy |
| `GBC` | Game Boy Color |
| `GBA` | Game Boy Advance |
| `FC` | NES / Famicom |
| `SFC` | SNES / Super Famicom |
| `MD` | Mega Drive / Genesis |
| `PCE` | PC Engine |
| `SMS` | Master System |
| `GG` | Game Gear |
| `PS` | PlayStation (`.img`/`.iso`) |

Ein Spiel hinzufügen:

```powershell
.\r36s-h-tool.ps1 -Action Add -DiskNumber 4 -ImagePath C:\R36S\backup.img -System GBA -Rom "C:\Spiele\Mein Spiel.gba"
```

Mehrere Spiele, mit schöneren Namen im Menü:

```powershell
.\r36s-h-tool.ps1 -Action Add -DiskNumber 4 -ImagePath C:\R36S\backup.img -System GB `
    -Rom "C:\Spiele\spiel1.gb","C:\Spiele\spiel2.gb" -Name "Spiel Eins","Spiel Zwei"
```

Steht da **„Done. The card can be removed.“**, Karte zurück ins Gerät. Die Spiele
stehen am **Ende** der Liste des jeweiligen Systems.

`-ImagePath` gehört jedes Mal dazu. Das Skript prüft vor dem Schreiben, ob die Karte zu
deinem Backup passt.

## Spiel entfernen

```powershell
.\r36s-h-tool.ps1 -Action Remove -DiskNumber 4 -ImagePath C:\R36S\backup.img -System GBA -Name "Mein Spiel"
```

---

## Tipps & Probleme

- **Gerät immer ganz ausschalten**, bevor du eine Karte herausnimmst.
- **Game-Boy-Spiel winzig in einem großen bunten Rahmen?** Das ist der *Super-Game-Boy*-Rahmen
  (z. B. Pokémon Rot/Blau). Spiel nochmal mit `-RemoveSgbBorder` hinzufügen. Dann wird in der
  Kopie auf der Karte das Super-Game-Boy-Kennzeichen abgeschaltet (2 Bytes, deine Datei auf dem
  PC bleibt unverändert):
  ```powershell
  .\r36s-h-tool.ps1 -Action Add -DiskNumber 4 -ImagePath C:\R36S\backup.img -System GB -Rom "C:\Spiele\Pokemon Blau.gb" -RemoveSgbBorder
  ```
- **USB-C-Anschluss und zweiter Kartenslot** helfen hier nicht. Die Firmware nutzt sie nicht für Spiele.
- **ArkOS / dArkOS laufen nicht** auf diesem Modell. Es hat einen anderen Chip (Hichip statt Rockchip).
- **Spielstände** liegen beim getesteten Gerät nicht auf der Karte. Ersetzt du ein Spiel durch
  eine Datei mit gleichem Namen, bleibt dein Fortschritt erhalten.
- **Etwas schiefgegangen?** Backup mit `-Action Clone` zurück auf die Karte schreiben (bei der
  Original-Karte mit `-Force`). Dann ist alles exakt wie vorher.

## Linux

Kein Skript nötig, das Dateisystem lässt sich direkt einbinden (Sektor 63 × 512 = `32256`
bei der getesteten Karte). Befehle siehe [englische Anleitung](README.md#linux).

## Rechtliches

Nur Spiele verwenden, die du besitzt. Hier gibt es keine Spiele und keine Links dazu.

## Haftungsausschluss

Keine Gewähr. Das Skript lehnt Systemlaufwerke ab und prüft die Karte gegen dein Backup.
Trotzdem: **immer Backup machen und die Datenträgernummer doppelt prüfen.**
