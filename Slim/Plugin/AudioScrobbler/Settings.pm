package Slim::Plugin::AudioScrobbler::Settings;

# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Digest::MD5 qw(md5_hex);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.audioscrobbler');
my $log   = logger('plugin.audioscrobbler');

sub name {
	return Slim::Web::HTTP::protectName('PLUGIN_AUDIOSCROBBLER_MODULE_NAME');
}

sub page {
	return Slim::Web::HTTP::protectURI('plugins/AudioScrobbler/settings/basic.html');
}

sub prefs {
	return ( $prefs, qw(accounts enable_scrobbling) );
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	if ( $params->{saveSettings} ) {
		
		# Save existing accounts
		$params->{accounts} = $prefs->get('accounts') || [];
		
		# delete accounts
		if ( my $delete = $params->{delete} ) {
			if ( !ref $delete ) {
				$delete = [ $delete ];
			}
			
			my $newlist = [];
			ACCOUNT:
			for my $account ( @{ $params->{accounts} } ) {
				for my $todelete ( @{$delete} ) {
					if ( $todelete eq $account->{username} ) {
						$log->debug( "Deleting account $todelete" );
						next ACCOUNT;
					}
				}
				
				push @{$newlist}, $account;
			}
			
			$params->{accounts} = $newlist;
		}
		
		# Save new account
		if ( $params->{password} ) {
			$params->{password} = md5_hex( $params->{password} );
		}
		
		# If the user added a username/password, we need to verify their info
		if ( $params->{username} && $params->{password} ) {
			Slim::Plugin::AudioScrobbler::Plugin::handshake( {
				username => $params->{username},
				password => $params->{password},
				cb       => sub {
					# Callback for OK handshake response
					
					push @{ $params->{accounts} }, {
						username => $params->{username},
						password => $params->{password},
					};
					
					if ( $log->is_debug ) {
						$log->debug( "Saving Audioscrobbler accounts: " . Data::Dump::dump( $params->{accounts} ) );
					}

					my $body = $class->SUPER::handler( $client, $params );

					if ( $params->{AJAX} ) {
						$params->{warning} = Slim::Utils::Strings::string('PLUGIN_AUDIOSCROBBLER_VALID_LOGIN');
						$params->{validated}->{valid} = 1;
					}
					$callback->( $client, $params, $body, @args );
				},
				ecb      => sub {
					# Callback for any errors
					my $error = shift;
					
					$error = Slim::Utils::Strings::string( 'SETUP_PLUGIN_AUDIOSCROBBLER_LOGIN_ERROR', $error );

					if ( $params->{AJAX} ) {
						$params->{warning} = $error;
						$params->{validated}->{valid} = 0;
					}
					else {
						$params->{warning} .= $error . '<br/>';						
					}

					delete $params->{username};
					delete $params->{password};

					my $body = $class->SUPER::handler( $client, $params );
					$callback->( $client, $params, $body, @args );
				},
			} );

			return;
		}
	}
	
	return $class->SUPER::handler( $client, $params );
}

1;