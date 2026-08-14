#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
# generateRegistry.sh
# Genera registry.json y mantiene checksums.md5 para detectar cambios.
# Solo marca como "changed" los plugins nuevos o modificados.
# ═══════════════════════════════════════════════════════════════════════
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGINS_DIR="$SCRIPT_DIR/plugins"
CHECKSUMS_FILE="$SCRIPT_DIR/checksums.md5"
REGISTRY_FILE="$SCRIPT_DIR/registry.json"
CHANGED_FILE="$SCRIPT_DIR/.changed-plugins"

# Asegurar que el directorio plugins/ existe
if [ ! -d "$PLUGINS_DIR" ]; then
    echo "  ⚠️  Directorio plugins/ no encontrado. Nada que registrar."
    exit 0
fi

# ── Función: detectar categoría por nombre del JAR ──
detect_category() {
    local name="$1"
    case "$name" in
        widget-*|calculator-*) echo "WIDGET" ;;
        popup-*)               echo "POPUP" ;;
        aes-*|triple-des*|fitbank-*|cipher-*) echo "CIPHER" ;;
        *)                     echo "PANEL" ;;
    esac
}

# ── Función: extraer nombre limpio del JAR ──
clean_plugin_name() {
    local filename="$1"
    echo "$filename" | sed 's/\.jar$//' | sed 's/-[0-9]\+\.[0-9]\+$//'
}

# ── Cargar checksums previos ──
declare -A OLD_CHECKSUMS
if [ -f "$CHECKSUMS_FILE" ]; then
    while IFS='  ' read -r hash file; do
        if [ -n "$hash" ] && [ -n "$file" ]; then
            OLD_CHECKSUMS["$file"]="$hash"
        fi
    done < "$CHECKSUMS_FILE"
fi

# ── Generar nuevos checksums y detectar cambios ──
declare -A NEW_CHECKSUMS
CHANGED_PLUGINS=()
ALL_PLUGINS=()

for jar in "$PLUGINS_DIR"/*.jar; do
    [ -f "$jar" ] || continue
    filename="$(basename "$jar")"
    
    md5hash="$(md5sum "$jar" | awk '{print $1}')"
    NEW_CHECKSUMS["$filename"]="$md5hash"
    ALL_PLUGINS+=("$filename")
    
    old_hash="${OLD_CHECKSUMS[$filename]:-}"
    if [ "$md5hash" != "$old_hash" ]; then
        CHANGED_PLUGINS+=("$filename")
    fi
done

# ── Detectar plugins eliminados ──
REMOVED_PLUGINS=()
for old_file in "${!OLD_CHECKSUMS[@]}"; do
    if [ -z "${NEW_CHECKSUMS[$old_file]:-}" ]; then
        REMOVED_PLUGINS+=("$old_file")
    fi
done

# ── Escribir nuevo archivo de checksums ──
> "$CHECKSUMS_FILE"
for filename in $(printf '%s\n' "${ALL_PLUGINS[@]}" | sort); do
    echo "${NEW_CHECKSUMS[$filename]}  $filename" >> "$CHECKSUMS_FILE"
done

# ── Escribir lista de plugins con cambios ──
> "$CHANGED_FILE"
for plugin in "${CHANGED_PLUGINS[@]}"; do
    echo "$plugin" >> "$CHANGED_FILE"
done

# ── Generar registry.json ──
echo "[" > "$REGISTRY_FILE"
FIRST=true

for filename in $(printf '%s\n' "${ALL_PLUGINS[@]}" | sort); do
    jar="$PLUGINS_DIR/$filename"
    
    plugin_name="$(clean_plugin_name "$filename")"
    category="$(detect_category "$filename")"
    size="$(stat -c%s "$jar" 2>/dev/null || stat -f%z "$jar" 2>/dev/null)"
    sha256="$(sha256sum "$jar" | awk '{print $1}')"
    updated_at="$(date -r "$jar" "+%Y-%m-%dT%H:%M:%S" 2>/dev/null || date "+%Y-%m-%dT%H:%M:%S")"
    version="$(echo "$filename" | grep -oP '\d+\.\d+(?=\.jar$)' || echo "1.0")"
    
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo "," >> "$REGISTRY_FILE"
    fi
    
    cat >> "$REGISTRY_FILE" <<EOF
  {
    "id": "$plugin_name",
    "name": "$plugin_name",
    "version": "$version",
    "category": "$category",
    "fileName": "$filename",
    "downloadUrl": "plugins/$filename",
    "size": $size,
    "checksum": "$sha256",
    "md5": "${NEW_CHECKSUMS[$filename]}",
    "minAppVersion": "1.0",
    "author": "DEcrypt Team",
    "updatedAt": "$updated_at"
  }
EOF
done

echo "" >> "$REGISTRY_FILE"
echo "]" >> "$REGISTRY_FILE"

# ── Resumen ──
echo "  📋 Registry generado: $(echo "${#ALL_PLUGINS[@]}") plugins"
echo "  🔄 Plugins con cambios: ${#CHANGED_PLUGINS[@]}"
if [ ${#CHANGED_PLUGINS[@]} -gt 0 ]; then
    for p in "${CHANGED_PLUGINS[@]}"; do
        echo "     → $p"
    done
fi
if [ ${#REMOVED_PLUGINS[@]} -gt 0 ]; then
    echo "  🗑️  Plugins eliminados: ${#REMOVED_PLUGINS[@]}"
    for p in "${REMOVED_PLUGINS[@]}"; do
        echo "     → $p"
    done
fi
