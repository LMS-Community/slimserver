package Slim::Utils::Strings;

# $Id: Strings.pm,v 1.3 2003/07/31 19:10:57 dean Exp $

# Slim Server Copyright (c) 2001, 2002, 2003 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK @EXPORT_FAIL);
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

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
# When a new string is added in strings.txt, it will probably take 
# a while before someome gets around to translating it. $failsafe_language
# is the fallback. If a string is not available in the user's
# preferred language (current_lang), then this is the one we'll return in it's place.
#

sub init {
	my $usr_strings;
	$Slim::Utils::Strings::failsafe_language = 'EN';

      foreach my $dir (stringsDirs()) {
              foreach my $stringfile (stringsFiles()) {
                      load_strings_file(catdir($dir, $stringfile));
              }
      }

    foreach my $lang (keys(%languages)) {
		$languages{$lang} = languageName($lang);
	}
}

sub stringsDirs {
      my @pluginDirs;
      push @pluginDirs, $Bin;
      push @pluginDirs, Slim::Utils::Prefs::preferencesPath();
      if ($^O eq 'darwin') {
              push @pluginDirs, $ENV{'HOME'} . "/Library/SlimDevices/";
              push @pluginDirs, "/Library/SlimDevices/";
      }
      return @pluginDirs;
}

sub stringsFiles {
      my @stringsFiles;
      push @stringsFiles, 'strings.txt';
      push @stringsFiles, ".slimp3-strings.txt";
      push @stringsFiles, "slimp3-strings.txt"; 
      return @stringsFiles;
}

#
# Loads a file containing strings
#
sub load_strings_file {
	my $strings_file = shift;
      if (!-e $strings_file) {
              return;
      }
		
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
