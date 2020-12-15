#!/bin/bash

D=`dirname $0`
cd $D

pid=$$

CONFIG_FILE="config.sh"
DOWN_PARAMS=()

usage() {
  echo -e "Usage: $0 -c CONFIG_FILE -p PRUNE_TEMPLATE" 1>&2
  exit 1
}

while getopts  ':c:p:'  opt; do # -l "identificator:,file-pattern:,export-audio" -a -o
  case "$opt" in
    'c')
      CONFIG_FILE=$OPTARG
      ;;
    'p')
      DOWN_PARAMS+=(--prune $OPTARG )
      ;;
    *)
      usage
  esac
done


export DATA_DIR=$PWD/out
export SHARED=.
export TEITOK=./TEITOK
export TEITOK_CORPUS=$TEITOK/projects/CORPUS

set -o allexport
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi
set +o allexport

export ID=`date +"%Y%m%dT%H%M%S"`

function log {
  echo -e `date +"%Y-%m-%d %T"`"\t$@" >> ${SHARED}/parczech.log
}

function log_process {
  echo "$pid steno_download" > ${SHARED}/current_process
}


log "STARTED $ID: $pid"
log "CONFIG FILE: $CONFIG_FILE"
log "params: ${DOWN_PARAMS[@]}"

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

export CL_WORKDIR=$DATA_DIR/downloader
export CL_OUTDIR_YAML=$DATA_DIR/downloader-yaml
export CL_OUTDIR_TEI=$DATA_DIR/downloader-tei
export CL_OUTDIR_CACHE=$DATA_DIR/downloader-cache
export CL_OUTDIR_HTML=$DATA_DIR/downloader-html
export CL_SCRIPT=stenoprotokoly_2013ps-now.pl
export FILELISTS_DIR=$DATA_DIR/filelists
mkdir -p $CL_WORKDIR
mkdir -p $CL_OUTDIR_YAML
mkdir -p $CL_OUTDIR_TEI
mkdir -p $CL_OUTDIR_CACHE
mkdir -p $CL_OUTDIR_HTML
mkdir -p $FILELISTS_DIR

export DOWNLOADER_TEI="$CL_OUTDIR_TEI/$ID"
export PERSON_LIST_PATH="$DOWNLOADER_TEI/person.xml"
export NEW_TEI_FILELIST="$FILELISTS_DIR/$ID.tei.fl"
export LAST_ID=`ls $CL_OUTDIR_TEI|grep -v "sha1sum.list"|sort|tail -n 1`


if [ -f "$CL_OUTDIR_TEI/$LAST_ID/person.xml" ]; then
  echo "moving $CL_OUTDIR_TEI/$LAST_ID/person.xml"
  mkdir -p "$DOWNLOADER_TEI"
  cp "$CL_OUTDIR_TEI/$LAST_ID/person.xml" "$PERSON_LIST_PATH"
fi

log "downloading $CL_OUTDIR_TEI"

perl -I downloader/lib -I lib -I ${SHARED}/lib downloader/$CL_SCRIPT --tei $CL_OUTDIR_TEI --yaml $CL_OUTDIR_YAML  --cache $CL_OUTDIR_CACHE --id $ID  "${DOWN_PARAMS[@]}"

# remove duplicities:
# calculate hashes for new files
export DOWNLOADER_TEI_HASHES=$DATA_DIR/downloader-tei/sha1sum.list
touch $DOWNLOADER_TEI_HASHES

for hf in `find "$DOWNLOADER_TEI" -type f ! -name "person.xml" -exec sha1sum {} \;|tr -s ' '|tr ' ' '='`
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

find "$DOWNLOADER_TEI" -type f -name '*.xml' ! -name "person.xml" -printf '%P\n' > $NEW_TEI_FILELIST


### cache to html
log "backup html $CL_OUTDIR_HTML/$ID"
./cache_to_dir_tree.sh -c $CL_OUTDIR_CACHE/$ID -o $CL_OUTDIR_HTML/$ID

################################
### Metadata to download-tei ###
#  input:
#    downloader-tei/$ID
#  output:
#    downloader-tei-meta/$ID
###############################

export DOWNLOADER_TEI_META=$DATA_DIR/downloader-tei-meta/${ID}
mkdir -p $DOWNLOADER_TEI_META

export METADATA_NAME=ParCzechPS7-2.0
echo "WARNING: metadata-name $METADATA_NAME is temporary - in future change to ParCzech-live-2.0"

log "adding metadata $METADATA_NAME $DOWNLOADER_TEI_META"
perl -I lib metadater/metadater.pl --metadata-name "$METADATA_NAME" --metadata-file metadater/tei_parczech.xml --filelist $NEW_TEI_FILELIST --input-dir $DOWNLOADER_TEI --output-dir $DOWNLOADER_TEI_META

###############################
###    Download audio       ###
#  input:
#    downloader-tei/$ID        ## used for list of mp3 files (grepped !!!)
#  output:
#    audio-orig
#      ./${ID}.audio.list      ## mp3 links that occure in new tei files
#      www.psp.cz              ## directory structure with downloaded mp3 files
###############################

#log_process "audio_download"
#log "downloading audio $ID"

# downloading moved to merging part
#export AUDIO_PATH_ORIG=$DATA_DIR/audio-orig
#mkdir -p $AUDIO_PATH_ORIG

#grep -ro "[^<]*audio/mp3[^>]*" $CL_OUTDIR_TEI/$ID|sed "s/.*url=\"//;s/\".*//" > $AUDIO_PATH_ORIG/${ID}.audio.list
#wget --no-clobber --directory-prefix $AUDIO_PATH_ORIG --force-directories -w 1 -i $AUDIO_PATH_ORIG/${ID}.audio.list 2>&1 | grep -B 2 ' 404 ' > $AUDIO_PATH_ORIG/${ID}.404.list
#mv $AUDIO_PATH_ORIG/${ID}.audio.list $AUDIO_PATH_ORIG/${ID}.audio.list.done



########################################
### Merge audio and enrich tei files ###
#  input:
#    downloader-tei/$ID
#    audio-orig/www.psp.cz
#  output:
#    audio-merged/$ID
#    audio-tei/$ID
###############################

# log_process "audio_merging"
# log "merging audio $ID"

# export AUDIO_PATH_MERGED=$DATA_DIR/audio-merged/${ID}
# export AUDIO_PATH_TEI=$DATA_DIR/audio-tei/${ID}
# export AUDIO_PATH_CORPUS=$TEITOK_CORPUS/Audio

# mkdir -p $AUDIO_PATH_MERGED
# mkdir -p $AUDIO_PATH_TEI

# for tei in `find "$CL_OUTDIR_TEI/$ID" -type f ! -name "person.xml"`
# do
#   rm -rf $AUDIO_PATH_MERGED/tmp
#   MERGED_AUDIO_FILE=`echo "${tei#*tei/*/}"| sed "s/xml$/mp3/"`
#   MERGED_AUDIO_TEI=$AUDIO_PATH_TEI/${tei#*tei/*/}

#   AUDIO_LIST=`perl -I lib -MTEI::ParlaClarin::TEI -e '
#     my $tei=TEI::ParlaClarin::TEI->load_tei(file => $ARGV[0]);
#     my @list = @{$tei->getAudioUrls()};
#     print STDERR $ARGV[2],"\n";
#     if(@list) {
#     	print STDERR join("\n",@list),"\n";
#       print join("\n",@list);
#       $tei->hideAudioUrls();
#       $tei->addAudioFile($ARGV[1]);
#     }
#     $tei->toFile(outputfile => $ARGV[2]);
#     exit 1 unless @list' $tei $MERGED_AUDIO_FILE $MERGED_AUDIO_TEI`

#   if [ $? -ne 0 ]; then
#   	echo "NO AUDIO   $MERGED_AUDIO_TEI"
#     echo "NO AUDIO   $MERGED_AUDIO_TEI" >> $AUDIO_PATH_MERGED/${ID}.log
#    	continue
#   fi

#   if [ -f "$AUDIO_PATH_CORPUS/$MERGED_AUDIO_FILE" ]; then
#     echo "EXISTS   $AUDIO_PATH_CORPUS/$MERGED_AUDIO_FILE" >> $AUDIO_PATH_MERGED/${ID}.log
#     continue
#   fi
#   log "merging to $AUDIO_PATH_MERGED/$MERGED_AUDIO_FILE";
#   mkdir -p $AUDIO_PATH_CORPUS/${MERGED_AUDIO_FILE%/*}
#   mkdir $AUDIO_PATH_MERGED/tmp

#   echo "$AUDIO_LIST" | tr " " "\n" > $AUDIO_PATH_MERGED/tmp/download-audio.list
#   wget --no-clobber --directory-prefix $AUDIO_PATH_ORIG --force-directories -w 1 -i $AUDIO_PATH_MERGED/tmp/download-audio.list 2>&1 | grep -B 2 ' 404 ' >> $AUDIO_PATH_ORIG/${ID}.404.list

#   for url in $AUDIO_LIST
#   do
#     AUDIO_REL_PATH=${url#*//}
#     AUDIO_FILENAME=${url##*/}
#     echo $AUDIO_FILENAME $AUDIO_REL_PATH
#     ffmpeg -t 600 -i $AUDIO_PATH_ORIG/$AUDIO_REL_PATH -acodec copy $AUDIO_PATH_MERGED/tmp/$AUDIO_FILENAME
#     echo "$AUDIO_PATH_MERGED/tmp/$AUDIO_FILENAME" >> $AUDIO_PATH_MERGED/tmp/filelist
#   done  # dont crop last file
#   ffmpeg -i "concat:"$(cat $AUDIO_PATH_MERGED/tmp/filelist | tr "\n" "|" | sed "s/|$//") -acodec copy $AUDIO_PATH_CORPUS/$MERGED_AUDIO_FILE
#   rm -rf $AUDIO_PATH_MERGED/tmp
#   echo "CREATED    $AUDIO_PATH_CORPUS/$MERGED_AUDIO_FILE" >> $AUDIO_PATH_MERGED/${ID}.log
#done


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

# log_process "tei_morphodita"
# log "morphodita tei $ID"

# export MORPHODITA_TEI=$DATA_DIR/morphodita-tei/${ID}
# export MORPHODITA_TEI_INPUT=$CL_OUTDIR_TEI/${ID}
# mkdir -p $MORPHODITA_TEI

# rsync -a --exclude "person.xml" --prune-empty-dirs $MORPHODITA_TEI_INPUT/ $MORPHODITA_TEI
# find $MORPHODITA_TEI -type f -name '*.xml' > $MORPHODITA_TEI/filelist

# perl MorphoDiTa-module/xmlmorphodita.pl --model $SHARED/MorphoDiTa-module/models/czech-morfflex-pdt-161115.tagger  --filelist $MORPHODITA_TEI/filelist --tags="msd mul::uposf" --tags="ana cs::multext" --tags="ana cs::pdt" --tags="pos mul::uposf" --no-backup-file


### paginate (backuped to *.nopb.xml)
# perl paginator-module/paginator.pl  --filelist $MORPHODITA_TEI/filelist
### convert tags (backuped to *.pdtuposf.xml)
# perl pdt2uposf-module/pdt2uposf.pl  --filelist $MORPHODITA_TEI/filelist --fixlemma



###############################
###     NameTag tei         ###
#  input:
#    morphodita-tei/$ID
#  output:
#    nametag-tei/$ID
###############################

# log_process "tei_nametagging"
# log "nametagging tei $ID"

# export NAMETAG_TEI=$DATA_DIR/nametag-tei/${ID}
# mkdir -p $NAMETAG_TEI

# # copy tokenized+PoSed+Lematized files (ignore backups *.nmorph.xml)
# rsync -a --prune-empty-dirs --exclude '*.nmorph.xml' --exclude '*.nopb.xml' --exclude '*.pdtuposf.xml' $MORPHODITA_TEI/ $NAMETAG_TEI

# find $NAMETAG_TEI -type f -name '*.xml' > $NAMETAG_TEI/filelist
# perl NameTag-module/xmlnametag.pl --model $SHARED/NameTag-module/models/czech-cnec2.0-140304-no_numbers.ner --filelist $NAMETAG_TEI/filelist --token-name="w" --token-name="pc" --no-backup-file



###############################################
###     UDPipe tei (using web service)      ###
###  Tokenize, lemmatize, PoS, parse tei    ###
#  input:
#    downloader-tei-meta/$ID
#  output:
#    udpipe-tei/$ID
###############################################

export UDPIPE_TEI=$DATA_DIR/udpipe-tei/${ID}
mkdir -p $UDPIPE_TEI
log "annotating udpipe2 $UDPIPE_TEI"

perl -I lib udpipe2/udpipe2.pl --model=czech-pdt-ud-2.6-200830 --filelist $NEW_TEI_FILELIST --input-dir $DOWNLOADER_TEI_META --output-dir $UDPIPE_TEI

###############################
###     NameTag tei         ###
#  input:
#    udpipe-tei/$ID
#  output:
#    nametag-tei/$ID
###############################

export NAMETAG_TEI=$DATA_DIR/nametag-tei/${ID}
mkdir -p $NAMETAG_TEI
log "annotating nametag2  $NAMETAG_TEI"

perl -I lib nametag2/nametag2.pl --model=czech-cnec2.0-200831 --filelist $NEW_TEI_FILELIST --input-dir $UDPIPE_TEI --output-dir $NAMETAG_TEI



################################
### Metadata to annotated    ###
#  input:
#    nametag-tei/$ID
#  output:
#    annotated-tei-meta/$ID
###############################

export ANNOTATED_TEI_META=$DATA_DIR/annotated-tei-meta/${ID}
mkdir -p $ANNOTATED_TEI_META

echo "WARNING: metadata-name $METADATA_NAME.ann is temporary - in future change to ParCzech-live-2.0.ann"
log "adding metadata $METADATA_NAME.ann $ANNOTATED_TEI_META"
perl -I lib metadater/metadater.pl --metadata-name "$METADATA_NAME.ann" --metadata-file metadater/tei_parczech.xml --filelist $NEW_TEI_FILELIST --input-dir $NAMETAG_TEI --output-dir $ANNOTATED_TEI_META


echo "TODO: fix tei to teitok conversion";exit;
###############################
###     FINALIZE            ###
### converting to teitok    ###
#  input:
#    annotated-tei-meta/$ID
#
#
###############################

export TEITOK_TEI=$DATA_DIR/teitok-tei/${ID}
mkdir -p $TEITOK_TEI
log "converting to teitok $TEITOK_TEI"

for tei_file in `cat $NEW_TEI_FILELIST`
do
  out_file=`echo "$tei_file" | sed "s@^$ANNOTATED_META_TEI@$TEITOK_TEI@" `
  ./tei2teitok/tei2teitok.sh  -i $tei_file -o $out_file -c `realpath $CONFIG_FILE`
done




###############################
log_process "tei publishing"
log "publishing tei $ID"

export FINALIZE_INPUT=$TEITOK_TEI

rsync -a --prune-empty-dirs --exclude "filelist" $FINALIZE_INPUT/ $TEITOK_CORPUS/xmlfiles

cp -f "$PERSON_LIST_PATH" "$TEITOK_CORPUS/Resources/person.xml"



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