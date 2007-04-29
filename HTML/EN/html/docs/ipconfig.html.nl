[% pageicon = 'help' %]
[% pagetitle = 'Player Network Setup' %] [% PROCESS helpheader.html %]

<p>
Het instellen van je Squeezebox of Transporter voor je netwerk is vrijwel hetzelfde als het instellen van een computer op een netwerk. Je moet de volgende informatie hebben:
</p>

<ul>
<li>Ondersteunt je netwerk DHCP? Als dit zo is, is configureren niet nodig. De speler haalt automatisch zijn IP-adres op en zoekt je server-pc op het netwerk.
<li>Als het netwerk geen DHCP heeft, moet je de speler met behulp van statische IP-adressen configureren. Je moet het IP-adres van de computer weten, en je moet &eacute;&eacute;n vrij IP-adres hebben dat aan de Squeezebox of Transporter toegewezen kan worden.
</ul>

<h4>Het set-upmenu</h4>

<p> Wanneer de speler voor het eerst wordt aangezet, wordt je gevraagd of je de netwerkinstellingen wilt wijzigen. </p>

<img src="vfdshots/setup.gif">

<p>
Gebruik de knoppen omhoog en omlaag om een optie te selecteren. Je kunt naar het set-upmenu gaan, of de set-up overslaan en de vorige instellingen gebruiken. Druk eenmaal op omlaag en kies de optie om naar het set-upmenu te gaan. Druk dan op het pijltje naar rechts.</p>

<img src="vfdshots/choose_auto.gif">

<p>Je hebt hier drie mogelijkheden:</p>

<ul>
  <li><b>Geheel automatisch</b> - Dit is de gemakkelijkste manier voor de meeste netwerken. De speler haalt zijn IP-adres via DHCP op en zoekt de server automatisch via het Slim Discovery Protocol. 
  <li><b>Sever handmatig opgeven</b> - DHCP wordt gebruikt, maar het IP-adres van de server wordt handmatig ingevoerd. Gebruik deze optie als de server zich niet op hetzelfde LAN bevindt als de speler. Raadpleeg het volgende document, Geavanceerd netwerken voor meer informatie over deze optie.
  <li><b>Alles handmatig invoeren</b> - Voor alles worden statische IP's gebruikt. Kies deze optie als uw netwerk DHCP niet ondersteunt.
</ul>

<h4>DHCP gebruiken</h4>

<p>
Kies gewoon 'Geheel automatisch' en druk op het pijltje naar rechts om DHCP te gebruiken. Je wordt gevraagd je keuze te bevestigen. Druk nogmaals op het pijltje naar rechts om dit te doen. Klaar. Het duurt een seconde of twee voordat de speler jouw DHCP-server gevonden heeft. Vervolgens wordt je verbonden.
</p>

<h4>Statische IP-adressen gebruiken</h4>

<p>
Kies 'Alles handmatig invoeren' om de speler met behulp van statische IP-adressen te configureren. Je gaat dan naar een reeks van vier schermen, waar je het IP-adres van de speler, de netmasker, het routeradres en het IP-adres van de server kunt invoeren. Gebruik de pijltjes naar links en rechts om het cijfer te kiezen dat je wilt wijzigen, en omhoog/omlaag om dat cijfer te veranderen. Druk op 'OK' om naar het volgende scherm te gaan (de knop OK bevindt zich vlak onder de pijltjesknoppen aan de rechterkant).
</p>

<img src="vfdshots/setup_myip.gif">

<p>Wanneer je alle adressen ingevoerd hebt, verschijnt het volgende bericht. Je kunt nu op het pijltje naar links drukken om terug te gaan en de wijzigingen te bekijken, of op het pijltje naar rechts om de wijzigingen op te slaan en het set-upmenu af te sluiten.</p>

<img src="vfdshots/setup_done.gif">

[% PROCESS helpfooter.html %]
