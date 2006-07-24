package MP3::Info;

# JRF: Added support for ID3v2.4 spec-valid frame size processing (falling back to old
#      non-spec valid frame size processing)
#      Added support for ID3v2.4 footers.
#      Updated text frames to correct mis-terminated frame content.
#      Added ignoring of encrypted frames.
#      TODO: sort out flags for compression / DLI

require 5.006;

use strict;
use overload;
use Carp;
use Fcntl qw(:seek);

use vars qw(
	@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION $REVISION
	@mp3_genres %mp3_genres @winamp_genres %winamp_genres $try_harder
	@t_bitrate @t_sampling_freq @frequency_tbl %v1_tag_fields
	@v1_tag_names %v2_tag_names %v2_to_v1_names $AUTOLOAD
	@mp3_info_fields %rva2_channel_types
	$debug_24 $debug_Tencoding
);

@ISA = 'Exporter';
@EXPORT = qw(
	set_mp3tag get_mp3tag get_mp3info remove_mp3tag
	use_winamp_genres
);
@EXPORT_OK = qw(@mp3_genres %mp3_genres use_mp3_utf8);
%EXPORT_TAGS = (
	genres	=> [qw(@mp3_genres %mp3_genres)],
	utf8	=> [qw(use_mp3_utf8)],
	all	=> [@EXPORT, @EXPORT_OK]
);

# $Id$
($REVISION) = ' $Revision: 1.19 $ ' =~ /\$Revision:\s+([^\s]+)/;
$VERSION = '1.21';

# JRF: Whether we're debugging the ID3v2.4 support
$debug_24 = 0;
$debug_Tencoding = 0;

=pod

=head1 NAME

MP3::Info - Manipulate / fetch info from MP3 audio files

=head1 SYNOPSIS

	#!perl -w
	use MP3::Info;
	my $file = 'Pearls_Before_Swine.mp3';
	set_mp3tag($file, 'Pearls Before Swine', q"77's",
		'Sticks and Stones', '1990',
		q"(c) 1990 77's LTD.", 'rock & roll');

	my $tag = get_mp3tag($file) or die "No TAG info";
	$tag->{GENRE} = 'rock';
	set_mp3tag($file, $tag);

	my $info = get_mp3info($file);
	printf "$file length is %d:%d\n", $info->{MM}, $info->{SS};

=cut

{
	my $c = -1;
	# set all lower-case and regular-cased versions of genres as keys
	# with index as value of each key
	%mp3_genres = map {($_, ++$c, lc, $c)} @mp3_genres;

	# do it again for winamp genres
	$c = -1;
	%winamp_genres = map {($_, ++$c, lc, $c)} @winamp_genres;
}

=pod

	my $mp3 = new MP3::Info $file;
	$mp3->title('Perls Before Swine');
	printf "$file length is %s, title is %s\n",
		$mp3->time, $mp3->title;


=head1 DESCRIPTION

=over 4

=item $mp3 = MP3::Info-E<gt>new(FILE)

OOP interface to the rest of the module.  The same keys
available via get_mp3info and get_mp3tag are available
via the returned object (using upper case or lower case;
but note that all-caps "VERSION" will return the module
version, not the MP3 version).

Passing a value to one of the methods will set the value
for that tag in the MP3 file, if applicable.

=cut

sub new {
	my($pack, $file) = @_;

	my $info = get_mp3info($file) or return undef;
	my $tags = get_mp3tag($file) || { map { ($_ => undef) } @v1_tag_names };
	my %self = (
		FILE		=> $file,
		TRY_HARDER	=> 0
	);

	@self{@mp3_info_fields, @v1_tag_names, 'file'} = (
		@{$info}{@mp3_info_fields},
		@{$tags}{@v1_tag_names},
		$file
	);

	return bless \%self, $pack;
}

sub can {
	my $self = shift;
	return $self->SUPER::can(@_) unless ref $self;
	my $name = uc shift;
	return sub { $self->$name(@_) } if exists $self->{$name};
	return undef;
}

sub AUTOLOAD {
	my($self) = @_;
	(my $name = uc $AUTOLOAD) =~ s/^.*://;

	if (exists $self->{$name}) {
		my $sub = exists $v1_tag_fields{$name}
			? sub {
				if (defined $_[1]) {
					$_[0]->{$name} = $_[1];
					set_mp3tag($_[0]->{FILE}, $_[0]);
				}
				return $_[0]->{$name};
			}
			: sub {
				return $_[0]->{$name}
			};

		no strict 'refs';
		*{$AUTOLOAD} = $sub;
		goto &$AUTOLOAD;

	} else {
		carp(sprintf "No method '$name' available in package %s.",
			__PACKAGE__);
	}
}

sub DESTROY {

}


=item use_mp3_utf8([STATUS])

Tells MP3::Info to (or not) return TAG info in UTF-8.
TRUE is 1, FALSE is 0.  Default is TRUE, if available.

Will only be able to turn it on if Encode is available.  ID3v2
tags will be converted to UTF-8 according to the encoding specified
in each tag; ID3v1 tags will be assumed Latin-1 and converted
to UTF-8.

Function returns status (TRUE/FALSE).  If no argument is supplied,
or an unaccepted argument is supplied, function merely returns status.

This function is not exported by default, but may be exported
with the C<:utf8> or C<:all> export tag.

=cut

my $unicode_module = eval { require Encode; require Encode::Guess };
my $UNICODE = use_mp3_utf8($unicode_module ? 1 : 0);

sub use_mp3_utf8 {
	my($val) = @_;
	if ($val == 1) {
		if ($unicode_module) {
			$UNICODE = 1;
			$Encode::Guess::NoUTFAutoGuess = 1;
		}
	} elsif ($val == 0) {
		$UNICODE = 0;
	}
	return $UNICODE;
}

=pod

=item use_winamp_genres()

Puts WinAmp genres into C<@mp3_genres> and C<%mp3_genres>
(adds 68 additional genres to the default list of 80).
This is a separate function because these are non-standard
genres, but they are included because they are widely used.

You can import the data structures with one of:

	use MP3::Info qw(:genres);
	use MP3::Info qw(:DEFAULT :genres);
	use MP3::Info qw(:all);

=cut

sub use_winamp_genres {
	%mp3_genres = %winamp_genres;
	@mp3_genres = @winamp_genres;
	return 1;
}

=pod

=item remove_mp3tag (FILE [, VERSION, BUFFER])

Can remove ID3v1 or ID3v2 tags.  VERSION should be C<1> for ID3v1
(the default), C<2> for ID3v2, and C<ALL> for both.

For ID3v1, removes last 128 bytes from file if those last 128 bytes begin
with the text 'TAG'.  File will be 128 bytes shorter.

For ID3v2, removes ID3v2 tag.  Because an ID3v2 tag is at the
beginning of the file, we rewrite the file after removing the tag data.
The buffer for rewriting the file is 4MB.  BUFFER (in bytes) ca
change the buffer size.

Returns the number of bytes removed, or -1 if no tag removed,
or undef if there is an error.

=cut

sub remove_mp3tag {
	my($file, $version, $buf) = @_;
	my($fh, $return);

	$buf ||= 4096*1024;  # the bigger the faster
	$version ||= 1;

	if (not (defined $file && $file ne '')) {
		$@ = "No file specified";
		return undef;
	}

	if (not -s $file) {
		$@ = "File is empty";
		return undef;
	}

	if (ref $file) { # filehandle passed
		$fh = $file;
	} else {
		if (not open $fh, '+<', $file) {
			$@ = "Can't open $file: $!";
			return undef;
		}
	}

	binmode $fh;

	if ($version eq 1 || $version eq 'ALL') {
		seek $fh, -128, SEEK_END;
		my $tell = tell $fh;
		if (<$fh> =~ /^TAG/) {
			truncate $fh, $tell or carp "Can't truncate '$file': $!";
			$return += 128;
		}
	}

	if ($version eq 2 || $version eq 'ALL') {
		my $v2h = _get_v2head($fh);
		if ($v2h) {
			local $\;
			seek $fh, 0, SEEK_END;
			my $eof = tell $fh;
			my $off = $v2h->{tag_size};

			while ($off < $eof) {
				seek $fh, $off, SEEK_SET;
				read $fh, my($bytes), $buf;
				seek $fh, $off - $v2h->{tag_size}, SEEK_SET;
				print $fh $bytes;
				$off += $buf;
			}

			truncate $fh, $eof - $v2h->{tag_size}
				or carp "Can't truncate '$file': $!";
			$return += $v2h->{tag_size};
		}

		# JRF: I've not written the code to strip ID3v2.4 footers.
		#      Sorry, I'm lazy.
	}

	_close($file, $fh);

	return $return || -1;
}


=pod

=item set_mp3tag (FILE, TITLE, ARTIST, ALBUM, YEAR, COMMENT, GENRE [, TRACKNUM])

=item set_mp3tag (FILE, $HASHREF)

Adds/changes tag information in an MP3 audio file.  Will clobber
any existing information in file.

Fields are TITLE, ARTIST, ALBUM, YEAR, COMMENT, GENRE.  All fields have
a 30-byte limit, except for YEAR, which has a four-byte limit, and GENRE,
which is one byte in the file.  The GENRE passed in the function is a
case-insensitive text string representing a genre found in C<@mp3_genres>.

Will accept either a list of values, or a hashref of the type
returned by C<get_mp3tag>.

If TRACKNUM is present (for ID3v1.1), then the COMMENT field can only be
28 bytes.

ID3v2 support may come eventually.  Note that if you set a tag on a file
with ID3v2, the set tag will be for ID3v1[.1] only, and if you call
C<get_mp3tag> on the file, it will show you the (unchanged) ID3v2 tags,
unless you specify ID3v1.

=cut

sub set_mp3tag {
	my($file, $title, $artist, $album, $year, $comment, $genre, $tracknum) = @_;
	my(%info, $oldfh, $ref, $fh);
	local %v1_tag_fields = %v1_tag_fields;

	# set each to '' if undef
	for ($title, $artist, $album, $year, $comment, $tracknum, $genre,
		(@info{@v1_tag_names}))
		{$_ = defined() ? $_ : ''}

	($ref) = (overload::StrVal($title) =~ /^(?:.*\=)?([^=]*)\((?:[^\(]*)\)$/)
		if ref $title;
	# populate data to hashref if hashref is not passed
	if (!$ref) {
		(@info{@v1_tag_names}) =
			($title, $artist, $album, $year, $comment, $tracknum, $genre);

	# put data from hashref into hashref if hashref is passed
	} elsif ($ref eq 'HASH') {
		%info = %$title;

	# return otherwise
	} else {
		carp(<<'EOT');
Usage: set_mp3tag (FILE, TITLE, ARTIST, ALBUM, YEAR, COMMENT, GENRE [, TRACKNUM])
       set_mp3tag (FILE, $HASHREF)
EOT
		return undef;
	}

	if (not (defined $file && $file ne '')) {
		$@ = "No file specified";
		return undef;
	}

	if (not -s $file) {
		$@ = "File is empty";
		return undef;
	}

	# comment field length 28 if ID3v1.1
	$v1_tag_fields{COMMENT} = 28 if $info{TRACKNUM};


	# only if -w is on
	if ($^W) {
		# warn if fields too long
		foreach my $field (keys %v1_tag_fields) {
			$info{$field} = '' unless defined $info{$field};
			if (length($info{$field}) > $v1_tag_fields{$field}) {
				carp "Data too long for field $field: truncated to " .
					 "$v1_tag_fields{$field}";
			}
		}

		if ($info{GENRE}) {
			carp "Genre `$info{GENRE}' does not exist\n"
				unless exists $mp3_genres{$info{GENRE}};
		}
	}

	if ($info{TRACKNUM}) {
		$info{TRACKNUM} =~ s/^(\d+)\/(\d+)$/$1/;
		unless ($info{TRACKNUM} =~ /^\d+$/ &&
			$info{TRACKNUM} > 0 && $info{TRACKNUM} < 256) {
			carp "Tracknum `$info{TRACKNUM}' must be an integer " .
				"from 1 and 255\n" if $^W;
			$info{TRACKNUM} = '';
		}
	}

	if (ref $file) { # filehandle passed
		$fh = $file;
	} else {
		if (not open $fh, '+<', $file) {
			$@ = "Can't open $file: $!";
			return undef;
		}
	}

	binmode $fh;
	$oldfh = select $fh;
	seek $fh, -128, SEEK_END;
	# go to end of file if no ID3v1 tag, beginning of existing tag if tag present
	seek $fh, (<$fh> =~ /^TAG/ ? -128 : 0), SEEK_END;

	# get genre value
	$info{GENRE} = $info{GENRE} && exists $mp3_genres{$info{GENRE}} ?
		$mp3_genres{$info{GENRE}} : 255;  # some default genre

	local $\;
	# print TAG to file
	if ($info{TRACKNUM}) {
		print pack 'a3a30a30a30a4a28xCC', 'TAG', @info{@v1_tag_names};
	} else {
		print pack 'a3a30a30a30a4a30C', 'TAG', @info{@v1_tag_names[0..4, 6]};
	}

	select $oldfh;

	_close($file, $fh);

	return 1;
}

=pod

=item get_mp3tag (FILE [, VERSION, RAW_V2, APE2])

Returns hash reference containing tag information in MP3 file.  The keys
returned are the same as those supplied for C<set_mp3tag>, except in the
case of RAW_V2 being set.

If VERSION is C<1>, the information is taken from the ID3v1 tag (if present).
If VERSION is C<2>, the information is taken from the ID3v2 tag (if present).
If VERSION is not supplied, or is false, the ID3v1 tag is read if present, and
then, if present, the ID3v2 tag information will override any existing ID3v1
tag info.

If RAW_V2 is C<1>, the raw ID3v2 tag data is returned, without any manipulation
of text encoding.  The key name is the same as the frame ID (ID to name mappings
are in the global %v2_tag_names).

If RAW_V2 is C<2>, the ID3v2 tag data is returned, manipulating for Unicode if
necessary, etc.  It also takes multiple values for a given key (such as comments)
and puts them in an arrayref.

If APE is C<1>, an APE tag will be located before all other tags.

If the ID3v2 version is older than ID3v2.2.0 or newer than ID3v2.4.0, it will
not be read.

Strings returned will be in Latin-1, unless UTF-8 is specified (L<use_mp3_utf8>),
(unless RAW_V2 is C<1>).

Also returns a TAGVERSION key, containing the ID3 version used for the returned
data (if TAGVERSION argument is C<0>, may contain two versions).

=cut

sub get_mp3tag {
	my $file     = shift;
	my $ver      = shift || 0;
	my $raw      = shift || 0;
	my $find_ape = shift || 0;
	my $fh;

	my $has_v1  = 0;
	my $has_v2  = 0;
	my $has_ape = 0;
	my %info    = ();

	# See if a version number was passed. Make sure it's a 1 or a 2
	$ver = !$ver ? 0 : ($ver == 2 || $ver == 1) ? $ver : 0;

	if (!(defined $file && $file ne '')) {
		$@ = "No file specified";
		return undef;
	}

	my $filesize = -s $file;

	if (!$filesize) {
		$@ = "File is empty";
		return undef;
	}

	# filehandle passed
	if (ref $file) {

		$fh = $file;

	} else {

		open($fh, $file) || do {
			$@ = "Can't open $file: $!";
			return undef;
		};
	}

	binmode $fh;

	# Try and find an APE Tag - this is where FooBar2k & others
	# store ReplayGain information
	if ($find_ape) {

		$has_ape = _parse_ape_tag($fh, $filesize, \%info);
	}

	if ($ver < 2) {

		$has_v1 = _get_v1tag($fh, \%info);

		if ($ver == 1 && !$has_v1) {
			_close($file, $fh);
			$@ = "No ID3v1 tag found";
			return undef;
		}
	}

	if ($ver == 2 || $ver == 0) {
		$has_v2 = _get_v2tag($fh, $ver, $raw, \%info);
	}

	if (!$has_v1 && !$has_v2 && !$has_ape) {
		_close($file, $fh);
		$@ = "No ID3 or APE tag found";
		return undef;
	}

	unless ($raw && $ver == 2) {

		# Strip out NULLs unless we want the raw data.
		foreach my $key (keys %info) {

			if (defined $info{$key}) {
				$info{$key} =~ s/\000+.*//g;
				$info{$key} =~ s/\s+$//;
			}
		}

		for (@v1_tag_names) {
			$info{$_} = '' unless defined $info{$_};
		}
	}

	if (keys %info && !defined $info{'GENRE'}) {
		$info{'GENRE'} = '';
	}

	_close($file, $fh);

	return keys %info ? \%info : undef;
}

sub _get_v1tag {
	my ($fh, $info) = @_;

	seek $fh, -128, SEEK_END;
	read($fh, my $tag, 128);

	if (!defined($tag) || $tag !~ /^TAG/) {

		return 0;
	}

	if (substr($tag, -3, 2) =~ /\000[^\000]/) {

		(undef, @{$info}{@v1_tag_names}) =
			(unpack('a3a30a30a30a4a28', $tag),
			ord(substr($tag, -2, 1)),
			$mp3_genres[ord(substr $tag, -1)]);

		$info->{'TAGVERSION'} = 'ID3v1.1';

	} else {

		(undef, @{$info}{@v1_tag_names[0..4, 6]}) =
			(unpack('a3a30a30a30a4a30', $tag),
			$mp3_genres[ord(substr $tag, -1)]);

		$info->{'TAGVERSION'} = 'ID3v1';
	}

	if (!$UNICODE) {
		return 1;
	}

	# Save off the old suspects list, since we add
	# iso-8859-1 below, but don't want that there
	# for possible ID3 v2.x parsing below.
	my $oldSuspects = $Encode::Encoding{'Guess'}->{'Suspects'};

	for my $key (keys %{$info}) {

		next unless $info->{$key};

		# Try and guess the encoding.
		my $value = $info->{$key};
		my $icode = Encode::Guess->guess($value);

		unless (ref($icode)) {

			# Often Latin1 bytes are
			# stuffed into a 1.1 tag.
			Encode::Guess->add_suspects('iso-8859-1');

			while (length($value)) {

				$icode = Encode::Guess->guess($value);

				last if ref($icode);

				# Remove garbage and retry
				# (string is truncated in the
				# middle of a multibyte char?)
				$value =~ s/(.)$//;
			}
		}

		$info->{$key} = Encode::decode(ref($icode) ? $icode->name : 'iso-8859-1', $info->{$key});
	}

	Encode::Guess->set_suspects(keys %{$oldSuspects});

	return 1;
}

sub _parse_v2tag {
	my ($raw_v2, $v2, $info) = @_;

	# Make sure any existing TXXX flags are an array.
	# As we might need to append comments to it below.
	if ($v2->{'TXXX'} && ref($v2->{'TXXX'}) ne 'ARRAY') {

		$v2->{'TXXX'} = [ $v2->{'TXXX'} ];
	}

	# J.River Media Center sticks RG tags in comments.
	# Ugh. Make them look like TXXX tags, which is really what they are.
	if (ref($v2->{'COMM'}) eq 'ARRAY' && grep { /Media Jukebox/ } @{$v2->{'COMM'}}) {

		for my $comment (@{$v2->{'COMM'}}) {

			if ($comment =~ /Media Jukebox/) {

				# we only want one null to lead.
				$comment =~ s/^\000+//g;

				push @{$v2->{'TXXX'}}, "\000$comment";
			}
		}
	}

	my $hash = $raw_v2 == 2 ? { map { ($_, $_) } keys %v2_tag_names } : \%v2_to_v1_names;

	for my $id (keys %{$hash}) {

		next if !exists $v2->{$id};

		if ($id =~ /^UFID?$/) {

			my @ufid_list = split(/\0/, $v2->{$id});

			$info->{$hash->{$id}} = $ufid_list[1] if ($#ufid_list > 0);

		} elsif ($id =~ /^RVA[D2]?$/) {

			# Expand these binary fields. See the ID3 spec for Relative Volume Adjustment.
			if ($id eq 'RVA2') {

				# ID is a text string
				($info->{$hash->{$id}}->{'ID'}, my $rvad) = split /\0/, $v2->{$id};

				my $channel = $rva2_channel_types{ ord(substr($rvad, 0, 1, '')) };

				$info->{$hash->{$id}}->{$channel}->{'REPLAYGAIN_TRACK_GAIN'} = 
					sprintf('%f', _grab_int_16(\$rvad) / 512);

				my $peakBytes = ord(substr($rvad, 0, 1, ''));

				if (int($peakBytes / 8)) {

					$info->{$hash->{$id}}->{$channel}->{'REPLAYGAIN_TRACK_PEAK'} = 
						sprintf('%f', _grab_int_16(\$rvad) / 512);
				}

			} elsif ($id eq 'RVAD' || $id eq 'RVA') {

				my $rvad  = $v2->{$id};
				my $flags = ord(substr($rvad, 0, 1, ''));
				my $desc  = ord(substr($rvad, 0, 1, ''));

				# iTunes appears to be the only program that actually writes
				# out a RVA/RVAD tag. Everyone else punts.
				for my $type (qw(REPLAYGAIN_TRACK_GAIN REPLAYGAIN_TRACK_PEAK)) {

					for my $channel (qw(RIGHT LEFT)) {

						my $val = _grab_uint_16(\$rvad) / 256;

						# iTunes uses a range of -255 to 255
						# to be -100% (silent) to 100% (+6dB)
						if ($val == -255) {
							$val = -96.0;
						} else {
							$val = 20.0 * log(($val+255)/255)/log(10);
						}

						$info->{$hash->{$id}}->{$channel}->{$type} = $flags & 0x01 ? $val : -$val;
					}
				}
			}

		} elsif ($id =~ /^A?PIC$/) {

			my $pic = $v2->{$id};

			# if there is more than one picture, just grab the first one.
			# JRF: Should consider looking for either the thumbnail or the front cover,
			#      rather than just returning the first one.
			#      Possibly also checking that the format is actually understood,
			#      but that's really down to the caller - we can't say whether the
			#      format is understood here.
			if (ref($pic) eq 'ARRAY') {
				$pic = (@$pic)[0];
			}

			use bytes;

			my $valid_pic  = 0;
			my $pic_len    = 0;
			my $pic_format = '';

			# look for ID3 v2.2 picture
			if ($pic && $id eq 'PIC') {

				# look for ID3 v2.2 picture
				my ($encoding, $format, $picture_type, $description) = unpack 'Ca3CZ*', $pic;
				$pic_len = length($description) + 1 + 5;

				# skip extra terminating null if unicode
				if ($encoding) { $pic_len++; }

				if ($pic_len < length($pic)) {
					$valid_pic  = 1;
					$pic_format = $format;
				}

			} elsif ($pic && $id eq 'APIC') {

				# look for ID3 v2.3/2.4 picture
				my ($encoding, $format) = unpack 'C Z*', $pic;

				$pic_len = length($format) + 2;

				if ($pic_len < length($pic)) {

					my ($picture_type, $description) = unpack "x$pic_len C Z*", $pic;

					$pic_len += 1 + length($description) + 1;

					# skip extra terminating null if unicode
					if ($encoding) { $pic_len++; }

					$valid_pic  = 1;
					$pic_format = $format;
				}
			}

			# Proceed if we have a valid picture.
			if ($valid_pic && $pic_format) {

				my ($data) = unpack("x$pic_len A*", $pic);

				if (length($data) && $pic_format) {

					$info->{$hash->{$id}} = {
						'DATA'   => $data,
						'FORMAT' => $pic_format,
					}
				}
			}

		} else {
			my $data1 = $v2->{$id};

			$data1 = [ $data1 ] if ref($data1) ne 'ARRAY';

			for my $data (@$data1) {
				# TODO : this should only be done for certain frames;
				# using RAW still gives you access, but we should be smarter
				# about how individual frame types are handled.  it's not
				# like the list is infinitely long.
				$data =~ s/^(.)//; # strip first char (text encoding)
				my $encoding = $1;
				my $desc;

				# Comments & Unsyncronized Lyrics have the same format.
				if ($id =~ /^(COM[M ]?|USLT)$/) { # space for iTunes brokenness

					$data =~ s/^(?:...)//;		# strip language
				}

				if ($UNICODE) {

					if ($encoding eq "\001" || $encoding eq "\002") {  # UTF-16, UTF-16BE
						# text fields can be null-separated lists;
						# UTF-16 therefore needs special care
						#
						# foobar2000 encodes tags in UTF-16LE
						# (which is apparently illegal)
						# Encode dies on a bad BOM, so it is
						# probably wise to wrap it in an eval
						# anyway
						$data = eval { Encode::decode('utf16', $data) } || Encode::decode('utf16le', $data);

					} elsif ($encoding eq "\003") { # UTF-8

						# make sure string is UTF8, and set flag appropriately
						$data = Encode::decode('utf8', $data);

					} elsif ($encoding eq "\000") {

						# Only guess if it's not ascii.
						if ($data && $data !~ /^[\x00-\x7F]+$/) {

							# Try and guess the encoding, otherwise just use latin1
							my $dec = Encode::Guess->guess($data);

							if (ref $dec) {
								$data = $dec->decode($data);
							} else {
								# Best try
								$data = Encode::decode('iso-8859-1', $data);
							}
						}
					}

				} else {

					# If the string starts with an
					# UTF-16 little endian BOM, use a hack to
					# convert to ASCII per best-effort
					my $pat;
					if ($data =~ s/^\xFF\xFE//) {
						$pat = 'v';
					} elsif ($data =~ s/^\xFE\xFF//) {
						$pat = 'n';
					}

					if ($pat) {
						$data = pack 'C*', map {
							(chr =~ /[[:ascii:]]/ && chr =~ /[[:print:]]/)
								? $_
								: ord('?')
						} unpack "$pat*", $data;
					}
				}

				# We do this after decoding so we could be certain we're dealing
				# with 8-bit text.
				if ($id =~ /^(COM[M ]?|USLT)$/) { # space for iTunes brokenness

					$data =~ s/^(.*?)\000//;	# strip up to first NULL(s),
									# for sub-comments (TODO:
									# handle all comment data)
					$desc = $1;

					if ($encoding eq "\001" || $encoding eq "\002") {

						$data =~ s/^\x{feff}//;
					}

				} elsif ($id =~ /^TCON?$/) {

					my ($index, $name);

					# Turn multiple nulls into a single.
					$data =~ s/\000+/\000/g;

					# Handle the ID3v2.x spec - 
					#
					# just an index number, possibly
					# paren enclosed - referer to the v1 genres.
					if ($data =~ /^ \(? (\d+) \)?\000?$/sx) {

						$index = $1;

					# Paren enclosed index with refinement.
					# (4)Eurodisco
					} elsif ($data =~ /^ \( (\d+) \)\000? ([^\(].+)$/x) {

						($index, $name) = ($1, $2);

					# List of indexes: (37)(38)
					} elsif ($data =~ /^ \( (\d+) \)\000?/x) {

						my @genres = ();

						while ($data =~ s/^ \( (\d+) \)//x) {

							# The indexes might have a refinement
							# not sure why one wouldn't just use
							# the proper genre in the first place..
							if ($data =~ s/^ ( [^\(]\D+ ) ( \000 | \( | \Z)/$2/x) {

								push @genres, $1;

							} else {

								push @genres, $mp3_genres[$1];
							}
						}

						$data = \@genres;

					} elsif ($data =~ /^[^\000]+\000/) {

						# name genres separated by nulls.
						$data = [ split /\000/, $data ];
					}

					# Text based genres will fall through.
					if ($name && $name ne "\000") {
						$data = $name;
					} elsif (defined $index) {
						$data = $mp3_genres[$index];
					}

					# Collapse single genres down, as we may have another tag.
					if ($data && ref($data) eq 'ARRAY' && scalar @$data == 1) {

						$data = $data->[0];
					}
				}

				if ($raw_v2 == 2 && $desc) {

					$data = { $desc => $data };

				} elsif ($desc && $desc =~ /^iTun/) {

					# leave iTunes tags alone.
					$data = join(' ', $desc, $data);
				}

				if ($raw_v2 == 2 && exists $info->{$hash->{$id}}) {

					if (ref $info->{$hash->{$id}} eq 'ARRAY') {
						push @{$info->{$hash->{$id}}}, $data;
					} else {
						$info->{$hash->{$id}} = [ $info->{$hash->{$id}}, $data ];
					}

				} else {

					# User defined frame
					if ($id eq 'TXXX') {

						my ($key, $val) = split(/\0/, $data);

						# Some programs - such as FB2K leave a UTF-16 BOM on the value
						if ($encoding eq "\001" || $encoding eq "\002") {

							$val =~ s/^\x{feff}//;
						}

						$info->{uc($key)} = $val;

					} elsif ($id eq 'PRIV') {

						my ($key, $val) = split(/\0/, $data);
						$info->{uc($key)} = unpack('v', $val);

					} else {

						my $key = $hash->{$id};

						# If we have multiple values
						# for the same key - turn them
						# into an array ref.
						if ($info->{$key} && !ref($info->{$key})) {

							my $old = delete $info->{$key};

							@{$info->{$key}} = ($old, $data);

						} elsif (ref($info->{$key}) eq 'ARRAY') {

							push @{$info->{$key}}, $data;

						} else {

							$info->{$key} = $data;
						}
					}
				}
			}
		}
	}
}

sub _get_v2tag {
	my ($fh, $ver, $raw, $info) = @_;
	my $eof;
	my $gotanyv2 = 0;

	# First we need to check the end of the file for any footer

	seek $fh, -128, SEEK_END;
	$eof = (tell $fh) + 128;

	# go to end of file if no ID3v1 tag, beginning of existing tag if tag present
	if (<$fh> =~ /^TAG/) {
		$eof -= 128;
	}

	seek $fh, $eof, SEEK_SET;
	# print STDERR "Checking for footer at $eof\n";

	if (my $v2f = _get_v2foot($fh)) {
		$eof -= $v2f->{tag_size};
		# We have a ID3v2.4 footer. Must read it.
		$gotanyv2 |= (_get_v2tagdata($fh, $ver, $raw, $info, $eof) ? 2 : 0);
	}

	# Now read any ID3v2 header
	$gotanyv2 |= (_get_v2tagdata($fh, $ver, $raw, $info, undef) ? 1 : 0);

	# Because we've merged the entries it makes sense to trim any duplicated
	# values - for example if there's a footer and a header that contain the same
	# data then this results in every entry being an array containing two
	# identical values.
	for my $name (keys %{$info})
	{
	  # Note: We must not sort these elements to do the comparison because that
	  #       changes the order in which they are claimed to appear. Whilst this
	  #       probably isn't important, it may matter for default display - for
	  #       example a lyric should be shown by default with the first entry
	  #       in the tag in the case where the user has not specified a language
	  #       preference. If we sorted the array it would destroy that order.
	  # This is a longwinded way of checking for duplicates and only writing the
	  # first element - we check the array for duplicates and clear all subsequent
	  # entries which are duplicates of earlier ones.
	  if (ref $info->{$name} eq 'ARRAY')
	  {
	    my @array = ();
	    my ($i, $o);
	    my @chk = @{$info->{$name}};
	    for $i ( 0..$#chk )
	    {
	      my $ielement = $chk[$i];
	      if (defined $chk[$i])
	      {
	        for $o ( ($i+1)..$#chk )
	        {
	          $chk[$o] = undef if (defined $ielement && defined $o && defined $chk[$o] && $ielement eq $chk[$o]);
	        }
	        push @array, $chk[$i];
	      }
	    }
	    # We may have reduced the array to a single element. If so, just assign
	    # a regular scalar instead of the array.
	    if ($#array == 0)
	    { 
	      $info->{$name} = $array[0];
	    }
	    else
	    { 
	      $info->{$name} = \@array;
	    }
	  }
	}

	return $gotanyv2;
}

# $has_v2 = &_get_v2tagdata($filehandle, $ver, $raw, $info, $startinfile);
# $info is a hash reference which will be updated with the new ID3v2 details
# if the updated bit is set, and set to the new details if the updated bit
# is clear.
# If undefined, $startinfile will be treated as 0 (see _get_v2head).
# $v2h is a reference to a hash of the frames present within the tag.
# Any frames which are repeated within the tag (eg USLT with different
# languages) will be supplied as an array rather than a scalar. All client
# code needs to be aware that any frame may be duplicated.
sub _get_v2tagdata {
	my($fh, $ver, $raw, $info, $start) = @_;
	my($off, $end, $myseek, $v2, $v2h, $hlen, $num, $wholetag);

	$v2 = {};
	$v2h = _get_v2head($fh, $start) or return 0;

	if ($v2h->{major_version} < 2) {
		carp "This is $v2h->{version}; " .
		     "ID3v2 versions older than ID3v2.2.0 not supported\n"
		     if $^W;
		return 0;
	}

	# use syncsafe bytes if using version 2.4
	my $id3v2_4_frame_size_broken = 0;
	my $bytesize = ($v2h->{major_version} > 3) ? 128 : 256;

	# alas, that's what the spec says, but iTunes and others don't syncsafe
	# the length, which breaks MP3 files with v2.4 tags longer than 128 bytes,
	# like every image file.
	# Because we should not break the spec conformant files due to
	# spec-inconformant programs, we first try the correct form and if the
	# data looks wrong we revert to broken behaviour.

	if ($v2h->{major_version} == 2) {
		$hlen = 6;
		$num = 3;
	} else {
		$hlen = 10;
		$num = 4;
	}

	$off = $v2h->{ext_header_size} + 10;
	$end = $v2h->{tag_size} + 10; # should we read in the footer too?

	# JRF: If the format was ID3v2.2 and the compression bit was set, then we can't
	#      actually read the content because there are no defined compression schemes
	#      for ID3v2.2. Perform no more processing, and return failure because we
	#      cannot read anything.
	return 0 if ($v2h->{major_version} == 2 && $v2h->{compression});

	# JRF: If the update flag is set then the input data is the same as that which was
	#      passed in. ID3v2.4 section 3.2.
	if ($v2h->{update}) {
		$v2 = $info;
	}

	seek $fh, $v2h->{offset}, SEEK_SET;
	read $fh, $wholetag, $end;

        # JRF: The discrepency between ID3v2.3 and ID3v2.4 is that :
        #          2.3: unsync flag indicates that unsync is used on the entire tag
        #          2.4: unsync flag indicates that all frames have the unsync bit set
        #      In 2.4 this means that the size of the frames which have the unsync bit
        #      set will be the unsync'd size (section 4. in the ID3v2.4.0 structure
        #      specification).
        #      This means that when processing 2.4 files we should perform all the
        #      unsynchronisation processing at the frame level, not the tag level.
        #      The tag unsync bit is redundant (IMO).
        if ($v2h->{major_version} == 4) {
		$v2h->{unsync} = 0
        }

	$wholetag =~ s/\xFF\x00/\xFF/gs if $v2h->{unsync};

	# JRF: If we /knew/ there would be something special in the tag which meant
	#      that the ID3v2.4 frame size was broken we could check it here. If,
	#      for example, the iTunes files had the word 'iTunes' somewhere in the
	#      tag and we knew that it was broken for versions below 3.145 (which is
	#      a number I just picked out of the air), then we could do something like this :
	# if ($v2h->{major_version} == 4) &&
	#    $wholetag =~ /iTunes ([0-9]+\.[0-9]+)/ &&
	#    $1 < 3.145)
	# {
	#   $id3v2_4_frame_size_broken = 1;
	# }
	# However I have not included this because I don't have examples of broken
	# files - and in any case couldn't guarentee I'd get it right.

	$myseek = sub {
		my $bytes = substr($wholetag, $off, $hlen);

		# iTunes is stupid and sticks ID3v2.2 3 byte frames in a
		# ID3v2.3 or 2.4 header. Ignore tags with a space in them.
		if ($bytes !~ /^([A-Z0-9 ]{$num})/) {
			return;
		}

		my ($id, $size) = ($1, $hlen);
		my @bytes = reverse unpack "C$num", substr($bytes, $num, $num);

		for my $i (0 .. ($num - 1)) {
			$size += $bytes[$i] * $bytesize ** $i;
		}

		# JRF: Now provide the fall back for the broken ID3v2.4 frame size
		#      (which will persist for subsequent frames if detected).

		#      Part 1: If the frame size cannot be valid according to the
		#              specification (or if it would be larger than the tag
		#              size allows).
		if ($v2h->{major_version}==4 && 
		    $id3v2_4_frame_size_broken == 0 && # we haven't detected brokenness yet
		    ((($bytes[0] | $bytes[1] | $bytes[2] | $bytes[3]) & 0x80) != 0 || # 0-bits set in size
		     $off + $size > $end)  # frame size would excede the tag end
		    )
		{
		  # The frame is definately not correct for the specification, so drop to
		  # broken frame size system instead.
		  $bytesize = 128;
		  $size -= $hlen; # hlen has alread been added, so take that off again
		  $size = (($size & 0x0000007f)) | 
		          (($size & 0x00003f80)<<1) |
		          (($size & 0x001fc000)<<2) |
		          (($size & 0x0fe00000)<<3); # convert spec to non-spec sizes

		  $size += $hlen; # and re-add header len so that the entire frame's size is known

		  $id3v2_4_frame_size_broken = 1;

		  print "Frame size cannot be valid ID3v2.4 (part 1); reverting to broken behaviour\n" if ($debug_24);

		}

		#      Part 2: If the frame size would result in the following frame being
		#              invalid.
		if ($v2h->{major_version}==4 && 
		    $id3v2_4_frame_size_broken == 0 && # we haven't detected brokenness yet
		    $size > 0x80+$hlen && # ignore frames that are too short to ever be wrong
		    $off + $size < $end)
		{

		  print "Frame size might not be valid ID3v2.4 (part 2); checking for following frame validity\n" if ($debug_24);

		  my $morebytes = substr($wholetag, $off+$size, 4);

		  if (! ($morebytes =~ /^([A-Z0-9]{4})/ || $morebytes =~ /^\x00{4}/) ) {

		    # The next tag cannot be valid because its name is wrong, which means that
		    # either the size must be invalid or the next frame truely is broken.
		    # Either way, we can try to reduce the size to see.
		    my $retrysize;

		    print "  following frame isn't valid using spec\n" if ($debug_24);

		    $retrysize = $size - $hlen; # remove already added header length
		    $retrysize = (($retrysize & 0x0000007f)) | 
		                 (($retrysize & 0x00003f80)<<1) |
		                 (($retrysize & 0x001fc000)<<2) |
		                 (($retrysize & 0x0fe00000)<<3); # convert spec to non-spec sizes

		    $retrysize += $hlen; # and re-add header len so that the entire frame's size is known

		    if (length($wholetag) >= ($off+$retrysize+4)) {

		    	$morebytes = substr($wholetag, $off+$retrysize, 4);

		    } else {

		    	$morebytes = '';
		    }

		    if (! ($morebytes =~ /^([A-Z0-9]{4})/ ||
		           $morebytes =~ /^\x00{4}/ ||
		           $off + $retrysize > $end) )
		    {
		      # With the retry at the smaller size, the following frame still isn't valid
		      # so the only thing we can assume is that this frame is just broken beyond
		      # repair. Give up right now - there's no way we can recover.
		      print "  and isn't valid using broken-spec support; giving up\n" if ($debug_24);
		      return;
		    }
		    
		    print "  but is fine with broken-spec support; reverting to broken behaviour\n" if ($debug_24);
		    
		    # We're happy that the non-spec size looks valid to lead us to the next frame.
		    # We might be wrong, generating false-positives, but that's really what you
		    # get for trying to handle applications that don't handle the spec properly -
		    # use something that isn't broken.
		    # (this is a copy of the recovery code in part 1)
		    $size = $retrysize;
		    $bytesize = 128;
		    $id3v2_4_frame_size_broken = 1;

		  } else {

		    print "  looks like valid following frame; keeping spec behaviour\n" if ($debug_24);

		  }
		}

		my $flags = {};

		# JRF: was > 3, but that's not true; future versions may be incompatible
		if ($v2h->{major_version} == 4) {
			my @bits = split //, unpack 'B16', substr($bytes, 8, 2);
			$flags->{frame_zlib}         = $bits[12]; # JRF: need to know about compressed
			$flags->{frame_encrypt}      = $bits[13]; # JRF: ... and encrypt
			$flags->{frame_unsync}       = $bits[14];
			$flags->{data_len_indicator} = $bits[15];
		}

		# JRF: version 3 was in a different order
		elsif ($v2h->{major_version} == 3) {
			my @bits = split //, unpack 'B16', substr($bytes, 8, 2);
			$flags->{frame_zlib}         = $bits[8]; # JRF: need to know about compressed
			$flags->{data_len_indicator} = $bits[8]; # JRF:   and compression implies the DLI is present
			$flags->{frame_encrypt}      = $bits[9]; # JRF: ... and encrypt
		}

		return ($id, $size, $flags);
	};

	while ($off < $end) {
		my ($id, $size, $flags) = &$myseek or last;
		my ($hlenextra) = 0;

		# NOTE: Wrong; the encrypt comes after the DLI. maybe.
		# JRF: Encrypted frames need to be decrypted first
		if ($flags->{frame_encrypt}) {

			my ($encypt_method) = substr($wholetag, $off+$hlen+$hlenextra, 1);

			$hlenextra++;

			# We don't actually know how to decrypt anything, so we'll just skip the entire frame.
			$off += $size;

			next;
		}

		my $bytes = substr($wholetag, $off+$hlen+$hlenextra, $size-$hlen-$hlenextra);

		my $data_len;
		if ($flags->{data_len_indicator}) {
			$data_len = 0;

			my @data_len_bytes = reverse unpack 'C4', substr($bytes, 0, 4);

			$bytes = substr($bytes, 4);

		        for my $i (0..3) {
				$data_len += $data_len_bytes[$i] * 128 ** $i;
		        }
		}

		print "got $id, length " . length($bytes) . " frameunsync: ".$flags->{frame_unsync}." tag unsync: ".$v2h->{unsync} ."\n" if ($debug_24);

		# perform frame-level unsync if needed (skip if already done for whole tag)
		$bytes =~ s/\xFF\x00/\xFF/gs if $flags->{frame_unsync} && !$v2h->{unsync};

		# JRF: Decompress now if compressed.
		#      (FIXME: Not implemented yet)

		# if we know the data length, sanity check it now.
		if ($flags->{data_len_indicator} && defined $data_len) {
		        carp("Size mismatch on $id\n") unless $data_len == length($bytes);
		}

		# JRF: Apply small sanity check on text elements - they must end with :
		#        a 0 if they are ISO8859-1
		#        0,0 if they are unicode
		# (This is handy because it can be caught by the 'duplicate elements'
		# in array checks)
		# There is a question in my mind whether I should be doing this here - it
		# is introducing knowledge of frame content format into the raw reader
		# which is not a good idea. But if the frames are broken we at least
		# recover.
		if (($v2h->{major_version} == 3 || $v2h->{major_version} == 4) && $id =~ /^T/) {

			my $encoding = substr($bytes, 0, 1);
		  
			# Both these cases are candidates for providing some warning, I feel.
			# ISO-8859-1 or UTF-8 $bytes
			if (($encoding eq "\x00" || $encoding eq "\x03") && $bytes !~ /\x00$/) { 

				$bytes .= "\x00"; 
				print "Text frame $id has malformed ISO-8859-1/UTF-8 content\n" if ($debug_Tencoding);

			# # UTF-16, UTF-16BE
			} elsif ( ($encoding eq "\x01" || $encoding eq "\x02") && $bytes !~ /\x00\x00$/) { 

				$bytes .= "\x00\x00";
				print "Text frame $id has malformed UTF-16/UTF-16BE content\n" if ($debug_Tencoding);

			} else {

				# Other encodings cannot be fixed up (we don't know how 'cos they're not defined).
			}
		}

		if (exists $v2->{$id}) {

			if (ref $v2->{$id} eq 'ARRAY') {
				push @{$v2->{$id}}, $bytes;
			} else {
				$v2->{$id} = [$v2->{$id}, $bytes];
			}

		} else {

			$v2->{$id} = $bytes;
		}

		$off += $size;
	}

	if (($ver == 0 || $ver == 2) && $v2) {

		if ($raw == 1 && $ver == 2) {

			%$info = %$v2;

			$info->{'TAGVERSION'} = $v2h->{'version'};

		} else {

			_parse_v2tag($raw, $v2, $info);

			if ($ver == 0 && $info->{'TAGVERSION'}) {
				$info->{'TAGVERSION'} .= ' / ' . $v2h->{'version'};
			} else {
				$info->{'TAGVERSION'} = $v2h->{'version'};
			}
		}
	}

	return 1;
}

=pod

=item get_mp3info (FILE)

Returns hash reference containing file information for MP3 file.
This data cannot be changed.  Returned data:

	VERSION		MPEG audio version (1, 2, 2.5)
	LAYER		MPEG layer description (1, 2, 3)
	STEREO		boolean for audio is in stereo

	VBR		boolean for variable bitrate
	BITRATE		bitrate in kbps (average for VBR files)
	FREQUENCY	frequency in kHz
	SIZE		bytes in audio stream
	OFFSET		bytes offset that stream begins

	SECS		total seconds
	MM		minutes
	SS		leftover seconds
	MS		leftover milliseconds
	TIME		time in MM:SS

	COPYRIGHT	boolean for audio is copyrighted
	PADDING		boolean for MP3 frames are padded
	MODE		channel mode (0 = stereo, 1 = joint stereo,
			2 = dual channel, 3 = single channel)
	FRAMES		approximate number of frames
	FRAME_LENGTH	approximate length of a frame
	VBR_SCALE	VBR scale from VBR header

On error, returns nothing and sets C<$@>.

=cut

sub get_mp3info {
	my($file) = @_;
	my($off, $byte, $eof, $h, $tot, $fh);

	if (not (defined $file && $file ne '')) {
		$@ = "No file specified";
		return undef;
	}

	if (not -s $file) {
		$@ = "File is empty";
		return undef;
	}

	if (ref $file) { # filehandle passed
		$fh = $file;
	} else {
		if (not open $fh, '<', $file) {
			$@ = "Can't open $file: $!";
			return undef;
		}
	}

	$off = 0;
	$tot = 8192;

	# Let the caller change how far we seek in looking for a header.
	if ($try_harder) {
		$tot *= $try_harder;
	}

	binmode $fh;
	seek $fh, $off, SEEK_SET;
	read $fh, $byte, 4;

	if (my $v2h = _get_v2head($fh)) {
		$tot += $off += $v2h->{tag_size};
		seek $fh, $off, SEEK_SET;
		read $fh, $byte, 4;
	}

	$h = _get_head($byte);
	my $is_mp3 = _is_mp3($h); 

	# the head wasn't where we were expecting it.. dig deeper.
	unless ($is_mp3) {

		# do only one read - it's _much_ faster
		$off++;
		seek $fh, $off, SEEK_SET;
		read $fh, $byte, $tot;
		 
		my $i;
		 
		# now walk the bytes looking for the head
		for ($i = 0; $i < $tot; $i++) {

			last if ($tot - $i) < 4;
		 
			my $head = substr($byte, $i, 4) || last;
			 
			next if (ord($head) != 0xff);
			 
			$h = _get_head($head);
			$is_mp3 = _is_mp3($h);
			last if $is_mp3;
		}
		 
		# adjust where we are for _get_vbr()
		$off += $i;

		if ($off > $tot && !$try_harder) {
			_close($file, $fh);
			$@ = "Couldn't find MP3 header (perhaps set " .
			     '$MP3::Info::try_harder and retry)';
			return undef;
		}
	}

	my $vbr = _get_vbr($fh, $h, \$off);

	seek $fh, 0, SEEK_END;
	$eof = tell $fh;
	seek $fh, -128, SEEK_END;
	$eof -= 128 if <$fh> =~ /^TAG/ ? 1 : 0;

	# JRF: Check for an ID3v2.4 footer and if present, remove it from
	#      the size.
	seek($fh, $eof, SEEK_SET);

	if (my $v2f = _get_v2foot($fh)) {
		$eof -= $v2f->{tag_size};
	}

	_close($file, $fh);

	$h->{size} = $eof - $off;
	$h->{offset} = $off;

	return _get_info($h, $vbr);
}

sub _get_info {
	my($h, $vbr) = @_;
	my $i;

	# No bitrate or sample rate? Something's wrong.
	unless ($h->{bitrate} && $h->{fs}) {
		return {};
	}

	$i->{VERSION}	= $h->{IDR} == 2 ? 2 : $h->{IDR} == 3 ? 1 :
				$h->{IDR} == 0 ? 2.5 : 0;
	$i->{LAYER}	= 4 - $h->{layer};
	$i->{VBR}	= defined $vbr ? 1 : 0;

	$i->{COPYRIGHT}	= $h->{copyright} ? 1 : 0;
	$i->{PADDING}	= $h->{padding_bit} ? 1 : 0;
	$i->{STEREO}	= $h->{mode} == 3 ? 0 : 1;
	$i->{MODE}	= $h->{mode};

	$i->{SIZE}	= $vbr && $vbr->{bytes} ? $vbr->{bytes} : $h->{size};
	$i->{OFFSET}	= $h->{offset};

	my $mfs		= $h->{fs} / ($h->{ID} ? 144000 : 72000);
	$i->{FRAMES}	= int($vbr && $vbr->{frames}
				? $vbr->{frames}
				: $i->{SIZE} / ($h->{bitrate} / $mfs)
			  );

	if ($vbr) {
		$i->{VBR_SCALE}	= $vbr->{scale} if $vbr->{scale};
		$h->{bitrate}	= $i->{SIZE} / $i->{FRAMES} * $mfs;
		if (not $h->{bitrate}) {
			$@ = "Couldn't determine VBR bitrate";
			return undef;
		}
	}

	$h->{'length'}	= ($i->{SIZE} * 8) / $h->{bitrate} / 10;
	$i->{SECS}	= $h->{'length'} / 100;
	$i->{MM}	= int $i->{SECS} / 60;
	$i->{SS}	= int $i->{SECS} % 60;
	$i->{MS}	= (($i->{SECS} - ($i->{MM} * 60) - $i->{SS}) * 1000);
#	$i->{LF}	= ($i->{MS} / 1000) * ($i->{FRAMES} / $i->{SECS});
#	int($i->{MS} / 100 * 75);  # is this right?
	$i->{TIME}	= sprintf "%.2d:%.2d", @{$i}{'MM', 'SS'};

	$i->{BITRATE}		= int $h->{bitrate};
	# should we just return if ! FRAMES?
	$i->{FRAME_LENGTH}	= int($h->{size} / $i->{FRAMES}) if $i->{FRAMES};
	$i->{FREQUENCY}		= $frequency_tbl[3 * $h->{IDR} + $h->{sampling_freq}];

	return $i;
}

sub _get_head {
	my($byte) = @_;
	my($bytes, $h);

	$bytes = _unpack_head($byte);
	@$h{qw(IDR ID layer protection_bit
		bitrate_index sampling_freq padding_bit private_bit
		mode mode_extension copyright original
		emphasis version_index bytes)} = (
		($bytes>>19)&3, ($bytes>>19)&1, ($bytes>>17)&3, ($bytes>>16)&1,
		($bytes>>12)&15, ($bytes>>10)&3, ($bytes>>9)&1, ($bytes>>8)&1,
		($bytes>>6)&3, ($bytes>>4)&3, ($bytes>>3)&1, ($bytes>>2)&1,
		$bytes&3, ($bytes>>19)&3, $bytes
	);

	$h->{bitrate} = $t_bitrate[$h->{ID}][3 - $h->{layer}][$h->{bitrate_index}];
	$h->{fs} = $t_sampling_freq[$h->{IDR}][$h->{sampling_freq}];

	return $h;
}

sub _is_mp3 {
	my $h = $_[0] or return undef;
	return ! (	# all below must be false
		 $h->{bitrate_index} == 0
			||
		 $h->{version_index} == 1
			||
		($h->{bytes} & 0xFFE00000) != 0xFFE00000
			||
		!$h->{fs}
			||
		!$h->{bitrate}
			||
		 $h->{bitrate_index} == 15
			||
		!$h->{layer}
			||
		 $h->{sampling_freq} == 3
			||
		 $h->{emphasis} == 2
			||
		!$h->{bitrate_index}
			||
		($h->{bytes} & 0xFFFF0000) == 0xFFFE0000
			||
		($h->{ID} == 1 && $h->{layer} == 3 && $h->{protection_bit} == 1)
		# mode extension should only be applicable when mode = 1
		# however, failing just becuase mode extension is used when unneeded is a bit strict
		#	||
		#($h->{mode_extension} != 0 && $h->{mode} != 1)
	);
}

sub _vbr_seek {
	my $fh    = shift;
	my $off   = shift;
	my $bytes = shift;
	my $n     = shift || 4;

	seek $fh, $$off, SEEK_SET;
	read $fh, $$bytes, $n;

	$$off += $n;
}

sub _get_vbr {
	my($fh, $h, $roff) = @_;
	my($off, $bytes, @bytes, %vbr);

	$off = $$roff;

	$off += 4;

	if ($h->{ID}) {	# MPEG1
		$off += $h->{mode} == 3 ? 17 : 32;
	} else {	# MPEG2
		$off += $h->{mode} == 3 ? 9 : 17;
	}

	_vbr_seek($fh, \$off, \$bytes);
	return unless $bytes eq 'Xing';

	_vbr_seek($fh, \$off, \$bytes);
	$vbr{flags} = _unpack_head($bytes);

	if ($vbr{flags} & 1) {
		_vbr_seek($fh, \$off, \$bytes);
		$vbr{frames} = _unpack_head($bytes);
	}

	if ($vbr{flags} & 2) {
		_vbr_seek($fh, \$off, \$bytes);
		$vbr{bytes} = _unpack_head($bytes);
	}

	if ($vbr{flags} & 4) {
		_vbr_seek($fh, \$off, \$bytes, 100);
# Not used right now ...
#		$vbr{toc} = _unpack_head($bytes);
	}

	if ($vbr{flags} & 8) { # (quality ind., 0=best 100=worst)
		_vbr_seek($fh, \$off, \$bytes);
		$vbr{scale} = _unpack_head($bytes);
	} else {
		$vbr{scale} = -1;
	}

	$$roff = $off;
	return \%vbr;
}

# _get_v2head(file handle, start offset in file);
# The start offset can be used to check ID3v2 headers anywhere
# in the MP3 (eg for 'update' frames).
sub _get_v2head {
	my $fh = $_[0] or return;
	my($v2h, $bytes, @bytes);
	$v2h->{offset} = $_[1] || 0;

	# check first three bytes for 'ID3'
	seek $fh, $v2h->{offset}, SEEK_SET;
	read $fh, $bytes, 3;

	# (Note: Footers are dealt with in v2foot)
	if ($v2h->{offset} == 0) {

		# JRF: Only check for special headers if we're at the start of the file.
		if ($bytes eq 'RIF' || $bytes eq 'FOR') {
			_find_id3_chunk($fh, $bytes) or return;
			$v2h->{offset} = tell $fh;
			read $fh, $bytes, 3;
		}
	}

	return unless $bytes eq 'ID3';

	# get version
	read $fh, $bytes, 2;
	$v2h->{version} = sprintf "ID3v2.%d.%d",
		@$v2h{qw[major_version minor_version]} =
			unpack 'c2', $bytes;

	# get flags
	read $fh, $bytes, 1;
	my @bits = split //, unpack 'b8', $bytes;
	if ($v2h->{major_version} == 2) {
		$v2h->{unsync}       = $bits[7];
		$v2h->{compression}  = $bits[6]; # Should be ignored - no defined form
		$v2h->{ext_header}   = 0;
		$v2h->{experimental} = 0;
	} else {
		$v2h->{unsync}       = $bits[7];
		$v2h->{ext_header}   = $bits[6];
		$v2h->{experimental} = $bits[5];
		$v2h->{footer}       = $bits[4] if $v2h->{major_version} == 4;
	}

	# get ID3v2 tag length from bytes 7-10
	$v2h->{tag_size} = 10;	# include ID3v2 header size
	$v2h->{tag_size} += 10 if $v2h->{footer};
	read $fh, $bytes, 4;
	@bytes = reverse unpack 'C4', $bytes;
	foreach my $i (0 .. 3) {
		# whoaaaaaa nellllllyyyyyy!
		$v2h->{tag_size} += $bytes[$i] * 128 ** $i;
	}

	# JRF: I think this is done wrongly - this should be part of the main frame,
	#      and therefore under ID3v2.3 it's subject to unsynchronisation
	#      (ID3v2.3, section 3.2).
	#      FIXME.

	# get extended header size (2.3/2.4 only)
	$v2h->{ext_header_size} = 0;
	if ($v2h->{ext_header}) {
		read $fh, $bytes, 4;
		@bytes = reverse unpack 'C4', $bytes;

		# use syncsafe bytes if using version 2.4
		my $bytesize = ($v2h->{major_version} > 3) ? 128 : 256;
		for my $i (0..3) {
			$v2h->{ext_header_size} += $bytes[$i] * $bytesize ** $i;
		}

		# Read the extended header
		my $ext_data;
		if ($v2h->{major_version} == 3) {
			# On ID3v2.3 the extended header size excludes the whole header
			read $fh, $bytes, 6 + $v2h->{ext_header_size};
			my @bits = split //, unpack 'b16', substr $bytes, 0, 2;
			$v2h->{crc_present}      = $bits[15];
			my $padding_size;
			for my $i (0..3) {
				$padding_size += $bytes[2 + $i] * $bytesize ** $i;
			}
			$ext_data = substr $bytes, 6, $v2h->{ext_header_size} - $padding_size;
		}
		elsif ($v2h->{major_version} == 4) {
			# On ID3v2.4, the extended header size includes the whole header
			read $fh, $bytes, $v2h->{ext_header_size} - 4;
			my @bits = split //, unpack 'b8', substr $bytes, 5, 1;
			$v2h->{update}           = $bits[6];
			$v2h->{crc_present}      = $bits[5];
			$v2h->{tag_restrictions} = $bits[4];
			$ext_data = substr $bytes, 2, $v2h->{ext_header_size} - 6;
		}

		# JRF: I'm not actually working out what the CRC or the tag
		#      restrictions are just yet. It doesn't seem to be
		#      all that worthwhile.
		# However, if this is implemented...
		#    Under ID3v2.3, the CRC is not sync-safe (4 bytes).
		#    Under ID3v2.4, the CRC is sync-safe (5 bytes, excluding the flag data
		#      length)
		#    Under ID3v2.4, every flag byte that's set is given a flag data byte
		#      in the extended data area, the first byte of which is the size of
		#      the flag data (see ID3v2.4 section 3.2).
	}

	return $v2h;
}

# JRF: We assume that we have seeked to the expected EOF (ie start of the ID3v1 tag)
#      The 'offset' value will hold the start of the ID3v1 header (NOT the footer)
#      The 'tag_size' value will hold the entire tag size, including the footer.
sub _get_v2foot {
	my $fh = $_[0] or return;
	my($v2h, $bytes, @bytes);
	my $eof;

	$eof = tell $fh;

	# check first three bytes for 'ID3'
	seek $fh, $eof-10, SEEK_SET; # back 10 bytes for footer
	read $fh, $bytes, 3;

	return undef unless $bytes eq '3DI';

	# get version
	read $fh, $bytes, 2;
	$v2h->{version} = sprintf "ID3v2.%d.%d",
		@$v2h{qw[major_version minor_version]} =
			unpack 'c2', $bytes;

	# get flags
	read $fh, $bytes, 1;
	my @bits = split //, unpack 'b8', $bytes;
	if ($v2h->{major_version} != 4) {
		# JRF: This should never happen - only v4 tags should have footers.
		#      Think about raising some warnings or something ?
		# print STDERR "Invalid ID3v2 footer version number\n";
	} else {
		$v2h->{unsync}       = $bits[7];
		$v2h->{ext_header}   = $bits[6];
		$v2h->{experimental} = $bits[5];
		$v2h->{footer}       = $bits[4];
		if (!$v2h->{footer})
		{
		  # JRF: This is an invalid footer marker; it doesn't make sense
		  #      for the footer to not be marked as the tag having a footer
		  #      so strictly it's an invalid tag.
		  #      A warning might be nice, but for now we'll ignore.
		  # print STDERR "Warning: Footer doesn't have footer bit set\n";
		}
	}

	# get ID3v2 tag length from bytes 7-10
	$v2h->{tag_size} = 10;  # include ID3v2 header size
	$v2h->{tag_size} += 10; # always account for the footer
	read $fh, $bytes, 4;
	@bytes = reverse unpack 'C4', $bytes;
	foreach my $i (0 .. 3) {
		# whoaaaaaa nellllllyyyyyy!
		$v2h->{tag_size} += $bytes[$i] * 128 ** $i;
	}

	# Note that there are no extended header details on the footer; it's
	# just a copy of it so that clients can seek backward to find the
	# footer's start.

	$v2h->{offset} = $eof - $v2h->{tag_size};

	# Just to be really sure, read the start of the ID3v2.4 header here.
	seek $fh, $v2h->{offset}, 0; # SEEK_SET
	read $fh, $bytes, 3;
	if ($bytes ne "ID3") {
	  # Not really an ID3v2.4 tag header; a warning would be nice but ignore
	  # for now.
	  # print STDERR "Invalid ID3v2 footer (header check) at " . $v2h->{offset} . "\n";
	  return undef;
	}

	# We could check more of the header. I'm not sure it's really worth it
	# right now but at some point in the future checking the details match
	# would be nice.

	return $v2h;
  
};

sub _find_id3_chunk {
	my($fh, $filetype) = @_;
	my($bytes, $size, $tag, $pat, $mat);

	read $fh, $bytes, 1;
	if ($filetype eq 'RIF') {  # WAV
		return 0 if $bytes ne 'F';
		$pat = 'a4V';
		$mat = 'id3 ';
	} elsif ($filetype eq 'FOR') { # AIFF
		return 0 if $bytes ne 'M';
		$pat = 'a4N';
		$mat = 'ID3 ';
	}
	seek $fh, 12, SEEK_SET;  # skip to the first chunk

	while ((read $fh, $bytes, 8) == 8) {
		($tag, $size)  = unpack $pat, $bytes;
		return 1 if $tag eq $mat;
		seek $fh, $size, SEEK_CUR;
	}

	return 0;
}

sub _unpack_head {
	unpack('l', pack('L', unpack('N', $_[0])));
}

sub _grab_int_16 {
        my $data  = shift;
        my $value = unpack('s',substr($$data,0,2));
        $$data    = substr($$data,2);
        return $value;
}

sub _grab_uint_16 {
        my $data  = shift;
        my $value = unpack('S',substr($$data,0,2));
        $$data    = substr($$data,2);
        return $value;
}

sub _grab_int_32 {
        my $data  = shift;
        my $value = unpack('V',substr($$data,0,4));
        $$data    = substr($$data,4);
        return $value;
}

# From getid3 - lyrics
# 
# Just get the size and offset, so the APE tag can be parsed.
sub _parse_lyrics3_tag {
	my ($fh, $filesize, $info) = @_;

	# end - ID3v1 - LYRICSEND - [Lyrics3size]
	seek($fh, (0 - 128 - 9 - 6), SEEK_END);
	read($fh, my $lyrics3_id3v1, 128 + 9 + 6);

	my $lyrics3_lsz = substr($lyrics3_id3v1,  0,   6); # Lyrics3size
	my $lyrics3_end = substr($lyrics3_id3v1,  6,   9); # LYRICSEND or LYRICS200
	my $id3v1_tag   = substr($lyrics3_id3v1, 15, 128); # ID3v1

	my ($lyrics3_size, $lyrics3_offset, $lyrics3_version);

	# Lyrics3v1, ID3v1, no APE
	if ($lyrics3_end eq 'LYRICSEND') {

		$lyrics3_size    = 5100;
		$lyrics3_offset  = $filesize - 128 - $lyrics3_size;
		$lyrics3_version = 1;

	} elsif ($lyrics3_end eq 'LYRICS200') {

		# Lyrics3v2, ID3v1, no APE
		# LSZ = lyrics + 'LYRICSBEGIN'; add 6-byte size field; add 'LYRICS200'
		$lyrics3_size    = $lyrics3_lsz + 6 + length('LYRICS200');
		$lyrics3_offset  = $filesize - 128 - $lyrics3_size;
		$lyrics3_version = 2;

	} elsif (substr(reverse($lyrics3_id3v1), 0, 9) eq 'DNESCIRYL') {

		# Lyrics3v1, no ID3v1, no APE
		$lyrics3_size    = 5100;
		$lyrics3_offset  = $filesize - $lyrics3_size;
		$lyrics3_version = 1;
		$lyrics3_offset  = $filesize - $lyrics3_size;

	} elsif (substr(reverse($lyrics3_id3v1), 0, 9) eq '002SCIRYL') {

		# Lyrics3v2, no ID3v1, no APE
		# LSZ = lyrics + 'LYRICSBEGIN'; add 6-byte size field; add 'LYRICS200' > 15 = 6 + strlen('LYRICS200')
		$lyrics3_size    = reverse(substr(reverse($lyrics3_id3v1), 9, 6)) + 15;
		$lyrics3_offset  = $filesize - $lyrics3_size;
		$lyrics3_version = 2;
	}

	return $lyrics3_offset;
}

sub _parse_ape_tag {
	my ($fh, $filesize, $info) = @_;

	my $ape_tag_id          = 'APETAGEX';
	my $id3v1_tag_size      = 128;
	my $ape_tag_header_size = 32;
	my $lyrics3_tag_size    = 10;
	my $tag_offset_start    = 0;
	my $tag_offset_end      = 0;

	if (my $offset = _parse_lyrics3_tag($fh, $filesize, $info)) {

		seek($fh, $offset - $ape_tag_header_size, SEEK_SET);
		$tag_offset_end = $offset;

	} else {

		seek($fh, (0 - $id3v1_tag_size - $ape_tag_header_size - $lyrics3_tag_size), SEEK_END);

		read($fh, my $ape_footer_id3v1, $id3v1_tag_size + $ape_tag_header_size + $lyrics3_tag_size);

		if (substr($ape_footer_id3v1, (length($ape_footer_id3v1) - $id3v1_tag_size - $ape_tag_header_size), 8) eq $ape_tag_id) {

			$tag_offset_end = $filesize - $id3v1_tag_size;

		} elsif (substr($ape_footer_id3v1, (length($ape_footer_id3v1) - $ape_tag_header_size), 8) eq $ape_tag_id) {

			$tag_offset_end = $filesize;
		}

		seek($fh, $tag_offset_end - $ape_tag_header_size, SEEK_SET);
	}

	read($fh, my $ape_footer_data, $ape_tag_header_size);

	my $ape_footer = _parse_ape_header_or_footer($ape_footer_data);

	if (keys %{$ape_footer}) {

		my $ape_tag_data = '';

		if ($ape_footer->{'flags'}->{'header'}) {

			seek($fh, ($tag_offset_end - $ape_footer->{'tag_size'} - $ape_tag_header_size), SEEK_SET);

			$tag_offset_start = tell($fh);

			read($fh, $ape_tag_data, $ape_footer->{'tag_size'} + $ape_tag_header_size);

		} else {

			$tag_offset_start = $tag_offset_end - $ape_footer->{'tag_size'};

			seek($fh, $tag_offset_start, SEEK_SET);

			read($fh, $ape_tag_data, $ape_footer->{'tag_size'});
		}

		my $ape_header_data = substr($ape_tag_data, 0, $ape_tag_header_size, '');
		my $ape_header      = _parse_ape_header_or_footer($ape_header_data);

		if (defined $ape_header->{'tag_items'} && $ape_header->{'tag_items'} =~ /^\d+$/) {

			for (my $c = 0; $c < $ape_header->{'tag_items'}; $c++) {
			
				# Loop through the tag items
				my $tag_len   = _grab_int_32(\$ape_tag_data);
				my $tag_flags = _grab_int_32(\$ape_tag_data);

				$ape_tag_data =~ s/^(.*?)\0//;

				my $tag_item_key = uc($1 || 'UNKNOWN');

				$info->{$tag_item_key} = substr($ape_tag_data, 0, $tag_len, '');
			}
		}
	}

	seek($fh, 0, SEEK_SET);

	return 1;
}

sub _parse_ape_header_or_footer {
	my $bytes = shift;
	my %data = ();

	if (substr($bytes, 0, 8, '') eq 'APETAGEX') {

		$data{'version'}      = _grab_int_32(\$bytes);
		$data{'tag_size'}     = _grab_int_32(\$bytes);
		$data{'tag_items'}    = _grab_int_32(\$bytes);
		$data{'global_flags'} = _grab_int_32(\$bytes);

		# trim the reseved bytes
		_grab_int_32(\$bytes);
		_grab_int_32(\$bytes);

		$data{'flags'}->{'header'}    = ($data{'global_flags'} & 0x80000000) ? 1 : 0;
		$data{'flags'}->{'footer'}    = ($data{'global_flags'} & 0x40000000) ? 1 : 0;
		$data{'flags'}->{'is_header'} = ($data{'global_flags'} & 0x20000000) ? 1 : 0;
	}

	return \%data;
}

sub _close {
	my($file, $fh) = @_;
	unless (ref $file) { # filehandle not passed
		close $fh or carp "Problem closing '$file': $!";
	}
}

BEGIN {
	@mp3_genres = (
		'Blues',
		'Classic Rock',
		'Country',
		'Dance',
		'Disco',
		'Funk',
		'Grunge',
		'Hip-Hop',
		'Jazz',
		'Metal',
		'New Age',
		'Oldies',
		'Other',
		'Pop',
		'R&B',
		'Rap',
		'Reggae',
		'Rock',
		'Techno',
		'Industrial',
		'Alternative',
		'Ska',
		'Death Metal',
		'Pranks',
		'Soundtrack',
		'Euro-Techno',
		'Ambient',
		'Trip-Hop',
		'Vocal',
		'Jazz+Funk',
		'Fusion',
		'Trance',
		'Classical',
		'Instrumental',
		'Acid',
		'House',
		'Game',
		'Sound Clip',
		'Gospel',
		'Noise',
		'AlternRock',
		'Bass',
		'Soul',
		'Punk',
		'Space',
		'Meditative',
		'Instrumental Pop',
		'Instrumental Rock',
		'Ethnic',
		'Gothic',
		'Darkwave',
		'Techno-Industrial',
		'Electronic',
		'Pop-Folk',
		'Eurodance',
		'Dream',
		'Southern Rock',
		'Comedy',
		'Cult',
		'Gangsta',
		'Top 40',
		'Christian Rap',
		'Pop/Funk',
		'Jungle',
		'Native American',
		'Cabaret',
		'New Wave',
		'Psychadelic',
		'Rave',
		'Showtunes',
		'Trailer',
		'Lo-Fi',
		'Tribal',
		'Acid Punk',
		'Acid Jazz',
		'Polka',
		'Retro',
		'Musical',
		'Rock & Roll',
		'Hard Rock',
	);

	@winamp_genres = (
		@mp3_genres,
		'Folk',
		'Folk-Rock',
		'National Folk',
		'Swing',
		'Fast Fusion',
		'Bebop',
		'Latin',
		'Revival',
		'Celtic',
		'Bluegrass',
		'Avantgarde',
		'Gothic Rock',
		'Progressive Rock',
		'Psychedelic Rock',
		'Symphonic Rock',
		'Slow Rock',
		'Big Band',
		'Chorus',
		'Easy Listening',
		'Acoustic',
		'Humour',
		'Speech',
		'Chanson',
		'Opera',
		'Chamber Music',
		'Sonata',
		'Symphony',
		'Booty Bass',
		'Primus',
		'Porn Groove',
		'Satire',
		'Slow Jam',
		'Club',
		'Tango',
		'Samba',
		'Folklore',
		'Ballad',
		'Power Ballad',
		'Rhythmic Soul',
		'Freestyle',
		'Duet',
		'Punk Rock',
		'Drum Solo',
		'Acapella',
		'Euro-House',
		'Dance Hall',
		'Goa',
		'Drum & Bass',
		'Club-House',
		'Hardcore',
		'Terror',
		'Indie',
		'BritPop',
		'Negerpunk',
		'Polsk Punk',
		'Beat',
		'Christian Gangsta Rap',
		'Heavy Metal',
		'Black Metal',
		'Crossover',
		'Contemporary Christian',
		'Christian Rock',
		'Merengue',
		'Salsa',
		'Thrash Metal',
		'Anime',
		'JPop',
		'Synthpop',
	);

	@t_bitrate = ([
		[0, 32, 48, 56,  64,  80,  96, 112, 128, 144, 160, 176, 192, 224, 256],
		[0,  8, 16, 24,  32,  40,  48,  56,  64,  80,  96, 112, 128, 144, 160],
		[0,  8, 16, 24,  32,  40,  48,  56,  64,  80,  96, 112, 128, 144, 160]
	],[
		[0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
		[0, 32, 48, 56,  64,  80,  96, 112, 128, 160, 192, 224, 256, 320, 384],
		[0, 32, 40, 48,  56,  64,  80,  96, 112, 128, 160, 192, 224, 256, 320]
	]);

	@t_sampling_freq = (
		[11025, 12000,  8000],
		[undef, undef, undef],	# reserved
		[22050, 24000, 16000],
		[44100, 48000, 32000]
	);

	@frequency_tbl = map { $_ ? eval "${_}e-3" : 0 }
		map { @$_ } @t_sampling_freq;

	@mp3_info_fields = qw(
		VERSION
		LAYER
		STEREO
		VBR
		BITRATE
		FREQUENCY
		SIZE
		OFFSET
		SECS
		MM
		SS
		MS
		TIME
		COPYRIGHT
		PADDING
		MODE
		FRAMES
		FRAME_LENGTH
		VBR_SCALE
	);

	%rva2_channel_types = (
		0x00 => 'OTHER',
		0x01 => 'MASTER',
		0x02 => 'FRONT_RIGHT',
		0x03 => 'FRONT_LEFT',
		0x04 => 'BACK_RIGHT',
		0x05 => 'BACK_LEFT',
		0x06 => 'FRONT_CENTER',
		0x07 => 'BACK_CENTER',
		0x08 => 'SUBWOOFER',
	);

	%v1_tag_fields =
		(TITLE => 30, ARTIST => 30, ALBUM => 30, COMMENT => 30, YEAR => 4);

	@v1_tag_names = qw(TITLE ARTIST ALBUM YEAR COMMENT TRACKNUM GENRE);

	%v2_to_v1_names = (
		# v2.2 tags
		'TT2' => 'TITLE',
		'TP1' => 'ARTIST',
		'TAL' => 'ALBUM',
		'TYE' => 'YEAR',
		'COM' => 'COMMENT',
		'TRK' => 'TRACKNUM',
		'TCO' => 'GENRE', # not clean mapping, but ...
		# v2.3 tags
		'TIT2' => 'TITLE',
		'TPE1' => 'ARTIST',
		'TALB' => 'ALBUM',
		'TYER' => 'YEAR',
		'COMM' => 'COMMENT',
		'TRCK' => 'TRACKNUM',
		'TCON' => 'GENRE',
		# v2.3 tags - needed for MusicBrainz
		'UFID' => 'Unique file identifier',
		'TXXX' => 'User defined text information frame',
	);

	%v2_tag_names = (
		# v2.2 tags
		'BUF' => 'Recommended buffer size',
		'CNT' => 'Play counter',
		'COM' => 'Comments',
		'CRA' => 'Audio encryption',
		'CRM' => 'Encrypted meta frame',
		'ETC' => 'Event timing codes',
		'EQU' => 'Equalization',
		'GEO' => 'General encapsulated object',
		'IPL' => 'Involved people list',
		'LNK' => 'Linked information',
		'MCI' => 'Music CD Identifier',
		'MLL' => 'MPEG location lookup table',
		'PIC' => 'Attached picture',
		'POP' => 'Popularimeter',
		'REV' => 'Reverb',
		'RVA' => 'Relative volume adjustment',
		'SLT' => 'Synchronized lyric/text',
		'STC' => 'Synced tempo codes',
		'TAL' => 'Album/Movie/Show title',
		'TBP' => 'BPM (Beats Per Minute)',
		'TCM' => 'Composer',
		'TCO' => 'Content type',
		'TCR' => 'Copyright message',
		'TDA' => 'Date',
		'TDY' => 'Playlist delay',
		'TEN' => 'Encoded by',
		'TFT' => 'File type',
		'TIM' => 'Time',
		'TKE' => 'Initial key',
		'TLA' => 'Language(s)',
		'TLE' => 'Length',
		'TMT' => 'Media type',
		'TOA' => 'Original artist(s)/performer(s)',
		'TOF' => 'Original filename',
		'TOL' => 'Original Lyricist(s)/text writer(s)',
		'TOR' => 'Original release year',
		'TOT' => 'Original album/Movie/Show title',
		'TP1' => 'Lead artist(s)/Lead performer(s)/Soloist(s)/Performing group',
		'TP2' => 'Band/Orchestra/Accompaniment',
		'TP3' => 'Conductor/Performer refinement',
		'TP4' => 'Interpreted, remixed, or otherwise modified by',
		'TPA' => 'Part of a set',
		'TPB' => 'Publisher',
		'TRC' => 'ISRC (International Standard Recording Code)',
		'TRD' => 'Recording dates',
		'TRK' => 'Track number/Position in set',
		'TSI' => 'Size',
		'TSS' => 'Software/hardware and settings used for encoding',
		'TT1' => 'Content group description',
		'TT2' => 'Title/Songname/Content description',
		'TT3' => 'Subtitle/Description refinement',
		'TXT' => 'Lyricist/text writer',
		'TXX' => 'User defined text information frame',
		'TYE' => 'Year',
		'UFI' => 'Unique file identifier',
		'ULT' => 'Unsychronized lyric/text transcription',
		'WAF' => 'Official audio file webpage',
		'WAR' => 'Official artist/performer webpage',
		'WAS' => 'Official audio source webpage',
		'WCM' => 'Commercial information',
		'WCP' => 'Copyright/Legal information',
		'WPB' => 'Publishers official webpage',
		'WXX' => 'User defined URL link frame',

		# v2.3 tags
		'AENC' => 'Audio encryption',
		'APIC' => 'Attached picture',
		'COMM' => 'Comments',
		'COMR' => 'Commercial frame',
		'ENCR' => 'Encryption method registration',
		'EQUA' => 'Equalization',
		'ETCO' => 'Event timing codes',
		'GEOB' => 'General encapsulated object',
		'GRID' => 'Group identification registration',
		'IPLS' => 'Involved people list',
		'LINK' => 'Linked information',
		'MCDI' => 'Music CD identifier',
		'MLLT' => 'MPEG location lookup table',
		'OWNE' => 'Ownership frame',
		'PCNT' => 'Play counter',
		'POPM' => 'Popularimeter',
		'POSS' => 'Position synchronisation frame',
		'PRIV' => 'Private frame',
		'RBUF' => 'Recommended buffer size',
		'RVAD' => 'Relative volume adjustment',
		'RVRB' => 'Reverb',
		'SYLT' => 'Synchronized lyric/text',
		'SYTC' => 'Synchronized tempo codes',
		'TALB' => 'Album/Movie/Show title',
		'TBPM' => 'BPM (beats per minute)',
		'TCOM' => 'Composer',
		'TCON' => 'Content type',
		'TCOP' => 'Copyright message',
		'TDAT' => 'Date',
		'TDLY' => 'Playlist delay',
		'TENC' => 'Encoded by',
		'TEXT' => 'Lyricist/Text writer',
		'TFLT' => 'File type',
		'TIME' => 'Time',
		'TIT1' => 'Content group description',
		'TIT2' => 'Title/songname/content description',
		'TIT3' => 'Subtitle/Description refinement',
		'TKEY' => 'Initial key',
		'TLAN' => 'Language(s)',
		'TLEN' => 'Length',
		'TMED' => 'Media type',
		'TOAL' => 'Original album/movie/show title',
		'TOFN' => 'Original filename',
		'TOLY' => 'Original lyricist(s)/text writer(s)',
		'TOPE' => 'Original artist(s)/performer(s)',
		'TORY' => 'Original release year',
		'TOWN' => 'File owner/licensee',
		'TPE1' => 'Lead performer(s)/Soloist(s)',
		'TPE2' => 'Band/orchestra/accompaniment',
		'TPE3' => 'Conductor/performer refinement',
		'TPE4' => 'Interpreted, remixed, or otherwise modified by',
		'TPOS' => 'Part of a set',
		'TPUB' => 'Publisher',
		'TRCK' => 'Track number/Position in set',
		'TRDA' => 'Recording dates',
		'TRSN' => 'Internet radio station name',
		'TRSO' => 'Internet radio station owner',
		'TSIZ' => 'Size',
		'TSRC' => 'ISRC (international standard recording code)',
		'TSSE' => 'Software/Hardware and settings used for encoding',
		'TXXX' => 'User defined text information frame',
		'TYER' => 'Year',
		'UFID' => 'Unique file identifier',
		'USER' => 'Terms of use',
		'USLT' => 'Unsychronized lyric/text transcription',
		'WCOM' => 'Commercial information',
		'WCOP' => 'Copyright/Legal information',
		'WOAF' => 'Official audio file webpage',
		'WOAR' => 'Official artist/performer webpage',
		'WOAS' => 'Official audio source webpage',
		'WORS' => 'Official internet radio station homepage',
		'WPAY' => 'Payment',
		'WPUB' => 'Publishers official webpage',
		'WXXX' => 'User defined URL link frame',

		# v2.4 additional tags
		# note that we don't restrict tags from 2.3 or 2.4,
		'ASPI' => 'Audio seek point index',
		'EQU2' => 'Equalisation (2)',
		'RVA2' => 'Relative volume adjustment (2)',
		'SEEK' => 'Seek frame',
		'SIGN' => 'Signature frame',
		'TDEN' => 'Encoding time',
		'TDOR' => 'Original release time',
		'TDRC' => 'Recording time',
		'TDRL' => 'Release time',
		'TDTG' => 'Tagging time',
		'TIPL' => 'Involved people list',
		'TMCL' => 'Musician credits list',
		'TMOO' => 'Mood',
		'TPRO' => 'Produced notice',
		'TSOA' => 'Album sort order',
		'TSOP' => 'Performer sort order',
		'TSOT' => 'Title sort order',
		'TSST' => 'Set subtitle',

		# grrrrrrr
		'COM ' => 'Broken iTunes comments',
	);
}

1;

__END__

=pod

=back

=head1 TROUBLESHOOTING

If you find a bug, please send me a patch (see the project page in L<"SEE ALSO">).
If you cannot figure out why it does not work for you, please put the MP3 file in
a place where I can get it (preferably via FTP, or HTTP, or .Mac iDisk) and send me
mail regarding where I can get the file, with a detailed description of the problem.

If I download the file, after debugging the problem I will not keep the MP3 file
if it is not legal for me to have it.  Just let me know if it is legal for me to
keep it or not.


=head1 TODO

=over 4

=item ID3v2 Support

Still need to do more for reading tags, such as using Compress::Zlib to decompress
compressed tags.  But until I see this in use more, I won't bother.  If something
does not work properly with reading, follow the instructions above for
troubleshooting.

ID3v2 I<writing> is coming soon.

=item Get data from scalar

Instead of passing a file spec or filehandle, pass the
data itself.  Would take some work, converting the seeks, etc.

=item Padding bit ?

Do something with padding bit.

=item Test suite

Test suite could use a bit of an overhaul and update.  Patches very welcome.

=over 4

=item *

Revamp getset.t.  Test all the various get_mp3tag args.

=item *

Test Unicode.

=item *

Test OOP API.

=item *

Test error handling, check more for missing files, bad MP3s, etc.

=back

=item Other VBR

Right now, only Xing VBR is supported.

=back


=head1 THANKS

Edward Allen,
Vittorio Bertola,
Michael Blakeley,
Per Bolmstedt,
Tony Bowden,
Tom Brown,
Sergio Camarena,
Chris Dawson,
Anthony DiSante,
Luke Drumm,
Kyle Farrell,
Jeffrey Friedl,
brian d foy,
Ben Gertzfield,
Brian Goodwin,
Todd Hanneken,
Todd Harris,
Woodrow Hill,
Kee Hinckley,
Roman Hodek,
Ilya Konstantinov,
Peter Kovacs,
Johann Lindvall,
Alex Marandon,
Peter Marschall,
michael,
Trond Michelsen,
Dave O'Neill,
Christoph Oberauer,
Jake Palmer,
Andrew Phillips,
David Reuteler,
John Ruttenberg,
Matthew Sachs,
scfc_de,
Hermann Schwaerzler,
Chris Sidi,
Roland Steinbach,
Brian S. Stephan,
Stuart,
Dan Sully,
Jeffery Sumler,
Predrag Supurovic,
Bogdan Surdu,
Pierre-Yves Thoulon,
tim,
Pass F. B. Travis,
Tobias Wagener,
Ronan Waide,
Andy Waite,
Ken Williams,
Ben Winslow,
Meng Weng Wong,
Justin Fletcher.

=head1 CURRENT AUTHOR 

Dan Sully E<lt>dan | at | slimdevices.comE<gt> & Slim Devices, Inc.

=head1 AUTHOR EMERITUS

Chris Nandor E<lt>pudge@pobox.comE<gt>, http://pudge.net/

=head1 COPYRIGHT AND LICENSE 

Copyright (c) 2006 Dan Sully & Slim Devices, Inc. All rights reserved. 

Copyright (c) 1998-2005 Chris Nandor. All rights reserved. 

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

=over 4

=item Slim Devices

	http://www.slimdevices.com/

=item mp3tools

	http://www.zevils.com/linux/mp3tools/

=item mpgtools

	http://www.dv.co.yu/mpgscript/mpgtools.htm
	http://www.dv.co.yu/mpgscript/mpeghdr.htm

=item mp3tool

	http://www.dtek.chalmers.se/~d2linjo/mp3/mp3tool.html

=item ID3v2

	http://www.id3.org/

=item Xing Variable Bitrate

	http://www.xingtech.com/support/partner_developer/mp3/vbr_sdk/

=item MP3Ext

	http://rupert.informatik.uni-stuttgart.de/~mutschml/MP3ext/

=item Xmms

	http://www.xmms.org/


=back

=cut
