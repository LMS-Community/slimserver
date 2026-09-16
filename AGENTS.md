# AGENTS.md — Lyrion Music Server (LMS)

Notes for AI agents working in this repo. See also `DEVELOPERS.md` (protocol-handler /
scanning internals) and `t/README.md` (running tests).

## What this repo is

Lyrion Music Server (LMS, fka Logitech Media Server / SlimServer / SqueezeCenter) is a
**Perl server**. It does not decode/play audio itself for the common case — it indexes a
music library, builds playlists, and either:

- tells a player to **direct-stream** a URL/file itself (server just hands out a URL,
  no server-side audio processing at all), or
- **transcodes** on the server (spawns `sox`/`flac`/`lame`/`ffmpeg`/etc. as a pipeline of
  external processes) and streams the resulting bytes to the player.

Actual audio decoding/output on the player side happens in separate codebases not in this
repo: squeezelite (C, most software players today), SqueezePlay/jivelite, or the original
hardware DSPs (SliMP3, Squeezebox 1/2/3, Boom, Transporter, Receiver).

## Player class hierarchy (`Slim/Player/*.pm`)

```
Slim::Player::Client
  └─ Slim::Player::Player
       └─ Slim::Player::Squeezebox
            ├─ Slim::Player::Squeezebox1        (original SliMP3/Squeezebox, mas35x9 DAC chip)
            ├─ Slim::Player::SqueezeSlave
            └─ Slim::Player::Squeezebox2         (SB2/3, and base for everything modern)
                 ├─ Slim::Player::Boom
                 ├─ Slim::Player::Transporter
                 ├─ Slim::Player::Receiver
                 └─ Slim::Player::SqueezePlay     (squeezelite, jivelite, iPeng-like clients)
```

Per-model capability limits (max volume/bass/treble/pitch, etc.) are plain subroutines
(`maxPitch`, `minBass`, ...) overridden per class — grep for `sub max<Feature>` /
`sub min<Feature>` to find what a given player model actually supports. A feature whose
`max == min` is a no-op for that model even though the generic mixer code path exists.

## The mixer-feature pattern (volume/bass/treble/pitch/stereoxl)

`Slim::Player::Client::_mixerPrefs()` is the generic getter/setter used by `volume()`,
`bass()`, `treble()`, `pitch()`, `stereoXL()`. Wired up via:
- default value in `$defaultPrefs` in `Slim/Player/Player.pm`
- `$prefs->setChange(...)` hook in the same file to push changes to the player
- `mixer` CLI/IR command in `Slim/Control/Commands.pm` and documented in `Slim/Control/Request.pm`
- per-model `max*`/`min*` overrides to enable/disable/clamp the feature

**Important existing/dead feature**: there is already a `pitch` mixer control
(`Slim::Player::Squeezebox1::pitch`/`sendPitch`) that changes playback speed by
reprogramming the mas35x9 decoder chip's clock (`OfreqControl` register) — a "vinyl
speed" trick that shifts pitch along with speed, MP3-only. It **only works on the
original Squeezebox1/SliMP3 hardware**. Every modern class (`Squeezebox2` and everything
inheriting from it — Boom, Transporter, SqueezePlay/squeezelite, SqueezeSlave) explicitly
pins `maxPitch`/`minPitch` to `100`, i.e. locked/no-op. So today this control is
effectively dead for ~all real-world installs. Do not assume "pitch" support means
speed-changing works generally — it doesn't.

## Transcoding pipeline (`convert.conf`, `Slim/Player/TranscodingHelper.pm`)

`convert.conf` (+ `custom-convert.conf`, `slimserver-convert.conf`) defines, per
`<src-format> <dst-format> <player-model-or-*> <client-id-or-*>`, a shell pipeline of
external binaries (referenced as `[binname]`, resolved via `Slim::Utils::Misc::findbin`).
The comment line immediately after the header line is *not* a comment — it's parsed by
`_getCapabilities()` into a capability spec, e.g.:

```
mp3 mp3 transcode *
	# IFB:{BITRATE=--abr %B}D:{RESAMPLE=--resample %D}
	[lame] --silent -q $QUALITY$ $BITRATE$ $RESAMPLE$ --mp3input $FILE$ -
```

`I/F/R` = can transcode from stdin/file/remote-URL, `E`-style `LETTER:{VAR=template}`
entries declare optional capabilities with a `$VAR$` substitution template containing
`%x`-style tokens that `tokenizeConvertCommand2()` fills in (see the big `%v`/%d/%b/...
table around `Slim/Player/TranscodingHelper.pm:600`). `getConvertCommand2()` decides
which profile to use; it can *force* transcoding even for a natively-supported format by
requiring an extra capability letter unconditionally (see how `D`/`RESAMPLE` is forced
when `samplerateLimit` is set: `Slim/Player/TranscodingHelper.pm:349`) — this is the
existing, sanctioned mechanism for "run this native-format audio through a filter
anyway", already used for smart bitrate limiting. `<type> <type> transcode *` profiles
(see the `mp3 mp3 transcode *` / `flc flc transcode *` examples in `convert.conf`) exist
specifically for this "same format in and out, but pipe it through a processor" case; a
protocol handler can also opt in wholesale via an optional `forceTranscode($client,
$type)` method (checked in `getConvertCommand2`), though no in-tree handler currently
implements it.

This is the natural extension point for any per-track/per-client audio DSP effect
(volume normalization, resampling, speed change, etc.) that needs to run through
`sox`/`ffmpeg` rather than being handled by player firmware.

### Playback speed (`mixer speed`)

A genuine, pitch-preserving playback-speed control (for audiobooks/podcasts) was added
using exactly the mechanism above — see it as the reference example for adding another
DSP-effect mixer feature:
- `speed` mixer feature (100 == normal, 150 == 1.5x, range 50-200), plumbed exactly like
  `pitch` (`Client.pm::speed()`/`maxSpeed`/`minSpeed`, `Player.pm` default pref, `mixer`
  CLI command/query in `Commands.pm`/`Queries.pm`). Unlike `pitch`, `maxSpeed`/`minSpeed`
  are enabled at the `Slim::Player::Squeezebox` level (not per-model), since it works via
  transcoding rather than player hardware.
- **Per-player enable/reset setting**: hidden by default. A new `speedReset` player pref
  (`Player.pm` default `0`) is exposed on the *Settings > Audio* page
  (`Slim::Web::Settings::Player::Audio`, `HTML/EN/settings/player/audio.html`) as a 3-way
  dropdown: `0` = off (default — `Squeezebox::maxSpeed`/`minSpeed` collapse to `100/100`,
  exactly like a player that never had the feature, so the Now Playing control stays
  hidden and `TranscodingHelper` never engages `V`), `1` = on, reset to 1x at the start of
  every track, `2` = on, reset to 1x only when the album changes (audiobooks split into
  chapter tracks keep the chosen speed across chapters). `Slim::Player::Squeezebox::
  _speedEnabled` is the single source of truth for "is speed actually usable right now" —
  both `TranscodingHelper::getConvertCommand2` and `StreamingController::
  playingSongElapsed`'s speed-scaling (see below) must gate on it too, not just on the raw
  `speed` pref value, because turning the setting off does **not** reset the stored
  `speed` pref back to 100 — a stale non-100 value must have zero effect anywhere once
  disabled.
- **Reset implementation**: `Slim::Control::Commands::_speedResetOnNewSong` is subscribed
  to `['playlist'], ['newsong']` and, per the `speedReset` policy, calls
  `$client->speed(100)` followed by the same `gototime(songTime($client))` live-reopen
  used for manual speed changes. Firing this at track-start means the reopen lands at (or
  extremely close to) position 0, so it reads as the track having simply opened at the
  reset speed — no separate "pre-open" hook was needed. Album-change detection compares
  `Slim::Player::Playlist::track($client)->albumid` against the previous value, stashed
  via `$client->pluginData('speedResetAlbumId', ...)` (a generic non-plugin-namespaced
  key/value store on the client, not persisted to prefs).
  - **Gotcha #1 — where the subscribe call lives**: the actual `subscribe()` call is in
    `Slim::Control::Request::init()` (next to the `mixer speed` `addDispatch` entries),
    *not* at `Slim::Control::Commands`'s top level. `Request.pm` does `use
    Slim::Control::Commands;` partway through its own compilation (before `Request.pm`
    has finished defining `subscribe`), so a top-level `Slim::Control::Request::subscribe`
    call sitting in `Commands.pm` dies at server startup with `Undefined subroutine
    &Slim::Control::Request::subscribe`. `init()` only runs later, at real server startup
    (`slimserver.pl` calls it explicitly), by which point everything is fully loaded.
  - **Gotcha #2 — `newsong` fires on same-track reopens, not just real track changes**:
    a stream reopen — a manual seek, *or the very `gototime()` reopen this feature issues
    for a manual speed change* — re-triggers the `playlist newsong` notification for the
    still-current track. Without a guard, that means: user picks 2x → `mixerCommand`
    reopens the stream → that reopen re-fires `newsong` → this handler immediately resets
    speed back to 100 (self-inflicted revert, invisible until the next status poll
    refreshes the dropdown) — and identically, any ordinary user seek on the progress bar
    would reset speed too. Fixed by comparing
    `Slim::Player::Source::playingSongIndex($client)` against the value stashed from the
    previous call (`$client->pluginData('speedResetLastIndex', ...)`) and bailing out
    whenever the index hasn't actually changed — only a genuine playlist advance gets
    past that check.
  - **Gotcha #4 — `Client::pluginData($key)` doesn't do what it looks like for non-plugin
    callers**: the single-arg *getter* form only returns a per-key value when the caller's
    package matches `Slim::Plugin::*`/`Plugins::*` (it uses `caller(0)` to namespace
    plugins automatically); for any other caller - like `Slim::Control::Commands` here -
    that branch is skipped and it falls through to `return $client->_pluginData;`, handing
    back the *entire* data hash instead of the one key. That value is always a (truthy)
    hashref, and `hashref == $integer_index` is essentially never numerically true, so the
    Gotcha #2 index-comparison guard above was **silently always false** - every reopen
    (including the feature's own speed-change reopen) looked like a genuine track change,
    and with a reset policy enabled this immediately reverted the speed right back to 100
    on every single speed change. The two-arg *setter* form (`pluginData($key, $value)`)
    is unaffected - it's key-specific for any caller. Fixed by fetching the whole hash
    once via the no-arg form (`my $data = $client->pluginData();`) and indexing into it
    directly (`$data->{'speedResetLastIndex'}`) instead of trying to read a single key
    through the getter form.
  - **Gotcha #5 — reopening right at the end of a track**: `mixerCommand` skips the reopen
    (leaves `$reopenAtTime` `undef`, so the pref still changes but nothing reopens) when
    `songTime()` is within 2s of `playingSongDuration()`. Asking a decoder to `--skip` to
    virtually the end of the file makes e.g. `flac` log `ERROR while decoding data: state =
    FLAC__STREAM_DECODER_END_OF_STREAM` (harmless - it just means ~nothing was left to
    decode), which in turn closes `sox`'s output pipe early and logs a "Broken pipe" right
    after it. Playback is unaffected either way (the track is about to end/advance on its
    own), so it's not worth the log noise - the new speed simply takes effect starting with
    whatever plays next.
- `TranscodingHelper.pm` forces the `V` capability into `@need` whenever
  `prefs->client($client)->get('speed') != 100`, exactly mirroring how `D`/samplerate-limit
  forcing works; substitution `%y` gives a `sox`-ready tempo factor (e.g. `1.500`).
- `convert.conf`: mp3/flac/aac/mp4 → flac get a *second* same-key profile instance
  (auto-numbered `-1` by the loader on a duplicate `<src> <dst> <player> <client>` line)
  that declares `V:{SPEED=tempo %y}` and pipes through `sox ... tempo $SPEED$`. Because
  it's a new instance (not an edit of the live passthrough entry), normal playback for
  users not touching the speed control is untouched — the new pipeline is only reached
  when the `V` capability is actually required. `flc flc transcode *` was edited in place
  instead, since it already runs `sox` unconditionally (only reached via forced `D`/`V`,
  never plain playback), so appending `$SPEED$` there costs nothing when unused.
- Web UI: `HTML/Default/status_header.html` + `Main.js` only (Classic skin is a
  fundamentally different, non-ExtJS template and wasn't touched). The `<select
  id="ctrlSpeed">` is hidden by default and only shown when a `status` poll's response
  includes `mixer speed` (i.e. `maxSpeed - minSpeed > 0` for that player).
- To extend to more source formats: add another `<src> flc * *` (or `<src> <src>
  transcode *`) duplicate instance with `V:{SPEED=tempo %y}` and a `sox ... tempo $SPEED$`
  stage — do not edit a live/no-`sox` passthrough entry in place, or every normal
  conversion for that format pays the extra process even when nobody uses speed control.
  **Also give it `T`/`U` (start/end-time seek)** — see below for why that's not optional.
- **Live reopen at current position**: changing `mixer speed` while a track is playing
  calls `Slim::Player::Source::gototime($client, songTime($client))` (in `Commands.pm`) to
  reopen the stream immediately rather than waiting for the next track. This *requires*
  every speed-carrying profile to also declare `T` (start-time seek), or `Song::open()`
  silently falls back to `seek=false, time=0` and the track **restarts from 0** instead of
  resuming — this was found and fixed live (squeezelite + real files): `flc` already had
  `T`/`U` (flac's native `--skip=%t`/`--until=%v`); `aac`/`mp4` reuse the existing
  `faad -j %s`/`-e %u` flags already used elsewhere in `convert.conf` for the same purpose;
  `mp3` has no native decode-time-skip in `lame`, so its `T` is done as a `sox trim %s`
  effect on the decoded PCM *before* `tempo` (order matters: trim first, then tempo) —
  costs one extra decode-from-start on seek/reopen only, not during normal playback.
  Confirmed live: reopening at speed 150 on a real FLAC file produced
  `flac --skip=2:41.75 ... | sox ... tempo 1.500`, resuming at the same position rather
  than restarting. Do **not** reintroduce a speed-carrying profile without `T`/`U` — the
  reopen call doesn't gate on `Song::canSeek()` (that value is cached from when the song
  was first opened and won't reflect a speed change made afterwards, so it can't be trusted
  as a pre-check here); it relies on every profile actually supporting the seek it asks for.
  - **Gotcha #3 — `Song::open()` itself *does* gate on the stale `canSeek()` cache**: even
    though `mixerCommand` avoids checking `Song::canSeek()` directly, `Song::open()`'s own
    decision whether to request capability `T` at all is `$wantTranscoderSeek = ... &&
    $self->canSeek() == 2` — and `canSeek()`/`canDoSeek()` memoizes its result in `_canSeek`
    the *first* time anything calls it for that `Song` object (`return $self->_canSeek() if
    defined ...`), which commonly happens earlier in playback (e.g. the web UI's seek bar
    querying seek support) while speed was still 100 and no transcoding was needed at all —
    caching `canSeek() == 1` (handler-level seek) rather than `2` (transcoder-level). Once
    cached, the speed-change reopen forever sees the stale `1`, `T` never gets requested,
    and every reopen restarts from 0 instead of resuming (V/tempo still applies, but from
    the wrong position) — the exact "resume, don't restart" behavior this whole mechanism
    exists for silently regresses. Fixed by clearing the cache (`$song->_canSeek(undef)` —
    the same pattern `Song::setStatus()` already uses for its own cache-invalidation case)
    right before the reopen in `mixerCommand`, forcing `canSeek()` to re-evaluate under the
    *new* speed pref (already written to prefs by this point) the next time `Song::open()`
    asks.
- **Elapsed-time scaling gotcha**: `Slim::Player::StreamingController::playingSongElapsed()`
  computes song position as `startOffset + client->songElapsedSeconds()`. `songElapsedSeconds()`
  is the player's own decode-clock — seconds of the *transcoded output stream* it has played —
  which `sox tempo` has compressed/stretched relative to the original track (tempo changes
  duration, not sample rate). It must be scaled by `speed/100` before being added to
  `startOffset` (already in original-track seconds), or `songTime()` drifts from the real
  position whenever `speed != 100` — this was the cause of a live bug report: going from a
  faster speed to a slower one made the position **jump backward** on `mixer speed` reopen,
  because the under-scaled elapsed time was fed straight into `gototime()`. Relatedly, in
  `Commands.pm`'s `mixerCommand`, the pre-reopen `songTime($client)` call **must be evaluated
  before** `$client->speed($newval)` sets the new pref — `playingSongElapsed()` always scales
  by the client's *current* speed, so if the pref is updated first, time accumulated under the
  old speed gets scaled by the new speed instead, landing the reopen at the wrong position
  again. `mixerCommand` therefore captures `songTime()` into `$reopenAtTime` *before* the
  `$client->$entity($newval)` pref-setting line, then reopens with that saved value afterward.

**Non-obvious gotcha for any new `mixer` (or other) subcommand**: a subcommand string
accepted inside `mixerCommand`/`mixerQuery`'s own `isNotCommand`/`isNotQuery` check is
*not enough* to make it dispatchable. `Slim::Control::Request::init()` maintains its own,
completely separate static table via `addDispatch(['mixer', '<subcommand>', ...], [...])`
— e.g. `addDispatch(['mixer', 'pitch', '_newvalue'], [1, 0, 1,
\&Slim::Control::Commands::mixerCommand])`. Forgetting the `addDispatch` entries makes the
command silently fail over the JSON-RPC HTTP endpoint: `$request->isStatusDispatchable`
comes back false, the request never reaches `mixerCommand`, and `Slim::Web::JSONRPC`
closes the socket with **zero bytes written and no response** — the browser sees a bare
connection reset (Firefox: `NS_ERROR_NET_RESET`), and nothing is logged unless you dig
into `network.jsonrpc` debug output. The CLI (raw port, `Slim::Control::Stdio`) doesn't
exhibit this as cleanly since its confirmation-echo behavior masks it. If you add a new
mixer-style subcommand, add both the `addDispatch` rows (query `?` and set `_newvalue`)
*and* the subcommand string in the two `isNotCommand`/`isNotQuery` arrays — all four are
required, not just the two inside `Commands.pm`/`Queries.pm`.

## Tests

```shell
perl -I$PWD/CPAN/arch/<perlver>/ -I$PWD/CPAN/arch/<perlver>/<platform>/auto t/<test>.t
```
See `t/README.md`.
