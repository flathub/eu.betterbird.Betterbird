#!/bin/bash
set -eo pipefail
set -x

VERSION="$1"

echo
echo "======================================================="
echo "Copying patches"
find thunderbird-patches/$VERSION -type f -name *.patch -exec cp '{}' patches ';'

echo
echo "======================================================="
echo "Applying patch series for main repository"
while read -r line; do
  patch=$(echo $line | cut -f1 -d'#' | sed 's/ *$//')
  if [[ -n "${patch// }" ]]
  then
      if [[ -f patches/$patch ]]
      then
          echo Applying patch $patch ... 
          git apply --apply --allow-empty patches/$patch
      else
          echo Patch $patch not found. Exiting.
          exit 1
      fi
  fi
done < <(grep -E "^[^#].*" thunderbird-patches/$VERSION/series-M-C)

echo
echo "======================================================="
echo "Applying patch series for comm repository"
cd comm
while read -r line; do
  patch=$(echo $line | cut -f1 -d'#' | sed 's/ *$//')
  if [[ -n "${patch// }" ]]
  then
      if [[ -f ../patches/$patch ]]
      then
          echo Applying patch $patch ... 
          git apply --apply --allow-empty ../patches/$patch
      else
          echo Patch $patch not found. Exiting.
          exit 1
      fi
  fi
done < <(grep -E "^[^#].*" thunderbird-patches/$VERSION/series)
cd ..

echo
echo "======================================================="
echo "Patching language packs"
if [ -d langpacks ]
then
  cd langpacks
  for langpack in *.xpi
  do 
      lang=$(echo "$langpack" | sed -r 's#\langpack-([^@]+)@thunderbird.mozilla.org.xpi#\1#')
      echo " -- $lang --"
      mkdir $lang
      cd $lang

      echo "   * extracting original lang pack"
      unzip -q ../$langpack
      rm -f ../$langpack

      echo "   * removing original branding"
      rm -f chrome/$lang/locale/$lang/branding/*
      rm -f localization/$lang/branding/*

      echo "   * modifying manifest.json"
      sed -i -e 's/@thunderbird.mozilla.org/@betterbird.eu/' manifest.json
      sed -i -e 's/Language pack for Thunderbird/Language pack for Betterbird/' manifest.json

      echo "   * copying Betterbird branding from en-US"
      branding_source="../../comm/mail/branding/betterbird/locales/en-US"
      cp "$branding_source/brand.ftl" localization/$lang/branding/
      cp "$branding_source/brand.dtd" "$branding_source/brand.properties" chrome/$lang/locale/$lang/branding/ 

      bb_string_patcher="../../thunderbird-patches/$VERSION/scripts/$lang.cmd"
      if [[ -f "$bb_string_patcher" ]]
      then
          echo "   * adding extra strings"
          sed -ri 's/^(::|REM)/#/; s/%lecho%/lessecho/; s/\r$//; s/\$/\\\$/g' "$bb_string_patcher"
          perl -pi -e 's#\\(?=[^ ]+$)#/#g' "$bb_string_patcher"
          . "$bb_string_patcher"
      fi

      echo "   * packing modified language pack"
      zip -qr "../langpack-$lang@betterbird.eu.xpi" manifest.json chrome localization

      cd ..
      rm -rf $lang
  done
fi
