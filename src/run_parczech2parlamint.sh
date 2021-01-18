#!/bin/bash

D=`dirname $0`
cd $D

pid=$$

CONFIG_FILE="config.sh"
INPUT_RAW_DIR=
INPUT_ANN_DIR=
OUTPUT_DIR=

usage() {
  echo -e "Usage: $0 -t INPUT_RAW_DIR -a INPUT_ANA_DIR -O OUTPUT_DIR -c CONFIG_FILE" 1>&2
  exit 1
}

while getopts  ':t:a:O:c:'  opt; do
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
    '0')
      OUTPUT_DIR=$OPTARG
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
  OUTPUT_DIR="$PWD/out/ParlaMint/$ID"
fi

export OUTPUT_ANA_DIR="$OUTPUT_DIR/$DATA_PREFIX.ana/$DATA_PREFIX.TEI.ana"
export OUTPUT_RAW_DIR="$OUTPUT_DIR/$DATA_PREFIX/$DATA_PREFIX.TEI"


mkdir -p "$OUTPUT_DIR"


create_parlaMint() {
  IN_DIR=$1
  OUT_DIR=$2
  mkdir -p OUT_DIR
  CORPFILE=`echo $IN_DIR/ParCzech*.xml`
  echo -e "in directory $IN_DIR\nout directory $OUT_DIR\n$CORPFILE\n"
  if [ ! -s $CORPFILE ]; then
    echo "input corpus file does not exist ($CORPFILE) or is empty "
    less $CORPFILE
    usage
  fi
  for TEIFILE in `grep -o '[^<>]*include [^<>]*' "$CORPFILE"|sed 's/^.*href="//;s/".*$//'`
  do
    echo "$TEIFILE $DATA_PREFIX"
    $XSL_TRANSFORM parlaMint/transform-TEI.xsl "$IN_DIR/$TEIFILE" "$OUT_DIR/${TEIFILE##*/}" id-prefix="$DATA_PREFIX"
  done
  echo
  echo $CORPFILE $OUT_DIR/${CORPFILE##*/}
    $XSL_TRANSFORM parlaMint/transform-teiCorpus.xsl "$CORPFILE" "$OUT_DIR/${CORPFILE##*/}" id-prefix="$DATA_PREFIX" outdir="$OUT_DIR"
}

create_parlaMint $INPUT_RAW_DIR $OUTPUT_RAW_DIR
create_parlaMint $INPUT_ANA_DIR $OUTPUT_ANA_DIR



log "FINISHED $OUTPUT_DIR: $pid"