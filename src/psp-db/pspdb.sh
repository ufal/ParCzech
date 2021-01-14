#!/bin/bash


PWD=`pwd`
D=`dirname $0`
PARAMS=()

usage() {
  echo -e "Usage: $0 -p PERSONLIST_FILE -g GOV_DATA_DIRRECTORY -o OUTPUT_DIRECTORY" 1>&2
  exit 1
}

while getopts  ':p:o:g:c:'  opt; do
  case "$opt" in
    'p')
      PERSONLIST=$OPTARG
      ;;
    'o')
      OUTPUT_DIRECTORY=$OPTARG
      ;;
    'g')
      PARAMS+=(--gov-input-dir $OPTARG )
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

if [ -z "$OUTPUT_DIRECTORY" ] || [ -z "$PERSONLIST" ] ; then
  usage
fi

[ -d $OUTPUT_DIRECTORY ] || mkdir -p $OUTPUT_DIRECTORY;


## download files
wget -O "$OUTPUT_DIRECTORY/poslanci.zip"  https://www.psp.cz/eknih/cdrom/opendata/poslanci.zip

## unpack
unzip -o "$OUTPUT_DIRECTORY/poslanci.zip" -d "$OUTPUT_DIRECTORY/poslanci"


perl -I $D/../lib $D/pspdb-generate-xml.pl --person-list "$PERSONLIST" "${PARAMS[@]}" --translations "$D/translations.unl" --patches "$D/patches.unl" --output-dir "$OUTPUT_DIRECTORY" --input-db-dir "$OUTPUT_DIRECTORY" --debug

