<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="2.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  xmlns:xi="http://www.w3.org/2001/XInclude"
  xmlns:mk="http://ufal.mff.cuni.cz/matyas-kopp"
  exclude-result-prefixes="tei" >
  <xsl:param name="coalition-opposition" />
  <xsl:param name="doc-personList" />
  <xsl:variable name="coal-opp" select="document($coalition-opposition)" />

  <xsl:output method="xml" indent="yes" encoding="UTF-8" />

  <xsl:variable name="listPerson">
    <xsl:choose>
      <xsl:when test="$doc-personList">
        <xsl:if test="normalize-space($doc-personList) and not(doc-available($doc-personList))">
          <xsl:message terminate="no">
            <xsl:text>ERROR: doc-personList document </xsl:text>
            <xsl:value-of select="$doc-personList"/>
            <xsl:text> not available!</xsl:text>
          </xsl:message>
        </xsl:if>
        <xsl:copy-of select="document($doc-personList)//tei:listPerson"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:copy-of select="//tei:listPerson"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:variable>

  <xsl:variable name="listOrg">
    <xsl:copy-of select="//tei:listOrg"/>
  </xsl:variable>

  <xsl:variable name="party-group-affiliation-pairs">
    <xsl:for-each select="$listPerson//tei:affiliation[@role='member'][$listOrg//tei:org[@role='parliamentaryGroup']/@xml:id = substring-after(@ref,'#')]">
      <xsl:variable name="aff-group" select="self::*"/>
      <xsl:variable name="aff-person" select="$aff-group/ancestor::tei:person[1]"/>
      <xsl:variable name="aff-party" select="$aff-person/tei:affiliation[@role='representative'][$listOrg//tei:org[@role='politicalParty']/@xml:id = substring-after(@ref,'#')][mk:is_in_interval(.,mk:get_from($aff-group))]"/>
      <xsl:variable name="group-event-id">
        <xsl:for-each select="tokenize($aff-group/@ana,' ')">
          <xsl:variable name="rf" select="substring-after(.,'#')"/>
          <xsl:if test="$listOrg//tei:org[@xml:id = substring-after($aff-group/@ref,'#')]//tei:event[@xml:id=$rf]">
            <xsl:value-of select="$rf"/>
          </xsl:if>
        </xsl:for-each>
      </xsl:variable>
      <xsl:if test="$aff-party">
        <xsl:element name="party-group">
          <xsl:attribute name="group-id" select="substring-after($aff-group[1]/@ref,'#')"/>
          <xsl:attribute name="party-id" select="substring-after($aff-party[1]/@ref,'#')"/>
          <xsl:attribute name="group-event-id" select="$group-event-id[1]"/>
        </xsl:element>
      </xsl:if>
    </xsl:for-each>
  </xsl:variable>

  <xsl:variable name="party-group">
    <xsl:for-each select="distinct-values($party-group-affiliation-pairs//@group-event-id)">
      <xsl:variable name="group-event-id" select="."/>
      <xsl:variable name="stat">
        <xsl:for-each select="distinct-values($party-group-affiliation-pairs/*[@group-event-id = $group-event-id]/@party-id)">
          <xsl:variable name="party-id" select="."/>
          <xsl:element name="party-group">
            <xsl:apply-templates select="$party-group-affiliation-pairs/*[@group-event-id = $group-event-id and @party-id = $party-id][1]/@*"/>
            <xsl:attribute name="cnt" select="count($party-group-affiliation-pairs/*[@group-event-id = $group-event-id and @party-id = $party-id])"/>
          </xsl:element>
        </xsl:for-each>
      </xsl:variable>
      <xsl:for-each select="$stat/*">
        <xsl:sort select="./@cnt" data-type="number" order="descending"/>
        <xsl:if test="position()=1">
          <xsl:copy-of select="."/>
        </xsl:if>
      </xsl:for-each>
    </xsl:for-each>
  </xsl:variable>

  <xsl:template match="tei:listOrg">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
      <xsl:element name="listRelation">
        <!--xsl:apply-templates select=".//tei:org[@role='parliamentaryGroup']//tei:event" mode="representing"/-->
        <xsl:call-template name="representing"/>
        <xsl:call-template name="formations"/>
      </xsl:element>
    </xsl:copy>
  </xsl:template>


  <xsl:template name="representing">
    <xsl:for-each select="$party-group/*">
      <xsl:variable name="group-event-id" select="./@group-event-id"/>
      <xsl:variable name="group-id" select="./@group-id"/>
      <xsl:variable name="event" select="$listOrg//tei:org[@xml:id=$group-id]//tei:event[$group-event-id='' or @xml:id=$group-event-id]"/>
      <xsl:element name="relation">
        <xsl:attribute name="name">representing</xsl:attribute>
        <xsl:attribute name="active" select="concat('#',./@group-id)"/>
        <xsl:attribute name="pasive" select="concat('#',./@party-id)"/>
        <xsl:attribute name="from" select="$event/@from"/>
        <xsl:if test="$event/@to"><xsl:attribute name="to" select="$event/@to"/></xsl:if>
        <xsl:if test="not($group-event-id='')"><xsl:attribute name="ana" select="concat('#',./@group-event-id)"/></xsl:if>
        <!--xsl:comment><xsl:value-of select="@cnt"/></xsl:comment-->
      </xsl:element>
    </xsl:for-each>
  </xsl:template>



  <xsl:template name="formations">
    <xsl:message>TODO: implement coallition and opposition formations (read from file)</xsl:message>
  </xsl:template>




  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>


  <xsl:function name="mk:get_from">
    <xsl:param name="node"/>
    <xsl:choose>
      <xsl:when test="$node/@from"><xsl:value-of select="$node/@from"/></xsl:when>
      <xsl:when test="$node/@when"><xsl:value-of select="$node/@from"/></xsl:when>
      <xsl:when test="$node
                       and $node/ancestor::tei:teiHeader//tei:sourceDesc/tei:bibl[1]/tei:date
                       and not($node/parent::tei:bibl/parent::tei:sourceDesc/parent::tei:fileDesc)">
        <xsl:value-of select="mk:get_from($node/ancestor::tei:teiHeader//tei:sourceDesc/tei:bibl[1]/tei:date)"/>
      </xsl:when>
      <xsl:otherwise>1500-01-01</xsl:otherwise>
    </xsl:choose>
  </xsl:function>

  <xsl:function name="mk:get_to">
    <xsl:param name="node"/>
    <xsl:choose>
      <xsl:when test="$node/@to"><xsl:value-of select="$node/@to"/></xsl:when>
      <xsl:when test="$node/@when"><xsl:value-of select="$node/@to"/></xsl:when>
      <xsl:when test="$node
                       and $node/ancestor::tei:teiHeader//tei:sourceDesc/tei:bibl[1]/tei:date
                       and not($node/parent::tei:bibl/parent::tei:sourceDesc/parent::tei:fileDesc)">
        <xsl:value-of select="mk:get_to($node/ancestor::tei:teiHeader//tei:sourceDesc/tei:bibl[1]/tei:date)"/>
      </xsl:when>
      <xsl:otherwise><xsl:value-of select="$node/ancestor::tei:teiHeader//tei:publicationStmt/tei:date/@when"/></xsl:otherwise>
    </xsl:choose>
  </xsl:function>


  <xsl:function name="mk:is_in_interval">
    <xsl:param name="node"/>
    <xsl:param name="date"/>
    <xsl:sequence select="$date >= mk:get_from($node) and mk:get_to($node) >= $date"/>
  </xsl:function>
</xsl:stylesheet>