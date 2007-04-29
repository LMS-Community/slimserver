[% pageicon = 'help' %]
[% pagetitle = 'REMOTE_STREAMING' | string %] [% PROCESS helpheader.html %]
<p>De SlimServer is ontworpen om mp3-bestanden naar een Slim Devices/Logitech-netwerkmuziekspeler te stromen. Dezelfde bestanden kunnen echter ook via het internet naar een MP3-softwarespeler zoals Winamp en iTunes gestroomd worden.

<p>Hier wordt de computer waarop de SlimServer uitgevoerd wordt, de externe machine genoemd.

<p>Eerst moet je de SlimServer-software op deze machine installeren en starten. Zorg ervoor dat de machine bereikbaar is via het internet.  Als dit niet zo is, moet je poort 9000 op je router openen.

<p>Volg nu deze instructies:
<ol>
<li>Open de stroom genaamd http://localhost:9000/stream.mp3 in je MP3-softwarespeler. (Vervang 'localhost' met het IP-adres van de externe computer.) De SlimServer weet dan dat de softwarespeler klaar is om een stroom te ontvangen.

<li>Open de webinterface van de SlimServer die op de externe computer wordt uitgevoerd door de webpagina http://localhost:9000 te openen (Vervang 'localhost' met het IP-adres van de externe computer.) Je zult merken dat een 'speler' overeenkomt met het IP-adres van de computer waarop de MP3-softwarespeler zich bevindt. 

<li>Gebruik het linkerpaneel van de SlimServer-webinterface om bestanden en playlists te zoeken en selecteren.  Wanneer muziek wordt geselecteerd, verschijnt deze in het rechterpaneel van de webinterface.

<li>Klik op 'Afspelen' in het rechterpaneel van de SlimServer-webinterface om de muziek te starten. 

<li>Na enkele seconden hoor je dat er muziek afgespeeld wordt via de MP3-softwarespeler. (De vertraging wordt veroorzaakt door bufferen in de MP3-spelersoftware.) 

<li>Gebruik de SlimServer op de externe machine om de afgespeelde inhoud te wijzigen.

<li>Als je de wachtwoordbeveiliging van de SlimServer gebruikt, moet je een enigszins gewijzigde URL gebruiken zoals deze: http://username:password@localhost:9000/stream.mp3
</ol>
<p>De muziek kan ook naar een Squeezebox- of Transporter-netwerkmuziekspeler gestroomd worden, zodat je er op een stereo naar kunt luisteren.  Ga naar <a href="http://www.slimdevices.com/">www.slimdevices.com</a> voor meer informatie over dit product en veelgestelde vragen.

<p>Heb je een vraag of probleem, neem dan contact op via 'support@slimdevices.com' of ga naar ons gebruikersforum op <a href="http://forums.slimdevices.com/">http://forums.slimdevices.com/</a>

