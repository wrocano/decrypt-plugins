#!/bin/bash
# ─────────────────────────────────────────────────────────
# initPluginRepo.sh
# Inicializa el repositorio de distribución de plugins
#
# Requisitos previos:
#   1. Crear repo vacío en GitHub (ej: decrypt-plugins)
#   2. Crear Fine-Grained Token con permisos:
#      - Contents: Read and Write (para push desde CI)
#      - Metadata: Read-only
#   3. Ejecutar este script UNA vez
#
# Uso:
#   ./initPluginRepo.sh <github-user> <repo-name> [token]
#
# Ejemplo:
#   ./initPluginRepo.sh mi-usuario decrypt-plugins ghp_XXXX
# ─────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GITHUB_USER="${1:-}"
REPO_NAME="${2:-}"
TOKEN="${3:-}"

if [ -z "$GITHUB_USER" ] || [ -z "$REPO_NAME" ]; then
    echo "❌ Uso: $0 <github-user> <repo-name> [token]"
    echo ""
    echo "Ejemplo:"
    echo "  $0 mi-usuario decrypt-plugins"
    echo "  $0 mi-usuario decrypt-plugins ghp_XXXXXXXXXXXX"
    echo ""
    echo "Si no proporcionas token, se usará la URL HTTPS estándar"
    echo "(necesitarás autenticarte al hacer push)."
    exit 1
fi

echo "╔══════════════════════════════════════════════╗"
echo "║  Inicializando repo de plugins compilados    ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

cd "$SCRIPT_DIR"

# Verificar si ya está inicializado
if [ -d ".git" ]; then
    echo "⚠️  Ya existe un repo git aquí."
    echo "   Remote actual: $(git remote get-url origin 2>/dev/null || echo 'no configurado')"
    read -p "   ¿Reinicializar? (y/N): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "   Cancelado."
        exit 0
    fi
    rm -rf .git
fi

# Inicializar repo
git init
git branch -M main

# Configurar remote con o sin token
if [ -n "$TOKEN" ]; then
    REMOTE_URL="https://${TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"
    echo "  🔑 Remote configurado con token embebido"
else
    REMOTE_URL="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
    echo "  🔗 Remote configurado sin token (se pedirá auth al push)"
fi

git remote add origin "$REMOTE_URL"

# Crear estructura inicial
mkdir -p plugins
cat > .gitignore <<'EOF'
.DS_Store
*.tmp
EOF

cat > README.md <<EOF
# ${REPO_NAME}

Repositorio de distribución de plugins compilados para DEcrypt.

## Estructura

\`\`\`
├── registry.json      ← Catálogo auto-generado de plugins
├── plugins/           ← JARs compilados
│   ├── database-workbench-1.0.jar
│   └── ...
└── generateRegistry.sh
\`\`\`

## Uso

Este repositorio es gestionado automáticamente por el script \`compileAllPlugins\`
del proyecto DEcrypt. No editar manualmente.

## Acceso

Requiere un GitHub Fine-Grained Token con permiso \`Contents: Read-only\`
para descargar plugins desde la aplicación DEcrypt.
EOF

# Commit inicial
git add .
git commit -m "init: repositorio de distribución de plugins"

echo ""
echo "══════════════════════════════════════════════"
echo "  ✅ Repo inicializado en: $SCRIPT_DIR"
echo "  📡 Remote: https://github.com/${GITHUB_USER}/${REPO_NAME}"
echo ""
echo "  Próximo paso:"
echo "    1. Crea el repo '${REPO_NAME}' en GitHub (puede ser privado)"
echo "    2. Ejecuta:  git push -u origin main"
echo "    3. Compila plugins:  cd .. && ./compileAllPlugins"
echo "══════════════════════════════════════════════"
