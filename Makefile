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
PATCH_PSP_STENO_TABLES_add_year = $(STATIC)/psp_idorg2year.tsv



$(DATA) $(DATABASE) $(TMP) $(PROC) $(DATASHARED):
	mkdir -p $@
####################### download

download-tables-steno: $(DATABASE)/steno
$(DATABASE)/steno: $(DATABASE)
	@# table documentation: https://www.psp.cz/sqw/hp.sqw?k=1310
	@echo "INFO: Downloading steno tables with metadata"
	@wget -O "$(DATABASE)/steno.zip"  $(URL_PSP_STENO_TABLES) 
	@unzip -o "$(DATABASE)/steno.zip" -d "$(DATABASE)/steno"



downloader-get-urls: $(DATABASE)/steno $(TMP) $(PROC) # download-tables-steno $(PATCH_PSP_STENO_TABLES_add_year)
	@# adding year as the last column
	@# 140734|173|111|79|2024-07-11|1|1320|1330|2021|
	@# columns:
	@ # 1) id like
	@	# 2) org_id
	@	# 3) meeting
	@	# 4) page order in day
	@	# 5) date YYYY-MM-DD
	@	# 6) sitting day in meeting
	@	# 7) start steno time - minutes from day beginning 
	@	# 8) end steno time - minutes from day beginning		
	@	# 9) term starting year - for constructing urls
	@sed 's#^\(.*\)\t\(.*\)$$#s@^\\([^\|]*\|\1\|.*\\)@\\1\2@\;t end#' $(PATCH_PSP_STENO_TABLES_add_year) > $(TMP)/steno-year.sed
	@echo  >> $(TMP)/steno-year.sed
	@echo ":end" >> $(TMP)/steno-year.sed
	@sed -f $(TMP)/steno-year.sed \
	    $</steno.unl \
			> $</steno-year.unl
	@# https://www.psp.cz/eknih/<id_org_year>ps/stenprot/<schuze>schuz/s<schuze><stranka>.htm
	@# https://www.psp.cz/eknih/<id_org_year>ps/audio/<year>/<month>/<day>/<year><monnth><day>08580912.mp3
	@# appending columns:
	@ # 10) start steno time HH:MM
	@ # 11) end steno time HH:MM
	@ # 12) start audio time HHMM
	@ # 13) end audio time HHMM
	@ # 14) steno url
	@ # 15) audio url
	@awk ' \
	  BEGIN {FS="|";OFS="\t"} \
		{ \
		  start_steno = sprintf("%02d:%02d",int(($$7) / 60),($$7 % 60)); \
		  end_steno = sprintf("%02d:%02d",int(($$8) / 60),($$8 % 60)); \
			start_audio = sprintf("%02d%02d",int((int($$7/10)*10-2) / 60),((int($$7/10)*10-2) % 60)); \
			end_audio = sprintf("%02d%02d",int((int($$7/10)*10-2+14) / 60),((int($$7/10)*10-2+14) % 60)); \
			split($$5, d, "-"); \
		  url_steno = sprintf("https://www.psp.cz/eknih/%sps/stenprot/%03dschuz/s%03d%03d.htm", $$9, $$3, $$3, $$4); \
		  url_audio = $$8 == "" ? "" : sprintf("https://www.psp.cz/eknih/%sps/audio/%04d/%02d/%02d/%04d%02d%02d%s%s.mp3",$$9, d[1], d[2], d[3], d[1], d[2], d[3], start_audio, end_audio); \
		  print $$1,$$2,$$3,$$4,$$5,$$6,$$7,$$8,$$9,start_steno,end_steno,start_audio,end_audio,url_steno, url_audio;\
		} \
	  ' \
	  $</steno-year.unl \
		> $(PROC)/urls-all.tsv

$(PROC)/urls-all.tsv: downloader-get-urls

$(DATASHARED)/urls-seen-notfinal.tsv $(DATASHARED)/urls-seen-final.tsv: $(DATASHARED)
	touch $@

$(PROC)/meetings-to-download.tsv: $(PROC)/urls-all.tsv $(DATASHARED)/urls-seen-notfinal.tsv
	@echo -n "INFO[$@]: getting list of meetings to be downloaded:"
	@( awk -F'\t' '$$5 >= "$(FIRSTDATE)"' $(PROC)/urls-all.tsv; cat $(DATASHARED)/urls-seen-notfinal.tsv ) |	cut -f 3,9 | sort |uniq > $@
	@cat $@|awk -F'\t' -v OFS='\t' '{ print $$2, $$1 }' |tr '\t\n' '/ '
	@echo


$(PROC)/urls-to-download.tsv: $(PROC)/meetings-to-download.tsv $(PROC)/urls-all.tsv $(DATASHARED)/urls-seen-final.tsv
	@# get all new and to update urls - all urls in meeting to download and skip final urls
	@echo "INFO[$@]: STARTED steno URLs to be downloaded"
	@awk -F'\t' \
	    'NR==FNR { key[$$1 FS $$2] = 1;next } ($$3 FS $$9) in key' \
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

download-steno-from-repository: $(HTML_WORK_REPOSITORY)
$(HTML_WORK_REPOSITORY): $(PROC)/meetings-to-download.tsv $(HTML_WORK_SOURCE)
	@# download only meetings
	@echo "TODO[$@]"
	@ #$(call REPOSITORY_CMD,handle,file_name,output_path)

download-steno-from-psp: $(HTML_WORK_SOURCE)
$(HTML_WORK_SOURCE): $(PROC)/urls-to-download.tsv
	@echo "INFO[$@]: downloading meeting steno, that has sitting day newer than $(FIRSTDATE) or needs to be updated"
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


build-steno: $(HTML_WORK_SOURCE) $(HTML_WORK_REPOSITORY)
	@mkdir -p $(HTML_WORK_NORMALIZED)
	@find $(HTML_WORK_SOURCE) -type d -printf '%P\n'| xargs -I {} mkdir -p $(HTML_WORK_NORMALIZED)/{}
	@find $(HTML_WORK_SOURCE) -type f -printf '%P\n'\
	  | parallel  "make --silent get-and-normalize-html-content INFILE=$(HTML_WORK_SOURCE)/{} > $(HTML_WORK_NORMALIZED)/{} "
	@# file_path md5sum_normalized runid source_url source_down_date isfinal
	@echo "INFO: calculating checksums of downloaded steno files"
	@cat $(HTML_WORK)/steno-down.log \
	  | sed -n 's/^\([-:0-9 ]*\) URL:\([^ ]*\) .* -> "\(.*\)".*/\1\t\2\t\3/p' \
		| awk -F'\t' -v OFS='\t' \
		      -v norm="$(HTML_WORK_NORMALIZED)/" \
		      -v down="$(HTML_WORK_SOURCE)/" \
		      -v runid="$(RUNID)" \
					' \
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
	@awk -F'\t' -v OFS='\t' \
	    '\
			  NR==FNR { fl[$$4]=$$0;next } \
        $$14 in fl { print $$0 "\t" fl[$$14] }\
			' \
    $(PROC)/files-current-steno-psp.tsv \
		$(PROC)/urls-to-download.tsv \
		> $(PROC)/urls_files-current-steno-psp.tsv
	@echo "INFO: creating checksum and metadata file in the final shape (TSV)"
	@# chamber therm meeting sittingN page_in_meeting date starttime endtime file md5sum isfinal cite_datetime stenourl audiourl
	@awk -F'\t' -v OFS='\t' \
	    '\
			{\
	      print "PSP ČR", \
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
	@echo "TODO: determining which files are new or updated"

	@echo "TODO: copy new or updated files to distro location"
	@echo "TODO: copy nonchanged files to distro location"
	@echo "TODO: create final checksums and metadata file" # use released file as a base and change updated or new rows
	

	
	
	@echo "TODO: $@"

release-steno: build-steno


get-and-normalize-html-content: $(INFILE)
	@iconv -f cp1250 -t utf-8  $< \
	  | perl -CSD -pe 's/\x{00A0}/ /g; s/&nbsp;/ /gi; s/[ \t]+/ /g;' \
		| iconv -f utf-8 -t cp1250 \
		| xmllint --html \
		          --recover \
							--xpath '//div[@id="main-content"]/*[not(self::script) and normalize-space(.)]' \
							- 2> /dev/null 

