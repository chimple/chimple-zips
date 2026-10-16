#!/usr/bin/env bash
set -euo pipefail

CHANGED_ZIPS_FILE="${CHANGED_ZIPS_FILE:-changed_zips.txt}"
DELETED_ZIPS_FILE="${DELETED_ZIPS_FILE:-deleted_zips.txt}"
STAGING_DIR="${STAGING_DIR:-r2-upload}"

is_supported_zip() {
  [[ "$1" == *.zip ]]
}

append_unique_sorted() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"
  sort -u "$file" > "$tmp"
  mv "$tmp" "$file"
}

collect_from_diff() {
  local before="$1"
  local after="$2"
  local status old_path new_path
  local -a diff_command

  if [ -z "$after" ] || ! git cat-file -e "${after}^{commit}" 2>/dev/null; then
    echo "ERROR: push after SHA is missing or unavailable: $after" >&2
    return 1
  fi

  if [ "$before" = "0000000000000000000000000000000000000000" ]; then
    diff_command=(git diff-tree --root --name-status --find-renames -z -r "$after" --)
  else
    if ! git cat-file -e "${before}^{commit}" 2>/dev/null; then
      echo "ERROR: push before SHA is unavailable: $before" >&2
      return 1
    fi
    diff_command=(git diff --name-status --find-renames -z "$before" "$after" --)
  fi

  while IFS= read -r -d '' status; do
    case "${status:0:1}" in
      A|M|C)
        IFS= read -r -d '' new_path || return 1
        if is_supported_zip "$new_path"; then
          printf '%s\n' "$new_path" >> "$CHANGED_ZIPS_FILE"
        fi
        ;;
      D)
        IFS= read -r -d '' old_path || return 1
        if is_supported_zip "$old_path"; then
          printf '%s\n' "$old_path" >> "$DELETED_ZIPS_FILE"
        fi
        ;;
      R)
        IFS= read -r -d '' old_path || return 1
        IFS= read -r -d '' new_path || return 1
        if is_supported_zip "$old_path"; then
          printf '%s\n' "$old_path" >> "$DELETED_ZIPS_FILE"
        fi
        if is_supported_zip "$new_path"; then
          printf '%s\n' "$new_path" >> "$CHANGED_ZIPS_FILE"
        fi
        ;;
      *)
        echo "ERROR: unexpected git diff status: $status" >&2
        return 1
        ;;
    esac
  done < <("${diff_command[@]}")
}

collect_all() {
  git ls-files -z -- '*.zip' |
    while IFS= read -r -d '' path; do
      printf '%s\n' "$path"
    done > "$CHANGED_ZIPS_FILE"
}

collect() {
  local before="$1"
  local after="$2"

  : > "$CHANGED_ZIPS_FILE"
  : > "$DELETED_ZIPS_FILE"
  collect_from_diff "$before" "$after"
  append_unique_sorted "$CHANGED_ZIPS_FILE"
  append_unique_sorted "$DELETED_ZIPS_FILE"

  echo "ZIP files to upload:"
  cat "$CHANGED_ZIPS_FILE"
  echo "ZIP files to delete:"
  cat "$DELETED_ZIPS_FILE"

  if [ ! -s "$CHANGED_ZIPS_FILE" ] && [ ! -s "$DELETED_ZIPS_FILE" ]; then
    echo "ERROR: push range contains no supported lowercase .zip changes." >&2
    return 1
  fi
}

collect_all_command() {
  : > "$CHANGED_ZIPS_FILE"
  : > "$DELETED_ZIPS_FILE"
  collect_all
  append_unique_sorted "$CHANGED_ZIPS_FILE"
}

stage_changed_zips() {
  local file
  local expected_count=0
  local staged_count

  rm -rf -- "$STAGING_DIR"
  mkdir -p -- "$STAGING_DIR"

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    expected_count=$((expected_count + 1))
    if [ ! -f "$file" ]; then
      echo "ERROR: detected ZIP is not present in the checked-out push: $file" >&2
      return 1
    fi
    mkdir -p -- "$STAGING_DIR/$(dirname -- "$file")"
    cp -- "$file" "$STAGING_DIR/$file"
  done < "$CHANGED_ZIPS_FILE"

  staged_count="$(find "$STAGING_DIR" -type f -name '*.zip' | wc -l | tr -d ' ')"
  if [ "$staged_count" -ne "$expected_count" ]; then
    echo "ERROR: staged ZIP count ($staged_count) does not match detected ZIP count ($expected_count)." >&2
    return 1
  fi
}

aws_r2() {
  AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" \
  AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
  aws "$@"
}

upload_and_verify() {
  local file local_size remote_size

  if [ -s "$CHANGED_ZIPS_FILE" ]; then
    stage_changed_zips
    while IFS= read -r file; do
      [ -n "$file" ] || continue
      echo "Uploading ZIP '$file' to R2 bucket root: $R2_BUCKET_NAME"
      aws_r2 s3 cp "$STAGING_DIR/$file" "s3://${R2_BUCKET_NAME}/${file}" \
        --endpoint-url "$R2_ENDPOINT" \
        --region auto \
        --no-progress

      local_size="$(wc -c < "$file" | tr -d ' ')"
      if ! remote_size="$(aws_r2 s3api head-object \
          --bucket "$R2_BUCKET_NAME" \
          --key "$file" \
          --endpoint-url "$R2_ENDPOINT" \
          --region auto \
          --query ContentLength \
          --output text)"; then
        echo "ERROR: upload verification failed; object does not exist: $file" >&2
        return 1
      fi
      remote_size="${remote_size//$'\r'/}"
      remote_size="${remote_size//$'\n'/}"
      if [ "$remote_size" != "$local_size" ]; then
        echo "ERROR: upload verification size mismatch for '$file': local=$local_size remote=$remote_size" >&2
        return 1
      fi
      echo "Verified R2 object '$file' ($local_size bytes)."
    done < "$CHANGED_ZIPS_FILE"
  else
    echo "No ZIP files require upload."
  fi
}

delete_removed_zips() {
  local file status

  if [ ! -s "$DELETED_ZIPS_FILE" ]; then
    echo "No ZIP files require deletion."
    return 0
  fi

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    echo "Deleting R2 object '$file'"
    if aws_r2 s3 rm "s3://${R2_BUCKET_NAME}/${file}" \
        --endpoint-url "$R2_ENDPOINT" \
        --region auto \
        --no-progress; then
      :
    else
      status=$?
      echo "ERROR: failed to delete R2 object '$file' (aws exit $status)." >&2
      return "$status"
    fi
  done < "$DELETED_ZIPS_FILE"
}

sync() {
  : "${R2_BUCKET_NAME:?R2_BUCKET_NAME is required}"
  : "${R2_ENDPOINT:?R2_ENDPOINT is required}"
  : "${R2_ACCESS_KEY_ID:?R2_ACCESS_KEY_ID is required}"
  : "${R2_SECRET_ACCESS_KEY:?R2_SECRET_ACCESS_KEY is required}"

  if [ ! -s "$CHANGED_ZIPS_FILE" ] && [ ! -s "$DELETED_ZIPS_FILE" ]; then
    echo "ERROR: no ZIP changes were collected; refusing a successful no-op." >&2
    return 1
  fi

  upload_and_verify
  delete_removed_zips
}

case "${1:-}" in
  collect)
    [ "$#" -eq 3 ] || { echo "Usage: $0 collect <before-sha> <after-sha>" >&2; exit 2; }
    collect "$2" "$3"
    ;;
  collect-all)
    [ "$#" -eq 1 ] || { echo "Usage: $0 collect-all" >&2; exit 2; }
    collect_all_command
    ;;
  sync)
    [ "$#" -eq 1 ] || { echo "Usage: $0 sync" >&2; exit 2; }
    sync
    ;;
  *)
    echo "Usage: $0 {collect <before-sha> <after-sha>|collect-all|sync}" >&2
    exit 2
    ;;
esac
