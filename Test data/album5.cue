REM "ALBUM5: use this file to further test validations and aggregation made by the 
REM "section immediatly after the line parsing".

REM "Here no attributes are filled at album level, see previous example."

REM "End of Album section"

TITLE "Album title"
FILE "album.wav" WAVE
  TRACK 01 AUDIO
    TITLE "track 01 title"
    INDEX 01 01:00:00

    REM DISCC 2
    PERFORMER "rem Track08 performer"
    REM COMPOSER "rem Track01 composer"

TRACK 02 AUDIO
    TITLE "track 02 title"
    INDEX 01 02:00:00
