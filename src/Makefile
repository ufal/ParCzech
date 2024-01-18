



PWD=$(shell pwd)
DATA-RELEASE=$(PWD)/data/release/
SAMPLE-DATA-IN=$(PWD)/data/sample-in/
DATA-IN=$(SAMPLE-DATA-IN)
SAMPLE-DATA-SOURCE=parczech:/opt/data/data-ParlaMint3.1-FRESH/




release:
	mkdir -p $(DATA-RELEASE)/
	$s -xsl:tools/ParCzech-finalize.xsl \
	    outDir=$(DATA-RELEASE)/ \
	    inListPerson=$(DATA-IN)/parczech.tei.ana/consolidated/ParCzech-listPerson.xml  \
	    inListOrg=$(DATA-IN)/parczech.tei.ana/consolidated/ParCzech-listOrg.xml \
	    inTaxonomiesDir=$(PWD)/metadater/taxonomies/ \
	    type=TEI.ana \
	    $(DATA-IN)/parczech.tei.ana/consolidated/ParCzech.ana.xml
	cp ./tei2teitok/pdt-fslib.xml $(DATA-RELEASE)/ParCzech.TEI.ana/





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
getcomponentincludes = -I % java -cp /usr/share/java/saxon.jar net.sf.saxon.Query -xi:off \!method=adaptive -qs:'/*/*[local-name()="include"]/@href' -s:% |sed 's/^ *href="//;s/"//'
