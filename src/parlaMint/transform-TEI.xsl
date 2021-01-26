<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  exclude-result-prefixes="tei" >

  <xsl:output method="xml" indent="yes" encoding="UTF-8" />

  <xsl:include href="parczech2parlamint.xsl" />

  <xsl:template match="//tei:note[@type='media']">
    <xsl:message>TEMPORARY REMOVING //note[./media]: <xsl:value-of select="./tei:media/@url" /></xsl:message>
  </xsl:template>

  <xsl:template match="//tei:div//tei:ref">
    <xsl:message>TEMPORARY REMOVING //div//ref: <xsl:value-of select="./@target" /></xsl:message>
    <xsl:apply-templates select="node()"/>
  </xsl:template>

  <xsl:template name="patch-id">
    <xsl:param name="id" />
    <xsl:attribute name="xml:id">
      <xsl:value-of select="concat($id-prefix,'_',$set-date,'_', $id)" />
    </xsl:attribute>
  </xsl:template>



</xsl:stylesheet>