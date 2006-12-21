package Slim::Display::Lib::Fonts;

# SlimServer Copyright (c) 2001-2006 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# $Id$
#

=head1 NAME

Slim::Display::Lib::Fonts

=head1 DESCRIPTION

Library functions to provide bitmapped fonts for graphics displays.

=over 4

=item * Parses bitmaps into font data structure and stores as fontcache

=item * Returns bitmap render of a specific string

=item * Supports Unicode characters via True Type

=item * Supports Hebrew via L<Locale::Hebrew>

=back

=cut

use strict;

use File::Slurp;
use File::Basename;
use File::Spec::Functions qw(catdir);
use List::Util qw(max);
use Path::Class;
use Storable;
use Tie::Cache::LRU;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;

our $fonts;
our $fonthash;
our $fontheight;
our $fontextents;

my $char0 = chr(0);
my $ord0a = ord("\x0a");

my $maxLines = 3; # Max lines any display will render

# TrueType support by using GD
my $canUseGD = eval {
	require GD;
	return 1;
};

# Hebrew support
my $canUseHebrew = eval {
	require Locale::Hebrew;
	return 1;
};

my $gdError = $@;

my ($gd, $GDBlack, $GDWhite, $TTFFontFile, $useTTFCache, $useTTF);

# Keep a cache of up to 256 characters at a time.
tie my %TTFCache, 'Tie::Cache::LRU', 256;

# Bug 3535 - perl < 5.8.5 uses a different Bidi property class.
my $bidiR = ($] <= 5.008004) ? qr/\p{BidiR}/ : qr/\p{BidiClass:R}/;
my $bidiL = ($] <= 5.008004) ? qr/\p{BidiL}/ : qr/\p{BidiClass:L}/;

# Font size & Offsets -- Optimized for the free Japanese TrueType font
# 'sazanami-gothic' from 'waka'.
#
# They seem to work pretty well for CODE2000 & Cyberbit as well. - dsully

my %font2TTF = (

	# The standard size - .1 is top line, .2 is bottom.
	'standard.1' => {
		'GDFontSize' => 9,
		'GDBaseline' => 8,
	},

	'standard.2' => {
		'GDFontSize' => 17,
		'GDBaseline' => 28,
	},

	 # Small size - .1 is top line, .2 is bottom.
	'light.1' => {
		'GDFontSize' => 10,
		'GDBaseline' => 10,
	},

	'light.2' => {
		'GDFontSize' => 11,
		'GDBaseline' => 29,
	},

	# Huge - only one line.
	'full.2' => {
		'GDFontSize' => 26,
		'GDBaseline' => 25,
	},

	# text for push on/off in fullscreen visu.
	'high.2' => {
		'GDFontSize' => 7,
		'GDBaseline' => 7,
	},
);

# When using TTF to replace the following fonts, the string is has uc() run on it first
my %font2uc = ( 
	'standard.1' => 1,
);

my $log = logger('player.graphics');

sub init {
	loadFonts();

	$log->info(sprintf("Trying to load GD Library for TTF support: %s", $canUseGD ? 'ok' : 'not ok!'));

	if ($canUseGD) {

		FONTDIRS:
		for my $fontFolder (graphicsDirs()) {

			# Initialize an image for working (1 character=32x32) and some variables...
			# Try a few different fonts..
			for my $fontFile (qw(arialuni.ttf ARIALUNI.TTF CODE2000.TTF Cyberbit.ttf CYBERBIT.TTF)) {
		
				$TTFFontFile = catdir($fontFolder, $fontFile);

				if ($canUseGD && -e $TTFFontFile) {
					$useTTF = 1;
					last FONTDIRS;
				}
			}
		}
	
		if ($useTTF) {

			$log->info("Using TTF for Unicode on Player Display. Font: [$TTFFontFile]");
	
			$useTTFCache = 1;
			%TTFCache    = ();
	
			# This should be configurable.
			$gd = eval { GD::Image->new(32, 32) };
	
			if ($gd) {

				$GDWhite = $gd->colorAllocate(255,255,255);
				$GDBlack = $gd->colorAllocate(0,0,0);

			} else {

				$useTTF = 0;

			}
		}	

	} else { 

		$log->info("Error while trying to load GD Library: [$gdError]");
	}
}

sub gfonthash {
	return $fonthash;
}

sub fontnames {
	my @fontnames;
	foreach my $gfont (keys %{$fonthash}) {
		my $fontname = $fonthash->{$gfont}->{line}[1];
		$fontname =~ s/(\.2)?//g;
		push @fontnames, $fontname;
	}
	return \@fontnames;
};

sub fontheight {
	my $fontname = shift;
	return $fontheight->{$fontname};
}

sub fontchars {
	my $fontname = shift;
	my $font = $fonts->{$fontname} || return 0;
	return scalar(@$font);
}

# extent returns the number of rows high a font is rendered (useful for vertical scrolling)
# based on char 0x1f, which is a bitmask of the valid rows.
# negative values are for top-row fonts
sub extent {
	my $fontname = shift;

	if (defined $fontname && exists $fontextents->{$fontname}) {

		return $fontextents->{$fontname};
	}

	return 0;
}

sub loadExtent {
	my $fontname = shift;

	my $extentbytes = string($fontname, chr(0x1f));	
	
	# count the number of set bits in the extent bytes (up to 32)
	my $extent = unpack( '%32b*', $extentbytes ); 
	
	if ($fontname =~ /\.1/) { $extent = -$extent; }
	
	$fonts->{extents}->{$fontname} = $extent;
	
	$log->debug(" extent of: $fontname is $extent");
}

sub string {
	my $defaultFontname = shift || return (0, '');
	my $string = shift || return (0, '');

	my $defaultFont = $fonts->{$defaultFontname} || do {

		logBacktrace(" Invalid font $defaultFontname");
		return (0, '');
	};

	my ($GDFontSize, $GDBaseline);
	my $useTTFNow = 0;
	my $reverse = 0; # flag for whether the text was reversed (Bidi:R)

	if ($useTTF && defined $font2TTF{$defaultFontname}) {
		$useTTFNow  = 1;
		$GDFontSize = $font2TTF{$defaultFontname}->{'GDFontSize'};
		$GDBaseline = $font2TTF{$defaultFontname}->{'GDBaseline'};
	}

	# U - unpacks Unicode chars into ords, much faster than split(//, $string)
	# C - is needed for older 5.6 perl's
	my $unpackTemplate = ($] > 5.007) ? 'U*' : 'C*';

	my @ords = unpack($unpackTemplate, $string);

	if (max(@ords) > 255) {

		if ($useTTFNow) {

			# convert to upper case if fontname is in list of uc fonts
			if ($font2uc{$defaultFontname}) {
				$string = uc($string);
				@ords = ();
			}

			# flip BiDi R text and decide if scrolling should be reversed
			if ($canUseHebrew && $string =~ $bidiR) {
				$reverse = ($string !~ $bidiL);
				$string = Locale::Hebrew::hebrewflip($string);
				@ords = ();
			}
			@ords = unpack($unpackTemplate, $string) unless @ords;

		} else {

			# fall back to transliteration for people who don't have the font installed.
			@ords = unpack($unpackTemplate, Slim::Utils::Unicode::utf8toLatin1Transliterate($string));
		}
	}

	my $bits = '';
	my $fontChange = 0;
	my $tight = 0;
	my $newFontname = '';
	my $font = $defaultFont;
	my $interspace = $defaultFont->[0];
	my $cursorpos = undef;
	my $cursorend = 0;

	# special characters:
	# \x1d [29] = 'tight'  - suppress inter character space
	# \x1c [28] = '/tight' - turn on inter character space [default]
	# \x1b [27] = font change - new fontname enclosed in \x1b chars, null name = back to default font
	# \x0a [10] = 'cursorpos' - set cursor for next character

	for my $ord (@ords) {

		if ($fontChange) {

			if ($ord == 27) {

				# end of new font definition - switch font
				$font = $fonts->{$newFontname} || $defaultFont;
				$interspace = $tight ? '' : $font->[0];
				$fontChange = 0;
				$newFontname = '';

			} else {

				$newFontname .= chr($ord);

			}

		} elsif ($ord == 27) {

			$fontChange = 1;

		} elsif ($ord == 29) { 

			$interspace = '';
			$tight = 1;

		} elsif ($ord == 28) {

			$interspace = $font->[0];
			$tight = 0;

		} elsif ($ord == 10) {

			$cursorpos = length($bits);

		} else {

			if ($ord > 255 && $useTTFNow) {

				my $bits_tmp = $useTTFCache ? $TTFCache{$defaultFontname}{$ord} : '';

				unless ($bits_tmp) {

					$bits_tmp = '';

					# Create our canvas.
					$gd->filledRectangle(0, 0, 31, 31, $GDWhite);

					# Using a negative color index will
					# disable anti-aliasing, as described
					# in the libgd manual page at
					# http://www.boutell.com/gd/manual2.0.9.html#gdImageStringFT.
					#
					
					# GD doesn't at present support characters with 6 or more digits
					if ($ord >= 99999) {
						$ord = 0x25af; # 0x25af  = 'White Vertical Rectangle'
					}
					
					my @GDBounds = $gd->stringFT(-1*$GDBlack, $TTFFontFile, $GDFontSize, 0, 0, $GDBaseline, "&#${ord};");

					# Construct the bitmap
					for (my $x = 0; $x <= $GDBounds[2]; $x++) {

						for (my $y = 0; $y < 32; $y++) {

							$bits_tmp .= $gd->getPixel($x,$y) == $GDBlack ? 1 : 0
						}
					}

					$bits_tmp = pack("B*", $bits_tmp);

					$TTFCache{$defaultFontname}{$ord} = $bits_tmp if $useTTFCache;
				}

				if (defined($cursorpos) && !$cursorend) { 
					$cursorend = length($bits_tmp) / length($defaultFont->[$ord0a]);
				}

				$bits .= $bits_tmp;

			} else {

				# We don't handle anything outside ISO-8859-1
				# right now in our non-TTF bitmaps.
				if ($ord > 255 || !defined $ord) {
					$ord = 63; # 63 == '?'
				}

				if (defined($cursorpos) && !$cursorend) { 

					$cursorend = length($font->[$ord]) / length($font->[$ord0a]); 
				}

				$bits .= $font->[$ord] . $interspace;
			}
		}
	}

	if (defined($cursorpos)) {

		$bits |= ($char0 x $cursorpos) . ($font->[$ord0a] x $cursorend);
	}
		
	return ($reverse, $bits);
}

sub measureText {
	my $fontname = shift;
	my $string = shift;
	my $bits = string($fontname, $string);
	return 0 if (!$fontname || !$fontheight->{$fontname});
	my $len = length($bits)/($fontheight->{$fontname}/8);
	
	return $len;
}
	
sub graphicsDirs {

	# graphics files allowed in Graphics dir and root directory of plugins
	return (
		Slim::Utils::OSDetect::dirsFor('Graphics'), 
		Slim::Utils::PluginManager->pluginRootDirs(), 
	); 
}

sub fontCacheFile {
	return catdir( Slim::Utils::Prefs::get('cachedir'), 
		Slim::Utils::OSDetect::OS() eq 'unix' ? 'fontcache' : 'fonts.bin');
}

# returns a hash of filenames/external names and newest modification time
sub fontfiles {
	my %fonts  = ();
	my $newest = 0;

	for my $fontFileDir (graphicsDirs()) {

		if (!-d $fontFileDir) {
			next;
		}

		my $dir = dir($fontFileDir);

		while (my $fileObj = $dir->next) {

			my $file = $fileObj->stringify;

			if ($file =~ /[\/\\](.+?)\.font\.bmp$/) {

				$fonts{basename($1)} = $file;

				my $moddate = (stat($file))[9]; 

				if ($moddate > $newest) {
					$newest = $moddate;
				}

				$log->debug(" found: $file");
			}
		}
	}

	return ($newest, %fonts);
}

sub loadFonts {
	my $forceParse = shift;

	my ($newest, %fontfiles) = fontfiles();
	my $fontCache = fontCacheFile();

	my $fontCacheVersion = 1; # version number of fontcache matching this code

	# use stored fontCache if newer than all font files and correct version
	if (!$forceParse && -r $fontCache && ($newest < (stat($fontCache))[9])) { 

		# check cache for consitency
		my $cacheOK = 1;

		$log->info("Retrieving font data from font cache: $fontCache");

		eval { $fonts = retrieve($fontCache); };

		if ($@) {
			$log->warn("Tried loading fonts: $@");
		}

		if (!$@ && defined $fonts && defined($fonts->{hash}) && defined($fonts->{height}) && defined($fonts->{extents})) {
			$fonthash    = $fonts->{hash};
			$fontheight  = $fonts->{height};
			$fontextents = $fonts->{extents};
		} else {
			$cacheOK     = 0;
		}

		# check for font files being removed
		for my $font (keys %{$fontheight}) {

			if (!exists($fontfiles{$font})) {
				$cacheOK = 0;
			}
		}

		# check for new fonts being added (with old modification date)
		for my $font (keys %fontfiles) {

			if (!exists($fontheight->{$font})) {
				$cacheOK = 0;
			}
		}

		# check for version of fontcache
		if (!$fonts->{version} || !$fontCacheVersion || $fonts->{version} != $fontCacheVersion) {

			$cacheOK = 0;
		}

		return if $cacheOK;

		$log->info("Font cache contains old data - reparsing fonts");
	}

	# otherwise clear data and parse all font files
	$fonts = {};

	foreach my $font (keys %fontfiles) {

		$log->debug("Now parsing: $font");

		my ($fontgrid, $height) = parseBMP($fontfiles{$font});

		$log->debug(" height of: $font is " . ($height - 1));

		# store height and then skip font if never seen a player requiring it
		$fonts->{'height'}->{$font} = $height - 1;

		next if ($height == 17 && !Slim::Utils::Prefs::get('loadFontsSqueezeboxG'));
		next if ($height == 33 && !Slim::Utils::Prefs::get('loadFontsSqueezeboxII'));

		$log->debug("loading...");

		if ($font =~ m/(.*?).(\d)/i) {
			$fonts->{hash}->{$1}->{line}[$2-1] = $font;
			$fonts->{hash}->{$1}->{overlay}[$2-1] = $font;
			$fonts->{hash}->{$1}->{center}[$2-1] = $font;
		}

		$fonts->{$font} = parseFont($fontgrid);
		$fonts->{extent}->{$font} = loadExtent($font);
	}

	$fonthash    = $fonts->{'hash'};
	$fontheight  = $fonts->{'height'};
	$fontextents = $fonts->{'extents'};

	$log->info("Writing font cache: $fontCache");

	$fonts->{'version'} = $fontCacheVersion;

	store($fonts, $fontCache);
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
		if ($charIndex == 0 && unpack( '%32b*', $fonttable->[$charIndex]) > 0) {
			# pixels in interspace character indicate no interspace
			$fonttable->[$charIndex] = '';
		}
	}
	#print "done fonttable\n";
	return $fonttable;
	
}

# parses a monochrome, uncompressed BMP file into an array for font data
sub parseBMP {
	my $fontfile = shift;

	use bytes;

	# slurp in bitmap file
	my $fontstring = read_file($fontfile);
	my @font       = ();

	my ($type, $fsize, $offset, 
	    $biSize, $biWidth, $biHeight, $biPlanes, $biBitCount, $biCompression, $biSizeImage, $biFirstPaletteEntry ) 
		= unpack("a2 V xx xx V  V V V v v V V xxxx xxxx xxxx xxxx V", $fontstring);

	if ($type ne "BM") {

		$log->warn("No BM header on $fontfile");
		return undef;
	}

	if ($fsize != -s $fontfile) {

		$log->warn("Bad size in $fontfile");
		return undef;
	}

	if ($biPlanes != 1) {

		$log->warn("Planes must be one, not $biPlanes in $fontfile");
		return undef;
	}

	if ($biBitCount != 1) {

		$log->warn("Font files must be one bpp, not $biBitCount in $fontfile");
		return undef;
	}

	if ($biCompression != 0) {

		$log->warn("Font files must be uncompressed in $fontfile");
		return undef;
	}
	
	# skip over the BMP header and the color table
	$fontstring = substr($fontstring, $offset);
	
	my $bitsPerLine = $biWidth - ($biWidth % 32);
	$bitsPerLine += 32 if ($biWidth % 32); # round up to 32 pixels wide

	for (my $i = 0 ; $i < $biHeight; $i++) {

		my @line = ();

		my $bitstring = substr(unpack( "B$bitsPerLine", substr($fontstring, $i * $bitsPerLine / 8) ), 0,$biWidth);
		my $bsLength  = length($bitstring);

		# Surprisingly, this loop is about 20% faster than doing split(//, $bitString)
		if ($biFirstPaletteEntry == 0xFFFFFF) {

			# normal palette
			for (my $j = 0; $j < $bsLength; $j++) {
				$line[$j] = substr($bitstring, $j, 1);
			}

		} else {

			# reversed palette
			for (my $j = 0; $j < $bsLength; $j++) {
				$line[$j] = substr($bitstring, $j, 1) ? 0 : 1;
			}
		}

		$font[$biHeight-$i-1] = \@line;
	}	

	return (\@font, $biHeight);
}

=head1 SEE ALSO

L<GD>

=cut

1;

__END__
