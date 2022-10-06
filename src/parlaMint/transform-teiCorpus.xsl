<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  xmlns:xi="http://www.w3.org/2001/XInclude"
  xmlns:pcz="http://ufal.mff.cuni.cz/parczech/ns/1.0"
  exclude-result-prefixes="tei pcz" >

  <xsl:output method="xml" indent="yes" encoding="UTF-8" />
  <xsl:param name="outdir" />
  <xsl:param name="rename" />
  <xsl:param name="insert-include" />

  <xsl:variable name="rename-files-doc" select="document($rename)" />
  <xsl:key name="rename-list" match="file" use="@from" />

  <xsl:include href="parczech2parlamint.xsl" />

  <xsl:template match="/tei:teiCorpus/@xml:id">
    <xsl:variable name="new-id" select="pcz:patch-corpus-id(.)" />
    <xsl:message><xsl:value-of select="concat('RENAME: ',.,' ',$new-id)" /></xsl:message> <!-- DO NOT REMOVE !!! -->
    <xsl:attribute name="xml:id">
      <xsl:value-of select="$new-id" />
    </xsl:attribute>
  </xsl:template>
  <xsl:template match="/tei:teiCorpus/tei:teiHeader/tei:encodingDesc/tei:listPrefixDef/tei:prefixDef[@ident='pdt']" /><!-- removing pdt prefix definition -->

  <xsl:template match="/tei:teiCorpus"> <!-- needed to remove unused namespaces -->
    <xsl:element name="{name()}">
      <xsl:apply-templates select="@*"/>
      <xsl:apply-templates select="element()"/>
    </xsl:element>
  </xsl:template>
  <xsl:template match="/tei:teiCorpus/xi:include">
    <xsl:element name="xi:include" namespace="http://www.w3.org/2001/XInclude">
      <xsl:namespace name="xi" select="'http://www.w3.org/2001/XInclude'"/>
      <xsl:attribute name="href">
        <xsl:value-of select=" key('rename-list',@href,$rename-files-doc)/@to"/>
      </xsl:attribute>
    </xsl:element>
  </xsl:template>


  <xsl:template match="//tei:particDesc"> <!-- needed to remove unused namespaces -->
    <xsl:element name="{name()}">
      <xsl:apply-templates select="@*"/>
      <xsl:apply-templates select="element()"/>
    </xsl:element>
  </xsl:template>
  <xsl:template match="xi:include[parent::tei:particDesc]">
    <xsl:choose>
      <xsl:when test="$insert-include = 1">
        <xsl:message select="concat('inserting content of ',@href)"/>
        <xsl:copy-of select="document(@href)"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:element name="xi:include" namespace="http://www.w3.org/2001/XInclude">
          <xsl:namespace name="xi" select="'http://www.w3.org/2001/XInclude'"/>
          <xsl:attribute name="href">
            <xsl:value-of select="replace(@href,'ParCzech','ParlaMint-CZ')"/>
          </xsl:attribute>
        </xsl:element>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>


  <xsl:function name="pcz:patch-id">
    <xsl:param name="id" />
    <xsl:value-of select="$id" />
  </xsl:function>

  <xsl:function name="pcz:patch-corpus-id">
    <xsl:param name="id" />
    <xsl:if test="contains($id,'.')">
      <xsl:value-of select="concat($id-prefix,'.',substring-after($id,'.'))" />
    </xsl:if>
    <xsl:value-of select="$id-prefix" />
  </xsl:function>

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