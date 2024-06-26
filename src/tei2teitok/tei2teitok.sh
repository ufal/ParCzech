#!/bin/bash


PWD=`pwd`
D=`dirname $0`

local_transformer() {
  xsltproc $1 --profile "$2" > "$3"
}

usage() {
  echo -e "Usage: $0 -i FILE_IN -o FILE_OUT" 1>&2
  exit 1
}

while getopts  ':i:o:c:C:'  opt; do # -l "identificator:,file-pattern:,export-audio" -a -o
  case "$opt" in
    'i')
      FILE_IN=$OPTARG
      ;;
    'o')
      FILE_OUT=$OPTARG
      ;;
    'C')
      CORPUS_FILE=$OPTARG
      ;;
    'c')
      CONFIG_FILE=$OPTARG
      ;;
    *)
      usage
  esac
done

set -o allexport
if [ -f "$CONFIG_FILE" ]; then
  echo "loading config $CONFIG_FILE"
  source "$CONFIG_FILE"
fi
set +o allexport


if [ -z "$FILE_IN" ] || [ -z "$FILE_OUT" ] ; then
	echo "$FILE_IN $FILE_OUT"
  usage
fi

if [ ! -s "$FILE_IN" ] ; then
  echo "file does not exist or is empty: $FILE_IN $FILE_OUT"
  exit 1
fi

if [ -z $XSL_TRANSFORM ] ; then
  XSL_TRANSFORM='local_transformer'
fi

if [ -z $CORPUS_FILE ] ; then
  CORPUS_FILE=$PERSON_LIST_PATH
fi

FILE_IN=`realpath --relative-to="$D" "$FILE_IN"`

mkdir -p `dirname "$FILE_OUT"`
touch "$FILE_OUT"
FILE_OUT=`realpath --relative-to="$D" "$FILE_OUT"`

cd $D

$XSL_TRANSFORM tei2teitok.xsl "$FILE_IN" "$FILE_OUT" corpus-path=$CORPUS_FILE
