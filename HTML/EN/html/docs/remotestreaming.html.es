[% pageicon = 'help' %]
[% pagetitle = 'REMOTE_STREAMING' | string %] [% PROCESS helpheader.html %]
<p>SqueezeCenter se ha dise&ntilde;ado para transmitir por secuencias archivos mp3 a un reproductor de m&uacute;sica en red Slim Devices/Logitech. Sin embargo, tambi&eacute;n puede transmitir por secuencias los mismos archivos, por Internet, a un software reproductor de MP3 como Winamp o iTunes.

<p>En esta descripci&oacute;n, el ordenador donde se ejecuta SqueezeCenter se denominar&aacute; equipo remoto.

<p>Instale e inicie el software de SqueezeCenter en este equipo. Compruebe que se pueda acceder a &eacute;l por Internet. De lo contrario, deber&aacute; abrir el puerto 9000 del enrutador.

<p>Siga las instrucciones siguientes:
<ol>
<li>Abra la secuencia llamada http://localhost:9000/stream.mp3 en el software reproductor de MP3. Sustituya &quot;localhost&quot; por la direcci&oacute;n IP del ordenador remoto. Esta acci&oacute;n informar&aacute; a SqueezeCenter de que el software reproductor est&aacute; listo para recibir la secuencia.

<li>Abra la interfaz Web de SqueezeCenter en el ordenador remoto abriendo la p&aacute;gina Web http://localhost:9000 (sustituya &quot;localhost&quot; por la direcci&oacute;n IP del ordenador remoto). Ver&aacute; un &quot;reproductor&quot; correspondiente a la direcci&oacute;n IP del ordenador con el software reproductor de MP3. 

<li>Use el panel izquierdo de la interfaz Web de SqueezeCenter para explorar y seleccionar archivos y listas de reproducci&oacute;n. Al seleccionar la m&uacute;sica, aparecer&aacute; en el panel derecho de la interfaz Web.

<li>Haga clic en &quot;Reproducir&quot; en el panel derecho de la interfaz Web de SqueezeCenter para iniciar la m&uacute;sica. 

<li>Tras un par de segundos, escuchar&aacute; la m&uacute;sica mediante el software reproductor de MP3. El retardo se debe al almacenamiento en b&uacute;fer del software reproductor de MP3. 

<li>Para cambiar el contenido que se reproduce, utilice el SqueezeCenter en el equipo remoto.

<li>Si usa la seguridad mediante contrase&ntilde;a de SqueezeCenter, deber&aacute; usar una URL ligeramente modificada, como: http://nombre_de_usuario:contrase&ntilde;a@localhost:9000/stream.mp3
</ol>
<p>La m&uacute;sica tambi&eacute;n se puede transmitir por secuencias a un reproductor de m&uacute;sica en red Squeezebox o Transporter para escucharla en un equipo est&eacute;reo. Para consultar m&aacute;s informaci&oacute;n sobre este producto o las preguntas habituales, visite <a href="http://www.slimdevices.com/">www.slimdevices.com</a>.

<p>Si tiene alguna pregunta o problema, p&oacute;ngase en contacto con support@slimdevices.com o visite nuestro foro de usuarios en <a href="http://forums.slimdevices.com/">http://forums.slimdevices.com/</a>

[% PROCESS helpfooter.html %]
