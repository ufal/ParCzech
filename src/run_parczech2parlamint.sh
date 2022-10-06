#!/bin/bash

D=`dirname $0`
cd $D

pid=$$

CONFIG_FILE="config.sh"
INPUT_RAW_DIR=
INPUT_ANN_DIR=
OUTPUT_DIR=
VALIDATE=0
HANDLER=0
PARAMS=()


usage() {
  echo -e "Usage: $0 -v -t INPUT_RAW_DIR -a INPUT_ANA_DIR -O OUTPUT_DIR -c CONFIG_FILE" 1>&2
  exit 1
}

while getopts  ':t:a:O:c:hv'  opt; do
  case "$opt" in
    'c')
      CONFIG_FILE=$OPTARG
      ;;
    't')
      INPUT_RAW_DIR=$OPTARG
      ;;
    'a')
      INPUT_ANA_DIR=$OPTARG
      ;;
    'O')
      OUTPUT_DIR=$OPTARG
      ;;
    'h')
      HANDLER=1
      ;;
    'v')
      VALIDATE=1
      ;;
    *)
      usage
  esac
done


export DATA_DIR=$PWD/out
export SHARED=.

export METADATA_NAME=ParlaMint

export DATA_PREFIX=ParlaMint-CZ

set -o allexport
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi
set +o allexport

function log {
  str=`date +"%Y-%m-%d %T"`"\t$@"
  echo -e "$str"
}


log "STARTED: $pid"
log "CONFIG FILE: $CONFIG_FILE"


if [ -z "$OUTPUT_DIR" ]; then
  export ID=`date +"%Y%m%dT%H%M%S"`
  OUTPUT_DIR="$DATA_DIR/ParlaMint/$ID"
fi



if [ -z $XPATH_QUERY ] ; then
  XPATH_QUERY='local_lint'
fi


export OUTPUT_ANA_DIR="$OUTPUT_DIR/$DATA_PREFIX.ana/$DATA_PREFIX.TEI.ana"
export OUTPUT_RAW_DIR="$OUTPUT_DIR/$DATA_PREFIX/$DATA_PREFIX.TEI"
export RENAME_LOG="$OUTPUT_DIR/parczech2parlamint.rename"

mkdir -p "$OUTPUT_DIR"

filter_rename () {
  FILE=$1
  while read LINE; do
    echo "$LINE"
    echo "$LINE" | grep "^RENAME:" >> $FILE
  done
}

create_xml_remame () {
  echo '<?xml version="1.0" encoding="UTF-8"?>';
  echo "<rename>"
  while read LINE; do
    echo "$LINE" | sed 's/^RENAME: \([^-]*-[^-]*\)\([^ ]*\) \([^ ]*\)$/  <file from="\1\/\1\2.xml" to="\3.xml" \/>/'
  done
  echo "</rename>"

}

rename_xml_file () {
  DIR=$1
  while read LINE; do
    FROM=`echo "$LINE" | cut -d' ' -f 2`
    TO=`echo "$LINE" | cut -d' ' -f 3`
    echo "$FROM.xml -> $TO.xml"
    mkdir -p "$DIR/${TO%%/*}"
    mv "$DIR/$FROM.xml" "$DIR/$TO.xml"
  done
}

set_handler () {
  FLAG=$1
  if [ "$HANDLER" -eq "1"  ]; then
    if [ "$FLAG" == "-t"  ]; then
      PARAMS=(handler="http://hdl.handle.net/11356/1388" )
    elif [ "$FLAG" == "-a"  ]; then
      PARAMS=(handler="http://hdl.handle.net/11356/1405" )
    fi
  fi
}

create_parlaMint() {
  IN_DIR=$1
  OUT_DIR=$2
  LOG=$3
  FLAG=$4
  SUFF=$5
  INSERTINCL=$6
  set_handler $FLAG
  mkdir -p OUT_DIR
  if [ ! -s "$IN_DIR" ]; then
    echo "warning: missing input directory"
    return 0
  fi
  CORPFILE=`ls $IN_DIR/ParCzech{,.ana}.xml 2> /dev/null`
  echo -e "in directory $IN_DIR\nout directory $OUT_DIR\n$CORPFILE\n"
  if [ ! -s $CORPFILE ]; then
    echo "input corpus file does not exist ($CORPFILE) or is empty "
    less $CORPFILE
    usage
  fi

  for TEIFILE in `$XPATH_QUERY "$CORPFILE" "declare option saxon:output 'omit-xml-declaration=yes'; string-join( for \\$i in /*/*[local-name() = 'include' and @href] return \\$i/@href,',')"|tr "," "\n"` #`grep -o '[^<>]*include [^<>]*' "$CORPFILE"|sed 's/^.*href="//;s/".*$//'`
  do
    echo "$TEIFILE $DATA_PREFIX"
    $XSL_TRANSFORM parlaMint/transform-TEI.xsl "$IN_DIR/$TEIFILE" "$OUT_DIR/${TEIFILE##*/}" id-prefix="$DATA_PREFIX" "${PARAMS[@]}" 2>&1 \
        | filter_rename $LOG
  done
  cat $LOG | create_xml_remame > $LOG.xml
  echo
  echo $CORPFILE $OUT_DIR/${CORPFILE##*/}
  $XSL_TRANSFORM parlaMint/transform-teiCorpus.xsl "$CORPFILE" "$OUT_DIR/${CORPFILE##*/}" insert-include=$INSERTINCL id-prefix="$DATA_PREFIX" outdir="$OUT_DIR" rename="$LOG.xml" "${PARAMS[@]}" 2>&1 \
        | filter_rename $LOG


  cat $LOG | rename_xml_file $OUT_DIR

  echo;echo "UPDATING tagUsage: $OUT_DIR/${DATA_PREFIX}${SUFF}.xml"
  sed -i 's/teiHeader xmlns:xi="[^"]*XInclude"/teiHeader/' "$OUT_DIR/${DATA_PREFIX}${SUFF}.xml"
  $D/metadater/update_tagUsage.sh -M -c `realpath $CONFIG_FILE` $FLAG "$OUT_DIR/${DATA_PREFIX}${SUFF}.xml"

}

create_parlaMint "$INPUT_RAW_DIR" "$OUTPUT_RAW_DIR" "$RENAME_LOG.raw" -t "" 1
create_parlaMint "$INPUT_ANA_DIR" "$OUTPUT_ANA_DIR" "$RENAME_LOG.ana" -a ".ana" 1


if [ "$VALIDATE" -eq "1"  ]; then
  $D/parlaMint/validate.sh -i $OUTPUT_RAW_DIR -c `realpath $CONFIG_FILE`
  $D/parlaMint/validate.sh -i $OUTPUT_ANA_DIR -c `realpath $CONFIG_FILE`
fi


log "FINISHED $OUTPUT_DIR: $pid"