Logitech Media Server
====

Logitech Media Server (aka. LMS, fka. SlimServer, SqueezeCenter, SqueezeboxServer, SliMP3) is the server software that powers audio players from [Logitech](https://www.logi.com) (formerly known as SlimDevices), including [Squeezebox 3rd Generation, Squeezebox Boom, Squeezebox Receiver, Transporter, Squeezebox2, Squeezebox and SLIMP3](http://wiki.slimdevices.com/index.php/Squeezebox_Family_Overview), and many software emulators like [Squeezelite and SqueezePlay](https://sourceforge.net/projects/lmsclients/files/).

With the help of many plugins, Logitech Media Server can stream not only your local music collection, but content from many music services and internet radio stations to your players.

Logitech Media Server is written in Perl. It runs on pretty much any platform that Perl runs on, including Linux, Mac OSX, Solaris and Windows.

## SB Radio and Logitech Media Server 8+

Unfortunately the latest Squeezebox Radio firmware (7.7.3) comes with a bug which prevents it from connecting correctly to Logitech Media Server 8+. It's version string comparison function fails to recognize 8.0.0 as more recent than 7.7.3. While the bug has been fixed years ago, the fixed firmware never got released. Unfortunately we're at this point not able to build a fixed firmware for distribution.

But there's a patch available, which you can easily install on an existing SB Radio:

* On the Radio go to Settings/Advanced/Applet Installer. Make sure "Recommended Applets Only" is unchecked, then install the Patch Installer. The Radio will re-boot.
* Once it's back, go to Settings/Advanced/Patch Installer and install the "Version Comparison Fix".

Enjoy the music on your SB Radio!
