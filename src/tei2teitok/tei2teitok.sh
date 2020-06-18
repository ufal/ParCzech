#!/bin/bash


PWD=`pwd`
D=`dirname $0`


usage() {
  echo -e "Usage: $0 -i FILE_IN -o FILE_OUT" 1>&2
  exit 1
}

while getopts  ':i:o:'  opt; do # -l "identificator:,file-pattern:,export-audio" -a -o
  case "$opt" in
    'i')
      FILE_IN=$OPTARG
      ;;
    'o')
      FILE_OUT=$OPTARG
      ;;
    *)
      usage
  esac
done


if [ -z "$FILE_IN" ] || [ -z "$FILE_OUT" ] ; then
	echo "$FILE_IN $FILE_OUT"
  usage
fi


FILE_IN=`realpath --relative-to="$D" "$FILE_IN"`

mkdir -p `dirname "$FILE_OUT"`
touch "$FILE_OUT"
FILE_OUT=`realpath --relative-to="$D" "$FILE_OUT"`

cd $D
xsltproc tei2teitok.xsl "$FILE_IN" > "$FILE_OUT"