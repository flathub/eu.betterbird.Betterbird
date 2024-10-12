#!/bin/bash
set -eo pipefail

if (($# < 1)); then
  echo "Usage: $0 CBINDGEN_VERSION"
  echo ""
  echo "Example: $0 v0.23.0"
  exit 1
fi

CBINDGEN_VERSION="$1" # cbindgen version tag
CBINDGEN_REPO="https://github.com/eqrion/cbindgen"
PACKAGE=cbindgen
SOURCES_FILE="$PACKAGE-sources.json"
MANIFEST_FILE="eu.betterbird.Betterbird.yml"

# clone cbindgen repo
[ -d cbindgen ] && rm -rf cbindgen
git clone -n $CBINDGEN_REPO cbindgen
cd cbindgen
cbindgen_commit=$(git rev-list -1 $CBINDGEN_VERSION)
git checkout $cbindgen_commit
cd ..

# update cbindgen release tag and commit in manifest
tmpfile="tmp.json"
yq '(.modules[] | objects | select(.name=="cbindgen") | .sources[] | objects | select(.type=="git") | .commit) = "'$cbindgen_commit'"' $MANIFEST_FILE > $tmpfile
yq '(.modules[] | objects | select(.name=="cbindgen") | .sources[] | objects | select(.type=="git") | .tag) = "'$CBINDGEN_VERSION'"' $tmpfile > $MANIFEST_FILE
rm -f $tmpfile

# update cbindgen-sources.json
flatpak-builder-tools/cargo/flatpak-cargo-generator.py cbindgen/Cargo.lock -o cbindgen-sources.json

rm -rf cbindgen

cat << EOT
The files were successfully updated to cbindgen $CBINDGEN_VERSION.

You can commit the result by executing the following command:
git commit --message='Update to cbindgen $CBINDGEN_VERSION' -- '$SOURCES_FILE' '$MANIFEST_FILE'
EOT
