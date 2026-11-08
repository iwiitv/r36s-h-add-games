<#
.SYNOPSIS
  Add your own games to Hichip-based R36S clones ("R36S-H OS") - without formatting the card.

.DESCRIPTION
  The stock SD card of these handhelds contains a normal FAT32 file system, but sector 0
  holds no partition table. Windows therefore offers to format the card (DON'T!).

  Actions:
    List     Show removable disks and whether they look like an R36S-H card
    Backup   Copy the whole card into an image file and verify it
    Clone    Write a backup image to a NEW card (same size or bigger) and verify it
    Add      Add games to a system folder (zip + game list entry + preview image)
    Remove   Remove games from a system folder

  How Add/Remove work: a temporary partition table pointing at the hidden FAT32 is written
  to sector 0, Windows mounts the volume, the files are changed, the volume is dismounted
  and the ORIGINAL sector 0 is written back.

  Run PowerShell as Administrator. Make a backup first. Use at your own risk.

.EXAMPLE
  .\r36s-h-tool.ps1 -Action List
  .\r36s-h-tool.ps1 -Action Backup -DiskNumber 4 -ImagePath D:\R36S\backup.img
  .\r36s-h-tool.ps1 -Action Clone  -DiskNumber 5 -ImagePath D:\R36S\backup.img
  .\r36s-h-tool.ps1 -Action Add    -DiskNumber 4 -ImagePath D:\R36S\backup.img -System GBA -Rom 'D:\roms\My Game.gba'
  .\r36s-h-tool.ps1 -Action Remove -DiskNumber 4 -ImagePath D:\R36S\backup.img -System GBA -Name 'My Game'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('List', 'Backup', 'Clone', 'Add', 'Remove')] [string]$Action,
    [int]$DiskNumber = -1,
    [string]$ImagePath,
    [string]$System,
    [string[]]$Rom,
    [string[]]$Name,
    [switch]$RemoveSgbBorder,
    [switch]$Force,
    [switch]$Yes          # Clone without the interactive YES prompt (for tools/agents - only after the user agreed)
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem, System.Drawing
$Bom = [string][char]0xFEFF

# ------------------------------------------------------------------ helpers
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Open-Raw([string]$path, [bool]$write) {
    $acc = if ($write) { [IO.FileAccess]::ReadWrite } else { [IO.FileAccess]::Read }
    $opt = if ($write) { [IO.FileOptions]::WriteThrough } else { [IO.FileOptions]::None }
    New-Object IO.FileStream($path, [IO.FileMode]::Open, $acc, [IO.FileShare]::ReadWrite, [int]4096, $opt)
}
function Read-Bytes([string]$path, [long]$offset, [int]$count) {
    $fs = Open-Raw $path $false
    try { $b = New-Object byte[] $count; $fs.Position = $offset; [void]$fs.Read($b, 0, $count); , $b } finally { $fs.Close() }
}
function Write-Bytes([string]$path, [long]$offset, [byte[]]$data) {
    $fs = Open-Raw $path $true
    try { $fs.Position = $offset; $fs.Write($data, 0, $data.Length); $fs.Flush() } finally { $fs.Close() }
}
function Test-Same([byte[]]$a, [byte[]]$b) {
    if ($a.Length -ne $b.Length) { return $false }
    for ($i = 0; $i -lt $a.Length; $i++) { if ($a[$i] -ne $b[$i]) { return $false } }
    $true
}
function Show-Progress([string]$what, [long]$done, [long]$total, [datetime]$start) {
    $sec = [Math]::Max(((Get-Date) - $start).TotalSeconds, 0.1)
    $mbs = $done / 1MB / $sec
    $left = if ($mbs -gt 0) { [int](($total - $done) / 1MB / $mbs) } else { 0 }
    Write-Progress -Activity $what -Status ("{0:N1} / {1:N1} GB  ({2:N1} MB/s, ~{3} min left)" -f ($done / 1GB), ($total / 1GB), $mbs, [int]($left / 60)) -PercentComplete ([Math]::Min(100, $done * 100 / [Math]::Max($total, 1)))
}

# Hidden FAT32: a FAT32 boot sector in the first 8 MiB whose "hidden sectors" field equals its own LBA.
function Find-Fat32([string]$path) {
    $buf = Read-Bytes $path 0 (8MB)
    for ($o = 512; $o -lt $buf.Length - 512; $o += 512) {
        if ($buf[$o + 510] -ne 0x55 -or $buf[$o + 511] -ne 0xAA) { continue }
        if ([Text.Encoding]::ASCII.GetString($buf, $o + 82, 8) -ne 'FAT32   ') { continue }
        $lba = [uint32]($o / 512)
        if ([BitConverter]::ToUInt32($buf, $o + 28) -eq $lba) {
            return [pscustomobject]@{ Lba = $lba; Offset = [long]$o; Sectors = [BitConverter]::ToUInt32($buf, $o + 32) }
        }
    }
    $null
}

function Get-SafeDisk {
    if ($DiskNumber -lt 0) { throw "Please pass -DiskNumber (see: -Action List)." }
    Update-HostStorageCache
    $d = Get-Disk -Number $DiskNumber
    if ($d.IsBoot -or $d.IsSystem) { throw "Disk $DiskNumber is a system/boot disk. Refusing." }
    if ($d.BusType -notin 'USB', 'SD', 'MMC') { throw "Disk $DiskNumber is not a USB/SD device (BusType $($d.BusType)). Refusing." }
    $d
}

function Get-Card {
    $d = Get-SafeDisk
    $dev = "\\.\PhysicalDrive$DiskNumber"
    $fat = Find-Fat32 $dev
    if (-not $fat) { throw "No hidden FAT32 file system found on disk $DiskNumber. Is this an R36S-H card?" }
    if ($fat.Lba + [long]$fat.Sectors -gt $d.Size / 512) { throw "The file system is larger than the card. Refusing." }
    # A backup must exist and belong to this card (same sector 0).
    if (-not $ImagePath -or -not (Test-Path -LiteralPath $ImagePath)) { throw "Make a backup first (-Action Backup) and pass it with -ImagePath." }
    $s0 = Read-Bytes $dev 0 512
    if (-not (Test-Same $s0 (Read-Bytes $ImagePath 0 512))) { throw "Sector 0 of the card does not match the backup. Wrong card or wrong backup?" }
    [pscustomobject]@{ Disk = $d; Dev = $dev; Sector0 = $s0; Fat = $fat }
}

# Mounts the hidden FAT32, runs $Work with the drive root (e.g. "G:\"), always restores sector 0.
function Invoke-Mounted($card, [scriptblock]$Work) {
    $orig = $card.Sector0
    $s0file = Join-Path $PSScriptRoot ("sector0-disk{0}-{1:yyyyMMdd-HHmmss}.bin" -f $DiskNumber, (Get-Date))
    [IO.File]::WriteAllBytes($s0file, $orig)

    $mbr = New-Object byte[] 512
    $mbr[450] = 0x0C
    [BitConverter]::GetBytes([uint32]$card.Fat.Lba).CopyTo($mbr, 454)
    [BitConverter]::GetBytes([uint32]$card.Fat.Sectors).CopyTo($mbr, 458)
    [BitConverter]::GetBytes([uint32]0x52333653).CopyTo($mbr, 440)
    $mbr[510] = 0x55; $mbr[511] = 0xAA
    Write-Bytes $card.Dev 0 $mbr
    try {
        $part = $null
        for ($i = 0; $i -lt 30 -and -not $part; $i++) {
            Update-HostStorageCache; Start-Sleep 1
            $part = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | Where-Object { $_.Offset -eq $card.Fat.Offset } | Select-Object -First 1
        }
        if (-not $part) { throw "Windows did not detect the temporary partition." }
        if (-not $part.DriveLetter -or $part.DriveLetter -eq [char]0) {
            Add-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $part.PartitionNumber -AssignDriveLetter
        }
        $root = $null
        for ($i = 0; $i -lt 20 -and -not $root; $i++) {
            Start-Sleep 1
            $part = Get-Partition -DiskNumber $DiskNumber | Where-Object { $_.Offset -eq $card.Fat.Offset } | Select-Object -First 1
            if ($part.DriveLetter -and $part.DriveLetter -ne [char]0 -and [IO.Directory]::Exists("$($part.DriveLetter):\")) { $root = "$($part.DriveLetter):\" }
        }
        if (-not $root) { throw "The volume could not be mounted." }
        & $Work $root
        Write-VolumeCache -DriveLetter $part.DriveLetter
        $chk = cmd /c "chkdsk $($part.DriveLetter):" 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Warning "chkdsk reports problems:`n$($chk -join "`n")" }
        Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath $root
        Start-Sleep 2
    }
    finally {
        Write-Bytes $card.Dev 0 $orig
        Update-HostStorageCache; Start-Sleep 2
        Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveLetter -ne [char]0 } |
            ForEach-Object { Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $_.PartitionNumber -AccessPath "$($_.DriveLetter):\" -ErrorAction SilentlyContinue }
        if (Test-Same (Read-Bytes $card.Dev 0 512) $orig) {
            Remove-Item -LiteralPath $s0file -ErrorAction SilentlyContinue
            Write-Host "Done. The card can be removed." -ForegroundColor Green
        }
        else { Write-Warning "Sector 0 differs from the original! It was saved to $s0file - restore it or write your backup back with -Action Clone." }
    }
}

function Get-SystemFolder([string]$root) {
    $dir = [IO.Directory]::GetDirectories($root) | Where-Object { [IO.Path]::GetFileName($_) -ieq $System } | Select-Object -First 1
    if (-not $dir -or -not [IO.File]::Exists((Join-Path $dir 'FILELIST.CSV'))) {
        $known = [IO.Directory]::GetDirectories($root) | Where-Object { [IO.File]::Exists((Join-Path $_ 'FILELIST.CSV')) } | ForEach-Object { [IO.Path]::GetFileName($_) }
        throw "System folder '$System' not found. Available: $($known -join ', ')"
    }
    $dir
}
function Read-List([string]$dir) {
    $t = [IO.File]::ReadAllText((Join-Path $dir 'FILELIST.CSV'), [Text.Encoding]::UTF8).TrimStart($Bom)
    , @($t.Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
function Write-List([string]$dir, [string[]]$lines) {
    [IO.File]::WriteAllText((Join-Path $dir 'FILELIST.CSV'), (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($true)))
}

function New-Preview([string]$title, [string]$path) {
    $bmp = New-Object Drawing.Bitmap 320, 240
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.TextRenderingHint = 'AntiAlias'
    $h = [Math]::Abs($title.GetHashCode()) % 6
    $colors = 'SteelBlue', 'Firebrick', 'ForestGreen', 'DarkOrange', 'MediumPurple', 'Teal'
    $g.Clear([Drawing.Color]::FromName($colors[$h]))
    $fmt = New-Object Drawing.StringFormat; $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
    $g.DrawString($title, (New-Object Drawing.Font('Segoe UI', 22, [Drawing.FontStyle]::Bold)), [Drawing.Brushes]::White, (New-Object Drawing.RectangleF(10, 10, 300, 220)), $fmt)
    $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

# Game Boy: clear the Super Game Boy flag so the emulator doesn't draw the (screen-shrinking) SGB border.
function Remove-SgbFlag([byte[]]$b) {
    if ($b.Length -lt 0x150 -or $b[0x146] -ne 0x03) { return $false }
    $b[0x146] = 0x00
    $x = 0; for ($i = 0x134; $i -le 0x14C; $i++) { $x = ($x - $b[$i] - 1) -band 0xFF }
    $b[0x14D] = [byte]$x
    $s = 0; for ($i = 0; $i -lt $b.Length; $i++) { if ($i -ne 0x14E -and $i -ne 0x14F) { $s = ($s + $b[$i]) -band 0xFFFF } }
    $b[0x14E] = [byte](($s -shr 8) -band 0xFF); $b[0x14F] = [byte]($s -band 0xFF)
    $true
}

# ------------------------------------------------------------------ actions
if (-not (Test-Admin)) { throw "Please run PowerShell as Administrator." }

switch ($Action) {

    'List' {
        Update-HostStorageCache
        $disks = Get-Disk | Where-Object { $_.BusType -in 'USB', 'SD', 'MMC' -and -not $_.IsBoot -and -not $_.IsSystem }
        if (-not $disks) { Write-Host "No USB/SD disks found. Is the card reader connected?"; break }
        foreach ($d in $disks) {
            $info = 'empty reader or unreadable'
            try {
                $fat = Find-Fat32 "\\.\PhysicalDrive$($d.Number)"
                $info = if ($fat) { "R36S-H card (hidden FAT32 at sector $($fat.Lba))" } else { 'not an R36S-H card' }
            } catch {}
            "Disk {0}: {1,-24} {2,8:N2} GB   {3}" -f $d.Number, $d.FriendlyName, ($d.Size / 1GB), $info
        }
    }

    'Backup' {
        $d = Get-SafeDisk
        if (-not $ImagePath) { throw "Pass -ImagePath, e.g. D:\R36S\backup.img" }
        if (Test-Path -LiteralPath $ImagePath) { throw "$ImagePath already exists." }
        $dir = Split-Path -Parent $ImagePath; if ($dir) { New-Item -ItemType Directory -Force $dir | Out-Null }
        $free = (Get-PSDrive -Name (Split-Path -Qualifier (Resolve-Path $dir).Path).TrimEnd(':')).Free
        if ($free -lt $d.Size) { throw ("Not enough free space: need {0:N1} GB." -f ($d.Size / 1GB)) }
        $size = [long]$d.Size; $chunk = 4MB; $buf = New-Object byte[] $chunk
        $sha = [Security.Cryptography.SHA1]::Create(); $start = Get-Date
        $src = Open-Raw "\\.\PhysicalDrive$DiskNumber" $false; $dst = [IO.File]::Create("$ImagePath.part")
        try {
            $done = [long]0
            while ($done -lt $size) {
                $n = [int][Math]::Min([long]$chunk, $size - $done)
                $r = $src.Read($buf, 0, $n); if ($r -le 0) { throw "Read error at byte $done - the card may be damaged." }
                $dst.Write($buf, 0, $r); [void]$sha.TransformBlock($buf, 0, $r, $null, 0); $done += $r
                Show-Progress 'Backup' $done $size $start
            }
        } finally { $src.Close(); $dst.Close() }
        [void]$sha.TransformFinalBlock($buf, 0, 0)
        $cardHash = [BitConverter]::ToString($sha.Hash).Replace('-', '')
        Write-Host "Verifying..."
        $fileHash = (Get-FileHash -LiteralPath "$ImagePath.part" -Algorithm SHA1).Hash
        if ($fileHash -ne $cardHash) { throw "Verification failed (card $cardHash, file $fileHash)." }
        Move-Item -LiteralPath "$ImagePath.part" $ImagePath
        "$cardHash  $(Split-Path -Leaf $ImagePath)" | Set-Content -LiteralPath "$ImagePath.sha1" -Encoding ASCII
        Write-Host "Backup OK: $ImagePath" -ForegroundColor Green
    }

    'Clone' {
        $d = Get-SafeDisk
        if (-not $ImagePath -or -not (Test-Path -LiteralPath $ImagePath)) { throw "Pass the backup image with -ImagePath." }
        $size = (Get-Item -LiteralPath $ImagePath).Length
        if ($d.Size -lt $size) { throw ("The new card is too small: {0:N2} GB needed, card has {1:N2} GB." -f ($size / 1GB), ($d.Size / 1GB)) }
        if (Find-Fat32 "\\.\PhysicalDrive$DiskNumber") {
            if (-not $Force) { throw "Disk $DiskNumber already looks like an R36S-H card. Is it your ORIGINAL card? Use -Force only if you really want to overwrite it." }
        }
        Write-Host ("Disk {0}: {1} ({2:N1} GB) will be COMPLETELY OVERWRITTEN." -f $DiskNumber, $d.FriendlyName, ($d.Size / 1GB)) -ForegroundColor Yellow
        if (-not $Yes -and (Read-Host "Type YES to continue") -ne 'YES') { Write-Host "Cancelled."; break }

        Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveLetter -ne [char]0 } |
            ForEach-Object { Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $_.PartitionNumber -AccessPath "$($_.DriveLetter):\" -ErrorAction SilentlyContinue }
        Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep 2

        $chunk = 4MB; $buf = New-Object byte[] $chunk; $start = Get-Date
        $src = [IO.File]::OpenRead($ImagePath); $dst = Open-Raw "\\.\PhysicalDrive$DiskNumber" $true
        try {
            $done = [long]0
            while (($n = $src.Read($buf, 0, $chunk)) -gt 0) {
                if ($n % 512) { [Array]::Clear($buf, $n, 512 - $n % 512); $n += 512 - $n % 512 }
                $dst.Write($buf, 0, $n); $done += $n
                Show-Progress 'Writing' $done $size $start
            }
            $dst.Flush()
        } finally { $src.Close(); $dst.Close() }

        Write-Host "Verifying..."
        $shaA = [Security.Cryptography.SHA1]::Create(); $shaB = [Security.Cryptography.SHA1]::Create()
        $a = [IO.File]::OpenRead($ImagePath); $b = Open-Raw "\\.\PhysicalDrive$DiskNumber" $false
        $buf2 = New-Object byte[] $chunk; $start = Get-Date
        try {
            $done = [long]0
            while ($done -lt $size) {
                $n = [int][Math]::Min([long]$chunk, $size - $done)
                $r1 = $a.Read($buf, 0, $n); $r2 = $b.Read($buf2, 0, [int]([Math]::Ceiling($n / 512) * 512))
                [void]$shaA.TransformBlock($buf, 0, $r1, $null, 0); [void]$shaB.TransformBlock($buf2, 0, $r1, $null, 0); $done += $r1
                Show-Progress 'Verifying' $done $size $start
            }
        } finally { $a.Close(); $b.Close() }
        [void]$shaA.TransformFinalBlock($buf, 0, 0); [void]$shaB.TransformFinalBlock($buf2, 0, 0)
        if ([BitConverter]::ToString($shaA.Hash) -ne [BitConverter]::ToString($shaB.Hash)) { throw "Verification FAILED - the new card may be faulty." }
        Update-HostStorageCache
        Write-Host "Clone OK. Put the new card into slot 1 and start the device." -ForegroundColor Green
    }

    'Add' {
        if (-not $System) { throw "Pass -System (folder on the card, e.g. GB, GBC, GBA, FC, SFC, MD)." }
        if (-not $Rom) { throw "Pass -Rom with one or more game files (.zip or ROM file)." }
        if ($Name -and $Name.Count -ne $Rom.Count) { throw "-Name needs as many entries as -Rom." }
        $card = Get-Card

        $stage = Join-Path ([IO.Path]::GetTempPath()) ("r36s-h-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Force $stage | Out-Null
        $items = @()
        try {
            for ($i = 0; $i -lt $Rom.Count; $i++) {
                $f = Get-Item -LiteralPath $Rom[$i]
                $title = if ($Name) { $Name[$i] } else { [IO.Path]::GetFileNameWithoutExtension($f.Name) }
                $title = ($title -replace '[\[\]]', '' -replace ',', ' ' -replace '\s+', ' ').Trim()
                $zip = Join-Path $stage "$title.zip"
                if ($System -ieq 'PS') {
                    # PlayStation games are stored as plain disc images, not zipped
                    if ($f.Extension -notin '.img', '.iso', '.IMG', '.ISO') { throw "PS games must be .img or .iso files: $($f.Name)" }
                    $zip = Join-Path $stage "$title$($f.Extension.ToLower())"
                    Copy-Item -LiteralPath $f.FullName $zip
                }
                elseif ($f.Extension -ieq '.zip') { Copy-Item -LiteralPath $f.FullName $zip }
                else {
                    $bytes = [IO.File]::ReadAllBytes($f.FullName)
                    if ($RemoveSgbBorder -and $f.Extension -ieq '.gb') {
                        if (Remove-SgbFlag $bytes) { Write-Host "  $title : Super Game Boy border removed" }
                    }
                    $za = [IO.Compression.ZipFile]::Open($zip, 'Create')
                    try {
                        $e = $za.CreateEntry("$title$($f.Extension.ToLower())")
                        $s = $e.Open(); $s.Write($bytes, 0, $bytes.Length); $s.Close()
                    } finally { $za.Dispose() }
                }
                New-Preview $title (Join-Path $stage "$title.png")
                $items += [pscustomobject]@{ Title = $title; Zip = $zip; Png = (Join-Path $stage "$title.png") }
            }

            Invoke-Mounted $card {
                param($root)
                $dir = Get-SystemFolder $root
                $lines = Read-List $dir
                $imgDir = Join-Path $dir 'IMAGES'; if (-not [IO.Directory]::Exists($imgDir)) { [void][IO.Directory]::CreateDirectory($imgDir) }
                foreach ($it in $items) {
                    $fileName = [IO.Path]::GetFileName($it.Zip)
                    $target = Join-Path $dir $fileName
                    [IO.File]::Copy($it.Zip, $target, $true)
                    if (-not [IO.File]::Exists((Join-Path $imgDir "$($it.Title).png"))) { [IO.File]::Copy($it.Png, (Join-Path $imgDir "$($it.Title).png"), $true) }
                    if (-not ($lines | Where-Object { $_.Split(',')[0].Trim() -ieq $fileName })) { $lines += "$fileName,$($it.Title),$($it.Title)" }
                    $ok = (Get-FileHash -LiteralPath $it.Zip -Algorithm SHA1).Hash -eq (Get-FileHash -LiteralPath $target -Algorithm SHA1).Hash
                    if ($ok) { Write-Host "  added: $System\$($it.Title)" } else { Write-Warning "  $($it.Title): copy could not be verified - the card may be damaged." }
                }
                Write-List $dir $lines
            }
        } finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }

    'Remove' {
        if (-not $System -or -not $Name) { throw "Pass -System and -Name (game names as shown by the game list, without .zip)." }
        $card = Get-Card
        Invoke-Mounted $card {
            param($root)
            $dir = Get-SystemFolder $root
            $lines = Read-List $dir
            foreach ($n in $Name) {
                $zipName = if ($n -match '\.(zip|iso|img)$') { $n } else {
                    $hit = [IO.Directory]::GetFiles($dir) | Where-Object { [IO.Path]::GetFileNameWithoutExtension($_) -ieq $n -and $_ -match '\.(zip|iso|img)$' } | Select-Object -First 1
                    if ($hit) { [IO.Path]::GetFileName($hit) } else { "$n.zip" }
                }
                $before = $lines.Count
                $lines = @($lines | Where-Object { $_.Split(',')[0].Trim() -ine $zipName })
                $zip = Join-Path $dir $zipName
                $png = Join-Path $dir ("IMAGES\" + [IO.Path]::ChangeExtension($zipName, '.png'))
                $gone = $false
                foreach ($x in $zip, $png) { if ([IO.File]::Exists($x)) { [IO.File]::Delete($x); $gone = $true } }
                if ($gone -or $lines.Count -lt $before) { Write-Host "  removed: $System\$n" } else { Write-Warning "  not found: $System\$n" }
            }
            Write-List $dir $lines
        }
    }
}
