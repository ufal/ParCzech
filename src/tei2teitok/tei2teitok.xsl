<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns="teitok:parczech">
  <xsl:output method="xml" indent="no" encoding="UTF-8" />
  <xsl:param name="corpus-path" />

  <xsl:variable name="corpus-doc" select="document($corpus-path)" />
  <xsl:key name="id-personlist" match="*[local-name(.) = 'person']" use="@*[local-name(.) = 'id']" />



<!--
  <xsl:variable name="pdt-fslib" select="concat('./',substring-before(//*[local-name(.) = 'prefixDef' and @ident='pdt']/@replacementPattern,'#'))"/>
  <xsl:variable name="pdt-fslib-doc" select="document($pdt-fslib)"/>
  <xsl:key name="id-pdt-fslib" match="*[local-name(.) = 'fs']" use="@*[local-name(.) = 'id']"/>

  <xsl:variable name="ne-fslib" select="concat('./',substring-before(//*[local-name(.) = 'prefixDef' and @ident='ne']/@replacementPattern,'#'))"/>
  <xsl:variable name="ne-fslib-doc" select="document($ne-fslib)"/>
  <xsl:key name="id-ne-fslib-fs" match="*[local-name(.) = 'fs']" use="@*[local-name(.) = 'id']"/>
  <xsl:key name="id-ne-fslib-f" match="*[local-name(.) = 'f']" use="@*[local-name(.) = 'id']"/>
-->



  <!-- rename w and pc to tok and fix attributes -->
  <xsl:template match="*[local-name(.) = 'w' or local-name(.) = 'pc' ]">
    <xsl:variable name="tokname" select="if ( @norm ) then 'dtok' else 'tok'"/>
    <xsl:element name="{$tokname}">
      <xsl:variable name="tokenid" select="./@*[local-name(.) = 'id']"/>
      <xsl:apply-templates select="@*[local-name(.) = 'id']"/> <!-- ID -->

      <xsl:variable name="form" select="@norm"/>
      <xsl:if test="$form">
        <xsl:attribute name="form"> <!-- norm -> form -->
          <xsl:value-of select="$form"/>
        </xsl:attribute>
      </xsl:if>

      <xsl:copy-of select="@lemma"/> <!-- copy LEMMA -->

      <xsl:variable name="upos" select="@pos"/>
      <xsl:if test="$upos">
        <xsl:attribute name="upos"> <!-- copy POS -->
          <xsl:value-of select="$upos"/>
        </xsl:attribute>
      </xsl:if>

      <xsl:variable name="feats" select="substring-after(@msd,'|')"/>
      <xsl:if test="$feats">
        <xsl:attribute name="feats">  <!-- clean MSD from UposTag-->
          <xsl:value-of select="$feats"/>
        </xsl:attribute>
      </xsl:if>

      <xsl:variable name="xpos" select="substring-before(substring-after(concat(@ana,' '),'pdt:'), ' ')"/>
      <xsl:if test="$xpos">
        <xsl:attribute name="xpos"> <!-- xpos -->
          <xsl:value-of select="$xpos" />
        </xsl:attribute>
      </xsl:if>

      <xsl:variable name="relation" select="./ancestor::*[local-name(.) = 's']/*[local-name(.) = 'linkGrp' and @targFunc='head argument' and @type='UD-SYN']/*[local-name(.) = 'link' and ends-with(@target, concat('#',$tokenid))]"/>

      <xsl:variable name="deprel" select="substring-before(substring-after(concat($relation/@ana,' '),'ud-syn:'), ' ')"/>

      <xsl:if test="$deprel">
        <xsl:attribute name="dep"> <!-- dependency relation-->
          <xsl:value-of select="$deprel"/>
        </xsl:attribute>
        <xsl:if test="$deprel != 'root'">
          <xsl:attribute name="head"> <!-- dependency head if not root-->
            <xsl:value-of select="substring-before(substring-after($relation/@target,'#'), ' ')"/>
          </xsl:attribute>
        </xsl:if>
      </xsl:if>
      <xsl:apply-templates select="node()"/>
    </xsl:element>
  </xsl:template>

  <!-- remove dependency linkGrp -->
  <xsl:template match="*[local-name(.) = 's']/*[local-name(.) = 'linkGrp' and @targFunc='head argument' and @type='UD-SYN']" />

<!-- Named Entities -->
  <xsl:template match="*[local-name(.) = 'name' ]">
    <xsl:element name="namedEntity">
      <xsl:apply-templates select="@*[local-name(.) = 'id']"/> <!-- ID -->
      <xsl:variable name="ne" select="substring-before(substring-after(concat(@ana,' '),'ne:'), ' ')"/>
      <xsl:if test="$ne">
        <xsl:attribute name="category"> <!-- ne shortcut -->
          <xsl:value-of select="$ne" />
        </xsl:attribute>
          <xsl:variable name="cat" select="//*[@*[local-name(.) = 'id'] = 'NER.cnec2.0']//*[@*[local-name(.) = 'id'] = $ne]" />
          <xsl:variable name="parentcat" select="$cat/parent::*[local-name(.) = 'category']" />
        <xsl:attribute name="label"> <!-- label for users -->
          <xsl:if test="$parentcat">
            <xsl:value-of select="concat($parentcat/*[local-name(.) = 'catDesc']/text(), ' - ')" />
          </xsl:if>
          <xsl:value-of select="$cat/*[local-name(.) = 'catDesc']/text()" />
        </xsl:attribute>
      </xsl:if>
      <xsl:apply-templates select="node()"/>
    </xsl:element>
  </xsl:template>




<!-- HYPERTEXT LINKING -->

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
  <xsl:template match="*[local-name(.) = 'note' and @type='speaker' and @target]">
    <xsl:element name="{local-name(.)}">
      <xsl:apply-templates select="@*"/> <!-- copy attributes -->
      <xsl:apply-templates select="node()"/>
      <xsl:variable name="person" select="substring-after(./@target, '#')"/>

      <xsl:call-template name="externalLink">
        <xsl:with-param name="link" select="normalize-space(key('id-personlist',$person,$corpus-doc)/*[local-name(.) = 'idno' and @type='URI'])"/>
        <xsl:with-param name="additionalClasses" select='"person-link"' />
      </xsl:call-template>

    </xsl:element>
  </xsl:template>


  <!-- speech link -->
  <xsl:template match="*[local-name(.) = 'u' and @source]">
    <xsl:element name="{local-name(.)}">
      <xsl:apply-templates select="@*"/> <!-- copy attributes -->
      <xsl:call-template name="externalLink">
        <xsl:with-param name="link" select="@source"/>
        <xsl:with-param name="additionalClasses" select='"speech-link"' />
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

<!-- ==================== CLEANING ============================ -->

  <!-- removing taxonomy -->
  <xsl:template match="*[local-name() = 'teiHeader']/*[local-name() = 'encodingDesc']/*[local-name() = 'classDecl']" />
  <!-- removing prefixes -->
  <xsl:template match="*[local-name() = 'teiHeader']/*[local-name() = 'encodingDesc']/*[local-name() = 'listPrefixDef']" />
  <!--  add annotation to header (NOTE that it is not TEI format !!!) -->
  <xsl:template match="*[local-name() = 'teiHeader']/*[local-name() = 'encodingDesc']">
    <xsl:element name="encodingDesc">
      <xsl:element name="p">
        <xsl:text>This file is designed to use in TEITOK</xsl:text>
      </xsl:element>
      <xsl:apply-templates select="node()"/>
    </xsl:element>
  </xsl:template>

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