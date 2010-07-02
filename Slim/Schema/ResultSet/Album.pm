package Slim::Schema::ResultSet::Album;

# $Id$

use strict;
use base qw(Slim::Schema::ResultSet::Base);

use Slim::Utils::Prefs;


sub pageBarResults {
	my $self = shift;
	my $sort = shift;

	my $table = $self->{'attrs'}{'alias'};
	my $name  = "$table.titlesort";

	# pagebar based on contributors if first sort field and results already sorted by this
	if ($sort && $sort =~ /^contributor\.namesort/) {

		if ($self->{'attrs'}{'order_by'} =~ /contributor\.namesort/) {
			$name  = "contributor.namesort";
		}

# bug 4633: sorting album views isn't fully supported yet
#		elsif ($self->{'attrs'}{'order_by'} =~ /me\.namesort/) {
#			$name  = "me.namesort";
#		}
	}

	$self->search(undef, {
		'select'     => [ \"SUBSTR($name, 1, 1)", { count => \"DISTINCT($table.id)" } ],
		as           => [ 'letter', 'count' ],
		group_by     => \"SUBSTR($name, 1, 1)",
		result_class => 'Slim::Schema::PageBar',
	});
}

sub alphaPageBar {
	my $self = shift;
	my $sort = shift;
	my $hierarchy = shift;

	# bug 4633: sorting album views isn't fully supported yet
	# use simple numerical pagebar if we used a different hierarchy than album/*
	return 0 unless ($hierarchy =~ /^album/ || !$sort || $sort =~ /^album\.titlesort/);

	return (!$sort || $sort =~ /^(?:contributor\.namesort|album\.titlesort)/) ? 1 : 0;
}

sub ignoreArticles {
	my $self = shift;

	return 1;
}

sub searchColumn {
	my $self  = shift;

	return 'titlesearch';
}

sub searchNames {
	my $self  = shift;
	my $terms = shift;
	my $attrs = shift || {};
	
	my $collate = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();

	$attrs->{'order_by'} ||= "me.titlesort $collate, me.disc";
	$attrs->{'distinct'} ||= 'me.id';

	return $self->search({ 'me.titlesearch' => { 'like' => $terms } }, $attrs);
}

sub browse {
	my $self = shift;
	my $find = shift;
	my $cond = shift;
	my $sort = shift;

	my @join = ();

	# This sort/join logic is here to handle the 'Sort Browse Artwork'
	# feature - which applies to albums, as artwork is just a view on the
	# album list.
	#
	# Quick and dirty to get something working again. This code should be
	# expanded to be generic per level. A UI feature would be to have a
	# drop down on certain browse pages of how to order the items being
	# displayed. Album is problably the most flexible of all our browse
	# modes.
	#
	# Writing this code also brought up how we might be able to abstract
	# out some join issues/duplications - if we resolve all potential
	# joins first, like the contributorAlbums issue below.
	if ($sort) {

		if ($sort =~ /contributor/) {

			push @join, 'contributor';
		}

		if ($sort =~ /genre/) {

			push @join, { 'tracks' => { 'genreTracks' => 'genre' } };
		}

		$sort = $self->fixupSortKeys($sort);
	}

	# Bug: 2563 - force a numeric compare on an alphanumeric column.
	my $sqlHelperClass = Slim::Utils::OSDetect->getOS()->sqlHelperClass();
	my $collate = $sqlHelperClass->collate();
	
	return $self->search($cond, {
		'order_by' => $sort || ( $sqlHelperClass->prepend0("me.titlesort") . " $collate" ) . ", me.disc",
		'distinct' => 'me.id',
		'join'     => \@join,
	});
}

1;
