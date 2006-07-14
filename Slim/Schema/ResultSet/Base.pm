package Slim::Schema::ResultSet::Base;

# $Id$

# Base class for ResultSets - override what you need.

use strict;
use base qw(DBIx::Class::ResultSet);

use Slim::Schema::PageBar;
use Slim::Utils::Misc;

sub suppressAll        { 0 }
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

sub generateConditionsFromFilters {
	my ($self, $attrs) = @_;

	my $rs      = $attrs->{'rs'};
	my $level   = $attrs->{'level'};
	my $levels  = $attrs->{'levels'};
	my $params  = $attrs->{'params'} || {};

	my %filters = ();
	my %find    = ();
	my %sort    = ();

	# Create a map pointing to the previous RS for each level.
	# 
	# Example: For the navigation from Genres to Contributors, the
	# hierarchy would be:
	# 
	# genre,contributor,album,track
	# 
	# we want the key in the level above us in order to descend.
	#
	# Which would give us: $find->{'genre'} = { 'contributor.id' => 33 }
	my %levelMap = ();

	for (my $i = 1; $i < scalar @{$levels}; $i++) {

		$levelMap{ lc($levels->[$i-1]) } = lc($levels->[$i]);
	}

	# Filters builds up the list of params passed that we want to filter
	# on. They are massaged into the %find hash.
	my @sources  = map { lc($_) } Slim::Schema->sources;

	# Build up the list of valid parameters we may pass to the db.
	while (my ($param, $value) = each %{$params}) {
	
		if (!grep { $param =~ /^$_(\.\w+)$/ } @sources) {
			next;
		}

		$filters{$param} = $value;
	}

	if ($::d_sql) {
		msg("levelMap:\n");
		print Data::Dumper::Dumper(\%levelMap);
		msg("filters:\n");
		print Data::Dumper::Dumper(\%filters);
	}

	# Turn parameters in the form of: album.sort into the appropriate sort
	# string. We specify a sortMap to turn something like:
	# tracks.timestamp desc, tracks.disc, tracks.titlesort
	while (my ($param, $value) = each %filters) {

		if ($param =~ /^(\w+)\.sort$/) {

			#$sort{$1} = $sortMap{$value} || $value;
			#$sort{$1} = $value;

			delete $filters{$param};
		}
	}

	# Now turn each filter we have into the find hash ref we'll pass to ->descend
	while (my ($param, $value) = each %filters) {

		my ($levelName) = ($param =~ /^(\w+)\.\w+$/);

		if ($param eq 'album.year') {

			$levelName = 'year';

			# Unknown Year is passed as 0 in the web UI. But we
			# need to query against NULL in the DB. Bug 3732
			if (!$value) {
				$value = undef;
			}
		}

		# Turn into me.* for the top level
		if ($param =~ /^$levels->[0]\.(\w+)$/) {
			$param = sprintf('%s.%s', $self->{'attrs'}{'alias'}, $1);
		}

		# Turn into me.* for the current level
		if ($param =~ /^$levels->[$level]\.(\w+)$/) {
			$param = sprintf('%s.%s', $rs->{'attrs'}{'alias'}, $1);
		}

		$::d_sql && msg("working on levelname: [$levelName]\n");

		if (exists $levelMap{$levelName} && defined $levelMap{$levelName}) {

			my $mapKey = $levelMap{$levelName};

			if (ref($value)) {
				$find{$mapKey} = $value;
			} else {
				$find{$mapKey} = { $param => $value };
			}
		}
	}

	if ($::d_sql) {
		msg("find:\n");
		print Data::Dumper::Dumper(\%find);
	}

	return (\%filters, \%find, \%sort);
}

sub descend {
	my ($self, $find, $cond, $sort, @levels) = @_;

	my $rs = $self;

	$::d_sql && msgf("\$self->result_class: [%s]\n", $self->result_class);

	# Walk the hierarchy we were passed, calling into the descend$level
	# for each, which will build up a RS to hand back to the caller.
	# 
	# Pass in the top level search conditions, as well as the per-level conditions.
	for my $level (@levels) {

		my $condForLevel = $cond->{lc($level)};

		# XXXX - sortForLevel isn't being processed by
		# generateConditionsFromFilters() yet. Instead, the only
		# caller is the Sort Album Artwork feature.
		#my $sortForLevel = $sort->{lc($level)};
		my $sortForLevel = $sort;

		$level           = ucfirst($level);

		if ($::d_sql) {

			msg("descend: working on level: [$level]\n");
			msgf("\$self->result_source->schema->source(\$level)->result_class: [%s]\n",
				$self->result_source->schema->source($level)->result_class
			);
		}

		# If we're at the top level for a Level, just browse.
		if ($self->result_class eq $self->result_source->schema->source($level)->result_class) {

			$::d_sql && msg("Calling method: [browse]\n");
			$rs = $rs->browse($find, $condForLevel, $sortForLevel);

		} else {

			my $method = "descend${level}";
			$::d_sql && msg("Calling method: [$method]\n");
			$rs = $rs->$method($find, $condForLevel, $sortForLevel);
		}
	}

	return $rs;
}

1;

__END__
