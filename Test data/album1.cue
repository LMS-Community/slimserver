REM "ALBUM1: use this initial test line parsing".
REM "CECK if correctly ignore/accept specific commands, but please note that"
REM "only the firs value encountered per attribute (command or REM) and per track 
REM "if defined is stored, others are discarded."
REM "Use ALBUM2 and others for further tests".

REM "NOTE THIS CUESHEET IS INVALID, WILL BE SKIPPED BY SCANNER AFTER LINE PARSING".

REM COMMENT "this is the only line of comment should be stored for album"

REM COMMENT "this line must be ignored"
REM "rem with no command are ignored"
REM

REM "here the list of STANDARD CUE COMMAND"

REM "valid per album, to be accepted, note that only the first is stored:"

CATALOG "1234567890123"
CATALOG 3210987654321
ISRC "ABCDE1234567"
ISRC XYZKW0000001
PERFORMER "album performer"
PERFORMER albumPerformer
SONGWRITER "album songwriter" 
SONGWRITER albumSongwriter
TITLE "Album title"
TITLE AlbumTitle

REM "note that this cue file will be skipped in scan due multiple FILE command";

FILE "aValidFilename.wav" WAVE
FILE "another Valid Filename.wav" WAVE
FILE stillValidFilename.wav WAVE
FILE an inValid filename.wav WAVE

REM "valid but NOT per album, to be refused:"

INDEX 00
INDEX 01

REM "valid but refused:"

CDTEXTFILE "cdtextfile.txt"
CDTEXTFILE cdtextfile.txt
FLAGS "DCP" 
FLAGS DCP
POSTGAP 100
POSTGAP "100"
PREGAP 20
PREGAP "20"

REM "invalid, must be refused:"

LYRICS "blah blah blah"
COMPOSER "Album composer in wrong command"
CONDUCTOR "Album conductor in wrong command"
BAND "Album band in wrong command"
ARTIST "Album artist in wrong command"
ALBUMARTIST "Album artist in wrong command"
REM "..."

REM "refused REM commands:"

REM URI "refused REM commands URI"
REM FILENAME "refused REM commands FILENAME"
REM CONTENT_TYPE "refused REM commands CONTENT_TYPE"
REM AUDIO "refused REM commands AUDIO"
REM AUDIO 1
REM AUDIO 0
REM LOSSLESS "refused REM commands LOSSLESS"
REM LOSSLESS 1
REM LOSSLESS 0
REM VIRTUAL "refused REM commands VIRTUAL"
REM VIRTUAL 1
REM VIRTUAL 0
REM START "refused REM commands START"
REM START 00:00:00
REM START "00:00:00"
REM START 0
REM START "0"
REM FILE "refused REM commands FILE"
REM TRACK "refused REM commands TRACK"
REM INDEX "refused REM commands INDEX"
REM SECS "refused REM commands SECS"
REM OFFSET "refused REM commands OFFSET"
REM TIMESTAMP "refused REM commands TIMESTAMP"
REM SIZE "refused REM commands SIZE"
REM FILESIZE "refused REM commands FILESIZE"
REM DRM "refused REM commands DRM"
REM ALBUM "rem album title as album"

REM CDTEXTFILE "cdtextfile.txt"
REM CDTEXTFILE cdtextfile.txt
REM FLAGS "DCP" 
REM FLAGS DCP
REM POSTGAP 100
REM POSTGAP "100"
REM PREGAP 20
REM PREGAP "20"

REM "valid REM commands with special and correct syntax:"

REM REPLAYGAIN_ALBUM_GAIN -1dB
REM REPLAYGAIN_ALBUM_GAIN "-1dB"

REM REPLAYGAIN_TRACK_GAIN +2dB
REM REPLAYGAIN_TRACK_GAIN "+2dB"
REM REPLAYGAIN_TRACK_GAIN 2dB
REM REPLAYGAIN_TRACK_GAIN "2dB"
REM COMPILATION 1
REM COMPILATION "1"
REM COMPILATION "Y"
REM COMPILATION Y
REM COMPILATION YES
REM COMPILATION "YES"

REM "other valid REM commands recognized by LMS"

REM CATALOG "1234567890120"
REM CATALOG 3210987654320
REM ISRC "ABCDE1234560"
REM ISRC XYZKW1000000
REM GENRE "genre in album"
REM GENRE genreInAlbum
REM YEAR 1981
REM YEAR "1981"
REM ARTIST "rem artist in album"
REM ARTIST remArtistInAlbum
REM COMPOSER "rem album composer"
REM COMPOSER remAlbumComposer
REM CONDUCTOR "rem album conductor"
REM CONDUCTOR remAlbumConductor
REM BAND "rem album band"
REM BAND remAlbumBand
REM ALBUMARTIST "rem album artist"
REM ALBUMARTIST remAlbumArtist
REM TRACKARTIST "rem track artist in album"
REM TRACKARTIST remTrackArtistInAlbum
REM ALBUMARTISTSORT "rem album artist sort"
REM ALBUMARTISTSORT remAlbumArtistSort
REM ARTISTSORT "rem artist sort in album"
REM ARTISTSORT remArtistSortInAlbum
REM ALBUMSORT "rem album sort"
REM ALBUMSORT remAlbumSort
REM DISC 1
REM DISC "1"
REM DISCC 2
REM DISCC "2"
REM MUSICBRAINZ_ALBUM_ID "73b0edca-47ad-46ec-9215-cc518d3ee991"
REM MUSICBRAINZ_ALBUMARTIST_ID "83903121-f611-4875-984c-673ae7173e56"
REM MUSICBRAINZ_ALBUM_TYPE "Album"
REM MUSICBRAINZ_ALBUM_STATUS "Official"
REM MUSICBRAINZ_ID "73b0edca-47ad-46ec-9215-cc518d3ee991"
REM MUSICBRAINZ_ARTIST_ID "83903121-f611-4875-984c-673ae7173e56"
REM REPLAYGAIN_ALBUM_PEAK 80
REM REPLAYGAIN_ALBUM_PEAK "80"
REM REPLAYGAIN_TRACK_PEAK 80
REM REPLAYGAIN_TRACK_PEAK "80"

REM "other valid REM commands recognized by LMS but converted to others"

REM DATE 1982
REM DATE "1982"
REM TITLE "rem album title"
REM TITLE RemAlbumTitle
REM PERFORMER "rem album performer"
REM PERFORMER remAlbumPerformer
REM SONGWRITER "rem album songwriter" 
REM SONGWRITER remAlbumSongwriter
REM DISCNUMBER 1
REM DISCNUMBER "1"
REM DISCTOTAL 2
REM DISCTOTAL "2"
REM TOTALDISCS 2
REM TOTALDISCS "2"

REM "other valid REM commands but not recognized by LMS"

REM INSTRUMENT:VIOLIN "Anne Sophie Mutter"
REM VOCAL:TENOR "Luciano Pavarotti" 
REM ...

REM "End of Album section"
FILE "album.wav" WAVE
  TRACK 01 AUDIO
  
    REM "Below same commands as per Album, some difference is expecteded"
    REM COMMENT "this is the only line of comment should be stored for track 01"
    REM COMMENT "this line must be ignored"
    REM "rem with no command are ignored"
    REM  

    REM "here the list of STANDARD CUE COMMAND"

    REM "valid per album, to be accepted and deleted per track, note that only the first is stored:"

    CATALOG "1234567890124"
    CATALOG 3210987654324
    ISRC "ABCDE1234560"
    ISRC XYZKW0000002
    PERFORMER "track 01 performer"
    PERFORMER track01Performer
    SONGWRITER "track 01 songwriter" 
    SONGWRITER track01Songwriter
    TITLE "track 01 title"
    TITLE track01Title
    REM "TRACK 01 AUDIO, is valid see above"

    REM "note that this cue file will be skipped in scan due multiple FILE command";

    FILE "aValidFilename.wav" WAVE
    FILE "another Valid Filename.wav" WAVE
    FILE stillValidFilename.wav WAVE
    FILE an inValid filename.wav WAVE

    REM "valid per track:"

    INDEX 00 00:30:00
    INDEX 01 01:00:00

    REM "valid but refused:"

    CDTEXTFILE "cdtextfile.txt"
    CDTEXTFILE cdtextfile.txt
    FLAGS "DCP" 
    FLAGS DCP
    POSTGAP 100
    POSTGAP "100"
    PREGAP 20
    PREGAP "20"

    REM "invalid, must be refused:"

    LYRICS "blah blah blah"
    COMPOSER "track01 composer in wrong command"
    CONDUCTOR "track01 conductor in wrong command"
    BAND "track01 band in wrong command"
    ARTIST "track01 artist in wrong command"
    ALBUMARTIST "track01 artist in wrong command"
    REM "..."

    REM "refused REM commands:"

    REM URI "refused REM commands URI"
    REM FILENAME "refused REM commands FILENAME"
    REM CONTENT_TYPE "refused REM commands CONTENT_TYPE"
    REM AUDIO "refused REM commands AUDIO"
    REM AUDIO 1
    REM AUDIO 0
    REM LOSSLESS "refused REM commands LOSSLESS"
    REM LOSSLESS 1
    REM LOSSLESS 0
    REM VIRTUAL "refused REM commands VIRTUAL"
    REM VIRTUAL 1
    REM VIRTUAL 0
    REM START "refused REM commands START"
    REM START 00:01:00
    REM START "00:02:00"
    REM START 0
    REM START "0"
    REM FILE "refused REM commands FILE"
    REM TRACK "refused REM commands TRACK"
    REM INDEX "refused REM commands INDEX"
    REM SECS "refused REM commands SECS"
    REM OFFSET "refused REM commands OFFSET"
    REM TIMESTAMP "refused REM commands TIMESTAMP"
    REM SIZE "refused REM commands SIZE"
    REM FILESIZE "refused REM commands FILESIZE"
    REM DRM "refused REM commands DRM"
    ALBUM "rem album title as album in track1"

    REM CDTEXTFILE "cdtextfile.txt"
    REM CDTEXTFILE cdtextfile.txt
    REM FLAGS "DCP" 
    REM FLAGS DCP
    REM POSTGAP 100
    REM POSTGAP "100"
    REM PREGAP 20
    REM PREGAP "20"

    REM "valid REM commands with special and correct syntax:"

    REM REPLAYGAIN_TRACK_GAIN +2dB
    REM REPLAYGAIN_TRACK_GAIN "+2dB"
    REM REPLAYGAIN_TRACK_GAIN 2dB
    REM REPLAYGAIN_TRACK_GAIN "2dB"

    REM "valid REM commands with special and correct syntax, but not per Track:"
  
    REM COMPILATION 1
    REM COMPILATION "1"
    REM COMPILATION "Y"
    REM COMPILATION Y
    REM COMPILATION YES
    REM COMPILATION "YES"
    REM REPLAYGAIN_ALBUM_GAIN -1dB
    REM REPLAYGAIN_ALBUM_GAIN "-1dB"

    REM "other valid REM commands recognized by LMS"

    REM GENRE "genre in track01"
    REM GENRE genreInTrack01
    REM YEAR 1983
    REM YEAR "1983"
    REM ARTIST "rem artist in Track01"
    REM ARTIST remArtistInTrack01
    REM COMPOSER "rem Track01 composer"
    REM COMPOSER remTrack01Composer
    REM CONDUCTOR "rem Track01 conductor"
    REM CONDUCTOR remTrack01Conductor
    REM BAND "rem Track01 band"
    REM BAND Track01Band
    REM TRACKARTIST "track artist in Track01"
    REM TRACKARTIST trackArtistInTrack01
    REM ARTISTSORT "rem artist sort in Track01"
    REM ARTISTSORT remAlbumArtistSortInTrack01
    REM DISC 1
    REM DISC "1"
    REM MUSICBRAINZ_ID "73b0edca-47ad-46ec-9215-cc518d3ee991"
    REM MUSICBRAINZ_ARTIST_ID "83903121-f611-4875-984c-673ae7173e56"
    REM REPLAYGAIN_TRACK_PEAK 80
    REM REPLAYGAIN_TRACK_PEAK "80"

    REM "other valid REM commands recognized by LMS but not per track"

    REM CATALOG "1234567890120"
    REM CATALOG 3210987654320
    REM ISRC "ABCDE1234560"
    REM ISRC XYZKW1000000
    REM ALBUMARTIST "rem album artist in Track01"
    REM ALBUMARTIST remAlbumArtistInTrack01
    REM ALBUMARTISTSORT "rem album artist sort in Track01"
    REM ALBUMARTISTSORT remAlbumArtistSortInTrack01
    REM ALBUMSORT "rem album sort In Track01"
    REM ALBUMSORT remAlbumSortInTrack01
    REM DISCC 2
    REM DISCC "2"
    REM MUSICBRAINZ_ALBUM_ID "73b0edca-47ad-46ec-9215-cc518d3ee991"
    REM MUSICBRAINZ_ALBUMARTIST_ID "83903121-f611-4875-984c-673ae7173e56"
    REM MUSICBRAINZ_ALBUM_TYPE "Album"
    REM MUSICBRAINZ_ALBUM_STATUS "Official"
    REM REPLAYGAIN_ALBUM_PEAK 80
    REM REPLAYGAIN_ALBUM_PEAK "80"

    REM "other valid REM commands recognized by LMS but converted to others"

    REM DATE 1985
    REM DATE "1985"
    REM TITLE "rem Track01 title"
    REM TITLE RemTrack01Title
    REM PERFORMER "rem Track01 performer"
    REM PERFORMER remTrack01Performer
    REM SONGWRITER "rem Track01 songwriter" 
    REM SONGWRITER remTrack01Songwriter
    REM DISCNUMBER 1
    REM DISCNUMBER "1"

    REM "other valid - per album - REM commands recognized by LMS but converted to others"
  
    REM DISCTOTAL 2
    REM DISCTOTAL "2"
    REM TOTALDISCS 2
    REM TOTALDISCS "2"

    REM "other valid REM commands but not recognized by LMS"

    REM INSTRUMENT:VIOLIN "Anne Sophie Mutter"
    REM VOCAL:TENOR "Luciano Pavarotti" 
    REM ...
  