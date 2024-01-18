<?xml version="1.0"?>
<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xi="http://www.w3.org/2001/XInclude"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  xmlns:mk="http://ufal.mff.cuni.cz/matyas-kopp"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  exclude-result-prefixes="xsl tei xs xi mk"
  version="2.0">

  <xsl:output method="xml" indent="yes"/>
  <xsl:preserve-space elements="catDesc seg p"/>

  <xsl:param name="inListPerson"/>
  <xsl:param name="inListOrg"/>
  <xsl:param name="inTaxonomiesDir"/>
  <xsl:param name="outDir"/>
  <xsl:param name="anaDir"/>
  <xsl:param name="type"/> <!-- TEI or TEI.ana-->

  <xsl:param name="version">4.0</xsl:param>
  <xsl:param name="handle">http://hdl.handle.net/11234/1-5360</xsl:param>
  <xsl:param name="model-udpipe">czech-pdt-ud-2.10-220711</xsl:param>
  <xsl:param name="model-nametag">czech-cnec2.0-200831</xsl:param>

  <xsl:variable name="publisher">
    <publisher>
      <orgName xml:lang="cs">LINDAT/CLARIAH-CZ: Digitální výzkumná infrastruktura pro jazykové technologie, umění a humanitní vědy</orgName>
      <orgName xml:lang="en">LINDAT/CLARIAH-CZ: Digital Research Infrastructure for Language Technologies, Arts and Humanities</orgName>
      <ref target="https://www.lindat.cz">www.lindat.cz</ref>
    </publisher>
  </xsl:variable>

  <!-- Input directory -->
  <xsl:variable name="inDir" select="replace(base-uri(), '(.*)/.*', '$1')"/>
  <!-- The name of the corpus directory to output to, i.e. "ParCzech" -->
  <xsl:variable name="corpusDir" select="concat('ParCzech.',$type)"/>
  <xsl:variable name="taxonomies">
    <item>ParlaMint-taxonomy-parla.legislature.xml</item>
    <item>ParlaMint-taxonomy-speaker_types.xml</item>
    <!--<item>ParlaMint-taxonomy-politicalOrientation.xml</item>-->
    <!--<item>ParlaMint-taxonomy-CHES.xml</item>-->
    <!--<item>ParlaMint-taxonomy-subcorpus.xml</item>-->
    <item>ParCzech-taxonomy-parla.links.xml</item>
    <item>ParCzech-taxonomy-meeting.parts.xml</item>
    <xsl:if test="$type = 'TEI.ana'">
      <item>ParlaMint-taxonomy-UD-SYN.ana.xml</item>
      <item>ParlaMint-taxonomy-NER.ana.xml</item>
      <item>ParCzech-taxonomy-NER.cnec2.0.ana.xml</item>
    </xsl:if>
  </xsl:variable>

  <xsl:variable name="today" select="format-date(current-date(), '[Y0001]-[M01]-[D01]')"/>
  <xsl:variable name="outRoot">
    <xsl:value-of select="$outDir"/>
    <xsl:text>/</xsl:text>
    <xsl:value-of select="$corpusDir"/>
    <xsl:text>/</xsl:text>
    <xsl:value-of select="replace(base-uri(), '.*/(.+?)(?:\.ana)?.xml$', '$1')"/>
    <xsl:choose>
      <xsl:when test="$type = 'TEI.ana'">.ana.xml</xsl:when>
      <xsl:when test="$type = 'TEI'">.xml</xsl:when>
      <xsl:otherwise>
        <xsl:message terminate="yes">invalid type param: allowed values are 'TEI' and 'TEI.ana'</xsl:message>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:variable>

  <xsl:variable name="url-corpus-ana" select="concat($anaDir, '/', replace(base-uri(), '.*/(.+?)(?:\.ana)?\.xml', '$1.ana.xml'))"/>

  <xsl:variable name="suff">
    <xsl:choose>
      <xsl:when test="$type = 'TEI.ana'">.ana</xsl:when>
      <xsl:otherwise><text/></xsl:otherwise>
    </xsl:choose>
  </xsl:variable>
  <!-- Gather URIs of component xi + files and map to new files, incl. .ana files -->
  <xsl:variable name="docs">
    <xsl:for-each select="/tei:teiCorpus/xi:include">
      <item>
        <xi-orig>
          <xsl:value-of select="@href"/>
        </xi-orig>
        <url-orig>
          <xsl:value-of select="concat($inDir, '/', @href)"/>
        </url-orig>
        <doc>
          <xsl:apply-templates select="document(concat($inDir, '/', @href))" mode="preprocess"/>
        </doc>
        <url-new>
          <xsl:value-of select="concat($outDir, '/', $corpusDir, '/')"/>
          <xsl:choose>
            <xsl:when test="$type = 'TEI.ana'"><xsl:value-of select="replace(@href,'(?:\.ana)?\.xml$','.ana.xml')"/></xsl:when>
            <xsl:when test="$type = 'TEI'"><xsl:value-of select="@href"/></xsl:when>
          </xsl:choose>
        </url-new>
        <xi-new>
          <xsl:choose>
            <xsl:when test="$type = 'TEI.ana'"><xsl:value-of select="replace(@href,'(?:\.ana)?\.xml$','.ana.xml')"/></xsl:when>
            <xsl:when test="$type = 'TEI'"><xsl:value-of select="@href"/></xsl:when>
          </xsl:choose>
        </xi-new>
        <url-ana>
          <xsl:value-of select="concat($anaDir, '/', replace(@href, '(?:\.ana)?\.xml', '.ana.xml'))"/>
        </url-ana>
      </item>
      </xsl:for-each>
  </xsl:variable>

  <xsl:template match="*" mode="preprocess">
    <xsl:copy>
      <xsl:apply-templates select="@*"/>
      <xsl:apply-templates mode="preprocess"/>
    </xsl:copy>
  </xsl:template>

  <!-- Numbers of words in component .ana files -->
  <xsl:variable name="words">
    <xsl:for-each select="$docs/tei:item">
      <item n="{tei:xi-orig}">
        <xsl:choose>
          <!-- For .ana files, compute number of words -->
          <xsl:when test="$type = 'TEI.ana'">
            <xsl:value-of select="count(tei:doc//tei:w[not(parent::tei:w)])"/>
          </xsl:when>
          <!-- For plain files, take number of words from .ana files -->
          <xsl:when test="doc-available(tei:url-ana)">
            <xsl:value-of select="document(tei:url-ana)/tei:TEI/tei:teiHeader//
                                  tei:extent/tei:measure[@unit='words'][1]/@quantity"/>
          </xsl:when>
          <xsl:otherwise>
            <xsl:message select="concat('ERROR ', /tei:TEI/@xml:id,
                                   ': cannot locate .ana file ', tei:url-ana)"/>
            <xsl:value-of select="number('0')"/>
          </xsl:otherwise>
        </xsl:choose>
      </item>
    </xsl:for-each>
  </xsl:variable>

  <!-- Terms in component files -->
  <xsl:variable name="terms">
    <xsl:for-each select="$docs/tei:item">
      <item n="{tei:xi-orig}">
        <xsl:copy-of select="tei:doc/tei:TEI/tei:teiHeader//tei:meeting[contains(@ana,'#parla.term')]"/>
      </item>
    </xsl:for-each>
  </xsl:variable>

  <!-- Dates in component files -->
  <xsl:variable name="dates">
    <xsl:for-each select="$docs/tei:item">
      <item n="{tei:xi-orig}">
        <xsl:value-of select="tei:doc/tei:TEI/tei:teiHeader//tei:settingDesc/tei:setting/tei:date/@when"/>
      </item>
    </xsl:for-each>
  </xsl:variable>
  <xsl:variable name="corpusFrom" select="replace(min($dates/tei:item/translate(.,'-','')),'(....)(..)(..)','$1-$2-$3')"/>
  <xsl:variable name="corpusTo" select="replace(max($dates/tei:item/translate(.,'-','')),'(....)(..)(..)','$1-$2-$3')"/>


  <!-- Numbers of speeches in component files -->
  <xsl:variable name="speeches">
    <xsl:for-each select="$docs/tei:item">
      <item n="{tei:xi-orig}">
        <xsl:value-of select="count(tei:doc/tei:TEI/tei:text//tei:u)"/>
      </item>
    </xsl:for-each>
  </xsl:variable>

  <!-- calculate tagUsages in component files -->
  <xsl:variable name="tagUsages">
    <xsl:for-each select="$docs/tei:item">
      <item n="{tei:xi-orig}">
        <xsl:variable name="context-node" select="."/>
        <xsl:for-each select="tei:doc/
                            distinct-values(tei:TEI/tei:text/descendant-or-self::tei:*/name())">
          <xsl:sort select="."/>
          <xsl:variable name="elem-name" select="."/>
          <!--item n="{$elem-name}">
              <xsl:value-of select="$context-node/tei:doc/
                                    count(tei:TEI/tei:text/descendant-or-self::tei:*[name()=$elem-name])"/>
          </item-->
          <xsl:element name="tagUsage">
            <xsl:attribute name="gi" select="$elem-name"/>
            <xsl:attribute name="occurs" select="$context-node/tei:doc/
                                    count(tei:TEI/tei:text/descendant-or-self::tei:*[name()=$elem-name])"/>
          </xsl:element>
        </xsl:for-each>
      </item>
    </xsl:for-each>
  </xsl:variable>

  <xsl:template match="/">
    <xsl:message select="concat('INFO: Starting to process ', tei:teiCorpus/@xml:id)"/>
    <!-- Process component files -->
    <xsl:for-each select="$docs//tei:item">
      <xsl:variable name="this" select="tei:xi-orig"/>
      <xsl:message select="concat('INFO: Processing ', $this)"/>
      <xsl:result-document href="{tei:url-new}">
        <xsl:apply-templates mode="comp" select="tei:doc/tei:TEI">
          <xsl:with-param name="words" select="$words/tei:item[@n = $this]"/>
          <xsl:with-param name="speeches" select="$speeches/tei:item[@n = $this]"/>
          <xsl:with-param name="tagUsages" select="$tagUsages/tei:item[@n = $this]"/>
          <xsl:with-param name="date" select="$dates/tei:item[@n = $this]/text()"/>
        </xsl:apply-templates>
      </xsl:result-document>
      <xsl:message select="concat('INFO: Saving to ', tei:xi-new)"/>
    </xsl:for-each>
    <!-- Output Root file -->
    <xsl:message>INFO: processing root </xsl:message>
    <xsl:result-document href="{$outRoot}">
      <xsl:apply-templates/>
    </xsl:result-document>
  </xsl:template>

  <xsl:template mode="comp" match="*">
    <xsl:param name="words"/>
    <xsl:param name="speeches"/>
    <xsl:param name="tagUsages"/>
    <xsl:param name="date"/>
    <xsl:copy>
      <xsl:apply-templates mode="comp" select="@*"/>
      <xsl:apply-templates mode="comp">
        <xsl:with-param name="words" select="$words"/>
        <xsl:with-param name="speeches" select="$speeches"/>
        <xsl:with-param name="tagUsages" select="$tagUsages"/>
        <xsl:with-param name="date" select="$date"/>
      </xsl:apply-templates>
    </xsl:copy>
  </xsl:template>

  <xsl:template mode="comp" match="@*">
    <xsl:copy/>
  </xsl:template>

  <xsl:template mode="comp" match="tei:div">
    <xsl:param name="words"/>
    <xsl:param name="speeches"/>
    <xsl:param name="tagUsages"/>
    <xsl:param name="date"/>
    <xsl:copy>
      <xsl:attribute name="type">
        <xsl:choose>
          <xsl:when test="./tei:u">debateSection</xsl:when>
          <xsl:otherwise>commentSection</xsl:otherwise>
        </xsl:choose>
      </xsl:attribute>
      <xsl:apply-templates mode="comp">
        <xsl:with-param name="words" select="$words"/>
        <xsl:with-param name="speeches" select="$speeches"/>
        <xsl:with-param name="tagUsages" select="$tagUsages"/>
        <xsl:with-param name="date" select="$date"/>
      </xsl:apply-templates>
    </xsl:copy>
  </xsl:template>

  <xsl:template mode="comp" match="tei:titleStmt">
    <xsl:copy>
      <xsl:apply-templates select="tei:title"/>
      <xsl:apply-templates select="tei:meeting"/>
      <xsl:call-template name="add-respStmt"/>
      <xsl:call-template name="add-funder"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template mode="comp" match="tei:extent">
    <xsl:param name="words"/>
    <xsl:param name="speeches"/>
    <xsl:copy>
      <xsl:call-template name="add-measure-speeches">
        <xsl:with-param name="quantity" select="$speeches"/>
      </xsl:call-template>
      <xsl:call-template name="add-measure-words">
        <xsl:with-param name="quantity" select="$words"/>
      </xsl:call-template>
    </xsl:copy>
  </xsl:template>

  <xsl:template mode="comp" match="tei:recording[@type='audio']/tei:media/@url">
    <xsl:attribute name="url" select="replace(.,'^[0-9]*ps/audio/','audio/psp/')"/>
  </xsl:template>

  <!-- Same as for root -->
  <xsl:template mode="comp" match="tei:publicationStmt">
    <xsl:call-template name="add-publicationStmt"/>
  </xsl:template>
  <xsl:template mode="comp" match="tei:editionStmt/tei:edition">
    <xsl:call-template name="add-edition"/>
  </xsl:template>
  <xsl:template mode="comp" match="tei:meeting">
    <xsl:apply-templates select="."/>
  </xsl:template>
  <xsl:template mode="comp" match="tei:settingDesc/tei:setting">
    <xsl:call-template name="add-setting"/>
  </xsl:template>

  <xsl:template mode="comp" match="tei:encodingDesc">
    <xsl:param name="tagUsages"/>
    <xsl:copy copy-namespaces="no">
      <xsl:apply-templates select="@*"/>
      <xsl:call-template name="add-projectDesc"/>
      <xsl:call-template name="add-tagsDecl">
        <xsl:with-param name="tagUsages" select="$tagUsages"/>
      </xsl:call-template>
    </xsl:copy>
  </xsl:template>

  <!-- Remove leading, trailing and multiple spaces -->
  <xsl:template mode="comp" match="text()[normalize-space(.)]">
    <xsl:variable name="str" select="replace(., '\s+', ' ')"/>
    <xsl:choose>
      <xsl:when test="(not(preceding-sibling::tei:*) and matches($str, '^ ')) and
                      (not(following-sibling::tei:*) and matches($str, ' $'))">
        <xsl:value-of select="replace($str, '^ (.+?) $', '$1')"/>
      </xsl:when>
      <xsl:when test="not(preceding-sibling::tei:*) and matches($str, '^ ')">
        <xsl:value-of select="replace($str, '^ ', '')"/>
      </xsl:when>
      <xsl:when test="not(following-sibling::tei:*) and matches($str, ' $')">
        <xsl:value-of select="replace($str, ' $', '')"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="$str"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- Finalizing ROOT -->
  <xsl:template match="*">
    <xsl:copy>
      <xsl:apply-templates select="@*"/>
      <xsl:apply-templates/>
    </xsl:copy>
  </xsl:template>
  <xsl:template match="@*">
    <xsl:copy/>
  </xsl:template>

  <xsl:template match="tei:teiCorpus">
    <xsl:copy>
      <xsl:apply-templates select="@*"/>
      <xsl:apply-templates select="tei:*"/>
      <xsl:for-each select="xi:include">
        <!--<xsl:sort select="@href"/>-->
        <xsl:variable name="href" select="@href"/>
        <xsl:variable name="new-href" select="$docs/tei:item[./tei:xi-orig/text() = $href]/tei:xi-new/text()"/>
        <xsl:message select="concat('INFO: Fixing xi:include: ',$href,' ',$new-href)"/>
        <xsl:copy>
          <xsl:attribute name="href" select="$new-href"/>
        </xsl:copy>
      </xsl:for-each>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="tei:teiHeader">
    <xsl:copy>
      <xsl:apply-templates select="@*"/>
      <fileDesc>
        <xsl:element name="titleStmt" xmlns="http://www.tei-c.org/ns/1.0">
          <xsl:apply-templates select="./tei:fileDesc/tei:titleStmt/tei:title"/>
          <xsl:for-each select="distinct-values($terms//tei:meeting/@n)">
            <xsl:sort select="."/>
            <xsl:variable name="term" select="."/>
            <xsl:apply-templates select="($terms//tei:meeting[@n=$term])[1]"/>
          </xsl:for-each>
          <xsl:call-template name="add-respStmt"/>
          <xsl:call-template name="add-funder"/>
        </xsl:element>
        <editionStmt>
          <xsl:call-template name="add-edition"/>
        </editionStmt>
        <extent>
          <xsl:call-template name="add-measure-speeches">
            <xsl:with-param name="quantity" select="sum($speeches/tei:item)"/>
          </xsl:call-template>
          <xsl:call-template name="add-measure-words">
            <xsl:with-param name="quantity" select="sum($words/tei:item)"/>
          </xsl:call-template>
        </extent>
        <xsl:call-template name="add-publicationStmt"/>
        <sourceDesc>
          <bibl>
            <title type="main" xml:lang="cs">Parlament České republiky, Poslanecká sněmovna</title>
            <title type="main" xml:lang="en">Parliament of the Czech Republic, Chamber of Deputies</title>
            <idno type="URI" subtype="parliament">https://www.psp.cz/eknih/</idno>
            <date from="{$corpusFrom}" to="{$corpusTo}"><xsl:value-of select="concat($corpusFrom,' - ',$corpusTo)"/></date>
          </bibl>
        </sourceDesc>
      </fileDesc>
      <encodingDesc>
        <xsl:call-template name="add-projectDesc"/>
        <editorialDecl>
          <correction>
            <p xml:lang="en">No correction of source texts was performed.</p>
          </correction>
          <normalization>
            <p xml:lang="en">Text has not been normalised, except for spacing.</p>
          </normalization>
          <hyphenation>
            <p xml:lang="en">No end-of-line hyphens were present in the source.</p>
          </hyphenation>
          <quotation>
            <p xml:lang="en">Quotation marks have been left in the text and are not explicitly marked up.</p>
          </quotation>
          <segmentation>
            <p xml:lang="en">The texts are segmented into utterances (speeches) and segments (corresponding to paragraphs in the source transcription).</p>
          </segmentation>
        </editorialDecl>
        <xsl:call-template name="add-tagsDecl">
          <xsl:with-param name="tagUsages">
            <xsl:for-each select="distinct-values($tagUsages//@gi)">
              <xsl:sort select="."/>
              <xsl:variable name="elem-name" select="."/>
              <tagUsage gi="{$elem-name}" occurs="{mk:number(sum($tagUsages//*[@gi=$elem-name]/@occurs))}"/>
            </xsl:for-each>
          </xsl:with-param>
        </xsl:call-template>
        <classDecl>
          <xsl:for-each select="$taxonomies/tei:item/text()">
            <xsl:sort select="."/>
            <xsl:variable name="taxonomy" select="."/>
            <xi:include xmlns:xi="http://www.w3.org/2001/XInclude" href="{$taxonomy}"/>
            <xsl:call-template name="copy-file">
              <xsl:with-param name="in" select="concat($inTaxonomiesDir,'/',$taxonomy)"/>
              <xsl:with-param name="out" select="concat($outDir,'/',$corpusDir, '/',$taxonomy)"/>
            </xsl:call-template>
          </xsl:for-each>
        </classDecl>
        <xsl:if test="$type = 'TEI.ana'">
          <listPrefixDef>
            <prefixDef ident="ud-syn" matchPattern="(.+)" replacementPattern="#$1">
               <p xml:lang="en">Private URIs with this prefix point to elements giving their name. In this document they are simply local references into the UD-SYN taxonomy categories in the corpus root TEI header.</p>
            </prefixDef>
            <prefixDef ident="pdt" matchPattern="(.+)" replacementPattern="pdt-fslib.xml#xpath(//fvLib/fs[./f/symbol/@value = '$1'])">
              <p xml:lang="en">Feature-structure elements definition of the Czech Positional Tags</p>
            </prefixDef>
            <prefixDef ident="ne" matchPattern="(.+)" replacementPattern="#NER.cnec2.0.$1">
              <p xml:lang="en">Taxonomy for named entities (cnec2.0)</p>
            </prefixDef>
          </listPrefixDef>
          <appInfo>
            <application ident="UDPipe" version="2">
              <label>UDPipe 2 (<xsl:value-of select="$model-udpipe"/> model)</label>
              <desc xml:lang="en">POS tagging, lemmatization and dependency parsing done with UDPipe 2 (<ref target="http://ufal.mff.cuni.cz/udpipe/2">http://ufal.mff.cuni.cz/udpipe/2</ref>) with <xsl:value-of select="$model-udpipe"/> model</desc>
            </application>
            <application ident="NameTag" version="2">
              <label>NameTag 2 (<xsl:value-of select="$model-nametag"/> model)</label>
              <desc xml:lang="en">Name entity recognition done with NameTag 2 (<ref target="http://ufal.mff.cuni.cz/nametag/2">http://ufal.mff.cuni.cz/nametag/2</ref>) with <xsl:value-of select="$model-nametag"/> model (<ref target="http://hdl.handle.net/11234/1-3443">http://hdl.handle.net/11234/1-3443</ref>). Posprocessing: nested named entities have been merged into four categories (PER, LOC, ORG, MISC).</desc>
            </application>
          </appInfo>
        </xsl:if>
      </encodingDesc>
      <xsl:call-template name="add-profileDesc"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template name="add-profileDesc">
    <profileDesc>
      <settingDesc>
        <xsl:call-template name="add-setting"/>
      </settingDesc>
      <textClass>
        <catRef scheme="#ParlaMint-taxonomy-parla.legislature" target="#parla.bi #parla.lower"/>
      </textClass>
      <particDesc>
        <xi:include xmlns:xi="http://www.w3.org/2001/XInclude" href="ParCzech-listOrg.xml"/>
        <xsl:call-template name="copy-file">
          <xsl:with-param name="in" select="$inListOrg"/>
          <xsl:with-param name="out" select="concat($outDir,'/',$corpusDir, '/ParCzech-listOrg.xml')"/>
        </xsl:call-template>
        <xi:include xmlns:xi="http://www.w3.org/2001/XInclude" href="ParCzech-listPerson.xml"/>
        <xsl:call-template name="copy-file">
          <xsl:with-param name="in" select="$inListPerson"/>
          <xsl:with-param name="out" select="concat($outDir,'/',$corpusDir, '/ParCzech-listPerson.xml')"/>
        </xsl:call-template>
      </particDesc>
      <langUsage>
        <language ident="cs" xml:lang="cs">čeština</language>
        <language ident="en" xml:lang="cs">angličtina</language>
        <language ident="cs" xml:lang="en">Czech</language>
        <language ident="en" xml:lang="en">English</language>
      </langUsage>
    </profileDesc>
  </xsl:template>

  <xsl:template name="add-measure-words">
    <xsl:param name="quantity"/>
    <xsl:call-template name="add-measure">
      <xsl:with-param name="quantity" select="$quantity"/>
      <xsl:with-param name="unit">words</xsl:with-param>
      <xsl:with-param name="en_text">words</xsl:with-param>
      <xsl:with-param name="cs_text">slov</xsl:with-param>
    </xsl:call-template>
  </xsl:template>

  <xsl:template name="add-measure-speeches">
    <xsl:param name="quantity"/>
    <xsl:call-template name="add-measure">
      <xsl:with-param name="quantity" select="$quantity"/>
      <xsl:with-param name="unit">speeches</xsl:with-param>
      <xsl:with-param name="en_text">speeches</xsl:with-param>
      <xsl:with-param name="cs_text">promluv</xsl:with-param>
    </xsl:call-template>
  </xsl:template>

  <xsl:template name="add-measure">
    <xsl:param name="quantity"/>
    <xsl:param name="unit"/>
    <xsl:param name="en_text"/>
    <xsl:param name="cs_text"/>
    <xsl:element name="measure">
      <xsl:attribute name="unit" select="$unit"/>
      <xsl:attribute name="quantity" select="mk:number($quantity)"/>
      <xsl:attribute name="xml:lang">cs</xsl:attribute>
      <xsl:value-of select="concat(mk:number($quantity),' ',$cs_text)"/>
    </xsl:element>
    <xsl:element name="measure">
      <xsl:attribute name="unit" select="$unit"/>
      <xsl:attribute name="quantity" select="mk:number($quantity)"/>
      <xsl:attribute name="xml:lang">en</xsl:attribute>
      <xsl:value-of select="concat(mk:number($quantity),' ',$en_text)"/>
    </xsl:element>
  </xsl:template>

  <xsl:template name="add-tagsDecl">
    <xsl:param name="tagUsages"/>
    <xsl:variable name="context" select="./tei:tagsDecl/tei:namespace[@name='http://www.tei-c.org/ns/1.0']"/>
    <xsl:element name="tagsDecl">
      <xsl:element name="namespace">
        <xsl:attribute name="name">http://www.tei-c.org/ns/1.0</xsl:attribute>
        <xsl:for-each select="distinct-values(($tagUsages//@gi,$context//@gi))">
          <xsl:sort select="."/>
          <xsl:variable name="elem-name" select="."/>
          <xsl:copy-of copy-namespaces="no" select="$tagUsages//*:tagUsage[@gi=$elem-name]"/>
        </xsl:for-each>
      </xsl:element>
    </xsl:element>
  </xsl:template>

  <xsl:template name="add-respStmt">
    <respStmt>
      <persName ref="https://orcid.org/0000-0001-7953-8783">Matyáš Kopp</persName>
      <resp xml:lang="en">Data retrieval</resp>
      <resp xml:lang="en">TEI XML corpus encoding</resp>
      <xsl:if test="$type = 'TEI.ana'">
        <resp xml:lang="en">Linguistic annotation</resp>
      </xsl:if>
    </respStmt>
  </xsl:template>

  <xsl:template name="add-funder">
    <funder>
      <orgName xml:lang="cs">LINDAT/CLARIAH-CZ: Digitální výzkumná infrastruktura pro jazykové technologie, umění a humanitní vědy</orgName>
      <orgName xml:lang="en">LINDAT/CLARIAH-CZ: Digital Research Infrastructure for Language Technologies, Arts and Humanities</orgName>
    </funder>
  </xsl:template>

  <xsl:template name="add-setting">
    <setting>
      <name type="org">Parlament České republiky - Poslanecká sněmovna</name>
      <name type="address">Sněmovní 176/4</name>
      <name type="city">Praha</name>
      <name key="CZ" type="country">Czech Republic</name>
      <xsl:choose>
        <xsl:when test="./tei:date[parent::tei:setting]/@when">
          <xsl:apply-templates select="./tei:date"/>
        </xsl:when>
        <xsl:otherwise>
          <date from="{$corpusFrom}" to="{$corpusTo}"><xsl:value-of select="concat($corpusFrom,' - ',$corpusTo)"/></date>
        </xsl:otherwise>
      </xsl:choose>
    </setting>
  </xsl:template>


<xsl:template name="add-edition">
    <edition><xsl:value-of select="$version"/></edition>
  </xsl:template>

  <xsl:template name="add-publicationStmt">
    <publicationStmt>
      <xsl:copy-of select="$publisher"/>
      <idno type="URI" subtype="handle"><xsl:value-of select="$handle"/></idno>
      <availability status="free">
        <licence>https://creativecommons.org/publicdomain/zero/1.0/</licence>
        <p xml:lang="en">This work is licensed under the <ref target="https://creativecommons.org/publicdomain/zero/1.0/">CC0 1.0 Universal (CC0 1.0) Public Domain Dedication</ref>.</p>
      </availability>
      <date when="{$today}"><xsl:value-of select="$today"/></date>
    </publicationStmt>
  </xsl:template>

  <xsl:template name="add-projectDesc">
    <projectDesc>
      <p xml:lang="en"><ref target="https://ufal.mff.cuni.cz/parczech">ParCzech</ref> is a project on compiling Czech parliamentary data into annotated corpora</p>
    </projectDesc>
  </xsl:template>


  <xsl:template name="copy-file">
    <xsl:param name="in"/>
    <xsl:param name="out"/>
    <xsl:message select="concat('INFO: copying file ',$in,' ',$out)"/>
    <xsl:result-document href="{$out}" method="text"><xsl:value-of select="unparsed-text($in,'UTF-8')"/></xsl:result-document>
  </xsl:template>

  <xsl:function name="mk:number">
    <xsl:param name="num"/>
    <xsl:value-of select="format-number($num,'#0')"/>
  </xsl:function>
</xsl:stylesheet>
