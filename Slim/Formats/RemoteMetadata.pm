package Slim::Formats::RemoteMetadata;

# $Id$

# Logitech Media Server Copyright 2001-2011 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

=head1 NAME

Slim::Formats::RemoteMetadata

=head1 DESCRIPTION

Allows plugins to register parsers and providers for remote URLs.
Parsers parse incoming metadata and providers return this metadata
for display in various places in the UIs.

=head1 METHODS

=cut

use strict;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

use Tie::RegexpHash;

my $log = logger('formats.metadata');

tie my %providers, 'Tie::RegexpHash';
tie my %parsers,   'Tie::RegexpHash';

# This doesn't do anything any more. But I'll leave it in, just in case something was calling us
sub init {}

=head2 registerProvider( PARAMS )

Register a new metadata provider:

  Slim::Formats::RemoteMetadata->registerProvider(
      match => qr/soma\.fm/,
      func  => \&provider,
  ) );

  sub provider {
      my ( $client, $url ) = @_;

      return {
          artist  => 'Artist Name',
          album   => 'Album Name',
          title   => 'Track Title',
          cover   => 'http://...',
          bitrate => 128,
          type    => 'Internet Radio',
      }
  }

=cut

sub registerProvider {
	my ( $class, %params ) = @_;
	
	if ( ref $params{match} ne 'Regexp' ) {
		$log->error( 'registerProvider called without a regular expression' );
		return;
	}
	
	if ( ref $params{func} ne 'CODE' ) {
		$log->error( 'registerProider called without a code reference' );
		return;
	}
	
	$providers{ $params{match} } = $params{func};
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		my $name = Slim::Utils::PerlRunTime::realNameForCodeRef( $params{func} );
		$log->debug( "Registered new metadata provider for " . $params{match} . ": $name" );
	}
	
	return 1;
}

sub getProviderFor {
	my ( $class, $url ) = @_;
	
	return $providers{ $url };
}

=head2 registerParser( PARAMS )

Register a new metadata parser.  This parser will be called anytime
new metadata is available for a stream.  Depending on the type of stream,
this may be Icy metadata strings, or binary WMA metadata.

Your function should return 1 if you handled the data, or return 0
if you want the standard metadata functions to handle the data.

  Slim::Formats::RemoteMetadata->registerParser(
      match => qr/soma\.fm/,
      func  => \&parser,
  ) );

  sub parser {
      my ( $client, $url, $metadata ) = @_;

      # parse the data

      # store the data, this is up to you

      return 1;
  }

=cut

sub registerParser {
	my ( $class, %params ) = @_;
	
	if ( ref $params{match} ne 'Regexp' ) {
		$log->error( 'registerParser called without a regular expression' );
		return;
	}
	
	if ( ref $params{func} ne 'CODE' ) {
		$log->error( 'registerParser called without a code reference' );
		return;
	}
	
	$parsers{ $params{match} } = $params{func};
	
	if ( main::DEBUGLOG && $log->is_debug ) {
		my $name = Slim::Utils::PerlRunTime::realNameForCodeRef( $params{func} );
		$log->debug( "Registered new metadata parser for " . $params{match} . ": $name" );
	}
	
	return 1;
}

sub getParserFor {
	my ( $class, $url ) = @_;
	
	return $parsers{ $url };
}

1;