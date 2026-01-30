#!/bin/bash
set -euxo pipefail

PUBLIC_DIR="public"
rm -rf "$PUBLIC_DIR"/*
mkdir -p "$PUBLIC_DIR"

for zip in *.zip; do
  NAME="$(basename "$zip" .zip)"
  mkdir -p "$PUBLIC_DIR/$NAME"
  unzip -o "$zip" -d "$PUBLIC_DIR/$NAME"
done

ls -R public | head -300
