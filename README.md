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

Being symlinks, editing the installed path edits the repo file directly, so they can't drift out of sync with it. It does **not** touch `~/.gitconfig` — see below.

## `git land [title] [--force]`

Lands commits already ahead of your branch's upstream through a real PR instead of a plain
push: pushes to a disposable branch, opens a PR (title defaults to the last commit's subject),
comments that it was auto-created and merged without review, rebase-merges (no squash), and
deletes the temp branch.

Refuses to run if:
- the branch is behind its upstream (pull/rebase first)
- there's nothing to land
- the remote repo isn't owned by your authenticated GitHub account — pass `--force` to override
  (stops the tool from ever auto-merging unreviewed work onto someone else's repo)

## `git todo <title...> [-b|--body <body>]`

Opens a GitHub issue in the current repo, assigned to you, no browser needed. Prints the issue
number and a reminder that `Fixes #N` in a later commit auto-closes it once that commit lands
on the default branch.

## `~/.gitconfig`

Templated rather than symlinked because it can legitimately hold different values (name, email,
key) across machines. Copy `gitconfig.example` to `~/.gitconfig` and fill in your name, email, and a GPG signing key
(`gpg --list-secret-keys --keyid-format=long`; `gpg --full-generate-key` if you don't have one).

New machine, two options:
- **Reuse your key**: `gpg --export-secret-keys --armor <KEYID> > key.asc`, then
  `gpg --import key.asc` on the new machine.
- **New key**: `gpg --full-generate-key`, then add the public key at
  https://github.com/settings/keys so commits still show as "Verified".

### Committing under a different email in some repos

Override the global `user.email` per-repo with `git config user.email <other-email>` (e.g. a
university email for school repos). One GPG key can hold multiple UIDs and signs regardless of
which UID is active, so commits under either email still verify if:

1. The email is verified on your GitHub account (Settings → Emails).
2. It's a UID on your signing key: `gpg --quick-add-uid <KEYID> "Your Name <other-email>"`.
3. GitHub has the updated key — it won't refresh UIDs on an already-registered key, so
   delete and re-add it:
   ```sh
   gpg --armor --export <KEYID> > key.asc
   gh api user/gpg_keys --jq '.[] | select(.key_id == "<KEYID short form>") | .id'  # registration id
   gh api -X DELETE user/gpg_keys/<id>
   gh gpg-key add key.asc --title "<some title>"
   ```
   Only affects GitHub's verification badge, not the local key or commit history. Keep
   `key.asc` until the re-add succeeds.

Verify: `gh api repos/<owner>/<repo>/commits/<sha> --jq '.commit.verification'` should show
`"verified": true, "reason": "valid"`.

## `hooks/commit-msg`

Strips any stray `Co-Authored-By:` trailer from commit messages before they're recorded.
