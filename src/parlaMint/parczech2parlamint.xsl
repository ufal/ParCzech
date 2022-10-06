<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  xmlns:pcz="http://ufal.mff.cuni.cz/parczech/ns/1.0"
  exclude-result-prefixes="tei pcz" >

  <xsl:output method="xml" indent="yes" encoding="UTF-8" />
  <xsl:param name="id-prefix" />
  <xsl:param name="handler" />
  <xsl:variable name="set-date" select="/tei:TEI//tei:settingDesc/tei:setting/tei:date[contains(concat(' ',./@ana,' '),' #parla.sitting ')]/@when"/>
  <xsl:variable name="date" select="translate($set-date, '-','')"/>



  <xsl:template match="@xml:id">
    <xsl:variable name="new-id" select="pcz:patch-id(.)" />
    <xsl:variable name="new-dir" select="pcz:get-directory()" />
    <xsl:if test="not(./parent::*/ancestor::*)" >
      <xsl:message><xsl:value-of select="concat('RENAME: ',.,' ',$new-dir,$new-id)" /></xsl:message> <!-- DO NOT REMOVE !!! -->
    </xsl:if>
    <xsl:attribute name="xml:id">
      <xsl:value-of select="$new-id" />
    </xsl:attribute>
  </xsl:template>

  <xsl:template match="/tei:tagUsage"/> <!-- removing tagUsage - statistics can change-->

  <xsl:template match="/tei:TEI | /tei:TEI/tei:text">
    <xsl:copy>
      <xsl:apply-templates select="@*"/>
      <xsl:attribute name="ana">
        <xsl:if test="./@ana"><xsl:value-of select="concat(./@ana,' ')" /></xsl:if>
        <xsl:choose>
          <xsl:when test="$date &lt; 20191100 ">
            <xsl:text>#reference</xsl:text>
          </xsl:when>
          <xsl:otherwise>
            <xsl:text>#covid</xsl:text>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:attribute>
      <xsl:apply-templates select="node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="/*/tei:teiHeader">
    <xsl:copy>
      <xsl:apply-templates select="@*"/>
      <xsl:apply-templates select="./tei:fileDesc"/>
      <xsl:apply-templates select="./tei:encodingDesc"/>
      <xsl:apply-templates select="./tei:profileDesc"/>
      <xsl:apply-templates select="./tei:revisionDesc"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="tei:recordingStmt"> <!-- IDs are not changed -->
    <xsl:copy-of select="." />
  </xsl:template>

  <xsl:template match="/tei:TEI/tei:teiHeader/tei:encodingDesc">
    <xsl:copy>
      <xsl:apply-templates select="@*"/>
      <xsl:apply-templates select="./tei:projectDesc"/>
      <xsl:apply-templates select="./tei:tagsDecl"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="//tei:encodingDesc/tei:projectDesc">
    <xsl:copy>
      <p xml:lang="cs"><ref target="https://www.clarin.eu/content/parlamint">ParlaMint</ref></p>
      <p xml:lang="en"><ref target="https://www.clarin.eu/content/parlamint">ParlaMint</ref> is a project that aims to (1) create a multilingual set of comparable corpora of parliamentary proceedings uniformly encoded according to the <ref target="https://github.com/clarin-eric/parla-clarin">Parla-CLARIN recommendations</ref> and covering the COVID-19 pandemic from November 2019 as well as the earlier period from 2015 to serve as a reference corpus; (2) process the corpora linguistically to add Universal Dependencies syntactic structures and Named Entity annotation; (3) make the corpora available through concordancers and Parlameter; and (4) build use cases in Political Sciences and Digital Humanities based on the corpus data.</p>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="//tei:fileDesc/tei:titleStmt/tei:title[@type='main' and @xml:lang='cs']">
    <xsl:copy><xsl:apply-templates select="@*"/>Český parlamentní korpus ParlaMint-CZ<xsl:call-template name="teiHeaderInterfix" /> [ParlaMint<xsl:value-of select="substring-after(.,'[ParCzech')" /></xsl:copy>
  </xsl:template>
  <xsl:template match="//tei:fileDesc/tei:titleStmt/tei:title[@type='main' and @xml:lang='en']">
    <xsl:copy><xsl:apply-templates select="@*"/>Czech parliamentary corpus ParlaMint-CZ<xsl:call-template name="teiHeaderInterfix" /> [ParlaMint<xsl:value-of select="substring-after(.,'[ParCzech')" /></xsl:copy>
  </xsl:template>
  <xsl:template match="//tei:fileDesc/tei:titleStmt/tei:title[@type='short' and @xml:lang='cs']">
    <xsl:message>Removing short title: <xsl:value-of select="./text()" /></xsl:message>
  </xsl:template>
  <xsl:template name="teiHeaderInterfix">
    <xsl:if test="/tei:TEI">
      <xsl:value-of select="concat(', ',//tei:sourceDesc/tei:bibl[1]/tei:date/@when,' ',/*/@xml:id)" />
    </xsl:if>
  </xsl:template>

  <xsl:template match="//tei:fileDesc/tei:titleStmt/tei:funder[1]">
    <xsl:element name="funder">
      <orgName xml:lang="en">CLARIN research infrastructure</orgName>
      <orgName xml:lang="cs">Výzkumná infrastruktura CLARIN</orgName>
    </xsl:element>
    <xsl:copy-of select="."/>
  </xsl:template>

  <xsl:template match="//tei:fileDesc/tei:editionStmt/tei:edition">
    <xsl:element name="edition">2.0</xsl:element>
  </xsl:template>
  <xsl:template match="//tei:fileDesc/tei:publicationStmt">
    <xsl:copy>
            <publisher>
               <orgName xml:lang="en">CLARIN research infrastructure</orgName>
               <orgName xml:lang="cs">Výzkumná infrastruktura CLARIN</orgName>
               <ref target="https://www.clarin.eu/">www.clarin.eu</ref>
            </publisher>
            <xsl:choose>
              <xsl:when test="$handler">
                <idno type="URI" subtype="handle"><xsl:value-of select="$handler" /></idno>
              </xsl:when>
              <xsl:otherwise>
                <idno type="URI">https://github.com/clarin-eric/ParlaMint</idno>
              </xsl:otherwise>
            </xsl:choose>

            <availability status="free">
               <licence>http://creativecommons.org/licenses/by/4.0/</licence>
               <p xml:lang="en">This work is licensed under the <ref target="http://creativecommons.org/licenses/by/4.0/">Creative Commons Attribution 4.0 International License</ref>.</p>
               <p xml:lang="cs">Toto dílo je licencováno <ref target="http://creativecommons.org/licenses/by/4.0/">Creative Commons Uveďte původ 4.0 Mezinárodní Veřejná licence</ref>.</p>
            </availability>
            <date><xsl:attribute name="when" select="substring(current-date(),1,10)"/>RELEASE_DATE</date> <!-- use current date to pass ParlaMint validation -->
    </xsl:copy>
  </xsl:template>

  <xsl:template match="@*|element()|comment()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="text()">
    <xsl:if test="starts-with(., ' ') and preceding-sibling::*">
      <xsl:text> </xsl:text>
    </xsl:if>
    <xsl:value-of select="normalize-space(.)"/>
    <xsl:if test="ends-with(., ' ') and following-sibling::* ">
      <xsl:text> </xsl:text>
    </xsl:if>


  </xsl:template>

  <xsl:template name="remove-prefix">
    <xsl:param name="prefix" />
    <xsl:variable name="before" select="substring-before(concat(' ',.),concat(' ',$prefix,':'))" />
    <xsl:variable name="after" select="substring-after(substring-after(concat(' ',.),concat(' ',$prefix,':')),' ')" />
    <xsl:variable name="result" select="normalize-space(concat($before,' ',$after))" />
    <xsl:if test="$result">
      <xsl:copy><xsl:value-of select="$result" /></xsl:copy>
    </xsl:if>
  </xsl:template>

</xsl:stylesheet>