$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$env:PYTHONPATH = Join-Path $root 'backend'
& "$root\.venv\Scripts\python.exe" -m uvicorn app.main:app --host 127.0.0.1 --port 8000
exit $LASTEXITCODE
