<script type="text/javascript">
	<!-- Start Hiding the Script
	function switchPlayer(player_List) {
		setCookie( 'SlimServer-player', player_List.options[player_List.selectedIndex].value );
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
	
		myString = new String(this.location.href);

		if (artwork) {
			setCookie( 'SlimServer-albumView', "1" );
			
			if (this.location.href.indexOf('start') == -1) {
				this.location=this.location.href+"&artwork=1";
			} else {
				myString = new String(this.location.href);
				var rExp = /\&start=/gi;
				this.location=myString.replace(rExp, "&artwork=1&start=");
			}
		} else {

			setCookie( 'SlimServer-albumView', "" );
			
			var rExp = /\&artwork=1/gi;
			this.location=myString.replace(rExp, "");
		}
	}

	// Stop Hiding script --->
</script> 
