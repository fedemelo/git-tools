"""The `gh` plumbing shared by the Python subcommands in bin/."""

import json
import os
import re
import shutil
import subprocess
import sys

PR_URL = re.compile(r"github\.com/([^/]+)/([^/]+)/pull/(\d+)")


class GhFailed(Exception):
    pass


def tool_name():
    return os.path.basename(sys.argv[0])


def fail(message):
    sys.exit(f"{tool_name()}: {message}")


def call_gh(*arguments):
    if shutil.which("gh") is None:
        raise GhFailed("'gh' is not installed (not found on PATH)")
    result = subprocess.run(["gh", *arguments], capture_output=True, text=True)
    if result.returncode != 0:
        raise GhFailed((result.stderr.strip() or f"gh {' '.join(arguments)} failed").splitlines()[0])
    return result.stdout


def call_gh_json(*arguments):
    output = call_gh(*arguments)
    try:
        return json.loads(output)
    except json.JSONDecodeError as error:
        raise GhFailed(f"gh returned output that is not JSON ({error})") from error


def gh(*arguments):
    try:
        return call_gh(*arguments)
    except GhFailed as error:
        fail(str(error))


def gh_json(*arguments):
    try:
        return call_gh_json(*arguments)
    except GhFailed as error:
        fail(str(error))


def resolve_target(spec, fields):
    """The PR the user meant: the one named, or else the current branch's.

    `gh pr view` already accepts a number, a URL or a branch, and already defaults to the
    current branch, so the only work here is reading the owner and repo back out of the URL
    it returns. Taking them from the URL rather than from the current directory is what lets
    a PR in another repo be addressed by link.
    """
    arguments = ["pr", "view", "--json", fields]
    if spec:
        arguments.insert(2, spec)
    target = gh_json(*arguments)

    match = PR_URL.search(target.get("url", ""))
    if not match:
        fail(f"could not read the owner and repository from {target.get('url')!r}")
    target["owner"], target["repo"] = match.group(1), match.group(2)
    return target
