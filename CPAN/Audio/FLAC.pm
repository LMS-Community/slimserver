package Audio::FLAC;

# $Id: FLAC.pm,v 1.1 2003/11/29 01:03:25 daniel Exp $

use strict;
use base qw(Exporter);

use vars qw($VERSION @EXPORT);

@EXPORT  = qw(readFlacTag);
$VERSION = '0.02';

use constant LASTBLOCKFLAG  => 1 << 31;
use constant BLOCKTYPEFLAG  => 127 << 24;
use constant MLENFLAG	    => 255 + 256*255 + 256*256*255;

use constant FLACHEADERFLAG => 'fLaC';

use constant STREAMINFO	    => 0;
use constant PADDING	    => 1;
use constant VORBIS_COMMENT => 4;

use constant DEBUG => 0;

# Only argument is filename, with full path
sub readFlacTag {
	my $filename = shift;

	my $flacInfo = {};

	open(FLACFILE,$filename) or return -1;
	binmode FLACFILE;

	read(FLACFILE, my $flacFlag, 4) or return -1;

	# this isn't a flac file.
	if ($flacFlag ne FLACHEADERFLAG) {
		close FLACFILE;
		return -1;
	}

	# grab the header and read vorbis info.
	while(1) {

		read(FLACFILE, my $tmp, 4) or return -1;
		my $metaHead = unpack('N', $tmp);

		# What's the info stored here?
		my $metaLast = (LASTBLOCKFLAG & $metaHead) >> 31;
		my $metaType = (BLOCKTYPEFLAG & $metaHead) >> 24;
		my $metaSize = MLENFLAG & $metaHead;

		if (DEBUG) {
			print "metaHead: [$metaHead]\n";
			print "metaLast: [$metaLast]\n";
			print "metaType: [$metaType]\n";
			print "metaSize: [$metaSize]\n\n";
		}

		read(FLACFILE, my $metaContents, $metaSize) or return -1;

		# see http://flac.sourceforge.net/format.html	
		if ($metaType == STREAMINFO) {
			_calculateTrackInfo($metaContents, $flacInfo);
		}

		# XXX - do we care about any of the other metadata?
		# cuesheet maybe

		if ($metaType == VORBIS_COMMENT) {
			_readVorbisHeader($metaContents, $flacInfo);
		}

		# we've reached the end of our metadata headers
		last if $metaLast;
	}

	close FLACFILE;

	return $flacInfo;
}

# private here on out

# it'd be nice to reuse Ogg::Vorbis::Header, but the API is different.
sub _readVorbisHeader {
	my $metaContents = shift;
	my $flacInfo	 = shift;

	my $vendorLength = _bin2long(\$metaContents);

	$flacInfo->{'VENDOR'} = substr($metaContents,0,$vendorLength);
	$metaContents	      = substr($metaContents,$vendorLength);

	my $numTags	 = _bin2long(\$metaContents);

	for (my $i = 0; $i < $numTags; $i++) {

		my $lnlen     = _bin2long(\$metaContents);

		my $lnstr     = substr($metaContents,0,$lnlen);
		$metaContents = substr($metaContents,$lnlen);

		if ($lnstr =~ /^(.*?)=(.*)$/) {
			my $key = $1;
			$key =~ tr/a-z/A-Z/;
			$flacInfo->{$key} = $2;
		}
	}
}

sub _calculateTrackInfo {
	my $metaContents   = shift;
	my $flacInfo	   = shift;

	# skip over min & max blocksize, framesize. useless.
	my $metaString	   = unpack('B64', substr($metaContents, 10));

	# these offsets all come from flac.sourceforge.net/format.html
	my $sampleRate	   = _bin2dec(substr($metaString,0,20));
	my $channels	   = _bin2dec(substr($metaString,20,3));
	my $bitsPerSample  = _bin2dec(substr($metaString,23,5)); 

	# since perl can't read a 36bit number, pull off the first 4 bits, and
	# multiple later
	my $sampleMulitple = _bin2dec(substr($metaString,28,4));
	my $totalSamples   = _bin2dec(substr($metaString,32,36));

	$totalSamples	   = $sampleMulitple*(2^32) + $totalSamples;

	my $sampleRatio	   = int($totalSamples/$sampleRate);

	# frames is base 75
	my $frames	   = int((($totalSamples/$sampleRate) - $sampleRatio) * 75);

	$flacInfo->{'TRACKLENGTH'}   = $totalSamples / $sampleRate;
	$flacInfo->{'SAMPLES'}	     = $totalSamples;
	$flacInfo->{'MM'}	     = int($sampleRatio / 60);
	$flacInfo->{'SS'}	     = $sampleRatio % 60;
	$flacInfo->{'FRAMES'}	     = $frames;
	$flacInfo->{'SAMPLERATE'}    = $sampleRate;
	$flacInfo->{'CHANNELS'}	     = $channels + 1;
	$flacInfo->{'BITSPERSAMPLE'} = $bitsPerSample + 1;
}

sub _bin2long {
	my $data = shift;
	my $long = unpack('L', substr($$data, 0, 4));
	$$data = substr($$data, 4);
	return $long;
}

# See perl cookbook page 48.
sub _bin2dec {
	return unpack('N', pack('B32',substr(0 x 32 . shift, -32)));
}

1;

__END__

=head1 NAME

Audio::FLAC - Perl extension for reading FLAC Tags

=head1 SYNOPSIS

  use Audio::FLAC;

  my $tag = get_flacTag($filename);

=head1 DESCRIPTION

Returns a hash reference of tags found in a FLAC file.

=head2 EXPORT

get_flacTag()

=head1 SEE ALSO

L<http://flac.sourceforge.net/format.html>

=head1 AUTHOR

Dan Sully, E<lt>daniel@cpan.orgE<gt> based off of code from 
Erik Reckase E<lt>cerebusjam at hotmail dot comE<gt>, used with permission.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2003 by Dan Sully

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=cut
