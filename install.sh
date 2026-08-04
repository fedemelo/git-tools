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
echo
echo "Otherwise untouched: ~/.gitconfig — copy gitconfig.example to ~/.gitconfig and fill in"
echo "your name, email, and a GPG signing key (see README for details)."
