<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

<xsl:template match="/">
 <div>
  <xsl:for-each select="/livesearch/searchresults">
   <p>
    <xsl:value-of select="@mstring"/>
   </p>
   <table>
    <xsl:for-each select="livesearchitem">
     <tr>
      <td class="browselistbuttons">
       <img onclick="parent.updateStatusCombined(&quot;&amp;command=playlist&amp;sub=addtracks&amp;{../@type}={@id}&quot;)"
            src="html/images/add.gif" width="8" height="8"/>
       <img onclick="parent.updateStatusCombined(&quot;&amp;command=playlist&amp;sub=loadtracks&amp;{../@type}={@id}&quot;)"
            src="html/images/play.this.gif" width="5" height="9"/>
      </td>
      <td class="browselisting">
       <a onclick="parent.browseurl(&quot;browsedb.html?hierarchy={../@hierarchy}&amp;level=0&amp;{../@type}={@id}&quot;)">
        <xsl:value-of select="."/>
       </a>
      </td>
     </tr>
    </xsl:for-each>
   </table>
  </xsl:for-each>
 </div>
</xsl:template>
</xsl:stylesheet>
