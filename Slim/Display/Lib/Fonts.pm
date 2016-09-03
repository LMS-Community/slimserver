package Slim::Display::Lib::Fonts;

# Logitech Media Server Copyright 2001-2011 Logitech.
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
use File::Spec::Functions qw(catdir catfile);
use List::Util qw(max);
use Path::Class;
use Storable qw(nstore retrieve);
use Tie::Cache::LRU;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::OSDetect;
use Slim::Utils::Prefs;

use constant FT_RENDER_MODE_MONO => 2;

my $prefs = preferences('server');

my $log = logger('player.fonts');

our $fonts;
our $fonthash;
our $fontheight;
our $fontextents;

my $char0 = chr(0);
my $ord0a = ord("\x0a");

my $maxLines = 3; # Max lines any display will render

# Keep a cache of measure text results to avoid calling string which is expensive
my %measureTextCache;

# Hebrew support
my $hasHebrew;
my $canUseHebrew = sub {
	return $hasHebrew if defined $hasHebrew;
	main::DEBUGLOG && $log->debug('Loading Locale::Hebrew');
	eval { require Locale::Hebrew };
	if ($@) {
		logWarning("Unable to load Hebrew support: $@");
	}
	$hasHebrew = $@ ? 0 : 1;
	return $hasHebrew;
};

my $hasFreeType;
my $canUseFreeType = sub {
	return $hasFreeType if defined $hasFreeType;
	main::DEBUGLOG && $log->debug('Loading Font::FreeType');
	eval { require Font::FreeType };
	if ($@) {
		logWarning("Unable to load TrueType font support: $@");
	}
	$hasFreeType = $@ ? 0 : 1;
	return $hasFreeType;
};

my ($ft, $TTFFontFile);

# Keep a cache of up to 256 characters at a time.
tie my %TTFCache, 'Tie::Cache::LRU', 256;
%TTFCache = ();

# template for unpacking strings: U - unpacks Unicode chars into ords, C - is needed for 5.6 perl's
my $unpackTemplate = ($] > 5.007) ? 'U*' : 'C*';

my $bidiR = qr/\p{BidiClass:R}/;
my $bidiL = qr/\p{BidiClass:L}/;

# Font size & Offsets -- Optimized for the free Japanese TrueType font
# 'sazanami-gothic' from 'waka'.
#
# They seem to work pretty well for CODE2000 & Cyberbit as well. - dsully

my %font2TTF = (

	# The standard size - .1 is top line, .2 is bottom.
	'standard.1' => {
		'FTFontSize' => 9, # Code2000: max ascender 14, max descender 4
		'FTBaseline' => 8,
	},

	'standard.2' => {
		'FTFontSize' => 14, # Code2000: max ascender 19, max descender 6
		'FTBaseline' => 28,
	},

	 # Small size - .1 is top line, .2 is bottom.
	'light.1' => {
		'FTFontSize' => 10, # Code2000: max ascender 14, max descender 4
		'FTBaseline' => 10,
	},

	'light.2' => {
		'FTFontSize' => 11, # Code2000: max ascender 15, max descender 5
		'FTBaseline' => 29,
	},

	# Huge - only one line.
	'full.2' => {
		'FTFontSize' => 24, # Code2000: max ascender 32, max descender 10
		'FTBaseline' => 25,
	},

	# text for push on/off in fullscreen visu.
	'high.2' => {
		'FTFontSize' => 7,
		'FTBaseline' => 7,
	},
);

# narrow fonts for Boom
$font2TTF{'standard_n.1'} = $font2TTF{'standard.1'};
$font2TTF{'standard_n.2'} = $font2TTF{'standard.2'};
$font2TTF{'light_n.1'}    = $font2TTF{'light.1'};
$font2TTF{'light_n.2'}    = $font2TTF{'light.2'};
$font2TTF{'full_n.2'}     = $font2TTF{'full.2'};


# When using TTF to replace the following fonts, the string is has uc() run on it first
my %font2uc = ( 
	'standard.1'   => 1,
	'standard_n.1' => 1,
);

# Our bitmap fonts are actually cp1252 (Windows-Latin1), NOT iso-8859-1.
# The cp1252 encoding has 27 printable characters in the range [\x80-\x9F] .
# In iso-8859-1, this range is occupied entirely by non-printing control codes.
# The Unicode codepoints for the characters in this range are > 255, so instead
# of displaying these characters with our bitmapped font, the code in this
# sub will normally either replace them with characters from a TTF font
# (if present) or transliterate them into the range [\x00-\x7F] .
#
# To prevent this (and allow our full bitmap font to be used whenever
# possible), the following remaps the affected Unicode codepoints to their
# locations in cp1252.
my %cp1252mapping = (
	"\x{0152}" => "\x8C",  # LATIN CAPITAL LIGATURE OE
	"\x{0153}" => "\x9C",  # LATIN SMALL LIGATURE OE
	"\x{0160}" => "\x8A",  # LATIN CAPITAL LETTER S WITH CARON
	"\x{0161}" => "\x9A",  # LATIN SMALL LETTER S WITH CARON
	"\x{0178}" => "\x9F",  # LATIN CAPITAL LETTER Y WITH DIAERESIS
	"\x{017D}" => "\x8E",  # LATIN CAPITAL LETTER Z WITH CARON
	"\x{017E}" => "\x9E",  # LATIN SMALL LETTER Z WITH CARON
	"\x{0192}" => "\x83",  # LATIN SMALL LETTER F WITH HOOK
	"\x{02C6}" => "\x88",  # MODIFIER LETTER CIRCUMFLEX ACCENT
	"\x{02DC}" => "\x98",  # SMALL TILDE
	"\x{2013}" => "\x96",  # EN DASH
	"\x{2014}" => "\x97",  # EM DASH
	"\x{2018}" => "\x91",  # LEFT SINGLE QUOTATION MARK
	"\x{2019}" => "\x92",  # RIGHT SINGLE QUOTATION MARK
	"\x{201A}" => "\x82",  # SINGLE LOW-9 QUOTATION MARK
	"\x{201C}" => "\x93",  # LEFT DOUBLE QUOTATION MARK
	"\x{201D}" => "\x94",  # RIGHT DOUBLE QUOTATION MARK
	"\x{201E}" => "\x84",  # DOUBLE LOW-9 QUOTATION MARK
	"\x{2020}" => "\x86",  # DAGGER
	"\x{2021}" => "\x87",  # DOUBLE DAGGER
	"\x{2022}" => "\x95",  # BULLET
	"\x{2026}" => "\x85",  # HORIZONTAL ELLIPSIS
	"\x{2030}" => "\x89",  # PER MILLE SIGN
	"\x{2039}" => "\x8B",  # SINGLE LEFT-POINTING ANGLE QUOTATION MARK
	"\x{203A}" => "\x9B",  # SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
	"\x{20AC}" => "\x80",  # EURO SIGN
	"\x{2122}" => "\x99"   # TRADE MARK SIGN
);

my $cp1252re = qr/(\x{0152}|\x{0153}|\x{0160}|\x{0161}|\x{0178}|\x{017D}|\x{017E}|\x{0192}|\x{02C6}|\x{02DC}|\x{2013}|\x{2014}|\x{2018}|\x{2019}|\x{201A}|\x{201C}|\x{201D}|\x{201E}|\x{2020}|\x{2021}|\x{2022}|\x{2026}|\x{2030}|\x{2039}|\x{203A}|\x{20AC}|\x{2122})/;

my $initialized = 0;

sub init {
	
	return if $initialized;
	
	$initialized = 1;
	
	loadFonts();

	FONTDIRS:
	for my $fontFolder (graphicsDirs()) {

		# Try a few different fonts..
		for my $fontFile (qw(arialuni.ttf ARIALUNI.TTF CODE2000.TTF Cyberbit.ttf CYBERBIT.TTF)) {
	
			my $file = catdir($fontFolder, $fontFile);

			if (-e $file) {
				$TTFFontFile = $file;
				last FONTDIRS;
			}
		}
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
	
	return $fontheight->{$fontname} if $fontname;
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

	my $extent = 0;

	# count the number of set bits in the extent bytes (up to 32)
	if (scalar @{ $fonts->{ $fontname }} >= 0x1f) {
		my $extentbytes = string($fontname, chr(0x1f));
		$extent = unpack( '%32b*', $extentbytes );
	}
	
	if ($fontname =~ /\.1/) { $extent = -$extent; }
	
	$fonts->{extents}->{$fontname} = $extent;
	
	main::DEBUGLOG && $log->debug(" extent of: $fontname is $extent");
}

sub string {
	my $defaultFontname = shift || return (0, '');
	my $string          = shift;

	if (!defined $string) {
		return (0, '');
	}

	my $defaultFont = $fonts->{$defaultFontname} || do {

		logBacktrace(" Invalid font $defaultFontname");
		return (0, '');
	};

	# Fast path when string does not include control symbols or characters not in the bitmap font
	if ($string !~ /[^\x00-\x09|\x0b-\x1a\|\x1e-\xff]/) {
		my $bits = '';
		my $len = length $string;
		my $interspace = $defaultFont->[0];
		for my $ord (unpack($unpackTemplate, $string)) {
			$bits .= $defaultFont->[$ord];
			$bits .= $interspace if --$len;
		}
		return (0, $bits);
	}

	my ($FTFontSize, $FTBaseline);
	my $useTTFNow = 0;
	my $reverse = 0; # flag for whether the text was reversed (Bidi:R)

	my @ords = unpack($unpackTemplate, $string);

	if (@ords && max(@ords) > 255) {
		
		if ($TTFFontFile && exists $font2TTF{$defaultFontname} && $canUseFreeType->()) {
			$useTTFNow  = 1;
			$FTFontSize = $font2TTF{$defaultFontname}->{'FTFontSize'};
			$FTBaseline = $font2TTF{$defaultFontname}->{'FTBaseline'};
			
			$ft ||= Font::FreeType->new->face($TTFFontFile);

			# If the string contains any Unicode characters which exist in our bitmap,
			# use the bitmap version instead of the TTF version
			# http://forums.slimdevices.com/showthread.php?t=42087
			if ( $string =~ /[\x{0152}-\x{2122}]/ ) {
				$string =~ s/$cp1252re/$cp1252mapping{$1}/ego;
			}
		}

		if ($useTTFNow) {

			# convert to upper case if fontname is in list of uc fonts
			if ($font2uc{$defaultFontname}) {
				$string = uc($string);
				@ords = ();
			}

			# flip BiDi R text and decide if scrolling should be reversed
			if ($string =~ $bidiR && $canUseHebrew->()) {
				$reverse = ($prefs->get('language') eq 'HE' || $string !~ $bidiL);
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
	my $cursorpos = 0;

	# special characters:
	# \x1d [29] = 'tight'  - suppress inter character space
	# \x1c [28] = '/tight' - turn on inter character space [default]
	# \x1b [27] = font change - new fontname enclosed in \x1b chars, null name = back to default font
	# \x0a [10] = 'cursorpos' - set cursor for next character

	my $remaining = scalar @ords;

	for my $ord (@ords) {

		$remaining--;

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

			$cursorpos = 1;

		} else {

			if ($ord > 255 && $useTTFNow) {

				my $char_bits = $TTFCache{"$FTFontSize.$FTBaseline.$ord"};

				if ( !$char_bits ) {

					my $bits_tmp = '';
					
					$ft->set_char_size($FTFontSize, $FTFontSize, 96, 96);
					my $glyph = $ft->glyph_from_char_code($ord) || $ft->glyph_from_char_code(9647); # square as fallback
					my ($bmp, $left, $top) = $glyph->bitmap(FT_RENDER_MODE_MONO);
					my $width  = length $bmp->[0];
					my $height = scalar @{$bmp};
					
					my $top_padding = $FTBaseline - $top;
					my $start_y = 0;					
					if ($top_padding < 0) {
						# Top of char is cut off
						$start_y = abs($top_padding);
						$top_padding = 0;
					}
					
					if ($height + $top_padding > 32) {
						# Bottom of char is cut off
						$height = 32 - $top_padding;
					}
					
					my $bottom_padding = 32 - $height - $top_padding + $start_y;
					if ($bottom_padding < 0) {
						$bottom_padding = 0;
					}
					
					# Add left_bearing padding if any
					for (my $x = 0; $x < $glyph->left_bearing; $x++) {
						$bits_tmp .= '0' x 32;
					}
					
					for (my $x = 0; $x < $width; $x++) {
						$bits_tmp .= '0' x $top_padding;
						
						for (my $y = $start_y; $y < $height; $y++) {
							$bits_tmp .= (substr $bmp->[$y], $x, 1) eq "\xFF" ? 1 : 0;
						}
						
						$bits_tmp .= '0' x $bottom_padding;
					}
					
					# Add right_bearing padding if any
					for (my $x = 0; $x < $glyph->right_bearing; $x++) {
						$bits_tmp .= '0' x 32;
					}
					
					$char_bits = pack "B*", $bits_tmp;

					$TTFCache{"$FTFontSize.$FTBaseline.$ord"} = $char_bits;
				}

				if ($cursorpos) {
					my $len = length($char_bits);
					$char_bits |= substr($defaultFont->[$ord0a] x $len, 0, $len);
					$cursorpos = 0;
				}

				$bits .= $char_bits;

			} else {

				# We don't handle anything outside ISO-8859-1
				# right now in our non-TTF bitmaps.
				if ($ord > 255 || !defined $ord) {
					$ord = 63; # 63 == '?'
				}

				if ($cursorpos) {

					my $char_bits = $font->[$ord];

					# pad narrow characters so the cursor is wide enough to see
					if (length($char_bits) < 3 * length($interspace) ) {
						$char_bits = $interspace . $char_bits . $interspace;
					}
					
					my $len = length($char_bits);
					$char_bits |= substr($defaultFont->[$ord0a] x $len, 0, $len);
					$bits .= $char_bits;

					$cursorpos = 0;

				} else {

					$bits .= $font->[$ord];
				}

				# add inter character space except at end of string
				if ($remaining) {
					$bits .= $interspace;
				}
			}
		}
	}
		
	return ($reverse, $bits);
}

sub measureText {
	my $fontname = shift;
	my $string = shift;

	return $measureTextCache{"$fontname-$string"} if exists $measureTextCache{"$fontname-$string"};

	# delete an old entry if the cache is too large (faster than LRU)
	if (keys %measureTextCache > 4) {
		delete $measureTextCache{ (keys %measureTextCache)[0] };
	}

	return 0 if (!$fontname || !$fontheight->{$fontname});

	return $measureTextCache{"$fontname-$string"} = length( string($fontname, $string) ) / ( $fontheight->{$fontname} / 8 );
}
	
sub graphicsDirs {

	# graphics files allowed in Graphics dir and root directory of plugins
	return (
		Slim::Utils::OSDetect::dirsFor('Graphics'), 
		Slim::Utils::PluginManager->dirsFor('Graphics'), 
	); 
}

sub fontCacheFile {
	my $file = catdir( $prefs->get('cachedir'),
		Slim::Utils::OSDetect::OS() eq 'unix' ? 'fontcache' : 'fonts');
	
	# Add the os arch to the cache file name, to avoid crashes when going
	# between 32-bit and 64-bit perl for example
	$file .= '.' . Slim::Utils::OSDetect::details()->{osArch} . '.bin';
	
	return $file;
}

# returns a hash of filenames/external names and the sum of mtimes as a cache verification key
sub fontfiles {
	my %fonts  = ();
	my $mtimesum = 0;
	my $defcache;

	for my $fontFileDir (graphicsDirs()) {

		if (!-d $fontFileDir) {
			next;
		}

		my $dir = dir($fontFileDir);

		while (my $fileObj = $dir->next) {

			my $file = $fileObj->stringify;

			if ($file =~ /[\/\\](.+?)\.font\.bmp$/) {

				$fonts{basename($1)} = $file;
				
				$mtimesum += (stat($file))[9]; 

				main::DEBUGLOG && $log->debug(" found: $file");

			} elsif ($file =~ /corefonts.bin$/) {

				$defcache = $file;
			}
		}
	}

	if ($defcache) {

		if ($mtimesum / scalar keys %fonts != (stat($defcache))[9]) {

			main::DEBUGLOG && $log->debug(" ignoring prebuild cache - different mtime from files");

			$defcache = undef;
			
		} else {

			main::DEBUGLOG && $log->debug(" prebuild cache is valid");
		}
	}

	return ($defcache, $mtimesum, %fonts);
}

sub loadFonts {
	my $forceParse = shift;
	
	init() if !$initialized;
	
	my ($defcache, $mtimesum, %fontfiles) = fontfiles();

	my $fontCache = fontCacheFile();

	my $fontCacheVersion = 2; # version number of fontcache matching this code
	
	# use stored fontCache if newer than all font files and correct version
	if (!$forceParse && ($defcache || -r $fontCache)) { 

		# check cache for consitency
		my $cacheOK = 1;

		my $cache = $defcache || $fontCache;

		main::INFOLOG && $log->info("Retrieving font data from font cache: $cache");

		eval { $fonts = retrieve($cache); };

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

		# check for version of fontcache & mtime checksum, ignore mtimesum if defcache is valid
		if (!$fonts->{version} || $fonts->{version} != $fontCacheVersion || !defined $defcache && ($fonts->{mtimesum} != $mtimesum) ) {

			$cacheOK = 0;
		}

		# check for font files being removed
		for my $font (keys %{$fontheight}) {

			if (!exists($fontfiles{$font})) {
				$cacheOK = 0;
			}
		}

		# check for new fonts being added
		for my $font (keys %fontfiles) {

			if (!exists($fontheight->{$font})) {
				$cacheOK = 0;
			}
		}
	
		if ( $cacheOK ) {
			# If we loaded a cached SBG font, mark it already loaded
			if ( exists $fonts->{'medium.1'} ) {
				$prefs->set( 'loadFontsSqueezeboxG', 1 );
			}
			
			# If we loaded a cached SB2 font, mark it already loaded
			if ( exists $fonts->{'standard.1'} ) {
				$prefs->set( 'loadFontsSqueezebox2', 1 );
			}
			
			return;
		}

		main::INFOLOG && $log->info("Font cache contains old data - reparsing fonts");
	}

	# otherwise clear data and parse all font files
	$fonts = {};

	foreach my $font (keys %fontfiles) {

		main::DEBUGLOG && $log->debug("Now parsing: $font");

		my ($fontgrid, $height) = parseBMP($fontfiles{$font});

		main::DEBUGLOG && $log->debug(" height of: $font is " . ($height - 1));

		# store height and then skip font if never seen a player requiring it
		$fonts->{'height'}->{$font} = $height - 1;

		next if ($height == 17 && !$prefs->get('loadFontsSqueezeboxG'));
		next if ($height == 33 && !$prefs->get('loadFontsSqueezebox2'));

		main::DEBUGLOG && $log->debug("loading...");

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

	main::INFOLOG && $log->info("Writing font cache: $fontCache");

	$fonts->{'version'} = $fontCacheVersion;
	$fonts->{'mtimesum'} = $mtimesum;

	nstore($fonts, $fontCache);
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

1;

__END__
