<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="http://www.tei-c.org/ns/1.0"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  exclude-result-prefixes="tei" >

  <xsl:output method="xml" indent="yes" encoding="UTF-8" />
  <xsl:param name="roles" />

  <xsl:template match="/tei:listOrg">
    <xsl:copy>
      <xsl:apply-templates select="@*" />
      <xsl:apply-templates select="tei:org[not(contains(concat('|',$roles,'|'),concat('|',./@role,'|') ))]" />
      <xsl:call-template name="role-merger">
        <xsl:with-param name="role-list" select="concat($roles,'|')" />
      </xsl:call-template>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>


  <xsl:template name="role-merger">
    <xsl:param name="role-list" />
    <xsl:variable name="act-role" select="substring-before($role-list,'|')" />
    <xsl:variable name="next-role-list" select="substring-after($role-list,'|')" />
    <xsl:if test="$act-role">
      <xsl:message>'<xsl:value-of select="$act-role" />': <xsl:value-of select="$next-role-list" /></xsl:message>
      <xsl:variable name="first" select="./tei:org[./@role = string($act-role)][1]" />

      <xsl:message><xsl:value-of select="translate(string-join(./tei:org[@role=$act-role]/tei:event/@from,' '),'-','')" /></xsl:message>

      <xsl:if test="$first">
        <xsl:message>'<xsl:value-of select="$act-role" />': <xsl:value-of select="$first/@xml:id" /></xsl:message>
        <xsl:element name="org">
          <xsl:attribute name="xml:id"><xsl:value-of select="$act-role" /></xsl:attribute>
          <xsl:attribute name="role"><xsl:value-of select="$act-role" /></xsl:attribute>
          <xsl:call-template name="add-attr">
            <xsl:with-param name="category" select="$act-role" />
          </xsl:call-template>
          <xsl:copy-of select="$first/tei:orgName[@full='yes']" />
          <xsl:element name="listEvent">
            <xsl:call-template name="add-event-head">
              <xsl:with-param name="category" select="$act-role" />
            </xsl:call-template>
            <xsl:for-each select="./tei:org[./@role = string($act-role)]">
              <xsl:sort select="./tei:event/@from" data-type="text" order="ascending"/>
              <xsl:element name="event">
                <xsl:copy-of select="./@xml:id" />
                <xsl:copy-of select="./tei:event/@from" />
                <xsl:copy-of select="./tei:event/@to" />
                <xsl:choose>
                  <xsl:when test="$act-role = 'parliament' or $act-role = 'senate' ">
                    <!-- use term number in labels -->
                    <xsl:variable name="term" select="number(translate(substring-after(@xml:id,'.'),'PSE',''))" />
                    <label xml:lang="cs"><xsl:value-of select="$term" />. volební období</label>
                    <label xml:lang="en">term <xsl:value-of select="$term" /></label>
                  </xsl:when>
                  <xsl:otherwise>
                    <!-- use title and extend it with date -->
                    <xsl:for-each select="./tei:orgName[@full='yes']">
                      <xsl:sort select="./xml:lang" data-type="text" order="ascending"/>
                      <xsl:element name="label">
                        <xsl:copy-of select="@xml:lang" />
                        <xsl:value-of select="concat( ./text(),' (',./../tei:event/@from, ' - ',./../tei:event/@to,')' )" />
                      </xsl:element>
                    </xsl:for-each>
                  </xsl:otherwise>
                </xsl:choose>
              </xsl:element>
            </xsl:for-each>
          </xsl:element>

        </xsl:element>
      </xsl:if>
      <xsl:call-template name="role-merger">
        <xsl:with-param name="role-list" select="$next-role-list" />
      </xsl:call-template>
    </xsl:if>
  </xsl:template>


  <xsl:template name="add-attr">
    <xsl:param name="category" />
    <xsl:choose>
      <xsl:when test="$category = 'parliament'">
        <xsl:attribute name="ana">#parla.national #parla.lower</xsl:attribute>
      </xsl:when>
      <xsl:when test="$category = 'senate'">
        <xsl:attribute name="ana">#parla.national #parla.upper</xsl:attribute>
      </xsl:when>
    </xsl:choose>
  </xsl:template>

  <xsl:template name="add-event-head">
    <xsl:param name="category" />
    <xsl:choose>
      <xsl:when test="$category = 'parliament' or $category = 'senate' ">
        <head xml:lang="cs">Volební období</head>
        <head xml:lang="en">Legislative period</head>
      </xsl:when>
    </xsl:choose>
  </xsl:template>

</xsl:stylesheet>