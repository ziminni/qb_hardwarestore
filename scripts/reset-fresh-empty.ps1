<#
.SYNOPSIS
    Wipe POS database to a clean, empty testing state (zero products/sales/POs/requisitions)
    while keeping only the 6 standard accounts, Store/Bodega shelves, 12 standard UOMs,
    and 1 contractor customer (BuildRight Construction) for CPMS integration.

.EXAMPLE
    .\scripts\reset-fresh-empty.ps1 -LocalOnly -ConfirmReset
#>

param([switch]$LocalOnly, [switch]$ConfirmReset)

$ErrorActionPreference = 'Stop'
if (-not $ConfirmReset) {
    throw 'This deletes the POS database volume. Back it up first, then pass -ConfirmReset for a disposable presentation database only.'
}
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host "=== 1/4 Wiping POS DB volume & restarting stack ===" -ForegroundColor Cyan
docker compose --profile tunnel down -v
if ($LASTEXITCODE -ne 0) { throw 'Could not reset the POS database volume.' }
if ($LocalOnly) {
    docker compose up -d --build backend
    if ($LASTEXITCODE -ne 0) { throw 'POS backend did not start.' }
} else {
    & (Join-Path $PSScriptRoot 'start-tunnel.ps1')
}

Write-Host "=== 2/4 Waiting for backend migrations & startup to finish ===" -ForegroundColor Cyan
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri 'http://127.0.0.1:8000/api/health/' -UseBasicParsing -TimeoutSec 2
        if ($resp.StatusCode -eq 200) { $ready = $true; break }
    } catch {}
    Start-Sleep 2
}
if (-not $ready) { throw "Backend did not become healthy on http://127.0.0.1:8000/api/health/ within 120s." }

Write-Host "=== 3/4 Flushing demo rows ===" -ForegroundColor Cyan
docker compose exec -T backend python manage.py migrate --noinput
if ($LASTEXITCODE -ne 0) { throw 'POS migrations failed.' }
docker compose exec -T backend python manage.py flush --noinput
if ($LASTEXITCODE -ne 0) { throw 'POS database flush failed.' }

Write-Host "=== 4/4 Seeding clean accounts, Store/Bodega, 12 standard UOMs & contractor payer ===" -ForegroundColor Cyan
$py = @'
from django.contrib.auth.models import Group
from apps.users.models import User
from apps.pos.models import Customer
from apps.inventory.models import StorageLocation, UnitOfMeasure

StorageLocation.objects.update_or_create(name="Store", defaults={"is_bodega": False})
StorageLocation.objects.update_or_create(name="Bodega", defaults={"is_bodega": True})

uoms = [
    ("PC", "Piece", True),
    ("BAG", "Bag", True),
    ("BOX", "Box", True),
    ("PACK", "Pack", True),
    ("ROLL", "Roll", True),
    ("SHEET", "Sheet", True),
    ("KG", "Kilogram", False),
    ("G", "Gram", False),
    ("M", "Metre", False),
    ("CM", "Centimetre", False),
    ("L", "Litre", False),
    ("ML", "Millilitre", False),
]
for code, name, whole in uoms:
    UnitOfMeasure.objects.get_or_create(
        code=code, defaults={"name": name, "is_whole": whole}
    )

roles = [
    ("admin", "System Administrator", True),
    ("manager", "Store Manager", False),
    ("stocker", "Stock Manager", False),
    ("cashier", "Cashier", False),
    ("checker", "Bodega Checker", False),
    ("cpms_service", "CPMS Service", False),
]
for un, role, is_admin in roles:
    grp, _ = Group.objects.get_or_create(name=role)
    user = User.objects.create_user(
        username=un,
        email=f"{un}@buildpro.local",
        password="demo1234",
        full_name=role,
    )
    user.is_staff = is_admin
    user.is_superuser = is_admin
    user.save()
    user.groups.add(grp)

Customer.objects.get_or_create(
    name="Walk-in Customer",
    defaults={"customer_type": "WALK_IN"},
)
payer = Customer.objects.create(
    name="BuildRight Construction",
    customer_type="CONSTRUCTION_FIRM",
    contact_details="09170000000",
)
print(f"FRESH EMPTY POS READY (PAYER_ID={payer.id})")
'@

$py | docker compose exec -T backend python manage.py shell
if ($LASTEXITCODE -ne 0) { throw 'POS fresh seed failed.' }

Write-Host ""
Write-Host "Done! Accounts (password: demo1234): admin, manager, stocker, cashier, checker, cpms_service" -ForegroundColor Green
Write-Host "Next: run CPMS scripts\reset-presentation.ps1 -Mode Fresh -ConfirmReset in the Windows CPMS checkout." -ForegroundColor Yellow
