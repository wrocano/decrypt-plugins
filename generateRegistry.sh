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
REGISTRY_SIGNATURE_FILE="$SCRIPT_DIR/registry-signature.json"

# Signing material is supplied by CI/operator and is never copied into this repo.
SIGNING_PRIVATE_KEY="${PLUGIN_SIGNING_PRIVATE_KEY:-}"
SIGNING_PUBLISHER_ID="${PLUGIN_PUBLISHER_ID:-}"
SIGNING_PUBLISHER_NAME="${PLUGIN_PUBLISHER_NAME:-}"
SIGNING_KEY_ID="${PLUGIN_SIGNING_KEY_ID:-}"
SIGNING_ALGORITHM="${PLUGIN_SIGNATURE_ALGORITHM:-SHA256withRSA}"
REQUIRE_SIGNATURES="${REQUIRE_PLUGIN_SIGNATURES:-0}"
SIGNING_ENABLED=false

if [ -n "$SIGNING_PRIVATE_KEY" ]; then
    [ -f "$SIGNING_PRIVATE_KEY" ] || {
        echo "  ❌ Private key no encontrada: $SIGNING_PRIVATE_KEY"
        exit 1
    }
    case "$SIGNING_ALGORITHM" in
        SHA256withRSA|SHA256withECDSA) ;;
        *) echo "  ❌ Algoritmo de firma no soportado: $SIGNING_ALGORITHM"; exit 1 ;;
    esac
    printf '%s' "$SIGNING_PUBLISHER_ID" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' || {
        echo "  ❌ PLUGIN_PUBLISHER_ID inválido"; exit 1;
    }
    printf '%s' "$SIGNING_KEY_ID" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' || {
        echo "  ❌ PLUGIN_SIGNING_KEY_ID inválido"; exit 1;
    }
    [ -n "$SIGNING_PUBLISHER_NAME" ] || SIGNING_PUBLISHER_NAME="$SIGNING_PUBLISHER_ID"
    command -v openssl >/dev/null 2>&1 || {
        echo "  ❌ openssl es requerido para firmar"; exit 1;
    }
    SIGNING_ENABLED=true
elif [ "$REQUIRE_SIGNATURES" = "1" ]; then
    echo "  ❌ REQUIRE_PLUGIN_SIGNATURES=1 pero no se configuró PLUGIN_SIGNING_PRIVATE_KEY"
    exit 1
else
    echo "  ⚠️  Registry/JARs se generarán sin firma (modo compatible)."
fi

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

# ── Funciones: metadata del manifest ──
manifest_value() {
    local jar="$1"
    local key="$2"
    local manifest
    manifest="$(unzip -p "$jar" META-INF/MANIFEST.MF 2>/dev/null || true)"
    printf '%s\n' "$manifest" \
        | tr -d '\r' \
        | awk '
            /^ / { current = current substr($0, 2); next }
            { if (current != "") print current; current = $0 }
            END { if (current != "") print current }
        ' \
        | awk -v prefix="$key:" 'index($0, prefix) == 1 {
            value = substr($0, length(prefix) + 1)
            sub(/^[[:space:]]+/, "", value)
            print value
            exit
        }'
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

sign_file() {
    openssl dgst -sha256 -sign "$SIGNING_PRIVATE_KEY" "$1" \
        | openssl base64 -A
}

capabilities_json() {
    local raw="$1"
    local result="["
    local separator=""
    local capability
    IFS=',' read -r -a values <<< "$raw"
    for capability in "${values[@]}"; do
        capability="$(printf '%s' "$capability" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -n "$capability" ] || continue
        [ "$capability" = "NONE" ] && continue
        result="$result$separator\"$(json_escape "$capability")\""
        separator=", "
    done
    printf '%s]' "$result"
}

lookup_checksum() {
    local filename="$1"
    local source_file="$2"
    [ -f "$source_file" ] || return 0
    awk -v target="$filename" '$2 == target { print $1; exit }' "$source_file"
}

# ── Generar nuevos checksums y detectar cambios ──
CHANGED_PLUGINS=()
ALL_PLUGINS=()
NEW_CHECKSUMS_FILE="$(mktemp "$SCRIPT_DIR/.checksums.new.XXXXXX")"
trap 'rm -f "$NEW_CHECKSUMS_FILE"' EXIT

for jar in "$PLUGINS_DIR"/*.jar; do
    [ -f "$jar" ] || continue
    filename="$(basename "$jar")"
    
    md5hash="$(md5sum "$jar" | awk '{print $1}')"
    echo "$md5hash  $filename" >> "$NEW_CHECKSUMS_FILE"
    ALL_PLUGINS+=("$filename")
    
    old_hash="$(lookup_checksum "$filename" "$CHECKSUMS_FILE")"
    if [ "$md5hash" != "$old_hash" ]; then
        CHANGED_PLUGINS+=("$filename")
    fi
done

# ── Detectar plugins eliminados ──
REMOVED_PLUGINS=()
if [ -f "$CHECKSUMS_FILE" ]; then
    while read -r old_hash old_file; do
        [ -n "$old_hash" ] && [ -n "$old_file" ] || continue
        if [ -z "$(lookup_checksum "$old_file" "$NEW_CHECKSUMS_FILE")" ]; then
            REMOVED_PLUGINS+=("$old_file")
        fi
    done < "$CHECKSUMS_FILE"
fi

# ── Escribir nuevo archivo de checksums ──
sort -k2 "$NEW_CHECKSUMS_FILE" > "$CHECKSUMS_FILE"

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
    
    fallback_name="$(clean_plugin_name "$filename")"
    size="$(stat -c%s "$jar" 2>/dev/null || stat -f%z "$jar" 2>/dev/null)"
    sha256="$(sha256_file "$jar")"
    updated_at="$(date -r "$jar" "+%Y-%m-%dT%H:%M:%S" 2>/dev/null || date "+%Y-%m-%dT%H:%M:%S")"
    fallback_version="$(printf '%s' "$filename" | sed -nE 's/.*-([0-9]+(\.[0-9]+)+)\.jar$/\1/p')"
    [ -n "$fallback_version" ] || fallback_version="1.0"

    metadata_version="$(manifest_value "$jar" "Plugin-Metadata-Version")"
    manifest_id="$(manifest_value "$jar" "Plugin-Id")"
    manifest_name="$(manifest_value "$jar" "Plugin-Name")"
    manifest_version="$(manifest_value "$jar" "Plugin-Version")"
    manifest_sdk_version="$(manifest_value "$jar" "Plugin-SDK-Version")"
    manifest_min_app_version="$(manifest_value "$jar" "Plugin-Min-App-Version")"
    manifest_category="$(manifest_value "$jar" "Plugin-Category")"
    manifest_capabilities="$(manifest_value "$jar" "Plugin-Capabilities")"
    manifest_execution_mode="$(manifest_value "$jar" "Plugin-Execution-Mode")"
    manifest_isolated_entrypoint="$(manifest_value "$jar" "Plugin-Isolated-Entrypoint")"
    manifest_broker_version="$(manifest_value "$jar" "Plugin-Isolation-Broker-Version")"

    if [ "$SIGNING_ENABLED" = true ]; then
        publisher_id_json="\"$(json_escape "$SIGNING_PUBLISHER_ID")\""
        publisher_name_json="\"$(json_escape "$SIGNING_PUBLISHER_NAME")\""
        key_id_json="\"$(json_escape "$SIGNING_KEY_ID")\""
        signature_algorithm_json="\"$(json_escape "$SIGNING_ALGORITHM")\""
        signature_json="\"$(sign_file "$jar")\""
    else
        publisher_id_json="null"
        publisher_name_json="null"
        key_id_json="null"
        signature_algorithm_json="null"
        signature_json="null"
    fi

    if [ -n "$metadata_version" ]; then
        plugin_id="$manifest_id"
        plugin_name="$manifest_name"
        version="$manifest_version"
        category="$manifest_category"
        min_app_version="$manifest_min_app_version"
        metadata_json="\"$(json_escape "$metadata_version")\""
        sdk_json="\"$(json_escape "$manifest_sdk_version")\""
        if [ -n "$manifest_capabilities" ]; then
            capabilities_value="$(capabilities_json "$manifest_capabilities")"
        else
            capabilities_value="null"
        fi
        if [ -n "$manifest_execution_mode" ]; then
            execution_mode_json="\"$(json_escape "$manifest_execution_mode")\""
        else
            execution_mode_json="null"
        fi
        if [ -n "$manifest_isolated_entrypoint" ]; then
            isolated_entrypoint_json="\"$(json_escape "$manifest_isolated_entrypoint")\""
        else
            isolated_entrypoint_json="null"
        fi
        if [ -n "$manifest_broker_version" ]; then
            broker_version_json="\"$(json_escape "$manifest_broker_version")\""
        else
            broker_version_json="null"
        fi
    else
        plugin_id="${manifest_id:-$fallback_name}"
        plugin_name="${manifest_name:-$fallback_name}"
        version="${manifest_version:-$fallback_version}"
        category="${manifest_category:-$(detect_category "$filename")}"
        min_app_version="${manifest_min_app_version:-1.0.0}"
        metadata_json="null"
        sdk_json="null"
        capabilities_value="null"
        execution_mode_json="null"
        isolated_entrypoint_json="null"
        broker_version_json="null"
    fi
    
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo "," >> "$REGISTRY_FILE"
    fi
    
    cat >> "$REGISTRY_FILE" <<EOF
  {
    "id": "$(json_escape "$plugin_id")",
    "name": "$(json_escape "$plugin_name")",
    "version": "$(json_escape "$version")",
    "category": "$(json_escape "$category")",
    "fileName": "$(json_escape "$filename")",
    "downloadUrl": "plugins/$(json_escape "$filename")",
    "size": $size,
    "checksum": "$sha256",
    "md5": "$(lookup_checksum "$filename" "$CHECKSUMS_FILE")",
    "metadataVersion": $metadata_json,
    "sdkVersion": $sdk_json,
    "minAppVersion": "$(json_escape "$min_app_version")",
    "capabilities": $capabilities_value,
    "executionMode": $execution_mode_json,
    "isolatedEntrypoint": $isolated_entrypoint_json,
    "isolationBrokerVersion": $broker_version_json,
    "author": "DEcrypt Team",
    "publisherId": $publisher_id_json,
    "publisherName": $publisher_name_json,
    "keyId": $key_id_json,
    "signatureAlgorithm": $signature_algorithm_json,
    "signature": $signature_json,
    "updatedAt": "$updated_at"
  }
EOF
done

echo "" >> "$REGISTRY_FILE"
echo "]" >> "$REGISTRY_FILE"

if [ "$SIGNING_ENABLED" = true ]; then
    registry_checksum="$(sha256_file "$REGISTRY_FILE")"
    registry_signature="$(sign_file "$REGISTRY_FILE")"
    cat > "$REGISTRY_SIGNATURE_FILE" <<EOF
{
  "publisherId": "$(json_escape "$SIGNING_PUBLISHER_ID")",
  "publisherName": "$(json_escape "$SIGNING_PUBLISHER_NAME")",
  "keyId": "$(json_escape "$SIGNING_KEY_ID")",
  "signatureAlgorithm": "$(json_escape "$SIGNING_ALGORITHM")",
  "checksum": "$registry_checksum",
  "signature": "$registry_signature"
}
EOF
    echo "  🔏 Registry y artefactos firmados por $SIGNING_PUBLISHER_ID/$SIGNING_KEY_ID"
else
    rm -f "$REGISTRY_SIGNATURE_FILE"
fi

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
