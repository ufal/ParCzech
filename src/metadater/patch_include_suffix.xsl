<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  xmlns:xi="http://www.w3.org/2001/XInclude"
  exclude-result-prefixes="tei" >

  <xsl:output method="xml" indent="yes" encoding="UTF-8" />
  <xsl:param name="remove" />
  <xsl:param name="append" />

  <xsl:template match="/tei:teiCorpus/xi:include">
    <xsl:element name="xi:include">
      <xsl:apply-templates select="@*"/>
      <xsl:attribute name="href">
        <xsl:value-of select="concat(substring-before(./@href,$remove),$append)"/>
      </xsl:attribute>
    </xsl:element>
  </xsl:template>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>