# decrypt-plugins

Repositorio de distribución de plugins compilados para DEcrypt.

## Estructura

```
├── registry.json          ← Catálogo auto-generado
├── registry-signature.json ← Firma detached opcional del catálogo
├── plugins/               ← JARs de plugins
├── app/                   ← Distribución de la app
│   ├── app-release.json
│   └── DEcrypt.jar
├── generateRegistry.sh
└── initPluginRepo.sh
```

## Configuración en DEcrypt

| Campo | Valor |
|-------|-------|
| Owner | `wrocano` |
| Repo | `decrypt-plugins` |
| Branch | `main` |
| Registry Path | `registry.json` |
| Registry Signature Path | `registry-signature.json` |

## Publicación firmada

`generateRegistry.sh` firma los bytes exactos de cada JAR y del registry cuando
recibe `PLUGIN_SIGNING_PRIVATE_KEY`, `PLUGIN_PUBLISHER_ID`,
`PLUGIN_PUBLISHER_NAME`, `PLUGIN_SIGNING_KEY_ID` y
`PLUGIN_SIGNATURE_ALGORITHM` (`SHA256withRSA` o `SHA256withECDSA`). Usa
`REQUIRE_PLUGIN_SIGNATURES=1` en CI para impedir publicaciones unsigned.

La clave privada debe permanecer fuera del repositorio. Sólo la clave pública
X.509 PEM se importa en el administrador de seguridad de DEcrypt.

Los plugins opt-in fuera de proceso publican además `executionMode` =
`ISOLATED_HEADLESS` e `isolatedEntrypoint`, derivados respectivamente de
`Plugin-Execution-Mode` y `Plugin-Isolated-Entrypoint` en el manifest.
