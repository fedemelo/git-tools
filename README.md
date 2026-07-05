# git-tools

Personal git workflow tooling: two subcommands plus supporting global config.

## Install

```sh
git clone <this-repo-url>
cd git-tools
./install.sh
```

This symlinks:
- `bin/git-land`, `bin/git-todo` into `~/.local/bin` (make sure that's on your `PATH`)
- `hooks/commit-msg` into `~/.config/git/hooks/commit-msg`
- `ignore` into `~/.config/git/ignore` (git reads this automatically as the global gitignore)

It does **not** touch `~/.gitconfig` — see below.

## `git land [title] [--force]`

Takes commits already sitting on your local branch, ahead of its upstream, and lands them
through a real PR instead of a plain push: pushes them to a disposable branch, opens a PR
(title defaults to the last commit's subject), posts a short comment explaining the PR was
auto-created and merged without review, then merges via rebase (commits land individually,
no squash) and cleans up the temp branch.

Refuses to run if:
- the branch is behind its upstream (pull/rebase first)
- there's nothing to land
- the remote repo isn't owned by your authenticated GitHub account (pass `--force` to override
  — this exists to stop the tool from ever auto-merging unreviewed work onto someone else's repo)

## `git todo <title...> [-b|--body <body>]`

Opens a GitHub issue in the current repo in one line, assigned to you, no browser needed.
Prints the issue number and a reminder that `Fixes #N` in a later commit message will
auto-close it once that commit lands on the default branch.

## `~/.gitconfig`

Copy `gitconfig.example` to `~/.gitconfig` and fill in your name, email, and a GPG signing key
(`gpg --list-secret-keys --keyid-format=long`, generate one with `gpg --full-generate-key` if
you don't have one yet).

Setting up a new machine, you have two options:
- **Reuse your existing key**: `gpg --export-secret-keys --armor <KEYID> > key.asc` on the old
  machine, `gpg --import key.asc` on the new one.
- **Generate a new key**: run `gpg --full-generate-key`, then add the new public key at
  https://github.com/settings/keys so commits still show as "Verified".

**Do not store a GitHub token in `.gitconfig`.** Git has no such field for authentication —
use `gh auth login` instead, which stores credentials via your OS keychain, not a plaintext file.

## `hooks/commit-msg`

Strips any stray `Co-Authored-By:` trailer from commit messages before they're recorded.
