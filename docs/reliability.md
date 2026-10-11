# Fiabilidad del despliegue

## Referencia de la auditoría (2026-10-11)

Se consultó develop remoto, sin utilizar main. Ramas de trabajo: codex/stack-reliability.

| Repositorio | Commit develop |
|---|---|
| Docker-L4D2-Competitive | 4f4c90f181833baf56d1357fa02c756d37d66466 |
| Docker-L4D2-AoC | ba382210fdde0d9473d8c978c2cb5ab040132f9c |
| Docker-L4D2-AoC-Vanilla | efba8fcc1a2c7b62f007fad1eee49e25ca5ec25c |
| AoC-L4D2-Competitive | 89a79afe06a18bff2252de2e635e61ecd077ea9c |

Hallazgos confirmados en esos commits: registro opcional sin prefijo (ambos aoc.default.sh), exclusiones solo en fuentes Vanilla, carga raíz de source_keyvalues empaquetado en custom, limpieza antes de descargas/hooks (install_stack.sh), huella solo de componentes (deploy_stack.sh), bloqueo por perfil posterior al estado, dependencias móviles y caché sin identidad exacta, hook seleccionado por branch y padres por tag, parches textuales AoC, borrado de errors_*.log.

Ya corregido previamente: autenticación GitHub y diagnósticos por stderr, caché persistente SourceTV. Se conservan y ejecutan sus regresiones. La limpieza previa de plugins ya existía: no se atribuye el problema a acumulación general de SMX. El healthcheck existente supervisa SSH y, en AoC, estado del despliegue; no se amplía a SRCDS.

## Recursos opcionales

La biblioteca base overlay_stack.py es la única implementación para AoC y Vanilla. Registros JSON schema_version=2: rutas relativas a left4dead2 con prefijo sound/, models/ o addons/, subtree explícito y SHA256 por archivo. Se rechazan rutas absolutas, .. y enlaces simbólicos en archivo/ancestros. La retirada elimina solo archivos aún iguales al contenido registrado. Un archivo modificado localmente se conserva.

Los .paths antiguos no se reinterpretan como formato nuevo. La etiqueta determina el subárbol; solo se adopta propiedad si el ZIP disponible y el archivo instalado coinciden en contenido. El resto se conserva y queda en .paths.unresolved; el original pasa a .paths.migrated. Sin ZIP no se presume propiedad. Revisar manualmente esos registros antes de una limpieza adicional.

## Validación

Las pruebas offline usan directorios temporales y fixtures; no equivalen a una prueba en SRCDS. El healthcheck no representa disponibilidad de las instancias SRCDS.
