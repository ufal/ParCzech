<?xml version="1.0" encoding="UTF8"?>
<xsl:stylesheet version="1.0"
 xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
 <xsl:output method="xml" omit-xml-declaration="no" indent="yes" encoding="UTF8"/>
 <xsl:strip-space elements="*"/>
 <xsl:variable name="person-list" select="document('/var/www/html/teitok/parczech/Resources/person.xml')"/>
   <xsl:template match="node()|@*">
     <xsl:copy>
       <xsl:apply-templates select="node()|@*"/>
     </xsl:copy>
   </xsl:template>
   <xsl:template match="person">
    <xsl:variable name="person-id" select="./@ref"/>
    <xsl:copy-of  select="$person-list//person[@id=$person-id]" />
   </xsl:template>
</xsl:stylesheet>