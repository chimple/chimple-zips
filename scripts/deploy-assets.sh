#!/bin/bash
set -euxo pipefail

PUBLIC_DIR="public"
mkdir -p "$PUBLIC_DIR"

echo "===== ZIP diff ====="
git diff --name-status HEAD~1 HEAD -- '*.zip' || true

git diff --name-status HEAD~1 HEAD -- '*.zip' | \
while IFS=$'\t' read -r status file; do

  [[ "$file" == */* ]] && continue

  NAME="$(basename "$file" .zip)"
  TARGET="$PUBLIC_DIR/$NAME"

  echo "Processing: status=$status zip=$file target=$TARGET"

  case "$status" in
    A|M)
      echo "🔄 Updating $TARGET"

      # Clean old content for this ZIP
      rm -rf "$TARGET"
      mkdir -p "$TARGET"

      # Extract ZIP contents into its own folder
      unzip -o "$file" -d "$TARGET"
      ;;
    D)
      echo "❌ Removing $TARGET (zip deleted)"
      rm -rf "$TARGET"
      ;;
  esac
done

echo "===== public/ after extraction ====="
ls -R public | head -300
