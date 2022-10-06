<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  exclude-result-prefixes="tei" >

  <xsl:output method="xml" indent="yes" encoding="UTF-8" />

  <xsl:template match="tei:listPerson"> <!-- listOrg using different sorting -->
    <xsl:copy>
      <xsl:apply-templates select="@*" />
      <xsl:apply-templates select="node()">
        <xsl:sort select="@xml:id" data-type="text" order="ascending"/>
      </xsl:apply-templates>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="tei:listRelation">
    <xsl:copy>
      <xsl:apply-templates select="@*" />
      <xsl:apply-templates select="tei:relation">
        <xsl:sort select="concat(@name,' ', @from)" data-type="text" order="ascending"/>
      </xsl:apply-templates>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>