#!/usr/bin/env bash
# Tests install.sh against a sandboxed HOME, so a run never touches the real ~/.local/bin,
# ~/.config/git or ~/.gitconfig. install.sh reads $HOME for every path it writes, including
# the global git config, which is what makes the sandbox complete.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

pass=0; fail=0

check() {
  if [ "$2" = "$3" ]; then printf '  PASS %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL %s\n       got:  %s\n       want: %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

new_home() { mktemp -d "$ROOT/home.XXXXXX"; }
install_into() { HOME="$1" "$repo_root/install.sh"; }

echo "=== fresh install on an empty HOME ==="
h="$(new_home)"
out="$(install_into "$h")"
check "git-land is linked" "$(readlink "$h/.local/bin/git-land")" "$repo_root/bin/git-land"
check "the commit-msg hook is linked" "$(readlink "$h/.config/git/hooks/commit-msg")" "$repo_root/hooks/commit-msg"
check "core.hooksPath is set" "$(HOME="$h" git config --global --get core.hooksPath)" "$h/.config/git/hooks"
check "the hook is verified live" "$(echo "$out" | grep -c 'Verified: commit-msg hook')" "1"
check "nothing reported as pruned" "$(echo "$out" | grep -c 'Pruned')" "0"

echo "=== a link to a script removed upstream is pruned ==="
h="$(new_home)"; install_into "$h" >/dev/null
ln -sf "$repo_root/bin/git-removed" "$h/.local/bin/git-removed"
ln -sf "$repo_root/hooks/removed-hook" "$h/.config/git/hooks/removed-hook"
out="$(install_into "$h")"
check "the stale bin link is gone" "$(test -L "$h/.local/bin/git-removed" && echo present || echo gone)" "gone"
check "the stale hook link is gone" "$(test -L "$h/.config/git/hooks/removed-hook" && echo present || echo gone)" "gone"
check "both prunes are reported" "$(echo "$out" | grep -c 'Pruned stale link')" "2"
check "git-land is still linked" "$(readlink "$h/.local/bin/git-land")" "$repo_root/bin/git-land"

echo "=== links owned by anything else are left alone ==="
h="$(new_home)"; install_into "$h" >/dev/null
ln -sf "/nonexistent/other-tool/bin/othertool" "$h/.local/bin/othertool"   # someone else's broken link
mkdir -p "$h/real"; printf '#!/bin/sh\n' > "$h/real/mytool"; chmod +x "$h/real/mytool"
ln -sf "$h/real/mytool" "$h/.local/bin/mytool"                            # someone else's working link
printf '#!/bin/sh\n' > "$h/.config/git/hooks/pre-commit"                  # a hook of your own
chmod +x "$h/.config/git/hooks/pre-commit"
out="$(install_into "$h")"
check "a broken link to another tool survives" "$(test -L "$h/.local/bin/othertool" && echo kept)" "kept"
check "nothing is reported as pruned" "$(echo "$out" | grep -c 'Pruned')" "0"
check "a working link of your own survives" "$(readlink "$h/.local/bin/mytool")" "$h/real/mytool"
check "a hook file of your own survives" "$(test -f "$h/.config/git/hooks/pre-commit" && echo kept)" "kept"

echo "=== re-running changes nothing ==="
h="$(new_home)"; install_into "$h" >/dev/null
out="$(install_into "$h")"
check "no prunes on a second run" "$(echo "$out" | grep -c 'Pruned')" "0"
check "still verified" "$(echo "$out" | grep -c 'Verified: commit-msg hook')" "1"
check "hooksPath unchanged" "$(HOME="$h" git config --global --get core.hooksPath)" "$h/.config/git/hooks"

printf '\n=== %d passed, %d failed ===\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
