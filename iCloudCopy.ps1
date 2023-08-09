# ==============================================================================================
# Helps you organise your digital photos into subdirectory, based on the Exif data 
# found inside the picture. Based on the date picture taken property the pictures will be organized into
# subdirectories \YYYY\YYYY-MM
# ============================================================================================== 

Add-Type -AssemblyName System.Drawing

$sourcePath = "D:\afuec\Pictures\iCloud Photos\Photos"
$imageDestinationPath = "D:\afuec\OneDrive\Bilder\Allgemeines" 
$videoDestinationPath = "D:\afuec\Videos"  

$photoTypes = "*.jpg", "*.png", "*.jpeg"
$videoTypes = "*.mov", "*.mp4"

$configFilename = Join-Path $sourcePath ".icloudcopy"
[DateTime]$lastSyncDate = Get-Date "01.01.1900"
if (Test-Path $configFilename) {
    $lastSyncDate = Get-Date (Get-Content -Path $configFilename)
}
Write-Output "Will process all files NEWER than $lastSyncDate in '$sourcePath'."

# ============================================================================================== 
# copy photos
# ============================================================================================== 

$files = Get-ChildItem -Path $sourcePath -filter * -Include $photoTypes -Recurse | Where-Object {!$_.PsIsContainer -and $_.CreationTime -ge $lastSyncDate}
$numFiles = $files.Count
[Int32]$counter = 0
[Int32]$copyCounter = 0
[Int32]$takenDatePropertyId = 36867

foreach ($file in $files) {

    $takenDate = $Null
    $counter++
    Write-Progress -Activity "$numFiles image files." -Status "Files copied: $counter" -PercentComplete (100 * $counter / $numFiles)

    $image = New-Object -TypeName System.Drawing.Bitmap -ArgumentList $file.FullName
    [string]$targetPath = $Null

    try {
        $takenDateExists = $image.PropertyIdList -Contains $takenDatePropertyId
        if (-Not $takenDateExists) {
            $year = $file.LastWriteTime.Year
            $month = $file.LastWriteTime.Month
            $target = "{0:d4}-{1:d2}" -f $year, $month
            $targetPath = Join-Path $imageDestinationPath $year $target
        } else {
            $dateCharArray = $image.GetPropertyItem(36867).Value[0..18]  # Omitting last null character from array
            [String]$dateString =  [System.Text.Encoding]::ASCII.GetString($dateCharArray)
            $takenDate = [DateTime]::ParseExact($dateString, 'yyyy:MM:dd HH:mm:ss', $Null)
            $targetPath = Join-Path $imageDestinationPath "$( Get-Date $takenDate -Format yyyy )\$( Get-Date $takenDate -Format yyyy-MM )"
        }

        $image.Dispose()

        If (-Not (Test-Path $TargetPath)) {
            New-Item $TargetPath -Type Directory | Out-Null
        }

        # Change create date to taken date
        if ($Null -ne $takenDate) {
            $file.CreationTime = $takenDate
            $file.LastWriteTime = $takenDate
        }

        $filename = Join-Path $TargetPath $file.Name
        If (-Not (Test-Path $filename)) {
            Copy-Item -Path $file.FullName -Destination $targetPath | Out-Null
            $copyCounter++
            $newFile = Get-Item $filename
            if ($Null -ne $takenDate) {
                $newFile.CreationTime = $takenDate
                $newFile.LastWriteTime = $takenDate
            } 
        }
        attrib +o -p +u $file

    } catch {
        $err = $_
        Write-Error "Error processing image $( $file.Name ):/r/n$err"

        if ($Null -ne $image) {
            $image.Dispose()
        }
    }


} 

Write-Output "Finished processing $numFiles image files."
Write-Output "Moved $copyCounter image files to '$imageDestinationPath.'"

# ============================================================================================== 
# copy videos
# ============================================================================================== 

$files = Get-ChildItem -Path $sourcePath -filter * -Include $videoTypes -Recurse | Where-Object {!$_.PsIsContainer -and $_.CreationTime -ge $lastSyncDate} 
$numFiles = $files.Count
[Int32]$counter = 0
[Int32]$copyCounter = 0
[Int32]$takenDatePropertyId = 36867

foreach ($file in $files) {

    $takenDate = $Null
    $counter++
    Write-Progress -Activity "$numFiles video files." -Status "Files copied: $counter" -PercentComplete (100 * $counter / $numFiles)

    $year = $file.LastWriteTime.Year
    $month = $file.LastWriteTime.Month
    $target = "{0:d4}-{1:d2}" -f $year, $month
    $targetPath = Join-Path $videoDestinationPath $year $target

    If (-Not (Test-Path $TargetPath)) {
        New-Item $TargetPath -Type Directory | Out-Null
    }

    If (-Not (Test-Path (Join-Path $TargetPath $file.Name))) {
        Copy-Item -Path $file.FullName -Destination $targetPath | Out-Null
        $copyCounter++
    }
    attrib +o -p +u $file

} 

Write-Output "Finished processing $numFiles video files."
Write-Output "Moved $copyCounter video files to '$videoDestinationPath.'"

Get-Date -Format "dd.MM.yyyy HH:mm" | Out-File -FilePath $configFilename -Force