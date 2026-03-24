# ------------------------- Extract zip files (changed / specific / all)

#!/bin/bash
set -e

OUT_DIR="public"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

TARGET_ZIP="$1"

if [ -n "$TARGET_ZIP" ]; then
  if [ "$TARGET_ZIP" = "ALL" ]; then
    echo "🔍 Extracting all zip files in repo for full refresh..."
    mapfile -t CHANGED_ZIPS < <(find . -type f -name '*.zip' | sed 's|^./||')
  else
    echo "🔍 Extracting requested zip file: $TARGET_ZIP"
    if [ ! -f "$TARGET_ZIP" ]; then
      echo "❌ Provided zip file does not exist: $TARGET_ZIP"
      exit 1
    fi
    CHANGED_ZIPS=("$TARGET_ZIP")
  fi
else
  echo "🔍 Detecting changed zip files..."
  mapfile -t CHANGED_ZIPS < <(git diff --name-only HEAD~1 HEAD -- '*.zip' || true)
fi

if [ ${#CHANGED_ZIPS[@]} -eq 0 ]; then
  echo "ℹ️ No zip files found to extract. Skipping extraction."
  exit 0
fi

for zipfile in "${CHANGED_ZIPS[@]}"; do
  if [ ! -f "$zipfile" ]; then
    echo "⚠️ Skipping missing file: $zipfile"
    continue
  fi

  name=$(basename "$zipfile" .zip)
  target="$OUT_DIR/$name"

  mkdir -p "$target"
  echo "📦 Unzipping $zipfile → $target"
  unzip -o "$zipfile" -d "$target"
done

echo "✅ Extraction complete"


# ------------------------- Full repo root extraction (For Syncing All Zips currently present in REpo)

# #!/bin/bash
# set -e

# OUT_DIR="public"

# # Clean previous output
# rm -rf "$OUT_DIR"
# mkdir -p "$OUT_DIR"

# # Loop through all zip files in root
# for zipfile in *.zip; do
#   [ -e "$zipfile" ] || continue

#   name=$(basename "$zipfile" .zip)
#   target="$OUT_DIR/$name"

#   mkdir -p "$target"
#   echo "Unzipping $zipfile -> $target"
#   unzip -o "$zipfile" -d "$target" || true
# done
