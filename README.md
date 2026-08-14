# decrypt-plugins

Repositorio de distribución de plugins compilados para DEcrypt.

## Estructura

```
├── registry.json          ← Catálogo auto-generado
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
