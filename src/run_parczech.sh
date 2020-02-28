#!/bin/bash
#set -e


function log {
  echo -e `date +"%Y-%m-%d %T"`"\t$1" >> parczech.log
}


D=`dirname $0`
cd $D

pid=$$

log "STARTED $pid"

if [ -f 'current_process' ]; then
  proc=`cat 'current_process'`
  log "another process is running: $proc"
  log "FINISHED $pid"
  exit 0;
fi


### Download stenoprotocols ###
echo "$pid steno_download" > 'current_process'
log "downloading"

export SCRAPPER_CACHE=1 # For development ONLY!
export SCRAPPER_FAST=1 # For development ONLY!
export CL_WORKDIR=$PWD/out/downloader
export CL_OUTDIR_YAML=$PWD/out/downloader-yaml
export CL_OUTDIR_TEI=$PWD/out/downloader-tei
export CL_SCRIPT=stenoprotokoly_2013ps-now.pl
mkdir -p $CL_WORKDIR
mkdir -p $CL_OUTDIR_YAML
mkdir -p $CL_OUTDIR_TEI

perl -I downloader/lib downloader/$CL_SCRIPT --tei $CL_OUTDIR_TEI --yaml $CL_OUTDIR_YAML





### Download audio ###
### Merge audio and enrich tei files ###
### Anotate tei ###
### remove overwriten tei from teitok ###
### upload (new and updated) tei files to teitok ###





### End of process ###
rm 'current_process'
log "FINISHED $pid"