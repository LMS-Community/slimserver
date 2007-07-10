package Slim::Utils::Strings;

# $Id$

# SlimServer Copyright (c) 2001-2007 Logitech.
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

our @EXPORT_OK = qw(string);

use POSIX qw(setlocale LC_TIME);
use File::Spec::Functions qw(:ALL);
use Storable;

use Slim::Utils::Log;
use Slim::Utils::Prefs;

our $strings = {};
our $defaultStrings;

my $currentLang;
my $failsafeLang  = 'EN';

my $log = logger('server');

my $prefs = preferences('server');

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

	my ($newest, $files) = stringsFiles();

	my $stringCache = catdir( $prefs->get('cachedir'),
		Slim::Utils::OSDetect::OS() eq 'unix' ? 'stringcache' : 'strings.bin');

	my $stringCacheVersion = 1; # Version number for cache file

	# use stored stringCache if newer than all string files and correct version
	if (!$args->{'ignoreCache'} && -r $stringCache && ($newest < (stat($stringCache))[9])) {

		# check cache for consitency
		my $cacheOK = 1;

		$log->info("Retrieving string data from string cache: $stringCache");

		eval { $strings = retrieve($stringCache); };

		if ($@) {
			$log->warn("Tried loading string: $@");
		}

		if (!$@ && defined $strings &&
			defined $strings->{'version'} && $strings->{'version'} == $stringCacheVersion &&
			defined $strings->{'lang'} && $strings->{'lang'} eq $currentLang ) {

			$defaultStrings = $strings->{$currentLang};

		} else {
			$cacheOK = 0;
		}

		# check for same list of strings files as that stored in stringcache
		if (scalar @{$strings->{'files'}} == scalar @$files) {
			for my $i (0 .. scalar @$files - 1) {
				if ($strings->{'files'}[$i] ne $files->[$i]) {
					$cacheOK = 0;
				}
			}
		} else {
			$cacheOK = 0;
		}

		return if $cacheOK;

		$log->info("String cache contains old data - reparsing string files");
	}

	# otherwise reparse all string files
	unless ($args->{'dontClear'}) {
		$strings = {
			'version' => $stringCacheVersion,
			'lang'    => $currentLang,
			'files'   => $files,
		};
	}

	unless (defined $args->{'storeFailsafe'}) {
		$args->{'storeFailsafe'} = storeFailsafe();
	}

	for my $file (@$files) {

		$log->info("Loading string file: $file");

		loadFile($file, $args);

	}

	unless ($args->{'dontSave'}) {
		$log->info("Storing string cache: $stringCache");
		store($strings, $stringCache);
	}

	$defaultStrings = $strings->{$currentLang};

}

sub stringsFiles {
	my @files;
	my $newest = 0;

	# server string file
	my $serverPath = Slim::Utils::OSDetect::dirsFor('strings');
	push @files, catdir($serverPath, 'strings.txt');

	# plugin string files
	for my $path ( Slim::Utils::PluginManager->pluginRootDirs() ) {
		push @files, catdir($path, 'strings.txt');
	}

	# custom string file
	push @files, catdir($serverPath, 'custom-strings.txt');

	# plugin custom string files
	for my $path ( Slim::Utils::PluginManager->pluginRootDirs() ) {
		push @files, catdir($path, 'custom-strings.txt');
	}

	# prune out files which don't exist and find newest
	my $i = 0;
	while (my $file = $files[$i]) {
		if (-r $file) {
			my $moddate = (stat($file))[9];
			if ($moddate > $newest) {
				$newest = $moddate;
			}
			$i++;
		} else {
			splice @files, $i, 1;
		}
	}

	return $newest, \@files;
}

sub loadFile {
	my $file = shift;
	my $args = shift;

	my $text;

	# Force the UTF-8 layer opening of the strings file.
	#
	# Be backwards compatible with perl 5.6.x
	#
	# Setting $/ to undef and slurping is much faster than join('', <STRINGS>)
	# it also avoids creating an extra in memory copy of the string.
	if ($] > 5.007) {

		local $/ = undef;

		open(STRINGS, '<:utf8', $file) || do {
			logError("Couldn't open $file - FATAL!");
			die;
		};

		$text = <STRINGS>;
		close STRINGS;

	} else {

		# This is lexically scoped.
		use utf8;
		local $/ = undef;

		open(STRINGS, $file) || do {
			logError("Couldn't open $file - FATAL!");
			die;
		};

		$text = <STRINGS>;

		if (Slim::Utils::Unicode::currentLocale() =~ /^iso-8859-1/) {
			$strings = Slim::Utils::Unicode::utf8toLatin1($text);
		}

		close STRINGS;
	}

	parseStrings(\$text, $file, $args);
}

sub parseStrings {
	my $text = shift;
	my $file = shift;
	my $args = shift;

	my $string = '';
	my $language = '';
	my $stringname = '';
	my $stringData = {};
	my $ln = 0;

	my $store = $args->{'storeString'} || \&storeString;

	LINE: for my $line (split('\n', $$text)) {

		$ln++;
		chomp($line);

		next if $line =~ /^#/;
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

	if (defined $strings->{$currentLang}->{$name} && $strings->{$currentLang}->{$name} ne $curString->{$currentLang}) {
		$log->warn("redefined string: $name in $file");
	}

	if (defined $curString->{$currentLang}) {
		$strings->{$currentLang}->{$name} = $curString->{$currentLang};

	} elsif (defined $curString->{$failsafeLang}) {
		$strings->{$currentLang}->{$name} = $curString->{$failsafeLang};
		$log->debug("Language $currentLang using $failsafeLang for $name in $file");
	}

	if ($args->{'storeFailsafe'}) {
		$strings->{$failsafeLang}->{$name} = $curString->{$failsafeLang};
	}
}

# access strings

=head2 string ( $token )

Return localised string for token $token, or ''.

=cut

sub string {
	my $token = uc(shift);
	my $string = $defaultStrings->{$token};

	return $string if defined $string;

	logBacktrace("missing string $token") if $token;
	return '';
}

=head2 getString ( $token )

Return localised string for token $token, or token itself.

=cut

sub getString {
	my $token = shift;
	return $defaultStrings->{uc($token)} || $token;
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

	$log->debug("setString token: $token to $string");
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
	my $display = $client->display;

	if (storeFailsafe() && ($display->isa('Slim::Display::Text') || $display->isa('Slim::Display::SqueezeboxG')) ) {

		unless ($strings->{$failsafeLang}) {
			$log->info("Reparsing strings as client requires failsafe language");
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
			$log->info("$file updated - reparsing");
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
	my $locale = string('LOCALE' . (Slim::Utils::OSDetect::OS() eq 'win' ? '_WIN' : '') );
	$locale .= Slim::Utils::Unicode::currentLocale() =~ /utf8/i ? '.UTF-8' : '';

	setlocale( LC_TIME, $locale );
}


1;
