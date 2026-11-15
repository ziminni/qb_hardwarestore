# Share this POS with a CPMS on another computer through a free Cloudflare Quick
# Tunnel. Only the tunnel gateway is exposed: CPMS sign-in plus the
# /api/v1/integration/cpms/ routes, and only with the secret gateway key.
#
# Usage (PowerShell, from anywhere):  .\scripts\start-tunnel.ps1
# Stop:  docker compose --profile tunnel stop gateway cloudflared

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

$KeyFile = "tunnel/gateway.env"
if (-not (Test-Path $KeyFile)) {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $newKey = -join ($bytes | ForEach-Object { $_.ToString("x2") })
    # ASCII, no BOM: docker compose reads this file.
    [System.IO.File]::WriteAllText((Join-Path (Get-Location) $KeyFile), "QB_GATEWAY_KEY=$newKey`n", [System.Text.Encoding]::ASCII)
    Write-Host "Created $KeyFile with a new gateway key."
}
$Key = ((Get-Content $KeyFile | Where-Object { $_ -like "QB_GATEWAY_KEY=*" }) -replace "^QB_GATEWAY_KEY=", "").Trim()

# Recreate cloudflared so its log holds only this run's URL.
docker compose --profile tunnel up -d --force-recreate gateway cloudflared
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Waiting for the tunnel URL..."
$Url = $null
for ($i = 0; $i -lt 60 -and -not $Url; $i++) {
    $logs = (docker compose logs cloudflared 2>&1) -join "`n"
    $found = [regex]::Matches($logs, "https://[a-z0-9-]+\.trycloudflare\.com")
    if ($found.Count -gt 0) { $Url = $found[$found.Count - 1].Value } else { Start-Sleep -Seconds 2 }
}
if (-not $Url) {
    Write-Error "No tunnel URL after 2 minutes. Check: docker compose logs cloudflared"
    exit 1
}

Write-Host ""
Write-Host "POS is reachable at $Url (gateway only)." -ForegroundColor Green
Write-Host ""
Write-Host "On the CPMS computer, put these lines in"
Write-Host "  qb_project_management_system\django-backend\.env"
Write-Host "then run  docker compose up -d  there:"
Write-Host ""
Write-Host "POS_API_BASE_URL=$Url"
Write-Host "POS_API_ALLOW_INSECURE_LOCAL=False"
Write-Host "POS_API_GATEWAY_HEADER_NAME=X-QB-Gateway-Key"
Write-Host "POS_API_GATEWAY_HEADER_VALUE=$Key"
Write-Host ""
Write-Host "Keep the key private. The URL changes every time the tunnel restarts."
Write-Host "Stop:  docker compose --profile tunnel stop gateway cloudflared"
