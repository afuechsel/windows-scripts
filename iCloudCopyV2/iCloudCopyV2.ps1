# iCloudCopyV2.ps1
# ============================================================
# End-to-End Foto-Pipeline für iCloud
#
# Pipeline:
#   1. icloudpd lädt Fotos inkrementell nach _incoming
#   2. Dieses Script sortiert idempotent nach yyyy\MM
#   3. Hash-basierte Duplikaterkennung
#   4. Live-Foto-Handling (JPG + MOV)
#
# Empfohlene icloudpd-Konfiguration (VOR diesem Script ausführen):
#
# icloudpd \
#   --directory "D:\Photos\_incoming" \
#   --username "DEINE_APPLE_ID@mail.de" \
#   --cookie-directory "%APPDATA%\icloudpd" \
#   --size original \
#   --set-exif-datetime \
#   --auto-delete
#
# Danach dieses Script regelmäßig (Taskplaner) starten.
#
# ============================================================

param (
    [string]$IncomingRoot = "D:\Photos\_incoming",
    [string]$TargetRoot   = "D:\Photos",
    [string]$LogRoot      = "D:\Photos\Logs",
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$RunId = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LogFile = Join-Path $LogRoot "photo_pipeline_$RunId.log"

New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
New-Item -ItemType Directory -Path "$TargetRoot\Conflicts" -Force | Out-Null

function Log {
    param($Message, $Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

Add-Type -AssemblyName System.Drawing

function Get-PhotoDate {
    param($File)
    try {
        $img = [System.Drawing.Image]::FromFile($File.FullName)
        if ($img.PropertyIdList -contains 0x9003) {
            $raw = $img.GetPropertyItem(0x9003).Value
            $text = ([System.Text.Encoding]::ASCII.GetString($raw)).Trim([char]0)
            $img.Dispose()
            return [datetime]::ParseExact($text, "yyyy:MM:dd HH:mm:ss", $null)
        }
        $img.Dispose()
    } catch {}
    return $File.LastWriteTime
}

function Get-HashSafe {
    param($Path)
    try { (Get-FileHash -Algorithm SHA256 -Path $Path).Hash } catch { $null }
}

Log "=== START iCloudCopyV2 ==="
Log "WhatIf Mode: $WhatIf"

$files = Get-ChildItem $IncomingRoot -File
$groups = $files | Group-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }

foreach ($group in $groups) {
    $jpg = $group.Group | Where-Object { $_.Extension -match '\.jpe?g' }
    if (-not $jpg) { continue }

    $date = Get-PhotoDate $jpg
    $year  = $date.Year.ToString("0000")
    $month = $date.Month.ToString("00")

    $destDir = Join-Path $TargetRoot "$year\$month"
    if (-not $WhatIf) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

    foreach ($file in $group.Group) {
        $dest = Join-Path $destDir $file.Name

        if (Test-Path $dest) {
            if ((Get-HashSafe $file.FullName) -eq (Get-HashSafe $dest)) {
                Log "Duplikat (Hash gleich): $($file.Name)"
                if (-not $WhatIf) { Remove-Item $file.FullName -Force }
            } else {
                $conflictDir = Join-Path $TargetRoot "Conflicts\$year\$month"
                if (-not $WhatIf) {
                    New-Item -ItemType Directory -Path $conflictDir -Force | Out-Null
                    Move-Item $file.FullName (Join-Path $conflictDir $file.Name)
                }
                Log "Konflikt (Hash unterschiedlich): $($file.Name)" "WARN"
            }
        } else {
            Log "Verschiebe: $($file.Name) → $year\$month"
            if (-not $WhatIf) { Move-Item $file.FullName $dest }
        }
    }
}

Log "=== ENDE iCloudCopyV2 ==="
