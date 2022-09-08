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
echo "... without enabling showing missing fluent strings"
sed -i 's/04-misc-missing-fluent-strings-m-c.patch/# 04-misc-missing-fluent-strings-m-c.patch/g' thunderbird-patches/$VERSION/series-M-C
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
