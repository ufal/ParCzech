<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  exclude-result-prefixes="tei" >

  <xsl:output method="xml" indent="yes" encoding="UTF-8" />
  <xsl:param name="id-prefix" />
  <xsl:variable name="set-date" select="/tei:TEI//tei:settingDesc/tei:setting/tei:date[contains(concat(' ',./@ana,' '),' #parla.sitting ')]/@when"/>
  <xsl:variable name="date" select="translate($set-date, '-','')"/>



  <xsl:template match="@xml:id">
    <xsl:call-template name="patch-id">
      <xsl:with-param name="id" select="."/>
    </xsl:call-template>

  </xsl:template>

  <xsl:template match="/tei:TEI">
    <xsl:copy>
      <xsl:apply-templates select="@*"/>
      <xsl:attribute name="ana">
        <xsl:if test="./@ana"><xsl:value-of select="concat(./@ana,' ')" /></xsl:if>
        <xsl:choose>
          <xsl:when test="$date &lt; 20191000 ">
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
            <idno type="URL">https://github.com/clarin-eric/ParlaMint</idno>
            <pubPlace><ref target="https://github.com/clarin-eric/ParlaMint">https://github.com/clarin-eric/ParlaMint</ref></pubPlace>

            <availability status="free">
               <licence>http://creativecommons.org/licenses/by/4.0/</licence>
               <p xml:lang="en">This work is licensed under the <ref target="http://creativecommons.org/licenses/by/4.0/">Creative Commons Attribution 4.0 International License</ref>.</p>
               <p xml:lang="cs">Toto dílo je licencováno <ref target="http://creativecommons.org/licenses/by/4.0/">Creative Commons Uveďte původ 4.0 Mezinárodní Veřejná licence</ref>.</p>
            </availability>
            <!-- <date when="RELEASE_DATE">RELEASE_DATE</date> -->
    </xsl:copy>
  </xsl:template>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>