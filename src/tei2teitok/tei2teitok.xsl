<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns="teitok:parczech">
  <xsl:output method="xml" indent="no" encoding="UTF-8" />
  <xsl:param name="personlist-path" />

  <xsl:variable name="personlist-doc" select="document($personlist-path)" />
  <xsl:key name="id-personlist" match="person" use="@*[local-name(.) = 'id']" />

  <xsl:variable name="pdt-fslib" select="concat('./',substring-before(//prefixDef[@ident='pdt']/@replacementPattern,'#'))"/>
  <xsl:variable name="pdt-fslib-doc" select="document($pdt-fslib)"/>
  <xsl:key name="id-pdt-fslib" match="fs" use="@*[local-name(.) = 'id']"/>

  <xsl:variable name="ne-fslib" select="concat('./',substring-before(//prefixDef[@ident='ne']/@replacementPattern,'#'))"/>
  <xsl:variable name="ne-fslib-doc" select="document($ne-fslib)"/>
  <xsl:key name="id-ne-fslib-fs" match="fs" use="@*[local-name(.) = 'id']"/>
  <xsl:key name="id-ne-fslib-f" match="f" use="@*[local-name(.) = 'id']"/>

  <!-- TODO - add annotation to header (NOTE that it is not TEI format !!!) -->

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
        <!-- <xsl:value-of select="$pdt-fslib-doc/div/fvLib/fs[@*[local-name(.) = 'id'] = $tag ]/f[@name = 'pdt']/symbol/@value"/> -->
        <xsl:value-of select="key('id-pdt-fslib', $tag, $pdt-fslib-doc)/f[@name = 'pdt']/symbol/@value"/>
      </xsl:attribute>

      <xsl:apply-templates select="node()"/>
    </xsl:element>
  </xsl:template>

  <!-- rename name to NamedEntity and decode ana to type -->
  <xsl:template match="*[local-name(.) = 'name' ]">
    <xsl:element name="NamedEntity">
      <xsl:apply-templates select="@*[local-name(.) = 'id']"/> <!-- ID -->

      <xsl:variable name="netag" select="substring-before(substring-after(concat(@ana,' '),'ne:'), ' ')"/>

      <xsl:attribute name="type"> <!-- type -->
        <xsl:call-template name="expandEntityFeats">
          <!-- <xsl:with-param name="feats" select="concat($ne-fslib-doc/div/fvLib/fs[@*[local-name(.) = 'id'] = $netag ]/@*[local-name(.) = 'feats'],' ')"/> -->
          <xsl:with-param name="feats" select="concat(key('id-ne-fslib-fs',$netag, $ne-fslib-doc)/@*[local-name(.) = 'feats'],' ')"/>
        </xsl:call-template>
      </xsl:attribute>

      <xsl:apply-templates select="node()"/>
    </xsl:element>
  </xsl:template>





<!-- LINKING -->

  <!-- rename ref to a -->
  <xsl:template match="*[local-name(.) = 'ref' ]">
    <xsl:element name="a">
      <xsl:apply-templates select="@*[local-name(.) = 'id']"/> <!-- ID -->
      <xsl:attribute name="href"> <!-- copy source -->
        <xsl:value-of select="@source"/>
      </xsl:attribute>
      <xsl:attribute name="type"> <!-- copy ana -->
        <xsl:value-of select="substring-after(@ana, '#')"/>
      </xsl:attribute>
      <xsl:attribute name="target">_blank</xsl:attribute>
      <xsl:apply-templates select="node()"/>
    </xsl:element>
  </xsl:template>

  <!-- person link -->
  <xsl:template match="*[local-name(.) = 'note' and @type='speaker' and starts-with(./following-sibling::u[1]/@who, '#')]">
    <xsl:element name="{local-name(.)}">
      <xsl:apply-templates select="@*"/> <!-- copy attributes -->
      <xsl:apply-templates select="node()"/>
      <xsl:variable name="person" select="substring-after(./following-sibling::u[1]/@who, '#')"/>

      <xsl:call-template name="externalLink">
        <xsl:with-param name="link" select="normalize-space(key('id-personlist',$person,$personlist-doc)/idno[@type='URI'])"/>
      </xsl:call-template>

    </xsl:element>
  </xsl:template>


  <!-- speech link -->
  <xsl:template match="*[local-name(.) = 'u' and @source]">
    <xsl:element name="{local-name(.)}">
      <xsl:apply-templates select="@*"/> <!-- copy attributes -->
      <xsl:call-template name="externalLink">
        <xsl:with-param name="link" select="@source"/>
      </xsl:call-template>
      <xsl:apply-templates select="node()"/>
    </xsl:element>
  </xsl:template>

  <!-- page link -->
  <xsl:template match="*[local-name(.) = 'pb' and @source]">
    <xsl:element name="{local-name(.)}">
      <xsl:apply-templates select="@*"/> <!-- copy attributes -->
      <xsl:call-template name="externalLink">
        <xsl:with-param name="link" select="@source"/>
        <xsl:with-param name="additionalClasses" select='"page-link"' />
      </xsl:call-template>
      <xsl:apply-templates select="node()"/>
    </xsl:element>
  </xsl:template>

<!-- ================================================ -->
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

 <!-- named templates -->
  <xsl:template name="expandEntityFeats">
    <xsl:param name="feats" />
    <xsl:if test="string-length($feats) &gt; 0">
      <xsl:variable name="v" select="substring-after(substring-before($feats, ' '),'#')"/>
      <!-- <xsl:value-of select="$ne-fslib-doc/div/fLib/f[@*[local-name(.) = 'id'] = $v ]/string"/> -->
      <xsl:value-of select="key('id-ne-fslib-f',$v, $ne-fslib-doc)/string"/>
      <xsl:variable name="nextfeats" select="substring-after($feats, ' ')"/>
      <xsl:if test="string-length($nextfeats) &gt; 0">
        <xsl:text> - </xsl:text>
      </xsl:if>
      <xsl:call-template name="expandEntityFeats">
        <xsl:with-param name="feats" select="$nextfeats"/>
      </xsl:call-template>
    </xsl:if>
  </xsl:template>
  <xsl:template name="externalLink">
    <xsl:param name="link" />
    <xsl:param name="additionalClasses" />
    <xsl:element name="a">
      <xsl:attribute name="href">
        <xsl:value-of select="$link"/>
      </xsl:attribute>
      <xsl:attribute name="target">_blank</xsl:attribute>
      <xsl:attribute name="class"><xsl:value-of select="normalize-space(concat('external-link ',$additionalClasses))" /></xsl:attribute>
    </xsl:element>
  </xsl:template>

</xsl:stylesheet>