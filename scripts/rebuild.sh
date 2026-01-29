#!/bin/bash
set -euxo pipefail

PUBLIC_DIR="public"
mkdir -p "$PUBLIC_DIR"

echo "⚠️ ONE-TIME FULL REBUILD"

rm -rf "$PUBLIC_DIR"/*
mkdir -p "$PUBLIC_DIR"

for zip in *.zip; do
  NAME="$(basename "$zip" .zip)"
  TARGET="$PUBLIC_DIR/$NAME"

  mkdir -p "$TARGET"
  unzip -o "$zip" -d "$TARGET"
done

ls -R public | head -300
