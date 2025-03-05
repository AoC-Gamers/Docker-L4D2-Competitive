#!/bin/bash
# Script: rep_branch.sh
# Descripción: Actualiza el campo "branch" en el archivo repos.json según las variables de entorno.
#              Cada variable tiene el prefijo "BRANH_" seguido del nombre del folder en mayúsculas.
#              Si la variable es "default", se omite la actualización para ese repositorio.

# Ruta del archivo repos.json
REPOS_FILE="/app/server-scripts/repos.json"

# Verificar que el archivo exista
if [ ! -f "$REPOS_FILE" ]; then
    echo "El archivo $REPOS_FILE no existe."
    exit 1
fi

# Crear un archivo temporal para trabajar
TMP_FILE=$(mktemp)
cp "$REPOS_FILE" "$TMP_FILE"

# Obtener la cantidad de objetos en el array JSON
NUM=$(jq length "$TMP_FILE")

# Recorrer cada elemento del array
for ((i=0; i<NUM; i++)); do
    # Obtener el valor del campo "folder"
    FOLDER=$(jq -r ".[$i].folder" "$TMP_FILE")
    # Construir el nombre de la variable de entorno (ejemplo: BRANCH_SIR)
    VAR_NAME="BRANCH_$(echo "$FOLDER" | tr '[:lower:]' '[:upper:]')"
    # Obtener el valor de la variable; si no está definida, se usa "default"
    VALUE=${!VAR_NAME:-default}

    # Verificar si el valor es "default"
    if [ "$VALUE" != "default" ]; then
        # Actualizar el campo "branch" con el valor obtenido
        jq --arg val "$VALUE" ".[$i].branch = \$val" "$TMP_FILE" > "${TMP_FILE}.tmp" && mv "${TMP_FILE}.tmp" "$TMP_FILE"
        echo "Actualizado branch '$FOLDER' a '$VALUE'."
    fi
done

# Reemplazar el archivo original con la versión actualizada
mv "$TMP_FILE" "$REPOS_FILE"
echo "Archivo repos.json actualizado."

exit 0