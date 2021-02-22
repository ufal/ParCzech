<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  xmlns:pcz="http://ufal.mff.cuni.cz/parczech/ns/1.0"
  exclude-result-prefixes="tei pcz" >

  <xsl:output method="xml" indent="yes" encoding="UTF-8" />

  <xsl:include href="parczech2parlamint.xsl" />
  <xsl:variable name="id-prefix-extended" select="concat($id-prefix,'_',$set-date,'-')" />

  <xsl:template match="//tei:linkGrp[@type='UD-SYN']/tei:link/@target">
    <xsl:param name="headid" select="substring-after(substring-before(.,' '),'#')" />
    <xsl:param name="argumentid" select="substring-after(substring-after(.,' '),'#')" />
    <xsl:attribute name="target">
      <xsl:value-of select="concat('#',$id-prefix-extended, $headid,' #',$id-prefix-extended, $argumentid)" />
    </xsl:attribute>
  </xsl:template>


  <xsl:template match="//tei:div//tei:ref">
    <xsl:message>TEMPORARY REMOVING //div//ref: <xsl:value-of select="./@target" /></xsl:message>
    <xsl:call-template name="add-only-childnodes" />
  </xsl:template>

  <xsl:template match="tei:s"><xsl:copy><xsl:apply-templates select="@*|element()"/></xsl:copy></xsl:template>
  <!--
  <xsl:template match="//tei:seg//tei:*[not(local-name(..) = 'node') and starts-with(@ana,'ne:') and contains(' ref email num age unit measure time date ',concat(' ',local-name(),' ') ) ]">
    <xsl:message>TEMPORARY RENAMING <xsl:value-of select="local-name()" /> to name</xsl:message>
    <xsl:text>&#xA;</xsl:text><xsl:comment>BEGIN <xsl:value-of select="local-name()" /></xsl:comment><xsl:text>&#xA;</xsl:text>
    <xsl:element name="name">
      <xsl:apply-templates select="@*" />
      <xsl:apply-templates select="node()"/>
    </xsl:element>
    <xsl:text>&#xA;</xsl:text><xsl:comment>END <xsl:value-of select="local-name()" /></xsl:comment><xsl:text>&#xA;</xsl:text>
  </xsl:template>
-->

  <xsl:template match="//tei:*[local-name() = 'w' or local-name() = 'pc']/@ana">
    <xsl:call-template name="remove-prefix">
      <xsl:with-param name="prefix" select="string('pdt')" />
    </xsl:call-template>
  </xsl:template>

  <xsl:template match="//tei:w/@pos" />  <!-- removing  w/@pos -->
  <xsl:template match="//tei:pc/@pos" /> <!-- removing pc/@pos -->
  <xsl:template match="//tei:pc/@lemma">
  <!--  <xsl:message>REMOVING pc/@lemma - TODO: do this in udpipe?</xsl:message> -->
  </xsl:template> <!-- removing pc/@lemma -->

  <xsl:function name="pcz:patch-id">
    <xsl:param name="id" />
    <xsl:value-of select="concat($id-prefix-extended, $id)" />
  </xsl:function>

  <xsl:template name="add-only-childnodes">
    <xsl:if test="./self::*[preceding-sibling::node()[1][self::text()][ends-with(., ' ')]] ">
      <xsl:message><xsl:value-of select="concat('|',./preceding-sibling::text()[1],'|')" /></xsl:message>
      <xsl:text> </xsl:text>
    </xsl:if>
    <xsl:apply-templates select="node()"/>
    <xsl:if test="./self::*[following-sibling::node()[1][self::text()][starts-with(., ' ')]] ">
      <xsl:message><xsl:value-of select="concat('|',./following-sibling::text()[1],'|')" /></xsl:message>
      <xsl:text> </xsl:text>
    </xsl:if>
  </xsl:template>


</xsl:stylesheet>