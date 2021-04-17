package Slim::Menu::Base;

# Logitech Media Server Copyright 2001-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Provides OPML-based extensible menu for system information and more

=head1 NAME

Slim::Menu::Base

=head1 DESCRIPTION

Provides a dynamic OPML-based menuing system to all UIs. 
This is the base class of various menus, like SystemInfo, TrackInfo etc.

=cut

use strict;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

my $log = logger('menu.base');

my %infoProvider;
my %infoOrdering;

sub init {
	my $class = shift;
	
	$infoProvider{$class->name} = {};
	$infoOrdering{$class->name} = [];

	# Our information providers are pluggable, call the 
	# registerInfoProvider function to extend the details
	# provided in the system info menu.
	$class->registerDefaultInfoProviders();
}

##
# Register all the information providers that we provide.
# This order is defined at http://wiki.slimdevices.com/index.php/UserInterfaceHierarchy
#
sub registerDefaultInfoProviders {
	my $class = shift;
	
	# The 'top', 'middle' and 'bottom' groups
	# so that we can add items in absolute positions
	$class->registerInfoProvider( top    => ( isa => '' ) );
	$class->registerInfoProvider( middle => ( isa => '' ) );
	$class->registerInfoProvider( bottom => ( isa => '' ) );	
}

=head1 METHODS

=head2 Slim::Menu::SystemInfo->registerInfoProvider( $name, %details )

Register a new menu provider to be displayed in System Info.

  Slim::Menu::SystemInfo->registerInfoProvider( album => (
      after => 'IP',
      func  => \&infoNetmask,
  ) );

=over 4

=item $name

The name of the menu provider.  This must be unique within the server, so
you should prefix it with your plugin's namespace.

=item %details

after: Place this menu after the given menu item.

before: Place this menu before the given menu item.

The special values 'top', 'middle', and 'bottom' may be used if you don't
want exact placement in the menu.

=back

=cut

sub registerInfoProvider {
	my ( $class, $name, %details ) = @_;

	$details{name} = $name; # For diagnostic purposes
	
	if (
		   !defined $details{after}
		&& !defined $details{before}
		&& !defined $details{isa}
	) {
		# If they didn't say anything about where it goes,
		# place it in the middle.
		$details{isa} = 'middle';
	}
	
	$infoProvider{$class->name}->{$name} = \%details;

	# Clear the array to force it to be rebuilt
	$infoOrdering{$class->name} = [];
}

=head2 Slim::Menu::SystemInfo->deregisterInfoProvider( $name )

Removes the given menu.  Core menus can be removed,
but you should only do this if you know what you are doing.

=cut

sub deregisterInfoProvider {
	my ( $class, $name ) = @_;
	
	delete $infoProvider{$class->name}->{$name};

	# Clear the array to force it to be rebuilt
	$infoOrdering{$class->name} = [];
}

sub menu {
	my ( $class, $client, $tags ) = @_;
	$tags ||= {};
	
	$class->getInfoOrdering;
		
	# Now run the order, which generates all the items we need
	my $items = [];
	
	for my $ref ( @{ $infoOrdering{$class->name} } ) {
		# Skip items with a defined parent, they are handled
		# as children below
		next if $ref->{parent};
		
		# Add the item
		$class->addItem( $client, $ref, $tags, $items );
		
		# Look for children of this item
		my @children = grep {
			$_->{parent} && $_->{parent} eq $ref->{name}
		} @{ $infoOrdering{$class->name} };
		
		if ( @children ) {
			my $subitems = $items->[-1]->{items} = [];
			
			for my $child ( @children ) {
				$class->addItem( $client, $child, $tags, $subitems );
			}
		}
	}
	
	return {
		name  => cstring($client, $class->name),
		type  => 'opml',
		items => $items,
		menuComplete => 1,
	};
}

# Function to add menu items
sub addItem {
	my ( $class, $client, $ref, $tags, $items ) = @_;
	
	if ( defined $ref->{func} ) {
		
		my $item = eval { $ref->{func}->( $client, $tags ) };
		if ( $@ ) {
			$log->error( 'Menu item "' . $ref->{name} . '" failed: ' . $@ );
			return;
		}
		
		return unless defined $item;
		
		# skip jive-only items for non-jive UIs
		return if $ref->{menuMode} && !$tags->{menuMode};
		
		if ( ref $item eq 'ARRAY' ) {
			if ( scalar @{$item} ) {
				push @{$items}, @{$item};
			}
		}
		elsif ( ref $item eq 'HASH' ) {
			return if $ref->{menuMode} && !$tags->{menuMode};
			if ( scalar keys %{$item} ) {
				push @{$items}, $item;
			}
		}
		else {
			$log->error( 'Menu item "' . $ref->{name} . '" failed: not an arrayref or hashref' );
		}				
	}
};


sub name {
	return '';
}


##
# Adds an item to the ordering list, following any
# 'after', 'before' and 'isa' requirements that the
# registered providers have requested.
#
# @param[in]  $name     The name of the item to add
# @param[in]  $previous The item before this one, for 'before' processing
sub generateInfoOrderingItem {
	my ( $class, $name, $previous ) = @_;

	# Check for the 'before' items which are 'after' the last item
	if ( defined $previous ) {
		for my $item (
			sort { $a cmp $b }
			grep {
				   defined $infoProvider{$class->name}->{$_}->{after}
				&& $infoProvider{$class->name}->{$_}->{after} eq $previous
				&& defined $infoProvider{$class->name}->{$_}->{before}
				&& $infoProvider{$class->name}->{$_}->{before} eq $name
			} keys %{ $infoProvider{$class->name} }
		) {
			$class->generateInfoOrderingItem( $item, $previous );
		}
	}

	# Now the before items which are just before this item
	for my $item (
		sort { $a cmp $b }
		grep {
			   !defined $infoProvider{$class->name}->{$_}->{after}
			&& defined $infoProvider{$class->name}->{$_}->{before}
			&& $infoProvider{$class->name}->{$_}->{before} eq $name
		} keys %{ $infoProvider{$class->name} }
	) {
		$class->generateInfoOrderingItem( $item, $previous );
	}

	# Add the item itself
	$infoOrdering{$class->name} ||= [];
	push @{ $infoOrdering{$class->name} }, $infoProvider{$class->name}->{$name};

	# Now any items that are members of the group
	for my $item (
		sort { $a cmp $b }
		grep {
			   defined $infoProvider{$class->name}->{$_}->{isa}
			&& $infoProvider{$class->name}->{$_}->{isa} eq $name
		} keys %{ $infoProvider{$class->name} }
	) {
		$class->generateInfoOrderingItem( $item );
	}

	# Any 'after' items
	for my $item (
		sort { $a cmp $b }
		grep {
			   defined $infoProvider{$class->name}->{$_}->{after}
			&& $infoProvider{$class->name}->{$_}->{after} eq $name
			&& !defined $infoProvider{$class->name}->{$_}->{before}
		} keys %{ $infoProvider{$class->name} }
	) {
		$class->generateInfoOrderingItem( $item, $name );
	}
}

sub getInfoProvider {
	my $class = shift;
	return $infoProvider{$class->name};
}

sub getInfoOrdering {
	my $class = shift;
	
	if ( !scalar @{ $infoOrdering{$class->name} || [] } ) {
		
		main::DEBUGLOG && $log->debug(sprintf("Creating order for %s menu", $class->name));
		
		# We don't know what order the entries should be in,
		# so work that out.
		$class->generateInfoOrderingItem( 'top' );
		$class->generateInfoOrderingItem( 'middle' );
		$class->generateInfoOrderingItem( 'bottom' );
	}
	
	return $infoOrdering{$class->name};
}

=head1 CREATING MENUS

Menus must be returned in the internal hashref format used for representing OPML.  Each
provider may also return more than one menu item by returning an arrayref.

=head2 EXAMPLES

=over 4

=item Text item, no actions

  {
      type => 'text',
      name => 'Rating: *****',
  }

=item Item with submenu containing one text item

  {
      name => 'More Info',
      items => [
          {
	          type => 'text',
	          name => 'Bitrate: 128kbps',
	      },
	  ],
  }

=item Item using a callback to perform some action in a plugin

  {
      name        => 'Perform Some Action',
      url         => \&myAction,
      passthrough => [ $foo, $bar ], # optional
  }

  sub myAction {
      my ( $client, $callback, $params, $foo, $bar ) = @_;

      my $menu = [
          {
              type => 'text',
              name => 'Results: ...',
          }
      ];

      return $callback->( $menu );
  }

=back

=cut

1;
