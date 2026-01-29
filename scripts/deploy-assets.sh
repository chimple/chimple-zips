#!/bin/bash
set -euo pipefail

PUBLIC_DIR="public"
mkdir -p "$PUBLIC_DIR"

# Detect the branch we are running on
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

git fetch origin "$CURRENT_BRANCH"

git diff --name-status "origin/$CURRENT_BRANCH"...HEAD -- '*.zip' | \
while IFS=$'\t' read -r status file; do

  # Only root-level ZIPs
  [[ "$file" == */* ]] && continue

  NAME=$(basename "$file" .zip)
  TARGET="$PUBLIC_DIR/$NAME"

  case "$status" in
    A|M)
      echo "🔄 Updating $NAME"

      # Ensure deterministic ownership
      rm -rf "$TARGET"

      # ZIP MUST contain a top-level folder named $NAME
      unzip -o "$file" -d "$PUBLIC_DIR"

      # Safety check
      if [ ! -d "$TARGET" ]; then
        echo "❌ ERROR: $file does not contain folder '$NAME/'"
        exit 1
      fi
      ;;
    D)
      echo "❌ Removing $TARGET"
      rm -rf "$TARGET"
      ;;
  esac
done
