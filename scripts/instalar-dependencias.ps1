<#
.SYNOPSIS
    Instala todas las dependencias de desarrollo del proyecto Teatro de la Ciudad de Coatzacoalcos.
.DESCRIPTION
    Crea el entorno virtual Python en backend/.venv e instala backend/requirements.txt,
    instala los paquetes Node.js en frontend/ y opcionalmente descarga los navegadores de Playwright.
.EXAMPLE
    .\scripts\instalar-dependencias.ps1
    .\scripts\instalar-dependencias.ps1 -SoloBackend
    .\scripts\instalar-dependencias.ps1 -SoloFrontend -ConPlaywright
#>

[CmdletBinding()]
param(
    [switch]$SoloBackend,
    [switch]$SoloFrontend,
    [switch]$SinPlaywright,
    [switch]$TodosNavegadoresPlaywright
)

$ErrorActionPreference = 'Stop'

if ($SoloBackend -and $SoloFrontend) {
    Write-Error "No puedes usar -SoloBackend y -SoloFrontend al mismo tiempo."
    exit 1
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$BackendDir = Join-Path $RepoRoot "backend"
$FrontendDir = Join-Path $RepoRoot "frontend"
$VenvDir = Join-Path $BackendDir ".venv"
$RequirementsFile = Join-Path $BackendDir "requirements.txt"
$PackageJsonFile = Join-Path $FrontendDir "package.json"
$LockFile = Join-Path $FrontendDir "package-lock.json"

function Write-Step([string]$Mensaje) {
    Write-Host ""
    Write-Host "==> $Mensaje" -ForegroundColor Cyan
}

function Write-Warn([string]$Mensaje) {
    Write-Host "[AVISO] $Mensaje" -ForegroundColor Yellow
}

function Resolve-PythonCommand {
    # Prioriza Python 3.12+ mediante el launcher py de Windows si está disponible
    if (Get-Command py -ErrorAction SilentlyContinue) {
        foreach ($ver in @("-3.13", "-3.12")) {
            try {
                $out = & py $ver --version 2>$null
                if ($LASTEXITCODE -eq 0 -and $out) {
                    return @{ Exe = "py"; PrefixArgs = @($ver); Version = $out.Trim() }
                }
            } catch {}
        }
    }

    if (Get-Command python -ErrorAction SilentlyContinue) {
        $out = & python --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            return @{ Exe = "python"; PrefixArgs = @(); Version = "$out".Trim() }
        }
    }

    throw "No se encontró Python instalado. Instala Python 3.12+ (https://www.python.org/downloads/)."
}

Write-Host "==============================================================" -ForegroundColor Green
Write-Host " Instalador de dependencias - Teatro de la Ciudad Coatzacoalcos" -ForegroundColor Green
Write-Host " Raiz del proyecto: $RepoRoot" -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Green

# ------------------------------------------------------------------------------
# 1. Dependencias Backend (Python + pip + venv)
# ------------------------------------------------------------------------------
if (-not $SoloFrontend) {
    Write-Step "Verificando Python y preparando entorno virtual del Backend..."

    $pyCmd = Resolve-PythonCommand
    Write-Host "Python detectado: $($pyCmd.Version)"

    if ($pyCmd.Version -match 'Python\s+(\d+)\.(\d+)') {
        $major = [int]$Matches[1]
        $minor = [int]$Matches[2]
        if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 12)) {
            Write-Warn "El stack oficial recomienda Python 3.12+ (detectado $($pyCmd.Version)). Se continuará, pero usa Python 3.12+ o Docker Compose para paridad con producción."
        }
    }

    if (-not (Test-Path -LiteralPath $RequirementsFile)) {
        throw "No se encontró $RequirementsFile"
    }

    $reqContent = (Get-Content -LiteralPath $RequirementsFile -Raw)
    if ([string]::IsNullOrWhiteSpace($reqContent)) {
        throw "$RequirementsFile está vacío. No hay dependencias declaradas para instalar."
    }

    if (-not (Test-Path -LiteralPath $VenvDir)) {
        Write-Host "Creando entorno virtual en backend\.venv..."
        & $pyCmd.Exe @($pyCmd.PrefixArgs) -m venv $VenvDir
        if ($LASTEXITCODE -ne 0) { throw "Falló la creación del entorno virtual." }
    } else {
        Write-Host "Entorno virtual existente encontrado en backend\.venv."
    }

    $VenvPython = Join-Path $VenvDir "Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $VenvPython)) {
        throw "No se encontró el intérprete del entorno virtual en $VenvPython"
    }

    Write-Step "Actualizando pip e instalando dependencias de backend/requirements.txt..."
    & $VenvPython -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { throw "Falló la actualización de pip." }

    & $VenvPython -m pip install -r $RequirementsFile
    if ($LASTEXITCODE -ne 0) { throw "Falló la instalación de dependencias de backend." }

    Write-Host "Dependencias del backend instaladas correctamente." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 2. Dependencias Frontend (Node.js + npm + Playwright)
# ------------------------------------------------------------------------------
if (-not $SoloBackend) {
    Write-Step "Verificando Node.js / npm e instalando dependencias del Frontend..."

    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        throw "No se encontró Node.js. Instala Node.js 22 LTS (https://nodejs.org/)."
    }
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw "No se encontró npm."
    }

    $nodeVer = (& node --version).Trim()
    $npmVer = (& npm --version).Trim()
    Write-Host "Node.js detectado: $nodeVer | npm: $npmVer"

    if ($nodeVer -match '^v(\d+)') {
        $nodeMajor = [int]$Matches[1]
        if ($nodeMajor -ne 22) {
            Write-Warn "El stack oficial recomienda Node.js 22 LTS (detectado $nodeVer)."
        }
    }

    if (-not (Test-Path -LiteralPath $PackageJsonFile)) {
        throw "No se encontró $PackageJsonFile"
    }

    $pkgContent = (Get-Content -LiteralPath $PackageJsonFile -Raw)
    if ([string]::IsNullOrWhiteSpace($pkgContent)) {
        throw "$PackageJsonFile está vacío. No hay dependencias declaradas para instalar."
    }

    Push-Location $FrontendDir
    try {
        $useCi = $false
        if (Test-Path -LiteralPath $LockFile) {
            $lockLength = (Get-Item -LiteralPath $LockFile).Length
            if ($lockLength -gt 0) {
                $useCi = $true
            }
        }

        if ($useCi) {
            Write-Host "package-lock.json detectado: ejecutando npm ci..."
            & npm ci
        } else {
            Write-Host "Ejecutando npm install (generará/actualizará package-lock.json)..."
            & npm install
        }
        if ($LASTEXITCODE -ne 0) { throw "Falló la instalación de paquetes npm." }

        if (-not $SinPlaywright) {
            Write-Step "Instalando navegadores para Playwright E2E..."
            if ($TodosNavegadoresPlaywright) {
                & npx playwright install
            } else {
                & npx playwright install chromium
            }
            if ($LASTEXITCODE -ne 0) {
                Write-Warn "No se pudieron instalar los navegadores de Playwright. Puedes reintentar manualmente con 'cd frontend && npx playwright install chromium'."
            }
        }
    }
    finally {
        Pop-Location
    }

    Write-Host "Dependencias del frontend instaladas correctamente." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 3. Verificación informativa de Docker / Servicios locales
# ------------------------------------------------------------------------------
Write-Step "Verificando herramientas complementarias..."
if (Get-Command docker -ErrorAction SilentlyContinue) {
    $dockerVer = (& docker --version).Trim()
    Write-Host "Docker detectado: $dockerVer"
    Write-Host "Tip: cuando docker-compose.yml esté configurado, levanta PostgreSQL, Redis y Mailpit con: docker compose up -d"
} else {
    Write-Warn "Docker no está instalado o no está en el PATH. Será necesario para levantar PostgreSQL (btree_gist), Redis y Mailpit localmente."
}

Write-Host ""
Write-Host "Instalación finalizada con éxito." -ForegroundColor Green
if (-not $SoloFrontend) {
    Write-Host "Para activar el entorno virtual del backend en PowerShell:" -ForegroundColor Gray
    Write-Host "  .\backend\.venv\Scripts\Activate.ps1" -ForegroundColor White
}
