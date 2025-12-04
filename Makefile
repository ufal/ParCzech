.DEFAULT_GOAL := help

##$FIRSTDATE## The oldest date (YYYY-MM-DD) to be considered to download
FIRSTDATE := 2025-11-05

RUNID := $(shell date +"%Y%m%dT%H%M%S")

DATA := $(shell pwd)/data
DATASHARED := $(DATA)/shared
REPOSITORY := $(DATA)/repository
DATARUN := $(DATA)/$(RUNID)
DATABASE := $(DATARUN)/database/work
PROC := $(DATARUN)/proc
HTML := $(DATARUN)/html
HTML_DISTRO := $(DATARUN)/dist
HTML_WORK := $(HTML)/work
HTML_WORK_SOURCE := $(HTML_WORK)/source
HTML_WORK_REPOSITORY := $(HTML_WORK)/repository
HTML_WORK_NORMALIZED := $(HTML_WORK)/normalized
TMP := $(DATARUN)/tmp
STATIC := $(shell pwd)/static

##$DONT_USE_REPOSITORY## Set whether the release result should be passed to repository or stored in local folder
DONT_USE_REPOSITORY := 1

ifeq ($(DONT_USE_REPOSITORY),1)
  REPOSITORY_URL := $(shell pwd)/test_repository
define REPOSITORY_CMD
	   mkdir -p "$3"; cp "$(REPOSITORY_URL)/$1/$2" "$3/$2"
endef
else
  REPOSITORY_URL := 
define REPOSITORY_CMD
    mkdir -p "$3"; curl -s -L -o "$3/$2" "$(REPOSITORY_URL)/$1/$2"
endef
endif


-include Makefile.dev


URL_PSP_STENO_TABLES = https://www.psp.cz/eknih/cdrom/opendata/steno.zip
URL_PSP_PERS_ORG_TABLES = https://www.psp.cz/eknih/cdrom/opendata/poslanci.zip
PATCH_PSP_STENO_TABLES_add_year = $(STATIC)/psp_idorg2year.tsv



$(DATA) $(DATABASE) $(TMP) $(PROC) $(DATASHARED) $(HTML_DISTRO):
	mkdir -p $@

###### Download

## download-tables-steno ## downloads current table with all steno metadata
download-tables-steno: $(DATABASE)/steno
$(DATABASE)/steno: $(DATABASE)
	@# table documentation: https://www.psp.cz/sqw/hp.sqw?k=1310
	@echo "INFO: Downloading steno tables with metadata"
	@wget -O "$(DATABASE)/steno.zip"  $(URL_PSP_STENO_TABLES) 
	@unzip -o "$(DATABASE)/steno.zip" -d "$(DATABASE)/steno"

## download-tables-person-and-org ## downloads current table with all persons and organizations
download-tables-person-and-org: $(DATABASE)/person-org
$(DATABASE)/person-org: $(DATABASE)
	@# table documentation: https://www.psp.cz/sqw/hp.sqw?k=1301
	@echo "INFO: Downloading 'poslanci a osoby' tables with metadata"
	@wget -O "$(DATABASE)/poslanci.zip"  $(URL_PSP_PERS_ORG_TABLES) 
	@unzip -o "$(DATABASE)/poslanci.zip" -d "$(DATABASE)/person-org"


## downloader-get-urls ## extend steno tables with times and steno and audio urls (calls download-tables-steno)
downloader-get-urls: $(DATABASE)/steno $(DATABASE)/person-org $(TMP) $(PROC) # download-tables-steno $(PATCH_PSP_STENO_TABLES_add_year)
	@# adding year as the last column (steno.unl)
	@# 140734|173|111|79|2024-07-11|1|1320|1330|
	@# columns:
	@ # 1) id like
	@	# 2) org_id
	@	# 3) meeting
	@	# 4) page order in day
	@	# 5) date YYYY-MM-DD
	@	# 6) sitting day in meeting
	@	# 7) start steno time - minutes from day beginning 
	@	# 8) end steno time - minutes from day beginning		
	@cut -f 1,3,4,7 -d'|'  $(DATABASE)/person-org/organy.unl| awk 'BEGIN {FS="|";OFS="|"}{if($$2 == 11){print $$1,$$3,$$4,substr($$4, 7, 4)}}' > $(PROC)/psp-organy-year.unl
	@# https://www.psp.cz/eknih/<id_org_year>ps/stenprot/<schuze>schuz/s<schuze><stranka>.htm
	@# https://www.psp.cz/eknih/<id_org_year>ps/audio/<year>/<month>/<day>/<year><monnth><day>08580912.mp3
	@# appending columns:
	@ # 9) start term year
	@ # 10) start steno time HH:MM
	@ # 11) end steno time HH:MM
	@ # 12) start audio time HHMM
	@ # 14) end audio time HHMM
	@ # 15) steno url
	@ # 16) audio url
	@awk ' \
	  BEGIN {FS="|";OFS="\t"} \
		NR==FNR { org2year[$$1] = $$4;next } \
		$$2 in org2year { \
		  start_steno = sprintf("%02d:%02d",int(($$7) / 60),($$7 % 60)); \
		  end_steno = sprintf("%02d:%02d",int(($$8) / 60),($$8 % 60)); \
			start_audio = sprintf("%02d%02d",int((int($$7/10)*10-2) / 60),((int($$7/10)*10-2) % 60)); \
			end_audio = sprintf("%02d%02d",int((int($$7/10)*10-2+14) / 60),((int($$7/10)*10-2+14) % 60)); \
			split($$5, d, "-"); \
		  url_steno = sprintf("https://www.psp.cz/eknih/%sps/stenprot/%03dschuz/s%03d%03d.htm", org2year[$$2], $$3, $$3, $$4); \
		  url_audio = $$8 == "" ? "" : sprintf("https://www.psp.cz/eknih/%sps/audio/%04d/%02d/%02d/%04d%02d%02d%s%s.mp3",org2year[$$2], d[1], d[2], d[3], d[1], d[2], d[3], start_audio, end_audio); \
		  print $$1,$$2,$$3,$$4,$$5,$$6,$$7,$$8,org2year[$$2],start_steno,end_steno,start_audio,end_audio,url_steno, url_audio;\
		} \
	  ' \
		$(PROC)/psp-organy-year.unl \
	  $</steno.unl \
		> $(PROC)/urls-all.tsv

$(PROC)/urls-all.tsv: downloader-get-urls

$(DATASHARED)/urls-seen-notfinal.tsv $(DATASHARED)/urls-seen-final.tsv: $(DATASHARED)
	touch $@

$(PROC)/meetings-to-download.tsv: $(PROC)/urls-all.tsv $(DATASHARED)/urls-seen-notfinal.tsv
	@echo -n "INFO[$@]: getting list of meetings to be downloaded:"
	@( awk -F'\t' '$$5 >= "$(FIRSTDATE)"' $(PROC)/urls-all.tsv; cat $(DATASHARED)/urls-seen-notfinal.tsv ) \
	  |	awk -F'\t' -v OFS='\t' '{ print $$9, $$3 }'\
		| sort \
		| uniq \
		> $@


$(PROC)/urls-to-download.tsv: $(PROC)/meetings-to-download.tsv $(PROC)/urls-all.tsv $(DATASHARED)/urls-seen-final.tsv
	@# get all new and to update urls - all urls in meeting to download and skip final urls
	@echo "INFO[$@]: STARTED steno URLs to be downloaded"
	@awk -F'\t' \
	    'NR==FNR { key[$$1 FS $$2] = 1;next } ($$9 FS $$3) in key' \
			$(PROC)/meetings-to-download.tsv \
			$(PROC)/urls-all.tsv > $(PROC)/urls-to-include.tsv
	@if [ -s $(DATASHARED)/urls-seen-final.tsv ]; then \
	  awk -F'\t' \
	    'NR==FNR {  if ($$14 != "") key[$$14] = 1;next } !($$14 in key)' \
			$(DATASHARED)/urls-seen-final.tsv \
			$(PROC)/urls-to-include.tsv ; \
	else \
	  cat $(PROC)/urls-to-include.tsv ; \
	fi > $@
	@echo "INFO[$@]: URLs to be downloaded stored in: $@"

## download-steno-from-repository ## download steno to be updated from repository
download-steno-from-repository: $(HTML_WORK_REPOSITORY)
$(HTML_WORK_REPOSITORY): $(PROC)/meetings-to-download.tsv $(HTML_WORK_SOURCE)
	@# download only meetings
	@echo "TODO[$@]"
	@ #$(call REPOSITORY_CMD,handle,file_name,output_path)

## download-steno-from-psp ## download new steno from PSP
download-steno-from-psp: $(HTML_WORK_SOURCE)
$(HTML_WORK_SOURCE): $(PROC)/urls-to-download.tsv
	@echo "INFO[$@]: downloading meeting steno, that has sitting day newer than $(FIRSTDATE) - new or needs to be updated"
	@test -d $@ && echo "INFO: downloading skipped - folder exists" || ( \
	  mkdir -p $@; \
	  cut -f14 $< \
	    | wget --no-verbose \
		       --no-clobber=off \
					 --directory-prefix "$(HTML_WORK_SOURCE)" \
					 --output-file "$(HTML_WORK)/steno-down.log" \
					 --rejected-log "$(HTML_WORK)/steno-down-reject.log" \
					 --force-directories \
					 -w 1 \
					 -i- \
	)

## build-steno ## prepare new repository records based on new/updated data
build-steno: $(HTML_WORK_SOURCE) $(HTML_WORK_REPOSITORY) $(HTML_DISTRO)
	@mkdir -p $(HTML_WORK_NORMALIZED)
	@find $(HTML_WORK_SOURCE) -type d -printf '%P\n'| xargs -I {} mkdir -p $(HTML_WORK_NORMALIZED)/{}
	@find $(HTML_WORK_SOURCE) -type f -printf '%P\n'\
	  | parallel  "make --silent get-and-normalize-html-content INFILE=$(HTML_WORK_SOURCE)/{} > $(HTML_WORK_NORMALIZED)/{} "
	@# file_path md5sum_normalized runid source_url source_down_date isfinal
	@echo "INFO: calculating checksums of downloaded steno files"
	@cat $(HTML_WORK)/steno-down.log \
	  | sed -n 's/^\([-:0-9 ]*\) URL:\([^ ]*\) .* -> "\(.*\)".*/\1\t\2\t\3/p' \
		| awk \
		      -v norm="$(HTML_WORK_NORMALIZED)/" \
		      -v down="$(HTML_WORK_SOURCE)/" \
		      -v runid="$(RUNID)" \
					' \
	        BEGIN {FS="\t";OFS="\t"} \
					{ \
					  sub("^" down, "", $$3); \
						cmd = "md5sum " norm $$3; \
						cmd | getline output; split(output, sum, " "); 	close(cmd); \
						cmd = "xmllint --html --xpath \"boolean(not(//p[@class=\\\"status warning\\\"]))\" " norm $$3;\
						cmd | getline isfinal; close(cmd); \
						print $$3, sum[1], runid, $$2, $$1, isfinal; \
					} \
					' \
		> $(PROC)/files-current-steno-psp.tsv
	@echo "INFO: merging checksum file with metadata from database"
	@awk \
	    '\
	      BEGIN {FS="\t";OFS="\t"} \
			  NR==FNR { fl[$$4]=$$0;next } \
        $$14 in fl { print $$0 "\t" fl[$$14] }\
			' \
    $(PROC)/files-current-steno-psp.tsv \
		$(PROC)/urls-to-download.tsv \
		> $(PROC)/urls_files-current-steno-psp.tsv
	@echo "INFO: creating checksum and metadata file in the final shape (TSV)"
	@# chamber therm meeting sittingN page_in_meeting date starttime endtime file md5sum isfinal cite_datetime stenourl audiourl
	@awk \
	    '\
	    BEGIN {FS="\t";OFS="\t"} \
			{\
	      print "ps", \
				      $$9, \
				      $$3, \
				      $$6, \
				      $$4, \
				      $$5, \
				      $$10, \
				      $$11, \
				      $$16, \
				      $$17, \
				      $$21, \
				      $$20, \
				      $$14, \
				      $$15;\
			}\
			'\
			$(PROC)/urls_files-current-steno-psp.tsv \
			> $(PROC)/distro-current-steno-psp.tsv	
	@echo "INFO: determining which files are new or updated"
	@if [ -s $(DATASHARED)/urls-seen-final.tsv ]; then \
	  awk ' \
	    BEGIN {FS="\t";OFS="\t"} \
		  NR==FNR { file[$$9] = $$10;next } \
		  !($$9 in file) { \
		    print $$0,$$1;\
			  next\
		  } \
		  file[$$9]!=$$10 { \
		    print $$0,$$1;\
			  next\
		  }\
	    ' \
		  $(DATASHARED)/urls-seen-notfinal.tsv\
	    $(PROC)/distro-current-steno-psp.tsv; \
	else \
	  cat $(PROC)/distro-current-steno-psp.tsv ; \
	fi > $(PROC)/distro-current-steno-psp-new-or-updated.tsv 
	@echo "INFO: " $$(cat $(PROC)/distro-current-steno-psp-new-or-updated.tsv | wc -l) " new or updated files"
	@echo "INFO: determining which meetings are new or updated"
	@cat $(PROC)/distro-current-steno-psp-new-or-updated.tsv \
	  | awk 'BEGIN {FS="\t";OFS="\t"} {print $$2,$$3;}'\
		|sort\
		|uniq \
	  > $(PROC)/distro-current-steno-psp-new-or-updated-meetings.tsv
	@echo "INFO: new/updated meetings:" $$(cat $(PROC)/distro-current-steno-psp-new-or-updated-meetings.tsv|tr "\n\t" " /")
	@echo "TODO: prepare folder structure for release"
	cp $(DATASHARED)/urls-seen-notfinal.tsv $(DATASHARED)/urls-seen-final.tsv $(PROC)/
	while read -r year meeting; do \
	  echo "Column 1: $$year"; \
	  echo "Column 2: $$meeting"; \
		foldername=$$(printf "ps%d-%03d" $$year $$meeting); \
		cat $(PROC)/distro-current-steno-psp-new-or-updated.tsv \
		  | awk \
		      -v year="$$year" \
		      -v meeting="$$meeting" \
					'BEGIN {FS="\t";OFS="\t"} \
					$$2==year && $$3==meeting {print $$0;}' \
			> $(PROC)/distro-current-steno-psp-new-or-updated.$$foldername.tsv; \
		awk \
		      -v year="$$year" \
		      -v meeting="$$meeting" \
					'\
					BEGIN {FS="\t";OFS="\t"} \
					NR==FNR { file[$$9] = 1; next} \
					!($$9 in file) && $$2==year && $$3==meeting {print $$9;print $$0; next} \
				' \
			  $(PROC)/distro-current-steno-psp-new-or-updated.$$foldername.tsv\
				$(PROC)/distro-current-steno-psp.tsv \
			> $(PROC)/distro-current-steno-psp-old.$$foldername.tsv; \
		cat $(PROC)/distro-current-steno-psp-old.$$foldername.tsv $(PROC)/distro-current-steno-psp-new-or-updated.$$foldername.tsv \
		  | cut -f9 | sort | uniq \
			| sed 's@[^/]*$$@@' \
			| xargs -I {} mkdir -p $(HTML_DISTRO)/$$foldername/{};\
		# copy old/notchanged files \
		cat $(PROC)/distro-current-steno-psp-old.$$foldername.tsv \
		  | cut -f9 \
			| xargs -I {} cp $(HTML_WORK_REPOSITORY)/$$foldername/{} $(HTML_DISTRO)/$$foldername/{};\
		# cope new/updated files \
		cat $(PROC)/distro-current-steno-psp-new-or-updated.$$foldername.tsv \
		  | cut -f9 \
			| xargs -I {} cp $(HTML_WORK_SOURCE)/{} $(HTML_DISTRO)/$$foldername/{};\
		cat $(PROC)/distro-current-steno-psp-old.$$foldername.tsv $(PROC)/distro-current-steno-psp-new-or-updated.$$foldername.tsv \
		  | sort > $(HTML_DISTRO)/$$foldername/metadata.tsv; \
	  cp $(PROC)/urls-seen-final.tsv $(PROC)/urls-seen-final.tsv.tmp; \
		awk 'BEGIN {FS="\t";OFS="\t"} $$11 == "true" {print $$0} ' $(HTML_DISTRO)/$$foldername/metadata.tsv \
		  >> $(PROC)/urls-seen-final.tsv.tmp; \
		cat $(PROC)/urls-seen-final.tsv.tmp | sort | uniq > $(PROC)/urls-seen-final.tsv; \
	  awk \
		  -v year="$$year" \
		  -v meeting="$$meeting" \
			'BEGIN {FS="\t";OFS="\t"}  !($$2==year && $$3==meeting) {print $$0;}' \
			$(PROC)/urls-seen-final.tsv \
			> $(PROC)/urls-seen-final.tsv.tmp; \
		awk 'BEGIN {FS="\t";OFS="\t"} $$11 == "false" {print $$0} ' $(HTML_DISTRO)/$$foldername/metadata.tsv \
		  >> $(PROC)/urls-seen-notfinal.tsv.tmp; \
		cat $(PROC)/urls-seen-notfinal.tsv.tmp | sort | uniq > $(PROC)/urls-seen-notfinal.tsv; \
	done < $(PROC)/distro-current-steno-psp-new-or-updated-meetings.tsv
	cp $(PROC)/urls-seen-notfinal.tsv $(PROC)/urls-seen-final.tsv $(DATASHARED)/


## release-steno ## calls build-steno and releases new/updated records in repository
release-steno: build-steno


get-and-normalize-html-content: $(INFILE)
	@iconv -f cp1250 -t utf-8  $< \
	  | perl -CSD -pe 's/\x{00A0}/ /g; s/&nbsp;/ /gi; s/[ \t]+/ /g;' \
		| iconv -f utf-8 -t cp1250 \
		| xmllint --html \
		          --recover \
							--xpath '//div[@id="main-content"]/*[not(self::script) and normalize-space(.)]' \
							- 2> /dev/null 



###### Help

help-intro:

help-variables:
	@echo "\033[1m\033[32mVARIABLES:\033[0m"
	@echo "Variable VAR with value 'value' can be set when calling target TARGET in $(MAKEFILE_LIST): make VAR=value TARGET"
	@grep -E '^## *\$$[a-zA-Z_-]*.*?##.*$$' $(MAKEFILE_LIST) |sed 's/^## *\$$/##/'| awk 'BEGIN {FS = " *## *"}; {printf "\033[1m%s\033[0m\033[36m%-18s\033[0m %s\n", $$4, $$2, $$3}'

help-targets:
	@echo "\033[1m\033[32mTARGETS:\033[0m"
	@grep -E '^## *[a-zA-Z_-]+.*?##.*$$|^####' $(MAKEFILE_LIST) | awk 'BEGIN {FS = " *## *"}; {printf "\033[1m%s\033[0m\033[36m%-25s\033[0m %s\n", $$4, $$2, $$3}'


.PHONY: help
## help ## print this help
help: help-intro help-variables help-targets

## help-advanced ## print full help
help-advanced: help
	@echo "\033[1m\033[32mADVANCED:\033[0m"
	@echo "If you want to run target on multiple targets but not all, you can overwrite PRESS variable. E.g. make check-links PRESS=\"GB CZ\""
	@grep -E '^## *![a-zA-Z_-]+.*?##.*$$|^##!##' $(MAKEFILE_LIST) |sed 's/^## *!/##/'| awk 'BEGIN {FS = " *## *"}; {printf "\033[1m%s\033[0m\033[35m%-25s\033[0m %s\n", $$4, $$2, $$3}'
