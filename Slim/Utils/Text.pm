package Slim::Utils::Text;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

my %caseArticlesCache = ();

# Article list to ignore.
my $ignoredArticles = undef;

sub ignorePunct {
	my $s = shift || return undef;

	my $orig = $s;

	$s =~ s/[!\*?,;=+<>#%&()\"\'\$\.\\:-]+/ /go;
	$s =~ s/  +/ /go; # compact multiple spaces, "L.A. Mix" -> "L A Mix", not "L A  Mix"
	$s =~ s/^ +//o; # zap leading/trailing spaces.
	$s =~ s/ +$//o;

	$s = $orig if $s eq '';

	return $s;
}

sub matchCase {
	my $s = shift || return undef;

	# Upper case and fold latin1 diacritical characters into their plain versions, surprisingly useful.
	$s =~ tr{abcdefghijklmnopqrstuvwxyzÀÁÂÃÄÅßÞÇ¢ÐÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜ×Ýàáâãäåþçèéêëìíîïñòóôõöøùúûüÿýð¡°}
		{ABCDEFGHIJKLMNOPQRSTUVWXYZAAAAAABBCCDEEEEIIIINOOOOOOUUUUXYAAAAAABCEEEEIIIINOOOOOOUUUUYYD!D};

	# Turn Æ & æ into AE
	$s =~ s/\xC6/AE/go;
	$s =~ s/\xC3\x86/AE/go;

	# and the lowercase version
	$s =~ s/\xE6/AE/go;
	$s =~ s/\xC3\xA6/AE/go;

	# And µ into MU
	$s =~ s/\xB5/MU/go;
	$s =~ s/\xC2\xB5/MU/go;

	return $s;
}

sub ignoreArticles {
	my $item = shift || return;

	if (!defined($ignoredArticles)) {

		$ignoredArticles = Slim::Utils::Prefs::get("ignoredarticles");

		# allow a space seperated list in preferences (easier for humans to deal with)
		$ignoredArticles =~ s/\s+/|/g;

		$ignoredArticles = qr/^($ignoredArticles)\s+/i;
	}

	# set up array for sorting items without leading articles
	$item =~ s/$ignoredArticles//;

	return $item;
}

sub ignoreCaseArticles {
	my $s = shift || return undef;

	if (scalar keys %caseArticlesCache > 256) {
		%caseArticlesCache = ();
	}

	if (!$caseArticlesCache{$s}) {

		use locale;

		$caseArticlesCache{$s} = ignorePunct(ignoreArticles(uc($s)));
	}

	return $caseArticlesCache{$s};
}

sub clearCaseArticleCache {

	%caseArticlesCache = ();
	$ignoredArticles   = undef;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
