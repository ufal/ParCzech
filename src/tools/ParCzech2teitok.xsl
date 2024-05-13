<?xml version="1.0"?>
<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xi="http://www.w3.org/2001/XInclude"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  xmlns:mk="http://ufal.mff.cuni.cz/matyas-kopp"
  xmlns:et="http://nl.ijs.si/et"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  exclude-result-prefixes="#all"
  version="2.0">

  <xsl:output method="xml" indent="yes" suppress-indentation="tok persName"/>
  <xsl:preserve-space elements="catDesc seg p"/>

  <xsl:param name="outDir"/>
  <xsl:param name="jobsCnt">1</xsl:param>
  <xsl:param name="jobN">1</xsl:param>
  <xsl:param name="commit"/>

  <xsl:import href="parlamint-lib.xsl"/>

  <!-- Input directory -->
  <xsl:variable name="inDir" select="replace(base-uri(), '(.*)/.*', '$1')"/>
  <xsl:key name="idwhen" match="tei:when" use="@xml:id"/>




  <!-- Output label for Government-members and non-Government-members (in vertical and metadata output) -->
  <xsl:param name="ingovernment-label">inGovernment</xsl:param>
  <xsl:param name="notingovernment-label">notInGovernment</xsl:param>

<!--
  <xsl:variable name="outRoot">
    <xsl:value-of select="$outDir"/>
    <xsl:text>/</xsl:text>
    <xsl:value-of select="replace(base-uri(), '.*/(.+?)(?:\.ana)?.xml$', '$1.tt.xml')"/>
  </xsl:variable>
-->
  <!-- Gather URIs of component xi + files and map to new files, incl. .ana files -->
  <xsl:variable name="docs">
    <xsl:for-each select="/tei:teiCorpus/xi:include[(position() mod $jobsCnt) = $jobN - 1 ]">
      <xsl:variable name="prev-href" select="./preceding-sibling::xi:include[1]/@href"/>
      <xsl:variable name="next-href" select="./following-sibling::xi:include[1]/@href"/>
      <item>
        <xi-orig>
          <xsl:value-of select="@href"/>
        </xi-orig>
        <url-orig>
          <xsl:value-of select="concat($inDir, '/', @href)"/>
        </url-orig>
        <url-new>
          <xsl:value-of select="concat($outDir, '/')"/>
          <xsl:value-of select="mk:to-teitok-href(@href)"/>
        </url-new>
        <xi-new>
          <xsl:value-of select="mk:to-teitok-href(@href)"/>
        </xi-new>
        <prev><xsl:value-of select="mk:to-teitok-href($prev-href)"/></prev>
        <next><xsl:value-of select="mk:to-teitok-href($next-href)"/></next>
      </item>
      </xsl:for-each>
  </xsl:variable>


  <xsl:variable name="person"> <!-- load listPerson and merge the info from listOrg  (add the info to affiliations)-->
    <xsl:variable name="listPerson" select="document(concat($inDir, '/',/tei:teiCorpus//tei:particDesc/xi:include[contains(@href,'listPerson')]/@href))"/>
    <xsl:variable name="listOrg" select="document(concat($inDir, '/',/tei:teiCorpus//tei:particDesc/xi:include[contains(@href,'listOrg')]/@href))"/>
    <xsl:for-each select="$listPerson//tei:person">
      <xsl:copy>
        <xsl:attribute name="xml:id" select="@xml:id"/>
        <xsl:attribute name="name" select="et:format-name(./tei:persName)"/>
      </xsl:copy>
    </xsl:for-each>
  </xsl:variable>


  <xsl:template match="/">
    <xsl:message select="concat('INFO [',$jobN,'/',$jobsCnt,']: Starting to process ', tei:teiCorpus/@xml:id)"/>
    <!-- Process component files -->
    <xsl:apply-templates select="$docs//item"/>
  </xsl:template>

  <xsl:template match="item">
    <xsl:variable name="this" select="xi-orig"/>
    <xsl:message select="concat('INFO [',$jobN,'/',$jobsCnt,']: Processing ', $this)"/>
    <xsl:result-document href="{url-new}">
      <!-- preprocess -->
      <xsl:variable name="preprocess">
        <xsl:apply-templates mode="comp" select="document(url-orig)/tei:TEI">
          <xsl:with-param name="next" select="next"/>
          <xsl:with-param name="prev" select="prev"/>
        </xsl:apply-templates>
      </xsl:variable>
      <!-- copy cnec value to tokens -->
      <xsl:apply-templates mode="cnec" select="$preprocess"/>
    </xsl:result-document>
    <xsl:message select="concat('INFO [',$jobN,'/',$jobsCnt,']: Saving to ', xi-new)"/>
  </xsl:template>

  <xsl:template mode="comp" match="tei:TEI">
    <xsl:param name="next"/>
    <xsl:param name="prev"/>
    <xsl:element name="{local-name()}">
      <xsl:apply-templates mode="comp" select="@*"/>
      <xsl:attribute name="xmlnsoff" select="namespace-uri()"/>
      <xsl:apply-templates mode="comp">
        <xsl:with-param name="TEI" select="."/>
        <xsl:with-param name="next" select="$next"/>
        <xsl:with-param name="prev" select="$prev"/>
     </xsl:apply-templates>
    </xsl:element>
  </xsl:template>

  <xsl:template mode="comp" match="tei:sourceDesc">
    <xsl:param name="TEI"/>
    <xsl:variable name="when" select="$TEI//tei:teiHeader//tei:setting/tei:date/@when"/>
    <xsl:element name="{local-name()}">
      <xsl:apply-templates mode="comp">
        <xsl:with-param name="TEI" select="$TEI"/>
      </xsl:apply-templates>
      <listPerson>
        <xsl:for-each select="distinct-values($TEI//tei:u/@who)">
          <xsl:sort select="."/>
          <xsl:variable name="whoId" select="substring-after(.,'#')"/>
          <xsl:variable name="speaker" select="$rootHeader//tei:listPerson//tei:person[@xml:id = $whoId]"/>
          <person id="{$whoId}">
            <persName
              lang="org"
              mp="{et:speaker-mp($speaker,$when)}"
              party_status="{et:party-status($speaker, $when)}"
              party_name="{et:speaker-party($speaker, 'yes', $when)}"
              minister="{et:speaker-minister($speaker, $when)}"
              member_of_gov="{mk:speaker-member-of-gov($speaker, $when)}"
              party_orientation="{et:party-orientation($speaker, $when)}"
              party="{et:speaker-party($speaker, 'abb', $when)}">
              <xsl:attribute name="birth">
                <xsl:choose>
                  <xsl:when test="$speaker/tei:birth">
                    <xsl:value-of select="replace($speaker/tei:birth/@when, '-.+', '')"/>
                  </xsl:when>
                  <xsl:otherwise>-</xsl:otherwise>
                </xsl:choose>
              </xsl:attribute>
              <xsl:attribute name="gender">
                <xsl:choose>
                  <xsl:when test="$speaker/tei:sex">
                    <xsl:value-of select="$speaker/tei:sex/@value"/>
                  </xsl:when>
                  <xsl:otherwise>-</xsl:otherwise>
                </xsl:choose>
              </xsl:attribute>

              <xsl:value-of select="et:format-name-chrono($speaker//tei:persName, $when)"/>
            </persName>
          </person>
        </xsl:for-each>
      </listPerson>
    </xsl:element>
  </xsl:template>

  <xsl:template mode="comp" match="tei:encodingDesc">
    <xsl:param name="TEI"/>
    <xsl:variable name="when" select="$TEI//tei:teiHeader//tei:setting/tei:date/@when"/>
    <xsl:element name="{local-name()}">
      <xsl:apply-templates mode="comp">
        <xsl:with-param name="TEI" select="$TEI"/>
      </xsl:apply-templates>
      <appInfo>
        <application ident="ParCzech2teitok" version="{$commit}">
          <label>ParCzech2teitok.xsl</label>
          <desc xml:lang="en">Script available at <ref target="{concat('https://github.com/ufal/ParCzech/tree/',$commit,'/src/tools/ParCzech2teitok.xsl')}">GitHub ufal/ParCzech</ref></desc>
        </application>
      </appInfo>
    </xsl:element>
  </xsl:template>



  <xsl:template mode="comp" match="tei:pc | tei:w">
    <xsl:param name="TEI"/>
    <xsl:variable name="startId" select="./preceding-sibling::tei:*[1][local-name() = 'anchor']/@synch/substring-after(.,'#')"/>
    <xsl:variable name="endId" select="./following-sibling::tei:*[1][local-name() = 'anchor']/@synch/substring-after(.,'#')"/>
    <xsl:variable name="id" select="@xml:id"/>
    <xsl:variable name="idRef" select="concat(' #',$id)"/>
    <tok type="{name()}">
      <xsl:apply-templates mode="comp" select="@xml:id"/>
      <xsl:apply-templates mode="comp" select="@lemma"/>
      <xsl:apply-templates mode="comp" select="@join"/>
      <xsl:apply-templates mode="comp" select="@norm"/>
      <xsl:if test="@ana">
        <xsl:attribute name="xpos" select="substring-after(@ana, 'pdt:')"/>
      </xsl:if>
      <xsl:if test="@pos">
        <xsl:attribute name="upos" select="@pos"/>
      </xsl:if>
      <xsl:variable name="feats" select="replace(@msd,'^UPosTag=[^\|]*\|?','')"/>
      <xsl:if test="$feats">
        <xsl:attribute name="feats" select="$feats"/>
      </xsl:if>
      <xsl:if test="$startId">
        <xsl:attribute name="start" select="key('idwhen', $startId, $TEI)/@interval div 1000"/>
      </xsl:if>
      <xsl:if test="$endId">
        <xsl:attribute name="end" select="key('idwhen', $endId, $TEI)/@interval div 1000"/>
      </xsl:if>
      <xsl:variable name="link" select="ancestor::tei:s[1]/tei:linkGrp[@type='UD-SYN']/tei:link[ends-with(@target,$idRef)]"/>
      <xsl:variable name="deprel" select="replace(substring-after($link/@ana,'ud-syn:'),'_',':')"/>
      <xsl:if test="not($deprel = 'root')">
        <xsl:attribute name="head" select="substring-after(substring-before($link/@target,' '),'#')"/>
      </xsl:if>
      <xsl:attribute name="deprel" select="$deprel"/>
      <xsl:apply-templates mode="comp"/>
    </tok>
  </xsl:template>

  <xsl:template mode="comp" match="tei:linkGrp"/>
  <xsl:template mode="comp" match="tei:anchor"/>
  <xsl:template mode="comp" match="tei:timeline"/>
  <xsl:template mode="comp" match="tei:media"/>


  <xsl:template mode="comp" match="tei:u">
    <xsl:param name="TEI"/>
    <!-- <xsl:variable name="whoIDref" select="@who"/> -->
    <xsl:variable name="when" select="$TEI//tei:teiHeader//tei:setting/tei:date/@when"/>
    <xsl:element name="{local-name()}">
      <xsl:apply-templates mode="comp" select="@xml:id"/>
      <xsl:variable name="speaker" select="key('idr', @who, $rootHeader)"/>
      <xsl:if test="$speaker">
        <xsl:attribute name="corresp" select="@who"/>
        <xsl:attribute name="who" select="et:format-name-chrono($speaker//tei:persName, $when)"/>
      </xsl:if>
      <xsl:apply-templates mode="comp" select="@ana"/>
      <xsl:if test="descendant::tei:anchor">
        <xsl:variable name="startId" select="./descendant::tei:anchor[1]/@synch/substring-after(.,'#')"/>
        <xsl:attribute name="start" select="key('idwhen', $startId, $TEI)/@interval div 1000"/>
        <xsl:if test="not(descendant::tei:pb)"> <!-- add end only if the speach is on one page -->
          <xsl:variable name="endId" select="./descendant::tei:anchor[last()]/@synch/substring-after(.,'#')"/>
          <xsl:attribute name="end" select="key('idwhen', $endId, $TEI)/@interval div 1000"/>
        </xsl:if>
      </xsl:if>
      <xsl:apply-templates mode="comp">
        <xsl:with-param name="TEI" select="$TEI"/>
      </xsl:apply-templates>
    </xsl:element>
  </xsl:template>

  <xsl:template mode="comp" match="tei:pb">
    <xsl:param name="TEI"/>
    <xsl:variable name="corresp" select="@corresp"/>
    <xsl:element name="{local-name()}">
      <xsl:apply-templates mode="comp" select="@*[not(name() = 'corresp')]"/>
      <xsl:if test="$corresp">
        <xsl:attribute name="start" select="$TEI//tei:timeline[@corresp = $corresp]/tei:when[@interval][1]/@interval div 1000"/>
        <xsl:attribute name="end" select="$TEI//tei:timeline[@corresp = $corresp]/tei:when[last()]/@interval div 1000"/>
      </xsl:if>
      <xsl:variable name="speaker" select="ancestor::tei:u[@who]"/>
      <xsl:if test="$speaker">
        <xsl:variable name="when" select="$TEI//tei:teiHeader//tei:setting/tei:date/@when"/>
        <xsl:attribute name="corresp" select="$speaker/@who"/>
        <xsl:attribute name="who" select="et:format-name-chrono(key('idr', $speaker/@who, $rootHeader)//tei:persName,$when)"/>
        <xsl:attribute name="ana" select="$speaker/@ana"/>
      </xsl:if>
<!--
ParlaMint: <pb source="https://www.psp.cz/eknih/2021ps/stenprot/071schuz/s071323.htm" n="3" xml:id="ParlaMint-CZ_2023-07-26-ps2021-071-07-001-003.pb3" corresp="#PavelBelobradek.1976" utt="ParlaMint-CZ_2023-07-26-ps2021-071-07-001-003.u8" who="Bělobrádek, Pavel" ana="#regular"/>
ParCzech(3.0 like): <pb source="https://www.psp.cz/eknih/2021ps/stenprot/071schuz/s071323.htm" n="3" id="ps2021-071-07-001-003.pb3" corresp="#ps2021-071-07-001-003.audio3"/><media id="ps2021-071-07-001-003.audio3" mimeType="audio/mp3" source="https://www.psp.cz/eknih/2021ps/audio/2023/07/26/2023072612181232.mp3" url="audio/psp/2023/07/26/2023072612181232.mp3" n="3"/>


-->
      <xsl:apply-templates mode="comp">
        <xsl:with-param name="TEI" select="$TEI"/>
      </xsl:apply-templates>
    </xsl:element>
    <xsl:if test="$corresp">
      <xsl:apply-templates select="$TEI//tei:media[@xml:id = substring-after($corresp,'#')]"/>
    </xsl:if>
  </xsl:template>

  <xsl:template mode="comp" match="tei:text">
    <xsl:param name="TEI"/>
    <xsl:param name="next"/>
    <xsl:param name="prev"/>
    <xsl:element name="{local-name()}">
      <xsl:apply-templates mode="comp" select="@*"/>
      <xsl:attribute name="xml:space">remove</xsl:attribute>
      <xsl:if test="normalize-space($prev)">
        <xsl:attribute name="prev" select="$prev"/>
      </xsl:if>
      <xsl:if test="normalize-space($next)">
        <xsl:attribute name="next" select="$next"/>
      </xsl:if>
      <xsl:apply-templates mode="comp">
        <xsl:with-param name="TEI" select="$TEI"/>
      </xsl:apply-templates>
    </xsl:element>
  </xsl:template>

  <xsl:template mode="comp" match="*">
    <xsl:param name="TEI"/>
    <xsl:element name="{local-name()}">
      <xsl:apply-templates mode="comp" select="@*"/>
      <xsl:if test="ancestor-or-self::tei:seg and descendant::tei:anchor">
        <xsl:variable name="startId" select="./descendant::tei:anchor[1]/@synch/substring-after(.,'#')"/>
        <xsl:variable name="endId" select="./descendant::tei:anchor[last()]/@synch/substring-after(.,'#')"/>
        <xsl:attribute name="start" select="key('idwhen', $startId, $TEI)/@interval div 1000"/>
        <xsl:attribute name="end" select="key('idwhen', $endId, $TEI)/@interval div 1000"/>
      </xsl:if>
      <xsl:apply-templates mode="comp">
        <xsl:with-param name="TEI" select="$TEI"/>
      </xsl:apply-templates>
    </xsl:element>
  </xsl:template>

  <xsl:template mode="comp" match="@ana[contains(concat(' ',.),' ne:')]">
    <xsl:attribute name="cnec" select="substring-before(substring-after(concat(' ',.,' '),' ne:'),' ')"/>
  </xsl:template>

  <xsl:template mode="comp" match="@xml:*">
    <xsl:attribute name="{local-name()}" select="."/>
  </xsl:template>

  <xsl:template match="@xml:*">
    <xsl:attribute name="{local-name()}" select="."/>
  </xsl:template>

  <xsl:template mode="comp" match="@*">
    <xsl:copy/>
  </xsl:template>

 <!-- cnec -->

  <xsl:template mode="cnec" match="tok[ancestor::*/@cnec]">
    <xsl:copy>
      <xsl:apply-templates mode="cnec" select="@*"/>
      <xsl:attribute name="cnec" select="string-join(ancestor::*/@cnec,',')"/> <!-- comma due to a TEITOK query builder -->
      <xsl:apply-templates mode="cnec"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template mode="cnec" match="*">
    <xsl:copy>
      <xsl:apply-templates mode="cnec" select="@*"/>
      <xsl:apply-templates mode="cnec"/>
    </xsl:copy>
  </xsl:template>
  <xsl:template mode="cnec" match="@*">
    <xsl:copy/>
  </xsl:template>
  <xsl:template mode="cnec" match="text()">
    <xsl:value-of select="."/>
  </xsl:template>

  <!-- Finalizing ROOT -->
  <xsl:template match="*">
    <xsl:element name="{local-name()}">
      <xsl:apply-templates select="@*"/>
      <xsl:apply-templates/>
    </xsl:element>
  </xsl:template>
  <xsl:template match="@*">
    <xsl:copy/>
  </xsl:template>

  <xsl:template match="tei:teiCorpus">
    <xsl:element name="{local-name()}">
      <xsl:apply-templates select="@*"/>
      <xsl:apply-templates select="tei:*"/>
      <xsl:for-each select="xi:include">
        <!--<xsl:sort select="@href"/>-->
        <xsl:variable name="href" select="@href"/>
        <xsl:variable name="new-href" select="$docs/tei:item[./tei:xi-orig/text() = $href]/tei:xi-new/text()"/>
        <xsl:message select="concat('INFO [',$jobN,'/',$jobsCnt,']: Fixing xi:include: ',$href,' ',$new-href)"/>
        <xsl:element name="{local-name()}">
          <xsl:attribute name="href" select="$new-href"/>
        </xsl:element>
      </xsl:for-each>
    </xsl:element>
  </xsl:template>

  <xsl:template name="copy-file">
    <xsl:param name="in"/>
    <xsl:param name="out"/>
    <xsl:message select="concat('INFO [',$jobN,'/',$jobsCnt,']: copying file ',$in,' ',$out)"/>
    <xsl:result-document href="{$out}" method="text"><xsl:value-of select="unparsed-text($in,'UTF-8')"/></xsl:result-document>
  </xsl:template>


  <!-- Format the name of a person from persName -->
  <xsl:function name="et:format-name">
    <xsl:param name="persName"/>
    <xsl:choose>
      <xsl:when test="$persName/tei:forename[normalize-space(.)] or $persName/tei:surname[normalize-space(.)]">
        <xsl:value-of select="normalize-space(
                              string-join(
                              (
                              string-join(
                                (
                                  $persName/tei:surname[not(@type='patronym')]
                                  |
                                  $persName/tei:nameLink[following-sibling::tei:*[1][local-name()='surname' or local-name()='nameLink']]
                                )/normalize-space(.),
                                ' '),
                              concat(
                              string-join($persName/tei:forename/normalize-space(.),' '),
                              ' ',
                              string-join($persName/tei:surname[@type='patronym']/normalize-space(.),' ')
                              )
                              )[normalize-space(.)],
                              ', ' ))"/>
      </xsl:when>
      <xsl:when test="$persName/tei:term">
        <xsl:value-of select="concat('@', $persName/tei:term, '@')"/>
      </xsl:when>
      <xsl:when test="normalize-space($persName)">
        <xsl:value-of select="$persName"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:message select="concat('ERROR: empty persName for ', $persName/@xml:id)"/>
        <xsl:text>-</xsl:text>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:function>

  <xsl:function name="mk:to-teitok-href">
    <xsl:param name="href"/>
    <xsl:value-of select="replace($href,'(?:\.ana)?\.xml$','.tt.xml')"/>
  </xsl:function>

  <!-- Output appropriate label if the speaker is (not) a in Government when speaking -->
  <xsl:function name="mk:speaker-member-of-gov" as="xs:string">
    <xsl:param name="speaker" as="element(tei:person)"/>
    <xsl:param name="when" as="xs:string"/>
    <xsl:variable name="govs" select="string($rootHeader//tei:listOrg//tei:org[@role='government']/@xml:id)"/>
    <xsl:choose>
      <xsl:when test="$speaker/tei:affiliation[@role = 'member']
                      [$govs = substring-after(@ref,'#')]
                      [et:between-dates($when, @from, @to)]">
        <xsl:value-of select="$ingovernment-label"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="$notingovernment-label"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:function>

</xsl:stylesheet>
