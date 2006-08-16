package Slim::Utils::DateTime;

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use POSIX qw(strftime);

use Slim::Utils::Unicode;

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

# The LC_TIME is set in ::Unicode when we start.

=head2 longDateF( $time, $format )

Returns a string of the time passed (or current time if none passed),
using the passed format (or pref: longdateFormat if not passed).

Encoding is the current locale.

=cut

sub longDateF {
	my $time = shift || time();
	my $format = shift || Slim::Utils::Prefs::get('longdateFormat');

	my $date = strftime($format, localtime($time));
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
	my $format = shift || Slim::Utils::Prefs::get('shortdateFormat');

	my $date = strftime($format, localtime($time));
	   $date =~ s/\|0*//;

	return Slim::Utils::Unicode::utf8decode_locale($date);
}

=head2 timeF( $time, $format )

Returns a string of the time passed (or current time if none passed),
using the passed format (or pref: timeFormat if not passed).

Encoding is the current locale.

=cut

sub timeF {
	my $ltime = shift || time();
	my $format = shift || Slim::Utils::Prefs::get('timeFormat');

	# remove leading zero if another digit follows
	my $time  = strftime($format, localtime($ltime));
	   $time =~ s/\|0?(\d+)/$1/;

	return Slim::Utils::Unicode::utf8decode_locale($time);
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
		,q(|%I:%M %p)		=> q{h:mm pm (12h)}
		,q(|%H:%M:%S)		=> q{h:mm:ss (24h)}
		,q(|%H:%M)		=> q{h:mm (24h)}
		,q(|%H.%M.%S)		=> q{h.mm.ss (24h)}
		,q(|%H.%M)		=> q{h.mm (24h)}
		,q(|%H,%M,%S)		=> q{h,mm,ss (24h)}
		,q(|%H,%M)		=> q{h,mm (24h)}
		# no idea what the separator between minutes and seconds should be here
		,q(|%Hh%M:%S)		=> q{h'h'mm:ss (24h 03h00:00 15h00:00)}
		,q(|%Hh%M)		=> q{h'h'mm (24h 03h00 15h00)}
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
		# Japanese style
		q(%Y/%m/%d) => q{YYYY/MM/DD},
	};
}

=head1 SEE ALSO

L<POSIX::strftime>

=cut

1;
