package Slim::Plugin::AudioScrobbler::Settings;

# Logitech Media Server Copyright 2001-2011 Logitech.
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
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_AUDIOSCROBBLER_MODULE_NAME');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/AudioScrobbler/settings/basic.html');
}

sub prefs {
	return ( $prefs, qw(accounts enable_scrobbling include_radio ignoreTitles ignoreGenres ignoreArtists ignoreAlbums) );
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	if ( $params->{saveSettings} ) {
		
		# Save existing accounts
		$params->{pref_accounts} = $prefs->get('accounts') || [];
		
		# delete accounts
		if ( my $delete = $params->{delete} ) {
			if ( !ref $delete ) {
				$delete = [ $delete ];
			}
			
			my $newlist = [];
			ACCOUNT:
			for my $account ( @{ $params->{pref_accounts} } ) {
				for my $todelete ( @{$delete} ) {
					if ( $todelete eq $account->{username} ) {
						main::DEBUGLOG && $log->debug( "Deleting account $todelete" );
						next ACCOUNT;
					}
				}
				
				push @{$newlist}, $account;
			}
			
			$params->{pref_accounts} = $newlist;
		}
		
		# Save new account
		if ( $params->{pref_password} ) {
			$params->{pref_password} = md5_hex( $params->{pref_password} );
		}
		
		# If the user added a username/password, we need to verify their info
		if ( $params->{pref_username} && $params->{pref_password} ) {
			Slim::Plugin::AudioScrobbler::Plugin::handshake( {
				username => $params->{pref_username},
				password => $params->{pref_password},
				pref_accounts => $params->{pref_accounts},

				cb       => sub {
					# Callback for OK handshake response
					
					push @{ $params->{pref_accounts} }, {
						username => $params->{pref_username},
						password => $params->{pref_password},
					};

					if ( main::DEBUGLOG && $log->is_debug ) {
						$log->debug( "Saving Audioscrobbler accounts: " . Data::Dump::dump( $params->{pref_accounts} ) );
					}

					my $msg  = Slim::Utils::Strings::string('PLUGIN_AUDIOSCROBBLER_VALID_LOGIN');
					my $body = $class->SUPER::handler( $client, $params );

					if ( $params->{AJAX} ) {
						$params->{warning} = $msg;
						$params->{validated}->{valid} = 1;
					}
					else {
						$params->{warning} .= $msg . '<br/>';												
					}

					$callback->( $client, $params, $body, @args );
				},
				ecb      => sub {
					# Callback for any errors
					my $error = shift;

					if ( main::DEBUGLOG && $log->is_debug ) {
						$log->debug( "Error saving Audioscrobbler account: " . Data::Dump::dump( $error ) );
					}
					
					$error = Slim::Utils::Strings::string( 'SETUP_PLUGIN_AUDIOSCROBBLER_LOGIN_ERROR', $error );

					if ( $params->{AJAX} ) {
						$params->{warning} = $error;
						$params->{validated}->{valid} = 0;
					}
					else {
						$params->{warning} .= $error . '<br/>';						
					}

					delete $params->{pref_username};
					delete $params->{pref_password};

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