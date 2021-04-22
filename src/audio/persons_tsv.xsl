<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:fo="http://www.w3.org/1999/XSL/Format"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0">
    <xsl:output method="text" omit-xml-declaration="yes" indent="no"/>
    <xsl:template match="/tei:teiCorpus">
        <xsl:text>id&#x9;</xsl:text>
        <xsl:text>surname&#x9;</xsl:text>
        <xsl:text>forename&#x9;</xsl:text>
        <xsl:text>gender&#x9;</xsl:text>
        <xsl:text>birth&#xA;</xsl:text>
        <xsl:apply-templates select=".//tei:person" />
    </xsl:template>

    <xsl:template match="tei:person">
        <xsl:value-of select="./@xml:id"/>
        <xsl:text>&#x9;</xsl:text>
        <xsl:value-of select="./tei:persName/tei:surname"/>
        <xsl:text>&#x9;</xsl:text>
        <xsl:value-of select="./tei:persName/tei:forename"/>
        <xsl:text>&#x9;</xsl:text>
        <xsl:value-of select="./tei:sex/@value"/>
        <xsl:text>&#x9;</xsl:text>
        <xsl:value-of select="./tei:birth/@when"/>
        <xsl:text>&#xA;</xsl:text>
    </xsl:template>
</xsl:stylesheet>