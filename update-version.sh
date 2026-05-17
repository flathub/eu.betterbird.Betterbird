#!/bin/bash
set -eo pipefail

script_args=()
force=false
private_mirror=false
compute=false
verbose=false
while [ $OPTIND -le "$#" ]
do
    if getopts fpcv option
    then
        case $option
        in
          f) force=true;;
          p) private_mirror=true;;
          c) compute=true;;
          v) verbose=true;;
        esac
    else
        script_args+=("${!OPTIND}")
        ((OPTIND++))
    fi
done

if ((${#script_args[@]} < 1)); then
  echo "Usage: $0 [-f] [-p] [-c] [-v] BETTERBIRD_VERSION [BETTERBIRD_COMMIT]"
  echo ""
  echo "Example: $0 102.2.2-bb16"
  echo "         $0 102 4d587481bc7dbca1ffc99cce319f84425fab7852"
  echo ""
  echo "Options:"
  echo "  -f : Skip the check that the version given as script input and the version specified in the appdata.xml agree."
  echo "  -p : Replace upstream mirror of source tar.xz by private mirror."
  echo "  -c : Compute checksums instead of reading from SHA256SUMS."
  echo "  -v : Verbose: print progress messages for each step."
  exit 1
fi

$verbose && echo "[update-version.sh] Parsed args: BETTERBIRD_VERSION=${script_args[0]}, BETTERBIRD_COMMIT=${script_args[1]:-<none>}, force=$force, private_mirror=$private_mirror, compute=$compute, verbose=$verbose"

BETTERBIRD_VERSION="${script_args[0]}" # Betterbird version. Can either be a tag or a major version number. If it's a tag, the commit is identified automatically. In case only the major version number is given, a commit must be specified by passing its hash as 2nd argument.
BETTERBIRD_COMMIT="${script_args[1]}"
BETTERBIRD_REPO="https://github.com/Betterbird/thunderbird-patches"
PACKAGE=thunderbird
PLATFORM=linux-x86_64
SOURCES_FILE="$PACKAGE-sources.json"
APPDATA_FILE="thunderbird-patches/metadata/eu.betterbird.Betterbird.140.appdata.xml"
MANIFEST_FILE="eu.betterbird.Betterbird.yml"
DIST_FILE="distribution.ini"
BUILD_DATE_FILE=".build-date"
KNOWN_TAGS_FILE=".known-tags"

# determine if the source revision was specified as a tag or as a commit hash
[[ "x$BETTERBIRD_COMMIT" != "x" ]] && source_spec=commit || source_spec=tag
echo ""
[[ "$source_spec" == "tag" ]] && echo -n "Updating to TAG $BETTERBIRD_VERSION"
[[ "$source_spec" == "commit" ]] && echo -n "Updating to COMMIT $BETTERBIRD_COMMIT"
echo " using Betterbird patches for Thunderbird ${BETTERBIRD_VERSION%%.*}"
echo ""

$verbose && echo "[step 1/7] Preparing thunderbird-patches repo at $PWD/thunderbird-patches"

# clone Betterbird repo
if [ -d thunderbird-patches ]
then
    $verbose && echo "  Repo already exists. Resetting to HEAD and fetching updates..."
    cd thunderbird-patches
    git reset --hard HEAD
    git fetch
else
    $verbose && echo "  Cloning $BETTERBIRD_REPO ..."
    git clone -n $BETTERBIRD_REPO thunderbird-patches
    cd thunderbird-patches
fi

if [[ "$source_spec" == "tag" ]]
then
  $verbose && echo "  Resolving tag '$BETTERBIRD_VERSION' to commit..."
  betterbird_commit=$(git rev-list -1 $BETTERBIRD_VERSION)
else
  $verbose && echo "  Resolving commit '$BETTERBIRD_COMMIT'..."
  betterbird_commit=$(git rev-list -1 $BETTERBIRD_COMMIT)
fi
$verbose && echo "  Checking out commit $betterbird_commit"
git checkout $betterbird_commit
cd ..
$verbose && echo "  thunderbird-patches ready at $betterbird_commit"

if [[ "$source_spec" == "tag" ]] && ! $force
then
  $verbose && echo "[step 2/7] Checking version agreement between CLI input and $APPDATA_FILE"
  # check if version from appdata.xml agrees with tag
  betterbird_version_appdata=$(cat $APPDATA_FILE | grep '<release version=' | sed -r 's@^\s+<release version="(([^"])+)(" date=")([^"]+)(">)$@\1@')
  $verbose && echo "  CLI version: $BETTERBIRD_VERSION  |  appdata.xml version: $betterbird_version_appdata"
  if [[ $BETTERBIRD_VERSION != $betterbird_version_appdata* ]]
  then
    echo "Betterbird version given on command line ($BETTERBIRD_VERSION) and version according to $APPDATA_FILE ($betterbird_version_appdata) don't agree. Stopping."
    echo "Hint: This check can be skipped by passing the -f flag."
    exit 1
  fi
  $verbose && echo "  Versions agree."
fi

# save current date
$verbose && echo "[step 3/7] Writing build date to $BUILD_DATE_FILE"
TZ='Europe/Berlin' date '+%Y%m%d%H%M%S' > $BUILD_DATE_FILE

# get base URL for sources from appdata.xml
$verbose && echo "[step 4/7] Extracting source base URL from $APPDATA_FILE"
source_archive=$(cat $APPDATA_FILE | sed -rz 's@.+<artifact type="source">\s*<location>([^<]+)<\/location>.+@\1@')
base_url="${source_archive%/source/*}"
$verbose && echo "  Source archive: $source_archive"
$verbose && echo "  Base URL: $base_url"

# write new sources file
echo '[' >"$SOURCES_FILE"

source_archive_json=""

if $compute; then
  $verbose && echo "[step 5/7] Computing checksums (compute mode)"
  # download source archive and compute checksum
  temp_source=$(mktemp)
  $verbose && echo "  Downloading source archive from $source_archive..."
  curl -fSs "$source_archive" -o "$temp_source"
  source_checksum=$(sha256sum "$temp_source" | awk '{print $1}')
  $verbose && echo "  Source archive SHA256: $source_checksum"
  rm "$temp_source"
  source_archive_json='    {
        "type": "archive",
        "url": "'"$source_archive"'",
        "sha256": "'"$source_checksum"'"
    }'
  $verbose && echo "  Source archive: $source_archive (SHA256: $source_checksum)"

  # download and add XPI files for locales that have patcher scripts
  $verbose && echo "  Checking language packs with patches..."
  locale_count=0
  for script in thunderbird-patches/${BETTERBIRD_VERSION%%.*}/scripts/*.sh; do
    locale="${script##*/}"
    locale="${locale%.sh}"
    xpi_url="$base_url/$PLATFORM/xpi/$locale.xpi"
    temp_xpi=$(mktemp)
    if curl -fSs "$xpi_url" -o "$temp_xpi" 2>/dev/null; then
      xpi_checksum=$(sha256sum "$temp_xpi" | awk '{print $1}')
      rm "$temp_xpi"
      $verbose && echo "  [$((++locale_count))] $locale (SHA256: $xpi_checksum)"
      cat >>"$SOURCES_FILE" <<EOT
      {
          "type": "file",
          "url": "$xpi_url",
          "sha256": "$xpi_checksum",
          "dest": "langpacks/",
          "dest-filename": "langpack-$locale@$PACKAGE.mozilla.org.xpi"
      },
EOT
    else
      $verbose && echo "  [$((++locale_count))] $locale — not available, skipping"
    fi
  done
else
  $verbose && echo "[step 5/7] Reading checksums from SHA256SUMS"
  # read files from SHA256SUMS file
  while read -r checksum path; do
    # store source archive entry for later, because it should be the last element
    # in the json array
    if [[ $path =~ ^(source|$PLATFORM/xpi)/ ]]; then
      if [[ $path =~ ^source/ ]]; then
        source_archive_json='    {
          "type": "archive",
          "url": "'"$base_url"'/'"$path"'",
          "sha256": "'"$checksum"'"
        }'
        $verbose && echo "  Source archive: $path (SHA256: $checksum)"
else
      # add locale to sources file only if patcher script exists
      locale="${path##*/}"
      locale="${locale%.*}"
      if [[ -f "thunderbird-patches/${BETTERBIRD_VERSION%%.*}/scripts/$locale.sh" ]]; then
        $verbose && echo "  Adding langpack: $locale (SHA256: $checksum)"
        cat >>"$SOURCES_FILE" <<EOT
      {
          "type": "file",
          "url": "$base_url/$path",
          "sha256": "$checksum",
          "dest": "langpacks/",
          "dest-filename": "langpack-$locale@$PACKAGE.mozilla.org.xpi"
      },
EOT
      else
        $verbose && echo "  Skipping $locale — no matching patch script"
      fi
    fi
  done < <(curl -fSs "$base_url/SHA256SUMS")
fi

# add source archive entry to sources file
if [[ -z "$source_archive_json" ]]; then
  echo "ERROR: source archive entry was not built by the SHA256SUMS loop (\$source_archive_json is empty). This is a script bug — the SHA256SUMS source path was not matched." >&2
  echo "You can try rerunning with -c to compute checksums, or file an issue." >&2
  exit 1
fi
echo -e "$source_archive_json\n]" >>"$SOURCES_FILE"
$verbose && echo "  Done. Sources written to $SOURCES_FILE"

# update betterbird release tag and commit in manifest
$verbose && echo "[step 6/7] Updating $MANIFEST_FILE (commit: $betterbird_commit, source_spec: $source_spec)"
yq -i '(.modules[] | select(.name=="betterbird") | .sources[] | select(.dest=="thunderbird-patches") | .commit) = "'$betterbird_commit'"' $MANIFEST_FILE
if [[ "$source_spec" == "tag" ]]
then
  $verbose && echo "  Setting tag in manifest to $BETTERBIRD_VERSION"
  yq -i '(.modules[] | select(.name=="betterbird") | .sources[] | select(.dest=="thunderbird-patches") | .tag) = "'$BETTERBIRD_VERSION'"' $MANIFEST_FILE
elif [[ "$source_spec" == "commit" ]]
then
  $verbose && echo "  Removing tag from manifest (commit-based update)"
  yq -i 'del((.modules[] | select(.name=="betterbird") | .sources[] | select(.dest=="thunderbird-patches") | .tag))' $MANIFEST_FILE
fi

# update version in distribution.ini
dist_version=$(git rev-parse --short $betterbird_commit)
$verbose && echo "[step 7/7] Updating version in $DIST_FILE to $dist_version"
sed -i 's/version=.*$/version='"$dist_version"'/' "$DIST_FILE"

# add tag to .known-tags if it has not been added yet
if [[ "$source_spec" == "tag" ]] && ! grep -Fxq "$BETTERBIRD_VERSION" "$KNOWN_TAGS_FILE"
then
  $verbose && echo "  Adding $BETTERBIRD_VERSION to $KNOWN_TAGS_FILE"
  echo "$BETTERBIRD_VERSION" >> "$KNOWN_TAGS_FILE"
  sort -o "$KNOWN_TAGS_FILE" "$KNOWN_TAGS_FILE"
fi

# download source tar to private mirror and replace download URLs
if $private_mirror
then
  $verbose && echo "  Uploading source tarballs to private mirror..."
  mapfile -t source_urls < <(jq -r '[.[] | select(.type == "archive") | .url] | .[]' "$SOURCES_FILE")
  if ((${#source_urls[@]} == 0)); then
    echo "ERROR: no source archive URLs found in $SOURCES_FILE. Aborting." >&2
    exit 1
  fi
  $verbose && printf "    %s\n" "${source_urls[@]}"
  ssh srv5dl curl -C - --retry 5 --retry-all-errors -O --output-dir /srv/containers/dl "${source_urls[@]}"
  $verbose && echo "  Rewriting URLs in $SOURCES_FILE to point to private mirror"
  sed -E 's#https:\/\/archive\.mozilla\.org\/.*\/([^\/]+)\.source\.tar\.xz#https://dl.mfs.name/\1.source.tar.xz#' -i "$SOURCES_FILE"
fi

cat <<EOT
The files were successfully updated to Betterbird $BETTERBIRD_VERSION.

You can commit the result by executing the following command:
git commit --message='Update to $BETTERBIRD_VERSION' -- '$SOURCES_FILE' '$MANIFEST_FILE' '$DIST_FILE' '$BUILD_DATE_FILE' '$KNOWN_TAGS_FILE'
EOT
