package Audio::Musepack;

# $Id$

use strict;
use Audio::APETags;
use Fcntl qw(:seek);
use MP3::Info;

our $VERSION = '0.02';

# First four bytes of stream are always fLaC
use constant MPCHEADERFLAG => 'MP+';
use constant APEHEADERFLAG => 'APETAGEX';

sub new {
	my $class = shift;
	my $file  = shift;
	my $errflag = 0;
	my $tmp;

	my $self  = {};

	bless $self, $class;

	# open up the file
	open(FILE, $file) or do {
		warn "File $file does not exist or cannot be read.";
		return $self;
	};

	# make sure dos-type systems can handle it...
	binmode FILE;

	$self->{'fileSize'}   = -s $file;
	$self->{'filename'}   = $file;
	$self->{'fileHandle'} = \*FILE;

	# Initialize MPC analysis
	$errflag = $self->_init();
	if ($errflag < 0) {
		warn "File $self->{'filename'} does not appear to be a Musepack file!";
		close FILE;
		undef $self->{'fileHandle'};
		return $self;
	};

	# Grab the information from the MPC headers
	$errflag = $self->_getAudioInfo();
	if ($errflag < 0) {
		warn "Unable to read MPC information from file!";
		close FILE;
		undef $self->{'fileHandle'};
		return $self;
	};

	close FILE;
	undef $self->{'fileHandle'};

	$tmp = Audio::APETags->getTags($self->{'filename'});

	$self->{'tags'} = $tmp->{'tags'};




	return $self;
}

sub info {
	my $self = shift;
	my $key  = shift;

	# if the user did not supply a key, return a hashref
	return $self->{'info'} unless $key;

	# otherwise, return the value for the given key
	return $self->{'info'}->{$key};
}

sub tags {
	my $self = shift;
	my $key  = shift;

	# if the user did not supply a key, return a hashref
	return $self->{'tags'} unless $key;

	# otherwise, return the value for the given key
	return $self->{'tags'}->{$key};
}


# "private" methods
sub _init {
	my $self = shift;

	my $fh	 = $self->{'fileHandle'};

	# check the header to make sure this is actually a MPC file
	my $byteCount = $self->_checkHeader() || 0;

	unless ($byteCount > 0) {
		# if it's not, we can't do anything
		return -1;
	}

	$self->{'startHeaderInfo'} = $byteCount;

	return 0;
}

sub _checkHeader {
	my $self = shift;

	my $fh	 = $self->{'fileHandle'};

	# Let MP3::Info test for the existance of a ID3v2 Tag - skip past it.
	my $v2h = MP3::Info::_get_v2head($fh);

	if ($v2h && ref($v2h) eq 'HASH' && defined $v2h->{'tag_size'}) {
			
		$self->{'ID3v2Tag'} = 1;

		seek($fh, $v2h->{'tag_size'}, SEEK_SET);

	} else {

		seek($fh, 0, SEEK_SET);
	}

	# Next, check for APE tag
	my $buffer = '';
	read ($fh, $buffer, 8) or return -1;

	if ($buffer eq APEHEADERFLAG) {

		read ($fh, $buffer, 24) or return -1;
		
		# Skip the ape tag structure
		seek $fh, unpack ("L",substr($buffer, 4, 4)), 1;
	} else {
		# set the pointer back to original location
		seek $fh, -8, 1;
	}

	# Finally, we should be at the location of the musepack header.
	read ($fh, $buffer, 3) or return -1;

	if ($buffer ne MPCHEADERFLAG) {
		return -2;
	}

	# at this point, we assume the bitstream is valid
	return tell($fh);
}

sub _getAudioInfo {
	my $self = shift;

	my $fh   = $self->{'fileHandle'};

	my @profileNames = (
		'na', "Unstable/Experimental", 'na', 'na',
		'na', "below Telephone", "below Telephone", "Telephone",
		"Thumb", "Radio", "Standard", "Xtreme",
		"Insane", "BrainDead", "above BrainDead", "above BrainDead"
	);

	my @samplFreq = (44100, 48000, 37800, 32000);


	my ($buffer,$earlyVer,$encVal,$totalSamples,$totalSeconds,$tmp);

	# Seek to beginning of header information
	seek $fh, $self->{'startHeaderInfo'}, 0;

	# Start parsing the bytes
	read $fh, $buffer, 1;

	$self->{'streamVersion'} = unpack "C", $buffer;

	# Switch on this value

	# Note.  MPC uses a strange sort of bitordering/reading
	# in the source code, such that 4 bytes are read at once
	# but the bits are streamed off in reverse BYTE order.
	# Hard to follow.

	if ($self->{'streamVersion'} < 0x07) {
		# unimplemented : 0x04 to 0x06 streamVersion...yet...

	} elsif ($self->{'streamVersion'} <= 0x17) {

		$self->{'bitRate'}        = 0;
		$self->{'channels'}       = 2;

		read $fh, $buffer, 4;
		$self->{'totalFrames'} = unpack "L", $buffer;

		read $fh, $buffer, 4;
		$buffer = _getWord($buffer);

		$self->{'profile'}          = $profileNames[_bin2dec(substr($buffer, 8, 4))];
		$self->{'sampleFreq'}       = $samplFreq   [_bin2dec(substr($buffer, 14, 2))];

		read $fh, $buffer, 12;
		$buffer = _getWord(substr($buffer,8));
		$self->{'lastValidSamples'} = _bin2dec(substr($buffer, 1, 11));

		read $fh, $buffer, 4;
		$buffer = _getWord($buffer);
		$encVal = _bin2dec(substr($buffer, 0, 8));

	} else {
		# unimplemented : 0xF7 or 0xFF streamVersion...yet...
	}


	# Calculate the track times
	$totalSamples = ($self->{'totalFrames'}-1)*32*36 + $self->{'lastValidSamples'};
	$self->{'trackTotalLengthSeconds'} = $totalSamples/$self->{'sampleFreq'};
	$totalSeconds = $self->{'trackTotalLengthSeconds'};

	$tmp = $totalSamples/$self->{'sampleFreq'}*75;
	$self->{'trackLengthFrames'} = $tmp % 75;

	$tmp -= $self->{'trackLengthFrames'};

	$self->{'trackLengthSeconds'} = ($tmp / 75) % 60;
	$tmp -= $self->{'trackLengthSeconds'};

	$self->{'trackLengthMinutes'} =  $tmp / (75*60);

	$self->{'bitRate'}            = 8 * ($self->{'fileSize'} - $self->{'startHeaderInfo'}) / $totalSeconds;

	if ($encVal<=0) {
		$self->{'encoder'} = '';
	} elsif ( ($encVal % 10) == 0) {
		$self->{'encoder'} = "(Release " . int($encVal/100) . "." . (int($encVal/10) % 10) . ")";
	} elsif ( ($encVal & 1 ) == 0) {
		$self->{'encoder'} = sprintf("(Beta %u.%02u)", int($encVal/100), $encVal % 100);
	} else {
		$self->{'encoder'} = "(Alpha " . int($encVal/100) . "." . ($encVal % 100) . ")";
	}

	return 0;
}

sub _getWord {
	my $inWord = shift;
	# Read in four bytes in reverse order, convert to binary
	my $outWord = '';

	for (my $c=0; $c<4; $c++) {
		$outWord .= unpack "B8", substr($inWord, 3-$c, 1);
	}
	
	return $outWord;
}

sub _bin2dec {
	# Freely swiped from Perl Cookbook p. 48 (May 1999)
	return unpack ('N', pack ('B32', substr(0 x 32 . shift, -32)));
}

sub _grabInt32 {
	# Pulls a little-endian unsigned int from a string and returns the remainder
	my $data  = shift;
	my $value = unpack('L',substr($$data,0,4));
	$$data    = substr($$data,4);
	return $value;
}

sub _packInt32 {
	# Packs an integer into a little-endian 32-bit unsigned int
	return pack('L',shift)
}

1;

__END__

=head1 NAME

Audio::Musepack - An object-oriented interface to Musepack file information
and APE tag fields, implemented entirely in Perl.

=head1 SYNOPSIS

	use Audio::Musepack;
	my $mpc = Audio::Musepack->new("song.mpc");

	my $mpcInfo = $mpc->info();

	foreach (keys %$mpcInfo) {
		print "$_: $mpcInfo->{$_}\n";
	}

	my $mpcTags = $mpc->tags();

	foreach (keys %$mpcTags) {
		print "$_: $mpcTags->{$_}\n";
	}

=head1 DESCRIPTION

This module returns a hash containing basic information about a Musepack
file, as well as tag information contained in the Musepack file's APE tags.
See Audio::APETags for more information about the tags.

The information returned by Audio::FLAC::info is keyed by:

	streamVersion
	channels
	totalFrames
	profile
	sampleFreq
	lastValidSamples
	encoder

Information stored in the main hash that relates to the file itself or is
calculated from some of the information fields is keyed by:

	trackLengthMinutes      : minutes field of track length
	trackLengthSeconds      : seconds field of track length
	trackLengthFrames       : frames field of track length (base 75)
	trackTotalLengthSeconds : total length of track in fractional seconds
	bitRate                 : average bits per second of file
	fileSize                : file size, in bytes
	filename                : filename with path

=head1 CONSTRUCTORS

=head2 C<new ($filename)>

Opens a Musepack file, ensuring that it exists and is actually an
Musepack stream, then loads the information and comment fields.

=head1 INSTANCE METHODS

=head2 C<info ([$key])>

Returns a hashref containing information about the Murepack file from
the file's information header.

The optional parameter, key, allows you to retrieve a single value from
the info hash.  Returns C<undef> if the key is not found.

=head2 C<tags ([$key])>

Returns a hashref containing tag keys and values of the Musepack file from
the file's APE tags.

The optional parameter, key, allows you to retrieve a single value from
the tag hash.  Returns C<undef> if the key is not found.

=head1 SEE ALSO

L<http://www.personal.uni-jena.de/~pfk/mpp/index2.html>

=head1 AUTHOR

Erik Reckase, E<lt>cerebusjam at hotmail dot comE<gt>, with lots of help
from Dan Sully, E<lt>daniel@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright (c) 2003-2006, Erik Reckase.
Copyright (c) 2003-2006, Dan Sully & Logitech.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=cut



