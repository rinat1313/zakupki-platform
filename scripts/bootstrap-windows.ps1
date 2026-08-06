# Клонирует все sibling-репозитории и поднимает стек на Windows (Docker Desktop).
#
# PowerShell (от имени пользователя, Docker Desktop уже запущен):
#   irm https://raw.githubusercontent.com/rinat1313/zakupki-platform/cursor/ui-catalog-csv-7460/scripts/bootstrap-windows.ps1 | iex
#
# Или локально после clone:
#   .\scripts\bootstrap-windows.ps1
#   .\scripts\bootstrap-windows.ps1 -Root D:\work\platform -Branch cursor/ui-catalog-csv-7460 -Ai
param(
  [string]$Root = (Join-Path (Get-Location) "platform"),
  [string]$Org = "rinat1313",
  [string]$Branch = "cursor/ui-catalog-csv-7460",
  [switch]$Ai = $true,
  [switch]$SkipAi
)

$ErrorActionPreference = "Stop"

function Need-Cmd([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Нужен $Name в PATH"
  }
}

Need-Cmd git
Need-Cmd docker
try { docker info | Out-Null } catch { throw "Docker Desktop не запущен" }

# Go нужен для сборки linux-бинарников в up.ps1
if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
  Write-Warning "Go не найден. Установите Go 1.22+ (https://go.dev/dl/) и повторите, либо поставьте Go и снова запустите этот скрипт."
}

$repos = @(
  "zakupki-platform",
  "zakupki-core",
  "zakupki-gateway",
  "zakupki-parser",
  "zakupki-customer",
  "analizator_zakupok"
)

New-Item -ItemType Directory -Force -Path $Root | Out-Null
$Root = (Resolve-Path $Root).Path
Write-Host "=== bootstrap-windows ==="
Write-Host "root:   $Root"
Write-Host "branch: $Branch"

foreach ($name in $repos) {
  $path = Join-Path $Root $name
  $url = "https://github.com/$Org/$name.git"
  if (Test-Path (Join-Path $path ".git")) {
    Write-Host "exists $name"
    Push-Location $path
    git fetch origin --prune
  } else {
    Write-Host "clone  $name"
    git clone $url $path
    Push-Location $path
  }
  $remoteBranch = "origin/$Branch"
  $hasBranch = git rev-parse --verify --quiet $remoteBranch
  if ($LASTEXITCODE -eq 0) {
    git checkout -B $Branch $remoteBranch
    Write-Host "  OK  $name @ $Branch ($((git rev-parse --short HEAD)))"
  } else {
    git checkout main 2>$null
    if ($LASTEXITCODE -ne 0) { git checkout master 2>$null }
    Write-Host "  OK  $name @ $(git branch --show-current) (нет $Branch)"
  }
  Pop-Location
}

$platform = Join-Path $Root "zakupki-platform"
Set-Location $platform

if ($SkipAi) { $Ai = $false }

Write-Host "→ запуск стека..."
if ($Ai) {
  & "$platform\up.ps1" -Ai
} else {
  & "$platform\up.ps1"
}

Write-Host ""
Write-Host "Готово."
Write-Host "  UI:  http://localhost:3000"
Write-Host "  Для AI: запустите LM Studio (Server :1234), модель загружена."
Write-Host "  yaml: $Root\analizator_zakupok\configs\lm_studio.yaml"
Write-Host "  Стоп: cd $platform; .\up.ps1 -Down"
