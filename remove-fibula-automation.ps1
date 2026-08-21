param(
    [string]$Root = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

function Write-Step($Message) {
    Write-Host "[Fibula cleanup] $Message" -ForegroundColor Cyan
}

$rootPath = (Resolve-Path $Root).Path

$targets = @(
    "modules\game_fibula_runemaker",
    "modules\game_fibula_autostack"
)

$existing = @()
foreach ($rel in $targets) {
    $full = Join-Path $rootPath $rel
    if (Test-Path $full) {
        $existing += [PSCustomObject]@{
            Relative = $rel
            Full = $full
        }
    }
}

if ($existing.Count -eq 0) {
    Write-Host "Rune Maker and AutoStack are already removed." -ForegroundColor Green
    exit 0
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path $rootPath "_disabled_modules_backup\$timestamp"
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

foreach ($item in $existing) {
    $name = Split-Path $item.Full -Leaf
    $backupDest = Join-Path $backupRoot $name

    Write-Step "Backing up $($item.Relative)"
    Copy-Item -Path $item.Full -Destination $backupDest -Recurse -Force

    Write-Step "Removing $($item.Relative)"
    Remove-Item -Path $item.Full -Recurse -Force
}

$failed = @()
foreach ($rel in $targets) {
    $full = Join-Path $rootPath $rel
    if (Test-Path $full) {
        $failed += $rel
    }
}

if ($failed.Count -gt 0) {
    throw "Removal failed for: $($failed -join ', ')"
}

Write-Host ""
Write-Host "Removed successfully:" -ForegroundColor Green
foreach ($rel in $targets) {
    Write-Host "  - $rel"
}

Write-Host ""
Write-Host "Backup saved to:" -ForegroundColor Yellow
Write-Host "  $backupRoot"
Write-Host ""
Write-Host "No C++ rebuild is required; restart the client." -ForegroundColor Green
