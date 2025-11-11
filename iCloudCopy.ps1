# ==============================================================================================
# Helps you organise your digital photos into subdirectory, based on the Exif data
# found inside the picture. Based on the date picture taken property the pictures will be organized into
# subdirectories \YYYY\YYYY-MM
# ==============================================================================================

param(
    [switch]$WhatIf,               # Optional dry-run flag
    [switch]$IncludeHeic = $true   # Allow user to disable HEIC handling if desired
)

Add-Type -AssemblyName System.Drawing

$sourcePath = "C:\users\afuec\iCloud Photos\Photos"
$imageDestinationPath = "D:\afuec\OneDrive\Bilder\Allgemeines"
$videoDestinationPath = "D:\afuec\Videos"

# STEP 4 (optional HEIC support): include .heic only if enabled
$photoTypes = if ($IncludeHeic) { "*.jpg", "*.png", "*.jpeg", "*.heic" } else { "*.jpg", "*.png", "*.jpeg" }
$videoTypes = "*.mov", "*.mp4"

$configFilename = Join-Path $sourcePath ".icloudcopy"
[DateTime]$lastSyncDate = Get-Date "01.01.1900"
if (Test-Path $configFilename) {
    $lastSyncDate = Get-Date (Get-Content -Path $configFilename)
}
Write-Output "Will process all files NEWER than $lastSyncDate in '$sourcePath'."

# Helper: build target child path as YYYY\YYYY-MM
function Get-YearMonthChildPath([DateTime]$dt) {
    $year = $dt.Year
    $month = $dt.Month
    return ('{0:d4}\{0:d4}-{1:d2}' -f $year, $month)
}

# ==============================================================================================
# copy photos
# ==============================================================================================

$files = Get-ChildItem -Path $sourcePath -Filter * -Include $photoTypes -Recurse |
    Where-Object { -not $_.PsIsContainer -and $_.LastWriteTime -ge $lastSyncDate }

$numFiles = $files.Count
[Int32]$counter = 0
[Int32]$copyCounter = 0
[Int32]$takenDatePropertyId = 36867

foreach ($file in $files) {
    $counter++
    Write-Progress -Activity "$numFiles image files." -Status "Processed: $counter / $numFiles" -PercentComplete ([int](100 * $counter / [Math]::Max(1,$numFiles)))

    $takenDate = $null
    $targetPath = $null
    $sourceDateKind = 'Fallback'

    $ext = [System.IO.Path]::GetExtension($file.FullName).ToLowerInvariant()

    if ($ext -ne '.heic') {
        $image = $null
        try {
            $image = New-Object -TypeName System.Drawing.Bitmap -ArgumentList $file.FullName
            $takenDateExists = $image.PropertyIdList -contains $takenDatePropertyId
            if ($takenDateExists) {
                try {
                    $dateCharArray = $image.GetPropertyItem(36867).Value[0..18]
                    [string]$dateString = [System.Text.Encoding]::ASCII.GetString($dateCharArray)
                    $takenDate = [DateTime]::ParseExact($dateString, 'yyyy:MM:dd HH:mm:ss', $null)
                    $sourceDateKind = 'EXIF'
                } catch {
                    $takenDate = $null
                    $sourceDateKind = 'Fallback'
                }
            }
        } catch {
            Write-Warning "EXIF read failed for $($file.Name). Falling back to LastWriteTime."
        } finally {
            if ($image) { $image.Dispose() }
        }
    }

    if ($takenDate) {
        $child = Get-YearMonthChildPath -dt $takenDate
    } else {
        $child = Get-YearMonthChildPath -dt $file.LastWriteTime
    }

    $targetPath = Join-Path $imageDestinationPath $child

    if (-not (Test-Path $targetPath)) {
        if (-not $WhatIf) { New-Item $targetPath -ItemType Directory | Out-Null }
    }

    $destFile = Join-Path $targetPath $file.Name

    if (-not (Test-Path $destFile)) {
        if (-not $WhatIf) {
            Copy-Item -Path $file.FullName -Destination $targetPath -Force | Out-Null
            $newFile = Get-Item $destFile
            if ($takenDate) {
                $newFile.CreationTime = $takenDate
                $newFile.LastWriteTime = $takenDate
            }
        }
        $copyCounter++
        Write-Output ("Copied {0} -> {1} (date={2}, kind={3})" -f $file.Name, $targetPath, ($takenDate ? $takenDate.ToString('yyyy-MM-dd HH:mm') : $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm')), $sourceDateKind)
    } else {
        Write-Output ("Skipped (exists): {0}" -f $destFile)
    }

    if (-not $WhatIf) { attrib +o -p +u $file }
}

Write-Output "Finished processing $numFiles image files."
Write-Output "Copied $copyCounter image files to '$imageDestinationPath.'"

# ==============================================================================================
# copy videos
# ==============================================================================================

$files = Get-ChildItem -Path $sourcePath -Filter * -Include $videoTypes -Recurse |
    Where-Object { -not $_.PsIsContainer -and $_.LastWriteTime -ge $lastSyncDate }

$numFiles = $files.Count
$counter = 0
$copyCounter = 0

foreach ($file in $files) {
    $counter++
    Write-Progress -Activity "$numFiles video files." -Status "Processed: $counter / $numFiles" -PercentComplete ([int](100 * $counter / [Math]::Max(1,$numFiles)))

    $child = Get-YearMonthChildPath -dt $file.LastWriteTime
    $targetPath = Join-Path $videoDestinationPath $child

    if (-not (Test-Path $targetPath)) {
        if (-not $WhatIf) { New-Item $targetPath -ItemType Directory | Out-Null }
    }

    $destFile = Join-Path $targetPath $file.Name
    if (-not (Test-Path $destFile)) {
        if (-not $WhatIf) { Copy-Item -Path $file.FullName -Destination $targetPath -Force | Out-Null }
        $copyCounter++
        Write-Output ("Copied {0} -> {1} (date={2})" -f $file.Name, $targetPath, $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
    } else {
        Write-Output ("Skipped (exists): {0}" -f $destFile)
    }

    if (-not $WhatIf) { attrib +o -p +u $file }
}

Write-Output "Finished processing $numFiles video files."
Write-Output "Copied $copyCounter video files to '$videoDestinationPath.'"

if (-not $WhatIf) {
    Get-Date -Format "dd.MM.yyyy HH:mm" | Out-File -FilePath $configFilename -Force
    Write-Output "Updated sync timestamp in .icloudcopy."
} else {
    Write-Output "Dry-run mode: no files were copied or modified."
}
