# Project-local CMake/Ninja build using the official Microsoft compiler and SDK.
# Requires Flutter's generated_config.cmake and generated plugin registrants.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$msvc = Join-Path $root '.tools\msvc\VC\Tools\MSVC\14.44.35207'
$kits = Join-Path $root '.tools\windows-sdk\Windows Kits\10'
$version = '10.0.26100.0'
$env:Path = "$msvc\bin\Hostx64\x64;$kits\bin\$version\x64;$root\.venv\Scripts;C:\Program Files\Git\cmd;" + $env:Path
$env:INCLUDE = "$msvc\include;$kits\Include\$version\ucrt;$kits\Include\$version\um;$kits\Include\$version\shared;$kits\Include\$version\winrt"
$env:LIB = "$msvc\lib\x64;$kits\Lib\$version\ucrt\x64;$kits\Lib\$version\um\x64"
$env:DASH__SUPPRESS_ANALYTICS = 'true'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:PUB_CACHE = Join-Path $root '.tools\pub-cache'
$env:JAIN_FLUTTER_CONFIG_DIR = Join-Path $root '.tools\flutter-state'
$cmake = Join-Path $root '.venv\Scripts\cmake.exe'
$source = Join-Path $root 'admin_app\windows'
$build = Join-Path $root 'admin_app\build\windows\local'
Push-Location "$root\admin_app"
try {
    & "$PSScriptRoot\flutter-local.ps1" assemble --output=build '-dTargetPlatform=windows-x64' '-dBuildMode=release' '-dTargetFile=lib/main.dart' '--DartDefines=QVBJX0JBU0VfVVJMPWh0dHA6Ly8xMjcuMC4wLjE6ODAwMA==' '-dTreeShakeIcons=true' '-dTrackWidgetCreation=false' release_bundle_windows-x64_assets
    if ($LASTEXITCODE -ne 0) { throw 'Windows Flutter asset compilation failed' }
} finally { Pop-Location }
& $cmake -S $source -B $build -G Ninja '-DCMAKE_BUILD_TYPE=Release' '-DCMAKE_CXX_COMPILER=cl.exe' '-DCMAKE_RC_COMPILER=rc.exe' '-DCMAKE_MT=mt.exe' '-DCMAKE_POLICY_DEFAULT_CMP0141=NEW' '-DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT=Embedded' '-DCMAKE_TRY_COMPILE_CONFIGURATION=Release' '-DFLUTTER_TARGET_PLATFORM=windows-x64' "-DCMAKE_INSTALL_PREFIX=$build\runner"
if ($LASTEXITCODE -ne 0) { throw 'Windows CMake configuration failed' }
& $cmake --build $build --target install --parallel 4
if ($LASTEXITCODE -ne 0) { throw 'Windows native build failed' }
