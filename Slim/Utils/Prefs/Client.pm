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

use Slim::Utils::Log;

my $log = logger('prefs');

sub new {
	my $ref    = shift;
	my $parent = shift;
	my $client = shift;

	my $clientid = $client->id;

	my $class = bless {
		'clientid'  => $clientid,
		'parent'    => $parent,
	}, $ref;

	$class->{'prefs'} = $parent->{'prefs'}->{"_client:$clientid"} ||= {
		'_version' => 0,
	};

	for my $version (sort keys %{$parent->{'migratecb'}}) {

		if ($class->{'prefs'}->{'_version'} < $version) {

			if ($parent->{'migratecb'}->{ $version }->($class, $client)) {

				$log->info("migrating client prefs $parent->{'namespace'}::$class->{'clientid'} to version $version");

				$class->{'prefs'}->{'_version'} = $version;

			} else {

				$log->warn("failed to migrate client prefs for $parent->{'namespace'}::$class->{'clientid'} to version $version");
			}
		}
	}

	return $class;
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
