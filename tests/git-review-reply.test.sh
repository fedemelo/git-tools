#!/usr/bin/env bash
# Tests git-review-reply without touching GitHub: `gh` is a stub earlier on PATH that records
# every call it gets, keeping each posted body in a file of its own, and answers `pr view` and
# the POSTs from canned fixtures. The checkout is a throwaway repo whose HEAD the fixture
# names as the PR's head, so the pushed-or-not check is exercised for real.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$repo_root/bin/git-review-reply"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

pass=0; fail=0

check() {
  if [ "$2" = "$3" ]; then printf '  PASS %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL %s\n       got:  %s\n       want: %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

check_has() {
  if printf '%s' "$2" | grep -Fq -e "$3"; then printf '  PASS %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL %s\n       missing: %s\n' "$1" "$3"; fail=$((fail+1)); fi
}

check_lacks() {
  if printf '%s' "$2" | grep -Fq -e "$3"; then printf '  FAIL %s\n       present: %s\n' "$1" "$3"; fail=$((fail+1))
  else printf '  PASS %s\n' "$1"; pass=$((pass+1)); fi
}

PR="https://github.com/fedemelo/demo/pull/7"
mkdir -p "$ROOT/bin" "$ROOT/bodies" "$ROOT/files"

git init -q "$ROOT/repo"
git -C "$ROOT/repo" config user.email test@test
git -C "$ROOT/repo" config user.name Test
git -C "$ROOT/repo" config commit.gpgsign false
git -C "$ROOT/repo" config core.hooksPath /dev/null
: > "$ROOT/repo/file"
git -C "$ROOT/repo" add file
git -C "$ROOT/repo" commit -q -m first
head="$(git -C "$ROOT/repo" rev-parse HEAD)"

view() {  # view <state> <isDraft> [<headRefOid>]
  printf '{"number": 7, "url": "%s", "state": "%s", "isDraft": %s, "headRefOid": "%s"}\n' \
    "$PR" "$1" "$2" "${3:-$head}" > "$ROOT/view.json"
}

# A POST to the path named in fail_path is refused, standing in for any error GitHub returns.
cat > "$ROOT/bin/gh" <<STUB
#!/usr/bin/env bash
n=\$(( \$(wc -l < "$ROOT/calls.log" 2>/dev/null || echo 0) + 1 ))
line="" previous=""
for argument in "\$@"; do
  if [ "\$previous" = "-f" ] && [ "\${argument#body=}" != "\$argument" ]; then
    printf '%s' "\${argument#body=}" > "$ROOT/bodies/\$n"
    line="\$line body=@\$n"
  else
    line="\$line \$argument"
  fi
  previous="\$argument"
done
echo "\${line# }" >> "$ROOT/calls.log"
case "\$1 \$2" in
  "pr view") cat "$ROOT/view.json" ;;
  "pr ready") exit 0 ;;
  "api -X")
    if [ "\$4" = "\$(cat "$ROOT/fail_path" 2>/dev/null)" ]; then echo "HTTP 422: Validation Failed" >&2; exit 1; fi
    printf '{"id": %d, "html_url": "$PR#issuecomment-%d"}' "\$((900 + n))" "\$((900 + n))" ;;
  *) echo "unexpected: \$*" >&2; exit 1 ;;
esac
STUB
chmod +x "$ROOT/bin/gh"
export PATH="$ROOT/bin:$PATH"

reset() { rm -f "$ROOT/calls.log" "$ROOT/fail_path" "$ROOT/bodies"/*; view OPEN false; }
calls() { cat "$ROOT/calls.log" 2>/dev/null; }
posts() { calls | grep -c '^api -X POST'; }
replies_file() {  # replies_file <name> <replies JSON array>
  printf '{"pr": "%s", "replies": %s}\n' "$PR" "$2" > "$ROOT/files/$1.json"
  printf '%s' "$ROOT/files/$1.json"
}
run() { (cd "$ROOT/repo" && "$TOOL" "$@" >"$ROOT/out" 2>"$ROOT/err"); }

THREAD="$PR#discussion_r123"
REVIEW="$PR#pullrequestreview-456"
COMMENT="$PR#issuecomment-789"

three="$(replies_file three '[
  {"to": "'"$THREAD"'", "body": "Renamed it in 1a2b3c4."},
  {"to": "'"$REVIEW"'", "quote": "rename clip to useClipboard", "body": "Done in 1a2b3c4."},
  {"to": "'"$COMMENT"'", "quote": "CI is red\non the lint job.", "body": "Fixed the lint error in 9f3a1c2, see `@ci-bot`."}
]')"

echo "=== every reply goes up, in file order, then the PR becomes a draft ==="
reset
run "$three"
check "exits zero" "$?" "0"
check "reads the PR first" "$(calls | sed -n 1p)" "pr view $PR --json number,url,state,isDraft,headRefOid"
check "a thread comment is answered in its thread" "$(calls | sed -n 2p)" \
  "api -X POST repos/fedemelo/demo/pulls/7/comments/123/replies -f body=@2"
check "with the body as written" "$(cat "$ROOT/bodies/2")" "Renamed it in 1a2b3c4."
check "a review body is answered as a conversation comment" "$(calls | sed -n 3p)" \
  "api -X POST repos/fedemelo/demo/issues/7/comments -f body=@3"
check "that quotes it first" "$(cat "$ROOT/bodies/3")" "$(printf '> rename clip to useClipboard\n\nDone in 1a2b3c4.')"
check "a conversation comment is answered the same way, quoting every line" "$(cat "$ROOT/bodies/4")" \
  "$(printf '> CI is red\n> on the lint job.\n\nFixed the lint error in 9f3a1c2, see `@ci-bot`.')"
check "the PR becomes a draft right after the last post" "$(calls | sed -n 5p)" "pr ready $PR --undo"
check "and nothing else is called" "$(calls | wc -l | tr -d ' ')" "5"
report="$(cat "$ROOT/out")"
check "it reports what was posted, as JSON" \
  "$(printf '%s' "$report" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["pr"], *[p["to"] for p in d["posted"]], d["posted"][0]["id"], d["draft"])')" \
  "$PR $THREAD $REVIEW $COMMENT 902 converted"
check "with each new comment's URL" \
  "$(printf '%s' "$report" | python3 -c 'import json,sys; print(json.load(sys.stdin)["posted"][1]["url"])')" "$PR#issuecomment-903"

echo "=== a PR that is already a draft is left as it is ==="
reset; view OPEN true
run "$three"
check "exits zero" "$?" "0"
check "posts all three" "$(posts)" "3"
check_lacks "without touching the draft state" "$(calls)" "pr ready"
check "and says it was already one" \
  "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["draft"])' "$ROOT/out")" "already"

echo "=== a mention inside code is not a mention ==="
reset
run "$(replies_file code '[{"to": "'"$THREAD"'", "body": "Kept `@user` as is, mailed a@b.com.\n```\n@decorator\n/not-a-command\n```"}]')"
check "exits zero" "$?" "0"
check "posts it" "$(posts)" "1"

refused() {  # refused <description> <replies JSON array> <expected message>
  reset
  run "$(replies_file refused "$2")"
  check "$1: exits non-zero" "$?" "1"
  check_has "$1: says why" "$(cat "$ROOT/err")" "$3"
  check "$1: posts nothing" "$(posts)" "0"
  check_lacks "$1: leaves the draft state alone" "$(calls)" "pr ready"
}

echo "=== anything that would reach a person or a bot early refuses the whole file ==="
refused "a mention in a body" \
  '[{"to": "'"$THREAD"'", "body": "Fine."}, {"to": "'"$COMMENT"'", "quote": "x", "body": "Thanks @ana."}]' \
  "reply 2 ($COMMENT): its body mentions someone"
refused "a mention of a bot" '[{"to": "'"$THREAD"'", "body": "@coderabbitai resolve"}]' "its body mentions someone"
refused "a mention in a quote" \
  '[{"to": "'"$REVIEW"'", "quote": "As @ana said", "body": "Done."}]' "its quote mentions someone"
refused "a line starting with a slash" \
  '[{"to": "'"$THREAD"'", "body": "Done.\n  /approve"}]' "which bots read as a command"
refused "a quote on a thread reply" \
  '[{"to": "'"$THREAD"'", "quote": "x", "body": "Done."}]' "has a 'quote', but a thread comment"
refused "no quote on a review body" \
  '[{"to": "'"$REVIEW"'", "body": "Done."}]' "needs a non-empty 'quote'"
refused "an empty body" '[{"to": "'"$THREAD"'", "body": "  "}]' "has an empty body"
refused "the same target twice" \
  '[{"to": "'"$THREAD"'", "body": "One."}, {"to": "'"$THREAD"'", "body": "Two."}]' "appears more than once"
refused "a target on another PR" \
  '[{"to": "https://github.com/fedemelo/demo/pull/8#discussion_r1", "body": "Done."}]' "is on a different PR"
refused "a target that is not a feedback URL" \
  '[{"to": "'"$PR"'#pullrequestreview-1x", "body": "Done."}]' "is not a thread comment, review or conversation comment URL"

reset
run "$(replies_file many '[{"to": "'"$THREAD"'", "body": "@ana"}, {"to": "'"$REVIEW"'", "body": ""}]')"
check "every problem is listed at once" "$(grep -c '^  reply ' "$ROOT/err")" "3"
check_lacks "before the PR is even read" "$(calls)" "pr view"

echo "=== the replies go up only after the work they describe ==="
gate() {  # gate <description> <expected message>
  run "$three"
  check "$1: exits non-zero" "$?" "1"
  check_has "$1: says why" "$(cat "$ROOT/err")" "$2"
  check "$1: posts nothing" "$(posts)" "0"
  check_lacks "$1: leaves the draft state alone" "$(calls)" "pr ready"
}
reset; view CLOSED false
gate "a closed PR" "is closed, not open"
reset; view OPEN false 0000000000000000000000000000000000000000
gate "a HEAD the PR does not have yet" "commit and push first"
reset; echo change > "$ROOT/repo/file"
gate "a dirty working tree" "uncommitted changes"
git -C "$ROOT/repo" checkout -q -- file

echo "=== nothing to post touches nothing ==="
reset
run "$(replies_file none '[]')"
check "exits zero" "$?" "0"
check_has "says there was nothing to post" "$(cat "$ROOT/out")" "Nothing to post"
check "posts nothing" "$(posts)" "0"
check_lacks "and does not make the PR a draft" "$(calls)" "pr ready"

echo "=== a failed post stops the rest but still makes the PR a draft ==="
reset; echo "repos/fedemelo/demo/issues/7/comments" > "$ROOT/fail_path"
run "$three"
check "exits non-zero" "$?" "1"
check "stops at the failure" "$(posts)" "2"
check "then makes the PR a draft" "$(calls | tail -1)" "pr ready $PR --undo"
check_has "names what was posted" "$(cat "$ROOT/err")" "posted: $THREAD"
check_has "and what was not" "$(cat "$ROOT/err")" "not posted: $REVIEW, $COMMENT"
check "and reports both as JSON" \
  "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d["posted"]), len(d["unposted"]), d["draft"])' "$ROOT/out")" "1 2 converted"

echo "=== --dry-run shows everything and posts nothing ==="
reset
run "$three" --dry-run
check "exits zero" "$?" "0"
check "posts nothing" "$(posts)" "0"
check_lacks "and leaves the draft state alone" "$(calls)" "pr ready"
dry="$(cat "$ROOT/out")"
check_has "names each target" "$dry" "2. to $REVIEW, as a conversation comment quoting it"
check_has "with its full text" "$dry" "    > on the lint job."
check_has "and says the PR would become a draft" "$dry" "convert the PR to a draft"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
