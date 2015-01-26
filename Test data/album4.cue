REM "ALBUM4: use this file to test validations and aggregation made by the section"
REM "immediatly after the line parsing".
REM "Here some attributes are filled at album level, see next example to test the"
REM "aggregation to album level for this attributes and others"

REM DATE 1982
REM YEAR 1981

REM DISCNUMBER 1
REM DISC 1

REM "switch DISCTOTAL and TOTALDISCS for a complete test, see tracks"
REM DISCTOTAL 2
REM TOTALDISCS 2
REM DISCC 2

REM "switch ALBUMARTIST and ARTIST for a complete test"
REM ALBUMARTIST "rem album artist in album"
REM ARTIST "rem artist in album"
PERFORMER "album performer"

SONGWRITER "album songwriter" 
REM COMPOSER "rem album composer"

REM ALBUMARTISTSORT "album artist sort"
REM ALBUMSORT "album sort"

REM "End of Album section"

TITLE "Album title"
FILE "album.wav" WAVE
  TRACK 01 AUDIO
    TITLE "track 01 title"
    INDEX 01 01:00:00

    REM DATE 1985
    REM YEAR 1983
    
    REM DISCNUMBER 1
    REM DISC 1

    REM TOTALDISCS 2
    REM DISCTOTAL 2
    REM DISCC 2
    
    REM ARTIST "rem artist in Track01"
    REM TRACKARTIST "track artist in Track01"
    REM PERFORMER "rem Track01 performer"

    REM COMPOSER "rem Track01 composer"
    SONGWRITER "track 01 songwriter"

TRACK 02 AUDIO
    TITLE "track 02 title"
    INDEX 01 02:00:00

    REM DISCTOTAL 2
    REM TOTALDISCS 2
    REM DISCC 2

    REM TRACKARTIST "track artist in Track02"
    REM ARTIST "rem artist in Track02"
    REM PERFORMER "rem Track02 performer"


TRACK 03 AUDIO
    TITLE "track 03 title"
    INDEX 01 03:00:00

    REM TRACKARTIST "track artist in Track03"
    REM PERFORMER "rem Track03 performer"
    REM ARTIST "rem artist in Track03"
    
TRACK 04 AUDIO
    TITLE "track 04 title"
    INDEX 01 04:00:00

    REM ARTIST "rem artist in Track04"
    REM PERFORMER "rem Track04 performer"
    REM TRACKARTIST "track artist in Track04"

TRACK 05 AUDIO
    TITLE "track 05 title"
    INDEX 01 05:00:00

    REM CATALOG "1234567890125"
    REM ISRC "ABCDE1234565"
    REM MUSICBRAINZ_ALBUM_ID "73b0edca-47ad-46ec-9215-cc518d3ee995"
    REM MUSICBRAINZ_ALBUMARTIST_ID "83903121-f611-4875-984c-673ae7173e55"
    REM MUSICBRAINZ_ALBUM_TYPE "Album"
    REM MUSICBRAINZ_ALBUM_STATUS "Official"
    REM REPLAYGAIN_ALBUM_GAIN -5dB
    REM REPLAYGAIN_ALBUM_PEAK 85

    COMPILATION 0

TRACK 06 AUDIO
    TITLE "track 06 title"
    INDEX 01 06:00:00

    REM CATALOG "1234567890126"
    REM ISRC "ABCDE1234566"
    REM MUSICBRAINZ_ALBUM_ID "73b0edca-47ad-46ec-9215-cc518d3ee996"
    REM MUSICBRAINZ_ALBUMARTIST_ID "83903121-f611-4875-984c-673ae7173e56"
    REM MUSICBRAINZ_ALBUM_TYPE "Compilation"
    REM MUSICBRAINZ_ALBUM_STATUS "Bootleg"
    REM REPLAYGAIN_ALBUM_GAIN -6dB
    REM REPLAYGAIN_ALBUM_PEAK 86

    COMPILATION 1
    
    REM ALBUMARTISTSORT "album artist sort track 6"
    REM ALBUMSORT "album sort track 6"

TRACK 07 AUDIO
    TITLE "track 07 title"
    INDEX 01 07:00:00

    REM CATALOG "1234567890127"
    REM ISRC "ABCDE1234567"
    REM MUSICBRAINZ_ALBUM_ID "73b0edca-47ad-46ec-9215-cc518d3ee997"
    REM MUSICBRAINZ_ALBUMARTIST_ID "83903121-f611-4875-984c-673ae7173e57"
    REM MUSICBRAINZ_ALBUM_TYPE "Album"
    REM MUSICBRAINZ_ALBUM_STATUS "Official"
    REM REPLAYGAIN_ALBUM_GAIN -7dB
    REM REPLAYGAIN_ALBUM_PEAK 87

    COMPILATION 0

    REM ALBUMARTISTSORT "album artist sort track 7"
    REM ALBUMSORT "album sort track 7"