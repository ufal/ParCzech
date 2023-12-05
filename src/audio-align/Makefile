
bin=~/scripts
RESOURCES=asr/resources

DATE=
DATADIR=$(shell pwd)/data/

AUDIO=$(DATADIR)/audio/
TOKENS=$(DATADIR)/audio-corresp-tsv-in/

WORKING-DIR=$(DATADIR)/audio-working
WORKING-DIR-ASR=$(WORKING-DIR)/asr/$(FILE)
ASR-DIR=$(DATADIR)/audio-asr
WORKING-DIR-ALIGN=$(WORKING-DIR)/align/$(FILE)

YEAR=$(shell echo -n "$(DATE)" | sed -nE "s/^([0-9]{4}).*$$/\1/p")
MONTH=$(shell echo -n "$(DATE)" | sed -nE "s/^[0-9]{4}-?([0-9]{2}).*$$/\1/p")
DAY=$(shell echo -n "$(DATE)" | sed -nE "s/^[0-9]{4}-?[0-9]{2}-?([0-9]{2})$$/\1/p")

AUDIO-DIR=$(shell echo $(AUDIO)/www.psp.cz/eknih/*/audio/$(YEAR)/$(MONTH)/$(DAY)/)
TOKENS-DIR=$(shell echo $(TOKENS)/www.psp.cz/eknih/*/audio/$(YEAR)/$(MONTH)/$(DAY)/)

YY=$(shell ls data/audio/www.psp.cz/eknih/*/audio/|sed 's/.*://'|xargs|)


all:
	echo "'$(YY)'"



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
	@rm -f $(ASR-DIR)/$(FILE).recout.FAILED
	./asr/get-aligned-transcript.sh $(RESOURCES) $(WORKING-DIR-ASR) $(AUDIO-DIR)/$(FILE).mp3 > $(ASR-DIR)/$(FILE).recout \
	  || ( echo "ERROR: FATAL make $@ DATE=$(DATE) FILE=$(FILE)" && mv $(ASR-DIR)/$(FILE).recout $(ASR-DIR)/$(FILE).recout.FAILED )
	@echo "INFO: " `cat $(ASR-DIR)/$(FILE).recout* |wc -l ` "tokens recognized in $(AUDIO-DIR)/$(FILE).mp3"



align-$(YEAR)-$(MONTH)-$(DAY): test-tokens-dir
	echo "TODO: add testing of existence asr"

$(ASR-DIR):
	mkdir -p  $(ASR-DIR)

create-working-dir-asr-$(FILE):
	mkdir -p $(WORKING-DIR-ASR)

create-working-dir-align-$(FILE):
	mkdir -p $(WORKING-DIR-ALIGN)

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


getdir = tr " " "\n" | sed "s@.*/@@"
