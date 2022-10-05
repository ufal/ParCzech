<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="2.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  xmlns:xi="http://www.w3.org/2001/XInclude"
  xmlns:mk="http://ufal.mff.cuni.cz/matyas-kopp"
  xmlns:et="http://nl.ijs.si/et"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  exclude-result-prefixes="tei mk et xs" >
  <xsl:param name="coal-opp" />
  <xsl:param name="doc-personList" />

  <xsl:output method="xml" indent="yes" encoding="UTF-8" />


  <!-- Transform TSV into a XML variable -->
  <xsl:variable name="coal-opp-relations">
    <xsl:variable name="data" select="unparsed-text($coal-opp,'UTF-8')"/>
    <list>
      <xsl:for-each select="tokenize($data, '\n')">
        <xsl:variable name="line" select="."/>
        <xsl:if test="not(starts-with($line, 'role'))">
          <xsl:analyze-string select="$line"
                  regex="^(.*)&#9;(.*)&#9;(.*)&#9;(.*)&#9;(.*)&#9;(.*)$">
            <xsl:matching-substring>
              <xsl:variable name="role" select="normalize-space(regex-group(1))"/>
              <xsl:variable name="from" select="replace(
                  replace(
                  normalize-space(regex-group(2)),
                  '-(\d)-', '-0$1-'),
                  '-(\d)$', '-0$1')"/>
              <xsl:variable name="to" select="replace(
                      replace(
                      normalize-space(regex-group(3)),
                      '-(\d)-', '-0$1-'),
                      '-(\d)$', '-0$1')"/>
              <xsl:variable name="groups" select="normalize-space(regex-group(4))"/>
              <xsl:choose>
                <xsl:when test="$from and $from != '-' and not(matches($from, '\d\d\d\d-\d\d-\d\d'))">
                  <xsl:message select="concat('ERROR: from = ', $from)"/>
                </xsl:when>
                <xsl:when test="$to and $to != '-' and not(matches($to, '\d\d\d\d-\d\d-\d\d'))">
                  <xsl:message select="concat('ERROR: to = ', $to)"/>
                </xsl:when>
                <xsl:when test="$role != 'coalition' and $role != 'opposition'">
                  <xsl:message select="concat('WARN: role = ', $role, ', skipping!')"/>
                </xsl:when>
                <xsl:otherwise>
                  <item>
                    <name>
                      <xsl:if test="$role != 'coalition' and $role != 'opposition'">
                        <xsl:message select="concat('WARN : role = ', $role, ' hmmm')"/>
                      </xsl:if>
                      <xsl:value-of select="$role"/>
                    </name>
                    <from>
                      <xsl:if test="$from != '' and $from != '-'">
                        <xsl:value-of select="$from"/>
                      </xsl:if>
                    </from>
                    <to>
                      <xsl:if test="$to != '' and $to != '-'">
                        <xsl:value-of select="$to"/>
                      </xsl:if>
                    </to>
                    <xsl:for-each select="tokenize($groups, ' ')">
                      <group>
                        <xsl:value-of select="."/>
                      </group>
                    </xsl:for-each>
                  </item>
                </xsl:otherwise>
              </xsl:choose>
            </xsl:matching-substring>
            <xsl:non-matching-substring>
              <xsl:message select="concat('ERROR: bad line ', $line)"/>
            </xsl:non-matching-substring>
          </xsl:analyze-string>
        </xsl:if>
      </xsl:for-each>
    </list>
  </xsl:variable>


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
        <xsl:attribute name="passive" select="concat('#',./@party-id)"/>
        <xsl:attribute name="from" select="$event/@from"/>
        <xsl:if test="$event/@to"><xsl:attribute name="to" select="$event/@to"/></xsl:if>
        <xsl:variable name="group-event-id">
          <xsl:if test="not($group-event-id='')"><xsl:value-of select="concat('#',./@group-event-id)"/></xsl:if>
        </xsl:variable>
        <!-- Add term when coalition/opposition active -->
        <xsl:variable name="term">
          <xsl:variable name="terms" select="$listOrg//tei:org[@role = 'parliament' and contains(@ana,'#parla.lower')]/tei:listEvent"/>
          <xsl:for-each select="$terms/tei:event">
            <xsl:if test="et:between-dates($event/@from, @from, @to) and
              et:between-dates($event/@to, @from, @to)">
              <xsl:value-of select="concat('#', @xml:id, ' ')"/>
            </xsl:if>
          </xsl:for-each>
        </xsl:variable>
        <xsl:variable name='ana' select="concat($term,' ',$group-event-id)"/>
        <xsl:if test="normalize-space($ana)">
          <xsl:attribute name="ana" select="normalize-space($ana)"/>
        </xsl:if>
        <!--xsl:comment><xsl:value-of select="@cnt"/></xsl:comment-->
      </xsl:element>
    </xsl:for-each>
  </xsl:template>



  <xsl:template name="formations">
    <xsl:for-each select="$coal-opp-relations//tei:item">
      <xsl:sort select="concat(tei:role,' ',tei:from)"/>
      <xsl:variable name="item" select="."/>
      <relation>
        <xsl:attribute name="name" select="$item/tei:name"/>
        <xsl:variable name="groups">
          <xsl:for-each select="tei:group">
            <xsl:variable name="group-abb" select="."/>
            <xsl:variable name="group-org" select="$listOrg//tei:org[@role='parliamentaryGroup'
                                                             and ./tei:orgName[@full='abb' and text() = $group-abb]
                                                             and .//tei:event[et:between-dates($item/tei:from,@from,@to)]
                                                                    ]"/>
            <xsl:if test="count($group-org)>1">
              <xsl:message select="concat('ERROR: multiple parliamentary groups match ',
                         $item/tei:name, ' group = ', ., ' between ',
                         $item/tei:from, ' - ', $item/tei:to)"/>
            </xsl:if>
            <xsl:choose>
              <xsl:when test="$group-org">
                <xsl:value-of select="$group-org/@xml:id/concat('#', . , ' ')"/>
              </xsl:when>
              <xsl:otherwise>
                <xsl:message select="concat('ERROR: ',
                         $item/tei:name, ' group = ', ., ' between ',
                         $item/tei:from, ' - ', $item/tei:to)"/>
              </xsl:otherwise>
            </xsl:choose>
          </xsl:for-each>
        </xsl:variable>
        <xsl:choose>
          <xsl:when test="tei:name = 'coalition'">
            <xsl:attribute name="mutual" select="normalize-space($groups)"/>
          </xsl:when>
          <xsl:when test="tei:name = 'opposition'">
            <xsl:attribute name="active" select="normalize-space($groups)"/>
            <xsl:attribute name="passive">
              <xsl:variable name="government"
                      select="$listOrg//tei:org[@role = 'government']/@xml:id"/>
              <xsl:choose>
                <xsl:when test="$government != ''">
                  <xsl:value-of select="concat('#', $government)"/>
                </xsl:when>
                <xsl:otherwise>
                  <xsl:message>ERROR: missing government for opposition</xsl:message>
                </xsl:otherwise>
              </xsl:choose>
            </xsl:attribute>
          </xsl:when>
        </xsl:choose>
        <xsl:if test="normalize-space(tei:from)">
          <xsl:attribute name="from" select="tei:from"/>
        </xsl:if>
        <xsl:if test="normalize-space(tei:to)">
          <xsl:attribute name="to" select="tei:to"/>
        </xsl:if>
        <!-- Add term when coalition/opposition active -->
        <xsl:variable name="term">
          <xsl:variable name="terms" select="$listOrg//tei:org[@role = 'parliament' and contains(@ana,'#parla.lower')]/tei:listEvent"/>
          <xsl:for-each select="$terms/tei:event">
            <xsl:if test="et:between-dates($item/tei:from, @from, @to) and
              et:between-dates($item/tei:to, @from, @to)">
              <xsl:value-of select="concat('#', @xml:id, ' ')"/>
            </xsl:if>
          </xsl:for-each>
        </xsl:variable>
        <xsl:if test="normalize-space($term)">
          <xsl:attribute name="ana" select="normalize-space($term)"/>
        </xsl:if>
      </relation>
    </xsl:for-each>
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

    <!-- Is the first date between the following two? -->
  <xsl:function name="et:between-dates" as="xs:boolean">
    <xsl:param name="date" as="xs:string?"/>
    <xsl:param name="from" as="xs:string?"/>
    <xsl:param name="to" as="xs:string?"/>
    <xsl:choose>
      <xsl:when test="not(normalize-space($date))">
        <xsl:value-of select="true()"/>
      </xsl:when>
      <xsl:when test="not(normalize-space($from) or normalize-space($to))">
        <xsl:value-of select="true()"/>
      </xsl:when>
      <xsl:when test="not(normalize-space($from)) and xs:date($date) &lt;= xs:date($to)">
        <xsl:value-of select="true()"/>
      </xsl:when>
      <xsl:when test="not(normalize-space($to)) and xs:date($date) &gt;= xs:date($from)">
        <xsl:value-of select="true()"/>
      </xsl:when>
      <xsl:when test="xs:date($date) &gt;= xs:date($from) and xs:date($date) &lt;= xs:date($to)">
        <xsl:value-of select="true()"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="false()"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:function>
</xsl:stylesheet>