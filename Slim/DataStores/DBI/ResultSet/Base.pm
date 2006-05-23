package Slim::DataStores::DBI::ResultSet::Base;

# $Id$

# Base class for ResultSets - override what you need.

use strict;
use base qw(DBIx::Class::ResultSet);

use Slim::DataStores::DBI::PageBar;

sub suppressAll {}
sub nameTransform {}
sub allTransform {}
sub descendTransform {}
sub browseBodyTemplate {}
sub pageBarResults {}
sub alphaPageBar {}
sub ignoreArticles {}

sub distinct {
	my $self = shift;

	# XXX - this will work when mst fixes ResultSet.pm
	# $self->search(undef, { 'distinct' => 1 });

	$self->search(undef, {
		'group_by' => map { $self->{'attrs'}->{'alias'}.'.'.$_ } $self->result_source->primary_columns
	});
}

sub descend {
	my $self = shift;
	my $find = shift;
	my $sort = shift;

	my $rs   = $self;

	# Walk the hierarchy we were passed, calling into the descend$level
	# for each, which will build up a RS to hand back to the caller.
	for my $level (@_) {

		my $findForLevel = $find->{lc($level)};
		my $sortForLevel = $sort->{lc($level)};

		$level = ucfirst($level);

		print "working on level: [$level]\n";

		if (1) {
			printf("\$self->result_class: [%s]\n", $self->result_class);
			printf("\$self->result_source->schema->source(\$level)->result_class: [%s]\n",
				$self->result_source->schema->source($level)->result_class
			);
		}

		# If we're at the top level for a Level, just browse.
		if ($self->result_class eq $self->result_source->schema->source($level)->result_class) {

			print "Calling method: [browse]\n";
			$rs = $rs->browse($findForLevel, $sortForLevel);

		} else {

			my $method = "descend${level}";
			print "Calling method: [$method]\n";
			$rs = $rs->$method($findForLevel, $sortForLevel);
		}
	}

	return $rs;
}

1;

__END__
