package Slim::Networking::SimpleHTTP::Base;

# Logitech Media Server Copyright 2003-2020 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Utils::Accessor);

use Exporter::Lite;
use HTTP::Date ();
use HTTP::Request;
use URI::Escape qw(uri_escape_utf8);

our @EXPORT = qw(hasZlib unzip _cacheKey);

__PACKAGE__->mk_accessor( rw => qw(
	cb ecb _params _log type url error code mess headers contentRef cacheTime cachedResponse
) );

BEGIN {
	my $hasZlib;

	sub hasZlib {
		return $hasZlib if defined $hasZlib;

		$hasZlib = 0;
		eval {
			require Compress::Raw::Zlib;
			require IO::Compress::Gzip::Constants;
			$hasZlib = 1;
		};
	}
}

use Slim::Utils::Cache;
use Slim::Utils::Prefs;

my $prefs = preferences('server');

sub params {
	my ($self, $key, $value) = @_;

	if ( !defined $key ) {
		return $self->_params;
	}
	elsif ( $value ) {
		$self->_params->{$key} = $value;
	}
	else {
		return $self->_params->{$key};
	}
}

sub get { shift->_createHTTPRequest( GET => @_ ) }

sub post { shift->_createHTTPRequest( POST => @_ ) }

sub put { shift->_createHTTPRequest( PUT => @_ ) }

sub delete { shift->_createHTTPRequest( DELETE => @_ ) }

sub head { shift->_createHTTPRequest( HEAD => @_ ) }

sub _createHTTPRequest {
	my $self = shift;
	my $type = shift;
	my $url  = shift;

	$self->type( $type );
	$self->url( $url );

	my $params = $self->_params || {};
	my $client = $params->{params}->{client} if $params->{params};
	my $log    = $self->_log;

	# Check for cached response
	if ( $params->{cache} ) {
		my $cache = Slim::Utils::Cache->new();

		if ( my $data = $cache->get( _cacheKey($self->url, $client) ) ) {
			# make sure this is a cached response, and not some random other cached value using the same key
			if (ref $data && $data->{_time}) {
				$self->cachedResponse( $data );

				if ( $self->shouldNotRevalidate($data) ) {
					main::DEBUGLOG && $log->is_debug && $log->debug("Using cached response [$url]");
					return $self->sendCachedResponse();
				}
			}
		}
	}

	main::DEBUGLOG && $log->debug("${type}ing $url");

	my $timeout
		=  $params->{Timeout}
		|| $params->{timeout}
		|| $prefs->get('remotestreamtimeout');

	my $request = $params->{request};
	if (!($request && ref $request eq 'HTTP::Request')) {
		$request = HTTP::Request->new( $type => $url );
	}

	if ( @_ % 2 ) {
		$request->content( pop @_ );
	}

	# If cached, add If-None-Match and If-Modified-Since headers
	my $data = $self->cachedResponse;
	if ( $data && ref $data && $data->{headers} ) {
		# gzip encoded results come with a -gzip postfix which needs to be removed, or the etag would not match
		my $etag = $data->{headers}->header('ETag') || undef;
		$etag =~ s/-gzip// if $etag;

		# if the last_modified value is a UNIX timestamp, convert it
		my $lastModified = $data->{headers}->last_modified || undef;
		$lastModified = HTTP::Date::time2str($lastModified) if $lastModified && $lastModified !~ /\D/;

		unshift @_, (
			'If-None-Match'     => $etag,
			'If-Modified-Since' => $lastModified
		);
	}

	# request compressed data if we have zlib
	if ( hasZlib() && !$params->{saveAs} ) {
		unshift @_, (
			'Accept-Encoding' => 'gzip',
		);
	}

	# Add Accept-Language header
	my $lang;
	if ( $client ) {
		$lang = $client->languageOverride(); # override from comet request
	}

	$lang ||= $prefs->get('language') || 'en';
	$lang =~ s/_/-/g;

	unshift @_, (
		'Accept-Language' => lc($lang),
	);

	if ( @_ ) {
		$request->header( @_ );
	}

	return wantarray ? ($request, $timeout) : $request;
}

sub shouldNotRevalidate {
	my ($self, $data) = @_;

	# If the data was cached within the past 5 minutes,
	# return it immediately without revalidation, to improve
	# UI experience
	return $data->{_no_revalidate} || time - $data->{_time} < 300;
}

sub sendCachedResponse {}

sub isNotModifiedResponse {
	my ($self, $res) = @_;

	if ( $self->cachedResponse && $res->code == 304) {
		my $params = $self->_params;
		my $client = $params->{params}->{client} if $params->{params};

		main::DEBUGLOG && $self->_log->debug("Remote file not modified, using cached content");

		# update the cache time so we get another 5 minutes with no revalidation
		my $cache = Slim::Utils::Cache->new();
		$self->cachedResponse->{_time} = time;
		my $expires = $self->cachedResponse->{_expires} || undef;
		$cache->set( _cacheKey($self->url, $client), $self->cachedResponse, $expires );

		return 1;
	}
}

sub processResponse {
	my ($self, $res) = @_;

	my $params = $self->_params;
	my $client = $params->{params}->{client} if $params->{params};

	$self->contentRef( $res->content_ref );

	# unzip if necessary
	if ( hasZlib() && (my $output = unzip($res)) ) {
		# Formats::XML requires a scalar ref
		$self->contentRef( \$output );
	}

	# cache the response if requested
	if ( $params->{cache} ) {

		if ( Slim::Utils::Misc::shouldCacheURL( $self->url ) ) {

			# By default, cached content can live for at most 1 day, this helps control the
			# size of the cache.  We use ETag/Last Modified to check for stale data during
			# this time.
			my $max = 60 * 60 * 24 + 1;
			my $expires; # undefined until max-age or expires header is seen, or caller defines it
			my $no_revalidate;

			if ( $params->{expires} ) {
				# An explicit expiration time from the caller
				$expires = $params->{expires};
			}
			else {
				# If we see max-age or an Expires header, use them
				if ( my $cc = $res->header('Cache-Control') ) {
					if ( $cc =~ /max-age=(-?\d+)/i ) {
						$expires = $1;
					}

					if ( $cc =~ /no-cache|no-store|must-revalidate/i ) {
						$expires = 0;
					}
				}
				elsif ( my $expire_date = $res->header('Expires') ) {
					$expires = HTTP::Date::str2time($expire_date) - time;
				}
			}

			# Don't cache if response is already stale, indicated by -ve expiry time.
			# Remark: Caching with a negative expiry time is treated as "Never expire" by
			# Slim::Utils::Cache/DbCache. Probably not what is wanted.
			# Example seen: Server doesn't return Cache-Control header, but does return
			# 'expires: Thu, 01 Jan 1970 00:00:00 GMT'.
			if ( $expires && $expires < 0 ) {
				$expires = 0;
			}

			# Don't cache for more than $max
			if ( $expires && $expires > $max ) {
				$expires = $max;
			}

			$self->cacheTime( $expires );

			# Only cache if we found an expiration time
			if ( $expires ) {
				if ( $expires < $max ) {
					# if we have an explicit expiration time, we can avoid revalidation
					$no_revalidate = 1;
				}

				$self->cacheResponse( $expires, $no_revalidate, $client );
			}
			else {
				my $log = $self->_log;
				if ( main::DEBUGLOG && $log->is_debug ) {
					if (defined $expires) {
						$log->debug(sprintf("Not caching [%s], cache headers forbid, or apparently stale", $self->url));
					}
					else {
						$log->debug(sprintf("Not caching [%s], no expiration set and missing cache headers", $self->url));
					}
				}
			}
		}
	}
}

sub cacheResponse {
	my ( $self, $expires, $norevalidate, $client ) = @_;

	my $log = $self->_log;
	if ( main::INFOLOG && $log->is_info ) {
		$log->info(sprintf("Caching [%s] for %d seconds", $self->url, $expires));
	}

	my $cache = Slim::Utils::Cache->new();

	my $data = {
		code     => $self->code,
		mess     => $self->mess,
		headers  => $self->headers,
		content  => $self->content,
		_time    => time,
		_expires => $expires,
		_no_revalidate => $norevalidate,
	};

	$cache->set( _cacheKey($self->url, $client), $data, $expires );
}

sub prepareCachedResponse {
	my ($self) = @_;

	my $data = $self->cachedResponse;

	# populate the object with cached data
	$self->code( $data->{code} );
	$self->mess( $data->{mess} );
	$self->headers( $data->{headers} );
	$self->contentRef( \$data->{content} );
}

sub _cacheKey {
	my ( $url, $client ) = @_;

	my $cachekey = $url;

	if ($client) {
		$cachekey .= '-' . ($client->languageOverride || '');
	}

	return uri_escape_utf8($cachekey);
}


sub unzip {
	my ($response) = @_;

	if ( my $ce = $response->header('Content-Encoding') ) {

		my ($x, $status) = Compress::Raw::Zlib::Inflate->new( {
			-WindowBits => -Compress::Raw::Zlib::MAX_WBITS(),
		} );

		if ( $ce eq 'gzip' ) {
			_removeGzipHeader( $response->content_ref );
		}

		my $output = '';
		$status = $x->inflate( $response->content_ref, $output );

		return $output;
	}
}

# From Compress::Zlib, to avoid having to include all
# of new Compress::Zlib and IO::* compress modules
sub _removeGzipHeader($)
{
    my $string = shift ;

    return Compress::Raw::Zlib::Z_DATA_ERROR()
        if length($$string) < IO::Compress::Gzip::Constants::GZIP_MIN_HEADER_SIZE();

    my ($magic1, $magic2, $method, $flags, $time, $xflags, $oscode) =
        unpack ('CCCCVCC', $$string);

    return Compress::Raw::Zlib::Z_DATA_ERROR()
        unless $magic1 == IO::Compress::Gzip::Constants::GZIP_ID1() and $magic2 == IO::Compress::Gzip::Constants::GZIP_ID2() and
           $method == Compress::Raw::Zlib::Z_DEFLATED() and !($flags & IO::Compress::Gzip::Constants::GZIP_FLG_RESERVED()) ;
    substr($$string, 0, IO::Compress::Gzip::Constants::GZIP_MIN_HEADER_SIZE()) = '' ;

    # skip extra field
    if ($flags & IO::Compress::Gzip::Constants::GZIP_FLG_FEXTRA())
    {
        return Compress::Raw::Zlib::Z_DATA_ERROR()
            if length($$string) < IO::Compress::Gzip::Constants::GZIP_FEXTRA_HEADER_SIZE();

        my ($extra_len) = unpack ('v', $$string);
        $extra_len += IO::Compress::Gzip::Constants::GZIP_FEXTRA_HEADER_SIZE();
        return Compress::Raw::Zlib::Z_DATA_ERROR()
            if length($$string) < $extra_len ;

        substr($$string, 0, $extra_len) = '';
    }

    # skip orig name
    if ($flags & IO::Compress::Gzip::Constants::GZIP_FLG_FNAME())
    {
        my $name_end = index ($$string, IO::Compress::Gzip::Constants::GZIP_NULL_BYTE());
        return Compress::Raw::Zlib::Z_DATA_ERROR()
           if $name_end == -1 ;
        substr($$string, 0, $name_end + 1) =  '';
    }

    # skip comment
    if ($flags & IO::Compress::Gzip::Constants::GZIP_FLG_FCOMMENT())
    {
        my $comment_end = index ($$string, IO::Compress::Gzip::Constants::GZIP_NULL_BYTE());
        return Compress::Raw::Zlib::Z_DATA_ERROR()
            if $comment_end == -1 ;
        substr($$string, 0, $comment_end + 1) = '';
    }

    # skip header crc
    if ($flags & IO::Compress::Gzip::Constants::GZIP_FLG_FHCRC())
    {
        return Compress::Raw::Zlib::Z_DATA_ERROR()
            if length ($$string) < IO::Compress::Gzip::Constants::GZIP_FHCRC_SIZE();
        substr($$string, 0, IO::Compress::Gzip::Constants::GZIP_FHCRC_SIZE()) = '';
    }

    return Compress::Raw::Zlib::Z_OK();
}

sub content { ${ shift->contentRef || \'' } }

1;