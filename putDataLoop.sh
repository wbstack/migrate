#!/bin/bash

## putDataLoop.sh
# Iterates over the files in a directory (argument #1)
# which is expected to hold directories with wiki data to migrate.
#
# Each run has it's own logfile and if some command fails, the loop will stop.
#

set -eux

WIKIS_PATH="$1"
TARGET="$2"

if [[ ! -d "$WIKIS_PATH" ]]; then
    echo "You must supply the path to a directory as the first argument"
    exit 1
fi

case $TARGET in
  "wikibase.dev")
    ;;
  "wikibase.cloud")
    ;;
  *)
    echo "You must supply wikibase.dev or wikibase.cloud as the second argument"
    exit 2
    ;;
esac

for wiki_path in $WIKIS_PATH/*; do
    # skip files that are not a directory
    if [[ ! -d $wiki_path ]]; then
        continue
    fi

    WIKI=$(basename $wiki_path)
    LOGFILE=./$(date +%F)-A-$WIKI-to-$TARGET.log
    
    mv $wiki_path .

    script -c "./putData.sh $WIKI $TARGET" $LOGFILE

    rm -R ./$WIKI
done

echo "$0 completed!"
