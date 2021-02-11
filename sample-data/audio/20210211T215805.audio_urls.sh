#!/bin/bash
SELF="$0"
DIR=`dirname $SELF`
LOG="$SELF.log"
REJECT="$SELF.reject"

cat "$SELF" | sed -n "s/^#AUDIO://p"| wget --no-verbose --no-clobber --directory-prefix "$DIR" --output-file "$LOG" --rejected-log "$REJECT" --force-directories -w 1 -i-


#AUDIO:https://psp.cz/eknih/2010ps/audio/2012/01/31/2012013113581412.mp3
# LIST OF FILES:

#TEI:ps2013-016/ps2013-016-01-000-000.xml
#AUDIO:https://www.psp.cz/eknih/2013ps/audio/2014/09/10/2014091013081322.mp3
#AUDIO:https://www.psp.cz/eknih/2013ps/audio/2014/09/10/2014091013181332.mp3

#TEI:ps2013-016/ps2013-016-01-001-001.xml
#AUDIO:https://www.psp.cz/eknih/2013ps/audio/2014/09/10/2014091013181332.mp3
#AUDIO:https://www.psp.cz/eknih/2013ps/audio/2014/09/10/2014091013281342.mp3
#AUDIO:https://www.psp.cz/eknih/2013ps/audio/2014/09/10/2014091013381352.mp3
#AUDIO:https://www.psp.cz/eknih/2013ps/audio/2014/09/10/2014091013481402.mp3
#AUDIO:https://www.psp.cz/eknih/2013ps/audio/2014/09/10/2014091013581412.mp3
#AUDIO:https://www.psp.cz/eknih/2013ps/audio/2014/09/10/2014091014081422.mp3
#AUDIO:https://www.psp.cz/eknih/2013ps/audio/2014/09/10/2014091014181432.mp3
#AUDIO:https://www.psp.cz/eknih/2013ps/audio/2014/09/10/2014091014281442.mp3

#TEI:ps2013-016/ps2013-016-01-002-002.xml
#AUDIO:https://www.psp.cz/eknih/2013ps/audio/2014/09/10/2014091014281442.mp3
#AUDIO:https://www.psp.cz/eknih/2013ps/audio/2014/09/10/2014091014381452.mp3

#TEI:ps2017-070/ps2017-070-01-000-000.xml
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111907580812.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111908080822.mp3

#TEI:ps2017-070/ps2017-070-01-001-001.xml
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111908080822.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111908180832.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111908280842.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111908380852.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111908480902.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111908580912.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111909080922.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111909180932.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111909280942.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111909380952.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111909481002.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111909581012.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111910081022.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111910181032.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111910281042.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111910381052.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111910481102.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111910581112.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111911081122.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111911181132.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111911281142.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111911381152.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111911481202.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111911581212.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111912081222.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111912181232.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111912281242.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111912381252.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111912481302.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111912481302.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111914081422.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111914181432.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111914281442.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111914381452.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111914481502.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111914581512.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111915081522.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111915181532.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111915281542.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111915381552.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111915481602.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111915581612.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111916081622.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111916181632.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111916281642.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111916381652.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111916481702.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111916581712.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111917081722.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111917181732.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111917281742.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111917381752.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111917481802.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111918381852.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111918481902.mp3
#AUDIO:https://www.psp.cz/eknih/2017ps/audio/2020/11/19/2020111918581912.mp3
