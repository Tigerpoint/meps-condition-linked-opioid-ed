<#
.SYNOPSIS
  Downloads every MEPS public-use file this analysis consumes, extracts the
  Stata (.dta) versions, and verifies each one against analysis/outputs/file_manifest.csv.

.DESCRIPTION
  The analysis reads 33 MEPS Household Component public-use files plus the
  HC-036 pooled linkage variance file. AHRQ distributes these directly in Stata
  format, so the downloaded .dta files are byte-identical to the ones used to
  produce the published results -- no format conversion sits in between.

  This script fetches them, then compares SHA-256 against the manifest recorded
  at analysis time. A clean run means your local copy of the source data is
  provably the same data the paper was computed from.

  Total download is roughly 1.6 GB. Files already present with a correct hash
  are skipped, so the script is safe to re-run and to resume after interruption.

.PARAMETER DataDir
  Where to put the extracted .dta files. This is the path you then pass to
  meps_analysis.py --data-dir.

.EXAMPLE
  .\scripts\fetch_meps_data.ps1 -DataDir "D:\meps\dta"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DataDir,
    [string]$ManifestPath = "$PSScriptRoot\..\analysis\outputs\file_manifest.csv",
    [switch]$KeepZips
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # large speedup for Invoke-WebRequest

if (-not (Test-Path $ManifestPath)) { throw "Manifest not found: $ManifestPath" }
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
$zipDir = Join-Path $DataDir '_zips'
New-Item -ItemType Directory -Force -Path $zipDir | Out-Null

# AHRQ directory naming is not simply the file stem in two cases.
function Get-PufDirectory([string]$stem) {
    if ($stem -match '^h36')      { return 'h036' }        # HC-036 pooled variance file
    if ($stem -match '^(.*i)f1$') { return $Matches[1] }   # event-condition link files
    return $stem
}

$manifest = Import-Csv $ManifestPath
Write-Host "Manifest lists $($manifest.Count) input files.`n"

$ok = 0; $failed = 0; $skipped = 0
$problems = @()

foreach ($row in $manifest) {
    $dtaName = $row.requested_file                      # e.g. h197a.dta
    $stem    = [IO.Path]::GetFileNameWithoutExtension($dtaName)
    $want    = $row.sha256.Trim().ToLower()
    $dest    = Join-Path $DataDir $dtaName

    # Skip anything already present and correct.
    if (Test-Path $dest) {
        $have = (Get-FileHash -Path $dest -Algorithm SHA256).Hash.ToLower()
        if ($have -eq $want) {
            Write-Host ("  {0,-14} already present, hash OK" -f $dtaName)
            $skipped++; continue
        }
        Write-Host ("  {0,-14} present but hash differs - refetching" -f $dtaName)
    }

    $dir = Get-PufDirectory $stem
    $url = "https://meps.ahrq.gov/mepsweb/data_files/pufs/$dir/${stem}dta.zip"
    $zip = Join-Path $zipDir "$stem.zip"

    try {
        Invoke-WebRequest -Uri $url -OutFile $zip -TimeoutSec 1800 -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $DataDir -Force

        # Archives occasionally differ in filename case from the manifest.
        if (-not (Test-Path $dest)) {
            $found = Get-ChildItem $DataDir -Filter "$stem.*" -File |
                     Where-Object { $_.Extension -ieq '.dta' } | Select-Object -First 1
            if ($found -and $found.Name -cne $dtaName) {
                Rename-Item $found.FullName -NewName $dtaName -Force
            }
        }
        if (-not (Test-Path $dest)) { throw "archive did not yield $dtaName" }

        $have = (Get-FileHash -Path $dest -Algorithm SHA256).Hash.ToLower()
        if ($have -eq $want) {
            Write-Host ("  {0,-14} downloaded, SHA-256 MATCH" -f $dtaName) -ForegroundColor Green
            $ok++
        } else {
            Write-Host ("  {0,-14} SHA-256 MISMATCH" -f $dtaName) -ForegroundColor Red
            Write-Host ("      expected $want")
            Write-Host ("      actual   $have")
            $failed++; $problems += $dtaName
        }
    }
    catch {
        Write-Host ("  {0,-14} FAILED: {1}" -f $dtaName, $_.Exception.Message) -ForegroundColor Red
        $failed++; $problems += $dtaName
    }
    finally {
        if (-not $KeepZips -and (Test-Path $zip)) { Remove-Item $zip -Force }
    }
}

if (-not $KeepZips) { Remove-Item $zipDir -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host "`n----------------------------------------"
Write-Host "verified this run : $ok"
Write-Host "already present   : $skipped"
Write-Host "failed            : $failed"
if ($problems.Count) { Write-Host "problem files     : $($problems -join ', ')" }

if ($failed -eq 0) {
    Write-Host "`nAll input files match the recorded manifest." -ForegroundColor Green
    Write-Host "Now run:  python analysis\meps_analysis.py --data-dir `"$DataDir`" ..."
    exit 0
} else {
    Write-Host "`nSome files could not be verified. AHRQ occasionally reposts a PUF," -ForegroundColor Yellow
    Write-Host "which changes its hash without changing the released data. If a mismatch"
    Write-Host "persists, compare record counts and key variable distributions rather than"
    Write-Host "raw hashes before concluding anything is wrong."
    exit 1
}
