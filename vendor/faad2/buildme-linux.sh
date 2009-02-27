#!/bin/sh

FAAD=2.7
LOG=$PWD/config.log
CHANGENO=` svn info .  | grep -i Revision | awk -F": " '{print $2}'`
ARCH=`arch`
OUTPUT=$PWD/faad2-build-$ARCH-$CHANGENO

# Clean up
rm -rf $OUTPUT
rm -rf faad2-$FAAD

## Start
echo "Most log mesages sent to $LOG... only 'errors' displayed here"
date > $LOG

## Build
echo "Untarring..."
tar zxvf faad2-$FAAD.tar.gz >> $LOG
cd faad2-$FAAD >> $LOG
echo "Configuring..."
./configure --without-xmms --without-drm --without-mpeg4ip --disable-shared --prefix $OUTPUT >> $LOG
echo "Running make"
make frontend >> $LOG
echo "Running make install"
make install >> $LOG
cd ..

## Tar the whole package up
tar -zcvf $OUTPUT.tgz $OUTPUT
rm -rf $OUTPUT
rm -rf faad2-$FAAD
