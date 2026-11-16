$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
# Foreground operation keeps the database alive in the managed terminal session.
& "$root\.tools\pgsql\bin\postgres.exe" -D "$root\.tools\pgdata" -h 127.0.0.1 -p 5432
exit $LASTEXITCODE
