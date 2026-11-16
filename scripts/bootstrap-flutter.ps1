param([string]$Flutter = 'flutter')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
foreach ($entry in @(@('customer_app','android','jain_customer'), @('admin_app','windows','jain_admin'))) {
    Push-Location (Join-Path $root $entry[0])
    try {
        & $Flutter create --platforms=$($entry[1]) --project-name $entry[2] --org in.jainconsultancy --no-pub .
        if ($LASTEXITCODE -ne 0) { throw 'Flutter platform generation failed' }
        # Remove generated counter-app test; repository tests cover the real foundation.
        $counterTest = Join-Path (Get-Location) 'test\widget_test.dart'
        if (Test-Path -LiteralPath $counterTest) { Remove-Item -LiteralPath $counterTest }
        & $Flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed' }
        & $Flutter analyze
        if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed' }
        & $Flutter test
        if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed' }
    } finally { Pop-Location }
}
