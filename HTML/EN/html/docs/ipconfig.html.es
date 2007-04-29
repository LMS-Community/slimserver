[% pageicon = 'help' %]
[% pagetitle = 'Player Network Setup' %] [% PROCESS helpheader.html %]

<p>
La configuraci&oacute;n de Squeezebox o Transporter en una red es muy similar a la de un ordenador en una red. Se debe conocer la informaci&oacute;n siguiente:
</p>

<ul>
<li>&iquest;La red admite DHCP? En caso afirmativo, no se requiere configuraci&oacute;n. El reproductor obtendr&aacute; autom&aacute;ticamente su direcci&oacute;n IP y localizar&aacute; el PC servidor en la red.
<li>Si la red no tiene DHCP, deber&aacute; configurar el reproductor utilizando direcciones IP est&aacute;ticas. Deber&aacute; conocer la direcci&oacute;n IP del ordenador y necesitar&aacute; una direcci&oacute;n IP disponible para asignarla al reproductor Squeezebox o Transporter.
</ul>

<h4>El men&uacute; de configuraci&oacute;n</h4>

<p> Al encender por primera vez el reproductor, preguntar&aacute; si se desea cambiar la configuraci&oacute;n de red. </p>

<img src="vfdshots/setup.gif">

<p>
Use los botones arriba y abajo para seleccionar una opci&oacute;n. Puede ir al men&uacute; de configuraci&oacute;n u omitir &eacute;sta y usar los par&aacute;metros anteriores. Pulse abajo una vez para elegir &quot;S&iacute;, ir al men&uacute; de configuraci&oacute;n&quot; y, a continuaci&oacute;n, pulse derecha.</p>

<img src="vfdshots/choose_auto.gif">

<p>Aqu&iacute; hay tres opciones:</p>

<ul>
  <li><b>Completamente autom&aacute;tica</b>: la opci&oacute;n m&aacute;s f&aacute;cil para la mayor&iacute;a de las redes. El reproductor obtendr&aacute; su direcci&oacute;n IP mediante DHCP y localizar&aacute; el servidor autom&aacute;ticamente mediante Slim Discovery Protocol. 
  <li><b>Especificar servidor manualmente</b>: se usar&aacute; DHCP, pero la direcci&oacute;n IP del servidor se introducir&aacute; manualmente. Use esta opci&oacute;n si el servidor no est&aacute; en la misma LAN que el reproductor. Consulte el documento siguiente, Redes avanzadas, si desea m&aacute;s informaci&oacute;n sobre esta opci&oacute;n.
  <li><b>Introducir todo manualmente</b>: se usar&aacute;n IP est&aacute;ticas para todo. Elija esta opci&oacute;n si la red no admite DHCP.
</ul>

<h4>Usar DHCP</h4>

<p>
Para usar DHCP, seleccione &quot;Completamente autom&aacute;tica&quot; y pulse derecha. El reproductor pedir&aacute; que se confirme la selecci&oacute;n. Pulse derecha otra vez para confirmar. Y esto es todo. El reproductor tardar&aacute; un par de segundos en localizar el servidor DHCP y realizar&aacute; la conexi&oacute;n.
</p>

<h4>Usar direcci&oacute;n IP est&aacute;tica</h4>

<p>
Para configurar el reproductor mediante direcciones IP est&aacute;ticas, seleccione &quot;Introducir todo manualmente&quot;. Esta acci&oacute;n le llevar&aacute; a una serie de pantallas, en las que puede introducir la direcci&oacute;n IP del reproductor, la m&aacute;scara de red, la direcci&oacute;n del enrutador y la direcci&oacute;n IP del servidor. Para introducir las direcciones, use los botones derecha/izquierda para seleccionar el d&iacute;gito que desee editar y arriba/abajo para cambiar dicho d&iacute;gito. Pulse &quot;ok&quot; para pasar a la pantalla siguiente (el bot&oacute;n &quot;ok&quot; est&aacute; justo debajo y a la derecha de los botones de flechas).
</p>

<img src="vfdshots/setup_myip.gif">

<p>Cuando haya introducido todas las direcciones, ver&aacute; el mensaje siguiente. Ahora puede pulsar izquierda para revisar los cambios o derecha para guardarlos y salir del men&uacute; de configuraci&oacute;n.</p>

<img src="vfdshots/setup_done.gif">

[% PROCESS helpfooter.html %]
