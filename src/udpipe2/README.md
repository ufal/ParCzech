# udpipe2 TEI file tokenizer, tagger and parser


## Setup

Copy code into the current directory:
```bash
svn checkout https://github.com/ufal/ParCzech/trunk/src/udpipe2
svn checkout https://github.com/ufal/ParCzech/trunk/src/lib
```

Then install all dependencies. Run:
```bash
perl -I lib udpipe2/udpipe2.pl
Can't locate XML/LibXML.pm in @INC (you may need to install the XML::LibXML module) (@INC contains: lib ...) at udpipe2/udpipe2.pl line 5.
BEGIN failed--compilation aborted at udpipe2/udpipe2.pl line 5.
```
and install missing dependencies
```bash
cpanm XML::LibXML
```

## Run

```bash
perl -I lib udpipe2/udpipe2.pl --colon2underscore \
                             --model "uk:ukrainian-iu-ud-2.10-220711" \
                             --model "ru:russian-syntagrus-ud-2.10-220711" \
                             --elements "seg" \
                             --debug \
                             --try2continue-on-error \
                             --filelist list_of_filenames2process.fl \
                             --input-dir inDir \
                            --output-dir outDir
```

