<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns="http://www.tei-c.org/ns/1.0">
  <xsl:output method="xml" indent="yes" encoding="UTF-8" />
  <xsl:param name="org-path" />

  <xsl:variable name="org-doc" select="document($org-path)" />
  <xsl:key name="id-personlist" match="*[local-name(.) = 'person']" use="@*[local-name(.) = 'id']" />

  <xsl:template match="/*/*[local-name(.) = 'teiHeader']//*[local-name(.) = 'particDesc']">
    <xsl:copy-of select="$org-doc" />
    <xsl:apply-templates select="@*|node()"/>
  </xsl:template>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>