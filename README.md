# git-tools

Personal git workflow tooling: two subcommands plus supporting global config.

These tools also back the `land` / `todo` skills in [claude-config](https://github.com/fedemelo/claude-config), so install this repo first if you use those.

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

## `git land [title] [--until <commit>] [--each] [--force]`

Lands commits already ahead of your branch's upstream through a real PR instead of a plain
push: pushes to a disposable branch, opens a PR (title defaults to the last commit's subject),
comments that it was auto-created and merged without review, rebase-merges (no squash), and
deletes the temp branch.

By default it lands everything ahead of upstream as one PR. To split a stack across several
PRs:

- `--until <commit>` lands only `upstream..<commit>` and leaves everything above it local.
  Takes any commit-ish (`abc123`, `HEAD~2`, a tag). Run it again to land the next batch.
- `--each` lands every commit ahead as its own PR, titled from that commit's subject. Combine
  with `--until` to cap how far it goes. For the unusual case where each commit really is
  independent: one piece of work spread over a PR per commit can't be read or reverted as a
  unit, so reach for `--until` instead when the commits belong together.

Only a *prefix* of your history can be landed, because commits are a chain: you can land the
first two and then the rest, but never the first and third while skipping the second. So order
commits to match the PRs you want; there is no need to interleave committing and landing.

Refuses to run if:
- the branch is behind its upstream (pull/rebase first)
- there's nothing to land, or `--until` names a commit already on upstream
- `--until` names a commit that isn't an ancestor of `HEAD`, or that sits behind upstream
- `--each` is given an explicit title, which each commit supplies instead
- the remote repo isn't owned by your authenticated GitHub account — pass `--force` to override
  (stops the tool from ever auto-merging unreviewed work onto someone else's repo)

When the direct fast-forward push is refused (branch protection), it falls back to a
server-side rebase-merge, which rewrites the landed commits. Anything still unlanded on top of
them is replayed onto the new upstream head, so a partial land never strands local work.

## Tests

```sh
tests/git-land.test.sh
```

No dependencies and no network: the remote is a local bare repo and `gh` is a stub earlier on
`PATH`, including a stand-in for GitHub's rebase-merge so the branch-protection fallback is
covered too.

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
