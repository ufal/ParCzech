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
      <xsl:if test="contains(.,'.')">
        <xsl:value-of select="concat('.',substring-after(.,'.'))" />
      </xsl:if>
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

  <xsl:template match="tei:encodingDesc">
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
      <xsl:apply-templates select="./tei:tagsDecl"/>
      <xsl:apply-templates select="./tei:classDecl"/>

      <xsl:apply-templates select="./tei:listPrefixDef"/>
      <xsl:apply-templates select="./tei:appInfo"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="tei:classDecl">
    <xsl:copy>
      <xsl:apply-templates select="./tei:taxonomy"/>
      <taxonomy xml:id="subcorpus">
         <desc xml:lang="cs"><term>Podkorpusy</term></desc>
         <desc xml:lang="en"><term>Subcorpora</term></desc>
         <category xml:id="reference">
            <catDesc xml:lang="cs"><term>Referenční</term>: referenční podkorpus, do 2019-10-31</catDesc>
            <catDesc xml:lang="en"><term>Reference</term>: reference subcorpus, until 2019-10-31</catDesc>
         </category>
         <category xml:id="covid">
            <catDesc xml:lang="cs"><term>COVID</term>: COVID podkorpus, od 2019-11-01 dále</catDesc>
            <catDesc xml:lang="en"><term>COVID</term>: COVID subcorpus, from 2019-11-01 onwards</catDesc>
         </category>
      </taxonomy>
    </xsl:copy>
  </xsl:template>



</xsl:stylesheet>