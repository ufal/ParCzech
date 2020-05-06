#!/bin/bash

D=`dirname $0`
cd $D

usage() {
  echo -e "Usage: $0 -c CACHE_DIR -o OUTPUT_DIR" 1>&2
  exit 1
}


set -o allexport
if [ -f "config.sh" ]; then
  source config.sh
fi
set +o allexport

OUT_DIR=
CACHE_DIR=


while getopts  ':c:o:'  opt; do # -l "identificator:,file-pattern:,export-audio" -a -o
  case "$opt" in
    'c')
      CACHE_DIR=$OPTARG
      ;;
    'o')
      OUT_DIR=$OPTARG
      ;;
    *)
      usage
  esac
done


if [ -z "$CACHE_DIR" ] || [ -z "$OUT_DIR" ] ; then
  usage
fi

mkdir -p $OUT_DIR

CACHE_FILES=`find $CACHE_DIR -type f`

for FILE in $CACHE_FILES;
do
  FILE_PATH=`head -n 1 $FILE | tr -d '\n' | sed 's@^http[s]*://@@;s@/$@/index.htm@'`
  echo "$FILE $FILE_PATH"

  mkdir -p $OUT_DIR/`dirname $FILE_PATH`
  tail -n +6 $FILE > $OUT_DIR/$FILE_PATH
done

