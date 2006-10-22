package Slim::Schema::ResultSet::Base;

# $Id$

# Base class for ResultSets - override what you need.

use strict;
use base qw(DBIx::Class::ResultSet);

use Slim::Schema::PageBar;
use Slim::Utils::Log;
use Slim::Utils::Misc;

my $log = logger('database.sql');

sub suppressAll        { 0 }
sub allTransform       { '' }
sub descendTransform   { '' }
sub browseBodyTemplate { '' }
sub orderBy            { '' }
sub searchColumn       { 'id' }
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
	if ($fixed =~ /\w+?.\w+?sort/ && $fixed !~ /concat/) {

		$fixed =~ s/(\w+?.\w+?sort)/concat('0', $1)/g;
	}

	# Always append disc for albums & tracks.
	if ($match =~ /^(?:album|track)$/ && $fixed !~ /me\.disc/) {

		$fixed .= ',me.disc';
	}

	$log->debug("fixupSortKeys: fixed: [$sort]\n");
	$log->debug("fixupSortKeys  into : [$fixed]\n");

	return $fixed;
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

	if ($log->is_debug) {

		$log->debug("levelMap: ", Data::Dump::dump(\%levelMap));
		$log->debug("filters : ", Data::Dump::dump(\%filters));
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

		# Turn into me.* for the top level
		if ($param =~ /^$levels->[0]\.(\w+)$/) {
			$param = sprintf('%s.%s', $self->{'attrs'}{'alias'}, $1);
		}

		# Turn into me.* for the current level
		if ($param =~ /^$levels->[$level]\.(\w+)$/) {
			$param = sprintf('%s.%s', $rs->{'attrs'}{'alias'}, $1);
		}

		$log->debug("Working on levelname: [$levelName]");

		if (exists $levelMap{$levelName} && defined $levelMap{$levelName}) {

			my $mapKey = $levelMap{$levelName};

			if (ref($value)) {
				$find{$mapKey} = $value;
			} else {
				$find{$mapKey} = { $param => $value };
			}
		}
	}

	if ($log->is_debug) {

		$log->debug("find: ", Data::Dump::dump(\%find));
	}

	return (\%filters, \%find, \%sort);
}

sub descend {
	my ($self, $find, $cond, $sort, @levels) = @_;

	my $rs = $self;

	$log->debug(sprintf("\$self->result_class: [%s]", $self->result_class));

	# Walk the hierarchy we were passed, calling into the descend$level
	# for each, which will build up a RS to hand back to the caller.
	# 
	# Pass in the top level search conditions, as well as the per-level conditions.
	for my $level (@levels) {

		my $condForLevel = $cond->{lc($level)};

		# XXXX - sortForLevel isn't being processed by
		# generateConditionsFromFilters() yet. Instead, the only
		# supported caller is the Sort Album Artwork feature.
		# Only accept the scalar used this at present.
		#my $sortForLevel = $sort->{lc($level)};
		my $sortForLevel = $sort unless ref $sort;

		$level           = ucfirst($level);

		if ($log->is_debug) {

			$log->debug("Working on level: [$level]");

			$log->deubg(sprintf("\$self->result_source->schema->source(\$level)->result_class: [%s]",
				$self->result_source->schema->source($level)->result_class
			));
		}

		# If we're at the top level for a Level, just browse.
		if ($self->result_class eq $self->result_source->schema->source($level)->result_class) {

			$log->debug("Calling method: [browse]");

			$rs = $rs->browse($find, $condForLevel, $sortForLevel);

		} else {

			my $method = "descend${level}";

			$log->debug("Calling method: [$method]");

			$rs = $rs->$method($find, $condForLevel, $sortForLevel);
		}

		# Bug: 3798 - Don't call distinct on playlistTrack's, as it's
		# desirable to have the same track in the playlist multiple times.
		if ($level ne 'PlaylistTrack') {

			$rs = $rs->distinct;
		}
	}

	return $rs;
}

1;

__END__
