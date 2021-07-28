#!/bin/bash

PWD=`pwd`
D=`dirname $0`

pid=$$

CONFIG_FILE="config.sh"
INPUT_RAW_CORPUS=
INPUT_ANN_CORPUS=
PREFIX=

usage() {
  echo -e "Usage: $0 -v -t INPUT_RAW_CORPUS -a INPUT_ANA_CORPUS -c CONFIG_FILE" 1>&2
  exit 1
}

while getopts  ':Mt:a:c:'  opt; do
  case "$opt" in
    'M')
      PREFIX="ParlaMint."
      ;;
    'c')
      CONFIG_FILE=$OPTARG
      ;;
    't')
      INPUT_RAW_CORPUS=$OPTARG
      ;;
    'a')
      INPUT_ANA_CORPUS=$OPTARG
      ;;
    *)
      usage
  esac
done


export SHARED=.

set -o allexport
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi
set +o allexport

function log {
  str=`date +"%Y-%m-%d %T"`"\t$@"
  echo -e "$str"
}


log "STARTED: update_tagUsage $pid"
log "CONFIG FILE: $CONFIG_FILE"


update_tagUsage() {
  CORPFILE=$1
  METADATA=$2
  log "running update ($PREFIX$METADATA) on $CORPFILE"
  if [ ! -s "$CORPFILE" ]; then
    return 0
  fi
  DATADIR=${CORPFILE%/*}
  log "base directory: $DATADIR"

  FILELIST=`mktemp -t "$(basename $0).fl.XXXXXXXXXX"`
  VARIABLES_LOG=`mktemp -t "$(basename $0).var.XXXXXXXXXX"`
  ls -l $FILELIST $VARIABLES_LOG
  $XPATH_QUERY "$CORPFILE" \
               "declare option saxon:output 'omit-xml-declaration=yes';
                string-join( for \$i in /*/*[local-name() = 'include' and @href] return \$i/@href,',')" \
               | tr "," "\n" >> $FILELIST

  perl -I $D/../lib $D/metadater.pl --metadata-name "$PREFIX$METADATA" \
                                   --metadata-file $D/tei_parczech.xml \
                                   --filelist $FILELIST \
                                   --input-dir $DATADIR \
                                   --output-dir $DATADIR \
                                   --variables-log "$VARIABLES_LOG"

  CORPUS_VARS=`cat "$VARIABLES_LOG"|sed -n 's/^AGGREGATED[|]//p'|tr "\n" "|"|sed 's/[|]$//'`
  log "VARIABLES: $CORPUS_VARS"

  perl -I $D/../lib $D/metadater.pl --metadata-name "$PREFIX$METADATA" \
                                   --metadata-file $D/tei_parczech.xml \
                                   --input-file "$CORPFILE"  \
                                   --output-file "$CORPFILE" \
                                   --variables "$CORPUS_VARS"
  rm $VARIABLES_LOG $FILELIST
}

update_tagUsage "$INPUT_RAW_CORPUS" "tagsDecl"
update_tagUsage "$INPUT_ANA_CORPUS" "tagsDecl.ana"



log "FINISHED update_tagUsage: $pid"