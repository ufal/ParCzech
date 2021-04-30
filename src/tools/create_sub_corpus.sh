#!/bin/bash

D=`dirname $0`

usage() {
  echo -e "Usage: " 1>&2
  exit 1
}


while getopts  ':c:'  opt; do #
  case "$opt" in
    'c')
      CONFIG=true
      ;;
    *)
      usage
  esac
done


# TODO - use this only for calling perl script TEI::ParlaClarin::filter::teiCorpus - for each term in list of teiCorpus files

shift $(( OPTIND - 1 ))

for corpus in "$@"; do
  template=`echo -n $corpus|sed -e 's/\(\.ana\.xml\|\.xml\)$/-%s\1/'`
  perl -I `realpath --relative-base="$D/.." "lib"` \
          `realpath --relative-base="$D/.." "lib/ParCzech/XMLfilter/teiCorpus.pm"`  "$corpus" "$template"
done