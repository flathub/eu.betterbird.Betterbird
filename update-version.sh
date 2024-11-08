#!/bin/bash
set -eo pipefail

script_args=()
force=false
private_mirror=false
while [ $OPTIND -le "$#" ]
do
    if getopts fp option
    then
        case $option
        in
          f) force=true;;
          p) private_mirror=true;;
        esac
    else
        script_args+=("${!OPTIND}")
        ((OPTIND++))
    fi
done

if ((${#script_args[@]} < 1)); then
  echo "Usage: $0 [-f] [-p] BETTERBIRD_VERSION [BETTERBIRD_COMMIT]"
  echo ""
  echo "Example: $0 102.2.2-bb16"
  echo "         $0 102 4d587481bc7dbca1ffc99cce319f84425fab7852"
  echo ""
  echo "Options:"
  echo "  -f : Skip the check that the version given as script input and the version specified in the appdata.xml agree."
  echo "  -p : Replace upstream mirror of source tar.xz by private mirror."
  exit 1
fi

BETTERBIRD_VERSION="${script_args[0]}" # Betterbird version. Can either be a tag or a major version number. If it's a tag, the commit is identified automatically. In case only the major version number is given, a commit must be specified by passing its hash as 2nd argument. 
BETTERBIRD_COMMIT="${script_args[1]}"
BETTERBIRD_REPO="https://github.com/Betterbird/thunderbird-patches"
PACKAGE=thunderbird
PLATFORM=linux-x86_64
SOURCES_FILE="$PACKAGE-sources.json"
APPDATA_FILE="thunderbird-patches/metadata/eu.betterbird.Betterbird.128.appdata.xml"
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

# clone Betterbird repo
if [ -d thunderbird-patches/.git ]
then
    cd thunderbird-patches
    git reset --hard HEAD
    git fetch
else
    git clone -n $BETTERBIRD_REPO thunderbird-patches
    cd thunderbird-patches
fi

if [[ "$source_spec" == "tag" ]]
then
  betterbird_commit=$(git rev-list -1 $BETTERBIRD_VERSION)
else
  betterbird_commit=$(git rev-list -1 $BETTERBIRD_COMMIT)
fi
git checkout $betterbird_commit
cd ..

if [[ "$source_spec" == "tag" ]] && ! $force 
then
  # check if version from appdata.xml agrees with tag
  betterbird_version_appdata=$(cat $APPDATA_FILE | grep '<release version=' | sed -r 's@^\s+<release version="(([^"])+)(" date=")([^"]+)(">)$@\1@')
  if [[ "$betterbird_version_appdata" != "$BETTERBIRD_VERSION" ]]
  then
    echo "Betterbird version given on command line ($BETTERBIRD_VERSION) and version according to $APPDATA_FILE ($betterbird_version_appdata) don't agree. Stopping."
    echo "Hint: This check can be skipped by passing the -f flag."
    exit 1
  fi
fi

# save current date
TZ='Europe/Berlin' date '+%Y%m%d%H%M%S' > $BUILD_DATE_FILE

# get base URL for sources from appdata.xml
source_archive=$(cat $APPDATA_FILE | sed -rz 's@.+<artifact type="source">\s*<location>([^<]+)<\/location>.+@\1@')
base_url="${source_archive%/source/*}"

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
        "url": "'"$base_url"'/'"$path"'",
        "sha256": "'"$checksum"'"
    }'

  # add locale to sources file
  else
    # strip directories and .xpi extension
    locale="${path##*/}"
    locale="${locale%.*}"

    # include langpack only if there is a Betterbird patch for it
    if [[ -f "thunderbird-patches/${BETTERBIRD_VERSION%%.*}/scripts/$locale.cmd" ]]
    then
      cat >>"$SOURCES_FILE" <<EOT
      {
          "type": "file",
          "url": "$base_url/$path",
          "sha256": "$checksum",
          "dest": "langpacks/",
          "dest-filename": "langpack-$locale@$PACKAGE.mozilla.org.xpi"
      },
EOT
    fi
  fi
done < <(curl -Ss "$base_url/SHA256SUMS" | grep "^\S\+  \(source\|$PLATFORM/xpi\)/")

# add source archive entry to sources file
echo -e "$source_archive\n]" >>"$SOURCES_FILE"

# update betterbird release tag and commit in manifest
tmpfile="tmp.json"
yq -Y '(.modules[] | objects | select(.name=="betterbird") | .sources[] | objects | select(.dest=="thunderbird-patches") | .commit) = "'$betterbird_commit'"' $MANIFEST_FILE > $tmpfile
if [[ "$source_spec" == "tag" ]]
then
  yq -Y '(.modules[] | objects | select(.name=="betterbird") | .sources[] | objects | select(.dest=="thunderbird-patches") | .tag) = "'$BETTERBIRD_VERSION'"' $tmpfile > $MANIFEST_FILE
elif [[ "$source_spec" == "commit" ]]
then
  yq -Y 'del((.modules[] | objects | select(.name=="betterbird") | .sources[] | objects | select(.dest=="thunderbird-patches") | .tag))' $tmpfile > $MANIFEST_FILE
fi
rm -f $tmpfile

# update version in distribution.ini
sed -i 's/version=.*$/version='"$(git rev-parse --short $betterbird_commit)"'/' "$DIST_FILE"

# add external patches to sources file
# patch series for main repo
while read -r line; do
  url=$(echo $line | sed -r 's/(.*) # (http.*\/rev\/[0-9a-f]+).*/\2/' | sed -e 's/\/rev\//\/raw-rev\//')
  name=$(echo $line | sed -r 's/(.*) # (.*)/\1/')
  wget $url --max-redirect=20 -O $name
  sha256=$(sha256sum "$name" | cut -f1 -d' ')
  jq --arg url $url --arg name $name --arg sha256 $sha256 \
    '. += [{"type":"file","url":$url,"sha256":$sha256,"dest":"patches/","dest-filename":$name}]' \
    $SOURCES_FILE > $tmpfile
  mv $tmpfile $SOURCES_FILE
  rm -f $name
done < <(grep -E "^[^#].* # " thunderbird-patches/$(echo $BETTERBIRD_VERSION | cut -f1 -d'.')/series-moz)
# patch series for comm repo
while read -r line; do
  url=$(echo $line | sed -r 's/(.*) # (http.*\/rev\/[0-9a-f]+).*/\2/' | sed -e 's/\/rev\//\/raw-rev\//')
  name=$(echo $line | sed -r 's/(.*) # (.*)/\1/')
  wget $url --max-redirect=20 -O $name
  sha256=$(sha256sum "$name" | cut -f1 -d' ')
  jq --arg url $url --arg name $name --arg sha256 $sha256 \
    '. += [{"type":"file","url":$url,"sha256":$sha256,"dest":"patches/","dest-filename":$name}]' \
    $SOURCES_FILE > $tmpfile
  mv $tmpfile $SOURCES_FILE
  rm -f $name
done < <(grep -E "^[^#].* # " thunderbird-patches/$(echo $BETTERBIRD_VERSION | cut -f1 -d'.')/series)

# add tag to .known-tags if it has not been added yet 
if [[ "$source_spec" == "tag" ]] && ! grep -Fxq "$BETTERBIRD_VERSION" "$KNOWN_TAGS_FILE"
then
  echo "$BETTERBIRD_VERSION" >> "$KNOWN_TAGS_FILE"
  sort -o "$KNOWN_TAGS_FILE" "$KNOWN_TAGS_FILE"
fi

# download source tar to private mirror and replace download URLs
if $private_mirror
then
  ssh srv5root curl -C - --retry 5 --retry-all-errors -O --output-dir /srv/containers/dl $(cat thunderbird-sources.json | grep -Eo 'https://.*.source.tar.xz')
  sed -E 's#https:\/\/archive\.mozilla\.org\/.*\/([^\/]+)\.source\.tar\.xz#https://dl.mfs.name/\1.source.tar.xz#' -i thunderbird-sources.json
fi

cat <<EOT
The files were successfully updated to Betterbird $BETTERBIRD_VERSION.

You can commit the result by executing the following command:
git commit --message='Update to $BETTERBIRD_VERSION' -- '$SOURCES_FILE' '$MANIFEST_FILE' '$DIST_FILE' '$BUILD_DATE_FILE' '$KNOWN_TAGS_FILE'
EOT
