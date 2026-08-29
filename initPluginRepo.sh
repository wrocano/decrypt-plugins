#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
# initPluginRepo.sh
# Inicializa el repositorio de distribución de plugins.
# Si el repo ya existe en GitHub, hace init + fetch para traer el historial
# y luego permite subir archivos locales como nueva versión.
#
# Uso:
#   ./initPluginRepo.sh                    (usa defaults: wrocano/decrypt-plugins)
#   ./initPluginRepo.sh <user> <repo>      (repo custom)
#   ./initPluginRepo.sh <user> <repo> <token>
# ═══════════════════════════════════════════════════════════════════════
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Defaults
GH_USER="${1:-wrocano}"
GH_REPO="${2:-decrypt-plugins}"
GH_TOKEN="${3:-}"
BRANCH="main"

# Construir URL del remote
if [ -n "$GH_TOKEN" ]; then
    REMOTE_URL="https://${GH_TOKEN}@github.com/${GH_USER}/${GH_REPO}.git"
else
    REMOTE_URL="https://github.com/${GH_USER}/${GH_REPO}.git"
fi

echo "╔══════════════════════════════════════════════════╗"
echo "║  Inicializar repositorio de plugins              ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  Repo:   ${GH_USER}/${GH_REPO}"
echo "  Branch: ${BRANCH}"
echo "  Dir:    ${SCRIPT_DIR}"
echo ""

# Si ya tiene .git, solo mostrar info
if [ -d "$SCRIPT_DIR/.git" ]; then
    CURRENT_REMOTE="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || echo "")"
    echo "  ℹ️  Repositorio ya inicializado."
    echo "  Remote: $CURRENT_REMOTE"
    echo "  Branch: $(git -C "$SCRIPT_DIR" branch --show-current 2>/dev/null)"
    echo ""
    echo "  Para forzar re-init: rm -rf .git && ./initPluginRepo.sh"
    exit 0
fi

# Init local
cd "$SCRIPT_DIR"
git init
git checkout -b "$BRANCH" 2>/dev/null || true
git remote add origin "$REMOTE_URL"

# Intentar traer historial existente
echo -n "  📥 Intentando traer historial del repo remoto... "
if git fetch origin "$BRANCH" 2>/dev/null; then
    echo "✅"
    # Hacer reset soft para que los archivos locales sean los "nuevos cambios"
    git reset --soft origin/"$BRANCH" 2>/dev/null || true
    git branch --set-upstream-to=origin/"$BRANCH" "$BRANCH" 2>/dev/null || true
    echo "  ✅ Historial importado. Archivos locales se subirán como nueva versión."
else
    echo "⚠️  No se pudo (repo nuevo o sin acceso)"
    echo "  ✅ Repositorio local inicializado como nuevo."
fi

# Crear .gitignore si no existe
if [ ! -f "$SCRIPT_DIR/.gitignore" ]; then
    cat > "$SCRIPT_DIR/.gitignore" <<'EOF'
.changed-plugins
*.tmp
.DS_Store
*.key
private*.pem
.signing/
EOF
    echo "  📄 .gitignore creado"
fi

# Crear README si no existe
if [ ! -f "$SCRIPT_DIR/README.md" ]; then
    cat > "$SCRIPT_DIR/README.md" <<EOF
# ${GH_REPO}

Repositorio de distribución de plugins compilados para DEcrypt.

## Estructura

\`\`\`
├── registry.json          ← Catálogo auto-generado
├── registry-signature.json ← Firma detached opcional del catálogo
├── plugins/               ← JARs de plugins
├── app/                   ← Distribución de la app
│   ├── app-release.json
│   └── DEcrypt.jar
├── generateRegistry.sh
└── initPluginRepo.sh
\`\`\`

## Configuración en DEcrypt

| Campo | Valor |
|-------|-------|
| Owner | \`${GH_USER}\` |
| Repo | \`${GH_REPO}\` |
| Branch | \`${BRANCH}\` |
| Registry Path | \`registry.json\` |
| Registry Signature Path | \`registry-signature.json\` |

La firma opcional se activa al ejecutar \`generateRegistry.sh\` con
\`PLUGIN_SIGNING_PRIVATE_KEY\`, \`PLUGIN_PUBLISHER_ID\`,
\`PLUGIN_SIGNING_KEY_ID\` y \`PLUGIN_SIGNATURE_ALGORITHM\`. La clave privada
debe permanecer fuera de este repositorio.
EOF
    echo "  📄 README.md creado"
fi

echo ""

# Regenerar registry si hay plugins
if [ -d "$SCRIPT_DIR/plugins" ] && ls "$SCRIPT_DIR/plugins/"*.jar 1>/dev/null 2>&1; then
    echo "── Regenerando registry.json ──"
    if [ -f "$SCRIPT_DIR/generateRegistry.sh" ]; then
        bash "$SCRIPT_DIR/generateRegistry.sh"
    fi
    echo ""
fi

# Commit y push
git add -A
if ! git diff --cached --quiet 2>/dev/null; then
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    git commit -m "init: repositorio de plugins - $TIMESTAMP"
    echo ""
    echo -n "  📤 Push a origin/$BRANCH... "
    if git push -u origin "$BRANCH" 2>/dev/null; then
        echo "✅"
    else
        if git push --force -u origin "$BRANCH" 2>/dev/null; then
            echo "✅ (force push)"
        else
            echo ""
            echo "  ⚠️  Push falló. Posibles causas:"
            echo "     - Sin permisos de escritura en el repo"
            echo "     - Configurar: git remote set-url origin https://<TOKEN>@github.com/${GH_USER}/${GH_REPO}.git"
            echo ""
            echo "  Para reintentar: git push -u origin $BRANCH"
        fi
    fi
else
    echo "  ℹ️  Sin cambios para commit."
fi

echo ""
echo "══════════════════════════════════════════════════"
echo "  Repositorio listo: ${GH_USER}/${GH_REPO}"
echo "══════════════════════════════════════════════════"
