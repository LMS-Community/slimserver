package Slim::Schema::ResultSet::Genre;

# $Id$

use strict;
use base qw(Slim::Schema::ResultSet::Base);

use Slim::Utils::Prefs;

sub pageBarResults {
	my $self = shift;

	my $table = $self->{'attrs'}{'alias'};
	my $name  = "$table.namesort";

	$self->search(undef, {
		'select'     => [ \"SUBSTR($name, 1, 1)", { count => \"DISTINCT($table.id)" } ],
		as           => [ 'letter', 'count' ],
		group_by     => \"SUBSTR($name, 1, 1)",
		result_class => 'Slim::Schema::PageBar',
	});
}

sub alphaPageBar { 1 }

sub searchColumn {
	my $self  = shift;

	return 'namesearch';
}

sub searchNames {
	my $self  = shift;
	my $terms = shift;
	my $attrs = shift || {};
	
	my $collate = Slim::Utils::OSDetect->getOS()->sqlHelperClass()->collate();

	$attrs->{'order_by'} ||= "me.namesort $collate";
	$attrs->{'distinct'} ||= 'me.id';

	return $self->search({ 'me.namesearch' => { 'like' => $terms } }, $attrs);
}

1;
