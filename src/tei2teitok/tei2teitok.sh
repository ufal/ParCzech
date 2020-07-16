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

while getopts  ':i:o:c:'  opt; do # -l "identificator:,file-pattern:,export-audio" -a -o
  case "$opt" in
    'i')
      FILE_IN=$OPTARG
      ;;
    'o')
      FILE_OUT=$OPTARG
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
  source "$CONFIG_FILE"
fi
set +o allexport


if [ -z "$FILE_IN" ] || [ -z "$FILE_OUT" ] ; then
	echo "$FILE_IN $FILE_OUT"
  usage
fi

if [ -z $XSL_TRANSFORM ] ; then
  XSL_TRANSFORM='local_transformer'
fi

FILE_IN=`realpath --relative-to="$D" "$FILE_IN"`

mkdir -p `dirname "$FILE_OUT"`
touch "$FILE_OUT"
FILE_OUT=`realpath --relative-to="$D" "$FILE_OUT"`

cd $D

$XSL_TRANSFORM tei2teitok.xsl "$FILE_IN" "$FILE_OUT"
