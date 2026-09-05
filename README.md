# git-tools

> **New machine, or after any pull:** `git pull && ./install.sh` here, *before* doing the same in
> [claude-config](https://github.com/fedemelo/claude-config). Editing an existing script takes
> effect immediately through the symlinks, but adding or removing one does not, and the skills
> over there instruct flags that only a current `git-land` has.

Personal git workflow tooling: three subcommands plus supporting global config.

These tools also back the `land` / `todo` / PR-review skills in [claude-config](https://github.com/fedemelo/claude-config), so install this repo first if you use those.

## Prerequisites

- The [`gh` CLI](https://cli.github.com), authenticated with `gh auth login`. Every subcommand is a wrapper around it. `git-land` and `git-todo` fail with a bare `gh: command not found` without it; `git-review-feedback` says so itself.
- `python3`, for `git-review-feedback` alone. macOS ships it, and nothing here needs a package installed with it.
- `~/.gitconfig`, filled in from `gitconfig.example` as described below. `install.sh` sets only `core.hooksPath`, so a fresh machine still has no `user.email` and every commit fails until you do this.

## Install

```sh
git clone <this-repo-url>
cd git-tools
./install.sh
```

This symlinks:
- `bin/git-land`, `bin/git-todo`, `bin/git-review-feedback` into `~/.local/bin` (make sure that's on your `PATH`)
- `hooks/commit-msg` into `~/.config/git/hooks/commit-msg`
- `ignore` into `~/.config/git/ignore` (git reads this automatically as the global gitignore)

and sets one config key: `core.hooksPath` to `~/.config/git/hooks`. Git has no default global
hooks directory, so the `commit-msg` symlink above does nothing without it, and any other value
leaves the hook silently dead — hence setting it rather than trusting it.

It then proves the hook is live by committing a throwaway attribution trailer in a temp repo and
checking it was stripped, exiting non-zero if it survives.

**Re-run `./install.sh` after every pull.** Editing an existing script takes effect immediately,
since the installed paths are symlinks, but one *added* upstream has no link until you re-run,
and one renamed or removed upstream leaves a link pointing nowhere. Re-running creates the
first and prunes the second, touching only links that point back into this repo, since
`~/.local/bin` is shared with every other tool that installs itself there.

Being symlinks, editing the installed path edits the repo file directly, so they can't drift out of sync with it. Apart from that one key, it does **not** touch `~/.gitconfig` — see below.

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
tests/git-review-feedback.test.sh
tests/git-todo.test.sh
tests/install.test.sh
```

No dependencies and no network. For `git-land`, the remote is a local bare repo and `gh` is a
stub earlier on `PATH`, including a stand-in for GitHub's rebase-merge so the
branch-protection fallback is covered too. `git-todo` uses the same stub, recording the
arguments it would have sent. `git-review-feedback` uses a stub that answers from canned
fixtures, so what is asserted is how a review is grouped and printed rather than how any real PR
happens to look today. For `install.sh`, every case installs into a throwaway `HOME`, so running
the suite never touches your real `~/.local/bin` or `~/.gitconfig`.

## `git todo <title...> [-b|--body <body>]`

Opens a GitHub issue in the current repo, assigned to you, no browser needed. Prints the issue
number and a reminder that `Fixes #N` in a later commit auto-closes it once that commit lands
on the default branch.

## `git review-feedback [<pr>] [--all] [--author <logins>] [--json] [--raw]`

Prints every piece of review feedback on a pull request, grouped and ready to work through. The
PR is a number, a URL or a branch, and defaults to the current branch's.

GitHub keeps that feedback in three places, and no two of them overlap: inline review threads,
the body attached to a submitted review, and conversation comments. No single `gh` command
returns all three — `gh pr view --json comments` is conversation comments alone, and a review
body is not a thread — so reading one or two looks complete and is not. The body attached to an
*approval* is the one most often lost that way, and it regularly carries a request that no
thread mentions and that nobody can reply to. One query returns all three here, so skipping a
source is not something a caller can do by accident.

Each point gets an id (`R1`, `T1`, `C1`) to answer against, and each thread arrives with the
lines of the diff it is anchored to, numbered as in the file. Bots are told from humans by their
GitHub account type rather than by the shape of their login, since GitHub's own reviewer posts
as `copilot-pull-request-reviewer`.

By default it skips resolved threads, empty review bodies and your own unsubmitted `PENDING`
review, since none of those is a point anybody has to answer, and it says how many resolved
threads it hid. Bot markup that carries no information — HTML comments, `<picture>` blocks,
zero-width spaces — is stripped so the finding is readable.

| Flag | Effect |
|---|---|
| `--all` | include resolved threads, labelled as resolved |
| `--author <logins>` | only points raised by these logins, comma-separated |
| `--json` | the same data as JSON, for a tool to consume |
| `--raw` | leave bodies verbatim, stripping no markup |

It only ever reads. Nothing it does puts anything in front of a person on the PR.

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
