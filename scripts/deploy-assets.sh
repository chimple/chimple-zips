#!/bin/bash
set -euxo pipefail

PUBLIC_DIR="public"
mkdir -p "$PUBLIC_DIR"

echo "===== Git status ====="
git status

echo "===== Current branch ====="
git branch --show-current

echo "===== Remote branches ====="
git branch -r

git fetch --all

echo "===== ZIP diff ====="
git diff --name-status HEAD~1 HEAD -- '*.zip' || true

git diff --name-status HEAD~1 HEAD -- '*.zip' | \
while IFS=$'\t' read -r status file; do

  echo "Processing: status=$status file=$file"

  [[ "$file" == */* ]] && continue

  NAME=$(basename "$file" .zip)
  TARGET="$PUBLIC_DIR/$NAME"

  case "$status" in
    A|M)
      echo "Updating ZIP: $file → $TARGET"
      rm -rf "$TARGET"
      unzip -o "$file" -d "$PUBLIC_DIR"
      ;;
    D)
      echo "Deleting folder: $TARGET"
      rm -rf "$TARGET"
      ;;
  esac
done

echo "===== public/ after extraction ====="
ls -R public | head -300
