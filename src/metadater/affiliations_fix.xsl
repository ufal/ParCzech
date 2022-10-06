<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  xmlns:xi="http://www.w3.org/2001/XInclude"
  exclude-result-prefixes="tei" >
  <xsl:param name="doc-orgList" />

  <xsl:output method="xml" indent="yes" encoding="UTF-8" />

  <xsl:template match="tei:affiliation">
    <xsl:variable name="ref" select="substring-after(@ref,'#')" />
    <xsl:copy>
      <xsl:choose>
        <xsl:when test="//tei:event[@xml:id=$ref]">
          <xsl:attribute name="ref"><xsl:value-of select="concat('#',//tei:event[@xml:id=$ref]/ancestor::tei:org/@xml:id)"/></xsl:attribute>
          <xsl:attribute name="ana"><xsl:value-of select="concat('#',$ref)"/></xsl:attribute>
        </xsl:when>
        <xsl:otherwise>
          <xsl:apply-templates select="@ref" />
        </xsl:otherwise>
      </xsl:choose>
      <xsl:apply-templates select="@role | @to | @from | @ana" />
      <xsl:apply-templates select="node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>