var thumbSize = [% IF thumbSize %][% thumbSize %][% ELSE %]250[% END %];
function chooseAlbumOrderBy(value, option, artwork)
{
	if (!artwork) {
		artwork = 1;
	}
        var url = '[% webroot %]browsedb.html?hierarchy=[% hierarchy %]&level=[% level %][% attributes %][% IF artwork %]&artwork='+artwork+'[% END %]&player=[% playerURI %]'; 
        if (option) {
                url = url + '&orderBy=' + option;
        }
        setCookie( 'SlimServer-orderBy', option );
        window.location = url;
}

function setCookie(name, value) {
        var expires = new Date();
        expires.setTime(expires.getTime() + 1000*60*60*24*365);
        document.cookie =
                name + "=" + escape(value) +
                ((expires == null) ? "" : ("; expires=" + expires.toGMTString()));
}
