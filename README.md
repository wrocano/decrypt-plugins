# decrypt-plugins

Repositorio de distribución de plugins compilados para DEcrypt.

## Estructura

```
├── registry.json          ← Catálogo auto-generado de plugins disponibles
├── plugins/               ← JARs compilados listos para descargar
│   ├── database-workbench-1.0.jar
│   ├── jcoder-1.0.jar
│   └── ...
├── generateRegistry.sh    ← Script que genera registry.json
└── initPluginRepo.sh      ← Script de inicialización (uso único)
```

## Uso

Este repositorio es gestionado automáticamente por el script `compileAllPlugins`
del proyecto DEcrypt. No editar manualmente.

## Acceso desde DEcrypt

Requiere un GitHub Fine-Grained Token con permiso `Contents: Read-only`
configurado en: **Widgets → Plugin Marketplace → Configurar Token**

| Campo | Valor |
|-------|-------|
| Owner | `wrocano` |
| Repo | `decrypt-plugins` |
| Branch | `main` |
| Registry Path | `registry.json` |
