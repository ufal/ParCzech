<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  exclude-result-prefixes="tei">

  <xsl:output method="xml" indent="yes" encoding="UTF-8" />
  <xsl:param name="personlist-path" />

  <xsl:variable name="personlist-doc" select="document($personlist-path)" />
  <xsl:key name="id-personlist" match="*[local-name(.) = 'person' and not(@corresp)]" use="@*[local-name(.) = 'id']" />
  <xsl:key name="id-personlist-corresp" match="*[local-name(.) = 'person' and @corresp]" use="@*[local-name(.) = 'id']" />

  <xsl:template match="/*/*[local-name(.) = 'teiHeader']//*[local-name(.) = 'listPerson']/*[local-name(.) = 'person' and @corresp]">
    <xsl:variable name="person-id" select="substring-after(./@corresp, '#')"/>
    <xsl:variable name="node" select="key('id-personlist',$person-id,$personlist-doc)/."/>
    <xsl:copy-of select="$node" />
    <xsl:if test="not($node)">
      <xsl:variable name="corresp" select="key('id-personlist-corresp',$person-id,$personlist-doc)"/>
      <xsl:variable name="node" select="key('id-personlist',substring-after($corresp/@corresp,'#'),$personlist-doc)/."/>
      <xsl:if test="not(//*[local-name(.) = 'person' and contains(@corresp,$corresp/@corresp) ])">
        <!-- traversed node is new -->
        <xsl:copy-of select="$node" />
      </xsl:if>
      <xsl:if test="not($node)">
        <!-- not found - just copy to output -->
        <xsl:copy>
          <xsl:apply-templates select="@*|node()"/>
        </xsl:copy>
      </xsl:if>
    </xsl:if>
  </xsl:template>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

</xsl:stylesheet>