package Slim::Utils::Strings;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use base qw(Exporter);

# we export string() so it's less typing to use it
our @EXPORT_OK = qw(string);

use File::Spec::Functions qw(:ALL);

use Slim::Utils::Misc;

#-------------------------------------------------

our %strings   = ();
our %languages = ();
our $failsafe_language = 'EN';

#
# Initializes the module
#
# When a new string is added in strings.txt, it will probably take 
# a while before someome gets around to translating it. $failsafe_language
# is the fallback. If a string is not available in the user's
# preferred language (current_lang), then this is the one we'll return in it's place.
#

sub init {
	my $usr_strings;

	# clear these so they can be reloaded after language change
	%strings   = ();
	%languages = ();

	for my $dir (stringsDirs()) {

		for my $stringfile (stringsFiles()) {
			load_strings_file(catdir($dir, $stringfile));
		}
	}

	for my $lang (keys(%languages)) {
		$languages{$lang} = languageName($lang);
	}
}

sub stringsDirs {

	return (
		Slim::Utils::OSDetect::dirsFor('strings'),
		Slim::Utils::Prefs::preferencesPath(),
	);
}

sub stringsFiles {

	my @stringsFiles = qw(
		strings.txt
		slimserver-strings.txt
		custom-strings.txt
	);

	return @stringsFiles;
}

#
# Loads a file containing strings
#
sub load_strings_file {
	my $file = shift;

	if (!-e $file) {
		return;
	}

	my $strings;

	# Force the UTF-8 layer opening of the strings file.
	#
	# Be backwards compatible with perl 5.6.x
	# 
	# Setting $/ to undef and slurping is much faster than join('', <STRINGS>)
	# it also avoids creating an extra in memory copy of the string.
	if ($] > 5.007) {

		local $/ = undef;

		open(STRINGS, '<:utf8', $file) || do {
			errorMsg("load_strings_file: couldn't open $file - FATAL!\n");
			die;
		};

		$strings = <STRINGS>;
		close STRINGS;

	} else {

		# This is lexically scoped.
		use utf8;
		local $/ = undef;

		open(STRINGS, $file) || do {
			errorMsg("load_strings_file: couldn't open $file - FATAL!\n");
			die;
		};

		$strings = <STRINGS>;

		if (Slim::Utils::Unicode::currentLocale() =~ /^iso-8859-1/) {
			$strings = Slim::Utils::Unicode::utf8toLatin1($strings);
		}

		close STRINGS;
	}

	addStrings(\$strings);
}

# Add a single string with a pointer to another string.
sub addStringPointer {
	my $name    = shift;
	my $pointer = shift;
	       
	foreach my $language (list_of_languages()) {
		$strings{$name}->{$language} = $pointer;
	}
}

sub addStrings {
	my $strings = shift;

	# memory saver by passing in a ref.
	if (ref($strings) ne 'SCALAR') {
		$strings = \$strings;
	}

	my $string = '';
	my $language = '';
	my $stringname = '';
	my $ln = 0;
	
	# TEMP changed language IDs for temporary ID translation (needed for plugins' 6.2.x <-> 6.5 compatibility)
	my %legacyLanguages = (
		'CZ' => 'CS',
		'DK' => 'DA',
		'JP' => 'JA',
		'SE' => 'SV',
	);
	# /TEMP

	my $currentLanguage  = getLanguage();
	my $failSafeLanguage = failsafeLanguage();
	
	LINE: for my $line (split('\n', $$strings)) {

		$ln++;
		chomp($line);
		
		next if $line =~ /^#/;
		next if $line !~ /\S/;

		if ($line =~ /^(\S+)$/) {

			$stringname = $1;
			$string = '';
			next LINE;

		} elsif ($line =~ /^\t(\S*)\t(.+)$/) {

			my $one = $1;
			$string = $2;

			# TEMP temporary ID translation for backwards compatibility
			# print a warning for plugin authors
			if ($legacyLanguages{$one} && $legacyLanguages{$one} eq $currentLanguage) {
				msg("Please tell the plugin author to update string '$string': '$one' should be '$legacyLanguages{$one}'\n");
				$one = $legacyLanguages{$one};
			}
			# /TEMP
						
			# only read strings in our preferred and the failback language - plus the language names for the setup page
			if ($one ne $failSafeLanguage && $one ne $currentLanguage && $stringname ne 'LANGUAGE_CHOICES') {
				next LINE;
			}

			if ($one =~ /./) {
				# if the string spans multiple lines, language can be left blank, and
				# we'll remember it from the last time we saw it.
				$language = uc($one);

				# keep track of all the languages we've seen
				if (!exists($languages{$language})) {
					$languages{$language} = $language;
				}

				if (defined $strings{$stringname}->{$language}) { 
					delete $strings{$stringname}->{$language};
				};
			} 

			if (defined $strings{$stringname}->{$language}) { 
				$strings{$stringname}->{$language} .= "\n$string";
			} else {
				$strings{$stringname}->{$language} = $string;
			}

		} else {
			msg("Parse error on line $ln: $line\n");
		}
	}
}

# These should be self explainatory.
sub list_of_languages {
	return sort(keys(%languages));
}

sub hash_of_languages {
	return %languages;
}

sub hashref_of_strings {
	return \%strings;
}

# Returns a string in the requested language
#
# We can pass in a language to override the default.
# Currently used for falling back to English when the selected language is a
# non-latin1 language such as Japanese.

sub string {
	my $stringname = uc(shift);
	my $language   = shift || Slim::Utils::Prefs::get('language');
	my $dontWarn   = shift || 0;

	my $translate  = Slim::Utils::Prefs::get('plugin-stringeditor-translatormode') || 0;

	for my $tryLang ($language, $failsafe_language) {

		if (!$strings{$stringname}->{$tryLang}) {
			next;
		}

		my $string = $strings{$stringname}->{$tryLang};

		# Some code to help with Michael Herger's string translator plugin.
		if (($tryLang ne $language) && $translate) {

			 $string .= " {$stringname}";
		}

		return $string;
	}

	if (!$dontWarn) {
		bt();
		msg("string: Undefined string: $stringname\n");
		msg("string: Requested language: $language - failsafe language: $failsafe_language\n");
	}

	return '';
}

# like string() above, but returns the string token if the string does not exist
sub getString {
	my $string = shift;

	# Call string, but don't warn on missing.
	my $parsed = string($string, undef, 1);

	return $parsed ? $parsed : $string;
}

#
# Returns a string for doublesize mode in the requested language
#

sub doubleString {
	my $stringname = uc(shift);
	my $language   = shift || Slim::Utils::Prefs::get('language');

	# Try the double size string first - but don't warn if we can't find
	# it. Then fallback to the regular string.
	return string($stringname.'_DBL', $language, 1) || string($stringname, $language);
}

#
# Returns 1 if the requested string exists, 0 if not
#

sub stringExists {
	my $stringname = uc(shift) || return 0;
	my $language   = shift || Slim::Utils::Prefs::get('language');

	return ($strings{$stringname}->{$language} || $strings{$stringname}->{$failsafe_language}) ? 1 : 0;
}

# "Pointer chase" a string - useful for plugins where we don't have $client yet.
sub resolveString {
	my $string   = shift;
	my $language = shift || Slim::Utils::Prefs::get('language');

	my $value  = '';

	if (stringExists($string, $language)) {

		$value = string($string, $language);

		if (stringExists($value, $language)) {
			$value = string($value, $language);
		}
	}

	return $value;
}

#
# Sets the language in which strings will be returned
#
# returns 1 if the language is available, otherwise returns 0
# and current_lang is unchanged.
#
sub setLanguage {
	my $lang = shift;
	
	$lang =~ tr/a-z/A-Z/;
	
	if (defined $languages{$lang}) {
		Slim::Utils::Prefs::set('language', $lang);
		return 1;
	}

	return 0;
}

sub getLanguage {
	return Slim::Utils::Prefs::get('language') || failsafeLanguage();
}

sub languageName {
	my $lang = shift;

	return $strings{'LANGUAGE_CHOICES'}->{$lang};
}

#
# Returns the failsafe language:
#
sub failsafeLanguage {
	return $failsafe_language;
}

sub validClientLanguages {

	# This should really be dynamically generated - how?
	# list_of_languages grab - and walk the list - check for stringExists(VALID_CLIENT_LANGUAGE)
	return map { $_, 1 } qw(CS DE DA EN ES FI FR IT NL NO PT SV);
}

1;
