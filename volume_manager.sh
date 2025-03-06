#!/bin/bash

VOLUME_NAME="name_of_your_volume"
BACKUP_NAME="name_of_your_volume_backup.tar.gz"

SCRIPT_DIR=$(dirname "$0")
BACKUP_DIR=$(cd "$SCRIPT_DIR" && pwd)
DOCKER_BACKUP_DIR=$(echo "$BACKUP_DIR" | sed 's/^\/c\//c:\//')

backup() {
  echo "Creating backup of volume $VOLUME_NAME..."
  MSYS_NO_PATHCONV=1 docker run --rm -v $VOLUME_NAME:/volume -v "$DOCKER_BACKUP_DIR":/backup alpine tar czf /backup/$BACKUP_NAME -C /volume .
  echo "Backup created: $BACKUP_NAME"
}

restore() {
  echo "Restoring volume $VOLUME_NAME from backup..."
  if docker volume inspect $VOLUME_NAME > /dev/null 2>&1; then
    echo "Volume $VOLUME_NAME exists, removing..."
    docker volume rm $VOLUME_NAME
  fi
  docker volume create $VOLUME_NAME
  MSYS_NO_PATHCONV=1 docker run --rm -v $VOLUME_NAME:/volume -v "$DOCKER_BACKUP_DIR":/backup alpine sh -c "cd /volume && tar xzf /backup/$BACKUP_NAME"
  echo "Volume $VOLUME_NAME restored from backup."
}

case $1 in
  backup)
    backup
    ;;
  restore)
    restore
    ;;
  *)
    echo "Usage: $0 {backup|restore}"
    exit 1
    ;;
esac
