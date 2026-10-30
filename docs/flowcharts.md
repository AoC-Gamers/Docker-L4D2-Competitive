# Diagramas de Flujo del Sistema

## Flujo completo de arranque

```mermaid
graph TD
    A[Inicio del contenedor] --> B[Bootstrap protegido root]
    B --> C[Supervisor mínimo]
    C --> SSH[OpenSSH root]
    C --> R[Runtime linuxgsm sin capacidades y con NNP]
    R --> D[container/entrypoint-user.sh]
    D --> E{L4D2 ya existe}
    E -->|No| F[l4d2_fix_install.sh o auto-install]
    E -->|Si| G[Continuar]
    F --> H[install_stack.sh]
    G --> H
    H --> I[stack/hooks/*.sh]
    I --> J[sync_instances.sh]
    J --> K[menu_stack.sh]
    K --> L[Servidores listos]
```

## Flujo del stack

```mermaid
graph TD
    A[Manifiesto, perfil y overrides] --> B[Validar contratos y tomar bloqueo del destino]
    B --> C[1. Obtener originales exactos en caché persistente]
    C --> D[2. Reutilizar preparación o expandir y ejecutar hooks en candidato]
    D --> E[Políticas finales, conservación y validación]
    E --> F[3. Publicar con diario y consumidores coordinados]
    F --> G{Resultado}
    G -->|éxito| H[Sincronizar, reconciliar, confirmar y limpiar payload]
    G -->|fallo| I[Conservar candidato para recuperación manual]
    I --> J[Conservar evidencia y estado failed]
```

Instalación y actualización comparten este flujo. Una publicación interrumpida
se recupera bajo el mismo bloqueo antes de preparar otra. No se limpia el stack
operativo antes de descargar. Véase [el contrato completo](artifact-flow.md).

## Mapa conceptual

### Bootstrap

- `container/root/bootstrap.py` (entrypoint protegido de la imagen)
- `container/runtime.py` (supervisor sin privilegios)
- `container/entrypoint.sh` (wrapper de compatibilidad)
- `container/bootstrap/dependencies_check.sh`
- `container/bootstrap/ssh.sh`
- `container/bootstrap/symlink.sh`

### Installer

- `installer/bin/install_stack.sh`
- `installer/bin/sync_instances.sh`
- `installer/bin/menu_stack.sh`
- `installer/bin/l4d2_fix_install.sh`
- `installer/lib/tools_stack.sh`

### Stack

- `stack/manifests/components.json`
- `stack/profiles/*.json`
- `stack/hooks/*.sh`
- `stack/preserve-paths.json`

## Notas de migracion

Los diagramas antiguos del modelo repo-centrico ya no representan el flujo vigente. Ese modelo fue sustituido por:

- `install_stack.sh`
- `stack/hooks/`
