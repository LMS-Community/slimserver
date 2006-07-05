<script type="text/javascript">
	<!-- Start Hiding the Script
	function switchPlayer(player_List) {
		var newPlayer = "=" + player_List.options[player_List.selectedIndex].value;
		var myString = new String(this.location);
		var rExp = /(=(\w\w(:|%3A)){5}(\w\w))|(=(\d{1,3}\.){3}\d{1,3})/gi;
		this.location = myString.replace(rExp, newPlayer);
	}

	function setCookie(name, value) {
		var expires = new Date();
		expires.setTime(expires.getTime() + 1000*60*60*24*365);
		document.cookie =
			name + "=" + escape(value) +
			((expires == null) ? "" : ("; expires=" + expires.toGMTString()));
	}

	function toggleGalleryView(artwork) {
	
		if (artwork) {
			setCookie( 'SlimServer-albumView', "&artwork=1" );
			this.location=this.location.href+"&artwork=1";
		} else {
			setCookie( 'SlimServer-albumView', "" );
			myString = new String(this.location.href);
			var rExp = /\&artwork=1/gi;
			this.location=myString.replace(rExp, "");
		}
	}

	// Stop Hiding script --->
</script> 
