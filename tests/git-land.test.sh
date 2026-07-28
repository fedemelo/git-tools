#!/usr/bin/env bash
# Tests git-land end to end without touching GitHub: the remote is a local bare repo and
# `gh` is a stub earlier on PATH. The stub's `pr merge` reimplements what GitHub's
# rebase-merge does (replays the commits onto the base with new SHAs), because that is the
# path where git-land has to repair local history afterwards.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITLAND="$repo_root/bin/git-land"
ROOT="$(mktemp -d)"
trap 'cd /; rm -rf "$ROOT"' EXIT

pass=0; fail=0

check() {
  if [ "$2" = "$3" ]; then printf '  PASS %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL %s\n       got:  %s\n       want: %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# $1 = case name, $2 = commits to stack on top of upstream, $3 = 1 to reject direct pushes to main
setup() {
  local d="$ROOT/$1" n="$2" protect="${3:-0}"
  mkdir -p "$d/bin"
  git init -q --bare -b main "$d/remote.git"

  cat > "$d/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
case "${1:-} ${2:-}" in
  "repo view"|"api user") echo tester ;;
  "pr create")
    n=$(( $(cat "$PRCOUNT" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$PRCOUNT"
    title=""; body=""
    while [ $# -gt 0 ]; do
      case "$1" in --title) title="$2"; shift 2 ;; --body) body="$2"; shift 2 ;; *) shift ;; esac
    done
    printf 'PR%s\t%s\t%s\n' "$n" "$title" "$(echo "$body" | tr '\n' '~')" >> "$PRLOG"
    echo "https://example.test/pr/$n" ;;
  "pr comment") : ;;
  "pr merge")
    tmpref=$(git -C "$BARE" for-each-ref --format='%(refname:short)' 'refs/heads/tmp/*' | head -1)
    [ -n "$tmpref" ] || exit 1
    w=$(mktemp -d); git clone -q "$BARE" "$w" || exit 1
    (
      cd "$w"
      git config user.email t@t; git config user.name T; git config commit.gpgsign false
      git checkout -q main
      GIT_COMMITTER_DATE="2030-01-01T00:00:00 +0000" git cherry-pick "origin/main..origin/$tmpref" >/dev/null || exit 1
      touch "$BARE/allow-main"
      git push -q origin main || exit 1
      rm -f "$BARE/allow-main"
      git push -q origin --delete "$tmpref" || true
    ) || exit 1
    rm -rf "$w" ;;
  *) echo "stub gh: unhandled: $*" >&2; exit 1 ;;
esac
STUB
  chmod +x "$d/bin/gh"

  if [ "$protect" = "1" ]; then
    # A global core.hooksPath silently wins over a repo's own hooks dir, which would make
    # this hook never fire and quietly turn the protected-branch case into a happy-path one.
    git -C "$d/remote.git" config core.hooksPath "$d/remote.git/hooks"
    cat > "$d/remote.git/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
while read -r _ _ ref; do
  if [ "$ref" = "refs/heads/main" ] && [ ! -e "$GIT_DIR/allow-main" ]; then
    echo "pre-receive: main is protected" >&2; exit 1
  fi
done
HOOK
    chmod +x "$d/remote.git/hooks/pre-receive"
  fi

  git clone -q "$d/remote.git" "$d/work" 2>/dev/null
  cd "$d/work"
  git config user.email t@t; git config user.name T; git config commit.gpgsign false
  git checkout -q -b main 2>/dev/null
  echo base > base.txt; git add .; git commit -q -m "Base commit"
  touch "$d/remote.git/allow-main"
  git push -q -u origin main
  rm -f "$d/remote.git/allow-main"
  local i
  for i in $(seq 1 "$n"); do
    echo "$i" > "f$i.txt"; git add .; git commit -q -m "Change number $i"
  done
  export PATH="$d/bin:$PATH" BARE="$d/remote.git" PRLOG="$d/prs.tsv" PRCOUNT="$d/prcount"
  : > "$PRLOG"
}

remote_log() { git -C "$BARE" log --format='%s' main | tr '\n' ',' ; }
local_ahead() { git rev-list --count '@{u}..HEAD'; }
pr_count() { wc -l < "$PRLOG" | tr -d ' ' ; }
pr_titles() { cut -f2 "$PRLOG" | tr '\n' ',' ; }
pr_bodies() { cut -f3 "$PRLOG" | tr '\n' ',' ; }

echo "=== default: everything ahead lands as one PR ==="
setup default 3
"$GITLAND" >/dev/null 2>&1
check "remote main has all 3" "$(remote_log)" "Change number 3,Change number 2,Change number 1,Base commit,"
check "nothing left ahead" "$(local_ahead)" "0"
check "one PR opened" "$(pr_count)" "1"
check "PR body lists 3 commits" "$(pr_bodies)" "- Change number 3~- Change number 2~- Change number 1~,"

echo "=== --until lands a prefix and leaves the rest local ==="
setup until 4
c2="$(git rev-list --reverse '@{u}..HEAD' | sed -n 2p)"
"$GITLAND" "First two" --until "$c2" >/dev/null 2>&1
check "remote main at commit 2" "$(remote_log)" "Change number 2,Change number 1,Base commit,"
check "2 commits still ahead" "$(local_ahead)" "2"
check "PR titled from the argument" "$(pr_titles)" "First two,"
"$GITLAND" >/dev/null 2>&1
check "remainder lands afterwards" "$(remote_log)" "Change number 4,Change number 3,Change number 2,Change number 1,Base commit,"
check "nothing left ahead" "$(local_ahead)" "0"
check "two PRs total" "$(pr_count)" "2"
check "second PR body holds only the last 2" "$(cut -f3 "$PRLOG" | sed -n 2p)" "- Change number 4~- Change number 3~"

echo "=== --each: one PR per commit ==="
setup each 3
"$GITLAND" --each >/dev/null 2>&1
check "remote main has all 3" "$(remote_log)" "Change number 3,Change number 2,Change number 1,Base commit,"
check "three PRs opened" "$(pr_count)" "3"
check "titles come from each commit" "$(pr_titles)" "Change number 1,Change number 2,Change number 3,"
check "each body holds exactly one commit" "$(pr_bodies)" "- Change number 1~,- Change number 2~,- Change number 3~,"

echo "=== --each --until: one PR per commit, up to a ceiling ==="
setup eachuntil 4
c2="$(git rev-list --reverse '@{u}..HEAD' | sed -n 2p)"
"$GITLAND" --each --until "$c2" >/dev/null 2>&1
check "remote main at commit 2" "$(remote_log)" "Change number 2,Change number 1,Base commit,"
check "2 commits still ahead" "$(local_ahead)" "2"
check "one PR per landed commit" "$(pr_titles)" "Change number 1,Change number 2,"

echo "=== rejected input lands nothing ==="
setup validate 2
git checkout -q -b side; echo x > side.txt; git add .; git commit -q -m "Side commit"
side="$(git rev-parse HEAD)"; git checkout -q main
out="$("$GITLAND" --until "$side" 2>&1)"
check "rejects a commit off this branch" "$(echo "$out" | grep -c 'not an ancestor of HEAD')" "1"
out="$("$GITLAND" --until '@{u}' 2>&1)"
check "rejects upstream itself" "$(echo "$out" | grep -c 'already on')" "1"
out="$("$GITLAND" --until 'HEAD~5' 2>&1)"
check "rejects a ref behind upstream" "$(echo "$out" | grep -c 'is not a commit\|not ahead of')" "1"
out="$("$GITLAND" --until nope123 2>&1)"
check "rejects a bad ref" "$(echo "$out" | grep -c 'is not a commit')" "1"
out="$("$GITLAND" --each "A title" 2>&1)"
check "rejects --each with a title" "$(echo "$out" | grep -c 'ambiguous')" "1"
out="$("$GITLAND" --bogus 2>&1)"
check "rejects unknown flags" "$(echo "$out" | grep -c 'unknown flag')" "1"
out="$("$GITLAND" --until 2>&1)"
check "rejects --until with no value" "$(echo "$out" | grep -c 'needs a commit')" "1"
check "remote untouched" "$(remote_log)" "Base commit,"
check "no PRs opened" "$(pr_count)" "0"
"$GITLAND" --until 'HEAD~1' >/dev/null 2>&1
check "accepts HEAD~n" "$(remote_log)" "Change number 1,Base commit,"

echo "=== protected branch: the rebase fallback keeps unlanded commits ==="
setup protected 4 1
c2="$(git rev-list --reverse '@{u}..HEAD' | sed -n 2p)"
before="$(git log --format='%s' -2 HEAD | tr '\n' ',')"
out="$("$GITLAND" --until "$c2" 2>&1)"
check "direct push really was refused" "$(echo "$out" | grep -c 'falling back to API rebase-merge')" "1"
check "remote rebase-merged the prefix" "$(remote_log)" "Change number 2,Change number 1,Base commit,"
check "unlanded commits survived" "$(git log --format='%s' -2 HEAD | tr '\n' ',')" "$before"
check "still exactly 2 ahead" "$(local_ahead)" "2"
check "replayed onto the rewritten remote head" "$(git rev-parse 'HEAD~2')" "$(git rev-parse origin/main)"
"$GITLAND" >/dev/null 2>&1
check "remainder lands afterwards" "$(remote_log)" "Change number 4,Change number 3,Change number 2,Change number 1,Base commit,"
check "nothing left ahead" "$(local_ahead)" "0"

printf '\n=== %d passed, %d failed ===\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
