#!/bin/bash

D=`dirname $0`
cd $D


CORPUS_ID=$1
FILE_WILDCARD=$2
# 2013-*.xml

SOFT_SIZE_LIMIT=10000000000



set -o allexport
if [ -f "config.sh" ]; then
  source config.sh
fi
set +o allexport

mkdir -p $CORPORA_DIR/$CORPUS_ID

RAW_XML_DIR=$DATA_DIR/audio-tei
ANNOTATED_XML_DIR=$TEITOK_CORPUS/xmlfiles
AUDIO_DIR=$TEITOK_CORPUS/Audio

RAW_XML_DIR_OUTPUT=$CORPORA_DIR/$CORPUS_ID/${CORPUS_ID}-raw
ANNOTATED_XML_DIR_OUTPUT=$CORPORA_DIR/$CORPUS_ID/${CORPUS_ID}-annotated

AUDIO_FILE_OUTPUT_TEMPLATE=$CORPORA_DIR/$CORPUS_ID/${CORPUS_ID}-audio-


for d in `ls -d $RAW_XML_DIR/*/`
do
  rsync -a --update --prune-empty-dirs --include="$FILE_WILDCARD" --exclude='*.*' $d $RAW_XML_DIR_OUTPUT
done

rsync -a --update --prune-empty-dirs --include="$FILE_WILDCARD" --exclude='*.*' $ANNOTATED_XML_DIR/ $ANNOTATED_XML_DIR_OUTPUT

grep -rFH 'u who="#' $RAW_XML_DIR_OUTPUT|grep -o 'who="#[^"]*'|sed 's/.*#//'|sort|uniq |awk 'BEGIN {print "<?xml version=\"1.0\" encoding=\"UTF8\"?>\n<personList>"} /.*/ {print "  <person ref=\"" $0 "\" />"} END {print "</personList>"}' | xsltproc corpus-builder/filterperson.xslt - > $RAW_XML_DIR_OUTPUT/person.xml
cp $RAW_XML_DIR_OUTPUT/person.xml $ANNOTATED_XML_DIR_OUTPUT/person.xml



tar -czf  ${ANNOTATED_XML_DIR_OUTPUT}.tar.gz --mode='a+rwX' --directory=$ANNOTATED_XML_DIR_OUTPUT/.. ${ANNOTATED_XML_DIR_OUTPUT##*/}
tar -czf  ${RAW_XML_DIR_OUTPUT}.tar.gz --mode='a+rwX' --directory=$RAW_XML_DIR_OUTPUT/.. ${RAW_XML_DIR_OUTPUT##*/}

AUDIO_LIST=`grep -rFH 'audio/mp3' $RAW_XML_DIR_OUTPUT| grep -o "[^\"]*\.mp3"|sort`

AUDIO_ACT_DIR=''
AUDIO_FILE_OUTPUT_CNT=001
AUDIO_FILE_OUTPUT="${AUDIO_FILE_OUTPUT_TEMPLATE}${AUDIO_FILE_OUTPUT_CNT}.tar"

for AUDIO_FILE in $AUDIO_LIST
do
  if [ "$AUDIO_ACT_DIR" != ${AUDIO_FILE%/*} ]; then
  	AUDIO_ACT_DIR=${AUDIO_FILE%/*}
    if [ -f "$AUDIO_FILE_OUTPUT" ]; then
      # test filesize
      if [ `stat -c%s $AUDIO_FILE_OUTPUT` -gt $SOFT_SIZE_LIMIT ]; then
        AUDIO_FILE_OUTPUT_CNT=$(printf %03d $(( $(printf %d "$((10#$AUDIO_FILE_OUTPUT_CNT))") + 1)) )
        AUDIO_FILE_OUTPUT="${AUDIO_FILE_OUTPUT_TEMPLATE}${AUDIO_FILE_OUTPUT_CNT}.tar"
      fi
    fi
  fi
  FLAG=--create
  if [ -f $AUDIO_FILE_OUTPUT ]; then
  	FLAG=--append
  fi
  tar $FLAG -f $AUDIO_FILE_OUTPUT --mode='a+rwX' --directory=$AUDIO_DIR $AUDIO_FILE
done

rm -r $RAW_XML_DIR_OUTPUT $ANNOTATED_XML_DIR_OUTPUT

