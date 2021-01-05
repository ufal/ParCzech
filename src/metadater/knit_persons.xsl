<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns="http://www.tei-c.org/ns/1.0">
  <xsl:output method="xml" indent="yes" encoding="UTF-8" />
  <xsl:param name="personlist-path" />

  <xsl:variable name="personlist-doc" select="document($personlist-path)" />
  <xsl:key name="id-personlist" match="*[local-name(.) = 'person']" use="@*[local-name(.) = 'id']" />

  <xsl:template match="/*/*[local-name(.) = 'teiHeader']//*[local-name(.) = 'listPerson']/*[local-name(.) = 'person' and @corresp]">
    <xsl:variable name="person-id" select="substring-after(./@corresp, '#')"/>
    <xsl:copy-of select="key('id-personlist',$person-id,$personlist-doc)/." />
  </xsl:template>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>