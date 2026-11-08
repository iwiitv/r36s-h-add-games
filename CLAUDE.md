# Instructions for Claude Code: R36S-H game helper

The user owns an R36S clone handheld with the stock firmware "R36S-H OS" and wants to put
their own games on it. Do the technical work for them with `r36s-h-tool.ps1`, explain
simply, and talk to the user in **their** language (e.g. German if they write German).
Assume no technical knowledge.

## Background (short)

- The stock SD card holds a normal FAT32 file system (system + games), but sector 0 has no
  partition table. Windows therefore offers to format the card.
- `r36s-h-tool.ps1` mounts the hidden FAT32 temporarily, changes files and restores sector 0.
- The stock cards are often fake/poor quality (e.g. "128 GB" that really holds ~29 GB, with
  bad blocks). Moving to a good card (≥ 32 GB) with `-Action Clone` is recommended.

## Hard safety rules

1. **Never format, partition, `Clear-Disk` or `diskpart` the original card.** Never tell the
   user to click "Format". Tell them to click **Cancel** if Windows asks.
2. **Before any command that takes `-DiskNumber`, show the user the output of
   `-Action List` and get explicit confirmation of the disk number.** Never guess.
3. **No `Add`/`Remove`/`Clone` without a verified backup.** If there's no backup yet, make one
   first (`-Action Backup`). Ask where to store it (needs ~32 GB free; the user may not want C:).
4. `-Action Clone` overwrites the target card completely. Only use `-Yes` after the user
   explicitly agreed to overwrite **that** disk. Use `-Force` only if the user explicitly wants
   to overwrite a card that already contains an R36S-H system (e.g. restoring the original).
5. Only use games the user provides. Never download ROMs or point to ROM sites.
6. Don't modify `r36s-h-tool.ps1` to bypass its checks.

## Requirements

- Windows 10/11, a USB card reader, PowerShell **as Administrator** (raw disk access).
  Test with: `([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')`.
  If not admin, ask the user to restart Claude Code from an **Administrator** terminal.
- Run the script with: `powershell -NoProfile -ExecutionPolicy Bypass -File .\r36s-h-tool.ps1 ...`
- The device must be **switched off** before the card is removed.

## Workflow

1. **Check admin rights.**
2. Ask the user to switch the device off and put the card from slot 1 ("TF1") into the reader.
3. `-Action List` → show the result, confirm the disk number (look for "R36S-H card").
4. **Backup**, unless the user already has one (ask for its path):
   `-Action Backup -DiskNumber <n> -ImagePath <path>\backup.img` (takes ~25 min, read only).
   Run long commands in the background and report progress.
5. Recommend moving to a new card (optional): user inserts the NEW card,
   `-Action List` again → confirm the NEW card's number (it must NOT say "R36S-H card")
   → `-Action Clone -DiskNumber <new> -ImagePath <backup> -Yes` after explicit OK.
   Afterwards the new card goes into slot 1 and the user tests it.
   **Smaller new card** (e.g. 16 GB, smaller than the backup): use
   `-Action CloneSmall -DiskNumber <new> -ImagePath <backup> -Games "<word1>","<word2>" -Yes`
   after explicit OK. Ask the user which games/series they want (words that appear in file
   names or menu titles, e.g. "zelda","kirby"). Needs Python 3 (check with `py --version`).
   It copies the system file by file (keeping the lowercase-name flags) plus only the chosen
   games, and copies the boot area (sectors before the FAT32) from the backup. Experimental:
   tell the user to keep the original card until the new one boots.
6. **Add games.** Ask where the game files are. Pick the system folder from the file extension:

   | Extension | `-System` |
   |---|---|
   | `.gb` | `GB` |
   | `.gbc` | `GBC` |
   | `.gba` | `GBA` |
   | `.nes` | `FC` |
   | `.sfc`, `.smc` | `SFC` |
   | `.md`, `.gen`, `.smd` | `MD` |
   | `.pce` | `PCE` |
   | `.sms` | `SMS` |
   | `.gg` | `GG` |
   | `.iso`, `.img` (PlayStation) | `PS` (experimental, may run slowly) |
   | `.zip` | look inside to see which ROM type it contains |

   Group games per system and add them in one call per system:
   `-Action Add -DiskNumber <n> -ImagePath <backup> -System GB -Rom "<file1>","<file2>" -Name "<Nice Name 1>","<Nice Name 2>"`

   - Offer clean names for the menu (e.g. "Pokemon Blue" instead of "Pokemon - Blue Version (USA, Europe) (SGB Enhanced)").
   - For Game Boy games with Super Game Boy support (often "[S]" or "SGB" in the name, e.g.
     Pokémon Red/Blue/Yellow, Donkey Kong Land) add `-RemoveSgbBorder`. Otherwise the game is
     shown tiny inside a big border.
   - New games appear at the **end** of that system's list on the device.
7. When the script prints **"Done. The card can be removed."**, tell the user to put the card
   back into slot 1 and test.
8. **Remove a game:** `-Action Remove -DiskNumber <n> -ImagePath <backup> -System <SYS> -Name "<name>"`.

## Troubleshooting

| Message / symptom | Meaning / what to do |
|---|---|
| "No hidden FAT32 file system found" | Not an R36S-H card, or the card was formatted. If it was formatted: restore with `-Action Clone` from the backup. |
| "Sector 0 of the card does not match the backup" | Wrong card or wrong backup file. Ask which backup belongs to this card. |
| "copy could not be verified" / chkdsk warnings / read errors | Card has bad blocks → recommend moving to a new card (`Clone`). |
| "System folder 'X' not found" | The error lists the available folders. Pick one of them. |
| Game doesn't start | Try another dump/region of the game. GBA and PS are demanding for this device. |
| Device hangs at the boot logo after Clone | Re-run Clone (verification must pass); if it persists, put the original card back. |
| Device hangs at the boot logo after CloneSmall | Lowercase name flags or boot area wrong. Re-run CloneSmall; if it persists use a ≥ 32 GB card with `Clone`. |
| "That does not fit" (CloneSmall) | Choose fewer games with `-Games`. |
| ArkOS / dArkOS | Not supported on this model (different chip). Don't try. |

## Notes

- Save games are not stored on the card (on the tested device). Replacing a game with the
  same name keeps progress.
- If something goes wrong, `-Action Clone` with the backup restores the card exactly
  (use `-Force` when writing back onto a card that already has an R36S-H system).
