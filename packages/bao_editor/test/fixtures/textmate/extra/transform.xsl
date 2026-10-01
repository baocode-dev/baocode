<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <!-- Lists the books. -->
  <xsl:template match="/">
    <html>
      <body>
        <xsl:for-each select="catalog/book[@price &gt; 10]">
          <p><xsl:value-of select="title"/> by <xsl:value-of select="author"/></p>
        </xsl:for-each>
        <xsl:if test="count(catalog/book) = 0">None</xsl:if>
      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>
