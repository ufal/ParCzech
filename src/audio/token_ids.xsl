<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:fo="http://www.w3.org/1999/XSL/Format"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0">
    <xsl:output method="text" omit-xml-declaration="yes" indent="no"/>
    <xsl:template match="tei:pb">
        <xsl:text># AUDIO: </xsl:text>
        <xsl:variable name="audio-id" select="substring-after(@corresp,'#')" />
        <xsl:value-of select="//tei:media[@xml:id=$audio-id]/@source" />
        <xsl:text>&#xA;</xsl:text>
    </xsl:template>

    <xsl:template match="*[local-name(.) = 's']">
        <xsl:apply-templates />
        <xsl:text>&#xA;</xsl:text>
    </xsl:template>
    <xsl:template match="*[local-name(.) = 'w' or local-name(.) = 'pc' ]">
        <xsl:value-of select="concat(text(),'&#x9;',@*[local-name(.) = 'id'])"/>
        <xsl:value-of select="concat('&#x9;',substring-after(ancestor::tei:u/@who,'#'))"/><!-- speaker ID -->
        <xsl:value-of select="string('&#xA;')"/>
    </xsl:template>
    <xsl:template match="text()" />
</xsl:stylesheet>