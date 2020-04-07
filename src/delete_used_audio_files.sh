#!/bin/bash

D=`dirname $0`
cd $D

pid=$$



export DATA_DIR=$PWD/out
export SHARED=.
export TEITOK=./TEITOK
export TEITOK_CORPUS=$TEITOK/projects/CORPUS

set -o allexport
if [ -f "config.sh" ]; then
  source config.sh
fi
set +o allexport

export ID=`date +"%Y%m%dT%H%M%S"`

export AUDIO_PATH_ORIG=$DATA_DIR/audio-orig
export AUDIO_PATH_CORPUS=$TEITOK_CORPUS/Audio
export XML_PATH_CORPUS=$TEITOK_CORPUS/xmlfiles

export DELETE_LOG_PATH=$DATA_DIR/delete-used-audio-log
mkdir -p $DELETE_LOG_PATH

# for each xml file find audio file
# 		keep audio if xml is unauthorized
# 		keep audio if xml contains links but audio does not exist


for xmlfile in `find $XML_PATH_CORPUS -type f -name '*.xml' -printf "%P\n"`
do
  if [[ -f $AUDIO_PATH_CORPUS/${xmlfile%%.xml}.mp3 ]] && [[ ! $xmlfile =~ ^.*u.xml$ ]]; then
    continue
  fi
  # keeping files:
  grep -o "<.--AUDIO:[^ ]*-->" $XML_PATH_CORPUS/$xmlfile | sed "s/.*AUDIO:https*:\/\///;s/-->$//" >> $DELETE_LOG_PATH/${ID}.keep.log
done


for audiofile in `find $AUDIO_PATH_ORIG -type f -name '*.mp3'  -printf "%P\n"`
do

    if ! grep -qFe "$audiofile" $DELETE_LOG_PATH/${ID}.keep.log; then
        echo $audiofile >> $DELETE_LOG_PATH/${ID}.deleted.log
        rm "$AUDIO_PATH_ORIG/$audiofile"
    fi
done

