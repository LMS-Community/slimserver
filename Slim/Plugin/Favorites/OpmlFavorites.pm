package Slim::Plugin::Favorites::OpmlFavorites;

# An opml based favorites handler

# $Id$

use strict;

use base qw(Slim::Plugin::Favorites::Opml);

use File::Spec::Functions qw(:ALL);
use Scalar::Util qw(blessed);

use Slim::Menu::BrowseLibrary;
use Slim::Player::ProtocolHandlers;
use Slim::Utils::Log;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

my $log = logger('favorites');

my $prefs = preferences('plugin.favorites');
my $prefsServer = preferences('server');

my $favs; # single instance for all callers

sub new {
	return $favs if $favs;

	my $class  = shift;
	my $client = shift; # ignored for this version as favorites are shared by all clients

	$favs = $class->SUPER::new;

	if (-r $favs->filename) {

		$favs->load({ 'url' => $favs->filename });

	} else {

		$favs->_loadOldFavorites;
	}

	Slim::Control::Request::subscribe(sub {
		my $request = shift;

		if ($request->getRequestString() eq 'rescan done'){
			$favs->_urlindex;
		}
		
	}, [['rescan'], ['done']]);

	return $favs;
}

sub migrate {
	my $class = shift;

	my $file = $class->filename();
	if (! -f $file) {
		foreach (Slim::Utils::Misc::getPlaylistDir(), $prefsServer->get('cachedir')) {
			my $oldfile = $class->filename($_);
			if (-f $oldfile) {
				require File::Copy;
				File::Copy::move($oldfile, $file);
				last;
			}
		}
	}
}

sub filename {
	my $class = shift;
	my $dir = shift;
	
	# Shortcut if filename supplied
	return $dir if ($dir && -f $dir);

	$dir ||= Slim::Utils::OSDetect::dirsFor('prefs');
	
	return catdir($dir, "favorites.opml");
}

sub icon {
	my $class = shift;
	my $url = shift;

	return Slim::Player::ProtocolHandlers->iconForURL($url) || 'html/images/favorites.png';
}

sub load {
	my $class = shift;

	$class->SUPER::load(@_);
	$class->_urlindex;
}

sub save {
	my $class = shift;

	$class->SUPER::save(@_);
	$class->_urlindex;

	Slim::Control::Request::notifyFromArray(undef, ['favorites', 'changed']);
}

sub _urlindex {
	my $class = shift;
	my $level = shift;
	my $index = shift || '';

	unless (defined $level) {
		$class->{'url-index'} = {};
		$class->{'hotkey-index'} = {};
		$class->{'hotkey-title'} = {};
		$class->{'url-hotkey'} = {};
		$level = $class->toplevel;
	}

	my $i = 0;

	for my $entry (@{$level}) {

		if ($entry->{'URL'} || $entry->{'url'}) {
			$class->{'url-index'}->{ $entry->{'URL'} || $entry->{'url'} } = $index . $i;
		}

		if (defined $entry->{'hotkey'}) {
			$class->{'hotkey-index'}->{ $entry->{'hotkey'} } = $index . $i;
			$class->{'hotkey-title'}->{ $entry->{'hotkey'} } = $entry->{'text'};
			$class->{'url-hotkey'}->{ $entry->{'URL'} || $entry->{'url'} } = $entry->{'hotkey'};
		}

		# look up icon if not defined or an album or track (can change during rescan)
		if ( !$entry->{'icon'} || ($entry->{'URL'} && $entry->{'URL'} =~ /^(?:db:album|file:)/) ) {
			$entry->{'icon'} = $class->icon($entry->{'URL'});
		}

		if ($entry->{'outline'}) {
			$class->_urlindex($entry->{'outline'}, $index."$i.");
		}

		$i++;
	}
}

sub _loadOldFavorites {
	my $class = shift;

	my $toplevel = $class->toplevel;

	main::INFOLOG && $log->info("No opml favorites file found - loading old favorites");

	require Slim::Utils::Prefs::OldPrefs;

	my @urls   = @{Slim::Utils::Prefs::OldPrefs->get('favorite_urls')   || []};
	my @titles = @{Slim::Utils::Prefs::OldPrefs->get('favorite_titles') || []} ;
	my @hotkeys= (1..9, 0);

	while (@urls) {

		my $entry = {
			'text'   => shift @titles,
			'URL'    => shift @urls,
			'type'   => 'audio',
		};

		if (@hotkeys) {
			$entry->{'hotkey'} = shift @hotkeys;
		}

		$entry->{'icon'} = $class->icon($entry->{'url'});

		push @$toplevel, $entry;
	}

	$class->title(string('FAVORITES'));

	$class->save;
}

sub xmlbrowser {
	my $class = shift;

	my $hash = $class->SUPER::xmlbrowser;

	# optionally let the user browse into local favorite items
	if ( !$prefs->get('dont_browsedb')) {
		$class->_prepareDbItems($hash->{'items'});
	}
	
	$hash->{'favorites'} = 1;

	return $hash;
}

my $dbBrowseModes;

sub _prepareDbItems {
	my ( $class, $items ) = @_;

	foreach my $item (@$items) {
		if ( $item->{'url'} =~ /^db:(\w+)\.(\w+)=(.+)/ ) {
			my ($class, $key, $value) = ($1, $2, $3);
			
			$class = ucfirst($class);

			$dbBrowseModes ||= {
				Album       => [ 'album_id', \&Slim::Menu::BrowseLibrary::_tracks, {
					wantMetadata => 1,
					wantIndex    => 1,
					library_id   => -1,
				} ],
				Contributor => [ 'artist_id', \&Slim::Menu::BrowseLibrary::_albums ],
				Genre       => [ 'genre_id', sub {
					# some plugins do replace artist browse modes - make sure we go to the right place
					my ($artistHandler) = grep { $_->{id} eq 'myMusicArtists' } @{ Slim::Menu::BrowseLibrary->_getNodeList() };
					$artistHandler->{feed}->(@_) if $artistHandler;
				} ],
			};
			
			if ( $dbBrowseModes->{$class} ) {
				$item->{'type'} = 'playlist';
				$item->{'play'} = $item->{'url'} . '&libraryTracks.library=-1';
				$item->{'url'}  = \&_dbItem;
				$item->{'passthrough'} = [{
					class => $class,
					key   => $key,
					value => $value,
				}];
			}
		}
		elsif ( $item->{'items'} && ref $item->{'items'} eq 'ARRAY' && scalar @{$item->{'items'}} ) {
			$class->_prepareDbItems($item->{'items'});
		}
	}
}

sub _dbItem {
	my ($client, $callback, $args, $pt) = @_;
	
	my $class  = ucfirst( delete $pt->{'class'} );
	my $key   = URI::Escape::uri_unescape(delete $pt->{'key'});
	my $value = URI::Escape::uri_unescape(delete $pt->{'value'});

	if (!utf8::is_utf8($value) && !utf8::decode($value)) { $log->warn("The following value is not UTF-8 encoded: $value"); }

	if (utf8::is_utf8($value)) {
		utf8::decode($value);
		utf8::encode($value);
	}
	
	if ( my $dbBrowseMode = $dbBrowseModes->{$class} ) {
		my $obj = Slim::Schema->single( ucfirst($class), { $key => $value } );
	
		if ($obj && $obj->id) {
			$pt->{'searchTags'} = [ $dbBrowseMode->[0] . ':' . $obj->id, 'library_id:-1' ];
			
			while ( my ($k, $v) = each %{ $dbBrowseMode->[2] || {} } ) {
				$pt->{$k} = $v
			}
			
			return $dbBrowseMode->[1]->($client, $callback, $args, $pt);
		}
	}
	
	# something went wrong
	# XXX - better error handling
	$callback->({
		items => [ {
			type  => 'text',
			title => Slim::Utils::Strings::cstring($client, 'EMPTY'),
		} ],
		total => 1
	});
}

sub all {
	my $class  = shift;
	my $typeRE = shift || qr/audio|playlist/;
	my $level  = shift || $class->toplevel;
	my $return = shift || [];

	for my $entry (@{$level}) {

		if ($entry->{'type'} && $entry->{'type'} =~ /$typeRE/) {
			push @$return, {
				'title' => $entry->{'text' },
				'url'   => $entry->{'URL'} || $entry->{'url'},
			}
		}

		if ($entry->{'outline'}) {
			$class->all($typeRE, $entry->{'outline'}, $return);
		}
	}

	return $return;
}

sub add {
	my $class  = shift;
	my $url    = shift;
	my $title  = shift;
	my $type   = shift;
	my $parser = shift;
	my $hotkey = shift; # legacy param left in for compat, no longer used
	my $icon   = shift;

	if (!$url) {
		logWarning("No url passed! Skipping.");
		return undef;
	}

	if (blessed($url) && $url->can('url')) {
		$url = $url->url;
	}

	$url =~ s/\?sessionid.+//i;	# Bug 3362, ignore sessionID's within URLs (Live365)

	if ( main::INFOLOG && $log->is_info ) {
		$log->info(sprintf("url: %s title: %s type: %s parser: %s icon: %s", $url, $title, $type, $parser, $icon));
	}

	# if it is already a favorite, don't add it again return the existing entry
	if ($class->hasUrl($url)) {

		my $index = $class->{'url-index'}->{ $url };
		my $entry = $class->entry($index);

		main::INFOLOG && $log->info("Url already exists in favorites as index $index");

		return $index;
	}

	my $entry = {
		'text' => $title,
		'URL'  => $url,
		'type' => $type || 'audio',
	};

	if ($parser) {
		$entry->{'parser'} = $parser;
	}
	
	if ( $url =~ /\.opml$/ ) {
		delete $entry->{'type'};
	}

	$entry->{'icon'} = $icon || $class->icon($url);

	# add it to end of top level
	push @{$class->toplevel}, $entry;

	$class->save;

	return scalar @{$class->toplevel} - 1;
}

sub hasUrl {
	my $class = shift;
	my $url   = shift;

	return (defined $class->{'url-index'}->{ $url });
}

sub findUrl {
	my $class  = shift;
	my $url    = shift;

	$url =~ s/\?sessionid.+//i;	# Bug 3362, ignore sessionID's within URLs (Live365)

	my $index = $class->{'url-index'}->{ $url };

	if (defined $index) {

		main::INFOLOG && $log->info("Match $url at index $index");

		return $index;
	}

	main::INFOLOG && $log->info("No match for $url");

	return undef;
}

sub deleteUrl {
	my $class  = shift;
	my $url    = shift;

	if (blessed($url) && $url->can('url')) {
		$url = $url->url;
	}

	$url =~ s/\?sessionid.+//i;	# Bug 3362, ignore sessionID's within URLs (Live365)

	if (exists $class->{'url-index'}->{ $url }) {

		$class->deleteIndex($class->{'url-index'}->{ $url });

	} else {

		$log->warn("Can't delete $url index does not exist");
	}
}

sub deleteIndex {
	my $class  = shift;
	my $index  = shift;

	my ($pos, $i) = $class->level($index, 'contains');

	if (ref @{$pos}[ $i ] eq 'HASH') {

		splice @{$pos}, $i, 1;

		main::INFOLOG && $log->info("Removed entry at index $index");

		$class->save;
	}
}

# This method is here only to support migration of old hotkeys (presets)
sub hotkeys {
	my $class = shift;

	my @keys;

	for my $key (1..9,0) {
		push @keys, {
			'key'   => $key,
			'used'  => $class->{'hotkey-index'}->{ $key } ? 1 : 0,
			'title' => $class->{'hotkey-title'}->{ $key },
			'index' => $class->{'hotkey-index'}->{ $key },
		};
	}

	return \@keys;
}

1;
