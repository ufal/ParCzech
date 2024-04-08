JAVA-MEMORY =
JM := $(shell test -n "$(JAVA-MEMORY)" && echo -n "-Xmx$(JAVA-MEMORY)g")
JAVA-PATH=/usr/share/java/

PWD=$(shell pwd)
CORPUS-NAME=ParCzech4.0
DATA-RELEASE=$(PWD)/data/release/
DATA-RELEASE-COMPLETE=$(PWD)/data/release-$(CORPUS-NAME)/
DATA-TEITOK=$(PWD)/data/teitok/
DATA-TEITOK-PACKED=$(PWD)/data/$(CORPUS-NAME).teitok.tar.gz
SAMPLE-DATA-IN=$(PWD)/data/sample-in/
DATA-IN=$(SAMPLE-DATA-IN)
SAMPLE-DATA-SOURCE=parczech:/opt/data/data-ParlaMint3.1-FRESH/


AUDIO-DATA-PATH=.
AUDIO-DATA-SOURCE=$(AUDIO-DATA-PATH)/audio-data-source/
AUDIO-DATA-TO-RELEASE=$(AUDIO-DATA-PATH)/audio-data-to-release/
AUDIO-DATA-RELEASE=$(AUDIO-DATA-PATH)/audio-data-release/
AUDIO-DATA-VERSION=24.01
AUDIO-DATA-RELEASE-COMMON-PATH=audio/psp
AUDIO-DATA-RELEASE-HANDLE-ID=11234/1-5404
AUDIO-DATA-RELEASE-REPOSITORY-URL-PREF=https://lindat.mff.cuni.cz/repository/xmlui/bitstream/handle/$(AUDIO-DATA-RELEASE-HANDLE-ID)/
TSVaudioFile=$(AUDIO-DATA-RELEASE)/audioPSP-meta.audioFile.tsv
TSVquarterArchive=$(AUDIO-DATA-RELEASE)/audioPSP-meta.quarterArchive.tsv

PROFILE =
PROF := $(shell test -n "$(PROFILE)" && date "+%F%T" | tr -d ':-' | sed 's/^/-TP:profile./;s/$$/.html/' )
JOBS-CNT=1
JOB-N=1


release: get-lists-ParlaMint4.0
	mkdir -p $(DATA-RELEASE)/
	sed -i 's/xml:id="ParlaMint-CZ-/xml:id="ParCzech-/' $(DATA-IN)/ParlaMint-CZ-list*.xml
	$s -xsl:tools/ParCzech-finalize.xsl \
	    outDir=$(DATA-RELEASE)/ \
	    inListPerson=$(DATA-IN)/ParlaMint-CZ-listPerson.xml  \
	    inListOrg=$(DATA-IN)/ParlaMint-CZ-listOrg.xml \
	    inTaxonomiesDir=$(PWD)/metadater/taxonomies/ \
	    type=TEI.ana \
	    $(DATA-IN)/parczech.tei.ana/consolidated/ParCzech.ana.xml
	cp ./tei2teitok/pdt-fslib.xml $(DATA-RELEASE)/ParCzech.TEI.ana/
	$s -xsl:tools/ParCzech-finalize.xsl \
	    outDir=$(DATA-RELEASE)/ \
	    inListPerson=$(DATA-IN)/ParlaMint-CZ-listPerson.xml  \
	    inListOrg=$(DATA-IN)/ParlaMint-CZ-listOrg.xml \
	    inTaxonomiesDir=$(PWD)/metadater/taxonomies/ \
	    anaDir=$(DATA-RELEASE)/ParCzech.TEI.ana \
	    type=TEI \
	    $(DATA-IN)/parczech.tei.raw/consolidated/ParCzech.xml

get-lists-ParlaMint4.0: $(DATA-IN)/ParlaMint-CZ-listOrg.xml $(DATA-IN)/ParlaMint-CZ-listPerson.xml
	echo 'diff <(sort $(DATA-IN)/parczech.tei.ana/consolidated/ParCzech-listPerson.xml| grep -o "xml:id=\"[^\"]*"|sort ) <(sort $(DATA-IN)/ParlaMint-CZ-listPerson.xml | grep -o "xml:id=\"[^\"]*"|sort)'| bash || :
	echo 'diff <(sort $(DATA-IN)/parczech.tei.ana/consolidated/ParCzech-listOrg.xml| grep -o "xml:id=\"[^\"]*"|sort ) <(sort $(DATA-IN)/ParlaMint-CZ-listOrg.xml | grep -o "xml:id=\"[^\"]*"|sort)'| bash || :
$(DATA-IN)/ParlaMint-CZ-listOrg.xml:
	wget https://raw.githubusercontent.com/clarin-eric/ParlaMint/v4.0/Samples/ParlaMint-CZ/ParlaMint-CZ-listOrg.xml -O $(DATA-IN)/ParlaMint-CZ-listOrg.xml
$(DATA-IN)/ParlaMint-CZ-listPerson.xml:
	wget https://raw.githubusercontent.com/clarin-eric/ParlaMint/v4.0/Samples/ParlaMint-CZ/ParlaMint-CZ-listPerson.xml -O $(DATA-IN)/ParlaMint-CZ-listPerson.xml

release-pack: release-pack-schema release-pack-html release-pack-TEI release-pack-TEI.ana

release-pack-schema: $(DATA-RELEASE-COMPLETE)-is-empty
	tar -czf $(DATA-RELEASE-COMPLETE)/$(CORPUS-NAME).schema.tar.gz --mode='a+rwX' schema/*.rng
	#tar -tf $(DATA-RELEASE-COMPLETE)/$(CORPUS-NAME).schema.tar.gz|sort

release-pack-html:
	tar -czf $(DATA-RELEASE-COMPLETE)/$(CORPUS-NAME).html.tar.gz --mode='a+rwX' --dereference --directory=$(DATA-RELEASE) ParCzech.html
release-pack-TEI release-pack-TEI.ana: release-pack-TEI%:
	tar -czf $(DATA-RELEASE-COMPLETE)/$(CORPUS-NAME).TEI$*.tar.gz --mode='a+rwX' --directory=$(DATA-RELEASE) ParCzech.TEI$*
	#tar -tf $(DATA-RELEASE-COMPLETE)/$(CORPUS-NAME).TEI$*.tar.gz|sort



$(DATA-RELEASE-COMPLETE):
	mkdir -p $(DATA-RELEASE-COMPLETE) || :
$(DATA-RELEASE-COMPLETE)-is-empty: $(DATA-RELEASE-COMPLETE)
	test -z "$$(ls -A $(DATA-RELEASE-COMPLETE))" || exit 1

validate-release-parlaclarin:
	echo $(DATA-RELEASE)/ParCzech.TEI.ana/ParCzech.ana.xml | xargs ${pc}
validate-release-ParCzech:
	echo $(DATA-RELEASE)/ParCzech.TEI.ana/ParCzech.ana.xml | xargs ${pc}



validate-release-ParCzech.TEI.ana:
	find $(DATA-RELEASE) -type f -path "$(DATA-RELEASE)ParCzech.TEI.ana/ParCzech.ana.xml" | xargs ${vra}
	find $(DATA-RELEASE) -type f -path "$(DATA-RELEASE)ParCzech.TEI.ana/*/*" -name "*.ana.xml" | xargs ${vca}
	find $(DATA-RELEASE) -type f -path "$(DATA-RELEASE)ParCzech.TEI.ana/*-taxonomy-*.xml" | xargs ${vch_taxonomy}
	find $(DATA-RELEASE) -type f -path "$(DATA-RELEASE)ParCzech.TEI.ana/ParCzech-listPerson.xml" | xargs ${vch_pers}
	find $(DATA-RELEASE) -type f -path "$(DATA-RELEASE)ParCzech.TEI.ana/ParCzech-listOrg.xml" | xargs ${vch_orgs}

validate-release-ParCzech.TEI:
	find $(DATA-RELEASE) -type f -path "$(DATA-RELEASE)ParCzech.TEI/ParCzech.xml" | xargs ${vrt}
	find $(DATA-RELEASE) -type f -path "$(DATA-RELEASE)ParCzech.TEI/*/*" -name "*.xml" | xargs ${vct}
	find $(DATA-RELEASE) -type f -path "$(DATA-RELEASE)ParCzech.TEI/*-taxonomy-*.xml" | xargs ${vch_taxonomy}
	find $(DATA-RELEASE) -type f -path "$(DATA-RELEASE)ParCzech.TEI/ParCzech-listPerson.xml" | xargs ${vch_pers}
	find $(DATA-RELEASE) -type f -path "$(DATA-RELEASE)ParCzech.TEI/ParCzech-listOrg.xml" | xargs ${vch_orgs}

###### Check links
check-links-release-ParCzech.TEI.ana check-links-release-ParCzech.TEI: check-links-release-ParCzech.TEI%:
	for root in `find $(DATA-RELEASE)ParCzech.TEI$*/ParCzech$*.xml`;	do \
	  echo "checking links in root:" $${root}; \
	  ${s} ${vlink} $${root}; \
	  for component in `echo $${root}| xargs ${getheaderincludes}`; do \
	    echo "checking links in header component:" $(DATA-RELEASE)ParCzech.TEI$*/$${component}; \
	    ${s} meta=$${root} ${vlink} $(DATA-RELEASE)ParCzech.TEI$*/$${component}; \
	  done; \
	  for component in `echo $${root}| xargs ${getcomponentincludes}`; do \
	    echo "checking links in component:" $(DATA-RELEASE)ParCzech.TEI$*/$${component}; \
	    ${s} meta=$${root} ${vlink} $(DATA-RELEASE)ParCzech.TEI$*/$${component}; \
	  done; \
	done


DEV-clean-sample-for-release:
	rm -r $(SAMPLE-DATA-IN)/parczech.tei.*
DEV-prepare-sample-for-release: DEV-prepare-sample-for-release-raw DEV-prepare-sample-for-release-ana

DEV-prepare-sample-for-release-raw DEV-prepare-sample-for-release-ana: DEV-prepare-sample-for-release-%:
	mkdir -p $(SAMPLE-DATA-IN)/parczech.tei.$* || :
	rsync -a --exclude='*/' $(SAMPLE-DATA-SOURCE)/parczech.tei.$*/consolidated/  $(SAMPLE-DATA-IN)/parczech.tei.$*/consolidated/
	@echo "INFO: [$*] sync files in root folder"
	xmlstarlet edit --inplace \
	                --delete "/_:teiCorpus/xi:include[not(position() = 1 or position() = last() )]" \
	                $(SAMPLE-DATA-IN)/parczech.tei.$*/consolidated/ParCzech.*xml
	@echo "INFO: [$*] sync component files"
	echo $(SAMPLE-DATA-IN)/parczech.tei.$*/consolidated/ParCzech.*xml \
	  | xargs ${getcomponentincludes} \
	  | xargs -I {} scp $(SAMPLE-DATA-SOURCE)/parczech.tei.$*/consolidated/{}  $(SAMPLE-DATA-IN)/parczech.tei.$*/consolidated/{}
	make DEV-prepare-sample-for-release-$*-fix

DEV-prepare-sample-for-release-raw-fix: # raw specific issues

DEV-prepare-sample-for-release-ana-fix: # ana specific issues

###################
audio-release-folder-structure: audio-release-folder-structure-clear
	mkdir -p $(AUDIO-DATA-TO-RELEASE)/ || :
	# create audioPSP-YYYY-QN/audio/psp/YYYY/MM audio-release-folder-structure
	find $(AUDIO-DATA-SOURCE)/ -type d| grep -v '/../..$$'| sed -n 's@^.*/audio/\(....\)/\(..\)@audioPSP-\1-MONTH\2/$(AUDIO-DATA-RELEASE-COMMON-PATH)/\1/\2@p' \
	  | sed 's/MONTH0[123]/Q1/;s/MONTH0[456]/Q2/;s/MONTH0[789]/Q3/;s/MONTH[1][012]/Q4/' |xargs -I {} mkdir -p $(AUDIO-DATA-TO-RELEASE)/{}
	# create audio/psp/YYYY/MM/DD symlinks
	find $(AUDIO-DATA-TO-RELEASE)/ -type d| grep  '/..../..$$' \
	  | sed 's@\(.*\)/\(....\)/\(..\)@realpath --relative-to="\1/\2/\3" `find $(AUDIO-DATA-SOURCE)/ -type d -path "**/\2/\3/*"|tr "\\n" " "`| xargs -I {} echo ln -s {}YYY \1/\2/\3/XXX@' \
	  | sh \
	  | sed 's@\(.*\)\(/..\)YYY \(.*\)XXX@\1\2 \3\2@' \
	  | sh
audio-release-folder-structure-clear:
	rm -r $(AUDIO-DATA-TO-RELEASE)/* || :

audio-release: audio-release-pack audio-release-meta

AUDIO-Qn = $(addprefix audio-release-pack-,$(shell ls $(AUDIO-DATA-TO-RELEASE)))
audio-release-pack: $(AUDIO-Qn)
$(AUDIO-Qn): audio-release-pack-%:
	mkdir -p $(AUDIO-DATA-RELEASE) || :
	tar -cf $(AUDIO-DATA-RELEASE)/$*.tar --mode='a+rwX' --dereference --directory=$(AUDIO-DATA-TO-RELEASE)/$* audio

AUDIO-Qn-unpack = $(addprefix audio-release-unpack-,$(shell ls $(AUDIO-DATA-TO-RELEASE)))
audio-release-unpack: $(AUDIO-Qn-unpack)
$(AUDIO-Qn-unpack): audio-release-unpack-%:
	mkdir $(AUDIO-DATA-PATH)/UNPACK-TEST/ || :
	tar -xvf $(AUDIO-DATA-RELEASE)/$*.tar -C $(AUDIO-DATA-PATH)/UNPACK-TEST/

## meta ##
audio-release-meta: audio-release-meta-mp3 audio-release-meta-quarter
audio-release-meta-clear:
	rm $(TSVaudioFile) $(TSVquarterArchive)

## audioFile
$(TSVaudioFile):
	@mkdir -p $(AUDIO-DATA-RELEASE) || :
	@echo "filePath fileSource archiveFileName fromVersion isUpdated"|tr " " "\t" > $(TSVaudioFile)

audio-release-meta-mp3: $(TSVaudioFile)
	@find -L $(AUDIO-DATA-TO-RELEASE) -type f | xargs -I {} make  --no-print-directory audio-release-meta-mp3-FILE FILE={}
	@cat $(TSVaudioFile).tmp | sort >> $(TSVaudioFile)
	@echo `cat $(TSVaudioFile).tmp|wc -l` "files added to $(TSVaudioFile)"
	@rm $(TSVaudioFile).tmp

FILE-DATE-PATH=$(shell echo -e "$(FILE)" | sed 's@.*$(AUDIO-DATA-RELEASE-COMMON-PATH)/*@@')
audio-release-meta-mp3-FILE: $(FILE)
	@echo -n "$(AUDIO-DATA-RELEASE-COMMON-PATH)/$(FILE-DATE-PATH)\\t" >> $(TSVaudioFile).tmp
	@realpath `find $(AUDIO-DATA-SOURCE) -path "*/2016/06/01/2016060110381052.mp3"`|sed 's@^.*\(www.psp.cz/\)@https://\1@'|tr "\n" "\t" >> $(TSVaudioFile).tmp
	@echo -n "$(FILE)"|sed 's@^.*\(audioPSP-....-Q.\).*$$@\1.tar\t@' >> $(TSVaudioFile).tmp
	@echo "$(AUDIO-DATA-VERSION)\\t1">> $(TSVaudioFile).tmp



## quarterArchive
$(TSVquarterArchive):
	mkdir -p $(AUDIO-DATA-RELEASE) || :
	echo "archiveFileName fromDate toDate cntFiles fromVersion isUpdated repositoryUrl"|tr " " "\t" > $(TSVquarterArchive)

audio-release-meta-quarter: $(TSVquarterArchive)
	@ls $(AUDIO-DATA-TO-RELEASE) | xargs -I {} make  --no-print-directory audio-release-meta-quarter-FILE FILE={}
	@cat $(TSVquarterArchive).tmp | sort >> $(TSVquarterArchive)
	@echo `cat $(TSVquarterArchive).tmp|wc -l` "files added to $(TSVquarterArchive)"
	@rm $(TSVquarterArchive).tmp

audio-release-meta-quarter-FILE:
	@echo -n "$(FILE).tar\\t" >> $(TSVquarterArchive).tmp
	@echo $(AUDIO-DATA-TO-RELEASE)/$(FILE)/$(AUDIO-DATA-RELEASE-COMMON-PATH)/*/*/*|tr " " "\\n"| sort|head -n1|sed 's@.*$(AUDIO-DATA-RELEASE-COMMON-PATH)/*@@'|tr "/\\n" "-\\t">> $(TSVquarterArchive).tmp
	@echo $(AUDIO-DATA-TO-RELEASE)/$(FILE)/$(AUDIO-DATA-RELEASE-COMMON-PATH)/*/*/*|tr " " "\\n"| sort|tail -n1|sed 's@.*$(AUDIO-DATA-RELEASE-COMMON-PATH)/*@@'|tr "/\\n" "-\\t">> $(TSVquarterArchive).tmp
	@find -L $(AUDIO-DATA-TO-RELEASE)/$(FILE) -type f | wc -l|tr "\\n" "\\t"  >> $(TSVquarterArchive).tmp
	@echo "$(AUDIO-DATA-VERSION)\\t1\\t$(AUDIO-DATA-RELEASE-REPOSITORY-URL-PREF)$(FILE).tar" >> $(TSVquarterArchive).tmp


################### TEITOK
release2teitok: tools/parlamint-lib.xsl
	mkdir -p $(DATA-TEITOK)/
	@test -n "$(PROFILE)" && echo "RUNNING PROFILER saxon param: $(PROF)" || :
	$s $(PROF) -xsl:tools/ParCzech2teitok.xsl \
	    commit=$(shell git -C . rev-parse HEAD) \
	    outDir=$(DATA-TEITOK)/ \
	    jobsCnt=$(JOBS-CNT) \
	    jobN=${JOB-N} \
	    $(DATA-RELEASE)/ParCzech.TEI.ana/ParCzech.ana.xml
	@test -n "$(PROFILE)" && echo "Profiler output: " $(shell echo -n "$(PROFILE)"|sed 's/^.*://') || :


teitok-get-taxonomies-translation:
	@make teitok-get-taxonomy-translation \
	           TAXONOMY=$(DATA-RELEASE)/ParCzech.TEI.ana/ParCzech-taxonomy-NER.cnec2.0.ana.xml \
	           TAXONOMY-REPLACE-ID='s/^NER.cnec2.0.//' \
	           TAXONOMY-TRANSLATION-ID-PREFIX='cnec-' \
	           TAXONOMY-REPLACE-TERM='s///' \
	           TAXONOMY-LANG='en'

teitok-get-taxonomy-translation:
	@java -cp /usr/share/java/saxon.jar net.sf.saxon.Query \
	         -xi:off \!method=adaptive \
	         -qs:'//*:category/*:catDesc[ancestor-or-self::*[@xml:lang][1]/@xml:lang="$(TAXONOMY-LANG)"]/concat(ancestor::*:category[1]/@xml:id,"@",./*:term,normalize-space(./*:term/following-sibling::text()))' \
	         -s:$(TAXONOMY) \
	  | sed 's/^"//;s/"$$//' \
	  | sed '$(TAXONOMY-REPLACE-ID)' \
	  | sed 's/^\(.*\)@/$(TAXONOMY-TRANSLATION-ID-PREFIX)\1\t\1::/'


################### DEPENDENCIES

tools/parlamint-lib.xsl:
	git archive --remote=git://github.com/clarin-eric/ParlaMint.git devel Scripts/parlamint-lib.xsl | tar -xO  Scripts/parlamint-lib.xsl > tools/parlamint-lib.xsl
###################
s = java $(JM) -jar $(JAVA-PATH)/saxon.jar
j = java $(JM) -jar $(JAVA-PATH)/jing.jar
pc = -I % $s -xi -xsl:$(PWD)/tools/copy.xsl % | $j schema/parla-clarin.rng
vrt = $j schema/ParCzech-teiCorpus.rng 	# Corpus root / text
vct = $j schema/ParCzech-TEI.rng		# Corpus component / text
vra = $j schema/ParCzech-teiCorpus.ana.rng	# Corpus root / analysed
vca = $j schema/ParCzech-TEI.ana.rng		# Corpus component / analysed
vch_taxonomy = $j schema/ParCzech-taxonomy.rng # factorized taxonomy
vch_pers = $j schema/ParCzech-listPerson.rng # factorized listPerson
vch_orgs = $j schema/ParCzech-listOrg.rng # factorized listOrg
vlink = -xsl:tools/check-links.xsl
getincludes = -I % java -cp /usr/share/java/saxon.jar net.sf.saxon.Query -xi:off \!method=adaptive -qs:'//*[local-name()="include"]/@href' -s:% |sed 's/^ *href="//;s/"//'
getheaderincludes = -I % java -cp /usr/share/java/saxon.jar net.sf.saxon.Query -xi:off \!method=adaptive -qs:'//*[local-name()="teiHeader"]//*[local-name()="include"]/@href' -s:% |sed 's/^ *href="//;s/"//'
getcomponentincludes = -I % java -cp /usr/share/java/saxon.jar net.sf.saxon.Query -xi:off \!method=adaptive -qs:'/*/*[local-name()="include"]/@href' -s:% |sed 's/^ *href="//;s/"//'
