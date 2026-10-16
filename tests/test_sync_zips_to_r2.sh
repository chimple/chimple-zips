#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/sync_zips_to_r2.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass=0
fail=0

new_repo() {
  local repo="$TMP_ROOT/repo-$RANDOM-$RANDOM"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name test
  printf base > "$repo/base.txt"
  git -C "$repo" add .
  git -C "$repo" commit -qm base
  printf '%s' "$repo"
}

assert_line() {
  grep -Fqx -- "$2" "$1"
}

run_test() {
  local name="$1"
  shift
  if "$@"; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name" >&2
    fail=$((fail + 1))
  fi
}

collect_insert_update_spaces() {
  local repo="$1"
  mkdir -p "$repo/nested path"
  printf original > "$repo/nested path/updated file.zip"
  git -C "$repo" add . && git -C "$repo" commit -qm 'add zip to update'
  local before="$(git -C "$repo" rev-parse HEAD)"
  printf one > "$repo/insert.zip"
  printf updated > "$repo/nested path/updated file.zip"
  printf ignored > "$repo/ignored.ZIP"
  git -C "$repo" add . && git -C "$repo" commit -qm 'insert and update'
  local after="$(git -C "$repo" rev-parse HEAD)"
  (cd "$repo" && CHANGED_ZIPS_FILE=changed.txt DELETED_ZIPS_FILE=deleted.txt bash "$SCRIPT" collect "$before" "$after") || return 1
  assert_line "$repo/changed.txt" insert.zip || return 1
  assert_line "$repo/changed.txt" 'nested path/updated file.zip' || return 1
  ! assert_line "$repo/changed.txt" ignored.ZIP
}

collect_rename_delete() {
  local repo="$1"
  printf old > "$repo/old.zip"
  git -C "$repo" add . && git -C "$repo" commit -qm 'add old zip'
  local before="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" mv "$repo/old.zip" "$repo/new name.zip"
  git -C "$repo" add -A && git -C "$repo" commit -qm 'rename zip'
  local after="$(git -C "$repo" rev-parse HEAD)"
  (cd "$repo" && CHANGED_ZIPS_FILE=changed.txt DELETED_ZIPS_FILE=deleted.txt bash "$SCRIPT" collect "$before" "$after") || return 1
  assert_line "$repo/changed.txt" 'new name.zip' || return 1
  assert_line "$repo/deleted.txt" old.zip || return 1
}

collect_delete() {
  local repo="$1"
  printf old > "$repo/delete-me.zip"
  git -C "$repo" add . && git -C "$repo" commit -qm 'add zip to delete'
  local before="$(git -C "$repo" rev-parse HEAD)"
  rm "$repo/delete-me.zip"
  git -C "$repo" add -A && git -C "$repo" commit -qm 'delete zip'
  local after="$(git -C "$repo" rev-parse HEAD)"
  (cd "$repo" && CHANGED_ZIPS_FILE=changed.txt DELETED_ZIPS_FILE=deleted.txt bash "$SCRIPT" collect "$before" "$after") || return 1
  assert_line "$repo/deleted.txt" delete-me.zip || return 1
}

collect_multiple_commits() {
  local repo="$1"
  local before="$(git -C "$repo" rev-parse HEAD)"
  printf one > "$repo/first.zip"
  git -C "$repo" add . && git -C "$repo" commit -qm first
  printf two > "$repo/second.zip"
  git -C "$repo" add . && git -C "$repo" commit -qm second
  local after="$(git -C "$repo" rev-parse HEAD)"
  (cd "$repo" && CHANGED_ZIPS_FILE=changed.txt DELETED_ZIPS_FILE=deleted.txt bash "$SCRIPT" collect "$before" "$after") || return 1
  assert_line "$repo/changed.txt" first.zip || return 1
  assert_line "$repo/changed.txt" second.zip || return 1
}

mock_aws() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${AWS_LOG:?}"
store_key() {
  local uri="$1"
  uri="${uri#s3://}"
  printf '%s' "${uri#*/}"
}
case "${AWS_MODE:-ok}:${1:-}:${2:-}" in
  verify-fail:s3api:head-object) exit 1 ;;
  delete-fail:s3:rm) exit 7 ;;
esac
if [ "${1:-}" = s3 ] && [ "${2:-}" = cp ]; then
  key="$(store_key "$4")"
  mkdir -p "${MOCK_R2_ROOT}/$(dirname "$key")"
  cp "$3" "${MOCK_R2_ROOT}/$key"
elif [ "${1:-}" = s3api ] && [ "${2:-}" = head-object ]; then
  key="${MOCK_R2_ROOT}/$6"
  [ -f "$key" ]
  wc -c < "$key" | tr -d ' '
elif [ "${1:-}" = s3 ] && [ "${2:-}" = rm ]; then
  key="$(store_key "$3")"
  rm -f "${MOCK_R2_ROOT}/$key"
fi
EOF
  chmod +x "$bin/aws"
}

sync_upload_update_delete() {
  local repo="$1" bin="$TMP_ROOT/bin-content" store="$TMP_ROOT/store-content" object='nested path/file name.zip'
  mock_aws "$bin"
  mkdir -p "$store"
  mkdir -p "$repo/nested path"
  printf original > "$repo/$object"
  printf '%s\n' "$object" > "$repo/changed.txt"
  : > "$repo/deleted.txt"
  (cd "$repo" && PATH="$bin:$PATH" AWS_LOG="$repo/aws.log" MOCK_R2_ROOT="$store" \
    R2_BUCKET_NAME=test R2_ENDPOINT=https://example.invalid R2_ACCESS_KEY_ID=x R2_SECRET_ACCESS_KEY=x \
    CHANGED_ZIPS_FILE=changed.txt DELETED_ZIPS_FILE=deleted.txt bash "$SCRIPT" sync) || return 1
  [ "$(cat "$store/$object")" = original ] || return 1
  grep -Fq 's3api head-object' "$repo/aws.log" || return 1

  printf updated > "$repo/$object"
  (cd "$repo" && PATH="$bin:$PATH" AWS_LOG="$repo/aws.log" MOCK_R2_ROOT="$store" \
    R2_BUCKET_NAME=test R2_ENDPOINT=https://example.invalid R2_ACCESS_KEY_ID=x R2_SECRET_ACCESS_KEY=x \
    CHANGED_ZIPS_FILE=changed.txt DELETED_ZIPS_FILE=deleted.txt bash "$SCRIPT" sync) || return 1
  [ "$(cat "$store/$object")" = updated ] || return 1

  : > "$repo/changed.txt"
  printf '%s\n' "$object" > "$repo/deleted.txt"
  (cd "$repo" && PATH="$bin:$PATH" AWS_LOG="$repo/aws.log" MOCK_R2_ROOT="$store" \
    R2_BUCKET_NAME=test R2_ENDPOINT=https://example.invalid R2_ACCESS_KEY_ID=x R2_SECRET_ACCESS_KEY=x \
    CHANGED_ZIPS_FILE=changed.txt DELETED_ZIPS_FILE=deleted.txt bash "$SCRIPT" sync) || return 1
  [ ! -e "$store/$object" ] || return 1
}

sync_missing_stage_fails() {
  local repo="$1"
  printf 'missing.zip\n' > "$repo/changed.txt"
  : > "$repo/deleted.txt"
  ! (cd "$repo" && \
    R2_BUCKET_NAME=test \
    R2_ENDPOINT=https://example.invalid \
    R2_ACCESS_KEY_ID=x \
    R2_SECRET_ACCESS_KEY=x \
    CHANGED_ZIPS_FILE=changed.txt \
    DELETED_ZIPS_FILE=deleted.txt \
    bash "$SCRIPT" sync)
}

sync_verification_fails() {
  local repo="$1" bin="$TMP_ROOT/bin-verify"
  mock_aws "$bin"
  printf abc > "$repo/file.zip"
  printf 'file.zip\n' > "$repo/changed.txt"
  : > "$repo/deleted.txt"
  ! (cd "$repo" && PATH="$bin:$PATH" AWS_LOG="$repo/aws.log" AWS_MODE=verify-fail MOCK_R2_ROOT="$TMP_ROOT/store-verify" \
    R2_BUCKET_NAME=test R2_ENDPOINT=https://example.invalid R2_ACCESS_KEY_ID=x R2_SECRET_ACCESS_KEY=x \
    CHANGED_ZIPS_FILE=changed.txt DELETED_ZIPS_FILE=deleted.txt bash "$SCRIPT" sync)
}

sync_deletion_fails() {
  local repo="$1" bin="$TMP_ROOT/bin-delete"
  mock_aws "$bin"
  : > "$repo/changed.txt"
  printf 'old.zip\n' > "$repo/deleted.txt"
  ! (cd "$repo" && PATH="$bin:$PATH" AWS_LOG="$repo/aws.log" AWS_MODE=delete-fail MOCK_R2_ROOT="$TMP_ROOT/store-delete" \
    R2_BUCKET_NAME=test R2_ENDPOINT=https://example.invalid R2_ACCESS_KEY_ID=x R2_SECRET_ACCESS_KEY=x \
    CHANGED_ZIPS_FILE=changed.txt DELETED_ZIPS_FILE=deleted.txt bash "$SCRIPT" sync)
}

run_test 'insert/update, nested paths, spaces, lowercase-only extension policy' collect_insert_update_spaces "$(new_repo)"
run_test 'rename and delete' collect_rename_delete "$(new_repo)"
run_test 'ZIP deletion' collect_delete "$(new_repo)"
run_test 'multiple commits and direct push without PR lookup' collect_multiple_commits "$(new_repo)"
run_test 'upload, update, verification, and successful deletion' sync_upload_update_delete "$(new_repo)"
run_test 'missing staged ZIP fails' sync_missing_stage_fails "$(new_repo)"
run_test 'upload verification failure fails' sync_verification_fails "$(new_repo)"
run_test 'deletion failure reports the object key' sync_deletion_fails "$(new_repo)"

echo "Tests passed: $pass; failed: $fail"
[ "$fail" -eq 0 ]
