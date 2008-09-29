package Slim::Menu::Base;

# $Id: $

# SqueezeCenter Copyright 2001-2008 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Provides OPML-based extensible menu for system information

=head1 NAME

Slim::Menu::SystemInfo

=head1 DESCRIPTION

Provides a dynamic OPML-based system info (player, server, controller)
menu to all UIs and allows plugins to register additional menu items.

=cut

use strict;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

my $log = logger('menu.base');

my %infoProvider;
my %infoOrdering;

sub init {
	my $class = shift;
	
	$infoProvider{$class->title} = {};
	$infoOrdering{$class->title} = [];

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
	
	$infoProvider{$class->title}->{$name} = \%details;

	# Clear the array to force it to be rebuilt
	$infoOrdering{$class->title} = [];
}

=head2 Slim::Menu::SystemInfo->deregisterInfoProvider( $name )

Removes the given menu.  Core menus can be removed,
but you should only do this if you know what you are doing.

=cut

sub deregisterInfoProvider {
	my ( $class, $name ) = @_;
	
	delete $infoProvider{$class->title}->{$name};

	# Clear the array to force it to be rebuilt
	$infoOrdering{$class->title} = [];
}

sub menu {
	my ( $class, $client, $tags ) = @_;
	$tags ||= {};
	
	$class->getInfoOrdering;
		
	# Now run the order, which generates all the items we need
	my $items = [];
	
	for my $ref ( @{ $infoOrdering{$class->title} } ) {
		# Skip items with a defined parent, they are handled
		# as children below
		next if $ref->{parent};
		
		# Add the item
		$class->addItem( $client, $ref, $tags, $items );
		
		# Look for children of this item
		my @children = grep {
			$_->{parent} && $_->{parent} eq $ref->{name}
		} @{ $infoOrdering{$class->title} };
		
		if ( @children ) {
			my $subitems = $items->[-1]->{items} = [];
			
			for my $child ( @children ) {
				$class->addItem( $client, $child, $tags, $subitems );
			}
		}
	}
	
	return {
		name  => $class->title,
		type  => 'opml',
		items => $items,
	};
}

# Function to add menu items
sub addItem {
	my ( $class, $client, $ref, $tags, $items ) = @_;
	
	if ( defined $ref->{func} ) {
		
		my $item = eval { $ref->{func}->( $client, $tags ) };
		if ( $@ ) {
			$log->error( 'SystemInfo menu item "' . $ref->{name} . '" failed: ' . $@ );
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
			$log->error( 'SystemInfo menu item "' . $ref->{name} . '" failed: not an arrayref or hashref' );
		}				
	}
};


sub title {
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
				   defined $infoProvider{$class->title}->{$_}->{after}
				&& $infoProvider{$class->title}->{$_}->{after} eq $previous
				&& defined $infoProvider{$class->title}->{$_}->{before}
				&& $infoProvider{$class->title}->{$_}->{before} eq $name
			} keys %{ $infoProvider{$class->title} }
		) {
			$class->generateInfoOrderingItem( $item, $previous );
		}
	}

	# Now the before items which are just before this item
	for my $item (
		sort { $a cmp $b }
		grep {
			   !defined $infoProvider{$class->title}->{$_}->{after}
			&& defined $infoProvider{$class->title}->{$_}->{before}
			&& $infoProvider{$class->title}->{$_}->{before} eq $name
		} keys %{ $infoProvider{$class->title} }
	) {
		$class->generateInfoOrderingItem( $item, $previous );
	}

	# Add the item itself
	$infoOrdering{$class->title} ||= [];
	push @{ $infoOrdering{$class->title} }, $infoProvider{$class->title}->{$name};

	# Now any items that are members of the group
	for my $item (
		sort { $a cmp $b }
		grep {
			   defined $infoProvider{$class->title}->{$_}->{isa}
			&& $infoProvider{$class->title}->{$_}->{isa} eq $name
		} keys %{ $infoProvider{$class->title} }
	) {
		$class->generateInfoOrderingItem( $item );
	}

	# Any 'after' items
	for my $item (
		sort { $a cmp $b }
		grep {
			   defined $infoProvider{$class->title}->{$_}->{after}
			&& $infoProvider{$class->title}->{$_}->{after} eq $name
			&& !defined $infoProvider{$class->title}->{$_}->{before}
		} keys %{ $infoProvider{$class->title} }
	) {
		$class->generateInfoOrderingItem( $item, $name );
	}
}

sub getInfoProvider {
	my $class = shift;
	return $infoProvider{$class->title};
}

sub getInfoOrdering {
	my $class = shift;
	
	if ( !scalar @{ $infoOrdering{$class->title} || [] } ) {
		
		$log->debug(sprintf("Creating order for %s menu", $class->title));
		
		# We don't know what order the entries should be in,
		# so work that out.
		$class->generateInfoOrderingItem( 'top' );
		$class->generateInfoOrderingItem( 'middle' );
		$class->generateInfoOrderingItem( 'bottom' );
	}
	
	return $infoOrdering{$class->title};
}

1;