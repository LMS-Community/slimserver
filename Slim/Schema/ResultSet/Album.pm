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


1;
