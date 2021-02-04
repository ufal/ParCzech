#!/bin/bash


PWD=`pwd`
D=`dirname $0`


usage() {
  echo -e "Usage: $0 -i INDIR " 1>&2
  exit 1
}

while getopts  ':i:c:'  opt; do
  case "$opt" in
    'i')
      INDIR=$OPTARG
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


if [ -z $XSL_TRANSFORM ] ; then
  echo "no transformer $XSL_TRANSFORM"
  usage
fi

CORPUS=`realpath $INDIR/ParlaMint-CZ.xml`
if [ ! -f $CORPUS ] ; then
  CORPUS=`realpath $INDIR/ParlaMint-CZ.ana.xml`
fi


for FILE in $INDIR/ParlaMint-CZ_*.xml ;
do
  $XSL_TRANSFORM "$D/ParlaMint/Scripts/check-links.xsl" $FILE 'XXX' meta="$CORPUS" 2>&1| grep "ERROR" | sed "s@^@$FILE\n\t@"
done
