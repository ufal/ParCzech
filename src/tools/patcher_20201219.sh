#!/bin/bash

# https://github.com/ufal/ParCzech/issues/50
# wrong agenda item number in //meeting[@ana="#parla.agenda"]
#

CORPUSDIR=$1


for FILE in `find $CORPUSDIR -type f -name "ps20*"`
do
  ID=`head -n 5 $FILE |grep '<TEI '|grep -o "ps20..-...-..-...-..."`
  OLD=`echo -n $ID | sed 's@^\(ps20..\)-\(...\)-..-\(...\)-...$@\1/\2/\3@'`
  NEW=`echo -n $ID | sed 's@^\(ps20..\)-\(...\)-..-...-\(...\)$@\1/\2/\3@'`
  echo "PATCHING: $ID $OLD -> $NEW | $FILE"
  sed -i "1,30s@$OLD@$NEW@g" $FILE
done