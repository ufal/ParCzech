<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
xmlns:fo="http://www.w3.org/1999/XSL/Format" >
    <xsl:output method="text" omit-xml-declaration="yes" indent="no"/>
    <xsl:template match="*[local-name(.) = 'media' and @mimeType='audio/mp3']">
        <xsl:text># AUDIO: </xsl:text>
        <xsl:value-of select="./@url" />
        <xsl:text>&#xA;</xsl:text>
    </xsl:template>

    <xsl:template match="*[local-name(.) = 's']">
        <xsl:apply-templates />
        <xsl:text>&#xA;</xsl:text>
    </xsl:template>
    <xsl:template match="*[local-name(.) = 'w' or local-name(.) = 'pc' ]">
        <xsl:value-of select="concat(text(),'&#x9;',@*[local-name(.) = 'id'],'&#xA;')"/>
    </xsl:template>
    <xsl:template match="text()" />
</xsl:stylesheet>