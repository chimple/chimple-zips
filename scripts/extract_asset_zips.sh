#!/bin/bash
set -e

OUT_DIR="public"

# Clean previous output
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Loop through all zip files in root
for zipfile in *.zip; do
  [ -e "$zipfile" ] || continue

  name=$(basename "$zipfile" .zip)
  target="$OUT_DIR/$name"

  mkdir -p "$target"
  echo "Unzipping $zipfile -> $target"
  unzip -o "$zipfile" -d "$target" || true
done