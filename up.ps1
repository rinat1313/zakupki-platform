# Запуск платформы на Windows (Docker Desktop).
# Требуется: Docker Desktop, sibling-репозитории рядом с zakupki-platform.
#
# Примеры:
#   .\up.ps1 -Ai
#   .\up.ps1 -Down
#   .\up.ps1 -Ai -NoBuild
#
# LM Studio поднимайте сами (Server :1234). Endpoints:
#   ..\analizator_zakupok\configs\lm_studio.yaml
# Скрипт НЕ стартует lms CLI и НЕ прописывает IP.

param(
  [switch]$Ai,
  [switch]$Full,
  [switch]$Down,
  [switch]$Logs,
  [switch]$Health,
  [switch]$NoBuild,
  [switch]$FromSource
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

function Resolve-Repo([string]$Name, [string]$EnvName) {
  $envVal = [Environment]::GetEnvironmentVariable($EnvName)
  if ($envVal -and (Test-Path $envVal)) { return (Resolve-Path $envVal).Path }
  $def = Join-Path (Split-Path $Root -Parent) $Name
  if (Test-Path $def) { return (Resolve-Path $def).Path }
  return $null
}

$env:CORE_PATH = Resolve-Repo "zakupki-core" "CORE_PATH"
$env:PARSER_PATH = Resolve-Repo "zakupki-parser" "PARSER_PATH"
$env:GATEWAY_PATH = Resolve-Repo "zakupki-gateway" "GATEWAY_PATH"
$env:CUSTOMER_PATH = Resolve-Repo "zakupki-customer" "CUSTOMER_PATH"
$env:ANALIZATOR_PATH = Resolve-Repo "analizator_zakupok" "ANALIZATOR_PATH"

$need = @("CORE_PATH", "PARSER_PATH", "GATEWAY_PATH", "CUSTOMER_PATH")
if ($Ai -or $Full) { $need += "ANALIZATOR_PATH" }
foreach ($n in $need) {
  $p = [Environment]::GetEnvironmentVariable($n)
  if (-not $p -or -not (Test-Path $p)) {
    Write-Error "Не найден репозиторий $n (ожидается sibling рядом с zakupki-platform)"
  }
  Write-Host "OK  $n = $p"
}

try { docker info | Out-Null } catch {
  Write-Error "Docker не запущен. Запустите Docker Desktop."
}

$composeFiles = @("-f", "docker-compose.yml")
if ((Test-Path "docker-compose.runtime.yml") -and -not $FromSource) {
  $composeFiles += @("-f", "docker-compose.runtime.yml")
}

function Invoke-Compose {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
  & docker compose @composeFiles @Args
}

if ($Down) {
  $downFiles = @("-f", "docker-compose.yml")
  if (Test-Path "docker-compose.runtime.yml") { $downFiles += @("-f", "docker-compose.runtime.yml") }
  if (Test-Path "docker-compose.analizator-lan.yml") { $downFiles += @("-f", "docker-compose.analizator-lan.yml") }
  & docker compose @downFiles --profile ai --profile redis --profile kafka down
  Write-Host "stopped"
  exit 0
}
if ($Logs) {
  Invoke-Compose logs -f --tail=200
  exit 0
}
if ($Health) {
  & "$Root\scripts\health.sh"
  exit 0
}

$mode = "default"
if ($Full) { $mode = "full" }
elseif ($Ai) { $mode = "ai" }

if ($mode -eq "ai" -or $mode -eq "full") {
  if (-not $env:ANALIZATOR_URL) { $env:ANALIZATOR_URL = "http://analizator:8088" }
  $yaml = Join-Path $env:ANALIZATOR_PATH "configs\lm_studio.yaml"
  if (Test-Path $yaml) {
    $first = python -c @"
import re
from pathlib import Path
t = Path(r'$($yaml -replace '\\','/')').read_text(encoding='utf-8')
for line in t.splitlines():
    s = line.strip()
    if not s or s.startswith('#'): continue
    m = re.match(r'-\s*base_url:\s*(https?://\S+)', s)
    if m:
        print(m.group(1).rstrip('/')); break
"@
    if ($first -and $first -like "http*") {
      $env:LM_STUDIO_BASE_URL = $first.Trim()
      Write-Host "OK  LM_STUDIO_BASE_URL <- yaml: $($env:LM_STUDIO_BASE_URL)"
    }
  }
  if (-not $env:LM_STUDIO_BASE_URL) { $env:LM_STUDIO_BASE_URL = "http://host.docker.internal:1234/v1" }
  if (-not $env:LM_STUDIO_API_KEY) { $env:LM_STUDIO_API_KEY = "lm-studio" }
  if (-not $env:LM_STUDIO_MODEL) { $env:LM_STUDIO_MODEL = "qwen/qwen3-8b" }
  Write-Host "OK  skip автостарт LM Studio — проверьте yaml и что LMS Server уже запущен"
}

# Go bins for Linux containers (Docker Desktop on Windows = linux)
$goarch = "amd64"
$uname = ""
try { $uname = (docker version --format '{{.Server.Arch}}' 2>$null) } catch {}
if ($uname -match "arm") { $goarch = "arm64" }

function Build-Bin([string]$RepoPath, [string]$OutRel, [string]$Pkg) {
  Push-Location $RepoPath
  try {
    $env:CGO_ENABLED = "0"
    $env:GOOS = "linux"
    $env:GOARCH = $goarch
    New-Item -ItemType Directory -Force -Path (Split-Path $OutRel) | Out-Null
    go build -o $OutRel $Pkg
  } finally { Pop-Location }
}

if (-not $NoBuild -and -not $FromSource) {
  Write-Host "→ собираю Go-бинарники (linux/$goarch)…"
  Build-Bin $env:CORE_PATH "bin/core" "./cmd/core"
  Build-Bin $env:PARSER_PATH "bin/parser-service" "./cmd/parser-service"
  Build-Bin $env:GATEWAY_PATH "bin/gateway" "./cmd/gateway"
  Build-Bin $env:CUSTOMER_PATH "bin/customer" "./cmd/customer"
  if ($mode -eq "ai" -or $mode -eq "full") {
    Build-Bin $env:ANALIZATOR_PATH "bin/analizator" "./cmd/analizator"
  }
  Write-Host "OK  GOOS=linux GOARCH=$goarch"
}

$profiles = @()
if ($mode -eq "ai") { $profiles = @("--profile", "ai") }
if ($mode -eq "full") { $profiles = @("--profile", "ai", "--profile", "redis", "--profile", "kafka") }

$upArgs = @("up", "-d", "--remove-orphans")
if (-not $NoBuild) { $upArgs += "--build" }

Write-Host "→ поднимаю контейнеры ($mode)…"
& docker compose @composeFiles @profiles @upArgs

if ($mode -eq "ai" -or $mode -eq "full") {
  Write-Host "→ force-recreate analizator…"
  & docker compose @composeFiles --profile ai up -d --force-recreate --no-deps analizator
}

Write-Host ""
Write-Host "Готово."
Write-Host "  UI:          http://localhost:3000"
Write-Host "  Core:        http://localhost:8080/api/v1/health"
Write-Host "  Analizator:  http://localhost:8088/health"
Write-Host "  LM pool:     curl http://127.0.0.1:8088/api/v1/lm/pool"
Write-Host "Остановить:   .\up.ps1 -Down"
