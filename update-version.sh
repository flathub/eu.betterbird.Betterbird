#!/bin/bash
set -eo pipefail

if (($# < 2)); then
  echo "Usage: $0 THUNDERBIRD_VERSION BETTERBIRD_PATCHES_VERSION BETTERBIRD_COMMIT BETTERBIRD_RELEASE_DATE"
  echo ""
  echo "Example: $0 102.2.0 14 fb63d05198813bc2ed4336759bf6e17a1076e97d 2022-08-27"
  exit 1
fi

THUNDERBIRD_VERSION="$1"
BETTERBIRD_PATCHES_VERSION="$2"
BETTERBIRD_COMMIT="$3"
BETTERBIRD_RELEASE_DATE="$4"
BETTERBIRD_VERSION="$THUNDERBIRD_VERSION-bb$BETTERBIRD_PATCHES_VERSION"
PACKAGE=thunderbird
PLATFORM=linux-x86_64
BASE_URL="https://archive.mozilla.org/pub/$PACKAGE/releases/$THUNDERBIRD_VERSION"
SOURCES_FILE="$PACKAGE-sources.json"
#APPDATA_FILE="eu.betterbird.Betterbird.appdata.xml"
MANIFEST_FILE="eu.betterbird.Betterbird.json"

# check provided release date
if ! [[ "$BETTERBIRD_RELEASE_DATE" =~ ^20[0-9]{2}-(0[0-9]|1[0-2])-([0-2][0-9]|3[01])$ ]]; then
  echo >&2 "Invalid release date '$BETTERBIRD_RELEASE_DATE'. Please provide the date in the format YYYY-MM-DD, e.g. 2021-01-28."
  exit 1
fi

# write new sources file
echo '[' >"$SOURCES_FILE"

# read files from SHA256SUMS file
while read -r line; do
  checksum="${line%%  *}"
  path="${line#*  }"

  # store source archive entry for later, because it should be the last element
  # in the json array
  if [[ $path =~ ^source/ ]]; then
    source_archive='    {
        "type": "archive",
        "url": "'"$BASE_URL"'/'"$path"'",
        "sha256": "'"$checksum"'"
    }'

  # add locale to sources file
  else
    # strip directories and .xpi extension
    locale="${path##*/}"
    locale="${locale%.*}"

    cat >>"$SOURCES_FILE" <<EOT
    {
        "type": "file",
        "url": "$BASE_URL/$path",
        "sha256": "$checksum",
        "dest": "langpacks/",
        "dest-filename": "langpack-$locale@$PACKAGE.mozilla.org.xpi"
    },
EOT
  fi
done < <(curl -Ss "$BASE_URL/SHA256SUMS" | grep "^\S\+  \(source\|$PLATFORM/xpi\)/")

# add source archive entry to sources file
echo -e "$source_archive\n]" >>"$SOURCES_FILE"

# update releases in appdata file
#sed -ri 's@^(\s+<release version=")[^"]+(" date=")[^"]+(" />)$@'"\1$BETTERBIRD_VERSION\2$BETTERBIRD_RELEASE_DATE\3@" "$APPDATA_FILE"

# update betterbird release tag and commit in manifest
tmpfile="tmp.json"
jq '(.modules[] | objects | select(.name=="betterbird") | .sources[] | objects | select(.dest=="thunderbird-patches") | .commit) = "'$BETTERBIRD_COMMIT'"' $MANIFEST_FILE > $tmpfile
jq '(.modules[] | objects | select(.name=="betterbird") | .sources[] | objects | select(.dest=="thunderbird-patches") | .tag) = "'$BETTERBIRD_VERSION'"' $tmpfile > $MANIFEST_FILE
rm -f $tmpfile

cat <<EOT
The files were successfully updated to Betterbird $BETTERBIRD_VERSION.

You can commit the result by executing the following command:
git commit --message='Update to $BETTERBIRD_VERSION' -- '$SOURCES_FILE' '$APPDATA_FILE' '$MANIFEST_FILE'
EOT
