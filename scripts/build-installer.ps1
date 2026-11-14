# Bouwt bigscreen-host en maakt de Windows-installer.
# Nodig: Visual Studio 2022 (C++), CMake, Ninja, Qt 6.8+ (msvc2022_64), vcpkg, Inno Setup 6.
# Gebruik:  .\scripts\build-installer.ps1 -QtDir C:\Qt\6.8.3\msvc2022_64 -VcpkgRoot C:\vcpkg
param(
    [Parameter(Mandatory)] [string]$QtDir,
    [Parameter(Mandatory)] [string]$VcpkgRoot,
    [string]$Version = "6.8.2"
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

# 1. Configureren + bouwen (uitvoeren vanuit een "x64 Native Tools" prompt of na vcvars64.bat)
cmake -B build -S . -G Ninja -DCMAKE_BUILD_TYPE=Release `
    "-DCMAKE_PREFIX_PATH=$QtDir" `
    "-DCMAKE_TOOLCHAIN_FILE=$VcpkgRoot\scripts\buildsystems\vcpkg.cmake" `
    -DVCPKG_TARGET_TRIPLET=x64-windows
if ($LASTEXITCODE) { throw "cmake configure mislukt" }
cmake --build build
if ($LASTEXITCODE) { throw "build mislukt" }

# 2. Installeren naar dist\ (exe + SDL3.dll)
if (Test-Path dist) { Remove-Item dist -Recurse -Force }
cmake --install build --prefix dist
if ($LASTEXITCODE) { throw "install mislukt" }

# 3. Qt-runtime erbij (DLL's, QML-modules, plugins, VC-runtime)
& "$QtDir\bin\windeployqt.exe" --release --qmldir qml --compiler-runtime dist\Kijkluister.exe
if ($LASTEXITCODE) { throw "windeployqt mislukt" }

# 3a. MPC-HC (clsid2/mpc-hc, GPL) voor films en series: nieuwste x64-uitgave, draagbaar
$mpcDir = Join-Path $root "build\mpc-hc"
if (-not (Test-Path "$mpcDir\mpc-hc64.exe")) {
    New-Item -ItemType Directory -Force $mpcDir | Out-Null
    $headers = @{ "User-Agent" = "Kijkluister-build" }
    if ($env:GITHUB_TOKEN) { $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN" }
    $rel = Invoke-RestMethod -Headers $headers "https://api.github.com/repos/clsid2/mpc-hc/releases/latest"
    $asset = $rel.assets | Where-Object { $_.name -match 'x64\.(zip|7z)$' -and $_.name -notmatch 'pdb|debug|installer|setup' } |
        Sort-Object { if ($_.name -like '*.zip') { 0 } else { 1 } } | Select-Object -First 1
    if (-not $asset) { throw "Geen MPC-HC x64-pakket gevonden in $($rel.tag_name): $(($rel.assets | ForEach-Object name) -join ', ')" }
    "MPC-HC $($rel.tag_name): $($asset.name)"
    $archive = Join-Path $mpcDir $asset.name
    Invoke-WebRequest -UseBasicParsing $asset.browser_download_url -OutFile $archive
    if ($asset.name -like '*.zip') { Expand-Archive $archive -DestinationPath "$mpcDir\unz" -Force }
    else { & 7z x -y "-o$mpcDir\unz" $archive | Out-Null }
    $exe = Get-ChildItem "$mpcDir\unz" -Recurse -Filter mpc-hc64.exe | Select-Object -First 1
    if (-not $exe) { throw "mpc-hc64.exe niet gevonden in $($asset.name)" }
    Copy-Item "$($exe.Directory.FullName)\*" $mpcDir -Recurse -Force
    Remove-Item "$mpcDir\unz" -Recurse -Force; Remove-Item $archive
}
New-Item -ItemType Directory -Force dist\mpc-hc | Out-Null
Copy-Item "$mpcDir\*" dist\mpc-hc\ -Recurse -Force
Get-ChildItem dist\mpc-hc | Select-Object -First 12 | ForEach-Object { "  mpc-hc\$($_.Name)" }

# 3b. ffmpeg (GPL-build van gyan.dev) voor het opnemen van live tv
$ffDir = Join-Path $root "build\ffmpeg"
if (-not (Test-Path "$ffDir\ffmpeg.exe")) {
    New-Item -ItemType Directory -Force $ffDir | Out-Null
    $zip = Join-Path $ffDir "ffmpeg.zip"
    Invoke-WebRequest -UseBasicParsing "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" -OutFile $zip
    Expand-Archive $zip -DestinationPath "$ffDir\unz" -Force
    $exe = Get-ChildItem "$ffDir\unz" -Recurse -Filter ffmpeg.exe | Select-Object -First 1
    Copy-Item $exe.FullName "$ffDir\ffmpeg.exe"
    $lic = Get-ChildItem $exe.Directory.Parent.FullName -Filter LICENSE* | Select-Object -First 1
    if ($lic) { Copy-Item $lic.FullName "$ffDir\LICENSE-ffmpeg.txt" }
    Remove-Item "$ffDir\unz" -Recurse -Force; Remove-Item $zip
}
New-Item -ItemType Directory -Force dist\ffmpeg | Out-Null
Copy-Item "$ffDir\ffmpeg.exe" dist\ffmpeg\
if (Test-Path "$ffDir\LICENSE-ffmpeg.txt") { Copy-Item "$ffDir\LICENSE-ffmpeg.txt" dist\ffmpeg\ }
& dist\ffmpeg\ffmpeg.exe -version | Select-Object -First 1

# 4. Installer
$iscc = (Get-Command iscc -ErrorAction SilentlyContinue).Source
if (-not $iscc) { $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
& $iscc "/DAppVersion=$Version" installer\bigscreen-host.iss
if ($LASTEXITCODE) { throw "Inno Setup mislukt" }
Write-Host "Klaar: out\Kijkluister-$Version-x64-setup.exe"
