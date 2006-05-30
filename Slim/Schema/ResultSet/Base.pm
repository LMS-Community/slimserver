package Slim::Schema::ResultSet::Base;

# $Id$

# Base class for ResultSets - override what you need.

use strict;
use base qw(DBIx::Class::ResultSet);

use Slim::Schema::PageBar;

sub suppressAll        { 0 }
sub nameTransform      { '' }
sub allTransform       { '' }
sub descendTransform   { '' }
sub browseBodyTemplate { '' }
sub pageBarResults     { 0 }
sub alphaPageBar       { 0 }
sub ignoreArticles     { 0 }

sub distinct {
	my $self = shift;

	# XXX - this will work when mst fixes ResultSet.pm
	# $self->search(undef, { 'distinct' => 1 });

	$self->search(undef, {
		'group_by' => map { $self->{'attrs'}->{'alias'}.'.'.$_ } $self->result_source->primary_columns
	});
}

# Turn find keys into their table aliased versions.
sub fixupFindKeys {
	my $self = shift;
	my $find = shift;

	my $match = lc($self->result_class);
	   $match =~ s/^.+:://;

	while (my ($key, $value) = each %{$find}) {

		if ($key =~ /^$match\.(\w+)$/) {

			$find->{sprintf('%s.%s', $self->{'attrs'}{'alias'}, $1)} = delete $find->{$key};
		}
	}

	return $find;
}

sub descend {
	my ($self, $find, $sort, @levels) = @_;

	my $rs = $self;

	# Walk the hierarchy we were passed, calling into the descend$level
	# for each, which will build up a RS to hand back to the caller.
	for my $level (@levels) {

		my $findForLevel = $find->{lc($level)};
		my $sortForLevel = $sort->{lc($level)};

		$level           = ucfirst($level);

		print "working on level: [$level]\n";

		if ($::d_sql) {
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
