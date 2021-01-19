<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  xmlns:xi="http://www.w3.org/2001/XInclude"
  exclude-result-prefixes="tei" >

  <xsl:output method="xml" indent="yes" encoding="UTF-8" />
  <xsl:param name="outdir" />

  <xsl:include href="parczech2parlamint.xsl" />

  <xsl:template match="/tei:teiCorpus/@xml:id">
    <xsl:attribute name="xml:id">
      <xsl:value-of select="$id-prefix" />
    </xsl:attribute>
  </xsl:template>

  <xsl:template match="/tei:teiCorpus/xi:include">
    <xsl:element name="xi:include">
      <xsl:variable name="filename" select="substring-after(./@href,'/')" />
      <xsl:attribute name="href">
        <xsl:value-of select="document(concat($outdir,'/',$filename))/tei:TEI/@xml:id"/>
        <xsl:text>.xml</xsl:text>
      </xsl:attribute>
    </xsl:element>
  </xsl:template>


  <xsl:template name="patch-id">
    <xsl:param name="id" />
    <xsl:attribute name="xml:id">
      <xsl:value-of select="$id" />
    </xsl:attribute>
  </xsl:template>



</xsl:stylesheet>