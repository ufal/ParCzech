<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="2.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  xmlns:xi="http://www.w3.org/2001/XInclude"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  exclude-result-prefixes="tei xs" >
  <xsl:param name="prefix" />
  <xsl:param name="element" />

  <xsl:output method="xml" indent="yes" encoding="UTF-8" />

  <xsl:template match="//*[local-name(.) = $element]">
    <xsl:variable name="path" select="concat($prefix,$element,'.xml')"/>
    <xsl:message select="concat('Saving ',$element, ' to ',$path)"/>
    <xsl:result-document href="{$path}" method="xml">
         <xsl:copy-of select="." copy-namespaces="no"/>
      </xsl:result-document>
  </xsl:template>

  <xsl:template match="@*|node()[not(local-name(.) = $element )]">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>