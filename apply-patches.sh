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

cat thunderbird-patches/$VERSION/series-M-C | while read line || [[ -n $line ]]
    do 
        patch=$(echo $line | cut -f1 -d'#' | sed 's/ *$//')
        if [[ -n "${patch// }" ]]
        then
            if [[ -f patches/$patch ]]
            then
                echo Applying patch $patch ... 
                git apply --apply patches/$patch
            else
                echo Patch $patch not found. Exiting.
                exit 1
            fi
        fi
    done

echo
echo "======================================================="
echo "Applying patch series for comm repository"
echo "... without disabling multi-language support"
sed -i 's/05-misc-no-multi-lingual.patch/# 05-misc-no-multi-lingual.patch/g' thunderbird-patches/$VERSION/series
cd comm
cat ../thunderbird-patches/$VERSION/series | while read line || [[ -n $line ]]
    do
        patch=$(echo $line | cut -f1 -d'#' | sed 's/ *$//')
        if [[ -n "${patch// }" ]]
        then
            if [[ -f ../patches/$patch ]]
            then
                echo Applying patch $patch ... 
                git apply --apply ../patches/$patch
            else
                echo Patch $patch not found. Exiting.
                exit 1
            fi
        fi
    done
cd ..
