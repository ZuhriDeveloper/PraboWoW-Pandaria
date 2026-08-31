<#
.SYNOPSIS
    Mengekstrak dbc/ maps/ vmaps/ mmaps/ dari client WoW 5.4.8 build 18414.

.DESCRIPTION
    Dijalankan di PC Windows yang punya client, BUKAN di VPS. Hasilnya
    (~20-25 GB) portable antar OS, jadi cukup di-rsync ke VPS Linux dengan
    scripts/sync-data.sh.

    Tahap mmaps adalah yang terlama (4-12 jam tergantung CPU). Mulai sedini
    mungkin -- ini bottleneck jadwal deployment.

    Prasyarat: tools sudah di-build dari repo core dengan TOOLS=ON.
      1. Copy skyfire-build.config.ps1.example -> skyfire-build.config.ps1
      2. Pastikan CMakeOptions.TOOLS = 'ON'
      3. Jalankan .\SkyFire-Build.ps1

.PARAMETER ClientPath
    Root folder client (yang berisi Wow.exe dan folder Data\).

.PARAMETER ToolsPath
    Folder berisi mapextractor.exe, vmap4extractor.exe, vmap4assembler.exe,
    mmaps_generator.exe.

.PARAMETER OutputPath
    Folder tujuan hasil ekstraksi.

.PARAMETER Steps
    Tahap yang dijalankan. Berguna untuk melanjutkan setelah gagal/terhenti.
    Default: semua.

.EXAMPLE
    .\scripts\extract-client-data.ps1 -ClientPath 'D:\WoW548' -ToolsPath 'C:\SkyFire_Files\Server\bin' -OutputPath 'D:\wow-extracted'

.EXAMPLE
    # Ulangi hanya mmaps setelah gagal di tengah jalan
    .\scripts\extract-client-data.ps1 -ClientPath 'D:\WoW548' -ToolsPath 'C:\SkyFire_Files\Server\bin' -OutputPath 'D:\wow-extracted' -Steps mmaps
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $ClientPath,
    [Parameter(Mandatory = $true)][string] $ToolsPath,
    [Parameter(Mandatory = $true)][string] $OutputPath,
    [ValidateSet('maps', 'vmaps', 'assemble', 'mmaps')]
    [string[]] $Steps = @('maps', 'vmaps', 'assemble', 'mmaps'),
    [int] $MmapThreads = 0
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Note($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

# --- Validasi ----------------------------------------------------------------
$ClientPath = (Resolve-Path -LiteralPath $ClientPath).Path.TrimEnd('\')
$ToolsPath = (Resolve-Path -LiteralPath $ToolsPath).Path.TrimEnd('\')

$dataDir = Join-Path $ClientPath 'Data'
if (-not (Test-Path (Join-Path $dataDir 'world.MPQ'))) {
    throw "Tidak menemukan '$dataDir\world.MPQ'. -ClientPath harus root client (folder berisi Wow.exe dan Data\)."
}

# mapextractor menyimpan path di buffer char[128] (map_extractor/System.cpp:62).
# Path panjang terpotong diam-diam dan menghasilkan ekstraksi gagal.
foreach ($p in @($ClientPath, $OutputPath)) {
    if ($p.Length -gt 100) {
        throw "Path terlalu panjang ($($p.Length) karakter): $p. Tool memakai buffer 128 byte; pakai path pendek seperti D:\wow548."
    }
}

$tools = @{
    maps     = Join-Path $ToolsPath 'mapextractor.exe'
    vmaps    = Join-Path $ToolsPath 'vmap4extractor.exe'
    assemble = Join-Path $ToolsPath 'vmap4assembler.exe'
    mmaps    = Join-Path $ToolsPath 'mmaps_generator.exe'
}
foreach ($step in $Steps) {
    if (-not (Test-Path $tools[$step])) {
        throw "Tool untuk tahap '$step' tidak ada: $($tools[$step]). Build ulang core dengan -DTOOLS=ON."
    }
}

New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
$OutputPath = (Resolve-Path -LiteralPath $OutputPath).Path.TrimEnd('\')

Write-Host "Client : $ClientPath"
Write-Host "Tools  : $ToolsPath"
Write-Host "Output : $OutputPath"
Write-Host "Tahap  : $($Steps -join ', ')"

$overallStart = Get-Date

function Invoke-Tool {
    param([string] $Exe, [string[]] $ToolArgs, [string] $WorkDir, [string] $Label)

    $start = Get-Date
    Write-Note "Menjalankan: $Exe $($ToolArgs -join ' ')"
    Write-Note "Working dir: $WorkDir"

    Push-Location $WorkDir
    try {
        & $Exe @ToolArgs
        if ($LASTEXITCODE -ne 0) {
            throw "$Label gagal dengan exit code $LASTEXITCODE."
        }
    }
    finally { Pop-Location }

    $elapsed = (Get-Date) - $start
    Write-Host "    Selesai dalam $([math]::Round($elapsed.TotalMinutes, 1)) menit." -ForegroundColor Green
}

# --- 1. dbc + maps + Cameras -------------------------------------------------
if ($Steps -contains 'maps') {
    Write-Step '1/4  mapextractor -> dbc/, maps/, Cameras/   (~20 menit, ~2 GB)'
    # -i memakai ROOT client: tool menambahkan "/Data/" sendiri
    # (map_extractor/System.cpp:1224).
    Invoke-Tool -Exe $tools.maps -WorkDir $OutputPath -Label 'mapextractor' -ToolArgs @('-i', $ClientPath, '-o', $OutputPath)
}

# --- 2. vmaps mentah ---------------------------------------------------------
if ($Steps -contains 'vmaps') {
    Write-Step '2/4  vmap4extractor -> Buildings/   (~30 menit)'

    # Tool menolak jalan kalau output dir sudah "kotor"
    # (vmapexport.cpp:534-547), jadi bersihkan dulu agar aman diulang.
    $buildings = Join-Path $OutputPath 'Buildings'
    if (Test-Path $buildings) {
        Write-Note 'Menghapus Buildings/ lama (tool menolak direktori tidak kosong).'
        Remove-Item -Recurse -Force $buildings
    }

    # BEDA dari mapextractor: -d memakai folder Data\ itu sendiri, bukan root
    # client (vmapexport.cpp:169 menyambung input_path + "world.MPQ").
    Invoke-Tool -Exe $tools.vmaps -WorkDir $OutputPath -Label 'vmap4extractor' -ToolArgs @('-d', "$dataDir\")
}

# --- 3. rakit vmaps ----------------------------------------------------------
if ($Steps -contains 'assemble') {
    Write-Step '3/4  vmap4assembler -> vmaps/   (~20 menit, ~4 GB)'
    Invoke-Tool -Exe $tools.assemble -WorkDir $OutputPath -Label 'vmap4assembler' -ToolArgs @('Buildings', 'vmaps')
}

# --- 4. mmaps (navmesh) ------------------------------------------------------
if ($Steps -contains 'mmaps') {
    Write-Step '4/4  mmaps_generator -> mmaps/   (4-12 JAM, ~12 GB)'

    foreach ($need in @('maps', 'vmaps')) {
        $p = Join-Path $OutputPath $need
        if (-not (Test-Path $p)) {
            throw "mmaps_generator butuh '$p'. Jalankan tahap sebelumnya dulu."
        }
    }

    Write-Note 'Tahap ini yang paling lama. Biarkan berjalan (mis. semalaman).'
    Write-Note 'Kalau terhenti, jalankan ulang dengan -Steps mmaps.'

    $mmapArgs = @()
    if ($MmapThreads -gt 0) { $mmapArgs += @('--threads', "$MmapThreads") }

    Invoke-Tool -Exe $tools.mmaps -WorkDir $OutputPath -Label 'mmaps_generator' -ToolArgs $mmapArgs
}

# --- Ringkasan ---------------------------------------------------------------
Write-Step 'Ringkasan'
$expected = @('dbc', 'maps', 'vmaps', 'mmaps')
$allOk = $true
foreach ($d in $expected) {
    $p = Join-Path $OutputPath $d
    if (Test-Path $p) {
        $files = Get-ChildItem -Recurse -File -LiteralPath $p
        $size = ($files | Measure-Object -Property Length -Sum).Sum
        $count = ($files | Measure-Object).Count
        Write-Host ('{0,-8} {1,8:N2} GB  {2,7:N0} file' -f $d, ($size / 1GB), $count)
    }
    else {
        Write-Host ('{0,-8} HILANG' -f $d) -ForegroundColor Red
        $allOk = $false
    }
}

$total = (Get-Date) - $overallStart
Write-Host "`nTotal waktu: $([math]::Round($total.TotalHours, 2)) jam"

if ($allOk) {
    Write-Host "`nSemua folder siap. Langkah berikutnya, dari Git Bash:" -ForegroundColor Green
    Write-Host "  ./scripts/sync-data.sh '$OutputPath'"
}
else {
    Write-Host "`nAda folder yang belum jadi. Jalankan ulang tahap yang kurang." -ForegroundColor Yellow
    exit 1
}
