#!/bin/bash

D=`dirname $0`
cd $D

pid=$$



export DATA_DIR=$PWD/out
export SCRAPPER_CACHE=1 # For development ONLY!
export SCRAPPER_FAST=1 # For development ONLY!
export SHARED=.
export TEITOK=./TEITOK
export TEITOK_CORPUS=$TEITOK/projects/CORPUS

set -o allexport
if [ -f "config.sh" ]; then
  source config.sh
fi
set +o allexport

export ID=`date +"%Y%m%dT%H%M%S"`

function log {
  echo -e `date +"%Y-%m-%d %T"`"\t$1" >> ${SHARED}/parczech.log
}

function log_process {
  echo "$pid steno_download" > ${SHARED}/current_process
}


log "STARTED $ID: $pid"

if [ -f 'current_process' ]; then
  proc=`cat 'current_process'`
  echo "another process is running: $proc"
  log "another process is running: $proc"
  log "FINISHED $ID: $pid"
  exit 0;
fi

###############################
### Download stenoprotocols ###
#   input:
#   output:
#     new:
#       downloader-yaml/$ID
#         - contains exported yaml files (only for quick manual checkout)
#       downloader-tei/$ID
#         ./YYYY-SSS                     ## each session has its own directory
#           - teifiles
#         ./person.xml                   ## copied from previeous run
#     update:
#       downloader-tei/sha1sum.list      ## pairs shasum=/path/.../downloader-tei/$ID/YYYY-SSS/teifile.xml
#
###############################

log_process "steno_download"
log "downloading $ID"

export CL_WORKDIR=$DATA_DIR/downloader
export CL_OUTDIR_YAML=$DATA_DIR/downloader-yaml
export CL_OUTDIR_TEI=$DATA_DIR/downloader-tei
export CL_SCRIPT=stenoprotokoly_2013ps-now.pl
mkdir -p $CL_WORKDIR
mkdir -p $CL_OUTDIR_YAML
mkdir -p $CL_OUTDIR_TEI

export LAST_ID=`ls $CL_OUTDIR_TEI|grep -v "sha1sum.list"|sort|tail -n 1`


if [ -f "$CL_OUTDIR_TEI/$LAST_ID/person.xml" ]; then
  echo "moving $CL_OUTDIR_TEI/$LAST_ID/person.xml"
  mkdir -p "$CL_OUTDIR_TEI/$ID"
  cp "$CL_OUTDIR_TEI/$LAST_ID/person.xml" "$CL_OUTDIR_TEI/$ID"
fi

perl -I downloader/lib -I lib -I ${SHARED}/lib downloader/$CL_SCRIPT --tei $CL_OUTDIR_TEI --yaml $CL_OUTDIR_YAML --id $ID --prune '201.-04.-.$'

# remove duplicities:
# calculate hashes for new files
export DOWNLOADER_TEI_HASHES=$DATA_DIR/downloader-tei/sha1sum.list
touch $DOWNLOADER_TEI_HASHES

for hf in `find "$CL_OUTDIR_TEI/$ID" -type f ! -name "person.xml" -exec sha1sum {} \;|tr -s ' '|tr ' ' '='`
do
  hash=${hf%=*}
  file=${hf##*/}
  filepath=${hf##*=}
  if grep -xq "${hash}.*${file}" $DOWNLOADER_TEI_HASHES
  then
  	rm $filepath
  else
  	echo $hf >> $DOWNLOADER_TEI_HASHES
  fi
done


###############################
###    Download audio       ###
#  input:
#    downloader-tei/$ID        ## used for list of mp3 files (grepped !!!)
#  output:
#    audio-orig
#      ./${ID}.audio.list      ## mp3 links that occure in new tei files
#      www.psp.cz              ## directory structure with downloaded mp3 files
###############################

log_process "audio_download"
log "downloading audio $ID"

export AUDIO_PATH_ORIG=$DATA_DIR/audio-orig
mkdir -p $AUDIO_PATH_ORIG

grep -r "audio/mp3" $CL_OUTDIR_TEI/$ID|sed "s/.*url=\"//;s/\".*//" > $AUDIO_PATH_ORIG/${ID}.audio.list
wget --no-clobber --directory-prefix $AUDIO_PATH_ORIG --force-directories -w 1 -i $AUDIO_PATH_ORIG/${ID}.audio.list 2>&1 | grep -B 2 ' 404 ' > $AUDIO_PATH_ORIG/${ID}.404.list
mv $AUDIO_PATH_ORIG/${ID}.audio.list $AUDIO_PATH_ORIG/${ID}.audio.list.done



########################################
### Merge audio and enrich tei files ###
#  input:
#    downloader-tei/$ID
#    audio-orig/www.psp.cz
#  output:
#    audio-merged/$ID
#    audio-tei/$ID
###############################

log_process "audio_merging"
log "merging audio $ID"

export AUDIO_PATH_MERGED=$DATA_DIR/audio-merged/${ID}
export AUDIO_PATH_TEI=$DATA_DIR/audio-tei/${ID}
mkdir -p $AUDIO_PATH_MERGED
mkdir -p $AUDIO_PATH_TEI

for tei in `find "$CL_OUTDIR_TEI/$ID" -type f ! -name "person.xml"`
do
  rm -rf $AUDIO_PATH_MERGED/tmp
  MERGED_AUDIO_FILE=`echo "${tei#*tei/*/}"| sed "s/xml$/mp3/"`
  MERGED_AUDIO_TEI=$AUDIO_PATH_TEI/${tei#*tei/*/}
  AUDIO_LIST=`perl -I lib -MTEI::ParlaClarin::TEI -e 'my $tei=TEI::ParlaClarin::TEI->load_tei(file => $ARGV[0]);print join("\n",@{$tei->getAudioUrls()});$tei->addAudioFile($ARGV[1]); $tei->toFile(outputfile => $ARGV[2])' $tei $MERGED_AUDIO_FILE $MERGED_AUDIO_TEI`

  log "merging to $AUDIO_PATH_MERGED/$MERGED_AUDIO_FILE";
  mkdir -p $AUDIO_PATH_MERGED/${MERGED_AUDIO_FILE%/*}
  mkdir $AUDIO_PATH_MERGED/tmp
  for url in $AUDIO_LIST
  do
    AUDIO_REL_PATH=${url#*//}
    AUDIO_FILENAME=${url##*/}
    echo $AUDIO_FILENAME $AUDIO_REL_PATH
    ffmpeg -t 600 -i $AUDIO_PATH_ORIG/$AUDIO_REL_PATH -acodec copy $AUDIO_PATH_MERGED/tmp/$AUDIO_FILENAME
    echo "$AUDIO_PATH_MERGED/tmp/$AUDIO_FILENAME" >> $AUDIO_PATH_MERGED/tmp/filelist
  done  # dont crop last file
  ffmpeg -i "concat:"$(cat $AUDIO_PATH_MERGED/tmp/filelist | tr "\n" "|" | sed "s/|$//") -acodec copy $AUDIO_PATH_MERGED/$MERGED_AUDIO_FILE
  chmod -w $AUDIO_PATH_MERGED/$MERGED_AUDIO_FILE
  rm -rf $AUDIO_PATH_MERGED/tmp
done




###############################
###     Tokenize tei        ###
#  input:
#    audio-tei/$ID
#  output:
#    tokenizer-tei/$ID
###############################

# log_process "tei_tokenizing"
# log "tokenizing tei $ID"

# export TOKENIZER_TEI=$DATA_DIR/tokenizer-tei/${ID}
# mkdir -p $TOKENIZER_TEI

# rsync -a --prune-empty-dirs $AUDIO_PATH_TEI/ $TOKENIZER_TEI
# find $TOKENIZER_TEI -type f -name '*.xml' -exec perl $TEITOK/common/Scripts/xmltokenize.pl  {} \;


###############################################
###     Tokenize, lemmatize, PoS tei        ###
#  input:
#    audio-tei/$ID
#  output:
#    morphodita-tei/$ID
###############################################

log_process "tei_morphodita"
log "morphodita tei $ID"

export MORPHODITA_TEI=$DATA_DIR/morphodita-tei/${ID}
mkdir -p $MORPHODITA_TEI

rsync -a --prune-empty-dirs $AUDIO_PATH_TEI/ $MORPHODITA_TEI
find $MORPHODITA_TEI -type f -name '*.xml' > $MORPHODITA_TEI/filelist

 perl MorphoDiTa-module/xmlmorphodita.pl --model $SHARED/MorphoDiTa-module/models/czech-morfflex-pdt-161115.tagger  --filelist $MORPHODITA_TEI/filelist --debug

###############################
###     NameTag tei         ###
#  input:
#    morphodita-tei/$ID
#  output:
#    nametag-tei/$ID
###############################

log_process "tei_nametagging"
log "nametagging tei $ID"

export NAMETAG_TEI=$DATA_DIR/nametag-tei/${ID}
mkdir -p $NAMETAG_TEI

# copy tokenized+PoSed+Lematized files (ignore backups *.nmorph.xml)
rsync -a --prune-empty-dirs --exclude '*.nmorph.xml' $MORPHODITA_TEI/ $NAMETAG_TEI

find $NAMETAG_TEI -type f -name '*.xml' > $NAMETAG_TEI/filelist
perl NameTag-module/xmlnametag.pl --model $SHARED/NameTag-module/models/czech-cnec2.0-140304.ner --filelist $NAMETAG_TEI/filelist --debug


###############################
###     FINALIZE            ###
#  input:
#    nametag-tei/$ID
###############################

log_process "tei publishing"
log "publishing tei $ID"

export FINALIZE_INPUT=$NAMETAG_TEI
export FINALIZE_EXCLUDE="*.nntg.xml"

rsync -a --prune-empty-dirs --exclude "filelist" --exclude "$FINALIZE_EXCLUDE" $FINALIZE_INPUT/ $TEITOK_CORPUS/xmlfiles

cp "$CL_OUTDIR_TEI/$ID/person.xml" "$TEITOK_CORPUS/Resources/person.xml"



echo "TODO: link merged audio !!!"




### upload (new and updated) tei files to teitok ###
# run
cd $TEITOK_CORPUS
#  Removing the old files
# command:
/bin/rm -f cqp/*
#----------------------
#(1) Encoding the corpus
#command:
/usr/local/bin/tt-cwb-encode -r cqp
#----------------------
#(2) Creating the corpus
#command:
/usr/local/bin/cwb-makeall  -r cqp TT-PARCZECH
#----------------------
#Regeneration completed on Fri Mar 20 22:48:27 2020




### End of process ###
cd $D
rm ${SHARED}/current_process
log "FINISHED $ID: $pid"