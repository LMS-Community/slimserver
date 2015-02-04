REM "ALBUM2: use this file to test line parsing with alternate possible values 
REM "i.e. with or without quotes, or format i.e. booleans".
REM "note that here are defined only the alterate values in respect of ALBUM1"
REM "when more than two values are admitted, the further are teste only by track"
REM "starting from track 2"
REM "USE ALBUM3 for test attributes from different sources (REM vs COMMAND)" 

REM "NOTE THIS CUESHEET IS INVALID, WILL BE SKIPPED BY SCANNER AFTER LINE PARSING".


CATALOG 3210987654321
CATALOG "1234567890123"

ISRC XYZKW0000001
ISRC "ABCDE1234567"
PERFORMER albumPerformer
PERFORMER "album performer"
SONGWRITER albumSongwriter
SONGWRITER "album songwriter" 
TITLE AlbumTitle
TITLE "Album title"

REM REPLAYGAIN_ALBUM_GAIN "-1dB"
REM REPLAYGAIN_ALBUM_GAIN -1dB

REM CATALOG 3210987654320
REM CATALOG "1234567890120"
REM ISRC XYZKW1000000
REM ISRC "ABCDE1234560"
REM GENRE genreInAlbum
REM GENRE "genre in album"
REM YEAR "1981"
REM YEAR 1981
REM ARTIST remArtistInAlbum
REM ARTIST "rem artist in album"
REM COMPOSER remAlbumComposer
REM COMPOSER "rem album composer"
REM CONDUCTOR remAlbumConductor
REM CONDUCTOR "rem album conductor"
REM BAND remAlbumBand
REM BAND "rem album band"
REM ALBUMARTIST remAlbumArtist
REM ALBUMARTIST "rem album artist"
REM TRACKARTIST remTrackArtistInAlbum
REM TRACKARTIST "rem track artist in album"
REM ALBUMARTISTSORT remAlbumArtistSort
REM ALBUMARTISTSORT "rem album artist sort"
REM ARTISTSORT remArtistSortInAlbum
REM ARTISTSORT "rem artist sort in album"
REM ALBUMSORT remAlbumSort
REM ALBUMSORT "rem album sort"
REM DISC "1"
REM DISC 1
REM DISCC "2"
REM DISCC 2
REM REPLAYGAIN_ALBUM_PEAK "80"
REM REPLAYGAIN_ALBUM_PEAK 80
REM REPLAYGAIN_TRACK_PEAK "80"
REM REPLAYGAIN_TRACK_PEAK 80

REM DATE "1982"
REM DATE 1982
REM TITLE RemAlbumTitle
REM TITLE "rem album title"
REM PERFORMER remAlbumPerformer
REM PERFORMER "rem album performer"
REM SONGWRITER remAlbumSongwriter
REM SONGWRITER "rem album songwriter" 
REM DISCNUMBER "1"
REM DISCNUMBER 1
REM DISCTOTAL "2"
REM DISCTOTAL 2
REM TOTALDISCS "2"
REM TOTALDISCS 2

REM "see tracks for all permutations"
REM REPLAYGAIN_TRACK_GAIN "+2dB"
REM REPLAYGAIN_TRACK_GAIN +2dB
REM REPLAYGAIN_TRACK_GAIN 2dB
REM REPLAYGAIN_TRACK_GAIN "2dB"

REM "see tracks for all permutations"
REM COMPILATION "1"
REM COMPILATION 1
REM COMPILATION "Y"
REM COMPILATION Y
REM COMPILATION YES
REM COMPILATION "YES"

REM "note that this cue file will be skipped in scan due multiple FILE command";

FILE an inValid filename.wav WAVE
FILE "aValidFilename.wav" WAVE
FILE "another Valid Filename.wav" WAVE
FILE stillValidFilename.wav WAVE

REM "End of Album section"
FILE "album.wav" WAVE
  TRACK 01 AUDIO
    INDEX 01 01:00:00

    REM "Below second option for any command"

    CATALOG 3210987654324
    ISRC XYZKW0000002
    PERFORMER track02Performer
    SONGWRITER track02Songwriter
    TITLE track02title
    FILE "another Valid Filename.wav" WAVE
    REM REPLAYGAIN_TRACK_GAIN "+2dB"

    REM COMPILATION "1"

    REM REPLAYGAIN_ALBUM_GAIN "-1dB"

    REM GENRE genreInTrack02
    REM YEAR "1983"
    REM ARTIST remArtistInTrack02
    REM COMPOSER remTrack02Composer
    REM CONDUCTOR remTrack02Conductor
    REM BAND remTrack02Band
    REM TRACKARTIST remTrackArtistInTrack02
    REM ARTISTSORT remArtistSortInTrack02
    REM DISC "1"
    REM REPLAYGAIN_TRACK_PEAK "80"

    REM CATALOG 3210987654320
    REM ISRC XYZKW1000000
    REM ALBUMARTIST remAlbumArtistInTrack02
    REM ALBUMARTISTSORT remAlbumArtistSortInTrack02
    REM ALBUMSORT remAlbumSortInTrack02
    REM DISCC "2"
    REM REPLAYGAIN_ALBUM_PEAK "80"

    REM DATE "1985"
    REM TITLE RemTrack02Title
    REM PERFORMER remTrack02Performer
    REM SONGWRITER remTrack02Songwriter
    REM DISCNUMBER "1"

    REM "other valid - per album - REM commands recognized by LMS but converted to others"

    REM DISCTOTAL "2"
    REM TOTALDISCS "2"

  TRACK 02 AUDIO
    INDEX 01 02:00:00

    REM "Below 3th option for commands"

    FILE stillValidFilename.wav WAVE
    REM REPLAYGAIN_TRACK_GAIN 2dB
    REM COMPILATION "Y"

  TRACK 03 AUDIO
    INDEX 01 03:00:00

    REM "Below 4th option for commands"

    FILE an inValid filename.wav WAVE
    REM REPLAYGAIN_TRACK_GAIN "2dB"
    REM COMPILATION Y
  TRACK 04 AUDIO
    INDEX 01 04:00:00

    REM "Below 5th option for commands"

    REM COMPILATION YES
  TRACK 05 AUDIO
    INDEX 01 05:00:00
    
    REM "Below 5th option for commands"
	
    REM COMPILATION "YES"
  