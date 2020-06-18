<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns="teitok:parczech">
  <xsl:output method="xml" indent="yes" encoding="UTF-8" />
  <xsl:variable name="pdt-fslib" select="concat('./',substring-before(//prefixDef[@ident='pdt']/@replacementPattern,'#'))"/>
  <xsl:variable name="ne-fslib" select="concat('./',substring-before(//prefixDef[@ident='ne']/@replacementPattern,'#'))"/>

  <!-- TODO - add annotation to header (NOTE that it is not TEI format !!!) -->

  <!-- remove element namespaces-->
  <xsl:template match="*">
    <xsl:element name="{local-name(.)}">
      <xsl:apply-templates select="@* | node()"/>
    </xsl:element>
  </xsl:template>
  <!-- remove attribute namespaces-->
  <xsl:template match="@*">
    <xsl:attribute name="{local-name(.)}">
      <xsl:value-of select="."/>
    </xsl:attribute>
  </xsl:template>
  <!-- rename w and pc to tok and fix attributes -->
  <xsl:template match="*[local-name(.) = 'w' or local-name(.) = 'pc' ]">
    <xsl:element name="tok">
      <xsl:apply-templates select="@*[local-name(.) = 'id']"/> <!-- ID -->
      <xsl:copy-of select="@lemma"/> <!-- copy LEMMA -->

      <xsl:attribute name="upos"> <!-- copy POS -->
        <xsl:value-of select="@pos"/>
      </xsl:attribute>

      <xsl:attribute name="feats"> <!-- clean MSD from UposTag-->
        <xsl:value-of select="substring-after(@msd,'|')"/>
      </xsl:attribute>

      <xsl:attribute name="xpos"> <!-- xpos -->
        <xsl:variable name="tag" select="substring-before(substring-after(concat(@ana,' '),'pdt:'), ' ')"/>
        <xsl:value-of select="document($pdt-fslib)//*[@*[local-name(.) = 'id'] = $tag ]/f[@name = 'pdt']/symbol/@value"/>
      </xsl:attribute>

      <xsl:apply-templates select="node()"/>
    </xsl:element>
  </xsl:template>

  <!-- rename name to NamedEntity and decode ana to type -->
  <xsl:template match="*[local-name(.) = 'name' ]">
    <xsl:element name="NamedEntity">
      <xsl:apply-templates select="@*[local-name(.) = 'id']"/> <!-- ID -->

      <xsl:attribute name="type"> <!-- type -->
        <xsl:variable name="netag" select="substring-before(substring-after(concat(@ana,' '),'ne:'), ' ')"/>
        <xsl:call-template name="expandEntityFeats">
          <xsl:with-param name="feats" select="concat(document($ne-fslib)//*[@*[local-name(.) = 'id'] = $netag ]/@*[local-name(.) = 'feats'],' ')"/>
        </xsl:call-template>
      </xsl:attribute>

      <xsl:apply-templates select="node()"/>
    </xsl:element>
  </xsl:template>

  <xsl:template name="expandEntityFeats">
    <xsl:param name="feats" />
    <xsl:if test="string-length($feats) &gt; 0">
      <xsl:variable name="v" select="substring-after(substring-before($feats, ' '),'#')"/>
      <xsl:value-of select="document($ne-fslib)//f[@*[local-name(.) = 'id'] = $v ]/string"/>
      <xsl:variable name="nextfeats" select="substring-after($feats, ' ')"/>
      <xsl:if test="string-length($nextfeats) &gt; 0">
        <xsl:text> - </xsl:text>
      </xsl:if>
      <xsl:call-template name="expandEntityFeats">
        <xsl:with-param name="feats" select="$nextfeats"/>
      </xsl:call-template>
    </xsl:if>
  </xsl:template>

</xsl:stylesheet>