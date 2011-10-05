# ======================================================================
#
# Copyright (C) 2000-2004 Paul Kulchenko (paulclinger@yahoo.com)
#
# SOAP::Lite is free software; you can redistribute it
# and/or modify it under the same terms as Perl itself.
#
# $Id: /sd/slim/7.6/branches/lms/server/Slim/Plugin/UPnP/lib/SOAP/Constants.pm 75368 2010-12-16T04:09:11.731914Z andy  $
#
# ======================================================================
package SOAP::Constants;
use strict;
use SOAP::Lite;

our $VERSION = 0.712;

use constant    URI_1999_SCHEMA_XSD    => "http://www.w3.org/1999/XMLSchema";
use constant    URI_1999_SCHEMA_XSI    => "http://www.w3.org/1999/XMLSchema-instance";
use constant    URI_2000_SCHEMA_XSD    => "http://www.w3.org/2000/10/XMLSchema";
use constant    URI_2000_SCHEMA_XSI    => "http://www.w3.org/2000/10/XMLSchema-instance";
use constant    URI_2001_SCHEMA_XSD    => "http://www.w3.org/2001/XMLSchema";
use constant    URI_2001_SCHEMA_XSI    => "http://www.w3.org/2001/XMLSchema-instance";
use constant    URI_LITERAL_ENC        => "";
use constant    URI_SOAP11_ENC         => "http://schemas.xmlsoap.org/soap/encoding/";
use constant    URI_SOAP11_ENV         => "http://schemas.xmlsoap.org/soap/envelope/";
use constant    URI_SOAP11_NEXT_ACTOR  => "http://schemas.xmlsoap.org/soap/actor/next";
use constant    URI_SOAP12_ENC         => "http://www.w3.org/2003/05/soap-encoding";
use constant    URI_SOAP12_ENV         => "http://www.w3.org/2003/05/soap-envelope";
use constant    URI_SOAP12_NOENC       => "http://www.w3.org/2003/05/soap-envelope/encoding/none";
use constant    URI_SOAP12_NEXT_ACTOR  => "http://www.w3.org/2003/05/soap-envelope/role/next";

use vars qw($NSMASK $ELMASK);

$NSMASK = '[a-zA-Z_:][\w.\-:]*';
$ELMASK = '^(?![xX][mM][lL])[a-zA-Z_][\w.\-]*$';

use vars qw($NEXT_ACTOR $NS_ENV $NS_ENC $NS_APS
    $FAULT_CLIENT $FAULT_SERVER $FAULT_VERSION_MISMATCH
    $HTTP_ON_FAULT_CODE $HTTP_ON_SUCCESS_CODE $FAULT_MUST_UNDERSTAND
    $NS_XSI_ALL $NS_XSI_NILS %XML_SCHEMAS $DEFAULT_XML_SCHEMA
    $DEFAULT_HTTP_CONTENT_TYPE
    $SOAP_VERSION %SOAP_VERSIONS $WRONG_VERSION
    $NS_SL_HEADER $NS_SL_PERLTYPE $PREFIX_ENV $PREFIX_ENC
    $DO_NOT_USE_XML_PARSER $DO_NOT_CHECK_MUSTUNDERSTAND
    $DO_NOT_USE_CHARSET $DO_NOT_PROCESS_XML_IN_MIME
    $DO_NOT_USE_LWP_LENGTH_HACK $DO_NOT_CHECK_CONTENT_TYPE
    $MAX_CONTENT_SIZE $PATCH_HTTP_KEEPALIVE $DEFAULT_PACKAGER
    @SUPPORTED_ENCODING_STYLES $OBJS_BY_REF_KEEPALIVE
    $DEFAULT_CACHE_TTL
    %XML_SCHEMA_OF
);

$FAULT_CLIENT           = 'Client';
$FAULT_SERVER           = 'Server';
$FAULT_VERSION_MISMATCH = 'VersionMismatch';
$FAULT_MUST_UNDERSTAND  = 'MustUnderstand';

$HTTP_ON_SUCCESS_CODE = 200; # OK
$HTTP_ON_FAULT_CODE   = 500; # INTERNAL_SERVER_ERROR

@SUPPORTED_ENCODING_STYLES = ( URI_LITERAL_ENC,URI_SOAP11_ENC,URI_SOAP12_ENC,URI_SOAP12_NOENC );

$WRONG_VERSION = 'Wrong SOAP version specified.';

$SOAP_VERSION = '1.1';
%SOAP_VERSIONS = (
    1.1 => {
        NEXT_ACTOR                => URI_SOAP11_NEXT_ACTOR,
        NS_ENV                    => URI_SOAP11_ENV,
        NS_ENC                    => URI_SOAP11_ENC,
        DEFAULT_XML_SCHEMA        => URI_2001_SCHEMA_XSD,
        DEFAULT_HTTP_CONTENT_TYPE => 'text/xml',
    },
    1.2 => {
        NEXT_ACTOR                => URI_SOAP12_NEXT_ACTOR,
        NS_ENV                    => URI_SOAP12_ENV,
        NS_ENC                    => URI_SOAP12_ENC,
        DEFAULT_XML_SCHEMA        => URI_2001_SCHEMA_XSD,
        DEFAULT_HTTP_CONTENT_TYPE => 'application/soap+xml',
    },
);

# schema namespaces
%XML_SCHEMAS = ( # The '()' is necessary to put constants in SCALAR form
    URI_1999_SCHEMA_XSD() => 'SOAP::XMLSchema1999',
    URI_2001_SCHEMA_XSD() => 'SOAP::XMLSchema2001',
    URI_SOAP11_ENC()      => 'SOAP::XMLSchemaSOAP1_1',
    URI_SOAP12_ENC()      => 'SOAP::XMLSchemaSOAP1_2',
);

# schema namespaces
%XML_SCHEMA_OF = ( # The '()' is necessary to put constants in SCALAR form
    URI_1999_SCHEMA_XSD() => 'XMLSchema1999',
    URI_2001_SCHEMA_XSD() => 'XMLSchema2001',
    URI_SOAP11_ENC()      => 'XMLSchemaSOAP1_1',
    URI_SOAP12_ENC()      => 'XMLSchemaSOAP1_2',
);


$NS_XSI_ALL = join join('|', map {"$_-instance"} grep {/XMLSchema/} keys %XML_SCHEMAS), '(?:', ')';
$NS_XSI_NILS = join join('|', map { my $class = $XML_SCHEMAS{$_} . '::Serializer'; "\{($_)-instance\}" . $class->nilValue
                                } grep {/XMLSchema/} keys %XML_SCHEMAS),
                  '(?:', ')';

# ApacheSOAP namespaces
$NS_APS = 'http://xml.apache.org/xml-soap';

# SOAP::Lite namespace
$NS_SL_HEADER   = 'http://namespaces.soaplite.com/header';
$NS_SL_PERLTYPE = 'http://namespaces.soaplite.com/perl';

# default prefixes
$PREFIX_ENV = 'soap';
$PREFIX_ENC = 'soapenc';

# others
$DO_NOT_USE_XML_PARSER = 0;
$DO_NOT_CHECK_MUSTUNDERSTAND = 0;
$DO_NOT_USE_CHARSET = 0;
$DO_NOT_PROCESS_XML_IN_MIME = 0;
$DO_NOT_USE_LWP_LENGTH_HACK = 0;
$DO_NOT_CHECK_CONTENT_TYPE = 0;
$PATCH_HTTP_KEEPALIVE = 1;
$OBJS_BY_REF_KEEPALIVE = 600; # seconds

# TODO - use default packager constant somewhere
$DEFAULT_PACKAGER = "SOAP::Packager::MIME";
$DEFAULT_CACHE_TTL = 0;

1;

__END__

=pod

=head1 NAME

SOAP::Constants - SOAP::Lite provides several variables to allows programmers and users to modify the behavior of SOAP::Lite in specific ways.

=head1 DESCRIPTION

A number of "constant" values are provided by means of this namespace. The values aren't constants in the strictest sense; the purpose of the values detailed here is to allow the application to change them if it desires to alter the specific behavior governed.

=head1 CONSTANTS

=head2 $DO_NOT_USE_XML_PARSER

The SOAP::Lite package attempts to locate and use the L<XML::Parser> package, falling back on an internal, pure-Perl parser in its absence. This package is a fast parser, based on the Expat parser developed by James Clark. If the application sets this value to 1, there will be no attempt to locate or use XML::Parser. There are several reasons you might choose to do this. If the package will never be made available, there is no reason to perform the test. Setting this parameter is less time-consuming than the test for the package would be. Also, the XML::Parser code links against the Expat libraries for the C language. In some environments, this could cause a problem when mixed with other applications that may be linked against a different version of the same libraries. This was once the case with certain combinations of Apache, mod_perl and XML::Parser.

=head2 $DO_NOT_USE_CHARSET

Unless this parameter is set to 1, outgoing Content-Type headers will include specification of the character set used in encoding the message itself. Not all endpoints (client or server) may be able to properly deal with that data on the content header, however. If dealing with an endpoint that expects to do a more literal examination of the header as whole (as opposed to fully parsing it), this parameter may prove useful.

=head2 $DO_NOT_CHECK_CONTENT_TYPE

The content-type itself for a SOAP message is rather clearly defined, and in most cases, an application would have no reason to disable the testing of that header. This having been said, the content-type for SOAP 1.2 is still only a recommended draft, and badly coded endpoints might send valid messages with invalid Content-Type headers. While the "right" thing to do would be to reject such messages, that isn't always an option. Setting this parameter to 1 allows the toolkit to skip the content-type test.

=head2 $PATCH_HTTP_KEEPALIVE

SOAP::Lite's HTTP Transport module attempts to provide a simple patch to
LWP::Protocol to enable HTTP Keep Alive. By default, this patch is turned
off, if however you would like to turn on the experimental patch change the
constant like so:

  $SOAP::Constants::PATCH_HTTP_KEEPALIVE = 1;

=head1 ACKNOWLEDGEMENTS

Special thanks to O'Reilly publishing which has graciously allowed SOAP::Lite to republish and redistribute large excerpts from I<Programming Web Services with Perl>, mainly the SOAP::Lite reference found in Appendix B.

=head1 COPYRIGHT

Copyright (C) 2000-2004 Paul Kulchenko. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHORS

Paul Kulchenko (paulclinger@yahoo.com)

Randy J. Ray (rjray@blackperl.com)

Byrne Reese (byrne@majordojo.com)

=cut
