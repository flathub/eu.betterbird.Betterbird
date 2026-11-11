#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import git
from ruamel.yaml import YAML
from datetime import datetime
from pathlib import Path
from urllib.request import urlopen
from typing import Optional

# Configuration
SCRIPT_DIR = Path(__file__).parent
BETTERBIRD_REPO = "https://github.com/Betterbird/thunderbird-patches"
FLATHUB_DIR = SCRIPT_DIR
PATCHES_DIR = SCRIPT_DIR / "thunderbird-patches"
PACKAGE = "thunderbird"
PLATFORM = "linux-x86_64"
SOURCES_FILE = FLATHUB_DIR / f"{PACKAGE}-sources.json"
APPDATA_FILE = PATCHES_DIR / "metadata/eu.betterbird.Betterbird.153.appdata.xml"
MANIFEST_FILE = FLATHUB_DIR / "eu.betterbird.Betterbird.yml"
DIST_FILE = FLATHUB_DIR / "distribution.ini"
BUILD_DATE_FILE = FLATHUB_DIR / ".build-date"
KNOWN_TAGS_FILE = FLATHUB_DIR / ".known-tags"

# Number of times a push to develop is retried after a concurrent update.
MAX_PUSH_ATTEMPTS = 3


def fetch_develop(repo: git.Repo) -> None:
    """Fetch develop explicitly; actions/checkout may use a single-branch refspec."""
    repo.git.fetch("origin", "+refs/heads/develop:refs/remotes/origin/develop")


def log_verbose(verbose: bool, msg: str) -> None:
    """Print a progress message only when verbose mode is enabled."""
    if verbose:
        print(msg)


def run_cmd(
    cmd, cwd: Optional[Path] = None, check=True, capture=False, text=False
) -> str:
    """Run a shell command."""
    if not cwd:
        cwd = os.path.dirname(__file__)
    result = subprocess.run(
        cmd, shell=True, cwd=cwd, check=check, capture_output=capture, text=text
    )
    if capture:
        return result.stdout.strip()
    return ""


def parse_args():
    parser = argparse.ArgumentParser(
        description="Update Betterbird version",
        epilog=f"Examples: {sys.argv[0]} 102.2.2-bb16\n"
        f"          {sys.argv[0]} 102 4d587481bc7dbca1ffc99cce319f84425fab7852",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "version", nargs="?", help="Betterbird version (tag or major version)"
    )
    parser.add_argument(
        "commit",
        nargs="?",
        help="Betterbird commit hash (required if version is major version only)",
    )
    parser.add_argument(
        "-f", "--force", action="store_true", help="Skip version check from appdata.xml"
    )
    parser.add_argument(
        "-p",
        "--private-mirror",
        action="store_true",
        help="Replace upstream mirror with private mirror",
    )
    parser.add_argument(
        "-c",
        "--self-contained",
        action="store_true",
        help="Download source and XPI files directly to compute SHA256 hashes (skip SHA256SUMS file)",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Verbose: print progress messages for each step",
    )
    parser.add_argument(
        "--auto",
        nargs="?",
        const="",
        metavar="MAJOR_RELEASE",
        help="Automated mode: discover new tags, update, commit, and push to develop. "
        "Optionally pass the major release number to filter tags.",
    )
    return parser.parse_args()


def ensure_repo(verbose: bool = False):
    """Clone or update the Betterbird repository."""
    patches_path = Path(__file__).parent / "thunderbird-patches"
    if patches_path.exists():
        log_verbose(
            verbose,
            "[step 1/7] thunderbird-patches: repo exists, resetting to HEAD and fetching updates…",
        )
        log_verbose(verbose, "  Running: git reset --hard HEAD")
        repo = git.Repo(patches_path)
        repo.git.reset("--hard", "HEAD")
        log_verbose(verbose, "  Running: git fetch")
        repo.remotes.origin.fetch()
    else:
        log_verbose(
            verbose, f"[step 1/7] thunderbird-patches: cloning {BETTERBIRD_REPO}…"
        )
        git.Repo.clone_from(BETTERBIRD_REPO, patches_path, no_checkout=True)


def get_commit(version=None, commit=None, verbose: bool = False):
    """Checkout the specified commit and return its hash."""
    patches_path = Path(__file__).parent / "thunderbird-patches"
    repo = git.Repo(patches_path)
    if commit:
        log_verbose(verbose, f"  Resolving commit '{commit}' to SHA…")
        betterbird_commit = repo.rev_parse(commit).hexsha
    else:
        log_verbose(verbose, f"  Resolving tag '{version}' to SHA…")
        betterbird_commit = repo.rev_parse(version).hexsha
    log_verbose(verbose, f"  Checking out commit {betterbird_commit}")
    repo.git.checkout(betterbird_commit)
    return betterbird_commit


def get_appdata_version():
    """Extract version from appdata.xml."""
    content = Path(APPDATA_FILE).read_text()
    match = re.search(r'<release version="([^"]+)"', content)
    if match:
        return match.group(1)
    return None


def get_appdata_source_location():
    """Extract the full source artifact location URL from appdata.xml."""
    content = Path(APPDATA_FILE).read_text()
    match = re.search(
        r'<artifact type="source">\s*<location>([^<]+)</location>', content, re.DOTALL
    )
    if match:
        return match.group(1)
    return None


def get_base_url():
    """Extract base URL for sources from appdata.xml."""
    source_archive = get_appdata_source_location()
    if source_archive:
        # Remove the "/source/…" suffix to get base URL
        return re.sub(r"/source/.*$", "", source_archive)
    return None


def compute_sha256(url):
    """Compute SHA256 hash of a file given its URL."""
    h = hashlib.sha256()
    with urlopen(url) as response:
        while True:
            chunk = response.read(8192)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def update_sources_file(base_url, betterbird_version, verbose: bool = False):
    """Generate thunderbird-sources.json from SHA256SUMS."""
    log_verbose(verbose, "[step 5/7] Reading checksums from SHA256SUMS")

    # Get SHA256SUMS content
    with urlopen(f"{base_url}/SHA256SUMS") as response:
        sha256_output = response.read().decode()

    entries = []
    source_archive = None
    langpack_count = 0

    for line in sha256_output.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split("  ", 1)
        if len(parts) != 2:
            continue
        checksum, path = parts[0], parts[1].strip()

        if path.startswith(f"{PLATFORM}/xpi/"):
            locale_file = Path(path).name
            locale = locale_file.rsplit(".", 1)[0]

            # Check if Betterbird has a patch for this locale
            major_version = betterbird_version.split(".")[0]
            patch_script = Path(
                f"thunderbird-patches/{major_version}/scripts/{locale}.sh"
            )
            if patch_script.exists():
                langpack_count += 1
                log_verbose(
                    verbose, f"  [{langpack_count}] {locale} (SHA256: {checksum})"
                )
                entries.append(
                    {
                        "type": "file",
                        "url": f"{base_url}/{path}",
                        "sha256": checksum,
                        "dest": "langpacks/",
                        "dest-filename": f"langpack-{locale}@{PACKAGE}.mozilla.org.xpi",
                    }
                )
            else:
                log_verbose(
                    verbose,
                    f"  [{langpack_count + 1}] {locale} — skipping, no patch script",
                )
        elif path.startswith("source/"):
            source_archive = {
                "type": "archive",
                "url": f"{base_url}/{path}",
                "sha256": checksum,
            }
            log_verbose(verbose, f"  Source archive: {path} (SHA256: {checksum})")

    if source_archive is None:
        raise RuntimeError(
            "No source archive entry was found in SHA256SUMS. "
            "Try rerunning with -c to compute checksums directly, or file an issue."
        )

    # Write JSON array with source archive last
    all_entries = entries + [source_archive]
    with open(SOURCES_FILE, "w") as f:
        json.dump(all_entries, f, indent=4)
        f.write("\n")

    log_verbose(verbose, f"  Done. Sources written to {SOURCES_FILE}")


def update_manifest(
    betterbird_commit, source_spec, betterbird_version, verbose: bool = False
):
    """Update the thunderbird-patches source in the manifest.

    Uses ruamel.yaml round-trip mode so the rest of the manifest keeps its
    existing indentation, line wrapping and comments. PyYAML's yaml.dump()
    cannot do this: it always emits block sequences flush-left, so using it
    would rewrite the whole file into a different style. The manifest is kept
    in the checker-compatible indented style (the flatpak-external-data-checker
    emits and preserves that style), and re-dumping with PyYAML would make
    master and develop diverge on every update, which in turn made the
    automatic 'merge master into develop' conflict on ~700 whitespace-only
    lines.
    """
    log_verbose(
        verbose,
        f"[step 6/7] Updating {MANIFEST_FILE} (commit: {betterbird_commit}, source_spec: {source_spec})",
    )

    manifest_file = os.path.join(os.path.dirname(__file__), MANIFEST_FILE)

    yaml = YAML()
    # Use the exact same ruamel.yaml configuration as
    # flatpak-external-data-checker (src/lib/utils.py: ``_yaml``), so that
    # both tools serialise the manifest identically and do not fight over
    # formatting. The checker preserves comments but re-emits the file with
    # this style (the Flathub YAML style guide: 2-space mappings, 4-space
    # sequences indented by 2). No custom ``width`` is set, matching the
    # checker's default.
    yaml.indent(mapping=2, sequence=4, offset=2)

    with open(manifest_file, "r") as f:
        manifest = yaml.load(f)

    # Find the betterbird module's thunderbird-patches source.
    updated = False
    for module in manifest.get("modules", []):
        if isinstance(module, dict) and module.get("name") == "betterbird":
            for source in module.get("sources", []):
                if (
                    isinstance(source, dict)
                    and source.get("dest") == "thunderbird-patches"
                ):
                    source["commit"] = betterbird_commit
                    if source_spec == "tag":
                        log_verbose(
                            verbose,
                            f"  Setting tag in manifest to {betterbird_version}",
                        )
                        source["tag"] = betterbird_version
                    else:
                        log_verbose(
                            verbose,
                            "  Removing tag from manifest (commit-based update)",
                        )
                        source.pop("tag", None)
                    updated = True
                    break
            break

    if not updated:
        raise RuntimeError(
            f"Could not find the betterbird module's 'dest: thunderbird-patches' "
            f"source in {MANIFEST_FILE}; the manifest layout may have changed."
        )

    with open(manifest_file, "w") as f:
        yaml.dump(manifest, f)


def update_distribution_ini(betterbird_commit, verbose: bool = False):
    """Update version in distribution.ini."""
    repo = git.Repo("thunderbird-patches")
    short_commit = repo.rev_parse(betterbird_commit).hexsha[:7]
    log_verbose(
        verbose, f"[step 7/7] Updating version in {DIST_FILE} to {short_commit}"
    )
    dist_path = Path(DIST_FILE)
    content = dist_path.read_text()
    content = re.sub(
        r"^version=.*$", f"version={short_commit}", content, flags=re.MULTILINE
    )
    dist_path.write_text(content)


def update_known_tags(betterbird_version, verbose: bool = False):
    """Add version to .known-tags if not present."""
    known_tags = Path(KNOWN_TAGS_FILE)
    tags = []
    if known_tags.exists():
        tags = known_tags.read_text().splitlines()

    if betterbird_version not in tags:
        log_verbose(verbose, f"  Adding {betterbird_version} to {KNOWN_TAGS_FILE}")
        tags.append(betterbird_version)
        tags.sort()
        known_tags.write_text("\n".join(tags) + "\n")


def handle_private_mirror(betterbird_version, verbose: bool = False):
    """Download sources to private mirror and update URLs."""
    log_verbose(verbose, "  Uploading source tarballs to private mirror…")

    # Extract source archive URLs from sources.json using json
    with open(SOURCES_FILE, "r") as f:
        data = json.load(f)

    urls = [entry["url"] for entry in data if entry["type"] == "archive"]

    if not urls:
        print(
            "ERROR: no source archive URLs found in sources file. Aborting.",
            file=sys.stderr,
        )
        sys.exit(1)

    log_verbose(verbose, "    " + "\n    ".join(urls))

    for url in urls:
        run_cmd(
            f'ssh srv5dl "curl -C - --retry 5 --retry-all-errors -O --output-dir /srv/containers/dl {url}"'
        )

    log_verbose(
        verbose, f"  Rewriting URLs in {SOURCES_FILE} to point to private mirror"
    )

    # Replace URLs in sources.json
    with open(SOURCES_FILE, "r") as f:
        content = f.read()

    new_content = re.sub(
        r"https://archive\.mozilla\.org/.*/([^/]+)\.source\.tar\.xz",
        r"https://dl.mfs.name/\1.source.tar.xz",
        content,
    )

    with open(SOURCES_FILE, "w") as f:
        f.write(new_content)


def self_contained_update_sources(base_url, betterbird_version, verbose: bool = False):
    """Generate thunderbird-sources.json by downloading files and computing SHA256 hashes."""
    log_verbose(verbose, "[step 5/7] Computing checksums (self-contained mode)")

    # Get source archive URL from appdata.xml
    source_url = get_appdata_source_location()
    if not source_url:
        raise ValueError("Could not extract source archive location from appdata.xml")

    log_verbose(verbose, f"  Downloading source archive from {source_url}…")
    source_checksum = compute_sha256(source_url)
    log_verbose(verbose, f"  Source archive SHA256: {source_checksum}")
    log_verbose(verbose, f"  Source archive: {source_url} (SHA256: {source_checksum})")

    source_archive_entry = {
        "type": "archive",
        "url": source_url,
        "sha256": source_checksum,
    }

    entries = []
    # Determine which locales have patcher scripts
    major_version = betterbird_version.split(".")[0]
    scripts_dir = Path(f"thunderbird-patches/{major_version}/scripts")

    log_verbose(verbose, "  Checking language packs with patches…")
    locale_count = 0

    if scripts_dir.is_dir():
        for script_file in sorted(scripts_dir.iterdir()):
            if script_file.suffix == ".sh":
                locale = script_file.stem
                xpi_url = f"{base_url}/{PLATFORM}/xpi/{locale}.xpi"
                try:
                    sha256 = compute_sha256(xpi_url)
                    locale_count += 1
                    log_verbose(
                        verbose, f"  [{locale_count}] {locale} (SHA256: {sha256})"
                    )
                    entries.append(
                        {
                            "type": "file",
                            "url": xpi_url,
                            "sha256": sha256,
                            "dest": "langpacks/",
                            "dest-filename": f"langpack-{locale}@{PACKAGE}.mozilla.org.xpi",
                        }
                    )
                except Exception as exc:
                    log_verbose(
                        verbose,
                        f"  [{locale_count + 1}] {locale} — not available, skipping ({exc})",
                    )

    # Write JSON array with source archive last
    all_entries = entries + [source_archive_entry]
    with open(SOURCES_FILE, "w") as f:
        json.dump(all_entries, f, indent=4)
        f.write("\n")

    log_verbose(verbose, f"  Done. Sources written to {SOURCES_FILE}")


def read_known_tags() -> set:
    """Return the tags recorded in .known-tags."""
    if KNOWN_TAGS_FILE.exists():
        return set(KNOWN_TAGS_FILE.read_text().splitlines())
    return set()


def find_new_tags(patches_dir: str, known_tags, verbose: bool = False):
    """Return tags in thunderbird-patches that are not among the known tags."""
    patches_repo = git.Repo(patches_dir)
    # Version sort, so that callers can rely on the last entry being the newest.
    all_tags = patches_repo.git.tag("--sort=v:refname").splitlines()

    known_tags = set(known_tags)

    new_tags = [t for t in all_tags if t not in known_tags]
    if verbose and new_tags:
        log_verbose(verbose, f"[auto] New tags: {', '.join(new_tags)}")
    return new_tags


def auto_update(major_release: str, verbose: bool = False):
    """Run automated update: discover a new tag, commit to develop and push."""
    flathub_repo_git = git.Repo(FLATHUB_DIR)

    fetch_develop(flathub_repo_git)

    # --auto resets the checkout to origin/develop. Refuse to discard tracked
    # changes or local commits that are not on develop.
    if flathub_repo_git.git.status("--porcelain", "--untracked-files=no").strip():
        print(
            "Error: the flathub checkout has uncommitted changes. --auto resets "
            "it to origin/develop, so commit or stash them first.",
            file=sys.stderr,
        )
        sys.exit(1)
    if flathub_repo_git.git.rev_list("origin/develop..HEAD").strip():
        print(
            "Error: the flathub checkout has commits that are not on develop. "
            "--auto must run on a clean checkout of develop.",
            file=sys.stderr,
        )
        sys.exit(1)

    # The patches repository is ignored by git, so updating it cannot disturb
    # the checkout that is later reset to origin/develop.
    ensure_repo(verbose=verbose)

    known_tags = read_known_tags()
    new_tags = find_new_tags(PATCHES_DIR, known_tags, verbose=verbose)
    if not new_tags:
        print("No new tags found.")
        return

    # Filter by major release and take the newest tag, so that a run which
    # missed several tags jumps straight to the latest one.
    matching = [tag for tag in new_tags if tag.split(".")[0] == major_release]
    for tag in new_tags:
        if tag not in matching:
            log_verbose(
                verbose,
                f"[auto] Skipping {tag}: major version does not match {major_release}",
            )

    if not matching:
        print(f"No new tags found for major release {major_release}.")
        return

    target_tag = matching[-1]

    log_verbose(verbose, f"[auto] Updating to {target_tag}…")
    betterbird_commit = get_commit(target_tag, None, verbose=verbose)

    base_url = get_base_url()
    if not base_url:
        print(f"Error: Could not extract base URL from {APPDATA_FILE}")
        return

    for attempt in range(1, MAX_PUSH_ATTEMPTS + 1):
        log_verbose(
            verbose,
            f"[auto] Resetting checkout to origin/develop "
            f"(attempt {attempt}/{MAX_PUSH_ATTEMPTS})…",
        )
        fetch_develop(flathub_repo_git)
        flathub_repo_git.git.switch("-C", "develop", "origin/develop")

        # A concurrent run may have landed the tag while this one was working.
        if target_tag in read_known_tags():
            print(f"{target_tag} is already present on develop; nothing to do.")
            return

        # Save build date
        build_date = datetime.now().astimezone().strftime("%Y%m%d%H%M%S")
        Path(BUILD_DATE_FILE).write_text(build_date + "\n")

        # Update sources, manifest, distribution.ini, known tags
        update_sources_file(base_url, target_tag, verbose=verbose)
        update_manifest(betterbird_commit, "tag", target_tag, verbose=verbose)
        update_distribution_ini(betterbird_commit, verbose=verbose)
        Path(KNOWN_TAGS_FILE).write_text(
            "\n".join(sorted(read_known_tags() | set(new_tags))) + "\n"
        )

        flathub_repo_git.git.add(
            MANIFEST_FILE, SOURCES_FILE, DIST_FILE, BUILD_DATE_FILE, KNOWN_TAGS_FILE
        )
        flathub_repo_git.git.commit(
            "-m",
            f"Update to {target_tag}",
            "--",
            MANIFEST_FILE,
            SOURCES_FILE,
            DIST_FILE,
            BUILD_DATE_FILE,
            KNOWN_TAGS_FILE,
        )

        try:
            log_verbose(verbose, "[auto] Pushing to develop…")
            flathub_repo_git.remotes.origin.push("HEAD:refs/heads/develop")
        except git.exc.GitCommandError as exc:
            if attempt == MAX_PUSH_ATTEMPTS:
                raise
            print(f"Push to develop was rejected, retrying: {exc}", file=sys.stderr)
            continue

        print(f"Successfully updated develop to {target_tag}.")
        return


def main():
    args = parse_args()
    verbose = args.verbose

    # --auto mode: automated CI/CD workflow
    if args.auto is not None:
        major_release: Optional[str] = args.auto if args.auto else None
        if not major_release:
            print("Usage: update-version.py --auto [MAJOR_RELEASE]")
            print("")
            print("Example: update-version.py --auto 140")
            sys.exit(1)
        auto_update(major_release, verbose=verbose)
        return

    betterbird_version = args.version
    betterbird_commit = args.commit

    if not betterbird_version:
        print(
            "Usage: update-version.py [-f] [-p] [-c] [-v] BETTERBIRD_VERSION [BETTERBIRD_COMMIT]"
        )
        print("       update-version.py --auto [MAJOR_RELEASE]")
        print("")
        print("Examples:")
        print("  update-version.py 102.2.2-bb16")
        print("  update-version.py 102 4d587481bc7dbca1ffc99cce319f84425fab7852")
        print("  update-version.py --auto 140")
        sys.exit(1)

    betterbird_version = args.version
    betterbird_commit = args.commit

    # Determine source spec
    if betterbird_commit:
        source_spec = "commit"
    else:
        source_spec = "tag"

    log_verbose(
        verbose,
        f"[update-version.py] Parsed args: BETTERBIRD_VERSION={betterbird_version}, "
        f"BETTERBIRD_COMMIT={betterbird_commit or '<none>'}, "
        f"force={args.force}, private_mirror={args.private_mirror}, "
        f"self_contained={args.self_contained}, verbose={verbose}",
    )

    print()
    if source_spec == "tag":
        print(f"Updating to TAG {betterbird_version}")
    else:
        print(f"Updating to COMMIT {betterbird_commit}")
    print(
        f" using Betterbird patches for Thunderbird {betterbird_version.split('.')[0]}"
    )
    print()

    # Clone/update repo
    ensure_repo(verbose=verbose)

    # Checkout commit
    betterbird_commit = get_commit(
        betterbird_version if source_spec == "tag" else None,
        betterbird_commit,
        verbose=verbose,
    )
    log_verbose(verbose, f"  thunderbird-patches ready at {betterbird_commit}")

    # Version check from appdata.xml
    if source_spec == "tag" and not args.force:
        log_verbose(
            verbose,
            f"[step 2/7] Checking version agreement between CLI input and {APPDATA_FILE}",
        )
        appdata_version = get_appdata_version()
        if appdata_version:
            log_verbose(
                verbose,
                f"  CLI version: {betterbird_version}  |  appdata.xml version: {appdata_version}",
            )
        else:
            log_verbose(verbose, f"  Could not read version from {APPDATA_FILE}")
        if appdata_version and not betterbird_version.startswith(appdata_version):
            print(
                f"Betterbird version given on command line ({betterbird_version}) "
                f"and version according to {APPDATA_FILE} ({appdata_version}) don't agree. Stopping."
            )
            print("Hint: This check can be skipped by passing the -f flag.")
            sys.exit(1)
        log_verbose(verbose, "  Versions agree.")

    # Save build date
    log_verbose(verbose, "[step 3/7] Writing build date to .build-date")
    build_date = datetime.now().astimezone().strftime("%Y%m%d%H%M%S")
    Path(BUILD_DATE_FILE).write_text(build_date + "\n")

    # Get base URL
    log_verbose(verbose, "[step 4/7] Extracting source base URL from appdata.xml")
    base_url = get_base_url()
    source_archive = get_appdata_source_location()
    if not base_url:
        print(f"Error: Could not extract base URL from {APPDATA_FILE}")
        sys.exit(1)
    log_verbose(verbose, f"  Source archive: {source_archive}")
    log_verbose(verbose, f"  Base URL: {base_url}")

    # Update sources file
    if args.self_contained:
        self_contained_update_sources(base_url, betterbird_version, verbose=verbose)
    else:
        update_sources_file(base_url, betterbird_version, verbose=verbose)

    # Update manifest
    update_manifest(betterbird_commit, source_spec, betterbird_version, verbose=verbose)

    # Update distribution.ini
    update_distribution_ini(betterbird_commit, verbose=verbose)

    # Update known tags
    if source_spec == "tag":
        update_known_tags(betterbird_version, verbose=verbose)

    # Private mirror handling
    if args.private_mirror:
        handle_private_mirror(betterbird_version, verbose=verbose)

    # Success message
    print(f"""The files were successfully updated to Betterbird {betterbird_version}.

You can commit the result by executing the following command:
git commit --message='Update to {betterbird_version}' -- '{SOURCES_FILE}' '{MANIFEST_FILE}' '{DIST_FILE}' '{BUILD_DATE_FILE}' '{KNOWN_TAGS_FILE}'
""")


if __name__ == "__main__":
    main()
