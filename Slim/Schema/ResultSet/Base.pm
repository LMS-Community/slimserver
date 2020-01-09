package Slim::Schema::ResultSet::Base;


# Base class for ResultSets - override what you need.

use strict;
use base qw(DBIx::Class::ResultSet);

use Slim::Utils::Log;
use Slim::Utils::Misc;

my $log = logger('database.sql');

sub orderBy            { '' }
sub searchColumn       { 'id' }

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

sub fixupSortKeys {
	my $self = shift;
	my $sort = shift;

	my $match = lc($self->result_class);
	   $match =~ s/^.+:://;

	my @keys  = ();

	for my $key (split /,/, $sort) {

		if ($key =~ /^$match\.(\w+)$/) {

			push @keys, sprintf('%s.%s', $self->{'attrs'}{'alias'}, $1);

		} else {

			push @keys, $key;
		}
	}

	my $fixed = join(',', @keys);
	
	# Always turn namesearch into the concat version.
	my $sqlHelperClass = Slim::Utils::OSDetect->getOS()->sqlHelperClass();
	my $concatFunction = $sqlHelperClass->concatFunction();
	my $collate = $sqlHelperClass->collate();
	
	if ($fixed =~ /sort/) {
		$fixed =~ s/((?:\w+\.)?\w+sort)/$sqlHelperClass->prepend0($1) . " $collate"/eg;
	}

	# Always append disc for albums & tracks.
	if ($match =~ /^(?:album|track)$/ && $fixed !~ /me\.disc/) {

		$fixed .= ',me.disc';
	}

	main::DEBUGLOG && $log->debug("fixupSortKeys: fixed: [$sort]\n");
	main::DEBUGLOG && $log->debug("fixupSortKeys  into : [$fixed]\n");

	return $fixed;
}

1;

__END__
