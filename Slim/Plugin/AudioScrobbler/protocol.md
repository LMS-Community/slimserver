# Last.fm Submissions Protocol v1.2.1
DEPRECATED

https://www.last.fm/api/submissions


This protocol is now deprecated! Please use the Scrobbling API

TIP

Note: There is now a new way for sending scrobbles called the Scrobbling API which is integrated into the rest of the Last.fm Web Services as opposed to being a separate service like 1.2.1. New clients should all use the Scrobbling API and not this protocol as we will not be issuing new client ids for this protocol and are likely to disable the "tst" client id at some point.

The Last.fm Submissions Protocol is designed for the submission of now-playing and recent historical track data to Last.fm user profiles (aka 'Scrobbling').

Protocol 1.2.1 is backward compatible with 1.2. The only change is an additional, optional, handshake mechanism to allow third-parties to use Last.fm web services authentication to create new scrobbling sessions. Please note that although this is optional, Last.fm web services authentication is the planned authentication mechanism for the next version of the Scrobble API so this should be used if possible.

Please direct any corrections or clarifications to us here.

## Introduction and Scope
The Submissions Protocol is designed for the submission of now-playing and recent historical track data to Last.fm user profiles (aka "Scrobbling"). Submission of bulk historical data is not catered for by this protocol.

The protocol is designed to be as simple and lightweight as possible. It is a REST-style interface based on HTTP, so a working knowledge of HTTP 1.1 is assumed.

## Protocol Stages
The protocol consists of three stages which must be performed in the following order:

* Handshake: The initial negotiation with the submissions server to establish authentication and connection details for the session.
* Now-Playing: Optional lightweight notification of now-playing data at the start of the track for realtime information purposes.
* Submission: Submission of full track data at the end of the track for statistical purposes.

Typically a client should perform the handshake once at the start of a listening session and then use the values returned to perform as many now-playing and submission requests as required (i.e. the handshake does not need to be performed for every track submitted, just once).

## 1. The Handshake
TIP

A handshake must occur each time a client is started, and additionally if failures are encountered later on in the submission process.

The handshake consists of a HTTP/1.1 GET request to this URL: http://post.audioscrobbler.com:80/

Note that the request must be HTTP/1.1

specifically the Host: header should be present.

Version 1.2.1 of the protocol introduces a new handshake mechanism to allow for Web Services authentication to be used for handshakes. Whenever possible you should use this mechanism for performing handshakes, otherwise you may use "standard authentication". Both forms of authentication require a base set of parameters, they differ in that web service authentication requires an extra two parameters and the authentication token is generated using a different algorithm. This is all explained below.

The request string that is common to both handshake mechanisms is as follows, note that all parameters must be present:

```
http://post.audioscrobbler.com/?hs=true&p=1.2.1&c=<client-id>&v=<client-ver>&u=<user>&t=<timestamp>&a=<auth>
```

The common parameters and their values are explained below (strings between angle brackets should be replaced by "real" values):

hs=true Indicates that a handshake is requested. Requests without this parameter set to true will return a human-readable informational message and no handshake will be performed.

* `p=1.2.1 `Is the version of the submissions protocol to which the client conforms.
* `c=<client-id>` Is an identifier for the client (See section 1.1).
* `v=<client-ver>` Is the version of the client being used.
* `u=<user>` Is the name of the user on who's behalf the request is being performed.
* `t=<timestamp>` Is a UNIX Timestamp representing the current time at which the request is being performed.
* `a=<authentication-token>` Is the authentication token (See section 1.2 and section 1.3).
* `api_key=<api_key>` The API key from your Web Services account. Required for Web Services authentication only.
* `sk=<session_key>` The Web Services session key generated via the authentication protocol. Required for Web Services authentication only.

### 1.1 Client Identifiers
Client identifiers are used to provide a centrally managed database of the client versions, allowing clients to be banned if they are found to be behaving undesirably. The client identifier is associated with a version number on the server, however these are only incremented if a client is banned and do not have to reflect the version of the actual client application.

During development, clients which have not been allocated an identifier should use the identifier tst, with a version number of 1.0. Do not distribute code or client implementations which use this test identifier. Do not use the identifiers used by other clients. To obtain a new client identifier please contact us and provide us with the name of your client and its homepage address.

### 1.2 Authentication Token for Standard Authentication
TIP

Please note that this form of authentication will be removed in the next version of the protocol so if possible please use Web Services authentication detailed in section 1.3 below.

The algorithm for generating this token is as follows:

```
token = md5(md5(password) + timestamp)
```

Where md5(password) is an MD5 checksum of the user's password and timestamp is the same timestamp sent in cleartext in the handshake request via param 't'.

The md5() function takes a string and returns the 32-byte ASCII hexadecimal representation of the MD5 hash, using lower case characters for the hex values. The '+' operator represents concatenation of the two strings.

### 1.3 Authentication Token for Web Services Authentication
TIP

Use this if you want to use Last.fm Web Services authentication (see authentication) to create a new scrobbling session. Please note that this is the preferred method of authentication.

The algorithm for generating this token is as follows:

```
token = md5(shared_secret + timestamp)
```

Where shared_secret is the shared secret from your web services account and timestamp is the same timestamp sent in cleartext in the handshake request via param 't'.

The md5() function takes a string and returns the 32-byte ASCII hexadecimal representation of the MD5 hash, using lower case characters for the hex values. The '+' operator represents concatenation of the two strings.

### 1.4 Handshake Response
The body of the server response consists of a series of \n (ASCII 10) terminated lines. A typical successful server response will be something like this:

```
OK
17E61E13454CDD8B68E8D7DEEEDF6170
http://post.audioscrobbler.com:80/np_1.2
http://post2.audioscrobbler.com:80/protocol_1.2
```

If the HTTP status code is not 200 OK (indicating a successful transfer), then this constitutes a hard failure i.e. the server is not responding to the request as expected and the client should handle this. Such events may occur during network outages or when the server is heavily loaded. In addition, 'transparent' proxies may obscure the connection attempt.

The client should consider the first line of the response to determine the action it should take as follows:

* OK This indicates that the handshake was successful. Three lines will follow the OK response:

	* Session ID - the scrobble session id, to be used in all following now-playing and submission requests.
	* Now-Playing URL - the URL that should be used for a now-playing request.
	* Submission URL - the URL that should be used for a submission request.
	* These values may change per handshake and should be used for one listening "session" only and not stored across application restarts.

* BANNED This indicates that this client version has been banned from the server. This usually happens if the client is violating the protocol in a destructive way. Users should be asked to upgrade their client application.

* BADAUTH This indicates that the authentication details provided were incorrect. The client should not retry the handshake until the user has changed their details.

* BADTIME The timestamp provided was not close enough to the current time. The system clock must be corrected before re-handshaking.

* FAILED This indicates a temporary server failure. The reason indicates the cause of the failure. The client should proceed as directed in the failure handling section.

All other responses should be treated as a hard failure.An error may be reported to the user, but as with other messages this should be kept to a minimum.

## 2. The Now-Playing Notification
TIP

The Now-Playing notification is a lightweight mechanism for notifying Last.fm that a track has started playing. This is used for realtime display of a user's currently playing track, and does not affect a user's musical profile.

The Now-Playing notification is optional, but recommended and should be sent once when a user starts listening to a song.

The request takes the form of a group of form encoded key-value pairs which are submitted to the server as the body of a HTTP POST request, using the now-playing URL returned by the handshake request. The key-value pairs are:

* `s=<sessionID>` The Session ID string returned by the handshake request. Required.
* `a=<artistname>` The artist name. Required.
* `t=<track>` The track name. Required.
* `b=<album>` The album title, or an empty string if not known.
* `l=<secs>` The length of the track in seconds, or an empty string if not known.
* `n=<tracknumber>` The position of the track on the album, or an empty string if not known.
* `m=<mb-trackid>` The MusicBrainz Track ID, or an empty string if not known.

The body of the server response will consist of a single \n (ASCII 10) terminated line. The client should process the first line of the body to determine the action it should take

OK This indicates that the Now-Playing notification was successful.
BADSESSION This indicates that the Session ID sent was somehow invalid, possibly because another client has performed a handshake for this user. On receiving this, the client should re-handshake with the server before continuing.

## 3. The Submission
### 3.1 When to Submit
The client should monitor the user's interaction with the music playing service to whatever extent the service allows. In order to qualify for submission all of the following criteria must be met:

* The track must be submitted once it has finished playing. Whether it has finished playing naturally or has been manually stopped by the user is irrelevant.
* The track must have been played for a duration of at least 240 seconds or half the track's total length, whichever comes first. Skipping or pausing the track is irrelevant as long as the appropriate amount has been played.
* The total playback time for the track must be more than 30 seconds. Do not submit tracks shorter than this.
* Unless the client has been specially configured, it should not attempt to interpret filename information to obtain metadata instead of using tags (ID3, etc).

### 3.2 Submission Stage
The submission takes place as a HTTP/1.1 POST request to the server, using the URL returned by the handshake phase of the protocol. The submission request body may contain the details for up to 50 tracks which are being submitted. Under normal circumstances only a single track should be submitted per request, however, clients should cache submissions in case of failure.

The request takes the form of a group of form encoded key-value pairs which are submitted to the server as the body of the HTTP POST request, using the URL returned by the handshake request. All specified parameters must be present; they should be left empty if not known. The example below assumes one track is being submitted as the fields which allow multiple values are indexed with zero ([0]). The key-value pairs are:

* `s=<sessionID>` The Session ID string returned by the handshake request. Required.
* `a[0]=<artist>` The artist name. Required.
* `t[0]=<track>` The track title. Required.
* `i[0]=<time>` The time the track started playing, in UNIX timestamp format (integer number of seconds since 00:00:00, January 1st 1970 UTC). This must be in the UTC time zone, and is required.
* `o[0]=<source>` The source of the track. Required, must be one of the following codes:
	* `P` Chosen by the user (the most common value, unless you have a reason for choosing otherwise, use this).
	* `R` Non-personalised broadcast (e.g. Shoutcast, BBC Radio 1).
	* `E` Personalised recommendation except Last.fm (e.g. Pandora, Launchcast).
	* `L` Last.fm (any mode). In this case, the 5-digit Last.fm recommendation key must be appended to this source ID to prove the validity of the submission (for example, "o[0]=L1b48a").
* `r[0]=<rating>` A single character denoting the rating of the track. Empty if not applicable.
	* `L` Love (on any mode if the user has manually loved the track). This implies a listen.
	* `B` Ban (only if source=L). This implies a skip, and the client should skip to the next track when a ban happens.
	* `S` Skip (only if source=L)

TIP

Note: Currently a Last.fm web service must also be called to set love (track.love) or ban (track.ban) status. We anticipate that the next version of the scrobble protocol will no longer perform love and ban and this will instead be handled by the web services only.

* `l[0]=<secs>` The length of the track in seconds. Required when the source is P, optional otherwise.
* `b[0]=<album>` The album title, or an empty string if not known.
* `n[0]=<tracknumber>` The position of the track on the album, or an empty string if not known.
* `m[0]=<mb-trackid>` The MusicBrainz Track ID, or an empty string if not known.

Key-value pairs are separated by an '&' character, in the usual manner for form submissions in HTTP. The values must be converted to UTF-8 first, and must be URL encoded. Multiple submissions may be specified by repeating the a[], t[], i[], o[], r[], l[], b[], n[], and m[] key-value pairs with increasing indices. (e.g. a[1], a[2] etc.) Note that when performing multiple submissions, the tracks must be submitted in chronological order according to when they were listened to (i.e. the track identified by t[0].. must have been played before the track identified by t[1].. and so on).

### 3.3 Submission Response
The body of the server response will consist of a single \n (ASCII 10) terminated line. The client should process the first line of the body to determine the action it should take:

* OK This indicates that the submission request was accepted for processing. It does not mean that the submission was valid, but only that the authentication and the form of the submission was validated. The client should remove the submitted track(s) from its queue.
* BADSESSION This indicates that the Session ID sent was somehow invalid, possibly because another client has performed a handshake for this user. On receiving this, the client should re-handshake with the server before continuing. The client should not remove submitted tracks from its queue.
* FAILED This indicates that a failure has occurred somewhere. The reason indicates the cause of the failure. Clients should treat this as a hard failure, and should proceed as directed in the failure handling section. The client should not remove submitted tracks from its queue.
* All other responses should be treated as a hard failure. An error may be reported to the user, but as with other messages this should be kept to a minimum.

The server may at its discretion ignore track details submitted by the user. Typical reasons for submissions being dropped include (but are not limited to):

* Submissions with inaccurate dates, e.g. in the far future or past, or before the last submitted entry (i.e. tracks must be submitted in chronological order according to when they were listened to).
* Spam filtering, such as submissions of tracks with impossible timings (e.g. tracks played within a few seconds of one another).
* Known incorrect tags (e.g. an artist called 'artist')
* Incorrectly encoded UTF-8 sequences.

In these cases, the client will receive an OK response, however the tracks will not be registered.

### 3.4 Failure Handling
A hard failure at any stage should be counted by the client. If three hard failure events occur consecutively, the client should fall back to the handshake phase.

If a hard failure occurs at the handshake phase, the client should initially pause for 1 minute before handshaking again. Subsequent failed handshakes should double this delay up to a maximum delay of 120 minutes.

Upon a successful handshake, the client should reset the hard failure counter.

### 3.5 Caching
It is recommended that the client hold submissions in a local queue if the submission process fails, since the server connectivity may be variable (either because of network outage, or server failure). This cache should be retained over client restarts, allowing the user to close the client and restart later without losing their scrobbled tracks. The cached tracks must be submitted in chronological order according to the time when they were listened to and before any new tracks are submitted.

### 3.6 Proxy Servers
It is recommended that the client use whatever system-configured proxy is in force for the HTTP scheme. The server requests will need to be modified to be proxy requests, rather than direct server requests. This usually involves using the full URL in the GET or POST request, rather than the components after the '/'.

## 4. Application Guidelines
There are a few things that the client should do to improve the user experience and to reduce the impact on the submissions servers.

* It is important to remember that the behaviour of the client should, above everything else, be non-intrusive to the end user in use.
* The client should not display pop-up error messages unless absolutely necessary. Notifications should be reported once when first identified and should not be re-displayed unless the cause is resolved in the meantime.
* Clients should be able to cope with long (multiples hours) downtime from the server. This may be caused by either server failure or a lack of network connectivity by the client (e.g. a portable system such as a laptop with only brief connectivity).