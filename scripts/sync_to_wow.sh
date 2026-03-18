#!/bin/sh
set -eu

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
SRC_DIR="$PROJECT_ROOT/Shinkili"
DEST_DIR="/Applications/World of Warcraft/_retail_/Interface/AddOns/Shinkili"

mkdir -p "$DEST_DIR"
rsync -av --delete "$SRC_DIR/" "$DEST_DIR/"
echo "Synced Shinkili to $DEST_DIR"
