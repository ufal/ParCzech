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


if [ -z $XML_VALIDATOR ] ; then
  echo "no validator $XML_VALIDATOR"
  usage
fi

for FILE in $INDIR/ParlaMint-CZ*.xml ;
do
  #ANA=`echo $FILE | grep 'ana.xml' | sed 's/.*.ana.xml/.ana/'`
  TYPE=`$XPATH_QUERY $FILE "declare option saxon:output 'omit-xml-declaration=yes'; concat(/*/local-name(),substring('.ana',1,number(ends-with(/*/@xml:id,'.ana'))*4 ) ) "`
  echo -e "\nVALIDATING $TYPE:\t$FILE"
  $XML_VALIDATOR "$D/ParlaMint/Schema/ParlaMint-${TYPE}.rng" $FILE
done
