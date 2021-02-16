<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:xi="http://www.w3.org/2001/XInclude"
  xmlns:tei="http://www.tei-c.org/ns/1.0">
  <xsl:output method="text" omit-xml-declaration="yes" indent="no"/>
  <xsl:param name="data-path" />
  <xsl:template match="/tei:teiCorpus">
<xsl:text>#!/bin/bash
SELF="$0"
DIR=`dirname $SELF`
LOG="$SELF.log"
REJECT="$SELF.reject"

cat "$SELF" | sed -n "s/^#AUDIO://p"| wget --no-verbose --no-clobber --directory-prefix "$DIR" --output-file "$LOG" --rejected-log "$REJECT" --force-directories -w 1 -i-


# LIST OF FILES:
</xsl:text>

  <xsl:apply-templates select="./xi:include" />
  </xsl:template>


  <xsl:template match="xi:include">
    <xsl:value-of select="concat('&#xA;#TEI:',./@href,'&#xA;')" />
    <xsl:variable name="tei-file" select="document(concat($data-path,'/',./@href))" />
    <xsl:for-each select="$tei-file/tei:TEI/tei:teiHeader/tei:fileDesc//tei:recording[@type='audio']/tei:media">
      <xsl:value-of select="concat('#AUDIO:',./@source,'&#xA;')"/>
    </xsl:for-each>
  </xsl:template>
  <xsl:template match="text()" />


</xsl:stylesheet>