#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Instalador de dependencias — Teatro de la Ciudad de Coatzacoalcos
# Uso:
#   ./scripts/instalar-dependencias.sh
#   ./scripts/instalar-dependencias.sh --solo-backend
#   ./scripts/instalar-dependencias.sh --solo-frontend --sin-playwright
# ==============================================================================

SOLO_BACKEND=false
SOLO_FRONTEND=false
SIN_PLAYWRIGHT=false
TODOS_NAVEGADORES=false

for arg in "$@"; do
  case "$arg" in
    --solo-backend) SOLO_BACKEND=true ;;
    --solo-frontend) SOLO_FRONTEND=true ;;
    --sin-playwright) SIN_PLAYWRIGHT=true ;;
    --todos-navegadores) TODOS_NAVEGADORES=true ;;
    -h|--help)
      echo "Uso: $0 [--solo-backend | --solo-frontend] [--sin-playwright] [--todos-navegadores]"
      exit 0
      ;;
    *)
      echo "Opción desconocida: $arg" >&2
      exit 1
      ;;
  esac
done

if $SOLO_BACKEND && $SOLO_FRONTEND; then
  echo "Error: no puedes usar --solo-backend y --solo-frontend al mismo tiempo." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/backend"
FRONTEND_DIR="$REPO_ROOT/frontend"
VENV_DIR="$BACKEND_DIR/.venv"
REQUIREMENTS_FILE="$BACKEND_DIR/requirements.txt"
PACKAGE_JSON="$FRONTEND_DIR/package.json"
LOCK_FILE="$FRONTEND_DIR/package-lock.json"

echo "=============================================================="
echo " Instalador de dependencias - Teatro de la Ciudad Coatzacoalcos"
echo " Raíz del proyecto: $REPO_ROOT"
echo "=============================================================="

# ------------------------------------------------------------------------------
# 1. Dependencias Backend
# ------------------------------------------------------------------------------
if ! $SOLO_FRONTEND; then
  echo ""
  echo "==> Verificando Python y preparando entorno virtual del Backend..."

  PYTHON_BIN=""
  for candidate in python3.12 python3.13 python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
      PYTHON_BIN="$candidate"
      break
    fi
  done

  if [ -z "$PYTHON_BIN" ]; then
    echo "Error: no se encontró Python 3 instalado. Instala Python 3.12+." >&2
    exit 1
  fi

  PY_VER="$($PYTHON_BIN --version 2>&1)"
  echo "Python detectado: $PY_VER ($PYTHON_BIN)"

  if [[ "$PY_VER" =~ Python\ ([0-9]+)\.([0-9]+) ]]; then
    PY_MAJ="${BASH_REMATCH[1]}"
    PY_MIN="${BASH_REMATCH[2]}"
    if [ "$PY_MAJ" -lt 3 ] || { [ "$PY_MAJ" -eq 3 ] && [ "$PY_MIN" -lt 12 ]; }; then
      echo "[AVISO] El stack oficial recomienda Python 3.12+ (detectado $PY_VER)."
    fi
  fi

  if [ ! -s "$REQUIREMENTS_FILE" ]; then
    echo "Error: $REQUIREMENTS_FILE no existe o está vacío." >&2
    exit 1
  fi

  if [ ! -d "$VENV_DIR" ]; then
    echo "Creando entorno virtual en backend/.venv..."
    "$PYTHON_BIN" -m venv "$VENV_DIR"
  else
    echo "Entorno virtual existente encontrado en backend/.venv."
  fi

  echo "==> Actualizando pip e instalando dependencias de backend/requirements.txt..."
  "$VENV_DIR/bin/python" -m pip install --upgrade pip
  "$VENV_DIR/bin/python" -m pip install -r "$REQUIREMENTS_FILE"
  echo "Dependencias del backend instaladas correctamente."
fi

# ------------------------------------------------------------------------------
# 2. Dependencias Frontend
# ------------------------------------------------------------------------------
if ! $SOLO_BACKEND; then
  echo ""
  echo "==> Verificando Node.js / npm e instalando dependencias del Frontend..."

  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "Error: se requiere Node.js 22 LTS y npm." >&2
    exit 1
  fi

  NODE_VER="$(node --version)"
  NPM_VER="$(npm --version)"
  echo "Node.js detectado: $NODE_VER | npm: $NPM_VER"

  if [[ "$NODE_VER" =~ ^v([0-9]+) ]] && [ "${BASH_REMATCH[1]}" -ne 22 ]; then
    echo "[AVISO] El stack oficial recomienda Node.js 22 LTS (detectado $NODE_VER)."
  fi

  if [ ! -s "$PACKAGE_JSON" ]; then
    echo "Error: $PACKAGE_JSON no existe o está vacío." >&2
    exit 1
  fi

  pushd "$FRONTEND_DIR" >/dev/null
  if [ -s "$LOCK_FILE" ]; then
    echo "package-lock.json detectado: ejecutando npm ci..."
    npm ci
  else
    echo "Ejecutando npm install (generará/actualizará package-lock.json)..."
    npm install
  fi

  if ! $SIN_PLAYWRIGHT; then
    echo "==> Instalando navegadores para Playwright E2E..."
    if $TODOS_NAVEGADORES; then
      npx playwright install || echo "[AVISO] Falló la descarga de navegadores Playwright."
    else
      npx playwright install chromium || echo "[AVISO] Falló la descarga de Chromium para Playwright."
    fi
  fi
  popd >/dev/null

  echo "Dependencias del frontend instaladas correctamente."
fi

# ------------------------------------------------------------------------------
# 3. Verificación de Docker
# ------------------------------------------------------------------------------
echo ""
echo "==> Verificando herramientas complementarias..."
if command -v docker >/dev/null 2>&1; then
  echo "Docker detectado: $(docker --version)"
else
  echo "[AVISO] Docker no está instalado o no está en PATH."
fi

echo ""
echo "Instalación finalizada con éxito."
if ! $SOLO_FRONTEND; then
  echo "Para activar el entorno virtual del backend:"
  echo "  source backend/.venv/bin/activate"
fi
