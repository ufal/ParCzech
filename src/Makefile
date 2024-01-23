



PWD=$(shell pwd)
DATA-RELEASE=$(PWD)/data/release/
SAMPLE-DATA-IN=$(PWD)/data/sample-in/
DATA-IN=$(SAMPLE-DATA-IN)
SAMPLE-DATA-SOURCE=parczech:/opt/data/data-ParlaMint3.1-FRESH/




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


###################x
s = java $(JM) -jar /usr/share/java/saxon.jar
j = java $(JM) -jar /usr/share/java/jing.jar
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
