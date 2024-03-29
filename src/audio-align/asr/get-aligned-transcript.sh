#!/bin/bash

echo "INFO: command $0 $1 $2 $3 $4" >&2

scriptdir=`dirname "$0"`

: ${PROCESSOR_COUNT:=`nproc`}
: ${PART_LENGTH:=60}

resources="$1"
tempdir="$2"
inaudiofn="$3"
TIME_NEGATIVE_SHIFT="${4:-0}"

audiolen=`soxi -D "$inaudiofn"`
floorlen=${audiolen%.*}
start=0
end=$((PART_LENGTH - TIME_NEGATIVE_SHIFT))
while ((start < floorlen)); do
  if ((end >= floorlen)); then
      sox "$inaudiofn" "$tempdir/rec--from-$start--to-end.wav" remix - rate 16k trim $start
  else
      sox "$inaudiofn" "$tempdir/rec--from-$start--to-$end.wav" remix - rate 16k trim $start $PART_LENGTH
  fi
  start=$((end))
  end=$((start + PART_LENGTH))
done
i=0
for wavfn in "$tempdir"/rec--*; do
  echo " -> $wavfn " >&2

  partstem=`echo "$wavfn" | sed s/\.wav//`
  ${scriptdir}/HCopy -C "${resources}/htk-config-wav2mfcc-full" "$wavfn" "$partstem.mfcc"
  echo "$partstem.mfcc" > "$partstem.scp"

  ${scriptdir}/julius -h ${resources}/hmmmodel \
           -filelist "$partstem.scp" \
           -nlr ${resources}/tg.arpa \
           -nrl ${resources}/tgb.arpa \
           -v ${resources}/test.phon.dict \
           -hlist ${resources}/phones \
           -walign \
           -palign \
           -input mfcfile -fallback1pass \
           > "$partstem.julout" 2>"$partstem.stderr" &

  if ((++i % PROCESSOR_COUNT == 0)); then wait; fi
done
wait

if perl ${scriptdir}/julutil.pl aggregate-julout $PART_LENGTH "$tempdir"/*.julout ; then
  echo "INFO: removing working directory $tempdir" >&2
  rm -r "$tempdir"
else
  echo "WARN: removing working directory $tempdir" >&2
  rm -r "$tempdir"
  exit 1
fi