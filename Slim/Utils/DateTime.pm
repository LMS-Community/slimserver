package Slim::Utils::DateTime;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2025 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use Date::Parse;
use HTTP::Status qw(RC_INTERNAL_SERVER_ERROR);
use JSON::XS qw(decode_json);
use POSIX qw(strftime);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Unicode;
use Slim::Networking::SimpleAsyncHTTP;

# The server/url that provides us with date/time data, including an Olson
# formatted TimeZone. The response is JSON formatted.
use constant TIME_INFO_URL => 'https://api.lms-community.org/time';

my $log = logger('server');
my $prefs = preferences('server');
my $tzInfo;

=head1 NAME

Slim::Utils::DateTime

=head1 SYNOPSIS

my $longDate = Slim::Utils::DateTime::longDateF()

=head1 DESCRIPTION

A collection of date & time releated functions.

Returns date & time information based on date & time prefs formatting settings.

=head1 METHODS

=cut

# the following functions cleanup the date and time, specifically:
# remove the leading zeros for single digit dates and hours
# where a | is specified in the format

# The LC_TIME is set in ::Strings when we select a language.

=head2 longDateF( $time, $format )

Returns a string of the time passed (or current time if none passed),
using the passed format (or pref: longdateFormat if not passed).

Encoding is the current locale.

=cut

sub longDateF {
	my $time = shift || time();
	my $format = shift || $prefs->get('longdateFormat');
	my $tz = shift;

	my $date = strftime($format, localtimeInTZ($time, $tz));
	   $date =~ s/\|0*//;

	return Slim::Utils::Unicode::utf8decode_locale($date);
}

=head2 shortDateF( $time, $format )

Returns a string of the time passed (or current time if none passed),
using the passed format (or pref: shortdateFormat if not passed).

Encoding is the current locale.

=cut

sub shortDateF {
	my $time = shift || time();
	my $format = shift || $prefs->get('shortdateFormat');
	my $tz = shift;

	my $date = strftime($format, localtimeInTZ($time, $tz));
	   $date =~ s/\|0*//;

	return Slim::Utils::Unicode::utf8decode_locale($date);
}

=head2 timeF( $time, $format, $timeIsUTC )

Returns a string of the time passed (or current time if none passed),
using the passed format (or pref: timeFormat if not passed).

The $timeIsUTC param is optional and indicates whether the passed time is in UTC
or the local time zone.  By default it is interpreted in the local time zone.

Encoding is the current locale.

=cut

sub timeF {
	my $ltime = shift || time();
	my $format = shift || $prefs->get('timeFormat');
	my $timeIsUTC = shift;
	my $tz = shift;

	my @timeDigits = $timeIsUTC ? gmtime($ltime) : localtimeInTZ($ltime, $tz);

	# remove leading zero if another digit follows
	my $time  = strftime($format, @timeDigits);
	   $time =~ s/\|0?(\d+)/$1/;

	return Slim::Utils::Unicode::utf8decode_locale($time);
}

=head2 timeFormat( $time )

Returns a string of the time in hh:mm:ss - not daytime, to be used as total playtime etc.

=cut

sub timeFormat {
	my $time = shift || 0;

	sprintf(
	    "%d:%02d:%02d",
	    ($time / 3600),
	    ($time / 60) % 60,
	    $time % 60,
	);
}

=head2 fracSecToMinSec( $seconds )

Turns seconds into min:sec

=cut

sub fracSecToMinSec {
	my $seconds = shift;

	my ($min, $sec, $frac, $fracrounded);

	$min = int($seconds/60);
	$sec = $seconds%60;
	$sec = "0$sec" if length($sec) < 2;

	# We want to round the last two decimals but we
	# always round down to avoid overshooting EOF on last track
	$fracrounded = int($seconds * 100) + 100;
	$frac = substr($fracrounded, -2, 2);

	return "$min:$sec.$frac";
}

=head2 secsToPrettyTime( $seconds, $client )

Turns seconds into HH:MM AM/PM.  Format returned is 12h or 24h depending on the user's preferences.

=cut

sub secsToPrettyTime {
	my $secs = shift;
	my $client = shift;

	my ($h0, $h1, $m0, $m1, $p) = timeDigits($secs, $client);

	my $string = ' ';

	if (!defined $p || $h0 != 0) {

		$string = $h0;
	}

	$string .= "$h1:$m0$m1";

	if (defined $p) {
		$string .= " $p";
	}

	return $string;
}

=head2 prettyTimeToSecs( "HH:MM AM/PM" )

Turns a pretty time string into seconds.

=cut

sub prettyTimeToSecs {
	my $secs = shift;

	my ($mm,$hh) = (strptime($secs))[1,2];

	return ($hh*3600) + ($mm*60);
}

=head2 splitTime ($time, $24h, $client)

This function converts a unix time value to hours, minutes and am/pm if applicable.  am/pm is given as undef or 0/1.

Takes as arguments, a scalar time value or a reference to one and optionally whether the time should be returned in 12h (true) or 24h (false) format.  The default format returned is based on the current timeFormat pref.

=cut

sub splitTime {
	my $time = shift;
	my $twelveHour = shift;

	if (! defined $twelveHour) {

		$twelveHour = hasAmPm(shift);

	}

	if (ref($time))  {
		$time = $$time;
	}
	$time = $time || 0;

	my $h = int($time / (60*60));
	my $m = int(($time - $h * 60 * 60) / 60);
	my $p = undef;

	if ($twelveHour) {
		$p = 0;

		if ($h > 11) { $h -= 12; $p = 1; }

		if ($h == 0) { $h = 12; }
	}

	return ($h, $m, $p);
}

sub hasAmPm {
	return $prefs->get('timeFormat') =~ /(?:%p|%I)/;
}

=head2 bcdTime ( $time )

This function converts a time value in seconds, minutes and hours into BCD format.  It's used when working
with the RTC in Boom and other devices.

=cut

sub bcdTime {
	my ($sec, $min, $hour) = @_;

	my $h_10 = int( $hour / 10);
	my $h_1 = $hour % 10;
	my $m_10 = int( $min / 10);
	my $m_1 = $min % 10;
	my $s_10 = int( $sec / 10);
	my $s_1 = $sec % 10;
	my $hhhBCD = $h_10 * 16 + $h_1;
	my $mmmBCD = $m_10 * 16 + $m_1;
	my $sssBCD = $s_10 * 16 + $s_1;

	return ($sssBCD, $mmmBCD, $hhhBCD);
}

=head2 hourMinToTime ( $h, $m, $p)

This function converts discrete time values into a scalar time value.  It is the reverse of splitTime().

Takes as arguments, the hour ($h), minute ($m) and whether time is am or pm if applicable ($p).

=cut

sub hourMinToTime {
	my ($h, $m, $p) = @_;

	$p ||= 0;
	return (((($p * 12) + $h) * 60) + $m) * 60;
}

=head2 timeDigits( $time, $client )

This function converts a unix time value to the individual digits for hours, minutes and am/pm.  am/pm is returned as 'AM' or 'PM'.

Takes as arguments, a scalar time value or a reference to one.

=cut

sub timeDigits {
	my $time = shift;
	my $client = shift;

	my ($h, $m, $p) = splitTime($time, undef, $client);

	if ($h < 10) { $h = '0' . $h; }

	if ($m < 10) { $m = '0' . $m; }

	my $h0 = substr($h, 0, 1);
	my $h1 = substr($h, 1, 1);
	my $m0 = substr($m, 0, 1);
	my $m1 = substr($m, 1, 1);

	if (defined $p) {
		$p = $p ? 'PM' : 'AM';
	}

	return ($h0, $h1, $m0, $m1, $p);
}

=head2 timeDigitsToTime( $h0, $h1, $m0, $m1, $p)
timeDigitsToTime( $h, $m, $p)

This function converts discreet time digits into a scalar time value.  It is the reverse of timeDigits().

Takes as arguments, the hour ($h0, $h1), minute ($m0, $m1) and whether time is am or pm if applicable ($p).

=cut

sub timeDigitsToTime {
	my ($h0, $h1, $m0, $m1, $p) = @_;

	my $h = $h0 * 10 + $h1;
	if (defined $p) {
		# 12h - treat 12am as midnight and 12pm as noon
		if ($h == 12) {
			if ($p) {
				$h = 12;
				$p = 0;
			} else {
				$h = 0;
			}
		}
	} else {
		$p = 0;
	}

	my $time = (((($p * 12)            # pm adds 12 hours
		 + $h) * 60)               # convert hours to minutes
		 + ($m0 * 10) + $m1) * 60; # then  minutes to seconds

	return $time;
}

=head2 timeFormats()

Return a hash ref of default time formats.

=cut

sub timeFormats {
	return {
		# hh is hours
		# h is hours (leading zero removed)
		# mm is minutes
		# ss is seconds
		# pm is either AM or PM
		# anything at the end in parentheses is just a comment
		q(%I:%M:%S %p)	=> q{hh:mm:ss pm (12h)}
		,q(%I:%M %p)	=> q{hh:mm pm (12h)}
		,q(%H:%M:%S)	=> q{hh:mm:ss (24h)}
		,q(%H:%M)	=> q{hh:mm (24h)}
		,q(%H.%M.%S)	=> q{hh.mm.ss (24h)}
		,q(%H.%M)	=> q{hh.mm (24h)}
		,q(%H,%M,%S)	=> q{hh,mm,ss (24h)}
		,q(%H,%M)	=> q{hh,mm (24h)}
		# no idea what the separator between minutes and seconds should be here
		,q(%Hh%M:%S)	=> q{hh'h'mm:ss (24h 03h00:00 15h00:00)}
		,q(%Hh%M)	=> q{hh'h'mm (24h 03h00 15h00)}
		,q(|%I:%M:%S %p)	=> q{h:mm:ss pm (12h)}
		,q(|%I:%M:%S)	=> q{h:mm:ss (12h)}
		,q(|%I:%M %p)		=> q{h:mm pm (12h)}
		,q(|%I:%M)		=> q{h:mm (12h)}
		,q(|%H:%M:%S)		=> q{h:mm:ss (24h)}
		,q(|%H:%M)		=> q{h:mm (24h)}
		,q(|%H.%M.%S)		=> q{h.mm.ss (24h)}
		,q(|%H.%M)		=> q{h.mm (24h)}
		,q(|%H,%M,%S)		=> q{h,mm,ss (24h)}
		,q(|%H,%M)		=> q{h,mm (24h)}
		# no idea what the separator between minutes and seconds should be here
		,q(|%Hh%M:%S)		=> q{h'h'mm:ss (24h 3h00:00 15h00:00)}
		,q(|%Hh%M)		=> q{h'h'mm (24h 3h00 15h00)}
	};
}

=head2 longDateFormats()

Return a hash ref of default long date formats.

=cut

sub longDateFormats {
	return {
		# WWWW is the name of the day of the week
		# WWW is the abbreviation of the name of the day of the week
		# MMMM is the full month name
		# MMM is the abbreviated month name
		# DD is the day of the month
		# YYYY is the 4 digit year
		# YY is the 2 digit year
		q(%A, %B |%d, %Y)  => q(WWWW, MMMM DD, YYYY),
		q(%a, %b |%d, %Y)  => q(WWW, MMM DD, YYYY),
		q(%a, %b |%d, '%y) => q(WWW, MMM DD, 'YY),
		q(%A, |%d %B %Y)   => q(WWWW, DD MMMM YYYY),
		q(%A, |%d. %B %Y)  => q(WWWW, DD. MMMM YYYY),
		q(%a, |%d %b %Y)   => q(WWW, DD MMM YYYY),
		q(%a, |%d. %b %Y)  => q(WWW, DD. MMM YYYY),
		q(%A |%d %B %Y)    => q(WWWW DD MMMM YYYY),
		q(%A |%d. %B %Y)   => q(WWWW DD. MMMM YYYY),
		q(%a |%d %b %Y)    => q(WWW DD MMM YYYY),
		q(%a |%d. %b %Y)   => q(WWW DD. MMM YYYY),
		# Japanese styles
		q(%Y/%m/%d\(%a\))  => q{YYYY/MM/DD(WWW)},
		q(%Y-%m-%d\(%a\))  => q{YYYY-MM-DD(WWW)},
		q(%Y/%m/%d %A)     => q{YYYY/MM/DD WWWW},
		q(%Y-%m-%d %A)     => q{YYYY-MM-DD WWWW},
	};
}

=head2 shortDateFormats()

Return a hash ref of default short date formats.

=cut

sub shortDateFormats {
	return {
		# MM is the month of the year
		# DD is the day of the year
		# YYYY is the 4 digit year
		# YY is the 2 digit year
		q(%m/%d/%Y) => q{MM/DD/YYYY},
		q(%m/%d/%y) => q{MM/DD/YY},
		q(%m-%d-%Y) => q{MM-DD-YYYY},
		q(%m-%d-%y) => q{MM-DD-YY},
		q(%m.%d.%Y) => q{MM.DD.YYYY},
		q(%m.%d.%y) => q{MM.DD.YY},
		q(%d/%m/%Y) => q{DD/MM/YYYY},
		q(%d/%m/%y) => q{DD/MM/YY},
		q(%d-%m-%Y) => q{DD-MM-YYYY},
		q(%d-%m-%y) => q{DD-MM-YY},
		q(%d.%m.%Y) => q{DD.MM.YYYY},
		q(%d.%m.%y) => q{DD.MM.YY},
		q(%Y-%m-%d) => q{YYYY-MM-DD (ISO)},
		# request 6884
		q(%a |%m/%d) => q{WWW M/DD},
		q(%a %d/|%m) => q{WWW DD/M},
		q(%a %d.|%m) => q{WWW DD.M},
		# Japanese style
		q(%Y/%m/%d) => q{YYYY/MM/DD},
	};
}

=head2 setDefaultFormats()

Set default date/time formats for the selected language.
Formats are to be defined in strings.txt file.

=cut

sub setDefaultFormats {
	$prefs->set('longdateFormat',  Slim::Utils::Strings::string('SETUP_LONGDATEFORMAT_DEFAULT'));
	$prefs->set('shortdateFormat', Slim::Utils::Strings::string('SETUP_SHORTDATEFORMAT_DEFAULT'));
	$prefs->set('timeFormat',      Slim::Utils::Strings::string('SETUP_TIMEFORMAT_DEFAULT'));
}


=head2 getTimeZoneInformation()

A bunch of timezone related helper methods. Reaches out to API server to get the local timezone.
This should keep this platform independent. Server response should look like:

{
	"datetime": "2025-04-03T11:39:10.351+01:00",
	"timezone": "Europe/London",
	"offset": "GMT+1",
	"offsetHours": 1,
	"offsetMinutes": 60,
	"isInDST": true
}

=cut

sub getTimeZoneInformation {
	my $cb = shift || sub { $_[0] };

	if ($tzInfo) {
		# reset cached information if we crossed the DST boundary
		$tzInfo = undef if ($tzInfo->{isInDST} && !isDST()) || (!$tzInfo->{isInDST} && isDST());
	}

	return $cb->($tzInfo) if $tzInfo;

	# API call to retrieve date/time data
	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $http = shift;
			my $res  = eval { decode_json($http->content) };

			if ($@ || ref $res ne 'HASH') {
				$log->error($@ || 'Invalid JSON response: ' . $http->content);
				return $cb->(undef, RC_INTERNAL_SERVER_ERROR);
			}

			$tzInfo = $res;
			($tzInfo->{offsetHHMM}) = (delete $tzInfo->{datetime}) =~ /([+-]\d{2}:\d{2})$/;

			return $cb->($tzInfo);
		},
		sub {
			my $http = shift;
			$log->error("Failed to get TimeZone information from ", join("\n", $http->url, $http->error));
			return $cb->(undef, RC_INTERNAL_SERVER_ERROR);
		},
		{
			timeout => 5,
		}
	)->get(TIME_INFO_URL, Slim::Utils::Misc::apiHeaders(__PACKAGE__));
}

sub getTZName {
	my $cb = shift || sub { $_[0] };

	return getTimeZoneInformation(sub {
		my ($tzInfo, $err) = @_;
		$tzInfo ||= {};

		return $cb->($tzInfo->{timezone}, $err);
	});
}

=head2 getTimezoneNames()

Returns a sorted array ref of known Olson timezone names.  Uses
C<DateTime::TimeZone-E<gt>all_names()> when available, otherwise parses
C<zone1970.tab> (or C<zone.tab>) from C</usr/share/zoneinfo/>.  Returns an
empty array ref when neither source is available.

=cut

my ($_tzHash, $_tzNames);
my ($_dttAvailable, %_tzCache);

sub getTimezoneNames {
	return $_tzNames if defined $_tzNames;

	_initDTT();
	my @names;
	if ($_dttAvailable) {
		@names = DateTime::TimeZone->all_names();
	} elsif (!main::ISWINDOWS) {
		# Parse zone1970.tab (or zone.tab) — same canonical list as DateTime::TimeZone.
		# Format: CC<TAB>coordinates<TAB>TZ[<TAB>comments]
		for my $tabfile (qw(/usr/share/zoneinfo/zone1970.tab /usr/share/zoneinfo/zone.tab)) {
			next unless -f $tabfile;
			open(my $fh, '<', $tabfile) or next;
			while (my $line = <$fh>) {
				next if $line =~ /^#/;
				my $tz = (split /\t/, $line)[2];
				next unless defined $tz;
				chomp $tz;
				push @names, $tz if validateTZName($tz);
			}
			close $fh;
			last if @names;
		}
	}

	$_tzHash  = { map { $_ => 1 } @names };
	$_tzNames = [ sort keys %$_tzHash ];
	return $_tzNames;
}

=head2 validateTZName( $tzName )

Returns true if C<$tzName> looks like a valid Olson timezone identifier
(e.g. C<"Europe/Amsterdam">, C<"America/New_York">).

A TimeZone identifier is, essentially, a POSIX path with some additional (more
and less voluntary) restrictions. These are indicated in the "theory" section
of the tz distribution: L<https://github.com/eggert/tz/blob/main/theory.html>

Identifier components should contain only A-Z, a-z, '-', and '_'. And we need
'/' to join the components together.  Some "legacy" and "etc" TimeZones may
also contain 0-9 and '+', but we do not expect or support such oddities.

Note: we do not guarantee to purge all invalid TimeZones with these checks.

=cut

sub validateTZName {
	my $tzName = shift;

	return 0 unless defined $tzName && length $tzName;

	# When the hash is already cached, use it for an exact match — more
	# accurate than the regex approximation below.
	return $_tzHash->{$tzName} if defined $_tzHash;

	# Fall back to regex (used when the list hasn't been built yet, e.g. at
	# startup or on Windows where zone1970.tab is not available).
	return !(
		$tzName =~ m{[^A-Za-z_\-/]}  # reject if any characters outside that range
		|| $tzName =~ m{^/}          # leading '/' not allowed
		|| $tzName =~ m{/$}          # trailing '/' not allowed
		|| $tzName =~ m{//}          # no component to be empty
		|| $tzName =~ m{ ^- | /- }x  # no component to start with a hyphen
		|| $tzName eq 'Factory'      # reserved for SqueezeOS use
		|| $tzName eq 'Etc/Unknown'  # reserved - never a valid TimeZone
	);
}

=head2 getServerTZName()

Returns the Olson timezone name for this server.  Tries
C<DateTime::TimeZone>, then C<$ENV{TZ}> / C</etc/localtime> symlink, then
the cached geolocation result from the C</time/tz> API.  Returns C<undef> if
none succeed.  Result is cached after the first successful detection.

=cut

my $_serverTZName;

sub getServerTZName {
	return $_serverTZName if defined $_serverTZName;

	# 1. DateTime::TimeZone (works everywhere DTT is installed)
	_initDTT();
	if ($_dttAvailable) {
		my $tz = eval { DateTime::TimeZone->new(name => 'local') };
		if ($tz) {
			my $name = eval { $tz->name() };
			return ($_serverTZName = $name) if $name && validateTZName($name);
		}
	}

	# 2. OS — $ENV{TZ} or /etc/localtime symlink
	if (!main::ISWINDOWS) {
		# $ENV{TZ} may be set explicitly (strip optional leading colon)
		if (defined $ENV{TZ}) {
			(my $tz = $ENV{TZ}) =~ s/^://;
			return ($_serverTZName = $tz) if validateTZName($tz);
		}

		# /etc/localtime symlink
		if (-l '/etc/localtime') {
			my $link = readlink('/etc/localtime') // '';
			if (my ($tz) = $link =~ m{zoneinfo/(.+)$}) {
				return ($_serverTZName = $tz) if validateTZName($tz);
			}
		}
	}

	# 3. Geolocation cache from /time/tz API — last resort
	if ($tzInfo && validateTZName($tzInfo->{timezone} // '')) {
		return ($_serverTZName = $tzInfo->{timezone});
	}

	return undef;
}

sub getTZOffsetHHMM {
	my $cb = shift || sub { $_[0] };

	return getTimeZoneInformation(sub {
		my ($tzInfo, $err) = @_;
		$tzInfo ||= {};

		return $cb->($tzInfo->{offsetHHMM}, $err);
	});
}

sub isDST { (localtime(time()))[8] ? 1 : 0 }

{
	# Minimal DateTime::TimeZone-compatible object built from a plain epoch.
	# Implements the interface required by offset_for_datetime().
	package Slim::Utils::DateTime::_EpochDT;
	sub new             { bless { epoch => $_[1] }, $_[0] }
	sub utc_rd_as_seconds { $_[0]->{epoch} + 62135596800 }
	sub utc_year        { (gmtime($_[0]->{epoch}))[5] + 1900 }
	sub utc_rd_values   {
		my $s = $_[0]->{epoch} + 62135596800;
		return (int($s / 86400), $s % 86400);
	}
}

sub _initDTT {
	return if defined $_dttAvailable;
	$_dttAvailable = eval { require DateTime::TimeZone; 1 } ? 1 : 0;
	if (!$_dttAvailable) {
		my $reason = $@ ? " ($@)" : '';
		$reason =~ s/\s+$//;
		if (!main::ISWINDOWS && eval { POSIX::tzset(); 1 }) {
			$log->info("DateTime::TimeZone not available; using POSIX::tzset fallback for timezone-aware time functions$reason");
		} else {
			$log->warn("DateTime::TimeZone not available; falling back to server timezone$reason");
		}
	}
}

sub _tzObj {
	my ($tzName) = @_;

	_initDTT();
	return if !$_dttAvailable;

	# Cache undef for unrecognised names to avoid repeated warnings.
	if (!exists $_tzCache{$tzName}) {
		$_tzCache{$tzName} = eval { DateTime::TimeZone->new(name => $tzName) };
		if (!$_tzCache{$tzName}) {
			$log->warn($@ ? "DateTime::TimeZone error for '$tzName': $@" : "Unrecognised timezone '$tzName'");
		}
	}
	return $_tzCache{$tzName};
}

=head2 localtimeInTZ( $epoch, $tzName )

Returns a list equivalent to C<localtime($epoch)> but computed in the named
Olson timezone (e.g. C<"Europe/Amsterdam">) rather than the server's local
timezone.  Falls back to server C<localtime> if the timezone is unrecognised
or unavailable.

=cut

sub localtimeInTZ {
	my ($epoch, $tzName) = @_;

	return localtime($epoch) unless $tzName;

	if (my $tz = _tzObj($tzName)) {
		my $offset = $tz->offset_for_datetime( Slim::Utils::DateTime::_EpochDT->new($epoch) );
		return gmtime($epoch + $offset);
	}

	if ($_dttAvailable) {
		# DateTime::TimeZone available but $tzName unrecognised — already warned.
		return localtime($epoch);
	}

	# POSIX::tzset fallback.  Save/restore $ENV{TZ} via 'local'.
	return localtime($epoch) if main::ISWINDOWS;
	main::DEBUGLOG && $log->debug("localtimeInTZ: using POSIX::tzset fallback for '$tzName'");
	my @result;
	{
		local $ENV{TZ} = ':' . $tzName;
		POSIX::tzset();
		@result = localtime($epoch);
	}
	POSIX::tzset();    # re-initialize with the now-restored $ENV{TZ}
	return @result;
}

=head2 tzAbbr( $epoch, $tzName )

Returns the timezone abbreviation (e.g. C<"CET">, C<"CEST">, C<"EST">) for
the named Olson timezone at the given epoch.  Uses the same fallback chain as
L</localtimeInTZ>.

=cut

sub tzAbbr {
	my ($epoch, $tzName) = @_;

	return undef unless $tzName;

	if (my $tz = _tzObj($tzName)) {
		return $tz->short_name_for_datetime( Slim::Utils::DateTime::_EpochDT->new($epoch) );
	}

	if ($_dttAvailable) {
		# DateTime::TimeZone available but $tzName unrecognised — already warned.
		return undef;
	}

	# POSIX::tzset fallback.  Save/restore $ENV{TZ} via 'local'.
	return undef if main::ISWINDOWS;
	main::DEBUGLOG && $log->debug("tzAbbr: using POSIX::tzset fallback for '$tzName'");
	my $abbr;
	{
		local $ENV{TZ} = ':' . $tzName;
		POSIX::tzset();
		$abbr = (POSIX::tzname())[ (localtime($epoch))[8] ];
	}
	POSIX::tzset();    # re-initialize with the now-restored $ENV{TZ}
	return $abbr;
}

=head1 SEE ALSO

L<POSIX::strftime>

=cut

1;
