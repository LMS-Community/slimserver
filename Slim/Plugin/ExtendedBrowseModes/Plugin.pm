package Slim::Plugin::ExtendedBrowseModes::Plugin;

use strict;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Log;

sub initPlugin {
	my ( $class ) = @_;

	my @menus = ({
		name         => 'PLUGIN_EXTENDED_BROWSEMODES_BROWSE_BY_ALBUMARTIST',
		role_id      => Slim::Schema::Contributor->typeToRole('ALBUMARTIST'),
		feed         => 'Slim::Menu::BrowseLibrary::_artists',
		icon         => 'html/images/artists.png',
		id           => 'myMusicAlbumArtists',
		weight       => 11,
	},
	{
		name         => 'PLUGIN_EXTENDED_BROWSEMODES_BROWSE_BY_COMPOSERS',
		role_id      => Slim::Schema::Contributor->typeToRole('COMPOSER'),
		feed         => 'Slim::Menu::BrowseLibrary::_artists',
		icon         => 'html/images/artists.png',
		id           => 'myMusicComposers',
		weight       => 12,
	});

	foreach (@menus) {
		$class->registerBrowseMode($_);
	}
}

sub registerBrowseMode {
	my ($class, $item) = @_;

	my $subclass = $item->{id} || return;

	my $package  = __PACKAGE__;
	my $tag      = lc($subclass);
	my $name     = $item->{name};
	my $feed     = $item->{feed};
	my $weight   = $item->{weight};
	my $icon     = $item->{icon};
	my $role_id  = $item->{role_id};

	my $code = qq{
package ${package}::${subclass};

use strict;
use base qw(Slim::Plugin::OPMLBased);

sub initPlugin {
	my \$class = shift;
	
	\$class->SUPER::initPlugin(
		tag    => '$tag',
		feed   => sub {
			my (\$client, \$callback, \$args, \$pt) = \@_;
			
			\$pt ||= {};
			\$pt->{searchTags} ||= [];
			
			push \@{\$pt->{searchTags}}, 'role_id:$role_id' unless grep /role_id/, \@{\$pt->{searchTags}};
			
			$feed(\$client, \$callback, \$args, \$pt);
		},
		node   => 'myMusic',
		menu   => 'browse',
		weight => $weight,
		type   => 'link',
		icon   => '$icon',
	);
}

sub getDisplayName { '$name' }

sub icon { '$icon' }

sub _pluginDataFor {
	my ( \$class, \$key ) = \@_;

	return \$class->icon if \$key eq 'icon';
	
	return \$class->SUPER::_pluginDataFor(\$key);
}

1;
	};

	eval $code;
	if ( $@ ) {
		logError( "Unable to dynamically create radio class $subclass: $@" );
		next;
	}

	$subclass = "${package}::${subclass}";

	$subclass->initPlugin();
}

1;