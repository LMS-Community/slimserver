#@echo off

setlocal
 
set ipaddr=192.168.0.6

set server=G:\Sviluppo\slimserver\slimserver.pl

set squeezedir=C:\Documents and Settings\All Users\Dati applicazioni\SqueezeboxTest

set prefsdir=%squeezedir%\prefs

set cachedir=%squeezedir%\cache

set logdir=%squeezedir%\logs
cmd.exe /c ""C:\Perl\bin\perl.exe" "%server%" --playeraddr %ipaddr% --streamaddr %ipaddr% --httpaddr %ipaddr% --cliaddr %ipaddr% --prefsdir "%prefsdir%" --cachedir "%cachedir%" --logdir "%logdir%""