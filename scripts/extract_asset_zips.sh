#!/bin/bash
set -e

OUT_DIR="public"
TARGET_ZIP="$1"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

if [ -n "$TARGET_ZIP" ]; then
  if [ "$TARGET_ZIP" = "ALL" ]; then
    echo "Extracting all zip files in repo for full refresh..."
    mapfile -t CHANGED_ZIPS < <(find . -type f -name '*.zip' | sed 's|^./||' | sort)
  else
    echo "Extracting requested zip file: $TARGET_ZIP"
    if [ ! -f "$TARGET_ZIP" ]; then
      echo "Provided zip file does not exist: $TARGET_ZIP"
      exit 1
    fi
    CHANGED_ZIPS=("$TARGET_ZIP")
  fi
else
  echo "Detecting changed zip files..."
  mapfile -t CHANGED_ZIPS < <(git diff --name-only HEAD~1 HEAD -- '*.zip' || true)
fi

if [ ${#CHANGED_ZIPS[@]} -eq 0 ]; then
  echo "No zip files found to extract. Skipping extraction."
  exit 0
fi

for zipfile in "${CHANGED_ZIPS[@]}"; do
  if [ ! -f "$zipfile" ]; then
    echo "Skipping missing file: $zipfile"
    continue
  fi

  name=$(basename "$zipfile" .zip)
  target="$OUT_DIR/$name"

  mkdir -p "$target"
  echo "Unzipping $zipfile -> $target"

  set +e
  unzip -o "$zipfile" -d "$target"
  unzip_status=$?
  set -e

  if [ "$unzip_status" -gt 1 ]; then
    echo "Failed to unzip $zipfile (exit code: $unzip_status)"
    exit "$unzip_status"
  fi

  if [ "$unzip_status" -eq 1 ]; then
    echo "unzip reported warnings for $zipfile, continuing"
  fi
done

echo "Extraction complete"