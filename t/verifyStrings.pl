#!/usr/bin/env perl

use strict;
use warnings;

use File::Next;
use File::Slurp;
use JSON;

my %translations;
my (@output, @invalid, $slug);

my $files = File::Next::files( {
	file_filter => sub { /\bstrings\.txt$/ }
}, '.' );

while (my $file = $files->()) {
	foreach (read_file($file)) {
		my ($lang, $translation);
		chomp;

		next if /^#/;

		if (/^\t([-A-Z0-9_]{2,5})\t(.*)/) {
			($lang, $translation) = ($1, $2);
		} elsif (/^[-A-Z0-9_]+$/) {
			$slug = $_;
		} elsif ($_) {
			push @invalid, "Invalid line ($slug): $_";
		}

		if ($lang && !exists $translations{$lang}) {
			$translations{$lang} = {};
		}

		if ($lang) {
			$translations{$lang}{$slug} = $translation;
		}
	}
}

foreach my $lang (grep { !$translations{$_}->{LANGUAGE_CHOICES} } keys %translations) {
	push @invalid, "Invalid language: $lang";
}

if (scalar(@invalid)) {
	print "Errors:\n";
	print join("\n", @invalid);
	exit 1;
}
