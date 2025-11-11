# Normalize-FotoMonate.ps1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    # Oberster Bilder-Ordner, der die Jahresordner (z.B. 2023, 2024, 2025) enthält
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RootPath,

    # Optional: Leere Quellordner nach erfolgreichem Zusammenführen entfernen
    [switch]$PruneEmpty
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-UniquePath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $Path }

    $dir  = Split-Path -LiteralPath $Path -Parent
    $name = Split-Path -LiteralPath $Path -Leaf
    $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $ext  = [System.IO.Path]::GetExtension($name)

    $i = 1
    do {
        $candidate = Join-Path $dir ("{0} ({1}){2}" -f $base, $i, $ext)
        $i++
    } while (Test-Path -LiteralPath $candidate)

    return $candidate
}

function Merge-Folder {
    <#
      Zweck: Inhalte von -Source nach -Destination sicher zusammenführen.
      - Dateien werden verschoben; Namenskollisionen werden mit Suffixen aufgelöst.
      - Unterordner werden rekursiv zusammengeführt.
      - Quellordner wird nur entfernt, wenn -PruneEmpty gesetzt ist und leer ist.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter()][switch]$PruneEmpty
    )

    if (-not (Test-Path -LiteralPath $Source)) { return }
    if (-not (Test-Path -LiteralPath $Destination)) {
        if ($PSCmdlet.ShouldProcess($Destination, "Create destination folder")) {
            New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        }
    }

    # Dateien zusammenführen
    Get-ChildItem -LiteralPath $Source -File -Force | ForEach-Object {
        $target = Join-Path $Destination $_.Name
        if (Test-Path -LiteralPath $target) {
            $target = Get-UniquePath -Path $target
        }
        if ($PSCmdlet.ShouldProcess($target, "Move file from '$($_.FullName)'")) {
            Move-Item -LiteralPath $_.FullName -Destination $target -Force
        }
    }

    # Unterordner zusammenführen / verschieben
    Get-ChildItem -LiteralPath $Source -Directory -Force | ForEach-Object {
        $destSub = Join-Path $Destination $_.Name
        if (Test-Path -LiteralPath $destSub) {
            Merge-Folder -Source $_.FullName -Destination $destSub -PruneEmpty:$PruneEmpty
        } else {
            if ($PSCmdlet.ShouldProcess($destSub, "Move folder from '$($_.FullName)'")) {
                Move-Item -LiteralPath $_.FullName -Destination $destSub
            }
        }
    }

    # Optional: leeren Quellordner entfernen
    if ($PruneEmpty) {
        $isEmpty = -not (Get-ChildItem -LiteralPath $Source -Force | Select-Object -First 1)
        if ($isEmpty -and $PSCmdlet.ShouldProcess($Source, "Remove empty source folder")) {
            Remove-Item -LiteralPath $Source -Force
        }
    }
}

function Get-MonthInfo {
    <#
      Erkennt aus einem Ordnernamen den Monatsindex (1..12) und erzeugt den kanonischen Namen "MM_Monat".
      Unterstützt Varianten wie: "01", "1", "01_Januar", "Januar", "01-Januar", "01 Januar", "Feb", "Sept", etc.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Name)

    $months = @(
        'Januar','Februar','März','April','Mai','Juni',
        'Juli','August','September','Oktober','November','Dezember'
    )
    $aliases = @{
        'jan'='Januar'; 'feb'='Februar'; 'mar'='März'; 'mär'='März'; 'apr'='April'; 'mai'='Mai';
        'jun'='Juni'; 'jul'='Juli'; 'aug'='August'; 'sep'='September'; 'sept'='September';
        'okt'='Oktober'; 'nov'='November'; 'dez'='Dezember'
    }

    $trimmed = ($Name -replace '[_\-\s]+',' ').Trim()

    # 1) Nur Zahl?
    if ($trimmed -match '^(?<n>\d{1,2})$') {
        $n = [int]$Matches['n']
        if ($n -ge 1 -and $n -le 12) {
            $canon = ('{0:00}_{1}' -f $n, $months[$n-1])
            return [PSCustomObject]@{ Index=$n; Canonical=$canon }
        }
    }

    # 2) Zahl + Name (beliebige Trennzeichen)
    if ($trimmed -match '^(?<n>\d{1,2})\s+(?<m>.+)$') {
        $n = [int]$Matches['n']; $m = $Matches['m'].ToLower()
        $mLong = $months | Where-Object { $_.ToLower() -eq $m }
        if (-not $mLong -and $aliases.ContainsKey($m)) { $mLong = $aliases[$m] }
        if ($n -ge 1 -and $n -le 12 -and $mLong) {
            $canon = ('{0:00}_{1}' -f $n, $mLong)
            return [PSCustomObject]@{ Index=$n; Canonical=$canon }
        }
    }

    # 3) Nur Name?
    $m = $months | Where-Object { $_.ToLower() -eq $trimmed.ToLower() }
    if (-not $m) {
        $key = $aliases.Keys | Where-Object { $_ -eq $trimmed.ToLower() } | Select-Object -First 1
        if ($key) { $m = $aliases[$key] }
    }
    if ($m) {
        $idx = [array]::IndexOf($months,$m) + 1
        $canon = ('{0:00}_{1}' -f $idx, $m)
        return [PSCustomObject]@{ Index=$idx; Canonical=$canon }
    }

    return $null
}

function Normalize-Year {
    <#
      Normalisiert alle Monatsordner in einem Jahresordner (vierstellig).
      - Kanonisches Format: "MM_Monat" (z.B. "01_Januar").
      - Existieren mehrere Varianten (z.B. "1", "01", "Januar", "01_Januar"), werden Inhalte zusammengeführt.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$YearPath,
        [Parameter()][switch]$PruneEmpty
    )

    if (-not (Test-Path -LiteralPath $YearPath)) { return }

    $dirs = Get-ChildItem -LiteralPath $YearPath -Directory -Force
    if (-not $dirs) { return }

    # Mapping: Monatsindex -> vorhandene Ordner (versch. Schreibweisen)
    $byIndex = @{}

    foreach ($d in $dirs) {
        $mi = Get-MonthInfo -Name $d.Name
        if ($mi) {
            if (-not $byIndex.ContainsKey($mi.Index)) {
                $byIndex[$mi.Index] = [System.Collections.Generic.List[string]]::new()
            }
            $byIndex[$mi.Index].Add($d.FullName)
        }
    }

    foreach ($kv in $byIndex.GetEnumerator() | Sort-Object Key) {
        $idx = $kv.Key
        $candidates = $kv.Value
        if (-not $candidates) { continue }

        $canonicalName = ('{0:00}_{1}' -f $idx, (Get-MonthInfo -Name "$idx").Canonical.Split('_',2)[1])
        $canonicalPath = Join-Path $YearPath $canonicalName

        # Falls der kanonische Ordner noch nicht existiert, wähle einen Kandidaten als Ziel
        if (-not (Test-Path -LiteralPath $canonicalPath)) {
            # Bevorzugt bereits korrekt formatierten Kandidaten, sonst den "längsten" plausiblen Namen
            $preferred = $candidates | Where-Object { Split-Path -Leaf $_ -match '^\d{2}[_\-\s]+' } |
                         Sort-Object { $_.Length } -Descending | Select-Object -First 1
            if (-not $preferred) {
                $preferred = $candidates | Sort-Object { $_.Length } -Descending | Select-Object -First 1
            }
            $preferredLeaf = Split-Path -Leaf $preferred
            if ($preferredLeaf -ne $canonicalName) {
                if ($PSCmdlet.ShouldProcess($preferred, "Rename to '$canonicalName'")) {
                    Rename-Item -LiteralPath $preferred -NewName $canonicalName
                }
                $canonicalPath = Join-Path $YearPath $canonicalName
            } else {
                $canonicalPath = $preferred
            }
        }

        # Alle übrigen Kandidaten in den kanonischen Ordner zusammenführen
        foreach ($src in $candidates) {
            if ((Resolve-Path -LiteralPath $src).Path -eq (Resolve-Path -LiteralPath $canonicalPath).Path) { continue }
            Merge-Folder -Source $src -Destination $canonicalPath -PruneEmpty:$PruneEmpty
        }
    }
}

# --- Hauptablauf ---
try {
    if (-not (Test-Path -LiteralPath $RootPath)) {
        throw "RootPath '$RootPath' wurde nicht gefunden."
    }

    $years = Get-ChildItem -LiteralPath $RootPath -Directory -Force |
             Where-Object { $_.Name -match '^\d{4}$' } |
             Sort-Object Name

    $totalYears = ($years | Measure-Object).Count
    $yearIdx = 0

    foreach ($y in $years) {
        $yearIdx++

        $activityOverall = "Normalisiere Foto-Monate"
        $statusOverall = "Jahr $($y.Name) ($yearIdx von $totalYears)"
        $percentOverall = [int](($yearIdx-1) / [math]::Max($totalYears,1) * 100)

        Write-Progress -Id 1 -Activity $activityOverall -Status $statusOverall -PercentComplete $percentOverall

        # Innerer Fortschritt: Anzahl Ordner im Jahr
        $yearDirs = Get-ChildItem -LiteralPath $y.FullName -Directory -Force
        $totalOps = [math]::Max(($yearDirs | Measure-Object).Count, 1)
        $opIdx = 0

        foreach ($d in $yearDirs) {
            $opIdx++
            $statusInner = "Bearbeite: " + $d.Name
            $percentInner = [int]($opIdx / $totalOps * 100)
            Write-Progress -Id 2 -ParentId 1 -Activity $statusOverall -Status $statusInner -PercentComplete $percentInner
        }

        # Eigentliche Normalisierung
        Normalize-Year -YearPath $y.FullName -PruneEmpty:$PruneEmpty
    }

    # Abschluss
    Write-Progress -Id 2 -Completed
    Write-Progress -Id 1 -Activity "Normalisiere Foto-Monate" -Status "Fertig" -PercentComplete 100 -Completed
    Write-Verbose "Fertig."
}
catch {
    Write-Error $_
}
