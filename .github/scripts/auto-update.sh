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
    fi
  done
  if [[ -n $target_tag ]]
  then
    echo " --- Updating to $target_tag ---"
    git config user.name github-actions
    git config user.email github-actions@github.com
    ./update-version.sh $target_tag \
    && echo "${all_tags}" > .known-tags \
    && git commit -m "Update to $target_tag" -- .known-tags eu.betterbird.Betterbird.json thunderbird-sources.json \
    && git push \
    || exit 1
  fi
else
  echo " --- No new tags found ---"
fi
