#!/bin/bash


PWD=`pwd`
D=`dirname $0`

local_lint() {
  echo "no transformer"
}


usage() {
  echo -e "Usage: $0 -C CORPUS_FILE -O OUTPUT_DIRECTORY" 1>&2
  exit 1
}

while getopts  ':C:O:c:'  opt; do
  case "$opt" in
    'C')
      CORPUS_FILE=$OPTARG
      ;;
    'O')
      OUTPUT_DIRECTORY=$OPTARG
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

if [ -z $XPATH_QUERY ] ; then
  XPATH_QUERY='local_lint'
fi

TEI_FILES=`$XPATH_QUERY $CORPUS_FILE "declare option saxon:output 'omit-xml-declaration=yes'; fn:string-join(//*[local-name()='include']/@*,' ')"`

INDIR=${CORPUS_FILE%/*}

for tei_file in $TEI_FILES
do
  echo "$D/tei2teitok.sh  -i "$INDIR/$tei_file" -o "$OUTPUT_DIRECTORY/$tei_file" -C $CORPUS_FILE -c " `realpath $CONFIG_FILE`
  teitok_file=`echo "$tei_file"| sed 's/ana\.xml$/tt.xml/'`
  $D/tei2teitok.sh  -i "$INDIR/$tei_file" -o "$OUTPUT_DIRECTORY/$teitok_file" -C $CORPUS_FILE -c `realpath $CONFIG_FILE`
done
