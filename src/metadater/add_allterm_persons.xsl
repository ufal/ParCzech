<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  exclude-result-prefixes="tei">

  <xsl:output method="xml" indent="yes" encoding="UTF-8" />
  <xsl:param name="allterm-personlist-path" />
  <xsl:variable name="personlist-doc" select="document($allterm-personlist-path)" />

  <xsl:template match="//*[local-name(.) = 'listPerson']">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
      <xsl:copy-of select="$personlist-doc/tei:listPerson/tei:person" />
    </xsl:copy>
  </xsl:template>

  <xsl:template match="@*|node()[not(local-name(.) = 'listPerson' )]">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>



</xsl:stylesheet>