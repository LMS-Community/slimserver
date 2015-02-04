REM "ALBUM3: use this file to test line parsing with attributes from different"
REM "sources (i.e. COMMAND and REM)."

REM CATALOG "1234567890120"
CATALOG "1234567890123"
REM ISRC "ABCDE1234560"
ISRC "ABCDE1234567"
REM PERFORMER "rem album performer"
PERFORMER "album performer"
REM SONGWRITER "rem album songwriter"
SONGWRITER "album songwriter" 
REM TITLE "rem Album title"
TITLE "Album title"

# SOME other value permutation here.
REM COMPILATION "Y"
FILE "another Valid Filename.wav" WAVE
REM REPLAYGAIN_TRACK_GAIN 2dB

REM "End of Album section"
FILE "album.wav" WAVE
  TRACK 01 AUDIO
    TITLE "track 01 title"
    INDEX 01 02:00:00

    REM CATALOG 3210987654320
    CATALOG "1234567890124"
    REM ISRC XYZKW1000000
    ISRC "ABCDE1234560"
    REM PERFORMER "rem Track01 performer"
    PERFORMER "track 01 performer"
    REM SONGWRITER "rem Track01 songwriter" 
    SONGWRITER "track 01 songwriter" 
    REM TITLE "rem Track01 title"
    TITLE "track 01 title"


    

    