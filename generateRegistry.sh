#!/bin/bash
# ─────────────────────────────────────────────────────────
# generateRegistry.sh
# Genera registry.json a partir de los JARs en el directorio actual
# Uso: cd plugins-compilados && ./generateRegistry.sh
# ─────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGISTRY_FILE="$SCRIPT_DIR/registry.json"
PLUGINS_DIR="$SCRIPT_DIR/plugins"

# Crear directorio plugins si no existe
mkdir -p "$PLUGINS_DIR"

# Mover JARs sueltos al directorio plugins/
for jar in "$SCRIPT_DIR"/*.jar; do
    [ -f "$jar" ] || continue
    mv "$jar" "$PLUGINS_DIR/"
done

echo "Generando registry.json..."

# Iniciar JSON array
echo "[" > "$REGISTRY_FILE"

FIRST=true
for jar in "$PLUGINS_DIR"/*.jar; do
    [ -f "$jar" ] || continue

    filename="$(basename "$jar")"
    size=$(stat -f%z "$jar" 2>/dev/null || stat --printf="%s" "$jar" 2>/dev/null)
    checksum=$(shasum -a 256 "$jar" 2>/dev/null | awk '{print $1}' || sha256sum "$jar" 2>/dev/null | awk '{print $1}')
    updated=$(date -r "$jar" "+%Y-%m-%d" 2>/dev/null || date -d @$(stat --printf="%Y" "$jar") "+%Y-%m-%d" 2>/dev/null)

    # Extraer nombre del plugin del JAR filename
    # Formato esperado: nombre-version.jar → e.g. database-workbench-1.2.0.jar
    # Si no tiene version, usar el nombre completo
    clean_name="${filename%.jar}"

    # Intentar separar nombre y versión (última secuencia -X.Y.Z)
    if echo "$clean_name" | grep -qE '-[0-9]+\.[0-9]+'; then
        plugin_version=$(echo "$clean_name" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | tail -1)
        plugin_id=$(echo "$clean_name" | sed -E "s/-${plugin_version}$//")
    else
        plugin_version="1.0.0"
        plugin_id="$clean_name"
    fi

    # Generar nombre display
    display_name=$(echo "$plugin_id" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')

    # Detectar categoría por nombre o manifest
    category="PANEL"
    if echo "$plugin_id" | grep -qiE "^(aes|triple-des|fitbank|cipher)"; then
        category="CIPHER"
    elif echo "$plugin_id" | grep -qiE "^(popup|repeated-lines|remove-duplicates|meld)"; then
        category="POPUP"
    elif echo "$plugin_id" | grep -qiE "^(widget|calculator|uuid|qr|converter|data-generator|image-ocr)"; then
        category="WIDGET"
    fi

    # Escribir entrada JSON
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo "  ," >> "$REGISTRY_FILE"
    fi

    cat >> "$REGISTRY_FILE" <<EOF
  {
    "id": "$plugin_id",
    "name": "$display_name",
    "description": "",
    "version": "$plugin_version",
    "category": "$category",
    "fileName": "$filename",
    "downloadUrl": "plugins/$filename",
    "size": $size,
    "checksum": "$checksum",
    "minAppVersion": "1.0",
    "author": "DEcrypt Team",
    "updatedAt": "$updated"
  }
EOF
done

echo "]" >> "$REGISTRY_FILE"

# Contar plugins
PLUGIN_COUNT=$(find "$PLUGINS_DIR" -name "*.jar" | wc -l | tr -d ' ')
echo "✅ registry.json generado con $PLUGIN_COUNT plugins"
