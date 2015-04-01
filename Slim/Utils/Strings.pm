package Slim::Utils::Strings;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Utils::Strings

=head1 SYNOPSIS

init ()

loadStrings ( [ $argshash ] )

string ( $token )

getString ( $token )

stringExists ( $token )

setString ( $token, $string )

=head1 DESCRIPTION

Global localization module.  Handles the reading of strings.txt for international translations

=head1 EXPORTS

string()

=cut

use strict;
use Exporter::Lite;

our @EXPORT_OK = qw(string cstring clientString);

use Config;
use Digest::SHA1 qw(sha1_hex);
use POSIX qw(setlocale LC_TIME LC_COLLATE);
use File::Slurp qw(read_file write_file);
use File::Spec::Functions qw(:ALL);
use JSON::XS::VersionOneAndTwo;
use Scalar::Util qw(blessed);
use Storable;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::PluginManager;

our $strings = {};
our $defaultStrings;

our $currentLang;
my $failsafeLang  = 'EN';

my $log = logger('server');

my $prefs = preferences('server');

use constant CACHE_VERSION => 3;
# version 2 - include the sum of string file mtimes as an additional validation check
# version 3 - include the server revision

=head1 METHODS

=head2 init( )

Initializes the module - called at server startup.

=cut

sub init {
	$currentLang = getLanguage();
	loadStrings();
	setLocale();

	if ($::checkstrings) {
		checkChangedStrings();
	}
	
	# Load cached extra strings from mysb.com
	loadExtraStrings();
}

=head2 loadStrings( [ $argshash ] )

Load/Reload Strings files for server and plugins using cache if valid.
If stringcache file is valid this is loaded into memory and used as string hash, otherwise
string text files are parsed and new stringhash creted which stored as the stringcache file.

optional $argshash allows default behavious to be overridden, keys that can be set are:
'ignoreCache' - ignore cache file and reparse all files
'dontClear'   - don't clear current string hash before loading file
'dontSave'    - don't save new string hash to cache file [restart will use old cache file]
'storeString' - sub as alternative to storeString [e.g. for use by string editor]

=cut

sub loadStrings {
	my $args = shift;

	my ($newest, $sum, $files) = stringsFiles();

	my $stringCache = catdir( $prefs->get('cachedir'),
		Slim::Utils::OSDetect::OS() eq 'unix' ? 'stringcache' : 'strings');
	
	# Add the os arch to the cache file name, to avoid crashes when going
	# between 32-bit and 64-bit perl for example
	$stringCache .= '.' . Slim::Utils::OSDetect::details()->{osArch} . '.bin';

	# use stored stringCache if newer than all string files and correct version
	if (!$args->{'ignoreCache'} && -r $stringCache && ($newest < (stat($stringCache))[9])) {

		# check cache for consitency
		my $cacheOK = 1;

		main::INFOLOG && $log->info("Retrieving string data from string cache: $stringCache");

		eval { $strings = retrieve($stringCache); };

		if ($@) {
			$log->warn("Tried loading strings file ($stringCache): $@");
			$cacheOK = 0;
		}

		if (!$@ && defined $strings &&
			defined $strings->{'version'} && $strings->{'version'} == CACHE_VERSION &&
			defined $strings->{'lang'} && $strings->{'lang'} eq $currentLang ) {

			$defaultStrings = $strings->{$currentLang};

		} else {
			$cacheOK = 0;
		}

		# check sum of mtimes matches that stored in stringcache
		if ($cacheOK && $strings->{'mtimesum'} && $strings->{'mtimesum'} != $sum) {
			$cacheOK = 0;
		}
		
		# force cache renewal on server updates
		if ($cacheOK && ( !$strings->{'serverRevision'} || $strings->{'serverRevision'} !~ /^$::REVISION$/ )) {
			$cacheOK = 0;
		}

		# check for same list of strings files as that stored in stringcache
		if ($cacheOK && scalar @{$strings->{'files'}} == scalar @$files) {
			my %files = map { $_ => 1 } @$files;
	
			foreach ( @{ $strings->{'files'} } ) {
				if (!$files{$_}) {
					$cacheOK = 0;
					last;
				}
			}
		} else {
			$cacheOK = 0;
		}

		return if $cacheOK;

		main::INFOLOG && $log->info("String cache contains old data - reparsing string files");
	}

	# otherwise reparse all string files
	unless ($args->{'dontClear'}) {
		$strings = {
			'version'        => CACHE_VERSION,
			'mtimesum'       => $sum,
			'lang'           => $currentLang,
			'files'          => $files,
			'serverRevision' => $::REVISION,
		};
	}

	unless (defined $args->{'storeFailsafe'}) {
		$args->{'storeFailsafe'} = storeFailsafe();
	}

	for my $file (@$files) {

		main::INFOLOG && $log->info("Loading string file: $file");

		loadFile($file, $args);

	}

	unless ($args->{'dontSave'}) {
		main::INFOLOG && $log->info("Storing string cache: $stringCache");
		store($strings, $stringCache);
	}

	$defaultStrings = $strings->{$currentLang};

}

sub loadAdditional {
	my $lang = shift;
	
	if ( exists $strings->{$lang} ) {
		return $strings->{$lang};
	}
	
	for my $file ( @{ $strings->{files} } ) {
		main::INFOLOG && $log->info("Loading string file for additional language $lang: $file");
		
		my $args = {
			storeString => sub {
				local $currentLang = $lang;
				storeString( @_ );
			},
		};

		loadFile( $file, $args );
		
		main::idleStreams();
	}
	
	# extra strings delivered by SN
	eval {
		local $currentLang = $lang;
		loadExtraStrings();
	};
	
	return $strings->{$lang};
}

sub stringsFiles {
	my @files;
	my $newest = 0; # mtime of newest file
	my $sum = 0;    # sum of all mtimes

	# server string file
	my $serverPath = Slim::Utils::OSDetect::dirsFor('strings');
	my @pluginDirs = Slim::Utils::PluginManager->dirsFor('strings');

	push @files, catdir($serverPath, 'strings.txt');

	# plugin string files
	for my $path ( @pluginDirs ) {
		push @files, catdir($path, 'strings.txt');
	}

	# custom string file
	push @files, catdir($serverPath, 'custom-strings.txt');

	# plugin custom string files
	for my $path ( @pluginDirs ) {
		push @files, catdir($path, 'custom-strings.txt');
	}
	
	if ( main::SLIM_SERVICE ) {
		push @files, catdir($serverPath, 'slimservice-strings.txt');
		push @files, catdir($main::SN_PATH, 'docroot', 'strings.txt');
	}

	# prune out files which don't exist and find newest
	my $i = 0;
	while (my $file = $files[$i]) {
		if (-r $file) {
			my $moddate = (stat($file))[9];
			$sum += $moddate;
			if ($moddate > $newest) {
				$newest = $moddate;
			}
			$i++;
		} else {
			splice @files, $i, 1;
		}
	}

	return $newest, $sum, \@files;
}

sub loadFile {
	my $file = shift;
	my $args = shift;

	# Force the UTF-8 layer opening of the strings file.
	open(my $fh, '<:utf8', $file) || do {
		logError("Couldn't open $file - FATAL!");
		die;
	};
	
	parseStrings($fh, $file, $args);
	
	close $fh;
}

sub parseStrings {
	my ( $fh, $file, $args ) = @_;

	my $string = '';
	my $language = '';
	my $stringname = '';
	my $stringData = {};
	my $ln = 0;

	my $store = $args->{'storeString'} || \&storeString;

	LINE: for my $line ( <$fh> ) {

		$ln++;

		# skip lines starting with # (comments?)
		next if $line =~ /^#/;
		# skip lines containing nothing but whitespace
		# (this includes empty lines)
		next if $line !~ /\S/;

		if ($line =~ /^(\S+)$/) {

			&$store($stringname, $stringData, $file, $args);

			$stringname = $1;
			$stringData = {};
			$string = '';
			next LINE;

		} elsif ($line =~ /^\t(\S*)\t(.+)$/) {

			my $one = $1;
			$string = $2;

			if ($one =~ /./) {
				$language = uc($one);
			}

			if ($stringname eq 'LANGUAGE_CHOICES') {
				$strings->{'langchoices'}->{$language} = $string;
				next LINE;
			}
			elsif ($stringname eq 'LOCALE') {
				$strings->{locales}->{$language} = $string;
			}

			if (defined $stringData->{$language}) {
				$stringData->{$language} .= "\n$string";
			} else {
				$stringData->{$language} = $string;
			}

		} else {

			logError("Parsing line $ln: $line");
		}
	}

	&$store($stringname, $stringData, $file, $args);
}

sub storeString {
	my $name = shift || return;
	my $curString = shift;
	my $file = shift;
	my $args = shift;

	return if ($name eq 'LANGUAGE_CHOICES');
	
	if ( main::SLIM_SERVICE ) {
		# Store all languages so we can have per-client language settings
		for my $lang ( keys %{ $strings->{langchoices} } ) {
			$strings->{$lang}->{$name} = $curString->{$lang} || $curString->{$failsafeLang};
		}
		return;
	}

	if ($log->is_info && defined $strings->{$currentLang}->{$name} && defined $curString->{$currentLang} && 
			$strings->{$currentLang}->{$name} ne $curString->{$currentLang}) {
		main::INFOLOG && $log->info("redefined string: $name in $file");
	}

	if (defined $curString->{$currentLang}) {
		$strings->{$currentLang}->{$name} = $curString->{$currentLang};

	} elsif (defined $curString->{$failsafeLang}) {
		$strings->{$currentLang}->{$name} = $curString->{$failsafeLang};
		main::DEBUGLOG && $log->is_debug && $log->debug("Language $currentLang using $failsafeLang for $name in". (defined $file ? $file : 'undefined'));
	}

	if ($args->{'storeFailsafe'} && defined $curString->{$failsafeLang}) {

		$strings->{$failsafeLang}->{$name} = $curString->{$failsafeLang};
	}
}

=head2 storeExtraStrings ( $arrayref )

Cache and store additional strings.  This is used by SN to send additional
strings for apps.

=cut

# Cache extra strings to avoid reading from disk
my $extraStringsCache = {};
my $extraStringsDirty = 0;

sub storeExtraStrings {
	my $extra = shift;
	
	# Cache strings to disk so they work on restart
	my $extraCache = catdir( $prefs->get('cachedir'), 'extrastrings.json' );
	
	if ( !scalar( keys %{$extraStringsCache} ) && -e $extraCache ) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Reading extrastrings.json file');
		
		$extraStringsCache = eval { from_json( read_file($extraCache) ) };
		if ( $@ ) {
			$extraStringsCache = {};
		}
	}
	
	# This function determines if the string hash data has changed
	my $hash_diff = sub {
		for my $k ( keys %{ $_[1] } ) {
			if ( !exists $_[0]->{$k} || $_[0]->{$k} ne $_[1]->{$k} ) {
				return 1;
			}
		}
		return 0;
	};
	
	# Turn into a hash
	$extra = { map { $_->{token} => $_->{strings} } @{$extra} };

	for my $string ( keys %{$extra} ) {
		storeString( $string, $extra->{$string} );
		if ( !exists $extraStringsCache->{$string} || $hash_diff->( $extraStringsCache->{$string}, $extra->{$string} ) ) {
			$extraStringsCache->{$string} = $extra->{$string};
			$extraStringsDirty = 1;
		}
	}

	if ( $extraStringsDirty ) {
		# Batch changes to avoid lots of writes
		Slim::Utils::Timers::killTimers( $extraCache, \&_writeExtraStrings );
		Slim::Utils::Timers::setTimer( $extraCache, time() + 5, \&_writeExtraStrings );
	}
}

sub _writeExtraStrings {
	my $extraCache = shift;
	
	main::DEBUGLOG && $log->is_debug && $log->debug('Writing updated extrastrings.json file');
	
	$extraStringsDirty = 0;
	eval { write_file( $extraCache, to_json($extraStringsCache) ) };
};

=head2 loadExtraStrings

Load cached additional strings delivered from SN.

=cut

sub loadExtraStrings {
	my $extraCache = catdir( $prefs->get('cachedir'), 'extrastrings.json' );
	
	my $cache = {};
	if ( -e $extraCache ) {
		$cache = eval { from_json( read_file($extraCache) ) };
	}
	
	for my $string ( keys %{ $cache || {} } ) {
		storeString( $string, $cache->{$string} );
	}
}


# access strings

=head2 string ( $token )

Return localised string for token $token, or ''.

=cut

sub string {
	my $token = uc(shift);

	my $string = $defaultStrings->{$token};
	logBacktrace("missing string $token") if ($token && !defined $string);

	if ( @_ ) {
		return sprintf( $string, @_ );
	}
	
	return $string;
}

=head2 clientString( $client, $token )

Same as string but uses $client->string if client is available.
Also available as cstring().

=cut

sub clientString {
	my $client = shift;
	
	if ( blessed($client) ) {
		return $client->string(@_);
	}
	else {
		return string(@_);
	}
}

*cstring = \&clientString;

=head2 getString ( $token )

Return localised string for token $token, or token itself.

=cut

sub getString {
	my $token = shift;

	# we don't have lowercase tokens
	return $token if $token =~ /(?:[a-z]|\s)/;

	my $string = $defaultStrings->{uc($token)};
	$string = $token if ($token && !defined $string);

	if ( @_ ) {
		return sprintf( $string, @_ );
	}
	
	return $string;
}

=head2 stringExists ( $token )

Return boolean indicating whether $token exists.

=cut

sub stringExists {
	my $token = uc(shift);
	return (defined $defaultStrings->{$token}) ? 1 : 0;
}

=head2 setString ( $token, $string )

Set string for $token to $string.  Used to override string definitions parsed from string files.
The new definition is lost if the language is changed.

=cut

sub setString {
	my $token = uc(shift);
	my $string = shift;

	main::DEBUGLOG && $log->debug("setString token: $token to $string");
	$defaultStrings->{$token} = $string;
}

=head2 defaultStrings ( )

Returns hash of tokens to localised strings for default language.

=cut

sub defaultStrings {
	return $defaultStrings;
}

# get & set languages

sub languageOptions {
	return $strings->{langchoices};
}

sub getLanguage {
	return $prefs->get('language') || $failsafeLang;
}

sub setLanguage {
	my $lang = shift;

	if ($strings->{'langchoices'}->{$lang}) {

		$prefs->set('language', $lang);
		$currentLang = $lang;

		loadStrings({'ignoreCache' => 1});
		loadExtraStrings();
		setLocale();

		for my $client ( Slim::Player::Client::clients() ) {
			$client->display->displayStrings(clientStrings($client));
		}

	}
}

sub failsafeLanguage {
	return $failsafeLang;
}

sub clientStrings {
	my $client = shift;
	
	if ( main::SLIM_SERVICE ) {
		if ( my $override = $client->languageOverride ) {
			return $strings->{ $override } || $strings->{ $failsafeLang };
		}
		
		return $strings->{ $prefs->client($client)->get('language') } || $strings->{$failsafeLang};
	}
	
	my $display = $client->display;

	if (storeFailsafe() && ($display->isa('Slim::Display::Text') || $display->isa('Slim::Display::SqueezeboxG')) ) {

		unless ($strings->{$failsafeLang}) {
			main::INFOLOG && $log->info("Reparsing strings as client requires failsafe language");
			loadStrings({'ignoreCache' => 1});
		}

		return $strings->{$failsafeLang};

	} else {
		return $defaultStrings;
	}
}

sub storeFailsafe {
	return ($currentLang ne $failsafeLang &&
			($prefs->get('loadFontsSqueezeboxG') || $prefs->get('loadFontsText') ) &&
			$currentLang !~ /CS|DE|DA|EN|ES|FI|FR|IT|NL|NO|PT|SV/ ) ? 1 : 0;
}


# Timer task to check mtime of string files and reload if they have changed.
# Started by init when --checkstrings is present on command line.
my $lastChange = time;

sub checkChangedStrings {

	my $reload;

	for my $file (@{$strings->{'files'}}) {
		if ((stat($file))[9] > $lastChange) {
			main::INFOLOG && $log->info("$file updated - reparsing");
			loadFile($file);
			$reload ||= time;
		}
	}

	if ($reload) {
		$lastChange = $reload;
	}

	Slim::Utils::Timers::setTimer(undef, time + 1, \&checkChangedStrings);
}

sub setLocale {
	my $locale = string(main::ISWINDOWS ? 'LOCALE_WIN' : 'LOCALE');
	$locale .= '.UTF-8' if Slim::Utils::Unicode::currentLocale() =~ /utf8/i;

	setlocale( LC_TIME, $locale );
	
	# We leave LC_TYPE unchanged.
	# This is used in Slim::Music::Info::sortFilename() to modify the
	# behaviour of uc() when sorting native-encoded filenames.
	# It is also used, probably incorrectly, in Slim::Schema::Genre::add() for ucfirst()
	
	# We set LC_COLLATE always to utf8 so that it can be used correctly within 
	# the collate function (perlcollate) for SQLite DB sorting, where the field values
	# are always UTF-8
	$locale = string(main::ISWINDOWS ? 'LOCALE_WIN' : 'LOCALE') . '.UTF-8';
	setlocale( LC_COLLATE, $locale );
}

sub getLocales {
	return $strings->{locales};
}

1;
