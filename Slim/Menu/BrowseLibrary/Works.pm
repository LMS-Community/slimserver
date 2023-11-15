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
	my $remote_library = $args->{'remote_library'} ||= $pt->{'remote_library'};
	my $byComposer = $args->{'params'}->{'byComposer'};

	if ($library_id && !grep /library_id/, @searchTags) {
		push @searchTags, 'library_id:' . $library_id if $library_id;
	}

	Slim::Menu::BrowseLibrary::_generic($client, $callback, $args, 'works', [ 'hasAlbums:1', "byComposer:$byComposer", @searchTags ],
		sub {
			my $results = shift;
			my $items = $results->{'works_loop'};
			$remote_library ||= $args->{'remote_library'};

			my $lastWork = "";
			my $lastComposerID = 0;
			foreach (@$items) {
				if ( $byComposer ) {
					$_->{'name'}          = $_->{'composer'}."\n".$_->{'work'};
				} else {
					$_->{'name'}          = $_->{'work'}."\n".$_->{'composer'};
				}
				$_->{'name2'}         = $_->{'composer'};
				$_->{'type'}          = 'playlist';
				$_->{'playlist'}      = \&_tracks;
				$_->{'url'}           = \&_albums;
				$_->{'passthrough'}   = [ { searchTags => [@searchTags, "work_id:" . $_->{'work_id'}, "composer_id:" . $_->{'composer_id'}], remote_library => $remote_library } ];
				$_->{'favorites_url'} = 'db:tracks.work=' . ($_->{'work'} || 0 );
			};

			my $params = _tagsToParams(\@searchTags);
			my %actions = $remote_library ? (
				commonVariables	=> [work_id => 'work_id', composer_id => 'composer_id'],
			) : (
				allAvailableActionsDefined => 1,
				commonVariables	=> [work_id => 'work_id', composer_id => 'composer_id'],
				info => {
					command     => ['workinfo', 'items'],
				},
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
		},
	);
}
