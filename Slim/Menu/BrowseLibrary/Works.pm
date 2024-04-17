package Slim::Menu::BrowseLibrary;

use strict;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

use constant BROWSELIBRARY => 'browselibrary';

my $log = logger('database.info');

sub _works {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	my $library_id = $args->{'library_id'} || $pt->{'library_id'};
	my $search     = $args->{'search'} || $pt->{'search'};
	my $remote_library = $args->{'remote_library'} ||= $pt->{'remote_library'};

	if ($library_id && !grep /library_id/, @searchTags) {
		push @searchTags, 'library_id:' . $library_id;
	}

	if ($search && !grep /from_search/, @searchTags) {
		push @searchTags, 'from_search:' . $search;
	}

	Slim::Menu::BrowseLibrary::_generic($client, $callback, $args, 'works',
		[ @searchTags, ($search ? 'search:' . $search : undef) ],
		sub {
			my $results = shift;
			my $items = $results->{'works_loop'};
			$remote_library ||= $args->{'remote_library'};

			foreach (@$items) {
				$_->{'name'}          = $_->{'composer'};
				$_->{'name2'}         = $_->{'work'};
				$_->{'hasMetadata'}   = 'work';
				$_->{'image'}         = $_->{'artwork_track_id'} ? 'music/' . $_->{'artwork_track_id'} . '/cover' : 'html/images/works.png';
				$_->{'type'}          = 'playlist';
				$_->{'playlist'}      = \&_tracks;
				$_->{'url'}           = \&_albums;
				$_->{'passthrough'}   = [ { searchTags => [@searchTags, "album_id:" . $_->{'album_id'}, "work_id:" . $_->{'work_id'}, "composer_id:" . $_->{'composer_id'}], remote_library => $remote_library } ];
			};

			my $params = _tagsToParams(\@searchTags);
			my %actions = $remote_library ? (
				commonVariables	=> [work_id => 'work_id', composer_id => 'composer_id', album_id => 'album_id'],
			) : (
				allAvailableActionsDefined => 1,
				commonVariables	=> [work_id => 'work_id', composer_id => 'composer_id', album_id => 'album_id'],
				items => {
					command     => [BROWSELIBRARY, 'items'],
					fixedParams => {
						mode       => 'albums',
						%$params
					},
				},
				play => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'load', %$params},
				},
				add => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'add', %$params},
				},
				insert => {
					command     => ['playlistcontrol'],
					fixedParams => {cmd => 'insert', %$params},
				},
			);
			$actions{'playall'} = $actions{'play'};
			$actions{'addall'} = $actions{'add'};

			return {items => $items, actions => \%actions, sorted => 1}, undef;
		}, undef, 1,
	);
}
