#!/bin/bash


PWD=`pwd`
D=`dirname $0`

usage() {
  echo -e "Usage: $0 -p PERSONLIST_FILE -i INPUT_DIRECTORY -o OUTPUT_DIRECTORY -f FILELIST" 1>&2
  exit 1
}


while getopts  ':p:i:o:f:c:'  opt; do
  case "$opt" in
    'p')
      PERSONLIST=$OPTARG
      ;;
    'i')
      INPUT_DIRECTORY=$OPTARG
      ;;
    'o')
      OUTPUT_DIRECTORY=$OPTARG
      ;;
    'f')
      FILELIST=$OPTARG
      ;;
    'c')
      CONFIG_FILE=$OPTARG
      ;;
    *)
      usage
  esac
done

set -o allexport
if [ -f "$CONFIG_FILE" ]; then
  echo "loading config $CONFIG_FILE"
  source "$CONFIG_FILE"
fi
set +o allexport

if [ -z "$OUTPUT_DIRECTORY" ] || [ -z "$PERSONLIST" ] || [ -z "$INPUT_DIRECTORY" ] || [ -z "$FILELIST" ] ; then
  usage
fi

[ -d $OUTPUT_DIRECTORY ] || mkdir -p $OUTPUT_DIRECTORY;


TRANSLATE=`$XPATH_QUERY "$PERSONLIST" "declare option saxon:output 'omit-xml-declaration=yes';string-join( for \\$i in //*[local-name() = 'person' and @corresp] return concat(\\$i/@xml:id,'=',substring-after(\\$i/@corresp, '#')),'&#10;') "`

echo "$TRANSLATE"
SCRIPT=''
if [ ! -z "$TRANSLATE" ] ; then
  SCRIPT=" my \$l=\$_;
    my @tr = map { [split('=',\$_)]} qw/$TRANSLATE/;
    for my \$i (@tr){
      my (\$s,\$t) = @\$i;
      print STDERR '.' if \$l =~ s/\\Q#\$s\\E/\$t/g;
    };
    \$_ = \$l;
  "
fi
for TEIFILE in `cat "$FILELIST"` ; do
    mkdir -p "$OUTPUT_DIRECTORY/${TEIFILE%/*}"
  if [ ! -z "$SCRIPT" ] ; then
    echo "transform: $TEIFILE"
    cat "$INPUT_DIRECTORY/$TEIFILE" | perl -pe "$SCRIPT" > $OUTPUT_DIRECTORY/$TEIFILE
  else
    echo "copy: $TEIFILE"
    cp "$INPUT_DIRECTORY/$TEIFILE" "$OUTPUT_DIRECTORY/$TEIFILE"
  fi
done
