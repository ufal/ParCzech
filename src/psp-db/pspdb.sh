#!/bin/bash


PWD=`pwd`
D=`dirname $0`
PARAMS=()

usage() {
  echo -e "Usage: $0 -p PERSONLIST_FILE -g GOV_DATA_DIRRECTORY -o OUTPUT_DIRECTORY" 1>&2
  exit 1
}

while getopts  ':p:o:g:t:a:c:'  opt; do
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
    't')
      PARAMS+=(--term-list $OPTARG )
      ;;
    'a')
      PARAMS+=(--allterm-person-outfile $OPTARG )
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

sed -i -f <(sed 's#\s*=>\s*#\\s*$/#;s#$#/#;s#^#s/^#' $D/patch_db.map) $OUTPUT_DIRECTORY/poslanci/*.unl

perl -I $D/../lib $D/pspdb-generate-xml.pl --merge-to-events --person-list "$PERSONLIST" "${PARAMS[@]}" --translations "$D/translations.unl" --patches "$D/patches.unl" --roles-patches "$D/roles-patches.unl" --org-ana "$D/org-ana.unl" --output-dir "$OUTPUT_DIRECTORY" --input-db-dir "$OUTPUT_DIRECTORY"

