package Slim::Plugin::AudioScrobbler::Settings;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Misc qw(safe_md5_hex);

use Slim::Utils::Log;
use Slim::Utils::Prefs;

use Slim::Plugin::AudioScrobbler::API::LastFM;
use Slim::Plugin::AudioScrobbler::API::ListenBrainz;

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

			$params->{pref_accounts} = [
				grep {
					my $account = $_;
					my $accountId = Slim::Plugin::AudioScrobbler::Plugin::getAccountId($account);

					grep {
						my $todelete = $_;
						main::INFOLOG && $log->is_info && $log->info("Checking account $accountId for deletion: $todelete");
						$todelete ne $accountId
					} @$delete;
				} @{ $params->{pref_accounts} }
			];
		}

		my $service = $params->{pref_api_type} || 'lastfm';
		my $serviceHandler;

		my $duplicateAccount = grep {
			$_->{username} eq $params->{pref_username}
				&& $_->{api_type} eq $service
				&& (!$_->{api_url} || $_->{api_url} eq $params->{pref_api_url});
		} @{ $params->{pref_accounts} };

		if ( !$duplicateAccount && $params->{pref_password} && $service eq 'lastfm' ) {
			# Last.fm Password (MD5)
			$params->{pref_password} = safe_md5_hex( $params->{pref_password} );

			$serviceHandler = 'Slim::Plugin::AudioScrobbler::API::LastFM';
		}
		elsif ( !$duplicateAccount && $params->{pref_password} && $service eq 'listenbrainz' ) {
			# ListenBrainz API key
			$params->{pref_password} = $params->{pref_password};

			$serviceHandler = 'Slim::Plugin::AudioScrobbler::API::ListenBrainz';
		}

		# If the user added a username/password, we need to verify their info
		if ($serviceHandler) {
			eval "require $serviceHandler";
			if ($@) {
				$log->error("Failed to load service handler $serviceHandler: $@");
			}
			else {
				main::INFOLOG && $log->is_info && $log->info("Validating credentials for $service ($params->{pref_username})");
				$serviceHandler->validate( {
					username => $params->{pref_username},
					password => $params->{pref_password},
					api_type => $params->{pref_api_type},
					api_url  => $params->{pref_api_url},
					cb       => sub {
						my $msg = shift;

						push @{ $params->{pref_accounts} }, {
							username    => $params->{pref_username} || $params->{pref_api_url},
							password    => $params->{pref_password},
							api_type    => $params->{pref_api_type},
							api_url     => $params->{pref_api_url},
						};

						if ( main::DEBUGLOG && $log->is_debug ) {
							$log->debug( "Saving Audioscrobbler accounts: " . Data::Dump::dump( $params->{pref_accounts} ) );
						}

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

						if ( $params->{AJAX} ) {
							$params->{warning} = $error;
							$params->{validated}->{valid} = 0;
						}
						else {
							$params->{warning} .= $error . '<br/>';
						}

						delete $params->{pref_username};
						delete $params->{pref_password};
						delete $params->{pref_api_url};
						delete $params->{pref_api_type};

						my $body = $class->SUPER::handler( $client, $params );
						$callback->( $client, $params, $body, @args );
					},
				} );

				return;
			}
		}
	}

	return $class->SUPER::handler( $client, $params );
}

1;