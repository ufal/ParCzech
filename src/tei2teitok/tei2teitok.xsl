<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  xmlns:pcz="http://ufal.mff.cuni.cz/parczech/ns/1.0"
  exclude-result-prefixes="tei pcz" >
  <xsl:output method="xml" indent="yes" suppress-indentation="s tok name ref email num time date unit p" encoding="UTF-8" />
  <xsl:param name="corpus-path" />

  <xsl:variable name="corpus-doc" select="document($corpus-path)" />
  <xsl:key name="id-personlist" match="*[local-name(.) = 'person']" use="@*[local-name(.) = 'id']" />
  <xsl:variable name="root" select="/"/>


<!--
  <xsl:variable name="pdt-fslib" select="concat('./',substring-before(//*[local-name(.) = 'prefixDef' and @ident='pdt']/@replacementPattern,'#'))"/>
  <xsl:variable name="pdt-fslib-doc" select="document($pdt-fslib)"/>
  <xsl:key name="id-pdt-fslib" match="*[local-name(.) = 'fs']" use="@*[local-name(.) = 'id']"/>

  <xsl:variable name="ne-fslib" select="concat('./',substring-before(//*[local-name(.) = 'prefixDef' and @ident='ne']/@replacementPattern,'#'))"/>
  <xsl:variable name="ne-fslib-doc" select="document($ne-fslib)"/>
  <xsl:key name="id-ne-fslib-fs" match="*[local-name(.) = 'fs']" use="@*[local-name(.) = 'id']"/>
  <xsl:key name="id-ne-fslib-f" match="*[local-name(.) = 'f']" use="@*[local-name(.) = 'id']"/>
-->


<!--
  <xsl:template match="tei:w|tei:pc|tei:name|tei:ref|tei:num" priority="9">
    <xsl:apply-templates select="node()"/>
  </xsl:template>
-->
  <xsl:template match="tei:anchor"></xsl:template>
  <xsl:template match="tei:timeline"></xsl:template>

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
  <xsl:template match="*[contains(concat(' ',@ana), ' ne:') ]">
    <xsl:element name="{local-name(.)}">
      <xsl:apply-templates select="@*[local-name(.) = 'id']"/> <!-- ID -->
      <xsl:apply-templates select="@type"/> <!-- conll named entities -->
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
      <xsl:apply-templates select="@*"/>
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
      <xsl:apply-templates select="@*"/>
      <xsl:call-template name="externalLink">
        <xsl:with-param name="link" select="@source"/>
        <xsl:with-param name="additionalClasses" select='"speech-link"' />
      </xsl:call-template>
      <xsl:apply-templates select="node()"/>
    </xsl:element>
  </xsl:template>


<!-- PageBreaks and media -->
  <xsl:template match="//tei:div">
    <xsl:copy>
      <xsl:apply-templates select="@*"/>
        <xsl:apply-templates select="descendant::tei:pb[1]/preceding-sibling::*" />
        <xsl:apply-templates select="descendant::tei:pb"/>
      </xsl:copy>
  </xsl:template>
  <xsl:template match="tei:pb">
    <xsl:element name="div">
      <xsl:element  name="{local-name(.)}">
        <xsl:apply-templates select="@*"/>
      </xsl:element>
      <xsl:call-template name="externalLink">
        <xsl:with-param name="link" select="@source"/>
        <xsl:with-param name="additionalClasses" select='"page-link"' />
      </xsl:call-template>
      <xsl:variable name="media-link" select="pcz:get-media(.)" />
      <xsl:choose>
        <xsl:when test="$media-link">
          <xsl:element name="media">
            <xsl:attribute name="url" select="$media-link" />
            <xsl:call-template name="pageContent" />
          </xsl:element>
        </xsl:when>
        <xsl:otherwise>
          <xsl:call-template name="pageContent" />
        </xsl:otherwise>
      </xsl:choose>
    </xsl:element>
  </xsl:template>

  <xsl:template match="tei:s">
    <xsl:element name="{local-name(.)}">
      <xsl:apply-templates select="@*"/>
      <xsl:variable name="start" select="pcz:get-since(./descendant::tei:anchor[1]/@synch)" />
      <xsl:variable name="end" select="pcz:get-since(./descendant::tei:anchor[last()]/@synch)" />
      <xsl:if test="$start">
        <xsl:attribute name="start" select="$start" />
        <xsl:if test="$end">
          <xsl:attribute name="end" select="$end" />
        </xsl:if>
      </xsl:if>
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
      <!--<xsl:apply-templates select="node()"/>-->
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


  <xsl:template name="pageContent">
        <xsl:variable name="pb_cntr" select="count(./preceding::tei:pb)+1"/>
        <xsl:choose>
          <xsl:when test="parent::tei:u">
            <!-- place starting notes outside utterance -->
            <xsl:apply-templates select="following-sibling::tei:seg[1]/preceding-sibling::*[count(./preceding::tei:pb) = $pb_cntr and not(name()='pb')]" />
            <!--speach from previeous page continues-->
            <xsl:for-each select="parent::tei:u/preceding-sibling::*[1][name()='note']" >
              <xsl:apply-templates select="." /><!-- ADD CONTINUE FLAG -->
            </xsl:for-each>
            <xsl:element name="u">
              <xsl:apply-templates select="parent::tei:u/@*"/>
              <xsl:apply-templates select="
                following-sibling::tei:seg[1]/self::*[count(./preceding::tei:pb) = $pb_cntr and not(name()='pb')]
                |
                following-sibling::tei:seg[1]/following-sibling::*[count(./preceding::tei:pb) = $pb_cntr and not(name()='pb')]

                " />
            </xsl:element>
            <xsl:call-template name="copyFollowing">
              <xsl:with-param name="context" select="parent::tei:u"/>
              <xsl:with-param name="pb_cntr" select='$pb_cntr' />
            </xsl:call-template>
          </xsl:when>
          <xsl:otherwise>
            <xsl:call-template name="copyFollowing">
              <xsl:with-param name="context" select="."/>
              <xsl:with-param name="pb_cntr" select='$pb_cntr' />
            </xsl:call-template>
          </xsl:otherwise>
        </xsl:choose>
  </xsl:template>

  <xsl:template name="copyFollowing">
    <xsl:param name="pb_cntr" />
    <xsl:param name="context" />
      <!-- following utterances -->
      <xsl:apply-templates select="$context/following-sibling::*[count(./preceding::tei:pb) = $pb_cntr and not(name()='pb') and not(descendant::tei:pb)]" />

      <!--following partial utterance -->
      <xsl:variable name="partial-utt" select="$context/following-sibling::*[count(./preceding::tei:pb) = $pb_cntr and not(name()='pb') and descendant::tei:pb]"/>
      <xsl:if test="$partial-utt">
        <xsl:element name="u">
          <xsl:apply-templates select="$partial-utt/@*"/>
          <xsl:apply-templates select="$partial-utt/*[count(./preceding::tei:pb) = $pb_cntr and not(name()='pb')]" />
        </xsl:element>
      </xsl:if>
  </xsl:template>

  <xsl:function name="pcz:get-since">
    <xsl:param name="ref" />
    <xsl:value-of select="$root//tei:timeline/tei:when[@xml:id = substring-after($ref,'#')]/@since" />
  </xsl:function>

  <xsl:function name="pcz:get-media">
    <xsl:param name="pb" />
    <xsl:variable name="med" select="$pb/@corresp" />
    <xsl:value-of select="$root//tei:media[@xml:id = substring-after($med,'#')]/@url" />
  </xsl:function>
</xsl:stylesheet>