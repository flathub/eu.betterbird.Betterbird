#!/bin/bash
set -eo pipefail

VERSION="$1"

echo
echo "======================================================="
echo "Copying patches"
rm -rf patches; mkdir patches
find thunderbird-patches/$VERSION -type f -name *.patch -exec cp '{}' patches ';'

echo
echo "======================================================="
echo "Downloading upstream patches for main repository"
echo '#!/bin/bash' > external.sh
grep " # " thunderbird-patches/$VERSION/series-M-C >> external.sh
sed -i -e 's/\/rev\//\/raw-rev\//' external.sh
sed -i -e 's/\(.*\) # \(.*\)/wget -nc \2 -O patches\/\1/' external.sh
chmod 700 external.sh
./external.sh
rm -f external.sh

echo
echo "======================================================="
echo "Applying patch series for main repository"
echo "... without patches for Windows installer"
sed -i 's/08-branding-m-c.patch/# 08-branding-m-c.patch/g' thunderbird-patches/$VERSION/series-M-C
sed -i 's/08a-branding-m-c.patch/# 08a-branding-m-c.patch/g' thunderbird-patches/$VERSION/series-M-C

cat thunderbird-patches/$VERSION/series-M-C | while read line || [[ -n $line ]]
    do 
        if [[ -f patches/$line ]]
        then
            echo Applying patch $line ... 
            git apply --stat --apply patches/$line
        fi
    done

echo
echo "======================================================="
echo "Downloading upstream patches for comm repository"
echo '#!/bin/bash' > external.sh
grep " # " thunderbird-patches/$VERSION/series >> external.sh
sed -i -e 's/\/rev\//\/raw-rev\//' external.sh
sed -i -e 's/\(.*\) # \(.*\)/wget -nc \2 -O patches\/\1/' external.sh
chmod 700 external.sh
./external.sh
rm -f external.sh

echo
echo "======================================================="
echo "Applying patch series for comm repository"
cd comm
cat ../thunderbird-patches/$VERSION/series | while read line || [[ -n $line ]]
    do
        if [[ -f ../patches/$line ]]
        then
            echo Applying patch $line ... 
            git apply --stat --apply ../patches/$line
        fi
    done
cd ..
