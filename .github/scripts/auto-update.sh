#!/bin/bash

auto_update_major_release=102
cd thunderbird-patches
all_tags=$(git tag | sort)
new_tags=$(comm -23 <(echo "${all_tags}") <(sort ../eu.betterbird.Betterbird/.known-tags))
cd ../eu.betterbird.Betterbird
if [[ -n $new_tags ]]
then
  echo " --- New tags: $new_tags ---"
  for tag in ${new_tags}
  do
    if [[ $(echo $tag | cut -f1 -d.) == $auto_update_major_release ]]
    then
      target_tag=$tag
      update_branch=$(git ls-remote --heads origin update-$target_tag)
    fi
  done
  if [[ -n $target_tag ]]
  then
    if [[ -z $update_branch ]]
    then
      echo " --- Updating to $target_tag ---"
      ./update-version.sh $target_tag \
      && echo "${all_tags}" > .known-tags \
      || exit 1
      echo "version_updated=true" >> $GITHUB_ENV
      echo "new_version=$target_tag" >> $GITHUB_ENV
    else
      echo " --- Skipping update, because branch update-$target_tag already exists ---"
      echo "version_updated=false" >> $GITHUB_ENV
    fi
  fi
else
  echo " --- No new tags found ---"
  echo "version_updated=false" >> $GITHUB_ENV
fi
