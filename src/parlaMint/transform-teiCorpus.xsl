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

  <xsl:template match="//tei:encodingDesc">
    <xsl:copy>
      <xsl:apply-templates select="./tei:projectDesc"/>
      <editorialDecl>
            <correction>
               <p xml:lang="en">No correction of source texts was performed.</p>
            </correction>
            <normalization>
               <p xml:lang="en">Text has not been normalised, except for spacing.</p>
            </normalization>
            <hyphenation>
               <p xml:lang="en">No end-of-line hyphens were present in the source.</p>
            </hyphenation>
            <quotation>
               <p xml:lang="en">Quotation marks have been left in the text and are not explicitly marked up.</p>
            </quotation>
            <segmentation>
               <p xml:lang="en">The texts are segmented into utterances (speeches) and segments (corresponding to paragraphs in the source transcription).</p>
            </segmentation>
         </editorialDecl>
      <xsl:apply-templates select="./*[not(local-name() = 'projectDesc')]"/>
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>