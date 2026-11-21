<#
.SYNOPSIS
    Wipe POS database and re-seed with the standard basic demo dataset
    (accounts, Store/Bodega shelves, 12 UOMs, sample hardware products & stock,
    suppliers, and contractor customer) while keeping tunnel/gateway.env intact.

.EXAMPLE
    .\scripts\reset-seeded-demo.ps1
#>

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host "=== 1/2 Wiping POS DB volume & restarting stack + tunnel (auto-migrates & seeds demo) ===" -ForegroundColor Cyan
docker compose --profile tunnel down -v
& (Join-Path $PSScriptRoot 'start-tunnel.ps1')

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

Write-Host ""
Write-Host "Done! Seeded demo POS is ready (password: demo1234 -> admin, manager, stocker, cashier, checker, cpms_service)." -ForegroundColor Green
Write-Host "Next: run C:\cpms\scripts\reset-seeded-demo-vps.ps1 on your Contabo VPS to seed CPMS too." -ForegroundColor Yellow
