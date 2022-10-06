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

  <xsl:template match="//*[local-name(.) = 'listPerson']/*[local-name(.) = 'person' and @corresp][1]">
    <xsl:call-template name="template-person">
      <xsl:with-param name="context-node" select="." />
      <xsl:with-param name="seen-ids" select="string(' ')" />
    </xsl:call-template>
  </xsl:template>

  <xsl:template match="@*|node()[not(local-name(.) = 'person') and not(local-name(..) = 'listPerson' )]">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template name="template-person">

    <xsl:param name="context-node" />
    <xsl:param name="seen-ids"/>
    <xsl:variable name="person-id" select="substring-after($context-node/@corresp, '#')"/>
    <xsl:variable name="node" select="key('id-personlist',$person-id,$personlist-doc)/."/>
    <xsl:variable name="next-context" select="$context-node/following-sibling::tei:person[@corresp][1]"/>
    <xsl:choose>
      <xsl:when test="$node">
        <xsl:copy-of select="$node" />
        <xsl:if test="$next-context">
          <xsl:call-template name="template-person">
            <xsl:with-param name="context-node" select="$next-context" />
            <xsl:with-param name="seen-ids" select="$seen-ids" />
          </xsl:call-template>
        </xsl:if>
      </xsl:when>
      <xsl:otherwise>
        <xsl:message>looking for corresp for <xsl:value-of select="$person-id" /></xsl:message>
        <xsl:variable name="corresp" select="key('id-personlist-corresp',$person-id,$personlist-doc)"/>
        <xsl:variable name="existingnode" select="//*[local-name(.) = 'person' and ends-with(@corresp,$corresp/@corresp)]"/>
        <xsl:variable name="node" select="key('id-personlist',substring-after($corresp/@corresp,'#'),$personlist-doc)/."/>

        <xsl:if test="$existingnode">
          <xsl:message>      node exists: <xsl:value-of select="$existingnode/@xml:id" /></xsl:message>
        </xsl:if>
        <xsl:if test="not($existingnode)">
          <xsl:choose>
            <xsl:when test="contains($seen-ids,$node/@xml:id)">
              <xsl:message>      already added <xsl:value-of select="$node/@xml:id" /></xsl:message>
            </xsl:when>
            <xsl:otherwise>
              <xsl:message>      new node <xsl:value-of select="$node/@xml:id" /></xsl:message>
              <xsl:copy-of select="$node" />
            </xsl:otherwise>
          </xsl:choose>
        </xsl:if>
        <xsl:if test="not($node)">
          <!-- not found - just copy to output -->
          <xsl:copy>
            <xsl:apply-templates select="@*|node()"/>
          </xsl:copy>
        </xsl:if>

        <xsl:if test="$next-context">
          <xsl:call-template name="template-person">
            <xsl:with-param name="context-node" select="$next-context" />
            <xsl:with-param name="seen-ids" select="concat($seen-ids,$node/@xml:id,' ')" />
          </xsl:call-template>
        </xsl:if>
      </xsl:otherwise>
    </xsl:choose>



  </xsl:template>

</xsl:stylesheet>