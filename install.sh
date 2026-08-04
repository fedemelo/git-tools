#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$HOME/.local/bin" "$HOME/.config/git/hooks"

for script in "$repo_dir"/bin/*; do
  ln -sf "$script" "$HOME/.local/bin/$(basename "$script")"
done

ln -sf "$repo_dir/hooks/commit-msg" "$HOME/.config/git/hooks/commit-msg"
ln -sf "$repo_dir/ignore" "$HOME/.config/git/ignore"

# git has no default global hooks directory, so the commit-msg symlink above does nothing
# until this points at it. Set unconditionally: any other value leaves the hook dead.
git config --global core.hooksPath "$HOME/.config/git/hooks"

echo "Linked bin/* into ~/.local/bin (make sure it's on your PATH)"
echo "Linked hooks/commit-msg into ~/.config/git/hooks/commit-msg"
echo "Linked ignore into ~/.config/git/ignore"
echo "Set core.hooksPath to ~/.config/git/hooks so that hook runs"

# The symlink and core.hooksPath are separate pieces, and a mismatch leaves the hook inert
# without any error, so make a throwaway commit and confirm the trailer is really stripped.
check_dir="$(mktemp -d)"
trap 'rm -rf "$check_dir"' EXIT
git init -q "$check_dir"
git -C "$check_dir" config user.email install@check
git -C "$check_dir" config user.name "Install Check"
git -C "$check_dir" config commit.gpgsign false
: > "$check_dir/probe"
git -C "$check_dir" add probe
printf 'Check the hook\n\nCo-Authored-By: Nobody <nobody@example.com>\n' \
  | git -C "$check_dir" commit -q -F -

if git -C "$check_dir" log -1 --format=%B | grep -qi 'co-authored-by'; then
  echo "FAILED: the commit-msg hook did not strip an attribution trailer, so it is not running" >&2
  exit 1
fi
echo "Verified: commit-msg hook strips attribution trailers"
echo
echo "Otherwise untouched: ~/.gitconfig — copy gitconfig.example to ~/.gitconfig and fill in"
echo "your name, email, and a GPG signing key (see README for details)."
