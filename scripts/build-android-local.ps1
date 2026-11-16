# Locally testable ARM64 debug APK. Use adb reverse to reach the host API over USB.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$jdk = Get-ChildItem -LiteralPath "$root\.tools\java" -Directory -Filter 'jdk*' | Select-Object -First 1
if ($null -eq $jdk) { throw 'Install the project-local JDK first' }
$env:JAVA_HOME = $jdk.FullName
$env:ANDROID_HOME = Join-Path $root '.tools\android-sdk'
$env:ANDROID_USER_HOME = Join-Path $root '.tools\android-user'
$env:GRADLE_USER_HOME = Join-Path $root '.tools\gradle'
New-Item -ItemType Directory -Path $env:ANDROID_USER_HOME -Force | Out-Null
Push-Location "$root\customer_app"
try {
    & "$PSScriptRoot\flutter-local.ps1" build apk --debug --no-pub --target-platform android-arm64 --dart-define=API_BASE_URL=http://127.0.0.1:8000 @args
    if ($LASTEXITCODE -ne 0) { throw 'Customer Android build failed' }
} finally { Pop-Location }
