package Slim::Utils::Strings;

# $Id: Strings.pm,v 1.2 2003/07/24 23:14:04 dean Exp $

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK @EXPORT_FAIL);
use File::Spec::Functions qw(:ALL);
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw( );
@EXPORT_OK = qw (string);    # we export string() so it's less typing to use it

#-------------------------------------------------

my %strings=();
my %languages=();
my $failsafe_language ="";

#
# Initializes the module
#
# strings_file is the file containing all the strings
#
# When a new string is added in strings.txt, it will probably take 
# a while before someome gets around to translating it. $failsafe_language
# is the fallback. If a string is not available in the user's
# preferred language (current_lang), then this is the one we'll return in it's place.
#

sub init {
	my ($strings_file, $failsafe) = @_;
	my $usr_strings;

	$Slim::Utils::Strings::failsafe_language = $failsafe;
	
	load_strings_file($strings_file); # First load the defaults
	
	my $userFile;
	if (Slim::Utils::OSDetect::OS() eq 'unix') {
		$userFile = ".slimserver-strings.txt";
	} else {
		$userFile = "slimserver-strings.txt"; 
	}
	
	$usr_strings = catdir(Slim::Utils::Prefs::preferencesPath(), $userFile);
	
	if ( -e $usr_strings ) { 
	    load_strings_file($usr_strings); # Then load any user preferences over the top
	}

    foreach my $lang (keys(%languages)) {
		$languages{$lang} = languageName($lang);
	}
}

#
# Loads a file containing strings
#
sub load_strings_file {

	my ($strings_file) = @_;
		
	open STRINGS, $strings_file || die "couldn't open $strings_file\n";
	my $strings = join('', <STRINGS>);
	addStrings($strings);
	close STRINGS;
}

sub addStrings {
	my $strings = shift;
	my @list = split('\n', $strings);

	my $string = '';
	my $language = '';
	my $stringname = '';
	my $line = '';
	my $ln = 0;
	
	LINE: foreach $line (@list) {
		$ln++;
		chomp($line);
		
		next if ($line=~/^#/);
		next if (!($line =~/\S/));

		if ($line=~/^(\S+)$/) {
			$stringname = $1;
			$string='';
			next LINE;
		} elsif ($line=~/^\t(\S*)\t(.+)$/) {
			my $one = $1;
			$string = $2;
			if ($one=~/./) {
				# if the string spans multiple lines, language can be left blank, and
				# we'll remember it from the last time we saw it.
				$language = $one;

				# keep track of all the languages we've seen
				if (!exists($languages{$language})) {
					$languages{$language}= $language;
				}
				if (defined $strings{$language.'_'.$stringname}) { 
					delete $strings{$language.'_'.$stringname};
				};
			} 
			if (defined $strings{$language.'_'.$stringname}) {
				$strings{$language.'_'.$stringname} .= "\n".$string;
			} else {
				$strings{$language.'_'.$stringname} = $string;
			}
		} else {
			Slim::Utils::Misc::msg("Parse error on line $ln: $line\n");
		}
	}
}

#
# Returns a list of all the available languages
#
sub list_of_languages {
	return sort(keys(%languages));
}

#
# Returns the hash of all available languages
#

sub hash_of_languages {
	return %languages;
}

#
# Returns a string in the requested language
#

sub string {
	my ($stringname) = @_;
	
	my $language = Slim::Utils::Prefs::get('language');

	if ($strings{$language.'_'.$stringname}) {
		return $strings{$language.'_'.$stringname};
	} else {
		if ($strings{$Slim::Utils::Strings::failsafe_language.'_'.$stringname}) {
			return $strings{$Slim::Utils::Strings::failsafe_language.'_'.$stringname};
		} else {
			warn "Undefined string: $stringname\nrequested language: $language\nfailsafe language: $Slim::Utils::Strings::failsafe_language\n";
			return '';
		}
	}
}

#
# Returns 1 if the requested string exists, 0 if not
#

sub stringExists {
	my $stringname = shift;
	if (!defined $stringname) {return 0;}
	my $language = Slim::Utils::Prefs::get('language');
	return ($strings{$language.'_'.$stringname} || $strings{$Slim::Utils::Strings::failsafe_language.'_'.$stringname}) ? 1 : 0;
}

#
# Sets the language in which strings will be returned
#
# returns 1 if the language is available, otherwise returns 0
# and current_lang is unchanged.
#
sub setLanguage {
	my $lang = shift;
	
	$lang=~tr/a-z/A-Z/;
	
	if (defined($languages{$lang})) {
		Slim::Utils::Prefs::set('language',$lang);
		return 1;
	}
	return 0;
}

sub getLanguage {
	return Slim::Utils::Prefs::get('language');
}

sub languageName {
	my $lang = shift;
	return $strings{$lang.'_LANGUAGE_CHOICES'};
}

#
# Returns the failsafe language:
#
sub failsafeLanguage {
	return $Slim::Utils::Strings::failsafe_language;
}

1;
