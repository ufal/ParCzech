#!/bin/bash

D=`dirname $0`
cd $D

pid=$$

CONFIG_FILE="config.sh"
DOWN_PARAMS=()
EXISTING_FILELIST=
EXIT_CONDITION=

usage() {
  echo -e "Usage: $0 -c CONFIG_FILE (-p PRUNE_TEMPLATE | -l FILELIST) -E EXIT_CONDITION" 1>&2
  exit 1
}

while getopts  ':c:p:l:E:'  opt; do # -l "identificator:,file-pattern:,export-audio" -a -o
  case "$opt" in
    'c')
      CONFIG_FILE=$OPTARG
      ;;
    'p')
      [ -n "$EXISTING_FILELIST" ] && usage || DOWN_PARAMS+=(--prune $OPTARG )
      ;;
    'l')
      [ ${#DOWN_PARAMS[@]} -ne 0 ] && usage || EXISTING_FILELIST=$OPTARG
     #[ ${#DOWN_PARAMS[@]} -ne 0 ] && echo "nenula"
      ;;
    'E')
      EXIT_CONDITION=$OPTARG
      ;;
    *)
      usage
  esac
done


export DATA_DIR=$PWD/out
export SHARED=.
export TEITOK=./TEITOK
export TEITOK_CORPUS=$TEITOK/projects/CORPUS
export METADATA_NAME=ParCzech-live


set -o allexport
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi
set +o allexport

function log {
  str=`date +"%Y-%m-%d %T"`"\t$@"
  echo -e "$str"
  echo -e "$str" >> ${SHARED}/parczech.log
}

function log_process {
  echo "$pid steno_download" > ${SHARED}/current_process
}

function skip_process {
  if [ -f "$3" ]; then
    log "testing if file exist ($1)"
    for tested_file in `cat $3`
    do
      if [ ! -s  "$2/$tested_file" ]; then
        log "file does not exists or is empty: $2/$tested_file"
        return 0;
      fi
    done
    log "SKIPPING $1 ($2)"
    return  1;
  fi
  return 0;
}

function skip_process_single_file {
  if [ ! -s  "$2" ]; then
    log "file does not exists or is empty: $2"
    return 0;
  fi
  log "SKIPPING $1 ($2)"
  return  1;
}

log "STARTED: $pid ========================$EXIT_CONDITION"
log "CONFIG FILE: $CONFIG_FILE"


if [ -n "$EXISTING_FILELIST" ]; then
  if [ -f "$EXISTING_FILELIST" ]; then
    log "USING EXISTING FILELIST: $EXISTING_FILELIST"
    export ID=`echo "$EXISTING_FILELIST"| sed 's@^.*\/@@;s@\..*tei\.fl$@@'` # allow interfix eg  20201218T120411.patch01.tei.fl (you can use sublist for patching some files)
  else
    echo  "file $EXISTING_FILELIST error" 1>&2
    usage
  fi
else
  export ID=`date +"%Y%m%dT%H%M%S"`
  log "FRESH RUN: $ID"
fi

log "PROCESS ID: $ID"
log "downloader params: ${DOWN_PARAMS[@]}"

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
#         ./ParCzech-$ID.xml             ## teiCorpus
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
export INTERFIX=ana

export TEICORPUS_FILENAME="ParCzech-$ID.xml"
export ANATEICORPUS_FILENAME="ParCzech-$ID.$INTERFIX.xml"
export TEI_FILELIST="$FILELISTS_DIR/$ID.tei.fl"
if [ -n "$EXISTING_FILELIST" ]; then
  TEI_FILELIST=$EXISTING_FILELIST
fi


if skip_process "downloader" "$CL_OUTDIR_TEI/$ID" "$EXISTING_FILELIST" ; then # BEGIN DOWNLOADER CONDITION

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

find "$DOWNLOADER_TEI" -type f -name '*.xml' ! -name "person.xml" ! -name "$TEICORPUS_FILENAME" -printf '%P\n' > $TEI_FILELIST


### cache to html
log "backup html $CL_OUTDIR_HTML/$ID"
./cache_to_dir_tree.sh -c $CL_OUTDIR_CACHE/$ID -o $CL_OUTDIR_HTML/$ID

fi; # END DOWNLOADER CONDITION

if [ "$EXIT_CONDITION" == "steno" ] ; then
  echo "EXITTING: $EXIT_CONDITION"
  exit
fi

################################
### vlada.cz database file   ###
#  input:
#
#  output:
#    downloader-vlada-db/$ID/gov_osoby.unl
###############################

export GOV_WORKDIR=$DATA_DIR/downloader-vlada
export GOV_OUTDIR_DB=$DATA_DIR/downloader-vlada-db
export GOV_OUTDIR_CACHE=$DATA_DIR/downloader-vlada-cache
export GOV_SCRIPT=gov_person.pl


if skip_process_single_file "gov-db" "$GOV_OUTDIR_DB/$ID/gov_osoby.unl" ; then # BEGIN GOV-DB download CONDITION

mkdir -p $GOV_WORKDIR
mkdir -p $GOV_OUTDIR_DB
mkdir -p $GOV_OUTDIR_CACHE

log "getting government persons"

perl -I downloader/lib -I lib -I ${SHARED}/lib downloader/$GOV_SCRIPT --db $GOV_OUTDIR_DB --id $ID --debug 10

fi # END GOV-DB download CONDITION

if [ "$EXIT_CONDITION" == "gov" ] ; then
  echo "EXITTING: $EXIT_CONDITION"
  exit
fi

################################
### psp database to psp-db   ###
#  input:
#    downloader-vlada-db/$ID/gov_osoby.unl
#
#  output:
#    psp-db/$ID/psp.db
#    psp-db/$ID/person.xml (enriched)
#    psp-db/$ID/org.xml (enriched)
#    psp-db/$ID (tei files with consolidated person ids)
###############################

export PSP_DB_DIR=$DATA_DIR/psp-db/${ID}
export PSP_DB_FILE=$PSP_DB_DIR/psp.db
export PSP_DB_TEI=$PSP_DB_DIR

if skip_process_single_file "psp-db" "$PSP_DB_DIR/person.xml" ; then # BEGIN PSP-DB download CONDITION
mkdir -p $PSP_DB_DIR

log "getting person and org info $PSP_DB_DIR"

echo ./psp-db/pspdb.sh -p "$PERSON_LIST_PATH" -o "$PSP_DB_DIR" -g "$GOV_OUTDIR_DB/$ID" -c `realpath $CONFIG_FILE`
./psp-db/pspdb.sh -p "$PERSON_LIST_PATH" -o "$PSP_DB_DIR" -g "$GOV_OUTDIR_DB/$ID" -c `realpath $CONFIG_FILE`

log "travers person - looking for duplicit persons"
echo ./psp-db/travers_person.sh -p "$PSP_DB_DIR/person.xml" -i "$DOWNLOADER_TEI" -f "$TEI_FILELIST" -o "$PSP_DB_TEI" -c `realpath $CONFIG_FILE`
./psp-db/travers_person.sh -p "$PSP_DB_DIR/person.xml" -i "$DOWNLOADER_TEI" -f "$TEI_FILELIST" -o "$PSP_DB_TEI" -c `realpath $CONFIG_FILE`

## merge orgs with common roles to list of events
$XSL_TRANSFORM psp-db/org_merger.xsl "$PSP_DB_DIR/org.xml" "$PSP_DB_DIR/org.merged.xml" roles="senate|parliament|government"

### set parliament org to parla.term

TERM_TO_PSP=`$XPATH_QUERY "$PSP_DB_DIR/org.merged.xml" "declare option saxon:output 'omit-xml-declaration=yes'; concat(string-join( for \\$i in //*[local-name() = 'org' and @role='parliament']/*[local-name() = 'listEvent']/*[local-name() = 'event'] return concat(concat('ps',substring-before(\\$i/@from, '-')),'=#',\\$i/@xml:id),' '),' ')"`
echo "TERM_TO_PSP:$TERM_TO_PSP"

cp "$DOWNLOADER_TEI/$TEICORPUS_FILENAME" "$PSP_DB_DIR/$TEICORPUS_FILENAME"

for FILE in `echo $TEICORPUS_FILENAME && cat $TEI_FILELIST`;
do
  xmlstarlet edit --inplace \
                  --update "/*/_:teiHeader/_:fileDesc/_:titleStmt/_:meeting[contains(@ana,'#parla.term')]/@ana" \
                  --expr "concat(.,' ',substring-before(substring-after('$TERM_TO_PSP',concat(../@n,'=')),' ')  )" \
                  "$PSP_DB_DIR/$FILE"
done

fi # END PSP-DB download CONDITION

if [ "$EXIT_CONDITION" == "psp-db" ] ; then
  echo "EXITTING: $EXIT_CONDITION"
  exit
fi
################################
### Metadata to download-tei ###
#  input:
#    psp-db/$ID
#    psp-db/$ID/person.xml
#    psp-db/$ID/org.xml
#  output:
#    downloader-tei-meta/$ID
###############################

export DOWNLOADER_TEI_META=$DATA_DIR/downloader-tei-meta/${ID}
VAR_LOG="$DOWNLOADER_TEI_META/variables.log"

if skip_process "metadater" "$DOWNLOADER_TEI_META" "$EXISTING_FILELIST" ; then # BEGIN METADATER CONDITION

mkdir -p $DOWNLOADER_TEI_META

log "adding metadata $METADATA_NAME $DOWNLOADER_TEI_META"
perl -I lib metadater/metadater.pl --metadata-name "$METADATA_NAME" \
                                   --metadata-file metadater/tei_parczech.xml \
                                   --filelist $TEI_FILELIST \
                                   --input-dir $PSP_DB_TEI \
                                   --output-dir $DOWNLOADER_TEI_META \
                                   --variables-log "$VAR_LOG" \

fi; # END METADATER CONDITION

###############################
### Metadata to teiCorpus   ###
###############################

if skip_process_single_file "metadater" "$DOWNLOADER_TEI_META/$TEICORPUS_FILENAME" ; then # BEGIN METADATER teiCorpus CONDITION

log "adding <listPerson> teiCorpus: $DOWNLOADER_TEI_META/pers.$TEICORPUS_FILENAME"

## merge personlist
$XSL_TRANSFORM metadater/knit_persons.xsl "$PSP_DB_DIR/$TEICORPUS_FILENAME" "$DOWNLOADER_TEI_META/pers.$TEICORPUS_FILENAME" personlist-path="$PSP_DB_DIR/person.xml"

log "adding <listOrg> teiCorpus: $DOWNLOADER_TEI_META/org.$TEICORPUS_FILENAME"

## add org
$XSL_TRANSFORM metadater/add_org.xsl "$DOWNLOADER_TEI_META/pers.$TEICORPUS_FILENAME" "$DOWNLOADER_TEI_META/org.$TEICORPUS_FILENAME" org-path="$PSP_DB_DIR/org.merged.xml"

## sort header data in teiCorpus
$XSL_TRANSFORM metadater/header_data_sorter.xsl "$DOWNLOADER_TEI_META/org.$TEICORPUS_FILENAME" "$DOWNLOADER_TEI_META/sorted.$TEICORPUS_FILENAME"


## add metadata to teiCorpus
CORPUS_VARS=`cat "$VAR_LOG"|sed -n 's/^AGGREGATED[|]//p'|tr "\n" "|"|sed 's/[|]$//'`

log "adding metadata to teiCorpus $METADATA_NAME-corpus: $DOWNLOADER_TEI_META/$TEICORPUS_FILENAME"
log "VARIABLES: $CORPUS_VARS"

perl -I lib metadater/metadater.pl --metadata-name "$METADATA_NAME-corpus" \
                                   --metadata-file metadater/tei_parczech.xml \
                                   --input-file "$DOWNLOADER_TEI_META/sorted.$TEICORPUS_FILENAME"  \
                                   --output-file "$DOWNLOADER_TEI_META/$TEICORPUS_FILENAME" \
                                   --variables "$CORPUS_VARS"



fi; # END METADATER teiCorpus CONDITION

if [ "$EXIT_CONDITION" == "tei-meta" ] ; then
  echo "EXITTING: $EXIT_CONDITION"
  exit
fi

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

if skip_process "udpipe2" "$UDPIPE_TEI" "$EXISTING_FILELIST" ; then # BEGIN UDPIPE2 CONDITION

mkdir -p $UDPIPE_TEI
log "annotating udpipe2 $UDPIPE_TEI"

perl -I lib udpipe2/udpipe2.pl --model=czech-pdt-ud-2.6-200830 \
                               --filelist $TEI_FILELIST \
                               --input-dir $DOWNLOADER_TEI_META \
                               --output-dir $UDPIPE_TEI

fi; # END UDPIPE CONDITION

if [ "$EXIT_CONDITION" == "udpipe" ] ; then
  echo "EXITTING: $EXIT_CONDITION"
  exit
fi

###############################
###     NameTag tei         ###
#  input:
#    udpipe-tei/$ID
#  output:
#    nametag-tei/$ID
###############################

export NAMETAG_TEI=$DATA_DIR/nametag-tei/${ID}

if skip_process "nametag2" "$NAMETAG_TEI" "$EXISTING_FILELIST" ; then # BEGIN NAMETAG CONDITION

mkdir -p $NAMETAG_TEI
log "annotating nametag2  $NAMETAG_TEI"

perl -I lib nametag2/nametag2.pl --conll2003 \
                                 --model=czech-cnec2.0-200831 \
                                 --filelist $TEI_FILELIST \
                                 --input-dir $UDPIPE_TEI \
                                 --output-dir $NAMETAG_TEI

fi; # END NAMETAG CONDITION

if [ "$EXIT_CONDITION" == "nametag" ] ; then
  echo "EXITTING: $EXIT_CONDITION"
  exit
fi

################################
### Metadata to annotated    ###
#  input:
#    nametag-tei/$ID
#  output:
#    annotated-tei-meta/$ID
###############################

export ANNOTATED_TEI_META=$DATA_DIR/annotated-tei-meta/${ID}
VAR_LOG_ANN="$ANNOTATED_TEI_META/variables.log"

if skip_process "metadater.ann" "$ANNOTATED_TEI_META" "$EXISTING_FILELIST" ; then # BEGIN METADATER.TEI.ann CONDITION

mkdir -p $ANNOTATED_TEI_META

echo "WARNING: metadata-name $METADATA_NAME.ann is temporary - in future change to ParCzech-live-2.0.ann"
log "adding metadata $METADATA_NAME.ann $ANNOTATED_TEI_META"
perl -I lib metadater/metadater.pl --metadata-name "$METADATA_NAME.ann" \
                                   --metadata-file metadater/tei_parczech.xml \
                                   --filelist $TEI_FILELIST \
                                   --input-dir $NAMETAG_TEI \
                                   --output-dir $ANNOTATED_TEI_META \
                                   --rename "\\.xml\$|.${INTERFIX}.xml" \
                                   --variables-log "$VAR_LOG_ANN"


fi; # END METADATER.TEI.ann CONDITION

#########################################
### Metadata to annotated teiCorpus   ###
#########################################

if skip_process_single_file "metadater.teiCorpus.ann" "$ANNOTATED_TEI_META/$ANATEICORPUS_FILENAME" ; then # BEGIN METADATER.teiCorpus.ann CONDITION

$XSL_TRANSFORM metadater/patch_include_suffix.xsl "$DOWNLOADER_TEI_META/$TEICORPUS_FILENAME" "$ANNOTATED_TEI_META/$ANATEICORPUS_FILENAME" remove=".xml" append=".$INTERFIX.xml"


## add metadata to teiCorpus
ANNCORPUS_VARS=`cat "$VAR_LOG_ANN"|sed -n 's/^AGGREGATED[|]//p'|tr "\n" "|"|sed 's/[|]$//'`

log "adding metadata to teiCorpus $METADATA_NAME.ann $ANNOTATED_TEI_META"
log "VARIABLES: $ANNCORPUS_VARS"

perl -I lib metadater/metadater.pl --metadata-name "$METADATA_NAME-corpus.ann" \
                                   --metadata-file metadater/tei_parczech.xml \
                                   --input-file "$ANNOTATED_TEI_META/$ANATEICORPUS_FILENAME"  \
                                   --output-file "$ANNOTATED_TEI_META/$ANATEICORPUS_FILENAME" \
                                   --variables "$ANNCORPUS_VARS"

fi; # END METADATER.teiCorpus.ann CONDITION

######################################################
### add number of words to downloader-tei-meta/*   ###
######################################################

for cnt_line in  `grep "|ELEMCNT:w=" "$VAR_LOG_ANN"`
do
  fullpath=${cnt_line%|*}
  if [ $fullpath == 'AGGREGATED' ] ; then
    FILENAME=$TEICORPUS_FILENAME
  else
    FILENAME=`echo "$fullpath"| sed "s/^.*$ID\///;s/$INTERFIX.xml$/xml/"`
  fi
  echo "patching: #words=${cnt_line##*|} $DOWNLOADER_TEI_META/$FILENAME"
  perl -I lib metadater/metadater.pl --metadata-name "ParCzech-extent.ann" \
                                   --metadata-file metadater/tei_parczech.xml \
                                   --input-file "$DOWNLOADER_TEI_META/$FILENAME"  \
                                   --output-file "$DOWNLOADER_TEI_META/$FILENAME" \
                                   --variables "${cnt_line##*|}"
done


if [ "$EXIT_CONDITION" == "ann-meta" ] ; then
  echo "EXITTING: $EXIT_CONDITION"
  exit
fi

###############################
###     FINALIZE            ###
### converting to teitok    ###
#  input:
#    annotated-tei-meta/$ID
#
#
###############################

export TEITOK_TEI=$DATA_DIR/teitok-tei/${ID}

if skip_process "tei2teitok" "$TEITOK_TEI" "$EXISTING_FILELIST" ; then # BEGIN tei2teitok CONDITION

mkdir -p $TEITOK_TEI
log "converting to teitok $TEITOK_TEI"

echo "./tei2teitok/teiCorpus2teitok.sh  -C \"$ANNOTATED_TEI_META/$TEICORPUS_FILENAME\" -O \"$TEITOK_TEI\" -c " `realpath $CONFIG_FILE`
./tei2teitok/teiCorpus2teitok.sh  -C "$ANNOTATED_TEI_META/$ANATEICORPUS_FILENAME" -O "$TEITOK_TEI" -c `realpath $CONFIG_FILE`

fi; # END tei2teitok CONDITION

if [ "$EXIT_CONDITION" == "teitok" ] ; then
  echo "EXITTING: $EXIT_CONDITION"
  exit
fi

###############################
log_process "tei publishing"
log "publishing in TEITOK $ID (${TEITOK_CORPUS##*/})"

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