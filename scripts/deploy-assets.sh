#!/bin/bash
set -e

PUBLIC_DIR="public"
mkdir -p "$PUBLIC_DIR"

git fetch origin main

git diff --name-status origin/main...HEAD '*.zip' | while read status file; do
  [[ "$file" == */* ]] && continue

  NAME=$(basename "$file" .zip)
  TARGET="$PUBLIC_DIR/$NAME"

  case "$status" in
    A|M)
      echo "🔄 Updating $NAME"
      rm -rf "$TARGET"
      unzip -o "$file" -d "$PUBLIC_DIR"
      ;;
    D)
      echo "❌ Removing $TARGET"
      rm -rf "$TARGET"
      ;;
  esac
done
