#!/bin/bash
set -eo pipefail

VERSION="$1"

echo
echo "======================================================="
echo "Copying patches"
find thunderbird-patches/$VERSION -type f -name *.patch -exec cp '{}' patches ';'

echo
echo "======================================================="
echo "Applying patch series for main repository"
echo "... without patches for Windows installer"
sed -i 's/08-branding-m-c.patch/# 08-branding-m-c.patch/g' thunderbird-patches/$VERSION/series-M-C
sed -i 's/08a-branding-m-c.patch/# 08a-branding-m-c.patch/g' thunderbird-patches/$VERSION/series-M-C

cat thunderbird-patches/$VERSION/series-M-C | while read line || [[ -n $line ]]
    do 
        patch=$(echo $line | cut -f1 -d'#' | sed 's/ *$//')
        if [[ -f patches/$patch ]]
        then
            echo Applying patch $patch ... 
            git apply --apply patches/$patch
        fi
    done

echo
echo "======================================================="
echo "Applying patch series for comm repository"
cd comm
cat ../thunderbird-patches/$VERSION/series | while read line || [[ -n $line ]]
    do
        patch=$(echo $line | cut -f1 -d'#' | sed 's/ *$//')
        if [[ -f ../patches/$patch ]]
        then
            echo Applying patch $patch ... 
            git apply --apply ../patches/$patch
        fi
    done
cd ..
