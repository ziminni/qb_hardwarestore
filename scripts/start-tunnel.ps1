# Share this POS with a CPMS on another computer through Cloudflare Tunnel
# (Named Tunnel with a permanent domain, or free Quick Tunnel).
# Only the tunnel gateway is exposed: CPMS sign-in plus the
# /api/v1/integration/cpms/ routes, and only with the secret gateway key.
#
# Usage (PowerShell, from anywhere):
#   .\scripts\start-tunnel.ps1
#   .\scripts\start-tunnel.ps1 -Token "<cloudflare-token>" -Hostname "pos-api.yourdomain.com"
# Stop:
#   docker compose --profile tunnel stop gateway cloudflared

param(
    [string]$Token = "",
    [string]$Hostname = "",
    [string]$GatewayKey = ""
)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

$KeyFile = "tunnel/gateway.env"
$KeyFilePath = Join-Path (Get-Location) $KeyFile

# Returns the value of NAME=value from the key file, or "" when the line is absent.
# (A missing line must not reach .Trim(): in Windows PowerShell 5.1 an empty
# pipeline result becomes an empty array, which has no Trim method.)
function Get-GatewaySetting([string]$Name) {
    if (-not (Test-Path $KeyFile)) { return "" }
    $line = Get-Content $KeyFile | Where-Object { $_ -like "$Name=*" } | Select-Object -First 1
    if ($null -eq $line) { return "" }
    return ($line.Substring($Name.Length + 1)).Trim()
}

$ExistingKey = Get-GatewaySetting "QB_GATEWAY_KEY"
$ExistingToken = Get-GatewaySetting "CLOUDFLARE_TUNNEL_TOKEN"
$ExistingHostname = Get-GatewaySetting "CLOUDFLARE_TUNNEL_HOSTNAME"

$FinalKey = if ($GatewayKey) { $GatewayKey.Trim() } elseif ($ExistingKey) { $ExistingKey } else {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    -join ($bytes | ForEach-Object { $_.ToString("x2") })
}
$FinalToken = if ($Token) { $Token.Trim() } else { $ExistingToken }
$FinalHostname = if ($Hostname) { $Hostname.Trim() } else { $ExistingHostname }

if (-not (Test-Path $KeyFile) -or $Token -or $Hostname -or $GatewayKey) {
    $lines = @("QB_GATEWAY_KEY=$FinalKey")
    if ($FinalToken) { $lines += "CLOUDFLARE_TUNNEL_TOKEN=$FinalToken" }
    if ($FinalHostname) { $lines += "CLOUDFLARE_TUNNEL_HOSTNAME=$FinalHostname" }
    # ASCII, no BOM: docker compose reads this file.
    [System.IO.File]::WriteAllText($KeyFilePath, (($lines -join "`n") + "`n"), [System.Text.Encoding]::ASCII)
    Write-Host "Saved $KeyFile."
}

$Key = $FinalKey
$Token = $FinalToken
$Hostname = $FinalHostname

# docker-compose.yml reads these to pick Named vs Quick Tunnel (the image has no shell).
if ($Token) {
    $env:CLOUDFLARE_TUNNEL_TOKEN = $Token
    $env:CLOUDFLARED_TUNNEL_ARGS = "run"
} else {
    Remove-Item Env:CLOUDFLARE_TUNNEL_TOKEN, Env:CLOUDFLARED_TUNNEL_ARGS -ErrorAction SilentlyContinue
}

# Recreate cloudflared so its log holds only this run's URL.
docker compose --profile tunnel up -d --force-recreate gateway cloudflared
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($Token) {
    $Url = if ($Hostname) { if ($Hostname -match "^https?://") { $Hostname } else { "https://$Hostname" } } else { "https://<your-named-tunnel-hostname>" }
} else {
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
$UrlNote = if ($Token) {
    "Named tunnel active: this URL stays fixed across restarts."
} else {
    "The URL changes every time a Quick Tunnel restarts."
}
Write-Host "Keep the key private. $UrlNote"
Write-Host "Stop:  docker compose --profile tunnel stop gateway cloudflared"
