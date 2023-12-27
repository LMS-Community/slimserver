package Slim::Menu::BrowseLibrary;

use strict;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

use constant BROWSELIBRARY => 'browselibrary';

my $log = logger('database.info');

sub _works {
	my ($client, $callback, $args, $pt) = @_;
#$log->error("DK \$args=" . Data::Dump::dump($args));
#$log->error("DK \$pt=" . Data::Dump::dump($pt));
	my @searchTags = $pt->{'searchTags'} ? @{$pt->{'searchTags'}} : ();
	my $library_id = $args->{'library_id'} || $pt->{'library_id'};
	my $remote_library = $args->{'remote_library'} ||= $pt->{'remote_library'};

#	# We only want role_id of COMPOSER, regardless of what the calling function has passed:
#	my ($index) = grep { $searchTags[$_] ~~ /^role_id:/ } 0 .. $#searchTags;
#	$searchTags[$index] = "role_id:COMPOSER" if $index;

	if ($library_id && !grep /library_id/, @searchTags) {
		push @searchTags, 'library_id:' . $library_id if $library_id;
	}	
#$log->error("DK \@searchTags=" . Data::Dump::dump(@searchTags));

	Slim::Menu::BrowseLibrary::_generic($client, $callback, $args, 'works', [ 'hasAlbums:1', @searchTags ],
		sub {
			my $results = shift;
			my $items = $results->{'works_loop'};
#$log->error("DK \$items=" . Data::Dump::dump($items));
			$remote_library ||= $args->{'remote_library'};

			foreach (@$items) {
				$_->{'name'}          = (grep /artist_id/ , @searchTags) ? $_->{'composer'}."\n".$_->{'work'} : $_->{'work'}."\n".$_->{'composer'};
				$_->{'name2'}         = $_->{'composer'};
				$_->{'type'}          = 'playlist';
				$_->{'playlist'}      = \&_tracks;
				$_->{'url'}           = \&_albums;
				$_->{'passthrough'}   = [ { searchTags => [@searchTags, "work_id:" . $_->{'work_id'}, "composer_id:" . $_->{'composer_id'}], remote_library => $remote_library } ];
				$_->{'favorites_url'} = 'db:work.id=' . ($_->{'work_id'} || 0 );
#$log->error("DK \$_->{'passthrough'}=" . Data::Dump::dump($_->{'passthrough'}));
			};

			my $params = _tagsToParams(\@searchTags);
#$log->error("DK \$params=" . Data::Dump::dump($params));
#$log->error("DK \@searchTags=" . Data::Dump::dump(@searchTags));
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
