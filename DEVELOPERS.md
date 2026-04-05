# Developer Notes

## How Image/Icon/Cover is Passed from the OPML Item to a Track

When a `$url` from an OPML item is added to the current playlist, a `$track` object is created and its image is obtained by calling `handlerForURL($url)->getMetadataFor($url)`. If this protocol handler is HTTP, it needs to find the image just by using this `$url`, there is no other information.

XMLBrowser(s), when adding the URL to the playlist, call `setRemoteMetadata` which caches the OPML item's image link as `remote_image_$url`. It does that automatically for HTTP(S) and otherwise calls the `$url`'s protocol handler method `shouldCacheImage`. This method can either return `true` and then the `remote_image_$url` will be cached or it can also do its own caching (or not) and return `false`. When `remote_image_$url` is cached, it is used in `getMetadataFor()` as one of the image sources.

When playing the `$track`, if `scanUrl()` points to [`Slim::Utils::Scanner::Remote::scanURL()`](Slim/Utils/Scanner/Remote.pm) and if there are redirections, a `$newTrack` is created whose `$newUrl` is the redirected one which will then be used in further `getMetadataFor` calls. As this `$newUrl` has no image's link entry in the cache, the `remote_entry_$url` is copied upon each redirection to `remote_image_$newUrl` during the scan. Ultimately, when the actual image is cached (not the link), there will be an artwork cache entry that `getMetadataFor()` will use.

Note that some formats may have other cover art inside streamed with the track and, for example, MP3 does grab that image and cache it using `cover_$url`. It is the **actual** image there, not a link to it. Look at `Slim::Format::XXX` for further details.

## How `scanUrl` Works

For HTTP(S) protocol handler, the `scanUrl` calls [`Slim::Utils::Scanner::Remote::scanURL`](Slim/Utils/Scanner/Remote.pm) when a track starts to play to acquire all necessary information. The `scanUrl` is called with the `$url` to scan and an `$args` containing the `$song` object and a `$callback`.

That `$song` contains a `$track` object that is created from the original `$url` set when OPML item is added in the playlist. When scanning `$url`, the [`Slim::Utils::Scanner::Remote::scanURL`](Slim/Utils/Scanner/Remote.pm) creates a new `$track` object every time the uri returned by the `GET` is different from the `$url` argument. This happens on HTTP redirection and if the `$url` argument differs from `$args->{'song'}->track->url`. The original URL is stored as `$track->redir` (note that it might be empty).

When it returns, `scanUrl` provides a new `$track` that replaces the current one in the `$song` object **and** in the playlist. This means that the playlist may have new `$track->url` for the same item index. When playing again that track from the playlist, LMS would normally scan again that redirected `$track->url` which might be gone (see below).

Note that `scanURL` also replaces the `$song->streamUrl` by the `$newTrack->url` if `streamUrl` still equals to the `$url` parameter when song is being opened/created. This allows protocol handler to change it as they want, but still update it when built-in scan has control. See [Thin Protocol Handler (e.g. podcast)](#thin-protocol-handler-eg-podcast) for more explanations.

## Issue of "Volatile" Redirection

Some URLs are being redirected to temporary locations, which means that the final location is only valid for as low as a few minutes. This causes a problem when user pauses such a track.

When pause happens, LMS quite often memorizes the current position and closes the connection (it's not always the case, depending of course if track is seekable, on the fullness of player's buffer and a few other parameters). The issue is that upon resume, the redirected location might be gone and a `403` will happen.

When resuming, LMS sometimes creates a `new()` song, sometimes it just re-opens it with a song `open()`. In both cases, the `$url` inside the track is the one that `scanUrl` has put after redirection. To solve that, if [`Slim::Player::Song::open()`](Slim/Player/Song.pm) fails and the track has been redirected, `open()` will set `streamUrl` to `$track->redir` (the original URL) and then will recurse with direct streaming disabled. It's not possible to allow direct streaming as if an HTTP -> HTTPS upgrade is requested during direct streaming redirection, playback will fall.

When using `new()` on resume, LMS does a `getNextSong` which is the method calling `scanUrl`. If it fails, `getNextSong` will recurse with `$track->redir`.

This is more tricky when direct stream is used because the error happens much later, when the player returns the result of the HTTP request and it is thus not possible to recurse in `open()`. In this case, as when redirection happens in direct streaming, we'll set the `streamUrl` to original URL and give it another try. It's not foolproof, but it solves most cases. Typically, as said above, the upgraded HTTP -> HTTPS redirection cannot be handled.

Note that the original URL is only set when [`Slim::Utils::Scanner::Remote::scanURL`](Slim/Utils/Scanner/Remote.pm) is called, so this behavior does not impact plugins that do not call their [`Slim::Player::HTTP::scanUrl`](Slim/Player/HTTP.pm) ancestor.

## Thin Protocol Handler [PH] (e.g. Podcast)

A thin protocol handler simply (and mostly) encapsulates HTTPS(s) URLs into a small wrapper like `<myph>://http://<$url>`. Typically, the `scanUrl` unwraps the `$url` to the HTTP(S) one and then relies on normal HTTP(S) handling, but there are a few catches as we want to benefit from all HTTP(S) methods but still overload some, making sure our protocol handler is still called after we have de-encapsulated URLs.

When a `$track` object has changed after `scanUrl` (due to a redirection), LMS offers to re-evaluate the `song->handler` and replace it by what the `$handler->songHandler()` returns. This is useful when an HTTP has been upgraded to HTTPS during redirection because you now want HTTPS handle to take care of this URL but in many cases it's dangerous. For example, for thin Protocol Handler, you don't want to lose the control on that song which would happen if the handler is reset to HTTP.

So, when calling the `scanUrl` ancestor, you should unwrap your `$url` parameter and then let [`Slim::Utils::Scanner::Remote::scanURL`](Slim/Utils/Scanner/Remote.pm) do its HTTP job. But the callback, which returns the parsed track, shall be intercepted to recover the redirected URL and replace it by your original URL (at least add-again your `<myph:://>` to what is returned) to make sure that the track, once replaced in the playlist, will still use your protocol handler. This is also where it's recommended to set `$song->streamUrl` to the streamable URL, often simply the `$newTrack->url`. Note that because `$song->streamUrl` is updated by the protocol handler, it will not be overwritten by `scanURL`.

Best is to look at [`Slim::Plugin::Podcast::Plugin`](Slim/Plugin/Podcast/Plugin.pm) as an example of such thin protocol handler.

> [!IMPORTANT]
> When doing proxy streaming, LMS calls the protocol handler's `new()` at each redirection. This can be problematic for HTTP(S) subclasses if the `new()` is calling the ancestor's `new()` **but** uses its `$song->streamUrl`. It will create an infinite loop as the URL is constantly reset to one that will be redirected. To avoid that, use the `$args->{redir}` in the new arguments to determine if this new is after a redirection.

## Scanning of Remote Tracks

One issue with remote tracks is that their headers might be needed for LMS to properly process their sample rate, size and a few critical parameters that are required for seeking across. Without acquiring the header, it can be impossible to seek into various formats like mp4. Sometimes, the header is at the bottom of the file, requiring to do an offset HTTP request.

The solution was to provide a small framework to allow LMS to acquire the header, get it stored and analysed, then re-used every time streaming bytes starts to be sent to players.

The core happens in [`Slim::Utils::Scanner::Remote`](Slim/Utils/Scanner/Remote.pm) where the method `parseRemoteHeader()` can be called by protocol handlers which want to acquire headers for their remote stream. It is the default for [`Slim::Player::Protocols::HTTP::scanUrl`](Slim/Player/Protocols/HTTP.pm).

It relies on helpers for each XXX format from `Slim::Format::XXX`:

- `parseStream()` is used to parse the stream on-the-fly, acquire track information and store them in track header so that it may be adjusted later when seeking. This method is aimed to be called every time a new scanning chunk is received, until a header is successfully parsed. It returns 0 upon failure, -1 if it needs more bytes, a value > 0 to jump to that offset in the stream and a hash containing parsed information when done. See [`Slim::Formats::Movie.pm`](Slim/Formats/Movie.pm) for a most complete example.

- `getInitialAudioBlock()` is used to get such header that will be sent to the player at the beginning of playback. It is called only when there is a processor, so see explanation below to handle header acquisition properly. In most of cases, it's simple and the default function will work.

The handling for every format is spread between `Slim::Formats::XXX` and [`Slim::Utils::Scanner::Remote`](Slim/Utils/Scanner/Remote.pm) and this could be refactored a bit. In a nutshell, after parsing stream's header, it is decided if the remote stream header should be discarded and replaced by a tweaked one when starting to send audio bytes to the player. Such tweaked headers can be added never, once, every time or only when seeking (this also influences the possibility for a track to be directly played or proxied).

Upon actual streaming of audio and when header needs to be tweaked, the [`Slim::Player::HTTP::request`](Slim/Player/HTTP.pm) will look for "processors" in the track. Such processors are set upon initial scanning or by a handler in `scanURL`. A track can output multiple formats, so that's why there are multiple processors possible. LMS will pick up one depending on what the scan offered and what the player can accept.

The relevant processor is then called in [`Slim::Player::HTTP::request`](Slim/Player/HTTP.pm) and can simply create a tweaked header that will then be passed to the player but it can also return a structure with a method to be called for every chunk of audio data received. This is used for adts frames extraction from MP4 file, when player wants `aac` and not `mp4`. This is also used for FLAC synchronization where some IP3K players can't resynchronize when seeking in a middle of a FLAC stream. The more simple case is WAV file that just need a header tweak but then don't need further handling of audio chunks.

Processors must set `initial_block_type` to either `ONCE`, `ONSEEK` or `ALWAYS` to set when `getInitialAudioBlock()` will be called by [`Slim::Player::HTTP::request`](Slim/Player/HTTP.pm) and also decide when/if direct streaming is possible. When there is nothing returned by `getInitialAudioBlock()`, it will be treated as a defined-but-empty initial block.

The `GET` request for the actual audio data uses a `Range` byte offset to skip the header (if any). If the `$track->audio_offset` has been set **and** the initial audio block is defined, then this is the range. Now, if there is a processor, it can override it by setting `sourceStreamOffset` but if there is no processor this cannot be changed.

So understand the implication of setting `$track->audio_offset`. When it is not set, then the `GET` range will be 0 unless a processor has set the `sourceStreamOffset`. Note that the stored initial block will only be sent to the player when there is a processor.

In other words, if you want LMS to `GET` the whole file from 0 and send it to the player but you don't want/need to set a processor, then DO NOT set `$track->audio_offset`!

When there is a processor, direct streaming is enabled only if `initial_block_type` is set to `ONSEEK` and track starts from zero (no seekdata). Streaming will always be proxied otherwise. When there is no processor, direct streaming will be attempted according to usual rules but the `$track->audio_offset` logic described above will apply and be passed to the player as range.

The logic is the same when seeking, except that the byte seek offset is added.

Look at [`Slim::Utils::Scanner::Remote`](Slim/Utils/Scanner/Remote.pm) and [`Slim::Formats::Movie`](Slim/Formats/Movie.pm) or [`Slim::Formats::FLAC`](Slim/Formats/FLAC.pm) for general understanding and at [`Plugins::TIDAL::ProtocolHandler`](https://github.com/michaelherger/lms-plugin-tidal/blob/main/ProtocolHandler.pm) to see how a plugin can use this framework to have its tracks scanned.

## Podcast Plugin Extension

Since LMS 8.2, the Podcast plugin has the possibility to search for feeds with a choice of search engines. As it is not possible to add too many engines directly in LMS, a small extension framework has been built and allows custom plugins to add their own provider and a few simple set of sub-menus.

The `Provider` class is used as the base for any podcast provider and is expecting to have the following methods:

- `new (O)` => a class/object reference to the newly created provider
- `getName` => name of the provider
- `getMenuItems (O)` => array reference of OPML items to add to main menu
- `getFeedsIterator` => closure to be called to iterate through results
- `getSearchParams` => array reference to: [`$url` for search and array reference to extra headers]
- `newsHandler (O)` => a classical OPML list builder if the provider supports "what's new"

The default search handler [`Slim::Plugin::Podcast::Plugin::searchHandler`](Slim/Plugin/Podcast/Plugin.pm) is doing an HTTP query using a customizable URL and expects a JSON payload in return that it maps to OPML feeds by repeatedly calling the iterator gotten from `getFeedsIterator` (See [PodcastIndex](Slim/Plugin/Podcast/PodcastIndex.pm) example).

The [`newsHandler`](Slim/Plugin/Podcast/PodcastIndex.pm) method, when present, signals to the plugin that the provider is capable of listing new episodes of subscribed feeds. Now, there is no boilerplate code for how to handle the search for news and it is left to the provider itself (it can be too much different between providers). The presence of [`newsHandler`](Slim/Plugin/Podcast/PodcastIndex.pm) methods only guarantees that podcast settings shows a "since" and "max" options.

The [`Slim::Plugin::Podcast::Plugin::registerProvider($classname)`](Slim/Plugin/Podcast/Plugin.pm) is used to add providers. See example here: [LMS-PodcastExt](https://github.com/philippe44/LMS-PodcastExt) for adding a new provider or extending an existing one.

## Some Comments on Tracks/Song Data Structure

### URL's in `$song`

- `streamUrl` is the URL that will actually be `GET`, optionally using direct mode. It is set to `$track->url` at creation of `$song`, updated when track is being changed after a `scanURL` (if the updated URL differs from the original one) and also set by `$player->canDirectStream` if direct is possible. Quite often, PH use it to store the URL they really want to stream. By default, HTTP uses it in `canDirectStreamSong` to pass the argument to `canDirectStream`.

### URL's in [`Slim::Schema::Track`](Slim/Schema/Track.pm) or [`Slim::Schema::RemoteTrack`](Slim/Schema/RemoteTrack.pm)

- `_url` is the URL used at the track's creation
- `url` is a method to get/set it. When set, it changes the cache
- `redir` is the `$url` argument of [`Slim::Utils::Scanner::Remote::scanURL`](Slim/Utils/Scanner/Remote.pm). It is set **only** upon redirection so it might be empty which is useful to know that redirection happened.

### Tracks in [`Slim::Player::Song`](Slim/Player/Song.pm)

When a track contains a playlist, there is only one `$song` created (`new`) but then that same song is opened multiple times. The first time the playlist is scanned and then all sub-tracks are scanned (note that visually it looks like one track that can be skipped but will stay on the same track until all sub-tracks have been skipped). On further `open()`, the next sub-track is set in `_currentTrack`.

- `_currentTrack (RW)` is the current sub-track (if any) in the playlist. It can be empty
- `_track (RW)` is the master track
- `track()` is a method that returns the master track
- `currentTrack()` is a method that returns the actual current track, i.e. `_currentTrack || _track`

### Handlers in [`Slim::Player::Song`](Slim/Player/Song.pm) and [`Slim::Player::StreamingController`](Slim/Player/StreamingController.pm)

- `$song->handler (RO)` is set at the creation of the song. It is based on `track->url` at creation and is immutable.
- `$song->_currentTrackHandler (RW)` is set when a single track happens to be a playlist, for each item. It allows each individual sub-tracks to have their own PH when it relates to some of their management. It means that it is empty most of the time but PH can update it when `$track` is changed after scanning (for example when upgrading from HTTP to HTTPS)
- `$song->currentTrackHandler()` is a method that returns (`_currentTrackHandler || handler`) so it tells what shall be used for all URL related to the current (sub) track
- `$streamingController->urlHandler` is RO and set at the creation of the song streaming controller, based on the `streamUrl` (in [`Slim::Player::Song::open`](Slim/Player/Song.pm))
- `$streamingController->streamHandler` is RO and set at creation of the song streaming controller. It is the class of the **socket** object created by `$song->handler->new`.
- `$streamingController->currentTrackHandler` is a shortcut to `$song->currentTrackHandler`

### Protocol Handlers

These files contain a base class but whose methods are called in different contexts (the $self):

1. a `$song` context means they are called with a `$song->currentTrackHandler` or `$song->handler`
2. a `$sock` context means they are called with a `$socket` (or the object) that was created by `$song->handler->new`
3. a simple `$url` context means they are called by `$song->currentTrackHandler`, `$song->handler` or a `$streamingController->streamHandler`

So it's a bit confusing that methods from the same package can be object-oriented called with totally different type of ancestors/context. In fact, some methods can be called in both context if the ancestor of the PH is capable of (e.g. HTTP).

- functions like `sysread` are only called with a `$sock` context
- functions like `getMetadataFor` can be called with a `$song` or a `$url` context
- functions like `requestString` can be called in a `$song` or `$sock` context

### Example of `requestString`

That function is to create the HTTP headers to be sent with the `GET` to grab the actual audio. It can be called in proxied or direct mode (in direct mode, there is no `$sock` available). Until version 8.2, it was only called in the context of `urlHandler` because such PH always derive from some sort of HTTP/RemoteStream. It could not be a `songHandler` as these might have a non-HTTP base so `requestString` will not exist.

But that caused a problem when a song's PH spits out a URL that can be direct **but** still wants to modify the `requestString`, he would never see the `requestString` as the one being called was in the class of `urlHandler` (means `streamUrl`). Since 8.2, the call of `requestString` is now trying in order first `songHandler` then `urlHandler`.

### Example of `getMetadataFor`

That function is called with the handler from `handlerForURL` most of the time but in many cases the URL can be the playing song. This is an issue if the song has redefined its `$track->url` (thin protocol for example). Now it is covered because when calling [`Slim::Player::Protocols::HTTP::getMetadataFor`](Slim/Player/Protocols/HTTP.pm) (most probably the base class) there we verify that we are not checking the current song in which case we call `currentTrackHandler->getMetadataFor`.

### Example of `canDirectStream` and `canDirectStreamSong`

The method `canDirectStream` is first invoked in a `$player` context with `currentTrack->url` and `$sock`. Its role is to check with protocol handlers if they will actually spit out a HTTP(s) URL that can be directly streamed by the player. The protocol handler must return the direct URL if it allows that LMS places it in `$song->streamUrl` (before the `StreamingController` is created).

In protocol handler's contexts, `canDirectStream` is invoked with the `$client` and `currentTrack->url`. From there and if available, `canDirectStreamSong` is invoked with the `$client` and the `$song` (it seems strange to have these 2 methods when one would have probably sufficed).

If `canDirectStreamSong` is missing, `canDirectStream` is invoked with the streamable URL. When using or subclassing, [`Slim::Player::Protocols::HTTP`](Slim/Player/Protocols/HTTP.pm) or [`Slim::Player::Protocols::HTTPS`](Slim/Player/Protocols/HTTPS.pm), protocol handler do not need to offer a `canDirectStream` as the base class will invoke it from `canDirectStreamSong` using the `streamUrl`.

## HTTP Methods

The constructors of [`Slim::Networking::SimpleAsyncHTTP`](Slim/Networking/SimpleAsyncHTTP.pm) and [`Slim::Networking::Async::HTTP`](Slim/Networking/Async/HTTP.pm) have two new keys in their hash argument:

- `options`: set parameters for underlying socket object. For example, to change SSL

  ```perl
  options => {
      SSL_cipher_list => 'DEFAULT:!DH',
      SSL_verify_mode => Net::SSLeay::VERIFY_NONE
  }
  ```

- `socks`: use a socks proxy to tunnel the request (see [SOCKS.md](SOCKS.md))

  ```perl
  socks => {
      ProxyAddr => '192.168.0.1', # can also be a FQDN
      ProxyPort => 1080,          # optional, 1080 by default
      Username => 'user',         # only for socks5
      Password => 'password',     # only for socks5
  }
  ```

  ```perl
  Slim::Networking::Async::HTTP->new({
      options => {
          SSL_cipher_list => 'DEFAULT:!DH',
          SSL_verify_mode => Net::SSLeay::VERIFY_NONE
      },
      socks => {
          ProxyAddr => '192.168.0.1',
          ProxyPort => 1080,
      }
  });
  ```
