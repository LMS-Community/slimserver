package MP3::Info;
use overload;
use strict;
use Carp;
use Symbol;

use vars qw(
	@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION $REVISION
	@mp3_genres %mp3_genres @winamp_genres %winamp_genres $try_harder
	@t_bitrate @t_sampling_freq @frequency_tbl %v1_tag_fields
	@v1_tag_names %v2_tag_names %v2_to_v1_names $AUTOLOAD
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

# $Id: Info.pm,v 1.5 2003/11/26 21:24:37 dean Exp $
($REVISION) = ' $Revision: 1.5 $ ' =~ /\$Revision:\s+([^\s]+)/;
$VERSION = '1.01';

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

=cut

sub new {
	my($pack, $file) = @_;

	my $info = get_mp3info($file) or return undef;
	my $tags = get_mp3tag($file) || { map { ($_ => undef) } @v1_tag_names };
	my %self = (
		FILE		=> $file,
		TRY_HARDER	=> 0
	);
	@self{keys %$info, keys %$tags, qw(file)} =
		(values %$info, values %$tags, $file);
	return bless \%self, $pack;
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


=head1 DESCRIPTION

=over 4

=item use_mp3_utf8([STATUS])

Tells MP3::Info to (or not) return TAG info in UTF-8.
TRUE is 1, FALSE is 0.  Default is FALSE.

Will only be able to it on if Unicode::String is available.  ID3v2
tags will be converted to UTF-8 according to the encoding specified
in each tag; ID3v1 tags will be assumed Latin-1 and converted
to UTF-8.

Function returns status (TRUE/FALSE).  If no argument is supplied,
or an unaccepted argument is supplied, function merely returns status.

This function is not exported by default, but may be exported
with the C<:utf8> export tag.

=cut

my $unicode_module = eval { require Unicode::String };
my $UNICODE = 0;

sub use_mp3_utf8 {
	my $val = @_;
	if ($val == 1) {
		$UNICODE = 1 if $unicode_module;
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

Can remove ID3v1 or ID3v2 tags.  VERSION should be C<1> for ID3v1,
C<2> for ID3v2, and C<ALL> for both.

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

	carp('No file specified'), return undef
		unless defined $file && $file ne '';

	return undef unless -s $file;
	if (ref $file) { # filehandle passed
		$fh = $file;
	} else {
		$fh = gensym;
		open $fh, "+< $file\0" or return undef;
	}

	binmode $fh;

	if ($version eq 1 || $version eq 'ALL') {
		seek $fh, -128, 2;
		my $tell = tell $fh;
		if (<$fh> =~ /^TAG/) {
			truncate $fh, $tell or carp "Can't truncate '$file': $!";
		}
		$return += 128;
	}

	if ($version eq 2 || $version eq 'ALL') {
		my $h = _get_v2head($fh);
		if ($h) {
			local $\;
			seek $fh, 0, 2;
			my $eof = tell $fh;
			my $off = $h->{tag_size};

			while ($off < $eof) {
				seek $fh, $off, 0;
				read $fh, my($bytes), $buf;
				seek $fh, $off - $h->{tag_size}, 0;
				print $fh $bytes;
				$off += $buf;
			}

			truncate $fh, $eof - $h->{tag_size}
				or carp "Can't truncate '$file': $!";
			$return += $h->{tag_size};
		}
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
C<get_mp3_tag> on the file, it will show you the (unchanged) ID3v2 tags,
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
		carp(<<'EOT'), return;
Usage: set_mp3tag (FILE, TITLE, ARTIST, ALBUM, YEAR, COMMENT, GENRE [, TRACKNUM]),
		set_mp3tag (FILE, $HASHREF)
EOT
	}

	carp('No file specified'), return unless defined $file && $file ne '';

	# comment field length 28 if ID3v1.1
	$v1_tag_fields{COMMENT} = 28 if $info{TRACKNUM};


	# only if -w is on
	if ($^W) {
		# warn if fields too long
		foreach my $field (keys %v1_tag_fields) {
			$info{$field} = '' unless defined $info{$field};
			if (length($info{$field}) > $v1_tag_fields{$field}) {
				carp 'Data too long for field $field: truncated to ' .
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

	return unless -s $file;
	if (ref $file) { # filehandle passed
		$fh = $file;
	} else {
		$fh = gensym;
		open $fh, "+< $file\0" or return;
	}

	binmode $fh;
	$oldfh = select $fh;
	seek $fh, -128, 2;
	# go to end of file if no tag, beginning of file if tag
	seek $fh, (<$fh> =~ /^TAG/ ? -128 : 0), 2;

	# get genre value
	$info{GENRE} = $info{GENRE} && exists $mp3_genres{$info{GENRE}} ?
		$mp3_genres{$info{GENRE}} : 255;  # some default genre

	local $\;
	# print TAG to file
	if ($info{TRACKNUM}) {
		print pack "a3a30a30a30a4a28xCC", 'TAG', @info{@v1_tag_names};
	} else {
		print pack "a3a30a30a30a4a30C", 'TAG', @info{@v1_tag_names[0..4, 6]};
	}

	select $oldfh;

	_close($file, $fh);

	return 1;
}

=pod

=item get_mp3tag (FILE [, VERSION, RAW_V2])

Returns hash reference containing tag information in MP3 file.  Same
info as described in C<set_mp3tag>.

If VERSION is C<1>, the information is taken from the ID3v1 tag (if present).
If VERSION is C<2>, the information is taken from the ID3v2 tag (if present).
If VERSION is not supplied, or is false, the ID3v1 tag is read if present, and
then, if present, the ID3v2 tag information will override any existing ID3v1
tag info.

If the ID3v2 version is older than ID3v2.2.0 or newer than ID3v2.3.0, it will
not be read (and a warning will be issued if B<-w> is on).

If RAW_V2 is false or not supplied and VERSION is C<2>, only the tags
corresponding to ID3v1 tags are returned, with the same keys in the returned
hashref.

If RAW_V2 is true and VERSION is C<2>, C<get_mp3tag> will return a hash
of tag four-character IDs and their data, without stripping text encoding and
language code information.  Tag IDs and their meanings are in the global hash
(not exported) C<%v2_tag_names>.

	my $tag = get_mp3tag('mysong.mp3', 2, 1);   # ID3v2, raw ID3v2 tags
	for (keys %$tag) {
		printf "%s => %s\n", $MP3::Info::v2_tag_names{$_}, $tag->{$_};
	}

Strings returned will be in Latin-1, unless UTF-8 is specified
(L<use_mp3_utf8>), unless RAW_V2 is specified, in which no
charset manipulation is done.

Also returns a VERSION key, containing the ID3 version used for the returned
data (if VERSION argument is C<0>, may contain two versions).

=cut

sub get_mp3tag {
	my($file, $ver, $raw_v2) = @_;
	my($tag, $v1, $v2, $v2h, %info, @array, $fh);
	$ver = !$ver ? 0 : ($ver == 2 || $ver == 1) ? $ver : 0;

	carp('No file specified'), return undef unless defined $file && $file ne '';

	return undef unless -s $file;
	if (ref $file) { # filehandle passed
		$fh = $file;
	} else {
		$fh = gensym;
		open $fh, "< $file\0" or return undef;
	}

	binmode $fh;

	if ($ver < 2) {
		seek $fh, -128, 2;
		while(defined(my $line = <$fh>)) { $tag .= $line }

		if (defined($tag) && $tag =~ /^TAG/) {
			$v1 = 1;
			if (substr($tag, -3, 2) =~ /\000[^\000]/) {
				(undef, @info{@v1_tag_names}) =
					(unpack('a3a30a30a30a4a28', $tag),
					ord(substr($tag, -2, 1)),
					$mp3_genres[ord(substr $tag, -1)]);
				$info{TAGVERSION} = 'ID3v1.1';
			} else {
				(undef, @info{@v1_tag_names[0..4, 6]}) =
					(unpack('a3a30a30a30a4a30', $tag),
					$mp3_genres[ord(substr $tag, -1)]);
				$info{TAGVERSION} = 'ID3v1';
			}
			if ($UNICODE) {
				for my $key (keys %info) {
					my $u;
					if (defined($key) && defined($info{$key})) {
						$u = Unicode::String::latin1($info{$key});
					}
					if (defined($u)) {
						if (defined($u->utf8)) { 
							$info{$key} = $u->utf8; 
						}	
					}
				}
			}
		} elsif ($ver == 1) {
			_close($file, $fh);
			return undef;
		}
	}

	($v2, $v2h) = _get_v2tag($fh);
	unless ($v1 || $v2) {
		_close($file, $fh);
		return undef;
	}

	if (($ver == 0 || $ver == 2) && $v2) {
		if ($raw_v2 && $ver == 2) {
			%info = %$v2;
			$info{TAGVERSION} = $v2h->{version};
		} else {
			for (keys %v2_to_v1_names) {
				if (exists $v2->{$_}) {
					if ($_ =~ /^TCON?$/ && $v2->{$_} =~ /^.?\((\d+)\)/) {
						$info{$v2_to_v1_names{$_}} = $mp3_genres[$1];
					} else {
						my $data = $v2->{$_};

						# this is tricky ... if this is an arrayref,
						# we want to only return one, so we pick the
						# first one.  but if it is a comment, we pick
						# the first one where the first charcter after
						# the language is NULL and not an additional
						# sub-comment, because that is most likely to be
						# the user-supplied comment
						if (ref $data) {
							if ($_ =~ /^COMM?$/) {
								my($newdata) = grep /^(....\000)/, @{$data};
								$data = $newdata || $data->[0];
							} else {
								$data = $data->[0];
							}
						}
						$data =~ s/^(.)//; # strip first char (text encoding)
						my $encoding = $1;
						if ($_ =~ /^COMM?$/) {
							$data =~ s/^(?:...)//;	# strip language
							$data =~ s/^.*?\000+//;	# strip up to first NULL(s),
										# for sub-comment
						}
						if ($UNICODE) {
							if ($encoding eq "\001" || $encoding eq "\002") {  # UTF-16, UTF-16BE
								my $u = Unicode::String::utf16($data);
								$data = $u->utf8;
								$data =~ s/^\xEF\xBB\xBF//;	# strip BOM
							} elsif ($encoding eq "\000") {
								my $u = Unicode::String::latin1($data);
								$data = $u->utf8;
							}
						}
						$info{$v2_to_v1_names{$_}} = $data;
					}
				}
			}
			if ($ver == 0 && $info{TAGVERSION}) {
				$info{TAGVERSION} .= ' / ' . $v2h->{version};
			} else {
				$info{TAGVERSION} = $v2h->{version};
			}
		}
	}

	unless ($raw_v2 && $ver == 2) {
		foreach my $key (keys %info) {
			if (defined $info{$key}) {
				$info{$key} =~ s/\000+.*//g;
				$info{$key} =~ s/\s+$//;
			}
		}
	}

	if (keys %info && ! defined $info{GENRE}) {
		$info{GENRE} = '';
	}

	_close($file, $fh);

	return keys %info ? {%info} : undef;
}

sub _get_v2tag {
	my($fh) = @_;
	my($off, $myseek, $myseek_22, $myseek_23, $v2, $h, $hlen, $num);

	$v2 = _get_v2head($fh) or return;
	if ($v2->{major_version} < 2) {
		carp "This is $v2->{version}; " .
			 "ID3v2 versions older than ID3v2.2.0 not supported\n"
			  if $^W;
		return;
	}

	if ($v2->{major_version} == 2) {
		$hlen = 6;
		$num = 3;
	} else {
		$hlen = 10;
		$num = 4;
	}
	
	$off = $v2->{ext_header_size} + 10;
	my $end = $off + $v2->{tag_size};

	seek $fh, 0, 0;
	
	my $wholetag;
	
	read $fh, $wholetag, $end;
	
	if ($v2->{unsync}) {
		my $hits = ($wholetag =~ s/\xFF\x00/\xFF/gs);
	}
	
	$myseek = sub {
		my $bytes = substr($wholetag, $off, $hlen);
		# djb - iTunes uses a space in one of the tag names.  not to spec, but safe nonetheless
		return unless $bytes =~ /^([A-Z0-9 ]{$num})/;
		my($id, $size) = ($1, $hlen);
		my @bytes = reverse unpack "C$num", substr($bytes, $num, $num);
		for my $i (0 .. ($num - 1)) {
			$size += $bytes[$i] * 256 ** $i;
		}
		return($id, $size);
	};

	while ($off < $end) {
		my($id, $size) = &$myseek or last;
		# djb - sanity check on size of tag.
		last if ($size > $v2->{tag_size});
		my $bytes = substr($wholetag, $off+$hlen, $size-$hlen);

		if (exists $h->{$id}) {
			if (ref $h->{$id} eq 'ARRAY') {
				push @{$h->{$id}}, $bytes;
			} else {
				$h->{$id} = [$h->{$id}, $bytes];
			}
		} else {
			$h->{$id} = $bytes;
		}
		$off += $size;
	}
	
	return($h, $v2);
}


=pod

=item get_mp3info (FILE)

Returns hash reference containing file information for MP3 file.
This data cannot be changed.  Returned data:

	VERSION			MPEG audio version (1, 2, 2.5)
	LAYER			MPEG layer description (1, 2, 3)
	STEREO			boolean for audio is in stereo
	
	VBR				boolean for variable bitrate
	BITRATE			bitrate in kbps (average for VBR files)
	FREQUENCY		frequency in kHz
	SIZE			bytes in audio stream
	OFFSET			offset from start of file to audio stream
	
	SECS			total seconds
	MM				minutes
	SS				leftover seconds
	MS				leftover milliseconds
	TIME			time in MM:SS
	
	COPYRIGHT		boolean for audio is copyrighted
	PADDING			boolean for MP3 frames are padded
	MODE			channel mode (0 = stereo, 1 = joint stereo,
					2 = dual channel, 3 = single channel)
	FRAMES			approximate number of frames
	FRAME_LENGTH	approximate length of a frame
	VBR_SCALE		VBR scale from VBR header

=cut

sub get_mp3info {
	my($file) = @_;
	my($off, $myseek, $byte, $eof, $h, $tot, $fh);

	carp('No file specified'), return undef unless defined $file && $file ne '';
	return undef unless -s $file;
	if (ref $file) { # filehandle passed
		$fh = $file;
	} else {
		$fh = gensym;
		open $fh, "< $file\0" or return undef;
	}

	$off = 0;
	$tot = 8192;

	$myseek = sub {
		seek $fh, $off, 0;
		read $fh, $byte, 4;
	};

	binmode $fh;
	&$myseek;

	if ($off == 0) {
		if (my $id3v2 = _get_v2head($fh)) {
			$tot += $off += $id3v2->{tag_size};
			&$myseek;
		}
	}

	$h = _get_head($byte);
	until (_is_mp3($h)) {
		$off++;
		&$myseek;
		$h = _get_head($byte);
		if ($off > $tot && !$try_harder) {
			_close($file, $fh);
			return undef;
		}
	}

	my $vbr = _get_vbr($fh, $h, \$off);

	seek $fh, 0, 2;
	$eof = tell $fh;
	seek $fh, -128, 2;
	$eof -= 128 if <$fh> =~ /^TAG/ ? 1 : 0;

	_close($file, $fh);

	$h->{size} = $eof - $off;
	$h->{offset} = $off;

	return _get_info($h, $vbr);
}

sub _get_info {
	my($h, $vbr) = @_;
	my $i;

	$i->{VERSION}	= $h->{IDR} == 2 ? 2 : $h->{IDR} == 3 ? 1 :
				$h->{IDR} == 0 ? 2.5 : 0;
	$i->{LAYER}	= 4 - $h->{layer};
	$i->{VBR}	= defined $vbr ? 1 : 0;

	$i->{COPYRIGHT}	= $h->{copyright} ? 1 : 0;
	$i->{PADDING}	= $h->{padding_bit} ? 1 : 0;
	$i->{STEREO}	= $h->{mode} == 3 ? 0 : 1;
	$i->{MODE}	= $h->{mode};

	$i->{SIZE}	= $vbr && $vbr->{bytes} ? $vbr->{bytes} : $h->{size};
	$i->{OFFSET} = $h->{offset};

	my $mfs		= $h->{fs} / ($h->{ID} ? 144000 : 72000);
	$i->{FRAMES}	= int($vbr && $vbr->{frames}
				? $vbr->{frames}
				: $i->{SIZE} / $h->{bitrate} / $mfs
			  );

	if ($vbr) {
		$i->{VBR_SCALE}	= $vbr->{scale} if $vbr->{scale};
		$h->{bitrate}	= $i->{SIZE} / $i->{FRAMES} * $mfs;
		return undef unless $h->{bitrate};
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
	$i->{FRAME_LENGTH}	= $i->{FRAMES} ? int($h->{size} / $i->{FRAMES}) : 0;
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
			||
		($h->{mode_extension} != 0 && $h->{mode} != 1)
	);
}

sub _get_vbr {
	my($fh, $h, $roff) = @_;
	my($off, $bytes, @bytes, $myseek, %vbr);

	$off = $$roff;
	@_ = ();	# closure confused if we don't do this

	$myseek = sub {
		my $n = $_[0] || 4;
		seek $fh, $off, 0;
		read $fh, $bytes, $n;
		$off += $n;
	};

	$off += 4;

	if ($h->{ID}) {	# MPEG1
		$off += $h->{mode} == 3 ? 17 : 32;
	} else {	# MPEG2
		$off += $h->{mode} == 3 ? 9 : 17;
	}

	&$myseek;
	return unless $bytes eq 'Xing';

	&$myseek;
	$vbr{flags} = _unpack_head($bytes);

	if ($vbr{flags} & 1) {
		&$myseek;
		$vbr{frames} = _unpack_head($bytes);
	}

	if ($vbr{flags} & 2) {
		&$myseek;
		$vbr{bytes} = _unpack_head($bytes);
	}

	if ($vbr{flags} & 4) {
		$myseek->(100);
# Not used right now ...
#		$vbr{toc} = _unpack_head($bytes);
	}

	if ($vbr{flags} & 8) { # (quality ind., 0=best 100=worst)
		&$myseek;
		$vbr{scale} = _unpack_head($bytes);
	} else {
		$vbr{scale} = -1;
	}

	$$roff = $off;
	return \%vbr;
}

sub _get_v2head {
	my $fh = $_[0] or return;
	my($h, $bytes, @bytes);
	my $offset = 0;
	# check first three bytes for 'ID3'
	seek $fh, 0, 0;
	read $fh, $bytes, 3;
	
	if ($bytes eq 'RIF') {
		if(_find_wav_id3_chunk($fh)) {
			$offset = tell($fh);
			read $fh, $bytes, 3;
		} else {
			return;
		};
	}
	return unless $bytes eq 'ID3';
	# get version
	read $fh, $bytes, 2;
	$h->{version} = sprintf "ID3v2.%d.%d",
		@$h{qw[major_version minor_version]} =
			unpack 'c2', $bytes;

	# get flags
	read $fh, $bytes, 1;
	my @bits = split //, (unpack 'b8', $bytes);
	if ($h->{major_version} == 2) {
		$h->{unsync} = $bits[7];
		$h->{compression} = $bits[6];
		$h->{ext_header} = 0;
		$h->{experimental} = 0;
	} else {
		@bits = split //, (unpack 'b8', $bytes);
		$h->{unsync} = $bits[7];
		$h->{header} = $bits[6];
		$h->{experimental} = $bits[5];
	}

	# get ID3v2 tag length from bytes 7-10
	$h->{tag_size} = 10;	# include ID3v2 header size
	read $fh, $bytes, 4;
	@bytes = reverse unpack 'C4', $bytes;
	foreach my $i (0 .. 3) {
		# whoaaaaaa nellllllyyyyyy!
		$h->{tag_size} += $bytes[$i] * 128 ** $i;
	}

	# get extended header size
	$h->{ext_header_size} = $offset;
	if ($h->{ext_header}) {
		$h->{ext_header_size} += 10;
		read $fh, $bytes, 4;
		@bytes = reverse unpack 'C4', $bytes;
		for my $i (0..3) {
			$h->{ext_header_size} += $bytes[$i] * 256 ** $i;
		}
	}
	return $h;
}

sub _find_wav_id3_chunk {
	my $fh = shift;
	my $bytes;
	my $size;
	my $tag;
	
	read $fh, $bytes, 1;	
	if ($bytes ne 'F') { return 0; }  # must be a RIFF file	
	seek $fh, 12, 0;  # skip to the first chunk
	
	while ((read $fh, $bytes, 8) == 8) {
		($tag, $size)  = unpack "a4V", $bytes;
		if ($tag eq 'id3 ') { 
			return 1;
		}
		seek $fh, $size, 1;
	}
	
	return 0;
}


sub _unpack_head {
	unpack('l', pack('L', unpack('N', $_[0])));
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
		'TPA' => 'SET',
		# v2.3 tags
		'TIT2' => 'TITLE',
		'TPE1' => 'ARTIST',
		'TALB' => 'ALBUM',
		'TYER' => 'YEAR',
		'COMM' => 'COMMENT',
		'TRCK' => 'TRACKNUM',
		'TCON' => 'GENRE',
		'TPOS' => 'SET'
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
	);
}

1;

__END__

=pod

=back

=head1 TROUBLESHOOTING

If you find a bug, please send me a patch.  If you cannot figure out
why it does not work for you, please put the MP3 file in a place where
I can get it (preferably via FTP) and send me mail regarding where I
can get the file, with a detailed description of the problem.

If I download the file, after debugging the problem I will not keep the
MP3 file if it is not legal for me to have it.  Just let me know if
it is legal for me to keep it or not.


=head1 TODO

=over 4

=item ID3v2 Support

First go at adding support for reading ID3v2 tags.  Still need to do
more, such as using Compress::Zlib to decompress compressed tags.
But until I see this in use more, I won't bother.  I might not be able
to support Unicode at all, until Perl supports 16-bit Unicode.
If something does not work properly with reading, follow the
instructions above for troubleshooting.

I think I might just use Matt DiMeo's MPEG::ID3v2Tag; the problem is
that right now it requires 5.005, and MacPerl uses 5.004 (for now).

=item Get data from scalar

Instead of passing a file spec or filehandle, pass the
data itself.  Would take some work, converting the seeks, etc.

=item Padding bit ?

Do something with padding bit.

=item ID3v2.4.0

It's the new standard.  There are no specific plans to update to
2.4.0.  I'd like it to be done, but there is no pressing need, and
I don't really have the time right now.  Patches welcome!  :-)

=item Test suite

Test suite could use a bit of an overhaul and update.

=item Other VBR

Right now, only Xing VBR is supported.

=back


=head1 HISTORY

=over 4

=item v1.01, Friday, February 26, 2002

That was less reasonable than previously thought.  Just strip
off text encoding bit, and then bytes for language and "up to first
null" if COMM field (COMM fields can have an extra comment about the
comment, which is terminated with a NULL, of course ...).
Some encoders like to put in an extra NULL at the end; plus, it
was doing the wrong thing for non-Latin-1 text.  (Ben Gertzfield)

Also make it work better with ID3v2.2 tags, and make a more reasonable
guess at which comment to use if there's more than one.

Add some support for ID3v2.4.0 and Unicode strings in tags;
see C<use_mp3_utf8>. (Ben Gertzfield)

Add TAGVERSION to get_mp3tag result.


=item v1.00, Tuesday, January 22, 2002

Get more reasonable data out of ID3v2 tags by stripping up to
last null in tag.

Don't get FRAME_LENGTH if no FRAMES (Woodrow Hill).


=item v0.91, Saturday, February 10, 2001

Fix dumb bug with /o. (David Reuteler)

Fix bug where C<get_mp3tag> would return an empty hashref instead
of undef if ID3v1 tag is asked for, and there is no ID3v1 tag, but
there is an ID3v2 tag.  (Stuart)


=item v0.90, Sunday, January 14, 2001

Added experimental OOP support for getting and setting data;
doesn't work for removing tags.

Made all functions optionally accept filehandle in place of filename.

Remove all croaks/dies and replace with simple returns or carps/warns.
(Jeffrey Sumler)

Fix various input data problems, bad warnings, division by zero, etc.

Undef C<$/> in set_mp3tag() so caller can't mess up the print.

Fix bitrate if ID == 0 and VBR.  (Kyle Farrell, Per Bolmstedt)

Split off _get_info() from get_mp3info(), so, eventually, programmers
can access that functionality without passing in a file or filehandle.
Not supported yet, but available for playing.

Added total frames, leftover milliseconds, and formatted time.

Fixed sample frequency for MPEG 2.5 files (perhaps not including
VBR, though ... see bug above).

Add in some additional genres.  (Peter Marschall)

Added ID3v2 tag removal. (Ronan Waide)  NOTE: this is DANGEROUS.  It is tested,
but needs more testing.  The file is rewritten entirely.  Lots of data
moving around.

Added ID3v2.2.0 tag reading. (Ronan Waide, Kee Hinckley)

Changed ID3v2 tag recognition to only match [A-Z0-9] instead of \w.
(Christoph Oberauer)


=item v0.80, Monday, March 6, 2000

Better stripping of bad data (after nulls) in ID3 tags (Dave O'Neill)

Fixed VERSION in get_mp3info to properly return 2 when appropriate.
(Bogdan Surdu)

Added VBR support.  Average bitrate is returned as BITRATE, and
minutes and seconds (MM and SS) should be accurate.
(Andy Waite for pointer to MP3Ext)

Made time calculation better overall.

Made MP3 header validation routines more comprehensive.
(Matthew Sachs for pointer to xmms source)

Changed name to MP3::Info (with wrapper still named MP3::Info).


=item v0.71, Thursday, July 8, 1999

Several fixes to ID3v2 support unpack unsigned instead
of signed, don't bail out after 4096-byte offsets on long ID3v2 headers.
Thanks much to Matthew Sachs.


=item v0.70, Saturday, July 3, 1999

Added preliminary ID3v2 reading support in C<get_mp3tag>.  Thanks much
to Tom Brown.


=item v0.64, Thursday, July 1, 1999

Found bug in checking TRACKNUM parameter, used \d instead of \d+.
Only gives spurious warnings, doesn't affect anything else.

Cleaned up a bit, prepare for impending ID3v2 support.

NOTE: truncate() broken in some builds of ActivePerl (517, maybe
others).  No changes to module to fix problem.  (Brian Goodwin)


=item v0.63, Friday, April 30, 1999

Added ID3v1.1 support. (Trond Michelsen, Pass F. B. Travis)

Added 255 (\xFF) as default genre. (Andrew Phillips)

I think I fixed bug relating to spaces in ID3v2 headers. (Tom Brown)


=item v0.62, Sunday, March 7, 1999

Doc updates.

Fix small unnoticable bug where ID3v2 offset is tag size plus 10,
not just tag size.

Not publickly released.


=item v0.61, Monday, March 1, 1999

Fixed problem of not removing nulls on return from C<get_mp3tag> (was
using spaces for padding before ... now trailing whitespace and
all nulls are removed before returning tag info).

Made tests more extensive (more for my own sanity when making all
these changes than to make sure it works on other platforms and
machines :).


=item v0.60, Sunday, February 28, 1999

Cleaned up a lot of stuff, added more comments, made C<get_mp3info>
much faster and much more reliable, and added recognition of ID3v2
headers.  (Tom Brown)



=item v0.52, Sunday, February 21, 1999

Fixed problem in C<get_mp3tag> that changed value of C<$_> in caller
(Todd Hanneken).


=item v0.51, Saturday, February 20, 1999

Fixed problem with C<%winamp_genres> having the wrong numbers
(Matthew Sachs).


=item v0.50, Friday, February 19, 1999

Added C<remove_mp3tag>.  Addeed VERSION to the hash returned by
C<get_mp3info>, and fixed a bug where STEREO was not being set correctly.

Export all genre data structures on request.  Added C<use_winamp_genres>
to use WinAmp genres. (Roland Steinbach)

Added a C<$MPEG::MP3Info::try_harder> (C<$MP3::Info::try_harder>) variable
that will try harder to find the MP3 header in a file.  False by default.
Can take a long time to fail, but should find most headers at any offsets
if set to true.

Thanks to Matthew Sachs for his input and fixes, and for mp3tools.


=item v0.20, Saturday, October 17, 1998

Changed name from C<MPEG::MP3Tag> to C<MPEG::MP3Info>, because it does
more than just TAG stuff now.

Made header stuff even more reliable.  Lots of help and testing from
Meng Weng Wong again.  :-)


=item v0.13, Thursday, October 8, 1998

Had some problems with header verification, got some code from
Predrag Supurovic with his mpgtools.
Great stuff.  Also did some looping to find a header if it is not in the
"right" place.  I did what I think it is a smart way to do it, since
some files have the header as far down as 2 kbytes into the file.  First,
I look at position 0, then at position 36 (a position where I have found
many headers), then I start at 0 again and jump in 128-byte chunks.
Once I do that a bunch of times, I go back at the beginning and try at 0
and go ahead in 1-byte chunks for a bunch more times.

If you have an MP3 that has the header begin at an odd place like byte
761, then I suggest you strip out the junk before the header begins. :-)


=item v0.12, Friday, October 2, 1998

Added C<get_mp3info>.  Thanks again to F<mp3tool> source from
Johann Lindvall, because I basically stole it straight (after
converting it from C to Perl, of course).

I did everything I could to find the header info, but if
anyone has valid MP3 files that are not recognized, or has suggestions
for improvement of the algorithms, let me know.


=item v0.04, Tuesday, September 29, 1998

Changed a few things, replaced a regex with an C<unpack>.
(Meng Weng Wong)


=item v0.03, Tuesday, September 8, 1998

First public release.

=back

=head1 THANKS

Edward Allen E<lt>allenej@c51844-a.spokn1.wa.home.comE<gt>,
Vittorio Bertola E<lt>v.bertola@vitaminic.comE<gt>,
Michael Blakeley E<lt>mike@blakeley.comE<gt>,
Per Bolmstedt E<lt>tomten@kol14.comE<gt>,
Tony Bowden E<lt>tony@tmtm.comE<gt>,
Tom Brown E<lt>thecap@usa.netE<gt>,
Sergio Camarena E<lt>scamarena@users.sourceforge.netE<gt>,
Chris Dawson E<lt>cdawson@webiphany.comE<gt>,
Luke Drumm E<lt>lukedrumm@mypad.comE<gt>,
Kyle Farrell E<lt>kyle@cantametrix.comE<gt>,
Ben Gertzfield E<lt>che@debian.orgE<gt>,
Brian Goodwin E<lt>brian@fuddmain.comE<gt>,
Todd Hanneken E<lt>thanneken@hds.harvard.eduE<gt>,
Woodrow Hill E<lt>asim@mindspring.comE<gt>,
Kee Hinckley E<lt>nazgul@somewhere.comE<gt>,
Roman Hodek E<lt>Roman.Hodek@informatik.uni-erlangen.deE<gt>,
Peter Kovacs E<lt>kovacsp@egr.uri.eduE<gt>,
Johann Lindvall,
Peter Marschall E<lt>peter.marschall@mayn.deE<gt>,
Trond Michelsen E<lt>mike@crusaders.noE<gt>,
Dave O'Neill E<lt>dave@nexus.carleton.caE<gt>,
Christoph Oberauer E<lt>christoph.oberauer@sbg.ac.atE<gt>,
Andrew Phillips E<lt>asp@wasteland.orgE<gt>,
David Reuteler E<lt>reuteler@visi.comE<gt>,
Matthew Sachs E<lt>matthewg@zevils.comE<gt>,
Hermann Schwaerzler E<lt>Hermann.Schwaerzler@uibk.ac.atE<gt>,
Chris Sidi E<lt>sidi@angband.orgE<gt>,
Roland Steinbach E<lt>roland@support-system.comE<gt>,
Stuart E<lt>schneis@users.sourceforge.netE<gt>,
Jeffery Sumler E<lt>jsumler@mediaone.netE<gt>,
Predrag Supurovic E<lt>mpgtools@dv.co.yuE<gt>,
Bogdan Surdu E<lt>tim@go.roE<gt>,
Pass F. B. Travis E<lt>pftravis@bellsouth.netE<gt>,
Tobias Wagener E<lt>tobias@wagener.nuE<gt>,
Ronan Waide E<lt>waider@stepstone.ieE<gt>,
Andy Waite E<lt>andy@mailroute.comE<gt>,
Ken Williams E<lt>ken@forum.swarthmore.eduE<gt>,
Meng Weng Wong E<lt>mengwong@pobox.comE<gt>.


=head1 AUTHOR AND COPYRIGHT

Chris Nandor E<lt>pudge@pobox.comE<gt>, http://pudge.net/

Copyright (c) 1998-2002 Chris Nandor.  All rights reserved.  This program is
free software; you can redistribute it and/or modify it under the terms
of the Artistic License, distributed with Perl.


=head1 SEE ALSO

=over 4

=item SourceForge Page

	http://sourceforge.net/projects/mp3-info/

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

=head1 VERSION

v1.01, Tuesday, February 26, 2002

=cut
