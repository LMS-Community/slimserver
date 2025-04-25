package Slim::Menu::BrowseLibrary;

use strict;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

use constant BROWSELIBRARY => 'browselibrary';

my $log = logger('database.info');

sub _labels {
	my ($client, $callback, $args, $pt) = @_;
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	my $library_id = $args->{'library_id'} || $pt->{'library_id'};
	my $search     = $args->{'search'} || $pt->{'search'};
	my $remote_library = $args->{'remote_library'} ||= $pt->{'remote_library'};

	if ($library_id && !grep /library_id/, @searchTags) {
		push @searchTags, 'library_id:' . $library_id;
	}

	Slim::Menu::BrowseLibrary::_generic($client, $callback, $args, 'labels',
		[ @searchTags, ($search ? 'search:' . $search : undef) ],
		sub {
			my $results = shift;
			my $items = $results->{'labels_loop'};
			$remote_library ||= $args->{'remote_library'};

			foreach (@$items) {
				$_->{'name'}          = $_->{'record_label'};
				$_->{'image'}         = 'html/images/albums.png';
				$_->{'type'}          = 'playlist';
				$_->{'playlist'}      = \&_tracks;
				$_->{'url'}           = \&_albums;
				$_->{'passthrough'}   = [ { searchTags => [@searchTags, "record_label:" . $_->{'record_label'}], remote_library => $remote_library } ];
			};

			my $params = _tagsToParams(\@searchTags);
			my %actions = $remote_library ? (
				commonVariables	=> [record_label => 'record_label']
			) : (
				allAvailableActionsDefined => 1,
				commonVariables	=> [record_label => 'record_label'],
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
