# R36S-H: add your own games (without formatting the card)

🇩🇪 [Deutsche Anleitung](README.de.md)

You bought an **R36S** handheld, put its SD card into your PC and Windows says:

> *"You need to format the disk in drive X: before you can use it."*

**Don't format it!** The card holds the system and all games. Windows just doesn't
understand how the card is laid out. This guide shows you how to add your own games anyway.

---

## Is this guide for my device?

This guide is for R36S clones running the stock firmware **"R36S-H OS"**.
You can find the name in the device's settings / about screen.

If your device runs **ArkOS / dArkOS** instead, or Windows shows partitions named `BOOT` and
`EASYROMS`, you have a different model. Use the usual ArkOS guides for that one.

Tested on: board `R36S-V3.0 (2026.07.20)`, firmware `R36S-H OS V1.2`.

## What's wrong with the card that comes with the device

1. **The partition table is missing.** The card contains a perfectly normal FAT32 file system
   with the system and all games, but the very first sector of the card (where the partition
   table belongs) holds something else. Windows doesn't find the file system and offers to
   format the card. **If you format it, the device won't start anymore.**
2. **The card is fake / of poor quality.** The tested card was sold as "128 GB" but actually
   has only **29.3 GB** (exactly 30,000 MiB, a programmed value). After a few writes it showed
   **defective blocks** and files could no longer be read back.
3. **No other way to get games onto the device.** The stock firmware does not use the second
   card slot for games, and connecting the device via USB-C to a PC does nothing.

The script in this repo works around #1: it points Windows to the file system for a moment,
copies your games and then puts everything back exactly as it was. For #2 it can copy your
whole card onto a new, good card (step 3).

---

## The easy way: let Claude Code do it

Don't want to type PowerShell commands? If you use [Claude Code](https://claude.com/claude-code),
it can do all the steps below for you. This repo contains a [`CLAUDE.md`](CLAUDE.md) that
tells Claude exactly how to do it safely (backup first, never format, always confirm the disk).

1. Download this repo (green **Code** button → **Download ZIP**) and extract it, e.g. to `C:\R36S`
2. Open a terminal **as administrator** (needed for direct card access), then:
   ```
   cd C:\R36S
   claude
   ```
3. Tell Claude what you want, e.g.:
   *"Put the games from C:\Games on my R36S."*

Claude will ask you to insert the card, confirm the disk number with you, make the backup
and add your games. You still have to swap the card between device and card reader yourself.

---

## What you need

- A Windows 10/11 PC
- A **USB card reader** for microSD cards
- About **32 GB free space** on your PC (for the backup)
- Your games as files (`.gb`, `.gbc`, `.gba`, `.nes`, `.sfc`/`.smc`, `.md`, … or `.zip`)
- Optional, but recommended: a **new good microSD card with 32 GB or more**
  (SanDisk or Samsung), see step 3

## Step 1: Download the script

Click the green **Code** button → **Download ZIP**, then extract it, e.g. to `C:\R36S`.

## Step 2: Open PowerShell as Administrator

1. Press the Windows key, type **PowerShell**
2. Right-click → **Run as administrator**
3. Go to the folder and allow the script for this window:

```powershell
cd C:\R36S
Set-ExecutionPolicy -Scope Process Bypass
```

## Step 3: Back up the card (important!)

Switch the R36S **off**, take out the SD card (slot 1 / "TF1") and put it into the card reader.
If Windows asks you to format it: click **Cancel**.

Find the disk number of the card:

```powershell
.\r36s-h-tool.ps1 -Action List
```

You'll see something like:

```
Disk 4: Mass Storage Device      29,30 GB   R36S-H card (hidden FAT32 at sector 63)
```

Now make the backup (replace `4` with your disk number):

```powershell
.\r36s-h-tool.ps1 -Action Backup -DiskNumber 4 -ImagePath C:\R36S\backup.img
```

This takes about 25 minutes with a normal card reader. The backup is checked at the end.

### Recommended: move to a new card

The cards that come with these devices are often bad. The tested "128 GB" card really had
only 29 GB and showed **defective blocks** after a few writes. If you have a new card
(**at least 32 GB**), copy your backup onto it and use the new card from now on:

```powershell
.\r36s-h-tool.ps1 -Action List                 # find the disk number of the NEW card
.\r36s-h-tool.ps1 -Action Clone -DiskNumber 5 -ImagePath C:\R36S\backup.img
```

Type `YES` to confirm. The new card is checked after writing. Then put it into slot 1 of the
device and test it. Keep the old card as a spare.

## Step 4: Add your games

The card has one folder per system. Use these names for `-System`:

| Folder | System |
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

Add one game:

```powershell
.\r36s-h-tool.ps1 -Action Add -DiskNumber 4 -ImagePath C:\R36S\backup.img -System GBA -Rom "C:\Games\My Game.gba"
```

Add several games, with nicer names in the menu:

```powershell
.\r36s-h-tool.ps1 -Action Add -DiskNumber 4 -ImagePath C:\R36S\backup.img -System GB `
    -Rom "C:\Games\game1.gb","C:\Games\game2.gb" -Name "Game One","Game Two"
```

When it says **"Done. The card can be removed."**, put the card back into the device.
Your games appear at the **end** of the list for that system.

`-ImagePath` is needed every time. The script checks that the card belongs to your backup
before it writes anything.

## Remove a game

```powershell
.\r36s-h-tool.ps1 -Action Remove -DiskNumber 4 -ImagePath C:\R36S\backup.img -System GBA -Name "My Game"
```

---

## Tips & problems

- **Always switch the device off completely** before you take a card out.
- **Game Boy game shown tiny inside a big colorful frame?** That's the *Super Game Boy*
  border (games like Pokémon Red/Blue). Add the game again with `-RemoveSgbBorder`; the
  script then switches off the Super Game Boy flag in the copy on the card (2 bytes, your file
  on the PC stays unchanged):
  ```powershell
  .\r36s-h-tool.ps1 -Action Add -DiskNumber 4 -ImagePath C:\R36S\backup.img -System GB -Rom "C:\Games\Pokemon Blue.gb" -RemoveSgbBorder
  ```
- **The USB-C port and the second card slot** don't help here. The stock firmware doesn't
  use them for games.
- **ArkOS / dArkOS do not run** on this model. It has a different chip (Hichip instead of Rockchip).
- **Save games** are not stored on the card on the tested device, so replacing a game file
  with the same name keeps your progress.
- **Something went wrong?** Write your backup back onto the card with `-Action Clone`
  (use `-Force` if it is the original card). Everything will be exactly as before.

## Linux

No script needed. Mount the file system at its offset (sector 63 × 512 = `32256` on the tested card):

```bash
sudo dd if=/dev/sdX of=backup.img bs=4M status=progress        # backup first
sudo mount -o offset=32256,uid=$(id -u) /dev/sdX /mnt
# copy "<Name>.zip" (one ROM inside) into the system folder and add a line
# "<Name>.zip,<Name>,<Name>" to FILELIST.CSV (UTF-8 with BOM, CRLF line endings)
sudo umount /mnt
```

## How the card works (for the curious)

- Sector 0 has no partition table; the FAT32 file system starts at sector 63.
- Each system folder contains `Name.zip` (exactly one ROM inside), `FILELIST.CSV` (the menu:
  `Name.zip,English name,Chinese name`, UTF-8 with BOM, CRLF) and `IMAGES\Name.png` (320×240 preview).
- The system itself (Linux) also lives on this file system (`cubegm`, `rootfs`). Copying it
  file by file needs care: lowercase file names must stay lowercase (FAT "NT case" flag),
  otherwise the device hangs at the logo. `-Action Clone` copies the whole card 1:1 and avoids this.

## Legal

Only use games you own. This repository contains no games and no links to games.

## Disclaimer

No warranty. The script refuses system disks and checks the card against your backup, but
**always make the backup and double-check the disk number**.
