#!/usr/bin/env python3

"""Create or refresh the release PR from develop into master.

The release PR is opened from a snapshot branch named ``release`` that is cut
from ``origin/develop``. develop itself must never be the PR head: Flathub
deletes the head branch after a merge, and develop has to survive releases.

The branch is only ever fast-forwarded to ``origin/develop``. Commits that are
not on develop make the script fail instead of being force-pushed away: fixes
belong on develop, from where the next refresh picks them up.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

import git
from ruamel.yaml import YAML

SCRIPT_DIR = Path(__file__).parent
MANIFEST_FILE = SCRIPT_DIR / "eu.betterbird.Betterbird.yml"
BASE_BRANCH = "master"
STAGING_BRANCH = "develop"
RELEASE_BRANCH = "release"


def run_git(repo: git.Repo, *args: str) -> str:
    return repo.git.execute(["git", *args]).strip()


def manifest_version() -> str:
    """Return the Betterbird version recorded in the manifest."""
    yaml = YAML()
    with open(MANIFEST_FILE) as f:
        manifest = yaml.load(f)

    for module in manifest.get("modules", []):
        if not isinstance(module, dict) or module.get("name") != "betterbird":
            continue
        for source in module.get("sources", []):
            if isinstance(source, dict) and source.get("dest") == "thunderbird-patches":
                if source.get("tag"):
                    return source["tag"]
                commit = source.get("commit")
                if commit:
                    return commit[:7]
                break

    print(
        f"Error: no thunderbird-patches source with a tag or commit in {MANIFEST_FILE}",
        file=sys.stderr,
    )
    sys.exit(1)


def stray_master_commits(repo: git.Repo) -> list[str]:
    output = run_git(
        repo,
        "rev-list",
        "--no-merges",
        f"origin/{STAGING_BRANCH}..origin/{BASE_BRANCH}",
    )
    return [line for line in output.splitlines() if line]


def fetch_branches(repo: git.Repo) -> None:
    """Fetch both branches explicitly; actions/checkout may use a narrow refspec."""
    run_git(
        repo,
        "fetch",
        "origin",
        f"+refs/heads/{BASE_BRANCH}:refs/remotes/origin/{BASE_BRANCH}",
        f"+refs/heads/{STAGING_BRANCH}:refs/remotes/origin/{STAGING_BRANCH}",
    )


def build_changelog(repo: git.Repo, release_branch: str) -> str:
    return run_git(
        repo,
        "log",
        "--no-merges",
        "--reverse",
        "--format=- %h %s",
        f"origin/{BASE_BRANCH}..origin/{release_branch}",
    )


def build_body(changelog: str, strays: list[str], release_branch: str) -> str:
    commits = [line for line in changelog.splitlines() if line.strip()]
    parts = [
        "Automated release PR. Merge with a **merge commit** only; do not "
        "squash or rebase.",
        "",
        "### Changes since the last release",
        "",
    ]
    if commits:
        parts.append(f"{len(commits)} commit{'s' if len(commits) != 1 else ''}:")
        parts.append("")
        parts.append(changelog)
    else:
        parts.append("No changes since the last release.")

    if strays:
        parts += [
            "",
            "> **Warning:** master has commits that are not on "
            f"`{STAGING_BRANCH}` ({', '.join(sha[:7] for sha in strays)}). "
            "Move them to develop before releasing.",
        ]

    parts += [
        "",
        "### After merging",
        "",
        f"- `{release_branch}` is deleted automatically.",
        f"- `{STAGING_BRANCH}` is unchanged; every commit in this branch is "
        f"already on it.",
    ]
    return "\n".join(parts) + "\n"


def ensure_release_branch(repo: git.Repo, release_branch: str) -> None:
    remote_branch = f"origin/{release_branch}"
    exists = bool(run_git(repo, "ls-remote", "--heads", "origin", release_branch))
    if not exists:
        print(f"Creating {release_branch} from origin/{STAGING_BRANCH}.")
        run_git(
            repo,
            "push",
            "origin",
            f"refs/remotes/origin/{STAGING_BRANCH}:refs/heads/{release_branch}",
        )
        return

    ancestor = subprocess.run(
        [
            "git",
            "-C",
            str(repo.working_dir),
            "merge-base",
            "--is-ancestor",
            remote_branch,
            f"origin/{STAGING_BRANCH}",
        ]
    )
    if ancestor.returncode != 0:
        print(
            f"Error: {release_branch} has commits that are not on "
            f"{STAGING_BRANCH}. The sync-release workflow merges them into "
            f"{STAGING_BRANCH}; wait for it, or merge them by hand. The branch "
            "is only ever fast-forwarded.",
            file=sys.stderr,
        )
        sys.exit(1)

    if run_git(repo, "rev-parse", remote_branch) == run_git(
        repo, "rev-parse", f"origin/{STAGING_BRANCH}"
    ):
        print(f"{release_branch} is already up to date.")
        return

    print(f"Fast-forwarding {release_branch} to origin/{STAGING_BRANCH}.")
    run_git(
        repo,
        "push",
        "origin",
        f"refs/remotes/origin/{STAGING_BRANCH}:refs/heads/{release_branch}",
    )


def find_open_pr(release_branch: str) -> int | None:
    result = subprocess.run(
        [
            "gh",
            "pr",
            "list",
            "--head",
            release_branch,
            "--base",
            BASE_BRANCH,
            "--state",
            "open",
            "--json",
            "number",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    numbers = [
        entry["number"]
        for entry in json.loads(result.stdout or "[]")
        if isinstance(entry, dict) and "number" in entry
    ]
    return numbers[0] if numbers else None


def upsert_pr(release_branch: str, title: str, body: str) -> None:
    number = find_open_pr(release_branch)
    command = ["gh", "pr"]
    if number is None:
        command += [
            "create",
            "--base",
            BASE_BRANCH,
            "--head",
            release_branch,
            "--title",
            title,
        ]
    else:
        command += ["edit", str(number), "--title", title]

    subprocess.run(
        command + ["--body-file", "-"],
        input=body,
        text=True,
        check=True,
    )
    if number is None:
        print(f"Created release PR for {release_branch}.")
    else:
        print(f"Updated release PR #{number} for {release_branch}.")


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="print the changelog and PR body without pushing or editing the PR",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    repo = git.Repo(SCRIPT_DIR)
    fetch_branches(repo)

    version = manifest_version()
    release_branch = RELEASE_BRANCH
    strays = stray_master_commits(repo)

    if not run_git(
        repo, "diff", "--name-only", f"origin/{BASE_BRANCH}..origin/{STAGING_BRANCH}"
    ):
        print(
            f"No content changes between origin/{BASE_BRANCH} and "
            f"origin/{STAGING_BRANCH}; nothing to release."
        )
        return

    if args.dry_run:
        changelog = run_git(
            repo,
            "log",
            "--no-merges",
            "--reverse",
            "--format=- %h %s",
            f"origin/{BASE_BRANCH}..origin/{STAGING_BRANCH}",
        )
        print(f"release branch: {release_branch}")
        print(f"stray master commits: {len(strays)}")
        print()
        print(build_body(changelog, strays, release_branch))
        return

    ensure_release_branch(repo, release_branch)

    changelog = build_changelog(repo, release_branch)
    if not changelog:
        print(
            f"Error: origin/{BASE_BRANCH}..origin/{release_branch} contains no "
            "commits; there is nothing to release.",
            file=sys.stderr,
        )
        sys.exit(1)

    if strays:
        print(
            f"Warning: master has {len(strays)} commit(s) that are not on "
            f"{STAGING_BRANCH}.",
            file=sys.stderr,
        )

    title = f"Release {version}"
    body = build_body(changelog, strays, release_branch)
    upsert_pr(release_branch, title, body)


if __name__ == "__main__":
    main()
