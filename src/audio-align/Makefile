
bin=~/scripts
RESOURCES=asr/resources

DATE=
PWD=$(shell pwd)
DATADIR=$(PWD)/data/
PYTHON-ENV=./virtualenv/ParCzech

AUDIO=$(DATADIR)/audio/
TOKENS=$(DATADIR)/audio-corresp-tsv-in/

WORKING-DIR=$(DATADIR)/audio-working

WORKING-DIR-ASR=$(WORKING-DIR)/asr/$(FILE)
ASR-DIR=$(DATADIR)/audio-asr

WORKING-DIR-ALIGN-SEQ=$(WORKING-DIR)/align-seq/$(FILE)
ALIGN-SEQ-DIR=$(DATADIR)/audio-align-seq

ALIGN-TOKEN-DIR=$(DATADIR)/audio-align-token
STENO-CONTEXT-DIR=$(DATADIR)/audio-steno-context

YEAR=$(shell echo -n "$(DATE)" | sed -nE "s/^([0-9]{4}).*$$/\1/p")
MONTH=$(shell echo -n "$(DATE)" | sed -nE "s/^[0-9]{4}-?([0-9]{2}).*$$/\1/p")
DAY=$(shell echo -n "$(DATE)" | sed -nE "s/^[0-9]{4}-?[0-9]{2}-?([0-9]{2}).*$$/\1/p")

AUDIO-DIR=$(shell echo $(AUDIO)/www.psp.cz/eknih/*/audio/$(YEAR)/$(MONTH)/$(DAY)/)
TOKENS-DIR=$(shell echo $(TOKENS)/www.psp.cz/eknih/*/audio/$(YEAR)/$(MONTH)/$(DAY)/)

YY=$(shell ls data/audio/www.psp.cz/eknih/*/audio/|sed 's/.*://'|xargs|)

SBATCHDIR=$(DATADIR)/../sbatch
SBATCHLOGS=$(DATADIR)/../logs
SBATCH=$(SBATCHDIR)/$(YEAR)$(MONTH)asr.sh

ASR-SPLIT-NEG-SHIFT=0

PREFIX=$(FILE)
PREV-FILE=$(shell ls $(TOKENS-DIR)|sort -r|sed -n '/$(FILE)/,$$p'|sed -n 2p|sed 's/\..*//')
NEXT-FILE=$(shell ls $(TOKENS-DIR)|sort   |sed -n '/$(FILE)/,$$p'|sed -n 2p|sed 's/\..*//')
CONTEXT-SIZE=100

.PHONY:

all:
	echo "'$(YY)'"




#(1)################  ASR

## prepare batch
asr-month-prepare-sbatch-jobs:
	@echo "$@: $(DATE)"
	echo $(AUDIO)/www.psp.cz/eknih/*/audio/*|${getdir}| xargs -I {} make --no-print-directory asr-month-prepare-sbatch-jobs-{} DATE={}
asr-month-prepare-sbatch-jobs-$(YEAR):
	@echo "$@: $(DATE)"
	@echo $(AUDIO)/www.psp.cz/eknih/*/audio/$(YEAR)/*|${getdir}| xargs -I {} make --no-print-directory asr-month-prepare-sbatch-jobs-$(YEAR)-{} DATE=$(YEAR)-{}
asr-month-prepare-sbatch-jobs-$(YEAR)-$(MONTH):
	@echo "$@: $(DATE)"
	@mkdir -p $(SBATCHDIR) $(SBATCHLOGS)
	@echo "#!/bin/bash" > $(SBATCH)
	@echo "#SBATCH -D $(PWD)/ # change directory before executing the job" >> $(SBATCH)
	@echo "#SBATCH -o $(SBATCHLOGS)/%x.%j.out" >> $(SBATCH)
	@echo "#SBATCH -e $(SBATCHLOGS)/%x.%j.err" >> $(SBATCH)
	@echo "#SBATCH -N 1                                  # number of nodes (default 1)" >> $(SBATCH)
	@echo "#SBATCH --cpus-per-task=15                     # number of cores/threads per task (default 1)" >> $(SBATCH)
	@echo "#SBATCH --gres=gpu:0                          # number of GPUs to request (default 0)" >> $(SBATCH)
	@echo "#SBATCH --mem=30G                             # request 10 gigabytes memory (per node, default depends on node)" >> $(SBATCH)
	#@echo "#SBATCH --mail-type=begin        # send email when job begins" >> $(SBATCH)
	#@echo "#SBATCH --mail-type=end          # send email when job ends" >> $(SBATCH)
	@echo "#SBATCH --mail-type=fail         # send email if job fails" >> $(SBATCH)
	@echo "#SBATCH --mail-user=kopp@ufal.mff.cuni.cz" >> $(SBATCH)
	@echo "" >> $(SBATCH)
	@echo "make asr-dir-$(YEAR)-$(MONTH) DATE=$(YEAR)-$(MONTH) DATADIR=$(DATADIR)/ RESOURCES=$(RESOURCES)" >> $(SBATCH)
	@echo "INFO: sbatch script created: $(SBATCH)"



## run asr

# process all directories
asr-dir:
	@echo "$@: $(DATE)"
	echo $(AUDIO)/www.psp.cz/eknih/*/audio/*|${getdir}| xargs -I {} make --no-print-directory asr-dir-{} DATE={}

# process year directory
asr-dir-$(YEAR):
	@echo "$@: $(DATE)"
	@echo $(AUDIO)/www.psp.cz/eknih/*/audio/$(YEAR)/*|${getdir}| xargs -I {} make --no-print-directory asr-dir-$(YEAR)-{} DATE=$(YEAR)-{}


# process month directory
asr-dir-$(YEAR)-$(MONTH):
	@echo "$@: $(DATE)"
	@echo $(AUDIO)/www.psp.cz/eknih/*/audio/$(YEAR)/$(MONTH)/*|${getdir}| xargs -I {} make --no-print-directory asr-dir-$(YEAR)-$(MONTH)-{} DATE=$(YEAR)-$(MONTH)-{}

# process day directory
asr-dir-$(YEAR)-$(MONTH)-$(DAY): test-audio-dir
	@echo "$@: $(DATE)"
	@ls $(AUDIO-DIR) | sed 's@\.mp3@@' | xargs -I {} make --no-print-directory asr-file-$(YEAR)-$(MONTH)-$(DAY) FILE={} DATE=$(DATE)

asr-file-$(YEAR)-$(MONTH)-$(DAY): create-working-dir-asr-$(FILE) $(ASR-DIR) # asr/julius asr/HCopy
	@echo "INFO: make $@ DATE=$(DATE) FILE=$(FILE)"
	@test -f  $(ASR-DIR)/$(FILE).recout.FAILED && mv $(ASR-DIR)/$(FILE).recout.FAILED $(ASR-DIR)/$(FILE).recout.FAILED.`date -Idate`
	./asr/get-aligned-transcript.sh $(RESOURCES) $(WORKING-DIR-ASR) $(AUDIO-DIR)/$(FILE).mp3 $(ASR-SPLIT-NEG-SHIFT) > $(ASR-DIR)/$(FILE).recout \
	  || ( echo "ERROR: FATAL make $@ DATE=$(DATE) FILE=$(FILE)" && mv $(ASR-DIR)/$(FILE).recout $(ASR-DIR)/$(FILE).recout.FAILED )
	@echo "INFO: " `cat $(ASR-DIR)/$(FILE).recout* |wc -l ` "tokens recognized in $(AUDIO-DIR)/$(FILE).mp3"

#(2)################  align ASR output with sequence of words

align-seq-dir:
	@echo "$@: $(DATE)"
	@echo $(TOKENS)/www.psp.cz/eknih/*/audio/*|${getdir}| xargs -I {} make --no-print-directory align-seq-dir-{} DATE={}

align-seq-dir-$(YEAR):
	@echo "$@: $(DATE)"
	@echo $(TOKENS)/www.psp.cz/eknih/*/audio/$(YEAR)/*|${getdir}| xargs -I {} make --no-print-directory align-seq-dir-$(YEAR)-{} DATE=$(YEAR)-{}

align-seq-dir-$(YEAR)-$(MONTH):
	@echo "$@: $(DATE)"
	@echo $(TOKENS)/www.psp.cz/eknih/*/audio/$(YEAR)/$(MONTH)/*|${getdir}| xargs -I {} make --no-print-directory align-seq-dir-$(YEAR)-$(MONTH)-{} DATE=$(YEAR)-$(MONTH)-{}

align-seq-dir-$(YEAR)-$(MONTH)-$(DAY): test-tokens-dir
	@echo "$@: $(DATE)"
	ls $(TOKENS-DIR) |sed 's@\.tsv@@'| xargs -I {} make --no-print-directory align-seq-file-{} FILE={} DATE=$(YEAR)-$(MONTH)-$(DAY)

align-seq-file-$(FILE): add-context-to-steno-page-$(FILE) $(ALIGN-SEQ-DIR) $(PYTHON-ENV)/bin/activate
	@echo "$@: $(DATE)"
	@test -f $(ASR-DIR)/$(FILE).recout || echo "ERROR: file has not been recognized $(FILE) or does not have corresponding audio"
	@(test -f $(ASR-DIR)/$(FILE).recout \
		&& echo "running alignment $(FILE)" \
		&& . $(PYTHON-ENV)/bin/activate \
		&& cut -f 1 $(STENO-CONTEXT-DIR)/$(FILE).steno.tsv > $(WORKING-DIR-ALIGN-SEQ)/steno-cut \
		&& bash align-seq/strip-timestamps.sh < "$(ASR-DIR)/$(FILE).recout" > "$(WORKING-DIR-ALIGN-SEQ)/recout-stripped" \
		&& perl -Ilib align-seq/clean-extracted.pl < "$(WORKING-DIR-ALIGN-SEQ)/steno-cut" > "$(WORKING-DIR-ALIGN-SEQ)/steno-cleaned" \
		&& python align-seq/match-lines.py "$(WORKING-DIR-ALIGN-SEQ)/recout-stripped" "$(WORKING-DIR-ALIGN-SEQ)/steno-cleaned" "$(WORKING-DIR-ALIGN-SEQ)/steno-disambiguated" > "$(WORKING-DIR-ALIGN-SEQ)/matched" \
		&& python align-seq/assign-timestamps.py "$(WORKING-DIR-ALIGN-SEQ)/steno-disambiguated" "$(ASR-DIR)/$(FILE).recout" < "$(WORKING-DIR-ALIGN-SEQ)/matched" > $(ALIGN-SEQ-DIR)/$(FILE).seq\
	 ) || (echo "ERROR: FATAL $@")
	@rm -r $(WORKING-DIR-ALIGN-SEQ)


add-context-to-steno-page-$(FILE): create-working-dir-align-seq-$(FILE)
	rm -f $(STENO-CONTEXT-DIR)/$(FILE).tsv
	@test -f $(TOKENS-DIR)/$(PREV-FILE).tsv \
	    && tail -n $(CONTEXT-SIZE) $(TOKENS-DIR)/$(PREV-FILE).tsv \
	      | sed -E 's/^([^\t]*\t)/\1CONTEXT_/' >> $(STENO-CONTEXT-DIR)/$(FILE).steno.tsv \
	    || :
	cat $(TOKENS-DIR)/$(FILE).tsv >> $(STENO-CONTEXT-DIR)/$(FILE).steno.tsv
	@test -f $(TOKENS-DIR)/$(NEXT-FILE).tsv \
	    && head -n $(CONTEXT-SIZE) $(TOKENS-DIR)/$(NEXT-FILE).tsv \
	      | sed -E 's/^([^\t]*\t)/\1CONTEXT_/'>> $(STENO-CONTEXT-DIR)/$(FILE).steno.tsv \
	    || :

#(3)################  token alignment

align-token-pref:
	ls $(ALIGN-SEQ-DIR)/$(PREFIX)*.seq | sed 's@^.*/@@;s@\.seq@@' | xargs -I {} make align-token-file-{} FILE={} DATE={}

align-token-file-$(FILE): $(ALIGN-TOKEN-DIR) $(PYTHON-ENV)/bin/activate
	@echo "$@: $(FILE)"
	. $(PYTHON-ENV)/bin/activate \
	&& cd align-token \
	&& python single_word_time_aligner.py \
	        --vertical $(STENO-CONTEXT-DIR)/$(FILE).steno.tsv \
	        --transcript $(ALIGN-SEQ-DIR)/$(FILE).seq \
	        --yaml_config config.yaml \
	        --output $(ALIGN-TOKEN-DIR)/$(FILE).tsv
	@echo "INFO: " \
	      `cut -f5 $(ALIGN-TOKEN-DIR)/$(FILE).tsv | grep -ci 'True' ` \
	      " out of " \
	      `cut -f4 $(ALIGN-TOKEN-DIR)/$(FILE).tsv | grep -vP '^(-|id|CONTEXT_.*)$$'|wc -l ` \
	      "tokens aligned in result $(ALIGN-TOKEN-DIR)/$(FILE).tsv"




#####################################################
$(ASR-DIR):
	mkdir -p  $(ASR-DIR)

$(ALIGN-SEQ-DIR):
	mkdir -p  $(ALIGN-SEQ-DIR)

$(ALIGN-TOKEN-DIR):
	mkdir -p  $(ALIGN-TOKEN-DIR)

create-working-dir-asr-$(FILE):
	mkdir -p $(WORKING-DIR-ASR)

create-working-dir-align-seq-$(FILE):
	mkdir -p $(WORKING-DIR-ALIGN-SEQ) $(STENO-CONTEXT-DIR)

test-audio-dir:
	@test -d $(AUDIO-DIR) || (echo "ERROR: wrong input audio directory $(AUDIO-DIR)" & exit 1)
	@echo "INFO: input audio directory $(AUDIO-DIR)"

test-tokens-dir:
	@test -d $(TOKENS-DIR) || (echo "ERROR: wrong input tokens directory $(TOKENS-DIR)" & exit 1)
	@echo "INFO: input tokens directory $(TOKENS-DIR)"


asr/julius:
	git clone -b 'v4.6' --single-branch --depth 1 https://github.com/julius-speech/julius.git
	cd julius && ./configure --enable-words-int && make -j4
	ln -s ../julius/julius/julius asr/julius

asr/HCopy: $(RESOURCES)/hmmmodel
	@test -d $(bin) || (echo "ERROR: wrong binary directory $(bin)" & exit 1)
	@test -f $(bin)/HCopy || (echo "ERROR: $(bin)/HCopy does not exists" & exit 1)
	@$(bin)/HCopy -V | grep -q HTK || (echo "ERROR: uneexpected binary $(bin)/HCopy" & exit 1)
	ln -s $(bin)/HCopy asr/HCopy

$(RESOURCES)/hmmmodel:
	@find $(RESOURCES)
	@echo "ERROR: resources are missing"
	exit 1


$(PYTHON-ENV)/bin/activate:
	@test -f $(PYTHON-ENV)/bin/activate || make setup-python-env
setup-python-env:
	mkdir -p `echo -n "$(PYTHON-ENV)"|sed 's#/$$##' |sed 's#[^/]*$$##'`
	python -m venv $(PYTHON-ENV)
	. $(PYTHON-ENV)/bin/activate \
	&& pip install wheel \
	&& pip install Levenshtein numpy unidecode num2words pyyaml pydub

getdir = tr " " "\n" | sed "s@.*/@@"
