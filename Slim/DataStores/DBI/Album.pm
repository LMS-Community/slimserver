package Slim::DataStores::DBI::Album;

# $Id: Album.pm,v 1.2 2005/01/04 03:38:52 dsully Exp $

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('albums');
	$class->columns(Essential => qw/id title titlesort artwork_path disc discc/);
	$class->columns(Stringify => qw/title/);

	$class->add_constructor('hasArtwork' => 'artwork_path IS NOT NULL');

	$class->has_many(tracks => ['Slim::DataStores::DBI::Track' => 'album']);
}

tie my %_cache, 'Tie::Cache::LRU', 5000;

sub searchTitle {
	my $class   = shift;
	my $pattern = shift;

	s/\*/%/g for @$pattern;

	my %where   = ( title => $pattern, );
	my $findKey = join(':', @$pattern);

	$_cache{$findKey} ||= [ $class->searchPattern('albums', \%where, ['titlesort']) ];

	return wantarray ? @{$_cache{$findKey}} : $_cache{$findKey}->[0];
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
