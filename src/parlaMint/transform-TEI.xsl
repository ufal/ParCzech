<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  exclude-result-prefixes="tei" >

  <xsl:output method="xml" indent="yes" encoding="UTF-8" />

  <xsl:include href="parczech2parlamint.xsl" />


  <xsl:template match="//tei:linkGrp[@type='UD-SYN']/tei:link/@target">
    <xsl:param name="headid" select="substring-after(substring-before(.,' '),'#')" />
    <xsl:param name="argumentid" select="substring-after(substring-after(.,' '),'#')" />
    <xsl:attribute name="target">
      <xsl:value-of select="concat('#',$id-prefix,'_',$set-date,'_', $headid,' #',$id-prefix,'_',$set-date,'_', $argumentid)" />
    </xsl:attribute>
  </xsl:template>

  <xsl:template match="//tei:note[@type='media']">
    <xsl:message>TEMPORARY REMOVING //note[./media]: <xsl:value-of select="./tei:media/@url" /></xsl:message>
  </xsl:template>

  <xsl:template match="//tei:div//tei:ref">
    <xsl:message>TEMPORARY REMOVING //div//ref: <xsl:value-of select="./@target" /></xsl:message>
    <xsl:apply-templates select="node()"/>
  </xsl:template>

  <xsl:template match="//tei:seg//tei:name[not(@type)]">
    <xsl:message>TEMPORARY REMOVING not typed name: <xsl:value-of select="./@ana" /></xsl:message>
    <xsl:apply-templates select="node()"/>
  </xsl:template>
  <xsl:template match="//tei:seg//tei:name[@type]">
    <xsl:message>TEMPORARY REMOVING ana from name: <xsl:value-of select="./@ana" /></xsl:message>
    <xsl:copy>
      <xsl:apply-templates select="@*[not(local-name()='ana')]" />
      <xsl:apply-templates select="node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="//tei:w/@pos" />  <!-- removing  w/@pos -->
  <xsl:template match="//tei:pc/@pos" /> <!-- removing pc/@pos -->
  <xsl:template match="//tei:pc/@lemma">
  <!--  <xsl:message>REMOVING pc/@lemma - TODO: do this in udpipe?</xsl:message> -->
  </xsl:template> <!-- removing pc/@lemma -->

  <xsl:template name="patch-id">
    <xsl:param name="id" />
    <xsl:attribute name="xml:id">
      <xsl:value-of select="concat($id-prefix,'_',$set-date,'_', $id)" />
    </xsl:attribute>
  </xsl:template>



</xsl:stylesheet>