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

function patch_invalid_characters {
  if [ ! -s  "$1" ]; then
    log "file does not exists or is empty: $1"
    return 0;
  fi
  # \x{200B} = [ZERO WIDTH SPACE]
  # \x{202F} = [NARROW NO-BREAK SPACE]
  # \x{00A0} = [NO-BREAK SPACE]
  # \x{00AD} = [SOFT HYPHEN]
  perl -CSD -pi -e '$_ =~ tr/\x{200B}\x{00AD}//d;$_ =~ tr/\x{202F}\x{00A0}/  /;' $1
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

# backup downloader database file
cp "$CL_WORKDIR/${CL_SCRIPT%.pl}.sq3" "$CL_WORKDIR/${CL_SCRIPT%.pl}.$ID.sq3"

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
find "$DOWNLOADER_TEI" -type f -name '*.xml' | while read FILE ; do patch_invalid_characters "$FILE" ; done

### cache to html
log "backup html $CL_OUTDIR_HTML/$ID"
./cache_to_dir_tree.sh -c $CL_OUTDIR_CACHE/$ID -o $CL_OUTDIR_HTML/$ID

fi; # END DOWNLOADER CONDITION

if [ "$EXIT_CONDITION" == "steno" ] ; then
  echo "EXITTING: $EXIT_CONDITION"
  exit
fi

################################
### audio files              ###
#  input:
#    downloader-tei/$ID
#
#  output:
#    audio/$ID.audio_urls.sh  # runnable list of audio links
###############################
export AUDIO_DIR=$DATA_DIR/audio
export AUDIO_URL_LIST=$AUDIO_DIR/${ID}.audio_urls.sh

mkdir -p $AUDIO_DIR

if skip_process_single_file "audio-links" "$AUDIO_URL_LIST" ; then # BEGIN AUDIO-LINKS CONDITION


$XSL_TRANSFORM audio/get-audiolinks.xsl "$DOWNLOADER_TEI/$TEICORPUS_FILENAME" "$AUDIO_URL_LIST" data-path="$DOWNLOADER_TEI"

fi; # END AUDIO-LINKS CONDITION

if [ "$EXIT_CONDITION" == "audio-links" ] ; then
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

perl -I downloader/lib -I lib -I ${SHARED}/lib downloader/$GOV_SCRIPT --db $GOV_OUTDIR_DB --cache $GOV_OUTDIR_CACHE --person-list $PERSON_LIST_PATH --id $ID --debug 10

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
#    psp-db/$ID/all-term-person-corresp.xml
#    psp-db/$ID/org.xml (enriched)
#    psp-db/$ID (tei files with consolidated person ids)
###############################

export PSP_DB_DIR=$DATA_DIR/psp-db/${ID}
export PSP_DB_FILE=$PSP_DB_DIR/psp.db
export PSP_DB_TEI=$PSP_DB_DIR
export PSP_DB_ALL_TERM_PERSON=$PSP_DB_DIR/all-term-person-corresp.xml

if skip_process_single_file "psp-db" "$PSP_DB_DIR/person.xml" ; then # BEGIN PSP-DB download CONDITION
mkdir -p $PSP_DB_DIR

log "getting person and org info $PSP_DB_DIR"
TERM_LIST=`$XPATH_QUERY "$DOWNLOADER_TEI/$TEICORPUS_FILENAME" "declare option saxon:output 'omit-xml-declaration=yes'; string-join( for \\$i in //*[local-name() = 'meeting' and contains(@ana,'#parla.term')]/@n return substring-after(\\$i,'ps'),',')"`
echo "TERM_LIST='$TERM_LIST'"

./psp-db/pspdb.sh -p "$PERSON_LIST_PATH"\
                  -o "$PSP_DB_DIR" \
                  -g "$GOV_OUTDIR_DB/$ID" \
                  -t "$TERM_LIST" \
                  -a "$PSP_DB_ALL_TERM_PERSON" \
                  -c `realpath $CONFIG_FILE`


log "travers person - looking for duplicit persons"
echo ./psp-db/travers_person.sh -p "$PSP_DB_DIR/person.xml" -i "$DOWNLOADER_TEI" -f "$TEI_FILELIST" -o "$PSP_DB_TEI" -c `realpath $CONFIG_FILE`
./psp-db/travers_person.sh -p "$PSP_DB_DIR/person.xml" -i "$DOWNLOADER_TEI" -f "$TEI_FILELIST" -o "$PSP_DB_TEI" -c `realpath $CONFIG_FILE`

## merge orgs with common roles to list of events (done inprevious step)
##$XSL_TRANSFORM psp-db/org_merger.xsl "$PSP_DB_DIR/org.xml" "$PSP_DB_DIR/org.merged.xml" roles="senate|parliament|government"

### set parliament org to parla.term

TERM_TO_PSP=`$XPATH_QUERY "$PSP_DB_DIR/org.xml" "declare option saxon:output 'omit-xml-declaration=yes'; concat(string-join( for \\$i in //*[local-name() = 'org' and @role='parliament']/*[local-name() = 'listEvent']/*[local-name() = 'event'] return concat(concat('ps',substring-before(\\$i/@from, '-')),'=#',\\$i/@xml:id),' '),' ')"`
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
### Annotate incidents       ###
#  input:
#    psp-db/$ID
#    psp-db/$ID/person.xml ???
#  output:
#    incidents-tei/$ID
###############################

export INCIDENTS_TEI=$DATA_DIR/incidents-tei/${ID}


if skip_process "incidents" "$INCIDENTS_TEI" "$EXISTING_FILELIST" ; then # BEGIN INCIDENTS CONDITION

perl -I lib incidents/incidents.pl \
                                   --filelist $TEI_FILELIST \
                                   --input-dir $PSP_DB_TEI \
                                   --output-dir $INCIDENTS_TEI

fi # END INCIDENTS CONDITION

if [ "$EXIT_CONDITION" == "incidents" ] ; then
  echo "EXITTING: $EXIT_CONDITION"
  exit
fi

#################################
### Metadata to incidents-tei ###
#  input:
#    incidents-tei/$ID
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
                                   --input-dir $INCIDENTS_TEI \
                                   --output-dir $DOWNLOADER_TEI_META \
                                   --variables-log "$VAR_LOG" \

fi; # END METADATER CONDITION

###############################
### Metadata to teiCorpus   ###
###############################

if skip_process_single_file "metadater" "$DOWNLOADER_TEI_META/$TEICORPUS_FILENAME" ; then # BEGIN METADATER teiCorpus CONDITION

log "adding <listPerson> teiCorpus: $DOWNLOADER_TEI_META/pers.$TEICORPUS_FILENAME"

## add all term persons
$XSL_TRANSFORM metadater/add_allterm_persons.xsl "$PSP_DB_DIR/$TEICORPUS_FILENAME" "$DOWNLOADER_TEI_META/allpers.$TEICORPUS_FILENAME" allterm-personlist-path="$PSP_DB_ALL_TERM_PERSON"

## merge personlist
$XSL_TRANSFORM metadater/knit_persons.xsl "$DOWNLOADER_TEI_META/allpers.$TEICORPUS_FILENAME" "$DOWNLOADER_TEI_META/pers.$TEICORPUS_FILENAME" personlist-path="$PSP_DB_DIR/person.xml"

log "adding <listOrg> teiCorpus: $DOWNLOADER_TEI_META/org.$TEICORPUS_FILENAME"

## add org
$XSL_TRANSFORM metadater/add_org.xsl "$DOWNLOADER_TEI_META/pers.$TEICORPUS_FILENAME" "$DOWNLOADER_TEI_META/org.$TEICORPUS_FILENAME" org-path="$PSP_DB_DIR/org.xml"

## fix affiliation (when affiliated to event) #event->@ana, #org->@ref
$XSL_TRANSFORM metadater/affiliations_fix.xsl "$DOWNLOADER_TEI_META/org.$TEICORPUS_FILENAME" "$DOWNLOADER_TEI_META/aff_fix.$TEICORPUS_FILENAME"

## sort header data in teiCorpus
$XSL_TRANSFORM metadater/header_data_sorter.xsl "$DOWNLOADER_TEI_META/aff_fix.$TEICORPUS_FILENAME" "$DOWNLOADER_TEI_META/sorted.$TEICORPUS_FILENAME"


## add metadata to teiCorpus
CORPUS_VARS=`cat "$VAR_LOG"|sed -n 's/^AGGREGATED[|]//p'|tr "\n" "|"|sed 's/[|]$//'`

log "adding metadata to teiCorpus $METADATA_NAME-corpus: $DOWNLOADER_TEI_META/$TEICORPUS_FILENAME"
log "VARIABLES: $CORPUS_VARS"

perl -I lib metadater/metadater.pl --metadata-name "$METADATA_NAME-corpus" \
                                   --metadata-file metadater/tei_parczech.xml \
                                   --input-file "$DOWNLOADER_TEI_META/sorted.$TEICORPUS_FILENAME"  \
                                   --output-file "$DOWNLOADER_TEI_META/$TEICORPUS_FILENAME" \
                                   --variables "$CORPUS_VARS"
patch_invalid_characters "$DOWNLOADER_TEI_META/$TEICORPUS_FILENAME"



fi; # END METADATER teiCorpus CONDITION

if [ "$EXIT_CONDITION" == "tei-meta" ] ; then
  echo "EXITTING: $EXIT_CONDITION"
  exit
fi


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

perl -I lib udpipe2/udpipe2.pl --colon2underscore \
                               --lindat-token "$LINDAT_TOKEN" \
                               --model=czech-pdt-ud-2.10-220711 \
                               --filelist $TEI_FILELIST \
                               --input-dir $DOWNLOADER_TEI_META \
                               --output-dir $UDPIPE_TEI

fi; # END UDPIPE CONDITION

if [ "$EXIT_CONDITION" == "udpipe" ] ; then
  echo "EXITTING: $EXIT_CONDITION"
  exit
fi

################################
### audio vertical           ###
#  input:
#    udpipe-tei/$ID
#
#  output:
#    audio-vert-in/$ID            # verticals from tokenized tei files
#    audio-vert-in/$ID/vertical.fl
###############################
export AUDIO_VERT_DIR=$DATA_DIR/audio-vert-in/${ID}
export AUDIO_VERT_LIST=$AUDIO_VERT_DIR/vertical.fl
export AUDIO_VERT_SPEAKERS=$AUDIO_VERT_DIR/speakers.tsv

mkdir -p $AUDIO_VERT_DIR

if skip_process_single_file "audio-vert" "$AUDIO_VERT_LIST" ; then # BEGIN AUDIO-VERT-IN CONDITION

$XSL_TRANSFORM audio/persons_tsv.xsl "$DOWNLOADER_TEI_META/$TEICORPUS_FILENAME" "$AUDIO_VERT_SPEAKERS"

for FILE in `cat $TEI_FILELIST`;
do
  OUTFILE="$AUDIO_VERT_DIR/${FILE%.*}.vert"
  mkdir -p "${OUTFILE%/*}"
  echo "${FILE%.*}.vert" >> $AUDIO_VERT_LIST
  $XSL_TRANSFORM audio/token_ids.xsl "$UDPIPE_TEI/$FILE" "$OUTFILE"
done

fi; # END AUDIO-VERT-IN CONDITION

if [ "$EXIT_CONDITION" == "audio-vert-in" ] ; then
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
                                 --varied-tei-elements \
                                 --use-xpos \
                                 --lindat-token "$LINDAT_TOKEN" \
                                 --model=czech-cnec2.0-200831 \
                                 --filelist $TEI_FILELIST \
                                 --input-dir $UDPIPE_TEI \
                                 --output-dir $NAMETAG_TEI

fi; # END NAMETAG CONDITION

if [ "$EXIT_CONDITION" == "nametag" ] ; then
  echo "EXITTING: $EXIT_CONDITION"
  exit
fi

######################################
###     Audio Timeline tei         ###
#  input:
#    nametag-tei/$ID
#  output:
#    audio-tei/$ID
######################################

export AUDIO_TEI=$DATA_DIR/audio-tei/${ID}
export AUDIO_VERT_OUTDIR=$DATA_DIR/audio-vert-out/${ID}

if skip_process "audio-timeline" "$AUDIO_TEI" "$EXISTING_FILELIST" ; then # BEGIN AUDIO TIMELINE CONDITION

mkdir -p $AUDIO_TEI
log "adding audio timeline  $AUDIO_TEI"

if [ -s  "$AUDIO_VERT_OUTDIR/outliers_continuous_gaps_cnt_normalized1.txt" ]; then
  log "adding outliers_continuous_gaps to audio stats from $AUDIO_VERT_OUTDIR/outliers_continuous_gaps_cnt_normalized1.txt"
  if ls $AUDIO_VERT_OUTDIR/stats_*.tsv.bak 1> /dev/null 2>&1; then
    log ".bak file exists - skipping patching"
  else
    sed -i'.bak' '1s/$/\toutliers_continuous_gaps/;2s/$/\t0/' $AUDIO_VERT_OUTDIR/stats_*.tsv
    for PAGEFILE in `sed 's/^.*sentences_//;s/\/.*$//' "$AUDIO_VERT_OUTDIR/outliers_continuous_gaps_cnt_normalized1.txt"`;
    do
      sed -i '2s/\t0$/\t1/' $AUDIO_VERT_OUTDIR/stats_$PAGEFILE.tsv
    done
  fi
fi

perl -I lib audio/audio-timeline.pl --sync-dir $AUDIO_VERT_OUTDIR \
                                    --filelist $TEI_FILELIST \
                                    --input-dir $NAMETAG_TEI \
                                    --output-dir $AUDIO_TEI

fi; # END AUDIO TIMELINE CONDITION

if [ "$EXIT_CONDITION" == "audio-timeline" ] ; then
  echo "EXITTING: $EXIT_CONDITION"
  exit
fi

################################
### Metadata to annotated    ###
#  input:
#    audio-tei/$ID
#  output:
#    annotated-tei-meta/$ID
###############################

export ANNOTATED_TEI_META=$DATA_DIR/parczech.tei.ana/${ID}
VAR_LOG_ANN="$DATA_DIR/parczech.tei.ana/variables.${ID}.log"
RENAME_TEMPLATE="\\.xml\$|.${INTERFIX}.xml"

if [ -f "$EXISTING_FILELIST" ]; then
  cat "$EXISTING_FILELIST"|sed "s|$RENAME_TEMPLATE|" > "$EXISTING_FILELIST.ana"
  EXISTING_FILELIST_ANA="$EXISTING_FILELIST.ana"
fi

if skip_process "metadater.ann" "$ANNOTATED_TEI_META" "$EXISTING_FILELIST_ANA" ; then # BEGIN METADATER.TEI.ann CONDITION

log "adding metadata and renaming TEI files:  $ANNOTATED_TEI_META"

mkdir -p $ANNOTATED_TEI_META

echo "WARNING: metadata-name $METADATA_NAME.ann is temporary - in future change to ParCzech-live-2.0.ann"
log "adding metadata $METADATA_NAME.ann $ANNOTATED_TEI_META"
perl -I lib metadater/metadater.pl --metadata-name "$METADATA_NAME.ann" \
                                   --metadata-file metadater/tei_parczech.xml \
                                   --filelist $TEI_FILELIST \
                                   --input-dir $AUDIO_TEI \
                                   --output-dir $ANNOTATED_TEI_META \
                                   --rename "$RENAME_TEMPLATE" \
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

export PARCZECH_TEI_RAW=$DATA_DIR/parczech.tei.raw/${ID}

if skip_process_single_file "parczech.tei.raw" "$PARCZECH_TEI_RAW/$TEICORPUS_FILENAME" ; then # BEGIN PARCZECH.TEI.raw CONDITION

mkdir -p $PARCZECH_TEI_RAW

# copy data
cp "$DOWNLOADER_TEI_META/$TEICORPUS_FILENAME" "$PARCZECH_TEI_RAW/$TEICORPUS_FILENAME"

cat $TEI_FILELIST | while read F
do
  mkdir -p "$PARCZECH_TEI_RAW/${F%%/*}"
  cp "$DOWNLOADER_TEI_META/$F" "$PARCZECH_TEI_RAW/$F"
done



# patch # of words
grep "XPATH:count.*w.*:XPATH" "$VAR_LOG_ANN"| while read cnt_line
do
  fullpath=${cnt_line%|*}
  if [ $fullpath == 'AGGREGATED' ] ; then
    FILENAME=$TEICORPUS_FILENAME
  else
    FILENAME=`echo "$fullpath"| sed "s/^.*$ID\///;s/$INTERFIX.xml$/xml/"`
  fi
  echo "patching: #words=${cnt_line##*|} $PARCZECH_TEI_RAW/$FILENAME"
  perl -I lib metadater/metadater.pl --metadata-name "ParCzech-extent.ann" \
                                   --metadata-file metadater/tei_parczech.xml \
                                   --input-file "$PARCZECH_TEI_RAW/$FILENAME"  \
                                   --output-file "$PARCZECH_TEI_RAW/$FILENAME" \
                                   --variables "${cnt_line##*|}"
done

fi;

if [ "$EXIT_CONDITION" == "ann-meta" ] ; then
  echo "EXITTING: $EXIT_CONDITION"
  exit
fi

#####################################
###     CONSOLIDATE               ###
### merging new data to corpus    ###
#  input:
#    parczech.tei.raw/$ID
#    parczech.tei.ana/$ID
#  output:
#    parczech.tei.raw/consolidated
#    parczech.tei.ana/consolidated
#
#####################################
CONSOLIDATED_FOLDER=consolidated
export PARCZECH_TEI_RAW_CONS=$DATA_DIR/parczech.tei.raw/${CONSOLIDATED_FOLDER}
export PARCZECH_TEI_ANA_CONS=$DATA_DIR/parczech.tei.ana/${CONSOLIDATED_FOLDER}

function consolidate() {
  echo -en "TODO CONSOLIDATE \n\t$1 \n\t$2 \n\t$3 \n\t$4\n"
  # test if exist consolidated data
  find $2
  echo
  if skip_process_single_file "new_data $3" "$2/${4}.xml" ; then

    echo "Copy all data to $2"
    cp -r $1 $2
    mv "$2/$3" "$2/${4}.xml"
    xmlstarlet edit --inplace \
                    --update "/_:teiCorpus/@xml:id" \
                    --value "${4}" \
                    "$2/${4}.xml"
  else
    echo "Consolidating new data $1 to $2"
    rsync -a --backup --suffix=".${ID}" --exclude "$3"  "$1/" "$2"
    mv "$2/${4}.xml" "$2/${4}.xml.${ID}"
    perl -I lib lib/ParCzech/XMLmerge.pm  "$2/${4}.xml.${ID}" "$1/$3" "$2/${4}.xml"
  fi
}

consolidate $PARCZECH_TEI_RAW $PARCZECH_TEI_RAW_CONS $TEICORPUS_FILENAME ParCzech
consolidate $ANNOTATED_TEI_META $PARCZECH_TEI_ANA_CONS $ANATEICORPUS_FILENAME ParCzech.ana

if [ "$EXIT_CONDITION" == "consolidate" ] ; then
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






### TODO FIX THIS:





export TEITOK_TEI=$DATA_DIR/parczech.tt/${ID}

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