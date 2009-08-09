package Slim::Utils::Prefs::Client;

# $Id$

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Utils::Prefs::Client

=head1 DESCRIPTION

Class for implementing object to hold per client preferences within a namespace.

=head1 METHODS

=cut

use strict;

use base qw(Slim::Utils::Prefs::Base);

use Scalar::Util qw(blessed);

use Slim::Utils::Log;

my $log = logger('prefs');

our $clientPreferenceTag = '_client';

sub new {
	my $ref    = shift;
	my $parent = shift;
	my $client = shift;

	my $clientid = blessed($client) ? $client->id : $client;

	my $class = bless {
		'clientid'  => $clientid,
		'parent'    => $parent,
	}, $ref;

	$class->{'prefs'} = $parent->{'prefs'}->{"$clientPreferenceTag:$clientid"} ||= {
		'_version' => 0,
	};		

	return $class;
}

sub migrate {
	my $self   = shift;
	my $client = shift;
	
	my $cversion = $self->get( '_version', 'force' ) || 0; # On SN, force _version to come from the DB

	for my $version (sort keys %{ $self->{parent}->{'migratecb'}}) {
		
		if ( $cversion < $version ) {
			
			if ( $self->{parent}->{'migratecb'}->{ $version }->($self, $client)) {
				
				main::INFOLOG && $log->info("migrating client prefs $self->{parent}->{'namespace'}:$self->{'clientid'} to version $version");
				
				if ( main::SLIM_SERVICE ) {
					# Store _version in the database on SN
					$self->set( '_version' => $version );
				}

				$self->{'prefs'}->{'_version'} = $version;
				
			} else {
				
				$log->warn("failed to migrate client prefs for $self->{parent}->{'namespace'}:$self->{'clientid'} to version $version");
			}
		}
	}
}

sub _root { shift->{'parent'} }

sub _obj { Slim::Player::Client::getClient(shift->{'clientid'}) }

=head2 SEE ALSO

L<Slim::Utils::Prefs::Base>
L<Slim::Utils::Prefs::Namespace>
L<Slim::Utils::Prefs::Client>
L<Slim::Utils::Preds::OldPrefs>

=cut

1;
