package Slim::Display::Graphics;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use File::Spec::Functions qw(catdir);
use FindBin qw($Bin);

use Slim::Buttons::Common;
use Slim::Utils::Misc;

my %fonts;

sub init {
	%fonts = ();
	loadFonts();
}

sub string {
	use bytes;
	my $bits = '';
	my $fontname = shift;
	my $string = shift;
	
	return '' if (!$fontname || !defined($string));

	my $font = $fonts{$fontname};
	
	if (!$font) {
		msg(" Invalid font $fontname\n"); 
		return '';
	};
	
	my $interspace = $font->[0];
	my $cursorpos = undef;
	my $cursorend = 0;
	foreach my $char (split(//, $string)) {
		if ($char eq "\x1d") { 
			$interspace = ''; 
		} elsif ($char eq "\x1c") {
			$interspace = $font->[0]; 
		} elsif ($char eq "\x0a") {
			$cursorpos = length($bits);
		} else {
			if (defined($cursorpos) && !$cursorend) { 
				$cursorend = length($font->[ord($char)])/2; 
			}
			$bits .= $font->[ord($char)] . $interspace;
		}
	}
	
	if (defined($cursorpos)) {
		$bits |= (chr(0) x $cursorpos) . ($font->[ord("\x0a")] x $cursorend);
	}
		
	return $bits;
}

sub measureText {
	use bytes;
	my $fontname = shift;
	my $string = shift;
	my $bits = string($fontname, $string);
	my $len = length($bits)/2;
	
	return $len;
}
	
sub graphicsDirs {
	my @dirs;
	
	push @dirs, catdir($Bin,"Graphics");
	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		push @dirs, $ENV{'HOME'} . "/Library/SlimDevices/Graphics/";
		push @dirs, "/Library/SlimDevices/Graphics/";
	}
	return @dirs;
}


#returns a reference to a hash of filenames/external names
sub fontfiles {
	my %fontfilelist = ();
	foreach my $fontfiledir (graphicsDirs()) {
		if (opendir(DIR, $fontfiledir)) {
			foreach my $fontfile ( sort(readdir(DIR)) ) {
				if ($fontfile =~ /(.+)\.font.bmp$/) {
					$::d_graphics && msg(" fontfile entry: $fontfile\n");
					$fontfilelist{$1} = catdir($fontfiledir, $fontfile);
				}
			}
			closedir(DIR);
		}
	}
	return %fontfilelist;
}

sub loadFonts {
	my %fontfiles = fontfiles();
	
	foreach my $font (keys %fontfiles) {

		$::d_graphics && msg( "Now parsing: $font\n");

		my $fontgrid = parseBMP($fontfiles{$font});
		
		my $fonttable = parseFont($fontgrid);

		$fonts{$font} = $fonttable;
	}
	return;
}

# parse the array of pixels ino a font table
sub parseFont {
	use bytes;
	my $g = shift;
	my $fonttable;
	
	my $bottomIndex = scalar(@{$g}) - 1;
	
	my $bottomRow = $g->[$bottomIndex];
	
	my $width = @{scalar($bottomRow)};
	
	my $charIndex = -1;
	
	for (my $i = 0; $i < $width; $i++) {
		#print "\n";
		next if ($bottomRow->[$i]);
		last if (!defined($bottomRow->[$i]));
		$charIndex++;

		my @column = ();
		while (!$bottomRow->[$i]) {
			for (my $j = 0; $j < $bottomIndex; $j++) {
				push @column, $g->[$j][$i]; 
				#print  $g->[$j][$i] ? '*' : ' ';
			}
			#print "\n";
			$i++;
		}
		$fonttable->[$charIndex] = pack("B*", join('',@column));
		#print $charIndex . " " . chr($charIndex) . " " . scalar(@column) . " ". length($fonttable->[$charIndex]) . " i: $i width: $width\n";
	}
	#print "done fonttable\n";
	return $fonttable;
	
}

# parses a monochrome, uncompressed BMP file into an array for font data
sub parseBMP {
	use bytes;
	my $fontfile = shift;
	my $fontstring;
	my @font;
	
	# slurp in bitmap file
	{
		use bytes;
		local( $/ );
		my $fh;
		if (!open($fh, $fontfile ))
			{ 
				msg(" couldn't open fontfile $fontfile\n"); 
				return undef;
			}
		binmode $fh;
		$fontstring = <$fh>;
	}
	
	my ($type, $fsize, $offset, 
	    $biSize, $biWidth, $biHeight, $biPlanes, $biBitCount, $biCompression, $biSizeImage  ) 
		= unpack("a2 V xx xx V  V V V v v V V xxxx xxxx xxxx xxxx", $fontstring);
	
	if ($type ne "BM") { msg(" No BM header on $fontfile\n"); return undef; }
	if ($fsize ne -s $fontfile) { msg(" Bad size in $fontfile\n"); return undef; }
	if ($biPlanes ne 1) { msg(" Planes must be one, not $biPlanes in $fontfile\n"); return undef; }
	if ($biBitCount ne 1) { msg(" Font files must be one bpp, not $biBitCount in $fontfile\n"); return undef; }
	if ($biCompression ne 0) { msg(" Font files must be uncompressed in $fontfile\n"); return undef; }
	
	# skip over the BMP header and the color table
	$fontstring = substr($fontstring, $offset);
	
	my $bitsPerLine = $biWidth - ($biWidth % 32);
	$bitsPerLine += 32 if ($biWidth % 32); # round up to 32 pixels wide

	for (my $i = 0 ; $i < $biHeight; $i++) {
		my @line = split( //, substr(unpack( "B$bitsPerLine", substr($fontstring, $i * $bitsPerLine / 8) ), 0,$biWidth));
		$font[$biHeight-$i-1] = \@line;
	}	

	return \@font;
}

1;


__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
