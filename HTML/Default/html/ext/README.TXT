Using JSBuilder2 to build optimized ExtJS packages
--------------------------------------------------

I've built two versions of the ExtJS framework optimized for our needs:

- ext-browse: used in the main navigation panel (left hand side). As this page
              very frequently, this version is stripped down to the bare minimum
              to speed up page loading/building

- ext-main:   this version includes all the ExtJS code required in the rest of
              the Logitech Media Server web UI, but still much less than ext-all

In order to build/update these two files download the latest version of ExtJS from
extjs.com. Copy /trunk/tools/JSBuilder/JSBuilder2.jar to the extracted extjs-x.y.z
folder. Edit ext-squeezebox.jsb2 to your needs (it's based on the default ext.jsb2
file), copy it to the same folder, and compile the packages:

java -jar JSBuilder2.jar --projectFile ./ext-squeezebox.jsb2 --homeDir .

Please note that you'll need at least Java 6 to run JSBuilder2.

-- Michael 