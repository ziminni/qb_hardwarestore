Param(
    [int]$Port = 8000
)

$ErrorActionPreference = "Stop"
$TargetUrl = "http://localhost:$Port"

if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
    Write-Error "'cloudflared' is not installed or not in PATH. Install via: winget install Cloudflare.cloudflared"
    exit 1
}

Write-Host "Starting Cloudflare Quick Tunnel for POS backend at $TargetUrl ..." -ForegroundColor Cyan
Write-Host "Copy the generated https://<name>.trycloudflare.com URL into CPMS:" -ForegroundColor Yellow
Write-Host "  POS_API_BASE_URL=https://<name>.trycloudflare.com"
Write-Host "  POS_API_SERVICE_USERNAME=cpms_service"
Write-Host "  POS_API_SERVICE_PASSWORD=demo1234"
Write-Host ""

& cloudflared tunnel --url $TargetUrl
