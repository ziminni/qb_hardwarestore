<#
.SYNOPSIS
    Wipe POS database and re-seed with the standard basic demo dataset
    (accounts, Store/Bodega shelves, 12 UOMs, sample hardware products & stock,
    suppliers, and contractor customer) while keeping tunnel/gateway.env intact.

.EXAMPLE
    .\scripts\reset-seeded-demo.ps1 -LocalOnly -ConfirmReset
#>

param([switch]$LocalOnly, [switch]$ConfirmReset)

$ErrorActionPreference = 'Stop'
if (-not $ConfirmReset) {
    throw 'This deletes the POS database volume. Back it up first, then pass -ConfirmReset for a disposable presentation database only.'
}
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host "=== 1/2 Wiping POS DB volume & restarting stack ===" -ForegroundColor Cyan
docker compose --profile tunnel down -v
if ($LASTEXITCODE -ne 0) { throw 'Could not reset the POS database volume.' }
if ($LocalOnly) {
    docker compose up -d --build backend
    if ($LASTEXITCODE -ne 0) { throw 'POS backend did not start.' }
} else {
    & (Join-Path $PSScriptRoot 'start-tunnel.ps1')
}

Write-Host "=== 2/2 Waiting for backend migrations & seed_demo to finish ===" -ForegroundColor Cyan
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri 'http://127.0.0.1:8000/api/health/' -UseBasicParsing -TimeoutSec 2
        if ($resp.StatusCode -eq 200) {
            Write-Host $resp.Content
            $ready = $true
            break
        }
    } catch {}
    Start-Sleep 2
}
if (-not $ready) { throw "Backend did not become healthy on http://127.0.0.1:8000/api/health/ within 120s." }

# Startup only auto-seeds in debug mode. Explicitly seed an empty demo DB in either mode.
docker compose exec -T backend python manage.py seed_demo --if-empty
if ($LASTEXITCODE -ne 0) { throw 'POS demo seed failed.' }

Write-Host ""
Write-Host "Done! Seeded demo POS is ready (password: demo1234 -> admin, manager, stocker, cashier, checker, cpms_service)." -ForegroundColor Green
Write-Host "Next: run CPMS scripts\reset-presentation.ps1 -Mode Demo -ConfirmReset in the Windows CPMS checkout." -ForegroundColor Yellow
