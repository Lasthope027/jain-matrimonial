# Project-local Flutter launcher for this managed Windows environment.
# Uses offline packages and a local SDK state-path patch documented in validation.md.
$root = Split-Path $PSScriptRoot -Parent
$sdk = Join-Path $root '.tools\flutter'
$env:DASH__SUPPRESS_ANALYTICS = 'true'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:PUB_CACHE = Join-Path $root '.tools\pub-cache'
$env:JAIN_FLUTTER_CONFIG_DIR = Join-Path $root '.tools\flutter-state'
$env:Path = "C:\Program Files\Git\cmd;" + $env:Path
& "$sdk\bin\cache\dart-sdk\bin\dart.exe" "--packages=$sdk\packages\flutter_tools\.dart_tool\package_config.json" "$sdk\packages\flutter_tools\bin\flutter_tools.dart" --no-version-check @args
exit $LASTEXITCODE
