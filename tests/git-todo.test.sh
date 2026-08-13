#!/usr/bin/env bash
# Tests git-todo without touching GitHub: `gh` is a stub earlier on PATH that records the
# arguments it was called with, so the assertions are about what git-todo would have asked
# GitHub to create.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITTODO="$repo_root/bin/git-todo"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

pass=0; fail=0

check() {
  if [ "$2" = "$3" ]; then printf '  PASS %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL %s\n       got:  %s\n       want: %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

mkdir -p "$ROOT/bin"
cat > "$ROOT/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Records each flag on its own line so a value containing spaces stays intact.
{
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) echo "title=$2"; shift 2 ;;
      --body) echo "body=$2"; shift 2 ;;
      --assignee) echo "assignee=$2"; shift 2 ;;
      *) shift ;;
    esac
  done
} > "$GH_LOG"
echo "https://github.com/o/r/issues/42"
STUB
chmod +x "$ROOT/bin/gh"
export PATH="$ROOT/bin:$PATH"

run() { GH_LOG="$ROOT/gh.log" "$GITTODO" "$@" 2>"$ROOT/err"; }
logged() { grep "^$1=" "$ROOT/gh.log" | sed "s/^$1=//"; }

echo "=== a one-word title ==="
out="$(run "Fix")"
check "the title is passed through" "$(logged title)" "Fix"
check "the body is empty" "$(logged body)" ""
check "it assigns to you" "$(logged assignee)" "@me"
check "it prints the issue url" "$(echo "$out" | grep -c 'opened https://github.com/o/r/issues/42')" "1"
check "it prints the Fixes reminder with the number" "$(echo "$out" | grep -c 'Fixes #42')" "1"

echo "=== an unquoted multi-word title is joined, not truncated ==="
run Add retry backoff to the worker >/dev/null
check "every word survives" "$(logged title)" "Add retry backoff to the worker"

echo "=== a body via -b and --body ==="
run "Fix the thing" -b "Some detail" >/dev/null
check "-b sets the body" "$(logged body)" "Some detail"
check "the title excludes the body" "$(logged title)" "Fix the thing"
run "Fix the thing" --body "Longer detail here" >/dev/null
check "--body sets the body" "$(logged body)" "Longer detail here"

echo "=== a body given before the title ==="
run -b "Detail first" "The title" >/dev/null
check "the body is still the body" "$(logged body)" "Detail first"
check "the title is still the title" "$(logged title)" "The title"

echo "=== nothing at all ==="
: > "$ROOT/gh.log"
run; code=$?
check "it exits non-zero" "$code" "1"
check "it prints usage" "$(grep -c 'usage: git todo' "$ROOT/err")" "1"
check "it never calls gh" "$(wc -c < "$ROOT/gh.log" | tr -d ' ')" "0"

echo "=== a body but no title ==="
: > "$ROOT/gh.log"
run -b "Only a body"; code=$?
check "it exits non-zero" "$code" "1"
check "it says the title is missing" "$(grep -c 'missing title' "$ROOT/err")" "1"
check "it never calls gh" "$(wc -c < "$ROOT/gh.log" | tr -d ' ')" "0"

printf '\n=== %d passed, %d failed ===\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
