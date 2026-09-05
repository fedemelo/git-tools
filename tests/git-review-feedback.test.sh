#!/usr/bin/env bash
# Tests git-review-feedback without touching GitHub: `gh` is a stub earlier on PATH that
# answers `pr view` and `api graphql` from canned fixtures, so the assertions are about what
# the tool does with a review, not about any particular PR still looking the way it did.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$repo_root/bin/git-review-feedback"
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

mkdir -p "$ROOT/bin"

cat > "$ROOT/view.json" <<'JSON'
{
  "number": 7,
  "title": "Add a clipboard preference",
  "url": "https://github.com/fedemelo/demo/pull/7",
  "reviewDecision": "CHANGES_REQUESTED",
  "isDraft": false,
  "headRefName": "clipboard"
}
JSON

# One review is APPROVED with a body, which is the case that used to be lost entirely: an
# approval carrying a request. One has no body and one is still PENDING, and neither is a
# point anybody has to answer.
cat > "$ROOT/graphql.json" <<'JSON'
{
  "data": { "repository": { "pullRequest": {
    "commits": { "nodes": [ { "commit": { "oid": "9f3a1c2ddddddddddddddddddddddddddddddddd", "committedDate": "2026-09-04T18:22:00Z" } } ] },
    "reviews": { "pageInfo": { "hasNextPage": false, "endCursor": null }, "nodes": [
      { "author": { "login": "babakks", "kind": "User" }, "state": "APPROVED",
        "body": "LGTM, though rename `clip` to `useClipboard` before merging.",
        "submittedAt": "2026-09-04T17:40:00Z", "url": "https://github.com/fedemelo/demo/pull/7#r1" },
      { "author": { "login": "reviewbot", "kind": "Bot" }, "state": "CHANGES_REQUESTED",
        "body": "<!-- marker --><picture><source srcset=\"x.svg\"></picture>Preserve the exported signature.<details><summary>Findings</summary>One</details>",
        "submittedAt": "2026-09-04T18:31:00Z", "url": "https://github.com/fedemelo/demo/pull/7#r2" },
      { "author": { "login": "quietone", "kind": "User" }, "state": "APPROVED",
        "body": "", "submittedAt": "2026-09-04T18:33:00Z", "url": "" },
      { "author": { "login": "fedemelo", "kind": "User" }, "state": "PENDING",
        "body": "half-written note to self", "submittedAt": null, "url": "" }
    ]},
    "comments": { "pageInfo": { "hasNextPage": false, "endCursor": null }, "nodes": [
      { "author": { "login": "williammartin", "kind": "User" },
        "body": "CI is red on the lint job.", "createdAt": "2026-09-04T19:02:00Z",
        "url": "https://github.com/fedemelo/demo/pull/7#c1" }
    ]},
    "reviewThreads": { "pageInfo": { "hasNextPage": false, "endCursor": null }, "nodes": [
      { "isResolved": false, "isOutdated": false, "path": "auth/login.go", "line": 88,
        "originalLine": 88, "startLine": null, "subjectType": "LINE",
        "comments": { "pageInfo": { "hasNextPage": false }, "nodes": [
          { "author": { "login": "williammartin", "kind": "User" },
            "body": "nil means unset, but defaultClip also covers an explicit false.",
            "createdAt": "2026-09-04T17:38:00Z",
            "diffHunk": "@@ -80,6 +84,5 @@ func newLoginFlow() {\n context line\n-\tclip := old()\n+\tclip := cfg.Clipboard()\n+\tif clip == nil {\n+\t\tclip = defaultClip\n+\t}",
            "url": "https://github.com/fedemelo/demo/pull/7#t1" },
          { "author": { "login": "fedemelo", "kind": "User" },
            "body": "Good catch, it is tri-state now.", "createdAt": "2026-09-04T17:55:00Z",
            "diffHunk": "", "url": "" }
        ]}},
      { "isResolved": true, "isOutdated": true, "path": "auth/refresh.go", "line": null,
        "originalLine": 12, "startLine": null, "subjectType": "LINE",
        "comments": { "pageInfo": { "hasNextPage": false }, "nodes": [
          { "author": { "login": "babakks", "kind": "User" }, "body": "Settled weeks ago.",
            "createdAt": "2026-09-01T09:00:00Z", "diffHunk": "@@ -10,2 +10,3 @@\n old\n+new", "url": "" }
        ]}}
    ]}
  }}}
}
JSON

cat > "$ROOT/bin/gh" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "pr view") cat "$ROOT/view.json" ;;
  "api graphql") cat "$ROOT/graphql.json" ;;
  *) echo "unexpected: \$*" >&2; exit 1 ;;
esac
STUB
chmod +x "$ROOT/bin/gh"
export PATH="$ROOT/bin:$PATH"

out="$("$TOOL" 2>"$ROOT/err")"
status=$?

echo "=== the three sources are all reported, every time ==="
check "exits zero" "$status" "0"
check_has "review summaries get a section" "$out" "REVIEW SUMMARIES (2)"
check_has "inline threads get a section" "$out" "INLINE THREADS (1"
check_has "conversation comments get a section" "$out" "CONVERSATION COMMENTS (1)"

echo "=== the body attached to an approval is never dropped ==="
check_has "the approval's own text is printed" "$out" "rename \`clip\` to \`useClipboard\`"
check_has "its state is shown, so APPROVED is visibly not the same as nothing to do" "$out" "[APPROVED]"
check_has "the section says an approval still counts" "$out" "An approval counts."

echo "=== a review nobody has to answer is not a point ==="
check_lacks "an empty-bodied approval is left out" "$out" "quietone"
check_lacks "an unsubmitted PENDING review is left out" "$out" "half-written note to self"
check_has "so the tally counts the four real points" "$out" "4 points to triage"

echo "=== resolved threads are out of the way unless asked for ==="
check_lacks "a resolved thread is hidden by default" "$out" "Settled weeks ago."
check_has "but it is counted, so the omission is visible" "$out" "1 resolved and hidden"
all="$("$TOOL" --all 2>/dev/null)"
check_has "--all brings it back" "$all" "Settled weeks ago."
check_has "--all labels it resolved" "$all" "resolved"
check_has "--all keeps GitHub's outdated verdict" "$all" "outdated"
check_has "a thread anchored to a line that moved falls back to the original" "$all" "auth/refresh.go:12"

echo "=== each point gets an id to reply against ==="
check_has "reviews are numbered from R1" "$out" "R1  babakks"
check_has "threads are numbered from T1" "$out" "T1  auth/login.go:88"
check_has "conversation comments are numbered from C1" "$out" "C1  williammartin"

echo "=== the code a comment is about arrives with it ==="
check_has "the hunk is numbered from the header, not from one" "$out" "84 |  context line"
check_has "each added line follows on" "$out" "87 | +		clip = defaultClip"
check_has "and the comment's own line is the last one, marked" "$out" "→    88 | +	}"
check_has "a deleted line carries no new-file number" "$out" "- | -	clip := old()"
check_has "replies are nested under the comment that started the thread" "$out" "└ fedemelo"

echo "=== a bot is told from a human by its account type, not its name ==="
check_has "a bot review is tagged" "$out" "reviewbot [bot]"
check_lacks "a human review is not" "$out" "babakks [bot]"

echo "=== bot markup is stripped so the point is readable ==="
check_has "the actual finding survives" "$out" "Preserve the exported signature."
check_lacks "an HTML comment marker does not" "$out" "<!-- marker -->"
check_lacks "nor a picture block" "$out" "<picture>"
check_has "a details summary is kept as text" "$out" "Findings"
check_lacks "without its tags" "$out" "<summary>"
raw="$("$TOOL" --raw 2>/dev/null)"
check_has "--raw leaves the markup alone" "$raw" "<picture>"

echo "=== a point written before the current head is flagged, not assumed dead ==="
check_has "an older review body is flagged" "$out" "written before the current head"
check "only the one point that predates it is flagged" \
  "$(printf '%s' "$out" | grep -c "written before the current head")" "1"

echo "=== scoping to one reviewer ==="
mine="$("$TOOL" --author williammartin 2>/dev/null)"
check_has "their thread is kept" "$mine" "T1  auth/login.go:88"
check_has "their conversation comment is kept" "$mine" "C1  williammartin"
check_lacks "someone else's approval is not" "$mine" "useClipboard"
check_has "and the sections still all appear" "$mine" "REVIEW SUMMARIES (0)"

echo "=== --json carries the same points ==="
as_json="$("$TOOL" --json 2>/dev/null)"
check "it parses" "$(printf '%s' "$as_json" | python3 -c 'import json,sys; json.load(sys.stdin); print("ok")')" "ok"
check "with one review, one thread, one comment" \
  "$(printf '%s' "$as_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d["reviews"]), len(d["threads"]), len(d["comments"]), d["resolvedHidden"])')" \
  "2 1 1 1"
check "and the PR it came from" \
  "$(printf '%s' "$as_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["pr"]["owner"], d["pr"]["repo"], d["pr"]["number"])')" \
  "fedemelo demo 7"

echo "=== a PR with no feedback at all says so ==="
cat > "$ROOT/graphql.json" <<'JSON'
{
  "data": { "repository": { "pullRequest": {
    "commits": { "nodes": [] },
    "reviews": { "pageInfo": { "hasNextPage": false, "endCursor": null }, "nodes": [] },
    "comments": { "pageInfo": { "hasNextPage": false, "endCursor": null }, "nodes": [] },
    "reviewThreads": { "pageInfo": { "hasNextPage": false, "endCursor": null }, "nodes": [] }
  }}}
}
JSON
empty="$("$TOOL" 2>/dev/null)"
check_has "it reports nothing to address" "$empty" "nothing to address"
check_has "and still names all three sources, so silence is a fact and not an omission" \
  "$empty" "CONVERSATION COMMENTS (0)"

echo "=== failures are reported, never papered over ==="
cat > "$ROOT/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "GraphQL: Could not resolve to a PullRequest with the number of 999." >&2
exit 1
STUB
chmod +x "$ROOT/bin/gh"
"$TOOL" 999 >"$ROOT/out" 2>"$ROOT/err"
check "a gh failure exits non-zero" "$?" "1"
check_has "and says what gh said" "$(cat "$ROOT/err")" "Could not resolve to a PullRequest"
check_has "prefixed by the tool" "$(cat "$ROOT/err")" "git-review-feedback:"
check "printing nothing that looks like feedback" "$(cat "$ROOT/out")" ""

rm "$ROOT/bin/gh"
mkdir -p "$ROOT/pybin"
ln -sf "$(command -v python3)" "$ROOT/pybin/python3"
PATH="$ROOT/bin:$ROOT/pybin" "$TOOL" >/dev/null 2>"$ROOT/err"
check "a missing gh exits non-zero" "$?" "1"
check_has "and says gh is missing rather than guessing" "$(cat "$ROOT/err")" "'gh' is not installed"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
