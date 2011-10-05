# ======================================================================
#
# Copyright (C) 2000-2005 Paul Kulchenko (paulclinger@yahoo.com)
# SOAP::Lite is free software; you can redistribute it
# and/or modify it under the same terms as Perl itself.
#
# $Id: /sd/slim/7.6/branches/lms/server/Slim/Plugin/UPnP/lib/SOAP/Lite.pm 75368 2010-12-16T04:09:11.731914Z andy  $
#
# ======================================================================

# Formatting hint:
# Target is the source code format laid out in Perl Best Practices (4 spaces
# indent, opening brace on condition line, no cuddled else).
#
# October 2007, Martin Kutter

package SOAP::Lite;

use 5.006; #weak references require perl 5.6
use strict;
our $VERSION = 0.712;
# ======================================================================

package SOAP::XMLSchemaApacheSOAP::Deserializer;

sub as_map {
    my $self = shift;
    return {
        map {
            my $hash = ($self->decode_object($_))[1];
            ($hash->{key} => $hash->{value})
        } @{$_[3] || []}
    };
}
sub as_Map; *as_Map = \&as_map;

# Thank to Kenneth Draper for this contribution
sub as_vector {
    my $self = shift;
    return [ map { scalar(($self->decode_object($_))[1]) } @{$_[3] || []} ];
}
sub as_Vector; *as_Vector = \&as_vector;

# ----------------------------------------------------------------------

package SOAP::XMLSchema::Serializer;

use vars qw(@ISA);

sub xmlschemaclass {
    my $self = shift;
    return $ISA[0] unless @_;
    @ISA = (shift);
    return $self;
}

# ----------------------------------------------------------------------

package SOAP::XMLSchema1999::Serializer;

use vars qw(@EXPORT $AUTOLOAD);

sub AUTOLOAD {
    local($1,$2);
    my($package, $method) = $AUTOLOAD =~ m/(?:(.+)::)([^:]+)$/;
    return if $method eq 'DESTROY';
    no strict 'refs';

    my $export_var = $package . '::EXPORT';
    my @export = @$export_var;

# Removed in 0.69 - this is a total hack. For some reason this is failing
# despite not being a fatal error condition.
#  die "Type '$method' can't be found in a schema class '$package'\n"
#    unless $method =~ s/^as_// && grep {$_ eq $method} @{$export_var};

# This was added in its place - it is still a hack, but it performs the
# necessary substitution. It just does not die.
    if ($method =~ s/^as_// && grep {$_ eq $method} @{$export_var}) {
#      print STDERR "method is now '$method'\n";
    } else {
        return;
    }

    $method =~ s/_/-/; # fix ur-type

    *$AUTOLOAD = sub {
        my $self = shift;
        my($value, $name, $type, $attr) = @_;
        return [$name, {'xsi:type' => "xsd:$method", %$attr}, $value];
    };
    goto &$AUTOLOAD;
}

BEGIN {
    @EXPORT = qw(ur_type
        float double decimal timeDuration recurringDuration uriReference
        integer nonPositiveInteger negativeInteger long int short byte
        nonNegativeInteger unsignedLong unsignedInt unsignedShort unsignedByte
        positiveInteger timeInstant time timePeriod date month year century
        recurringDate recurringDay language
        base64 hex string boolean
    );
    # TODO: replace by symbol table operations...
    # predeclare subs, so ->can check will be positive
    foreach (@EXPORT) { eval "sub as_$_" }
}

sub nilValue { 'null' }

sub anyTypeValue { 'ur-type' }

sub as_base64 {
    my ($self, $value, $name, $type, $attr) = @_;

    # Fixes #30271 for 5.8 and above.
    # Won't fix for 5.6 and below - perl can't handle unicode before
    # 5.8, and applying pack() to everything is just a slowdown.
    if (eval "require Encode; 1") {
        if (Encode::is_utf8($value)) {
            if (Encode->can('_utf8_off')) { # the quick way, but it may change in future Perl versions.
                Encode::_utf8_off($value);
            }
            else {
                $value = pack('C*',unpack('C*',$value)); # the slow but safe way,
                # but this fallback works always.
            }
        }
    }

    require MIME::Base64;
    return [
        $name,
        {
            'xsi:type' => SOAP::Utils::qualify($self->encprefix => 'base64'),
            %$attr
        },
        MIME::Base64::encode_base64($value,'')
    ];
}

sub as_hex {
    my ($self, $value, $name, $type, $attr) = @_;
    return [
        $name,
        {
            'xsi:type' => 'xsd:hex', %$attr
        },
        join '', map {
            uc sprintf "%02x", ord
        } split '', $value
    ];
}

sub as_long {
    my($self, $value, $name, $type, $attr) = @_;
    return [
        $name,
        {'xsi:type' => 'xsd:long', %$attr},
        $value
    ];
}

sub as_dateTime {
    my ($self, $value, $name, $type, $attr) = @_;
    return [$name, {'xsi:type' => 'xsd:dateTime', %$attr}, $value];
}

sub as_string {
    my ($self, $value, $name, $type, $attr) = @_;
    die "String value expected instead of @{[ref $value]} reference\n"
        if ref $value;
    return [
        $name,
        {'xsi:type' => 'xsd:string', %$attr},
        SOAP::Utils::encode_data($value)
    ];
}

sub as_anyURI {
    my($self, $value, $name, $type, $attr) = @_;
    die "String value expected instead of @{[ref $value]} reference\n" if ref $value;
    return [
        $name,
        {'xsi:type' => 'xsd:anyURI', %$attr},
        SOAP::Utils::encode_data($value)
    ];
}

sub as_undef { $_[1] ? '1' : '0' }

sub as_boolean {
    my $self = shift;
    my($value, $name, $type, $attr) = @_;
    # fix [ 1204279 ] Boolean serialization error
    return [
        $name,
        {'xsi:type' => 'xsd:boolean', %$attr},
        ( $value ne 'false' && $value ) ? 'true' : 'false'
    ];
}

sub as_float {
    my($self, $value, $name, $type, $attr) = @_;
    return [
        $name,
        {'xsi:type' => 'xsd:float', %$attr},
        $value
    ];
}

# ----------------------------------------------------------------------

package SOAP::XMLSchema2001::Serializer;

use vars qw(@EXPORT);

# no more warnings about "used only once"
*AUTOLOAD if 0;

*AUTOLOAD = \&SOAP::XMLSchema1999::Serializer::AUTOLOAD;

BEGIN {
  @EXPORT = qw(anyType anySimpleType float double decimal dateTime
               timePeriod gMonth gYearMonth gYear century
               gMonthDay gDay duration recurringDuration anyURI
               language integer nonPositiveInteger negativeInteger
               long int short byte nonNegativeInteger unsignedLong
               unsignedInt unsignedShort unsignedByte positiveInteger
               date time string hex base64 boolean
               QName
  );
  # Add QName to @EXPORT
  # predeclare subs, so ->can check will be positive
  foreach (@EXPORT) { eval "sub as_$_" }
}

sub nilValue { 'nil' }

sub anyTypeValue { 'anyType' }

sub as_long;        *as_long = \&SOAP::XMLSchema1999::Serializer::as_long;
sub as_float;       *as_float = \&SOAP::XMLSchema1999::Serializer::as_float;
sub as_string;      *as_string = \&SOAP::XMLSchema1999::Serializer::as_string;
sub as_anyURI;      *as_anyURI = \&SOAP::XMLSchema1999::Serializer::as_anyURI;

# TODO - QNames still don't work for 2001 schema!
sub as_QName;       *as_QName = \&SOAP::XMLSchema1999::Serializer::as_string;
sub as_hex;         *as_hex = \&as_hexBinary;
sub as_base64;      *as_base64 = \&as_base64Binary;
sub as_timeInstant; *as_timeInstant = \&as_dateTime;

# only 0 and 1 allowed - that's easy...
sub as_undef {
    $_[1]
    ? 'true'
    : 'false'
}

sub as_hexBinary {
    my ($self, $value, $name, $type, $attr) = @_;
    return [
        $name,
        {'xsi:type' => 'xsd:hexBinary', %$attr},
        join '', map {
                uc sprintf "%02x", ord
            } split '', $value
    ];
}

sub as_base64Binary {
    my ($self, $value, $name, $type, $attr) = @_;

    # Fixes #30271 for 5.8 and above.
    # Won't fix for 5.6 and below - perl can't handle unicode before
    # 5.8, and applying pack() to everything is just a slowdown.
    if (eval "require Encode; 1") {
        if (Encode::is_utf8($value)) {
            if (Encode->can('_utf8_off')) { # the quick way, but it may change in future Perl versions.
                Encode::_utf8_off($value);
            }
            else {
                $value = pack('C*',unpack('C*',$value)); # the slow but safe way,
                # but this fallback works always.
            }
        }
    }

    require MIME::Base64;
    return [
        $name,
        {
            'xsi:type' => 'xsd:base64Binary', %$attr
        },
        MIME::Base64::encode_base64($value,'')
    ];
}

sub as_boolean {
    my ($self, $value, $name, $type, $attr) = @_;
    # fix [ 1204279 ] Boolean serialization error
    return [
        $name,
        {
            'xsi:type' => 'xsd:boolean', %$attr
        },
        ( $value ne 'false' && $value )
            ? 'true'
            : 'false'
    ];
}


# ======================================================================

package SOAP::Utils;

sub qualify {
    $_[1]
        ? $_[1] =~ /:/
            ? $_[1]
            : join(':', $_[0] || (), $_[1])
        : defined $_[1]
            ? $_[0]
            : ''
    }

sub overqualify (&$) {
    for ($_[1]) {
        &{$_[0]};
        s/^:|:$//g
    }
}

sub disqualify {
    (my $qname = shift) =~ s/^($SOAP::Constants::NSMASK?)://;
    return $qname;
}

sub splitqname {
    local($1,$2);
    $_[0] =~ /^(?:([^:]+):)?(.+)$/;
    return ($1,$2)
}

sub longname {
    defined $_[0]
        ? sprintf('{%s}%s', $_[0], $_[1])
        : $_[1]
}

sub splitlongname {
    local($1,$2);
    $_[0] =~ /^(?:\{(.*)\})?(.+)$/;
    return ($1,$2)
}

# Q: why only '&' and '<' are encoded, but not '>'?
# A: because it is not required according to XML spec.
#
# [http://www.w3.org/TR/REC-xml#syntax]
# The ampersand character (&) and the left angle bracket (<) may appear in
# their literal form only when used as markup delimiters, or within a comment,
# a processing instruction, or a CDATA section. If they are needed elsewhere,
# they must be escaped using either numeric character references or the
# strings "&amp;" and "&lt;" respectively. The right angle bracket (>) may be
# represented using the string "&gt;", and must, for compatibility, be
# escaped using "&gt;" or a character reference when it appears in the
# string "]]>" in content, when that string is not marking the end of a
# CDATA section.

my %encode_attribute = ('&' => '&amp;', '>' => '&gt;', '<' => '&lt;', '"' => '&quot;');
sub encode_attribute { (my $e = $_[0]) =~ s/([&<>\"])/$encode_attribute{$1}/g; $e }

my %encode_data = ('&' => '&amp;', '>' => '&gt;', '<' => '&lt;', "\xd" => '&#xd;');
sub encode_data {
    my $e = $_[0];
    if ($e) {
        $e =~ s/([&<>\015])/$encode_data{$1}/g;
        $e =~ s/\]\]>/\]\]&gt;/g;
    }
    $e
}

# methods for internal tree (SOAP::Deserializer, SOAP::SOM and SOAP::Serializer)

sub o_qname { $_[0]->[0] }
sub o_attr  { $_[0]->[1] }
sub o_child { ref $_[0]->[2] ? $_[0]->[2] : undef }
sub o_chars { ref $_[0]->[2] ? undef : $_[0]->[2] }
            # $_[0]->[3] is not used. Serializer stores object ID there
sub o_value { $_[0]->[4] }
sub o_lname { $_[0]->[5] }
sub o_lattr { $_[0]->[6] }

sub format_datetime {
    my ($s,$m,$h,$D,$M,$Y) = (@_)[0,1,2,3,4,5];
    my $time = sprintf("%04d-%02d-%02dT%02d:%02d:%02d",($Y+1900),($M+1),$D,$h,$m,$s);
    return $time;
}

# make bytelength that calculates length in bytes regardless of utf/byte settings
# either we can do 'use bytes' or length will count bytes already
BEGIN {
    sub bytelength;
    *bytelength = eval('use bytes; 1') # 5.6.0 and later?
        ? sub { use bytes; length(@_ ? $_[0] : $_) }
        : sub { length(@_ ? $_[0] : $_) };
}

# ======================================================================

package SOAP::Cloneable;

sub clone {
    my $self = shift;

    return unless ref $self && UNIVERSAL::isa($self => __PACKAGE__);

    my $clone = bless {} => ref($self) || $self;
    for (keys %$self) {
        my $value = $self->{$_};
        $clone->{$_} = ref $value && UNIVERSAL::isa($value => __PACKAGE__) ? $value->clone : $value;
    }
    return $clone;
}

# ======================================================================

package SOAP::Transport;

use vars qw($AUTOLOAD @ISA);
@ISA = qw(SOAP::Cloneable);

use Class::Inspector;


sub DESTROY { SOAP::Trace::objects('()') }

sub new {
    my $self = shift;
    return $self if ref $self;
    my $class = ref($self) || $self;

    SOAP::Trace::objects('()');
    return bless {} => $class;
}

sub proxy {
    my $self = shift;
    $self = $self->new() if not ref $self;

    my $class = ref $self;

    return $self->{_proxy} unless @_;

    $_[0] =~ /^(\w+):/ or die "proxy: transport protocol not specified\n";
    my $protocol = uc "$1"; # untainted now

    # HTTPS is handled by HTTP class
    $protocol =~s/^HTTPS$/HTTP/;

    (my $protocol_class = "${class}::$protocol") =~ s/-/_/g;

    no strict 'refs';
    unless (Class::Inspector->loaded("$protocol_class\::Client")
        && UNIVERSAL::can("$protocol_class\::Client" => 'new')
    ) {
        eval "require $protocol_class";
        die "Unsupported protocol '$protocol'\n"
            if $@ =~ m!^Can\'t locate SOAP/Transport/!;
        die if $@;
    }

    $protocol_class .= "::Client";
    return $self->{_proxy} = $protocol_class->new(endpoint => shift, @_);
}

sub AUTOLOAD {
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
    return if $method eq 'DESTROY';

    no strict 'refs';
    *$AUTOLOAD = sub { shift->proxy->$method(@_) };
    goto &$AUTOLOAD;
}

# ======================================================================

package SOAP::Fault;

use Carp ();

use overload fallback => 1, '""' => "stringify";

sub DESTROY { SOAP::Trace::objects('()') }

sub new {
    my $self = shift;

    unless (ref $self) {
        my $class = $self;
        $self = bless {} => $class;
        SOAP::Trace::objects('()');
    }

    Carp::carp "Odd (wrong?) number of parameters in new()"
        if $^W && (@_ & 1);

    no strict qw(refs);
    while (@_) {
        my $method = shift;
        $self->$method(shift)
            if $self->can($method)
    }

    return $self;
}

sub stringify {
    my $self = shift;
    return join ': ', $self->faultcode, $self->faultstring;
}

sub BEGIN {
    no strict 'refs';
    for my $method (qw(faultcode faultstring faultactor faultdetail)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
                ? shift->new
                : __PACKAGE__->new;
            if (@_) {
                $self->{$field} = shift;
                return $self
            }
            return $self->{$field};
        }
    }
    *detail = \&faultdetail;
}

# ======================================================================

package SOAP::Data;

use vars qw(@ISA @EXPORT_OK);
use Exporter;
use Carp ();
use SOAP::Lite::Deserializer::XMLSchemaSOAP1_2;

@ISA = qw(Exporter);
@EXPORT_OK = qw(name type attr value uri);

sub DESTROY { SOAP::Trace::objects('()') }

sub new {
    my $self = shift;

    unless (ref $self) {
        my $class = $self;
        $self = bless {_attr => {}, _value => [], _signature => []} => $class;
        SOAP::Trace::objects('()');
    }
    no strict qw(refs);
    Carp::carp "Odd (wrong?) number of parameters in new()" if $^W && (@_ & 1);
    while (@_) {
        my $method = shift;
        $self->$method(shift) if $self->can($method)
    }

    return $self;
}

sub name {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__) ? shift->new : __PACKAGE__->new;
    if (@_) {
        my ($name, $uri, $prefix) = shift;
        if ($name) {
            ($uri, $name) = SOAP::Utils::splitlongname($name);
            unless (defined $uri) {
                ($prefix, $name) = SOAP::Utils::splitqname($name);
                $self->prefix($prefix) if defined $prefix;
            } else {
                $self->uri($uri);
            }
        }
        $self->{_name} = $name;

        $self->value(@_) if @_;
        return $self;
    }
    return $self->{_name};
}

sub attr {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
        ? shift->new()
        : __PACKAGE__->new();
    if (@_) {
        $self->{_attr} = shift;
        $self->value(@_) if @_;
        return $self
    }
    return $self->{_attr};
}

sub type {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
        ? shift->new()
        : __PACKAGE__->new();
    if (@_) {
        $self->{_type} = shift;
        $self->value(@_) if @_;
        return $self;
    }
    if (!defined $self->{_type} && (my @types = grep {/^\{$SOAP::Constants::NS_XSI_ALL}type$/o} keys %{$self->{_attr}})) {
        $self->{_type} = (SOAP::Utils::splitlongname(delete $self->{_attr}->{shift(@types)}))[1];
    }
    return $self->{_type};
}

BEGIN {
    no strict 'refs';
    for my $method (qw(root mustUnderstand)) {
        my $field = '_' . $method;
        *$method = sub {
        my $attr = $method eq 'root'
            ? "{$SOAP::Constants::NS_ENC}$method"
            : "{$SOAP::Constants::NS_ENV}$method";
            my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
                ? shift->new
                : __PACKAGE__->new;
            if (@_) {
                $self->{_attr}->{$attr} = $self->{$field} = shift() ? 1 : 0;
                $self->value(@_) if @_;
                return $self;
            }
            $self->{$field} = SOAP::Lite::Deserializer::XMLSchemaSOAP1_2->as_boolean($self->{_attr}->{$attr})
                if !defined $self->{$field} && defined $self->{_attr}->{$attr};
            return $self->{$field};
        }
    }

    for my $method (qw(actor encodingStyle)) {
        my $field = '_' . $method;
        *$method = sub {
            my $attr = "{$SOAP::Constants::NS_ENV}$method";
            my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
                ? shift->new()
                : __PACKAGE__->new();
            if (@_) {
                $self->{_attr}->{$attr} = $self->{$field} = shift;
                $self->value(@_) if @_;
                return $self;
            }
            $self->{$field} = $self->{_attr}->{$attr}
                if !defined $self->{$field} && defined $self->{_attr}->{$attr};
            return $self->{$field};
        }
    }
}

sub prefix {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
        ? shift->new()
        : __PACKAGE__->new();
    return $self->{_prefix} unless @_;
    $self->{_prefix} = shift;
    $self->value(@_) if @_;
    return $self;
}

sub uri {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
        ? shift->new()
        : __PACKAGE__->new();
    return $self->{_uri} unless @_;
    my $uri = $self->{_uri} = shift;
    warn "Usage of '::' in URI ($uri) deprecated. Use '/' instead\n"
        if defined $uri && $^W && $uri =~ /::/;
    $self->value(@_) if @_;
    return $self;
}

sub set_value {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
        ? shift->new()
        : __PACKAGE__->new();
    $self->{_value} = [@_];
    return $self;
}

sub value {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
        ? shift->new()
        : __PACKAGE__->new;
    (@_)
        ? ($self->set_value(@_), return $self)
        : wantarray
            ? return @{$self->{_value}}
            : return $self->{_value}->[0];
}

sub signature {
    my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
        ? shift->new()
        : __PACKAGE__->new();
    (@_)
        ? ($self->{_signature} = shift, return $self)
        : (return $self->{_signature});
}

# ======================================================================

package SOAP::Header;

use vars qw(@ISA);
@ISA = qw(SOAP::Data);

# ======================================================================

package SOAP::Serializer;
use SOAP::Lite::Utils;
use Carp ();
use vars qw(@ISA);

@ISA = qw(SOAP::Cloneable SOAP::XMLSchema::Serializer);

BEGIN {
    # namespaces and anonymous data structures
    my $ns   = 0;
    my $name = 0;
    my $prefix = 'c-';
    sub gen_ns { 'namesp' . ++$ns }
    sub gen_name { join '', $prefix, 'gensym', ++$name }
    sub prefix { $prefix =~ s/^[^\-]+-/$_[1]-/; $_[0]; }
}

sub BEGIN {
    no strict 'refs';

    __PACKAGE__->__mk_accessors(qw(readable level seen autotype typelookup attr maptype
        namespaces multirefinplace encoding signature on_nonserialized context
        ns_uri ns_prefix use_default_ns));

    for my $method (qw(method fault freeform)) { # aliases for envelope
        *$method = sub { shift->envelope($method => @_) }
    }
    # Is this necessary? Seems like work for nothing when a user could just use
    # SOAP::Utils directly.
    # for my $method (qw(qualify overqualify disqualify)) { # import from SOAP::Utils
    #   *$method = \&{'SOAP::Utils::'.$method};
    # }
}

sub DESTROY { SOAP::Trace::objects('()') }

sub new {
    my $self = shift;
    return $self if ref $self;

    my $class = $self;
    $self = bless {
        _level => 0,
        _autotype => 1,
        _readable => 0,
        _ns_uri => '',
        _ns_prefix => '',
        _use_default_ns => 1,
        _multirefinplace => 0,
        _seen => {},
        _typelookup => {
          # this breaks UPnP -Andy
          # 'base64Binary' =>
          #    [10, sub {$_[0] =~ /[^\x09\x0a\x0d\x20-\x7f]/ }, 'as_base64Binary'],
           'zerostring' =>
               [12, sub { $_[0] =~ /^0\d+$/ }, 'as_string'],
            # int (and actually long too) are subtle: the negative range is one greater...
            'int'  =>
               [20, sub {$_[0] =~ /^([+-]?\d+)$/ && ($1 <= 2147483647) && ($1 >= -2147483648); }, 'as_int'],
            'long' =>
               [25, sub {$_[0] =~ /^([+-]?\d+)$/ && $1 <= 9223372036854775807;}, 'as_long'],
            'float'  =>
               [30, sub {$_[0] =~ /^(-?(?:\d+(?:\.\d*)?|\.\d+|NaN|INF)|([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?)$/}, 'as_float'],
            'gMonth' =>
               [35, sub { $_[0] =~ /^--\d\d--(-\d\d:\d\d)?$/; }, 'as_gMonth'],
            'gDay' =>
               [40, sub { $_[0] =~ /^---\d\d(-\d\d:\d\d)?$/; }, 'as_gDay'],
            'gYear' =>
               [45, sub { $_[0] =~ /^-?\d\d\d\d(-\d\d:\d\d)?$/; }, 'as_gYear'],
            'gMonthDay' =>
               [50, sub { $_[0] =~ /^-\d\d-\d\d(-\d\d:\d\d)?$/; }, 'as_gMonthDay'],
            'gYearMonth' =>
               [55, sub { $_[0] =~ /^-?\d\d\d\d-\d\d(Z|([+-]\d\d:\d\d))?$/; }, 'as_gYearMonth'],
            'date' =>
               [60, sub { $_[0] =~ /^-?\d\d\d\d-\d\d-\d\d(Z|([+-]\d\d:\d\d))?$/; }, 'as_date'],
            'time' =>
               [70, sub { $_[0] =~ /^\d\d:\d\d:\d\d(\.\d\d\d)?(Z|([+-]\d\d:\d\d))?$/; }, 'as_time'],
            'dateTime' =>
               [75, sub { $_[0] =~ /^\d\d\d\d-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d\d\d)?(Z|([+-]\d\d:\d\d))?$/; }, 'as_dateTime'],
            'duration' =>
               [80, sub { $_[0] !~m{^-?PT?$} && $_[0] =~ m{^
                        -?   # a optional - sign
                        P
                        (:? \d+Y )?
                        (:? \d+M )?
                        (:? \d+D )?
                        (:?
                            T(:?\d+H)?
                            (:?\d+M)?
                            (:?\d+S)?
                        )?
                        $
                    }x;
               }, 'as_duration'],
            'boolean' =>
               [90, sub { $_[0] =~ /^(true|false)$/i; }, 'as_boolean'],
            'anyURI' =>
               [95, sub { $_[0] =~ /^(urn:|http:\/\/)/i; }, 'as_anyURI'],
            'string' =>
               [100, sub {1}, 'as_string'],
        },
        _encoding => 'UTF-8',
        _objectstack => {},
        _signature => [],
        _maptype => {},
        _on_nonserialized => sub {Carp::carp "Cannot marshall @{[ref shift]} reference" if $^W; return},
        _encodingStyle => $SOAP::Constants::NS_ENC,
        _attr => {
            "{$SOAP::Constants::NS_ENV}encodingStyle" => $SOAP::Constants::NS_ENC,
        },
        _namespaces => {},
        _soapversion => SOAP::Lite->soapversion,
    } => $class;
    $self->register_ns($SOAP::Constants::NS_ENC,$SOAP::Constants::PREFIX_ENC);
    $self->register_ns($SOAP::Constants::NS_ENV,$SOAP::Constants::PREFIX_ENV)
        if $SOAP::Constants::PREFIX_ENV;
    $self->xmlschema($SOAP::Constants::DEFAULT_XML_SCHEMA);
    SOAP::Trace::objects('()');

    no strict qw(refs);
    Carp::carp "Odd (wrong?) number of parameters in new()" if $^W && (@_ & 1);
    while (@_) { my $method = shift; $self->$method(shift) if $self->can($method) }

    return $self;
}

sub ns {
    my $self = shift;
    $self = $self->new() if not ref $self;
    if (@_) {
        my ($u,$p) = @_;
        my $prefix;

        if ($p) {
            $prefix = $p;
        }
        elsif (!$p && !($prefix = $self->find_prefix($u))) {
            $prefix = gen_ns;
        }

        $self->{'_ns_uri'}         = $u;
        $self->{'_ns_prefix'}      = $prefix;
        $self->{'_use_default_ns'} = 0;
        # $self->register_ns($u,$prefix);
        $self->{'_namespaces'}->{$u} = $prefix;
        return $self;
    }
    return $self->{'_ns_uri'};
}

sub default_ns {
    my $self = shift;
    $self = $self->new() if not ref $self;
    if (@_) {
        my ($u) = @_;
        $self->{'_ns_uri'}         = $u;
        $self->{'_ns_prefix'}      = '';
        $self->{'_use_default_ns'} = 1;
        return $self;
    }
    return $self->{'_ns_uri'};
}

sub use_prefix {
    my $self = shift;
    $self = $self->new() if not ref $self;
    warn 'use_prefix has been deprecated. if you wish to turn off or on the '
        . 'use of a default namespace, then please use either ns(uri) or default_ns(uri)';
    if (@_) {
        my $use = shift;
        $self->{'_use_default_ns'} = !$use || 0;
        return $self;
    } else {
        return $self->{'_use_default_ns'};
    }
}
sub uri {
    my $self = shift;
    $self = $self->new() if not ref $self;
#    warn 'uri has been deprecated. if you wish to set the namespace for the request, then please use either ns(uri) or default_ns(uri)';
    if (@_) {
        my $ns = shift;
        if ($self->{_use_default_ns}) {
           $self->default_ns($ns);
        }
        else {
           $self->ns($ns);
        }
#       $self->{'_ns_uri'} = $ns;
#       $self->register_ns($self->{'_ns_uri'}) if (!$self->{_use_default_ns});
        return $self;
    }
    return $self->{'_ns_uri'};
}

sub encodingStyle {
    my $self = shift;
    $self = $self->new() if not ref $self;
    return $self->{'_encodingStyle'} unless @_;

    my $cur_style = $self->{'_encodingStyle'};
    delete($self->{'_namespaces'}->{$cur_style});

    my $new_style = shift;
    if ($new_style eq "") {
        delete($self->{'_attr'}->{"{$SOAP::Constants::NS_ENV}encodingStyle"});
    }
    else {
        $self->{'_attr'}->{"{$SOAP::Constants::NS_ENV}encodingStyle"} = $new_style;
        $self->{'_namespaces'}->{$new_style} = $SOAP::Constants::PREFIX_ENC;
    }
}

# TODO - changing SOAP version can affect previously set encodingStyle
sub soapversion {
    my $self = shift;
    return $self->{_soapversion} unless @_;
    return $self if $self->{_soapversion} eq SOAP::Lite->soapversion;
    $self->{_soapversion} = shift;

    $self->attr({
        "{$SOAP::Constants::NS_ENV}encodingStyle" => $SOAP::Constants::NS_ENC,
    });
    $self->namespaces({
        $SOAP::Constants::NS_ENC => $SOAP::Constants::PREFIX_ENC,
        $SOAP::Constants::PREFIX_ENV ? ($SOAP::Constants::NS_ENV => $SOAP::Constants::PREFIX_ENV) : (),
    });
    $self->xmlschema($SOAP::Constants::DEFAULT_XML_SCHEMA);

    return $self;
}

sub xmlschema {
    my $self = shift->new;
    return $self->{_xmlschema} unless @_;

    my @schema;
    if ($_[0]) {
        @schema = grep {/XMLSchema/ && /$_[0]/} keys %SOAP::Constants::XML_SCHEMAS;
        Carp::croak "More than one schema match parameter '$_[0]': @{[join ', ', @schema]}" if @schema > 1;
        Carp::croak "No schema match parameter '$_[0]'" if @schema != 1;
    }

    # do nothing if current schema is the same as new
    return $self if $self->{_xmlschema} && $self->{_xmlschema} eq $schema[0];

    my $ns = $self->namespaces;

    # delete current schema from namespaces
    if (my $schema = $self->{_xmlschema}) {
        delete $ns->{$schema};
        delete $ns->{"$schema-instance"};
    }

    # add new schema into namespaces
    if (my $schema = $self->{_xmlschema} = shift @schema) {
        $ns->{$schema} = 'xsd';
        $ns->{"$schema-instance"} = 'xsi';
    }

    # and here is the class serializer should work with
    my $class = exists $SOAP::Constants::XML_SCHEMAS{$self->{_xmlschema}}
        ? $SOAP::Constants::XML_SCHEMAS{$self->{_xmlschema}} . '::Serializer'
        : $self;

    $self->xmlschemaclass($class);

    return $self;
}

sub envprefix {
    my $self = shift->new();
    return $self->namespaces->{$SOAP::Constants::NS_ENV} unless @_;
    $self->namespaces->{$SOAP::Constants::NS_ENV} = shift;
    return $self;
}

sub encprefix {
    my $self = shift->new();
    return $self->namespaces->{$SOAP::Constants::NS_ENC} unless @_;
    $self->namespaces->{$SOAP::Constants::NS_ENC} = shift;
    return $self;
}

sub gen_id { sprintf "%U", $_[1] }

sub multiref_object {
    my ($self, $object) = @_;
    my $id = $self->gen_id($object);
    my $seen = $self->seen;
    $seen->{$id}->{count}++;
    $seen->{$id}->{multiref} ||= $seen->{$id}->{count} > 1;
    $seen->{$id}->{value} = $object;
    $seen->{$id}->{recursive} ||= 0;
    return $id;
}

sub recursive_object {
    my $self = shift;
    $self->seen->{$self->gen_id(shift)}->{recursive} = 1;
}

sub is_href {
    my $self = shift;
    my $seen = $self->seen->{shift || return} or return;
    return 1 if $seen->{id};
    return $seen->{multiref}
        && !($seen->{id} = (shift
            || $seen->{recursive}
            || $seen->{multiref} && $self->multirefinplace));
}

sub multiref_anchor {
    my $seen = shift->seen->{my $id = shift || return undef};
    return $seen->{multiref} ? "ref-$id" : undef;
}

sub encode_multirefs {
    my $self = shift;
    return if $self->multirefinplace();

    my $seen = $self->seen();
    map { $_->[1]->{_id} = 1; $_ }
        map { $self->encode_object($seen->{$_}->{value}) }
            grep { $seen->{$_}->{multiref} && !$seen->{$_}->{recursive} }
                keys %$seen;
}

sub maptypetouri {
    my($self, $type, $simple) = @_;

    return $type unless defined $type;
    my($prefix, $name) = SOAP::Utils::splitqname($type);

    unless (defined $prefix) {
        $name =~ s/__|\./::/g;
        $self->maptype->{$name} = $simple
            ? die "Schema/namespace for type '$type' is not specified\n"
            : $SOAP::Constants::NS_SL_PERLTYPE
                unless exists $self->maptype->{$name};
        $type = $self->maptype->{$name}
            ? SOAP::Utils::qualify($self->namespaces->{$self->maptype->{$name}} ||= gen_ns, $type)
            : undef;
    }
    return $type;
}

sub encode_object {
    my($self, $object, $name, $type, $attr) = @_;

    $attr ||= {};
    return $self->encode_scalar($object, $name, $type, $attr)
        unless ref $object;

    my $id = $self->multiref_object($object);

    use vars '%objectstack';           # we'll play with symbol table
    local %objectstack = %objectstack; # want to see objects ONLY in the current tree
    # did we see this object in current tree? Seems to be recursive refs
    $self->recursive_object($object) if ++$objectstack{$id} > 1;
    # return if we already saw it twice. It should be already properly serialized
    return if $objectstack{$id} > 2;

    if (UNIVERSAL::isa($object => 'SOAP::Data')) {
        # use $object->SOAP::Data:: to enable overriding name() and others in inherited classes
        $object->SOAP::Data::name($name)
            unless defined $object->SOAP::Data::name;

        # apply ->uri() and ->prefix() which can modify name and attributes of
        # element, but do not modify SOAP::Data itself
        my($name, $attr) = $self->fixattrs($object);
        $attr = $self->attrstoqname($attr);

        my @realvalues = $object->SOAP::Data::value;
        return [$name || gen_name, $attr] unless @realvalues;

        my $method = "as_" . ($object->SOAP::Data::type || '-'); # dummy type if not defined
        # try to call method specified for this type
        no strict qw(refs);
        my @values = map {
            # store null/nil attribute if value is undef
            local $attr->{SOAP::Utils::qualify(xsi => $self->xmlschemaclass->nilValue)} = $self->xmlschemaclass->as_undef(1)
                unless defined;
            $self->can($method) && $self->$method($_, $name || gen_name, $object->SOAP::Data::type, $attr)
                || $self->typecast($_, $name || gen_name, $object->SOAP::Data::type, $attr)
                || $self->encode_object($_, $name, $object->SOAP::Data::type, $attr)
        } @realvalues;
        $object->SOAP::Data::signature([map {join $;, $_->[0], SOAP::Utils::disqualify($_->[1]->{'xsi:type'} || '')} @values]) if @values;
        return wantarray ? @values : $values[0];
    }

    my $class = ref $object;

    if ($class !~ /^(?:SCALAR|ARRAY|HASH|REF)$/o) {
        # we could also check for CODE|GLOB|LVALUE, but we cannot serialize
        # them anyway, so they'll be cought by check below
        $class =~ s/::/__/g;

        $name = $class if !defined $name;
        $type = $class if !defined $type && $self->autotype;

        my $method = 'as_' . $class;
        if ($self->can($method)) {
            no strict qw(refs);
            my $encoded = $self->$method($object, $name, $type, $attr);
            return $encoded if ref $encoded;
            # return only if handled, otherwise handle with default handlers
        }
    }

    if (UNIVERSAL::isa($object => 'REF') || UNIVERSAL::isa($object => 'SCALAR')) {
        return $self->encode_scalar($object, $name, $type, $attr);
    }
    elsif (UNIVERSAL::isa($object => 'ARRAY')) {
        # Added in SOAP::Lite 0.65_6 to fix an XMLRPC bug
        return $self->encodingStyle eq ""
            || $self->isa('XMLRPC::Serializer')
                ? $self->encode_array($object, $name, $type, $attr)
                : $self->encode_literal_array($object, $name, $type, $attr);
    }
    elsif (UNIVERSAL::isa($object => 'HASH')) {
        return $self->encode_hash($object, $name, $type, $attr);
    }
    else {
        return $self->on_nonserialized->($object);
    }
}

sub encode_scalar {
    my($self, $value, $name, $type, $attr) = @_;
    $name ||= gen_name;

    my $schemaclass = $self->xmlschemaclass;

    # null reference
    return [$name, {%$attr, SOAP::Utils::qualify(xsi => $schemaclass->nilValue) => $schemaclass->as_undef(1)}] unless defined $value;

    # object reference
    return [$name, {'xsi:type' => $self->maptypetouri($type), %$attr}, [$self->encode_object($$value)], $self->gen_id($value)] if ref $value;

    # autodefined type
    if ($self->autotype) {
        my $lookup = $self->typelookup();
        no strict qw(refs);
        for (sort {$lookup->{$a}->[0] <=> $lookup->{$b}->[0]} keys %$lookup) {
            my $method = $lookup->{$_}->[2];
            return $self->can($method) && $self->$method($value, $name, $type, $attr)
                || $method->($value, $name, $type, $attr)
                    if $lookup->{$_}->[1]->($value);
        }
    }

    # invariant
    return [$name, $attr, $value];
}

sub encode_array {
    my($self, $array, $name, $type, $attr) = @_;
    my $items = 'item';

    # If typing is disabled, just serialize each of the array items
    # with no type information, each using the specified name,
    # and do not crete a wrapper array tag.
    if (!$self->autotype) {
        $name ||= gen_name;
        return map {$self->encode_object($_, $name)} @$array;
    }

    # TODO: add support for multidimensional, partially transmitted and sparse arrays
    my @items = map {$self->encode_object($_, $items)} @$array;
    my $num = @items;
    my($arraytype, %types) = '-';
    for (@items) { $arraytype = $_->[1]->{'xsi:type'} || '-'; $types{$arraytype}++ }
    $arraytype = sprintf "%s\[$num]", keys %types > 1 || $arraytype eq '-' ? SOAP::Utils::qualify(xsd => $self->xmlschemaclass->anyTypeValue) : $arraytype;

    # $type = SOAP::Utils::qualify($self->encprefix => 'Array') if $self->autotype && !defined $type;
    $type = qualify($self->encprefix => 'Array') if !defined $type;
    return [$name || SOAP::Utils::qualify($self->encprefix => 'Array'),
          {
              SOAP::Utils::qualify($self->encprefix => 'arrayType') => $arraytype,
              'xsi:type' => $self->maptypetouri($type), %$attr
          },
          [@items],
          $self->gen_id($array)
    ];
}

# Will encode arrays using doc-literal style
sub encode_literal_array {
    my($self, $array, $name, $type, $attr) = @_;

    if ($self->autotype) {
        my $items = 'item';
    
        # TODO: add support for multidimensional, partially transmitted and sparse arrays
        my @items = map {$self->encode_object($_, $items)} @$array;

    
        my $num = @items;
        my($arraytype, %types) = '-';
        for (@items) {
           $arraytype = $_->[1]->{'xsi:type'} || '-';
           $types{$arraytype}++
        }
        $arraytype = sprintf "%s\[$num]", keys %types > 1 || $arraytype eq '-'
            ? SOAP::Utils::qualify(xsd => $self->xmlschemaclass->anyTypeValue)
            : $arraytype;
    
        $type = SOAP::Utils::qualify($self->encprefix => 'Array')
            if !defined $type;
    
        return [$name || SOAP::Utils::qualify($self->encprefix => 'Array'),
            {
                SOAP::Utils::qualify($self->encprefix => 'arrayType') => $arraytype,
                'xsi:type' => $self->maptypetouri($type), %$attr
            },
            [ @items ],
            $self->gen_id($array)
        ];
    }
    else {
        #
        # literal arrays are different - { array => [ 5,6 ] }
        # results in <array>5</array><array>6</array>
        # This means that if there's a literal inside the array (not a 
        # reference), we have to encode it this way. If there's only 
        # nested tags, encode as 
        # <array><foo>1</foo><foo>2</foo></array>
        #
        
        my $literal = undef;
        my @items = map {
            ref $_ 
                ? $self->encode_object($_)
                : do {
                    $literal++;
                    $_
                }
            
        } @$array;

        if ($literal) {
            return map { [ $name , $attr , $_, $self->gen_id($array) ] } @items;
        }
        else {         
            return [$name || SOAP::Utils::qualify($self->encprefix => 'Array'),
                $attr,
                [ @items ],
                $self->gen_id($array)
            ];            
        }
    }
}

sub encode_hash {
    my($self, $hash, $name, $type, $attr) = @_;

    if ($self->autotype && grep {!/$SOAP::Constants::ELMASK/o} keys %$hash) {
        warn qq!Cannot encode @{[$name ? "'$name'" : 'unnamed']} element as 'hash'. Will be encoded as 'map' instead\n! if $^W;
        return $self->as_map($hash, $name || gen_name, $type, $attr);
    }

    $type = 'SOAPStruct'
        if $self->autotype && !defined($type) && exists $self->maptype->{SOAPStruct};
    return [$name || gen_name,
          $self->autotype ? {'xsi:type' => $self->maptypetouri($type), %$attr} : { %$attr },
          [map {$self->encode_object($hash->{$_}, $_)} keys %$hash],
          $self->gen_id($hash)
    ];
}

sub as_ordered_hash {
    my ($self, $value, $name, $type, $attr) = @_;
    die "Not an ARRAY reference for 'ordered_hash' type" unless UNIVERSAL::isa($value => 'ARRAY');
    return [ $name, $attr,
        [map{$self->encode_object(@{$value}[2*$_+1,2*$_])} 0..$#$value/2 ],
        $self->gen_id($value)
    ];
}

sub as_map {
    my ($self, $value, $name, $type, $attr) = @_;
    die "Not a HASH reference for 'map' type" unless UNIVERSAL::isa($value => 'HASH');
    my $prefix = ($self->namespaces->{$SOAP::Constants::NS_APS} ||= 'apachens');
    my @items = map {
        $self->encode_object(
            SOAP::Data->type(
                ordered_hash => [
                    key => $_,
                    value => $value->{$_}
                ]
            ),
            'item',
            ''
        )} keys %$value;
    return [
        $name,
        {'xsi:type' => "$prefix:Map", %$attr},
        [@items],
        $self->gen_id($value)
    ];
}

sub as_xml {
    my $self = shift;
    my($value, $name, $type, $attr) = @_;
    return [$name, {'_xml' => 1}, $value];
}

sub typecast {
    my $self = shift;
    my($value, $name, $type, $attr) = @_;
    return if ref $value; # skip complex object, caller knows how to deal with it
    return if $self->autotype && !defined $type; # we don't know, autotype knows
    return [$name,
          {(defined $type && $type gt '' ? ('xsi:type' => $self->maptypetouri($type, 'simple type')) : ()), %$attr},
          $value
    ];
}

sub register_ns {
    my $self = shift->new();
    my ($ns,$prefix) = @_;
    $prefix = gen_ns if !$prefix;
    $self->{'_namespaces'}->{$ns} = $prefix if $ns;
}

sub find_prefix {
    my ($self, $ns) = @_;
    return (exists $self->{'_namespaces'}->{$ns})
        ? $self->{'_namespaces'}->{$ns}
        : ();
}

sub fixattrs {
    my $self = shift;
    my $data = shift;
    my($name, $attr) = ($data->SOAP::Data::name, {%{$data->SOAP::Data::attr}});
    my($xmlns, $prefix) = ($data->uri, $data->prefix);
    unless (defined($xmlns) || defined($prefix)) {
        $self->register_ns($xmlns,$prefix) unless ($self->use_default_ns);
        return ($name, $attr);
    }
    $name ||= gen_name; # local name
    $prefix = gen_ns if !defined $prefix && $xmlns gt '';
    $prefix = ''
        if defined $xmlns && $xmlns eq ''
            || defined $prefix && $prefix eq '';

    $attr->{join ':', xmlns => $prefix || ()} = $xmlns if defined $xmlns;
    $name = join ':', $prefix, $name if $prefix;

    $self->register_ns($xmlns,$prefix) unless ($self->use_default_ns);

    return ($name, $attr);

}

sub toqname {
    my $self = shift;
    my $long = shift;

    return $long unless $long =~ /^\{(.*)\}(.+)$/;
    return SOAP::Utils::qualify $self->namespaces->{$1} ||= gen_ns, $2;
}

sub attrstoqname {
    my $self = shift;
    my $attrs = shift;

    return {
        map { /^\{(.*)\}(.+)$/
            ? ($self->toqname($_) => $2 eq 'type'
                || $2 eq 'arrayType'
                    ? $self->toqname($attrs->{$_})
                    : $attrs->{$_})
            : ($_ => $attrs->{$_})
        } keys %$attrs
    };
}

sub tag {
    my ($self, $tag, $attrs, @values) = @_;
    my $value = join '', @values;
    my $level = $self->level;
    my $indent = $self->readable ? ' ' x (($level-1)*2) : '';

    # check for special attribute
    return "$indent$value" if exists $attrs->{_xml} && delete $attrs->{_xml};

    die "Element '$tag' can't be allowed in valid XML message. Died."
        if $tag !~ /^(?![xX][mM][lL])$SOAP::Constants::NSMASK$/o;

    my $prolog = $self->readable ? "\n" : "";
    my $epilog = $self->readable ? "\n" : "";
    my $tagjoiner = " ";
    if ($level == 1) {
        my $namespaces = $self->namespaces;
        foreach (keys %$namespaces) {
            $attrs->{SOAP::Utils::qualify(xmlns => $namespaces->{$_})} = $_
        }
        $prolog = qq!<?xml version="1.0" encoding="@{[$self->encoding]}"?>!
            if defined $self->encoding;
        $prolog .= "\n" if $self->readable;
        $tagjoiner = " \n".(' ' x (($level+1) * 2)) if $self->readable;
    }
    my $tagattrs = join($tagjoiner, '',
        map { sprintf '%s="%s"', $_, SOAP::Utils::encode_attribute($attrs->{$_}) }
            grep { $_ && defined $attrs->{$_} && ($_ ne 'xsi:type' || $attrs->{$_} ne '') }
                keys %$attrs);

    if ($value gt '') {
        return sprintf("$prolog$indent<%s%s>%s%s</%s>$epilog",$tag,$tagattrs,$value,($value =~ /^\s*</ ? $indent : ""),$tag);
    }
    else {
        return sprintf("$prolog$indent<%s%s />$epilog$indent",$tag,$tagattrs);
    }
}

sub xmlize {
    my $self = shift;
    my($name, $attrs, $values, $id) = @{+shift};
    $attrs ||= {};

    local $self->{_level} = $self->{_level} + 1;
    return $self->tag($name, $attrs)
        unless defined $values;
    return $self->tag($name, $attrs, $values)
        unless UNIVERSAL::isa($values => 'ARRAY');
    return $self->tag($name, {%$attrs, href => '#'.$self->multiref_anchor($id)})
        if $self->is_href($id, delete($attrs->{_id}));
    return $self->tag($name,
        {
            %$attrs, id => $self->multiref_anchor($id)
        },
        map {$self->xmlize($_)} @$values
    );
}

sub uriformethod {
    my $self = shift;

    my $method_is_data = ref $_[0] && UNIVERSAL::isa($_[0] => 'SOAP::Data');

    # drop prefix from method that could be string or SOAP::Data object
    my($prefix, $method) = $method_is_data
        ? ($_[0]->prefix, $_[0]->name)
        : SOAP::Utils::splitqname($_[0]);

    my $attr = {reverse %{$self->namespaces}};
    # try to define namespace that could be stored as
    #   a) method is SOAP::Data
    #        ? attribute in method's element as xmlns= or xmlns:${prefix}=
    #        : uri
    #   b) attribute in Envelope element as xmlns= or xmlns:${prefix}=
    #   c) no prefix or prefix equal serializer->envprefix
    #        ? '', but see coment below
    #        : die with error message
    my $uri = $method_is_data
        ? ref $_[0]->attr && ($_[0]->attr->{$prefix ? "xmlns:$prefix" : 'xmlns'} || $_[0]->uri)
        : $self->uri;

    defined $uri or $uri = $attr->{$prefix || ''};

    defined $uri or $uri = !$prefix || $prefix eq $self->envprefix
    # still in doubts what should namespace be in this case
    # but will keep it like this for now and be compatible with our server
        ? ( $method_is_data
            && $^W
            && warn("URI is not provided as an attribute for method ($method)\n"),
            ''
            )
        : die "Can't find namespace for method ($prefix:$method)\n";

    return ($uri, $method);
}

sub serialize { SOAP::Trace::trace('()');
    my $self = shift->new;
    @_ == 1 or Carp::croak "serialize() method accepts one parameter";

    $self->seen({}); # reinitialize multiref table
    my($encoded) = $self->encode_object($_[0]);

    # now encode multirefs if any
    #                 v -------------- subelements of Envelope
    push(@{$encoded->[2]}, $self->encode_multirefs) if ref $encoded->[2];
    return $self->xmlize($encoded);
}

sub envelope {
    SOAP::Trace::trace('()');
    my $self = shift->new;
    my $type = shift;
    my(@parameters, @header);
    for (@_) {
        # Find all the SOAP Headers
        if (defined($_) && ref($_) && UNIVERSAL::isa($_ => 'SOAP::Header')) {
            push(@header, $_);
        }
        # Find all the SOAP Message Parts (attachments)
        elsif (defined($_) && ref($_) && $self->context
            && $self->context->packager->is_supported_part($_)
        ) {
            $self->context->packager->push_part($_);
        }
        # Find all the SOAP Body elements
        else {
            # proposed resolution for [ 1700326 ] encode_data called incorrectly in envelope
            push(@parameters, $_);
            # push (@parameters, SOAP::Utils::encode_data($_));
        }
    }
    my $header = @header ? SOAP::Data->set_value(@header) : undef;
    my($body,$parameters);
    if ($type eq 'method' || $type eq 'response') {
        SOAP::Trace::method(@parameters);

        my $method = shift(@parameters);
        #  or die "Unspecified method for SOAP call\n";

        $parameters = @parameters ? SOAP::Data->set_value(@parameters) : undef;
        if (!defined($method)) {}
        elsif (UNIVERSAL::isa($method => 'SOAP::Data')) {
            $body = $method;
        }
        elsif ($self->use_default_ns) {
            if ($self->{'_ns_uri'}) {
                $body = SOAP::Data->name($method)
                    ->attr({'xmlns' => $self->{'_ns_uri'} } );
            }
            else {
                $body = SOAP::Data->name($method);
            }
        }
        else {
            # Commented out by Byrne on 1/4/2006 - to address default namespace problems
            #      $body = SOAP::Data->name($method)->uri($self->{'_ns_uri'});
            #      $body = $body->prefix($self->{'_ns_prefix'}) if ($self->{'_ns_prefix'});

            # Added by Byrne on 1/4/2006 - to avoid the unnecessary creation of a new
            # namespace
            # Begin New Code (replaces code commented out above)
            $body = SOAP::Data->name($method);
            my $pre = $self->find_prefix($self->{'_ns_uri'});
            $body = $body->prefix($pre) if ($self->{'_ns_prefix'});
            # End new code
        }

        # This is breaking a unit test right now...
        # proposed resolution for [ 1700326 ] encode_data called incorrectly in envelope
        #    $body->set_value(SOAP::Utils::encode_data($parameters ? \$parameters : ()))
        #      if $body;
        # must call encode_data on nothing to enforce xsi:nil="true" to be set.
        $body->set_value($parameters ? \$parameters : SOAP::Utils::encode_data()) if $body;
    }
    elsif ($type eq 'fault') {
        SOAP::Trace::fault(@parameters);
        # -> attr({'xmlns' => ''})
        # Parameter order fixed thanks to Tom Fischer
        $body = SOAP::Data-> name(SOAP::Utils::qualify($self->envprefix => 'Fault'))
          -> value(\SOAP::Data->set_value(
                SOAP::Data->name(faultcode => SOAP::Utils::qualify($self->envprefix => $parameters[0]))->type(""),
                SOAP::Data->name(faultstring => SOAP::Utils::encode_data($parameters[1]))->type(""),
                defined($parameters[3])
                    ? SOAP::Data->name(faultactor => $parameters[3])->type("")
                    : (),
                defined($parameters[2])
                    ? SOAP::Data->name(detail => do{
                        my $detail = $parameters[2];
                        ref $detail
                            ? \$detail
                            : SOAP::Utils::encode_data($detail)
                    })
                    : (),
        ));
    }
    elsif ($type eq 'freeform') {
        SOAP::Trace::freeform(@parameters);
        $body = SOAP::Data->set_value(@parameters);
    }
    elsif (!defined($type)) {
        # This occurs when the Body is intended to be null. When no method has been
        # passed in of any kind.
    }
    else {
        die "Wrong type of envelope ($type) for SOAP call\n";
    }

    $self->seen({}); # reinitialize multiref table
    # Build the envelope
    # Right now it is possible for $body to be a SOAP::Data element that has not
    # XML escaped any values. How do you remedy this?
    my($encoded) = $self->encode_object(
        SOAP::Data->name(
            SOAP::Utils::qualify($self->envprefix => 'Envelope') => \SOAP::Data->value(
                ($header
                    ? SOAP::Data->name( SOAP::Utils::qualify($self->envprefix => 'Header') => \$header)
                    : ()
                ),
                ($body
                    ? SOAP::Data->name(SOAP::Utils::qualify($self->envprefix => 'Body') => \$body)
                    : SOAP::Data->name(SOAP::Utils::qualify($self->envprefix => 'Body')) ),
            )
        )->attr($self->attr)
    );

    $self->signature($parameters->signature) if ref $parameters;

    # IMHO multirefs should be encoded after Body, but only some
    # toolkits understand this encoding, so we'll keep them for now (04/15/2001)
    # as the last element inside the Body
    #                 v -------------- subelements of Envelope
    #                      vv -------- last of them (Body)
    #                            v --- subelements
    push(@{$encoded->[2]->[-1]->[2]}, $self->encode_multirefs) if ref $encoded->[2]->[-1]->[2];

    # Sometimes SOAP::Serializer is invoked statically when there is no context.
    # So first check to see if a context exists.
    # TODO - a context needs to be initialized by a constructor?
    if ($self->context && $self->context->packager->parts) {
        # TODO - this needs to be called! Calling it though wraps the payload twice!
        #  return $self->context->packager->package($self->xmlize($encoded));
    }

    return $self->xmlize($encoded);
}

# ======================================================================

package SOAP::Parser;

sub DESTROY { SOAP::Trace::objects('()') }

sub xmlparser {
    my $self = shift;
    return eval {
        $SOAP::Constants::DO_NOT_USE_XML_PARSER
            ? undef
            : do {
                require XML::Parser;
                XML::Parser->new() }
            }
            || eval { require XML::Parser::Lite; XML::Parser::Lite->new }
            || die "XML::Parser is not @{[$SOAP::Constants::DO_NOT_USE_XML_PARSER ? 'used' : 'available']} and ", $@;
}

sub parser {
    my $self = shift->new;
    @_
        ? do {
            $self->{'_parser'} = shift;
            return $self;
        }
        : return ($self->{'_parser'} ||= $self->xmlparser);
}

sub new {
    my $self = shift;
    return $self if ref $self;
    my $class = $self;
    SOAP::Trace::objects('()');
    return bless {_parser => shift}, $class;
}

sub decode { SOAP::Trace::trace('()');
    my $self = shift;

    $self->parser->setHandlers(
        Final => sub { shift; $self->final(@_) },
        Start => sub { shift; $self->start(@_) },
        End   => sub { shift; $self->end(@_)   },
        Char  => sub { shift; $self->char(@_)  },
        ExternEnt => sub { shift; die "External entity (pointing to '$_[1]') is not allowed" },
    );
    # my $parsed = $self->parser->parse($_[0]);
    # return $parsed;
    #
    my $ret = undef;
    eval {
        $ret = $self->parser->parse($_[0]);
    };
    if ($@) {
        $self->final; # Clean up in the event of an error
        die $@; # Pass back the error
    }
    return $ret;
}

sub final {
    my $self = shift;

    # clean handlers, otherwise SOAP::Parser won't be deleted:
    # it refers to XML::Parser which refers to subs from SOAP::Parser
    # Thanks to Ryan Adams <iceman@mit.edu>
    # and Craig Johnston <craig.johnston@pressplay.com>
    # checked by number of tests in t/02-payload.t

    undef $self->{_values};
    $self->parser->setHandlers(
        Final => undef,
        Start => undef,
        End => undef,
        Char => undef,
        ExternEnt => undef,
    );
    $self->{_done};
}

sub start { push @{shift->{_values}}, [shift, {@_}] }

# string concatenation changed to arrays which should improve performance
# for strings with many entity-encoded elements.
# Thanks to Mathieu Longtin <mrdamnfrenchy@yahoo.com>
sub char { push @{shift->{_values}->[-1]->[3]}, shift }

sub end {
    my $self = shift;
    my $done = pop @{$self->{_values}};
    $done->[2] = defined $done->[3]
        ? join('',@{$done->[3]})
        : '' unless ref $done->[2];
    undef $done->[3];
    @{$self->{_values}}
        ? (push @{$self->{_values}->[-1]->[2]}, $done)
        : ($self->{_done} = $done);
}

# ======================================================================

package SOAP::SOM;

use Carp ();
use SOAP::Lite::Utils;

sub BEGIN {
    no strict 'refs';
    my %path = (
        root        => '/',
        envelope    => '/Envelope',
        body        => '/Envelope/Body',
        header      => '/Envelope/Header',
        headers     => '/Envelope/Header/[>0]',
        fault       => '/Envelope/Body/Fault',
        faultcode   => '/Envelope/Body/Fault/faultcode',
        faultstring => '/Envelope/Body/Fault/faultstring',
        faultactor  => '/Envelope/Body/Fault/faultactor',
        faultdetail => '/Envelope/Body/Fault/detail',
    );
    for my $method (keys %path) {
        *$method = sub {
            my $self = shift;
            ref $self or return $path{$method};
            Carp::croak "Method '$method' is readonly and doesn't accept any parameters" if @_;
            return $self->valueof($path{$method});
        };
    }
    my %results = (
        method    => '/Envelope/Body/[1]',
        result    => '/Envelope/Body/[1]/[1]',
        freeform  => '/Envelope/Body/[>0]',
        paramsin  => '/Envelope/Body/[1]/[>0]',
        paramsall => '/Envelope/Body/[1]/[>0]',
        paramsout => '/Envelope/Body/[1]/[>1]'
    );
    for my $method (keys %results) {
        *$method = sub {
            my $self = shift;
            ref $self or return $results{$method};
            Carp::croak "Method '$method' is readonly and doesn't accept any parameters" if @_;
            defined $self->fault ? return : return $self->valueof($results{$method});
        };
    }

    for my $method (qw(o_child o_value o_lname o_lattr o_qname)) { # import from SOAP::Utils
        *$method = \&{'SOAP::Utils::'.$method};
    }

    __PACKAGE__->__mk_accessors('context');

}

# use object in boolean context return true/false on last match
# Ex.: $som->match('//Fault') ? 'SOAP call failed' : 'success';
use overload fallback => 1, 'bool'  => sub { @{shift->{_current}} > 0 };

sub DESTROY { SOAP::Trace::objects('()') }

sub new {
    my $self = shift;
    my $class = ref($self) || $self;
    my $content = shift;
    SOAP::Trace::objects('()');
    return bless { _content => $content, _current => [$content] } => $class;
}

sub parts {
    my $self = shift;
    if (@_) {
        $self->context->packager->parts(@_);
        return $self;
    }
    else {
        return $self->context->packager->parts;
    }
}

sub is_multipart {
    my $self = shift;
    return defined($self->parts);
}

sub current {
    my $self = shift;
    $self->{_current} = [@_], return $self if @_;
    return wantarray ? @{$self->{_current}} : $self->{_current}->[0];
}

sub valueof {
    my $self = shift;
    local $self->{_current} = $self->{_current};
    $self->match(shift) if @_;
    return wantarray
        ? map {o_value($_)} @{$self->{_current}}
        : @{$self->{_current}} ? o_value($self->{_current}->[0]) : undef;
}

sub headerof { # SOAP::Header is the same as SOAP::Data, so just rebless it
    wantarray
        ? map { bless $_ => 'SOAP::Header' } shift->dataof(@_)
        : do { # header returned by ->dataof can be undef in scalar context
            my $header = shift->dataof(@_);
            ref $header ? bless($header => 'SOAP::Header') : undef;
        };
}

sub dataof {
    my $self = shift;
    local $self->{_current} = $self->{_current};
    $self->match(shift) if @_;
    return wantarray
        ? map {$self->_as_data($_)} @{$self->{_current}}
        : @{$self->{_current}}
            ? $self->_as_data($self->{_current}->[0])
            : undef;
}

sub namespaceuriof {
    my $self = shift;
    local $self->{_current} = $self->{_current};
    $self->match(shift) if @_;
    return wantarray
        ? map {(SOAP::Utils::splitlongname(o_lname($_)))[0]} @{$self->{_current}}
        : @{$self->{_current}} ? (SOAP::Utils::splitlongname(o_lname($self->{_current}->[0])))[0] : undef;
}

#sub _as_data {
#    my $self = shift;
#    my $pointer = shift;
#
#    SOAP::Data
#        -> new(prefix => '', name => o_qname($pointer), name => o_lname($pointer), attr => o_lattr($pointer))
#        -> set_value(o_value($pointer));
#}

sub _as_data {
    my $self = shift;
    my $node = shift;

    my $data = SOAP::Data->new( prefix => '',
        # name => o_qname has side effect: sets namespace !
        name => o_qname($node),
        name => o_lname($node),
        attr => o_lattr($node) );

    if ( defined o_child($node) ) {
        my @children;
        foreach my $child ( @{ o_child($node) } ) {
            push( @children, $self->_as_data($child) );
        }
        $data->set_value( \SOAP::Data->value(@children) );
    }
    else {
        $data->set_value( o_value($node) );
    }

    return $data;
}


sub match {
    my $self = shift;
    my $path = shift;
    $self->{_current} = [
        $path =~ s!^/!! || !@{$self->{_current}}
        ? $self->_traverse($self->{_content}, 1 => split '/' => $path)
        : map {$self->_traverse_tree(o_child($_), split '/' => $path)} @{$self->{_current}}
    ];
    return $self;
}

sub _traverse {
    my $self = shift;
    my ($pointer, $itself, $path, @path) = @_;

    die "Incorrect parameter" unless $itself =~ /^\d*$/;

    if ($path && substr($path, 0, 1) eq '{') {
        $path = join '/', $path, shift @path while @path && $path !~ /}/;
    }

    my($op, $num) = $path =~ /^\[(<=|<|>=|>|=|!=?)?(\d+)\]$/ if defined $path;

    return $pointer unless defined $path;

    $op = '==' unless $op; $op .= '=' if $op eq '=' || $op eq '!';
    my $numok = defined $num && eval "$itself $op $num";
    my $nameok = (o_lname($pointer) || '') =~ /(?:^|\})$path$/ if defined $path; # name can be with namespace

    my $anynode = $path eq '';
    unless ($anynode) {
        if (@path) {
            return if defined $num && !$numok || !defined $num && !$nameok;
        }
        else {
            return $pointer if defined $num && $numok || !defined $num && $nameok;
            return;
        }
    }

    my @walk;
    push @walk, $self->_traverse_tree([$pointer], @path) if $anynode;
    push @walk, $self->_traverse_tree(o_child($pointer), $anynode ? ($path, @path) : @path);
    return @walk;
}

sub _traverse_tree {
    my $self = shift;
    my($pointer, @path) = @_;

    # can be list of children or value itself. Traverse only children
    return unless ref $pointer eq 'ARRAY';

    my $itself = 1;

    grep {defined}
        map {$self->_traverse($_, $itself++, @path)}
        grep {!ref o_lattr($_) ||
            !exists o_lattr($_)->{"{$SOAP::Constants::NS_ENC}root"} ||
            o_lattr($_)->{"{$SOAP::Constants::NS_ENC}root"} ne '0'}
        @$pointer;
}

# ======================================================================

package SOAP::Deserializer;

use vars qw(@ISA);
use SOAP::Lite::Utils;
use Class::Inspector;

@ISA = qw(SOAP::Cloneable);

sub DESTROY { SOAP::Trace::objects('()') }

sub BEGIN {
    __PACKAGE__->__mk_accessors( qw(ids hrefs parts parser
        base xmlschemas xmlschema context) );
}

sub new {
    my $self = shift;
    return $self if ref $self;
    my $class = $self;
    SOAP::Trace::objects('()');
    return bless {
        '_ids'        => {},
        '_hrefs'      => {},
        '_parser'     => SOAP::Parser->new,
        '_xmlschemas' => {
            $SOAP::Constants::NS_APS => 'SOAP::XMLSchemaApacheSOAP::Deserializer',
#            map {
#                $_ => $SOAP::Constants::XML_SCHEMAS{$_} . '::Deserializer'
#              } keys %SOAP::Constants::XML_SCHEMAS
            map {
                $_ => 'SOAP::Lite::Deserializer::' . $SOAP::Constants::XML_SCHEMA_OF{$_}
              } keys %SOAP::Constants::XML_SCHEMA_OF

        },
    }, $class;
}

sub is_xml {
    # Added check for envelope delivery. Fairly standard with MMDF and sendmail
    # Thanks to Chris Davies <Chris.Davies@ManheimEurope.com>
    $_[1] =~ /^\s*</ || $_[1] !~ /^(?:[\w-]+:|From )/;
}

sub baselocation {
    my $self = shift;
    my $location = shift;
    if ($location) {
        my $uri = URI->new($location);
        # make absolute location if relative
        $location = $uri->abs($self->base || 'thismessage:/')->as_string unless $uri->scheme;
    }
    return $location;
}

# Returns the envelope and populates SOAP::Packager with parts
sub decode_parts {
    my $self = shift;
    my $env = $self->context->packager->unpackage($_[0],$self->context);
    my $body = $self->parser->decode($env);
    # TODO - This shouldn't be here! This is packager specific!
    #        However this does need to pull out all the cid's
    #        to populate ids hash with.
    foreach (@{$self->context->packager->parts}) {
        my $data     = $_->bodyhandle->as_string;
        my $type     = $_->head->mime_attr('Content-Type');
        my $location = $_->head->mime_attr('Content-Location');
        my $id       = $_->head->mime_attr('Content-Id');
        $location = $self->baselocation($location);
        my $part = lc($type) eq 'text/xml' && !$SOAP::Constants::DO_NOT_PROCESS_XML_IN_MIME
            ? $self->parser->decode($data)
            : ['mimepart', {}, $data];
        # This below looks like unnecessary bloat!!!
        # I should probably dereference the mimepart, provide a callback to get the string data
        $id =~ s/^<([^>]*)>$/$1/; # string any leading and trailing brackets
        $self->ids->{$id} = $part if $id;
        $self->ids->{$location} = $part if $location;
    }
    return $body;
}

# decode returns a parsed body in the form of an ARRAY
# each element of the ARRAY is a HASH, ARRAY or SCALAR
sub decode {
    my $self = shift->new; # this actually is important
    return $self->is_xml($_[0])
        ? $self->parser->decode($_[0])
        : $self->decode_parts($_[0]);
}

# deserialize returns a SOAP::SOM object and parses straight
# text as input
sub deserialize {
    SOAP::Trace::trace('()');
    my $self = shift->new;

    # initialize
    $self->hrefs({});
    $self->ids({});

    # If the document is XML, then ids will be empty
    # If the document is MIME, then ids will hold a list of cids
    my $parsed = $self->decode($_[0]);

    # Having this code here makes multirefs in the Body work, but multirefs
    # that reference XML fragments in a MIME part do not work.
    if (keys %{$self->ids()}) {
        $self->traverse_ids($parsed);
    }
    else {
        # delay - set ids to be traversed later in decode_object, they only get
        # traversed if an href is found that is referencing an id.
        $self->ids($parsed);
    }
    $self->decode_object($parsed);
    my $som = SOAP::SOM->new($parsed);
    $som->context($self->context); # TODO - try removing this and see if it works!
    return $som;
}

sub traverse_ids {
    my $self = shift;
    my $ref = shift;
    my($undef, $attrs, $children) = @$ref;
    #  ^^^^^^ to fix nasty error on Mac platform (Carl K. Cunningham)
    $self->ids->{$attrs->{'id'}} = $ref if exists $attrs->{'id'};
    return unless ref $children;
    for (@$children) {
        $self->traverse_ids($_)
    };
}

use constant _ATTRS => 6;
use constant _NAME => 5;

sub decode_object {
    my $self = shift;
    my $ref = shift;
    my($name, $attrs, $children, $value) = @$ref;

    $ref->[ _ATTRS ] = $attrs = {%$attrs}; # make a copy for long attributes

    use vars qw(%uris);
    local %uris = (%uris, map {
        do { (my $ns = $_) =~ s/^xmlns:?//; $ns } => delete $attrs->{$_}
    } grep {/^xmlns(:|$)/} keys %$attrs);

    foreach (keys %$attrs) {
        next unless m/^($SOAP::Constants::NSMASK?):($SOAP::Constants::NSMASK)$/;

    $1 =~ /^[xX][mM][lL]/ ||
        $uris{$1} &&
            do {
                $attrs->{SOAP::Utils::longname($uris{$1}, $2)} = do {
                    my $value = $attrs->{$_};
                    $2 ne 'type' && $2 ne 'arrayType'
                        ? $value
                        : SOAP::Utils::longname($value =~ m/^($SOAP::Constants::NSMASK?):(${SOAP::Constants::NSMASK}(?:\[[\d,]*\])*)/
                            ? ($uris{$1} || die("Unresolved prefix '$1' for attribute value '$value'\n"), $2)
                            : ($uris{''} || die("Unspecified namespace for type '$value'\n"), $value)
                    );
                };
                1;
            }
            || die "Unresolved prefix '$1' for attribute '$_'\n";
  }

    # and now check the element
    my $ns = ($name =~ s/^($SOAP::Constants::NSMASK?):// ? $1 : '');
    $ref->[ _NAME ] = SOAP::Utils::longname(
        $ns
            ? ($uris{$ns} || die "Unresolved prefix '$ns' for element '$name'\n")
            : (defined $uris{''} ? $uris{''} : undef),
        $name
    );

    ($children, $value) = (undef, $children) unless ref $children;

    return $name => ($ref->[4] = $self->decode_value(
        [$ref->[ _NAME ], $attrs, $children, $value]
    ));
}

sub decode_value {
    my $self = shift;
    my $ref = shift;
    my($name, $attrs, $children, $value) = @$ref;

    # check SOAP version if applicable
    use vars '$level'; local $level = $level || 0;
    if (++$level == 1) {
        my($namespace, $envelope) = SOAP::Utils::splitlongname($name);
        SOAP::Lite->soapversion($namespace) if $envelope eq 'Envelope' && $namespace;
    }

    # check encodingStyle
    # future versions may bind deserializer to encodingStyle
    my $encodingStyle = $attrs->{"{$SOAP::Constants::NS_ENV}encodingStyle"} || "";
    my (%union,%isect);
    # TODO - SOAP 1.2 and 1.1 have different rules about valid encodingStyle values
    #        For example, in 1.1 - any http://schemas.xmlsoap.org/soap/encoding/*
    #        value is valid
    # Find intersection of declared and supported encoding styles
    foreach my $e (@SOAP::Constants::SUPPORTED_ENCODING_STYLES, split(/ +/,$encodingStyle)) {
        $union{$e}++ && $isect{$e}++;
    }
    die "Unrecognized/unsupported value of encodingStyle attribute '$encodingStyle'"
        if defined($encodingStyle) && length($encodingStyle) > 0 && !%isect &&
            !(SOAP::Lite->soapversion == 1.1 && $encodingStyle =~ /(?:^|\b)$SOAP::Constants::NS_ENC/);

    # removed to provide literal support in 0.65
    #$encodingStyle !~ /(?:^|\b)$SOAP::Constants::NS_ENC/;
    #                 # ^^^^^^^^ \b causing problems (!?) on some systems
    #                 # as reported by David Dyck <dcd@tc.fluke.com>
    #                 # so use (?:^|\b) instead

    use vars '$arraytype'; # type of Array element specified on Array itself
    # either specified with xsi:type, or <enc:name/> or array element
    my ($type) = grep { defined }
        map($attrs->{$_}, sort grep {/^\{$SOAP::Constants::NS_XSI_ALL\}type$/o} keys %$attrs),
           $name =~ /^\{$SOAP::Constants::NS_ENC\}/ ? $name : $arraytype;
    local $arraytype; # it's used only for one level, we don't need it anymore

    # $name is not used here since type should be encoded as type, not as name
    my ($schema, $class) = SOAP::Utils::splitlongname($type) if $type;
    my $schemaclass = defined($schema) && $self->xmlschemas->{$schema}
        || $self;

    {
        no strict qw(refs);
        if (! Class::Inspector->loaded($schemaclass) ) {
            eval "require $schemaclass" or die $@ if not ref $schemaclass;
        }
    }

    # store schema that is used in parsed message
    $self->xmlschema($schema) if $schema && $schema =~ /XMLSchema/;

    # don't use class/type if anyType/ur-type is specified on wire
    undef $class
        if $schemaclass->can('anyTypeValue')
            && $schemaclass->anyTypeValue eq $class;

    my $method = 'as_' . ($class || '-'); # dummy type if not defined
    $class =~ s/__|\./::/g if $class;

    my $id = $attrs->{id};
    if (defined $id && exists $self->hrefs->{$id}) {
        return $self->hrefs->{$id};
    }
    elsif (exists $attrs->{href}) {
        (my $id = delete $attrs->{href}) =~ s/^(#|cid:|uuid:)?//;
        # convert to absolute if not internal '#' or 'cid:'
        $id = $self->baselocation($id) unless $1;
        return $self->hrefs->{$id} if exists $self->hrefs->{$id};
        # First time optimization. we don't traverse IDs unless asked for it.
        # This is where traversing id's is delayed from before
        #   - the first time through - ids should contain a copy of the parsed XML
        #     structure! seems silly to make so many copies
        my $ids = $self->ids;
        if (ref($ids) ne 'HASH') {
            $self->ids({});            # reset list of ids first time through
            $self->traverse_ids($ids);
        }
        if (exists($self->ids->{$id})) {
            my $obj = ($self->decode_object(delete($self->ids->{$id})))[1];
            return $self->hrefs->{$id} = $obj;
        }
        else {
            die "Unresolved (wrong?) href ($id) in element '$name'\n";
        }
    }

    return undef if grep {
        /^$SOAP::Constants::NS_XSI_NILS$/ && do {
            my $class = $self->xmlschemas->{ $1 || $2 };
            eval "require $class" or die @$;;
            $class->as_undef($attrs->{$_})
        }
    } keys %$attrs;

    # try to handle with typecasting
    my $res = $self->typecast($value, $name, $attrs, $children, $type);
    return $res if defined $res;

    # ok, continue with others
    if (exists $attrs->{"{$SOAP::Constants::NS_ENC}arrayType"}) {
        my $res = [];
        $self->hrefs->{$id} = $res if defined $id;

        # check for arrayType which could be [1], [,2][5] or []
        # [,][1] will NOT be allowed right now (multidimensional sparse array)
        my($type, $multisize) = $attrs->{"{$SOAP::Constants::NS_ENC}arrayType"}
            =~ /^(.+)\[(\d*(?:,\d+)*)\](?:\[(?:\d+(?:,\d+)*)\])*$/
                or die qq!Unrecognized/unsupported format of arrayType attribute '@{[$attrs->{"{$SOAP::Constants::NS_ENC}arrayType"}]}'\n!;

        my @dimensions = map { $_ || undef } split /,/, $multisize;
        my $size = 1;
        foreach (@dimensions) { $size *= $_ || 0 }

        # TODO ähm, shouldn't this local be my?
        local $arraytype = $type;

        # multidimensional
        if ($multisize =~ /,/) {
            @$res = splitarray(
                [@dimensions],
                [map { scalar(($self->decode_object($_))[1]) } @{$children || []}]
            );
        }
        # normal
        else {
            @$res = map { scalar(($self->decode_object($_))[1]) } @{$children || []};
        }

        # sparse (position)
        if (ref $children && exists SOAP::Utils::o_lattr($children->[0])->{"{$SOAP::Constants::NS_ENC}position"}) {
            my @new;
            for (my $pos = 0; $pos < @$children; $pos++) {
                # TBD implement position in multidimensional array
                my($position) = SOAP::Utils::o_lattr($children->[$pos])->{"{$SOAP::Constants::NS_ENC}position"} =~ /^\[(\d+)\]$/
                    or die "Position must be specified for all elements of sparse array\n";
                $new[$position] = $res->[$pos];
            }
            @$res = @new;
        }

        # partially transmitted (offset)
        # TBD implement offset in multidimensional array
        my($offset) = $attrs->{"{$SOAP::Constants::NS_ENC}offset"} =~ /^\[(\d+)\]$/
            if exists $attrs->{"{$SOAP::Constants::NS_ENC}offset"};
        unshift(@$res, (undef) x $offset) if $offset;

        die "Too many elements in array. @{[scalar@$res]} instead of claimed $multisize ($size)\n"
            if $multisize && $size < @$res;

        # extend the array if number of elements is specified
        $#$res = $dimensions[0]-1 if defined $dimensions[0] && @$res < $dimensions[0];

        return defined $class && $class ne 'Array' ? bless($res => $class) : $res;

    }
    elsif ($name =~ /^\{$SOAP::Constants::NS_ENC\}Struct$/
        || !$schemaclass->can($method)
           && (ref $children || defined $class && $value =~ /^\s*$/)) {
        my $res = {};
        $self->hrefs->{$id} = $res if defined $id;

        # Patch code introduced in 0.65 - deserializes array properly
        # Decode each element of the struct.
        my %child_count_of = ();
        foreach my $child (@{$children || []}) {
            my ($child_name, $child_value) = $self->decode_object($child);
            # Store the decoded element in the struct.  If the element name is
            # repeated, replace the previous scalar value with a new array
            # containing both values.
            if (not $child_count_of{$child_name}) {
                # first time to see this value: use scalar
                $res->{$child_name} = $child_value;
            }
            elsif ($child_count_of{$child_name} == 1) {
                # second time to see this value: convert scalar to array
                $res->{$child_name} = [ $res->{$child_name}, $child_value ];
            }
            else {
                # already have an array: append to it
                push @{$res->{$child_name}}, $child_value;
            }
            $child_count_of{$child_name}++;
        }
        # End patch code

        return defined $class && $class ne 'SOAPStruct' ? bless($res => $class) : $res;
    }
    else {
        my $res;
        if (my $method_ref = $schemaclass->can($method)) {
            $res = $method_ref->($self, $value, $name, $attrs, $children, $type);
        }
        else {
            $res = $self->typecast($value, $name, $attrs, $children, $type);
            $res = $class ? die "Unrecognized type '$type'\n" : $value
                unless defined $res;
        }
        $self->hrefs->{$id} = $res if defined $id;
        return $res;
    }
}

sub splitarray {
    my @sizes = @{+shift};
    my $size = shift @sizes;
    my $array = shift;

    return splice(@$array, 0, $size) unless @sizes;
    my @array = ();
    push @array, [
        splitarray([@sizes], $array)
    ] while @$array && (!defined $size || $size--);
    return @array;
}

sub typecast { } # typecast is called for both objects AND scalar types
                 # check ref of the second parameter (first is the object)
                 # return undef if you don't want to handle it

# ======================================================================

package SOAP::Client;


use SOAP::Lite::Utils;

$VERSION = $SOAP::Lite::VERSION;
sub BEGIN {
    __PACKAGE__->__mk_accessors(qw(endpoint code message
        is_success status options));
}

# ======================================================================

package SOAP::Server::Object;

sub gen_id; *gen_id = \&SOAP::Serializer::gen_id;

my %alive;
my %objects;

sub objects_by_reference {
    shift;
    while (@_) {
        @alive{shift()} = ref $_[0]
            ? shift
            : sub {
                $_[1]-$_[$_[5] ? 5 : 4] > $SOAP::Constants::OBJS_BY_REF_KEEPALIVE
            }
    }
    keys %alive;
}

sub reference {
    my $self = shift;
    my $stamp = time;
    my $object = shift;
    my $id = $stamp . $self->gen_id($object);

    # this is code for garbage collection
    my $time = time;
    my $type = ref $object;
    my @objects = grep { $objects{$_}->[1] eq $type } keys %objects;
    for (grep { $alive{$type}->(scalar @objects, $time, @{$objects{$_}}) } @objects) {
        delete $objects{$_};
    }

    $objects{$id} = [$object, $type, $stamp];
    bless { id => $id } => ref $object;
}

sub references {
    my $self = shift;
    return @_ unless %alive; # small optimization
    return map {
        ref($_) && exists $alive{ref $_}
            ? $self->reference($_)
            : $_
    } @_;
}

sub object {
    my $self = shift;
    my $class = ref($self) || $self;
    my $object = shift;
    return $object unless ref($object) && $alive{ref $object} && exists $object->{id};

    my $reference = $objects{$object->{id}};
    die "Object with specified id couldn't be found\n" unless ref $reference->[0];

    $reference->[3] = time; # last access time
    return $reference->[0]; # reference to actual object
}

sub objects {
    my $self = shift;
    return @_ unless %alive; # small optimization
    return map {
        ref($_) && exists $alive{ref $_} && exists $_->{id}
            ? $self->object($_)
            : $_
    } @_;
}

# ======================================================================

package SOAP::Server::Parameters;

sub byNameOrOrder {
    unless (UNIVERSAL::isa($_[-1] => 'SOAP::SOM')) {
        warn "Last parameter is expected to be envelope\n" if $^W;
        pop;
        return @_;
    }
    my $params = pop->method;
    my @mandatory = ref $_[0] eq 'ARRAY'
        ? @{shift()}
        : die "list of parameters expected as the first parameter for byName";
    my $byname = 0;
    my @res = map { $byname += exists $params->{$_}; $params->{$_} } @mandatory;
    return $byname
        ? @res
        : @_;
}

sub byName {
  unless (UNIVERSAL::isa($_[-1] => 'SOAP::SOM')) {
    warn "Last parameter is expected to be envelope\n" if $^W;
    pop;
    return @_;
  }
  return @{pop->method}{ref $_[0] eq 'ARRAY' ? @{shift()} : die "list of parameters expected as the first parameter for byName"};
}

# ======================================================================

package SOAP::Server;

use Carp ();
use Scalar::Util qw(weaken);
sub DESTROY { SOAP::Trace::objects('()') }

sub initialize {
    return (
        packager => SOAP::Packager::MIME->new,
        transport => SOAP::Transport->new,
        serializer => SOAP::Serializer->new,
        deserializer => SOAP::Deserializer->new,
        on_action => sub { ; },
        on_dispatch => sub {
            return;
        },
    );
}

sub new {
    my $self = shift;
    return $self if ref $self;

    unless (ref $self) {
        my $class = $self;
        my(@params, @methods);

        while (@_) {
            my($method, $params) = splice(@_,0,2);
            $class->can($method)
                ? push(@methods, $method, $params)
                : $^W && Carp::carp "Unrecognized parameter '$method' in new()";
        }

        $self = bless {
            _dispatch_to   => [],
            _dispatch_with => {},
            _dispatched    => [],
            _action        => '',
            _options       => {},
        } => $class;
        unshift(@methods, $self->initialize);
        no strict qw(refs);
        while (@methods) {
            my($method, $params) = splice(@methods,0,2);
            $self->$method(ref $params eq 'ARRAY' ? @$params : $params)
        }
        SOAP::Trace::objects('()');
    }

    Carp::carp "Odd (wrong?) number of parameters in new()"
        if $^W && (@_ & 1);

    no strict qw(refs);
    while (@_) {
        my($method, $params) = splice(@_,0,2);
        $self->can($method)
            ? $self->$method(ref $params eq 'ARRAY' ? @$params : $params)
            : $^W && Carp::carp "Unrecognized parameter '$method' in new()"
    }

    return $self;
}

sub init_context {
    my $self = shift;
    $self->{'_deserializer'}->{'_context'} = $self;
    # weaken circular reference to avoid a memory hole
    weaken($self->{'_deserializer'}->{'_context'});

    $self->{'_serializer'}->{'_context'} = $self;
    # weaken circular reference to avoid a memory hole
    weaken($self->{'_serializer'}->{'_context'});
}

sub BEGIN {
    no strict 'refs';
    for my $method (qw(serializer deserializer transport)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new();
            if (@_) {
                my $context = $self->{$field}->{'_context'}; # save the old context
                $self->{$field} = shift;
                $self->{$field}->{'_context'} = $context;    # restore the old context
                return $self;
            }
            else {
                return $self->{$field};
            }
        }
    }

    for my $method (qw(action myuri options dispatch_with packager)) {
    my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new();
            (@_)
                ? do {
                    $self->{$field} = shift;
                    return $self;
                }
                : return $self->{$field};
        }
    }
    for my $method (qw(on_action on_dispatch)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new;
            # my $self = shift;
            return $self->{$field} unless @_;
            local $@;
            # commented out because that 'eval' was unsecure
            # > ref $_[0] eq 'CODE' ? shift : eval shift;
            # Am I paranoid enough?
            $self->{$field} = shift;
            Carp::croak $@ if $@;
            Carp::croak "$method() expects subroutine (CODE) or string that evaluates into subroutine (CODE)"
                unless ref $self->{$field} eq 'CODE';
            return $self;
        }
    }

    #    __PACKAGE__->__mk_accessors( qw(dispatch_to) );
    for my $method (qw(dispatch_to)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new;
            # my $self = shift;
            (@_)
                ? do {
                    $self->{$field} = [@_];
                    return $self;
                }
                : return @{ $self->{$field} };
        }
    }
}

sub objects_by_reference {
    my $self = shift;
    $self = $self->new() if not ref $self;
    @_
        ? (SOAP::Server::Object->objects_by_reference(@_), return $self)
        : SOAP::Server::Object->objects_by_reference;
}

sub dispatched {
    my $self = shift;
    $self = $self->new() if not ref $self;
    @_
        ? (push(@{$self->{_dispatched}}, @_), return $self)
        : return @{$self->{_dispatched}};
}

sub find_target {
    my $self = shift;
    my $request = shift;

    # try to find URI/method from on_dispatch call first
    my($method_uri, $method_name) = $self->on_dispatch->($request);

    # if nothing there, then get it from envelope itself
    $request->match((ref $request)->method);
    ($method_uri, $method_name) = ($request->namespaceuriof || '', $request->dataof->name)
        unless $method_name;

    $self->on_action->(my $action = $self->action, $method_uri, $method_name);

    # check to avoid security vulnerability: Protected->Unprotected::method(@parameters)
    # see for more details: http://www.phrack.org/phrack/58/p58-0x09
    die "Denied access to method ($method_name)\n" unless $method_name =~ /^\w+$/;

    my ($class, $static);
    # try to bind directly
    if (defined($class = $self->dispatch_with->{$method_uri}
            || $self->dispatch_with->{$action || ''}
            || ($action =~ /^"(.+)"$/
                ? $self->dispatch_with->{$1}
                : undef))) {
        # return object, nothing else to do here
        return ($class, $method_uri, $method_name) if ref $class;
        $static = 1;
    }
    else {
        die "URI path shall map to class" unless defined ($class = URI->new($method_uri)->path);

        for ($class) { s!^/|/$!!g; s!/!::!g; s/^$/main/; }
        die "Failed to access class ($class)" unless $class =~ /^(\w[\w:]*)$/;

        my $fullname = "$class\::$method_name";
        foreach ($self->dispatch_to) {
            return ($_, $method_uri, $method_name) if ref eq $class; # $OBJECT
            next if ref;                                   # skip other objects
            # will ignore errors, because it may complain on
            # d:\foo\bar, which is PATH and not regexp
            eval {
                $static ||= $class =~ /^$_$/           # MODULE
                    || $fullname =~ /^$_$/             # MODULE::method
                    || $method_name =~ /^$_$/ && ($class eq 'main'); # method ('main' assumed)
            };
        }
    }

    no strict 'refs';

# TODO - sort this mess out:
# The task is to test whether the class in question has already been loaded.
#
# SOAP::Lite 0.60:
#  unless (defined %{"${class}::"}) {
# Patch to SOAP::Lite 0.60:
# The following patch does not work for packages defined within a BEGIN block
#  unless (exists($INC{join '/', split /::/, $class.'.pm'})) {
# Combination of 0.60 and patch did not work reliably, either.
#
# Now we do the following: Check whether the class is main (always loaded)
# or the class implements the method in question
# or the package exists as file in %INC.
#
# This is still sort of a hack - but I don't know anything better
# If you have some idea, please help me out...
#
    unless (($class eq 'main') || $class->can($method_name)
        || exists($INC{join '/', split /::/, $class . '.pm'})) {

        # allow all for static and only specified path for dynamic bindings
        local @INC = (($static ? @INC : ()), grep {!ref && m![/\\.]!} $self->dispatch_to());
        eval 'local $^W; ' . "require $class";
        die "Failed to access class ($class): $@" if $@;
        $self->dispatched($class) unless $static;
    }

    die "Denied access to method ($method_name) in class ($class)"
        unless $static || grep {/^$class$/} $self->dispatched;

    return ($class, $method_uri, $method_name);
}

sub handle {
    SOAP::Trace::trace('()');
    my $self = shift;
    $self = $self->new if !ref $self; # inits the server when called in a static context
    $self->init_context();
    # we want to restore it when we are done
    local $SOAP::Constants::DEFAULT_XML_SCHEMA
        = $SOAP::Constants::DEFAULT_XML_SCHEMA;

    # SOAP version WILL NOT be restored when we are done.
    # is it problem?

    my $result = eval {
        local $SIG{__DIE__};
        # why is this here:
        $self->serializer->soapversion(1.1);
        my $request = eval { $self->deserializer->deserialize($_[0]) };

        die SOAP::Fault
            ->faultcode($SOAP::Constants::FAULT_VERSION_MISMATCH)
            ->faultstring($@)
                if $@ && $@ =~ /^$SOAP::Constants::WRONG_VERSION/;

        die "Application failed during request deserialization: $@" if $@;
        my $som = ref $request;
        die "Can't find root element in the message"
            unless $request->match($som->envelope);
        $self->serializer->soapversion(SOAP::Lite->soapversion);
        $self->serializer->xmlschema($SOAP::Constants::DEFAULT_XML_SCHEMA
            = $self->deserializer->xmlschema)
                if $self->deserializer->xmlschema;

        die SOAP::Fault
            ->faultcode($SOAP::Constants::FAULT_MUST_UNDERSTAND)
            ->faultstring("Unrecognized header has mustUnderstand attribute set to 'true'")
            if !$SOAP::Constants::DO_NOT_CHECK_MUSTUNDERSTAND &&
                grep {
                    $_->mustUnderstand
                    && (!$_->actor || $_->actor eq $SOAP::Constants::NEXT_ACTOR)
                } $request->dataof($som->headers);

        die "Can't find method element in the message"
            unless $request->match($som->method);
        # TODO - SOAP::Dispatcher plugs in here
        # my $handler = $self->dispatcher->find_handler($request);
        my($class, $method_uri, $method_name) = $self->find_target($request);
        my @results = eval {
            local $^W;
            my @parameters = $request->paramsin;

            # SOAP::Trace::dispatch($fullname);
            SOAP::Trace::parameters(@parameters);

            push @parameters, $request
                if UNIVERSAL::isa($class => 'SOAP::Server::Parameters');

            no strict qw(refs);
            SOAP::Server::Object->references(
                defined $parameters[0]
                && ref $parameters[0]
                && UNIVERSAL::isa($parameters[0] => $class)
                    ? do {
                        my $object = shift @parameters;
                        SOAP::Server::Object->object(ref $class
                            ? $class
                            : $object
                        )->$method_name(SOAP::Server::Object->objects(@parameters)),

                        # send object back as a header
                        # preserve name, specify URI
                        SOAP::Header
                            ->uri($SOAP::Constants::NS_SL_HEADER => $object)
                            ->name($request->dataof($som->method.'/[1]')->name)
                    } # end do block

                    # SOAP::Dispatcher will plug-in here as well
                    # $handler->dispatch(SOAP::Server::Object->objects(@parameters)
                    : $class->$method_name(SOAP::Server::Object->objects(@parameters)) );
        }; # end eval block
        SOAP::Trace::result(@results);

        # let application errors pass through with 'Server' code
        die ref $@
            ? $@
            : $@ =~ /^Can\'t locate object method "$method_name"/
                ? "Failed to locate method ($method_name) in class ($class)"
                : SOAP::Fault->faultcode($SOAP::Constants::FAULT_SERVER)->faultstring($@)
                    if $@;

        my $result = $self->serializer
            ->prefix('s') # distinguish generated element names between client and server
            ->uri($method_uri)
            ->envelope(response => $method_name . 'Response', @results);
        return $result;
    };

    # void context
    return unless defined wantarray;

    # normal result
    return $result unless $@;

    # check fails, something wrong with message
    return $self->make_fault($SOAP::Constants::FAULT_CLIENT, $@) unless ref $@;

    # died with SOAP::Fault
    return $self->make_fault($@->faultcode   || $SOAP::Constants::FAULT_SERVER,
        $@->faultstring || 'Application error',
        $@->faultdetail, $@->faultactor)
    if UNIVERSAL::isa($@ => 'SOAP::Fault');

    # died with complex detail
    return $self->make_fault($SOAP::Constants::FAULT_SERVER, 'Application error' => $@);

} # end of handle()

sub make_fault {
    my $self = shift;
    my($code, $string, $detail, $actor) = @_;
    $self->serializer->fault($code, $string, $detail, $actor || $self->myuri);
}

# ======================================================================

package SOAP::Trace;

use Carp ();

my @list = qw(
    transport   dispatch    result
    parameters  headers     objects
    method      fault       freeform
    trace       debug);
{
    no strict 'refs';
    for (@list) {
        *$_ = sub {}
    }
}

sub defaultlog {
    my $caller = (caller(1))[3]; # the 4th element returned by caller is the subroutine namea
    $caller = (caller(2))[3] if $caller =~ /eval/;
    chomp(my $msg = join ' ', @_);
    printf STDERR "%s: %s\n", $caller, $msg;
}

sub import {
    no strict 'refs';
    local $^W;
    my $pack = shift;
    my(@notrace, @symbols);
    for (@_) {
        if (ref eq 'CODE') {
            my $call = $_;
            foreach (@symbols) { *$_ = sub { $call->(@_) } }
            @symbols = ();
        }
        else {
            local $_ = $_;
            my $minus = s/^-//;
            my $all = $_ eq 'all';
            Carp::carp "Illegal symbol for tracing ($_)" unless $all || $pack->can($_);
            $minus ? push(@notrace, $all ? @list : $_) : push(@symbols, $all ? @list : $_);
        }
    }
    # TODO - I am getting a warning here about redefining a subroutine
    foreach (@symbols) { *$_ = \&defaultlog }
    foreach (@notrace) { *$_ = sub {} }
}

# ======================================================================

package SOAP::Custom::XML::Data;

use vars qw(@ISA $AUTOLOAD);
@ISA = qw(SOAP::Data);

use overload fallback => 1, '""' => sub { shift->value };

sub _compileit {
    no strict 'refs';
    my $method = shift;
    *$method = sub {
        return __PACKAGE__->SUPER::name($method => $_[0]->attr->{$method})
            if exists $_[0]->attr->{$method};
        my @elems = grep {
            ref $_ && UNIVERSAL::isa($_ => __PACKAGE__)
            && $_->SUPER::name =~ /(^|:)$method$/
        } $_[0]->value;
        return wantarray? @elems : $elems[0];
    };
}

sub BEGIN { foreach (qw(name type import use)) { _compileit($_) } }

sub AUTOLOAD {
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
    return if $method eq 'DESTROY';

    _compileit($method);
    goto &$AUTOLOAD;
}

# ======================================================================

package SOAP::Custom::XML::Deserializer;

use vars qw(@ISA);
@ISA = qw(SOAP::Deserializer);

sub decode_value {
    my $self = shift;
    my $ref = shift;
    my($name, $attrs, $children, $value) = @$ref;
    # base class knows what to do with it
    return $self->SUPER::decode_value($ref) if exists $attrs->{href};

    SOAP::Custom::XML::Data
        -> SOAP::Data::name($name)
        -> attr($attrs)
        -> set_value(ref $children && @$children
            ? map(scalar(($self->decode_object($_))[1]), @$children)
            : $value);
}

# ======================================================================

package SOAP::Schema::Deserializer;

use vars qw(@ISA);
@ISA = qw(SOAP::Custom::XML::Deserializer);

# ======================================================================

package SOAP::Schema::WSDL;

use vars qw(%imported @ISA);
@ISA = qw(SOAP::Schema);

sub new {
    my $self = shift;

    unless (ref $self) {
        my $class = $self;
        $self = $class->SUPER::new(@_);
    }
    return $self;
}

sub base {
    my $self = shift->new;
    @_
        ? ($self->{_base} = shift, return $self)
        : return $self->{_base};
}

sub import {
    my $self = shift->new;
    my $s = shift;
    my $base = shift || $self->base || die "Missing base argument for ", __PACKAGE__, "\n";

    my @a = $s->import;
    local %imported = %imported;
    foreach (@a) {
        next unless $_->location;
        my $location = URI->new_abs($_->location->value, $base)->as_string;
        if ($imported{$location}++) {
            warn "Recursion loop detected in service description from '$location'. Ignored\n" if $^W;
            return $s;
        }
        my $root = $self->import(
            $self->deserializer->deserialize(
                $self->access($location)
            )->root, $location);

        $root->SOAP::Data::name eq 'definitions' ? $s->set_value($s->value, $root->value) :
        $root->SOAP::Data::name eq 'schema' ? do { # add <types> element if there is no one
        $s->set_value($s->value, $self->deserializer->deserialize('<types></types>')->root) unless $s->types;
        $s->types->set_value($s->types->value, $root) } :
        die "Don't know what to do with '@{[$root->SOAP::Data::name]}' in schema imported from '$location'\n";
    }

    # return the parsed WSDL file
    $s;
}

# TODO - This is woefully incomplete!
sub parse_schema_element {
    my $element = shift;
    # Current element is a complex type
    if (defined($element->complexType)) {
        my @elements = ();
        if (defined($element->complexType->sequence)) {

            foreach my $e ($element->complexType->sequence->element) {
                push @elements,parse_schema_element($e);
            }
        }
        return @elements;
    }
    elsif ($element->simpleType) {
    }
    else {
        return $element;
    }
}

sub parse {
    my $self = shift->new;
    my($s, $service, $port) = @_;
    my @result;

    # handle imports
    $self->import($s);

    # handle descriptions without <service>, aka tModel-type descriptions
    my @services = $s->service;
    my $tns = $s->{'_attr'}->{'targetNamespace'};
    # if there is no <service> element we'll provide it
    @services = $self->deserializer->deserialize(<<"FAKE")->root->service unless @services;
<definitions>
  <service name="@{[$service || 'FakeService']}">
    <port name="@{[$port || 'FakePort']}" binding="@{[$s->binding->name]}"/>
  </service>
</definitions>
FAKE

    my $has_warned = 0;
    foreach (@services) {
        my $name = $_->name;
        next if $service && $service ne $name;
        my %services;
        foreach ($_->port) {
            next if $port && $port ne $_->name;
            my $binding = SOAP::Utils::disqualify($_->binding);
            my $endpoint = ref $_->address ? $_->address->location : undef;
            foreach ($s->binding) {
                # is this a SOAP binding?
                next unless grep { $_->uri eq 'http://schemas.xmlsoap.org/wsdl/soap/' } $_->binding;
                next unless $_->name eq $binding;
                my $default_style = $_->binding->style;
                my $porttype = SOAP::Utils::disqualify($_->type);
                foreach ($_->operation) {
                    my $opername = $_->name;
                    $services{$opername} = {}; # should be initialized in 5.7 and after
                    my $soapaction = $_->operation->soapAction;
                    my $invocationStyle = $_->operation->style || $default_style || "rpc";
                    my $encodingStyle = $_->input->body->use || "encoded";
                    my $namespace = $_->input->body->namespace || $tns;
                    my @parts;
                    foreach ($s->portType) {
                        next unless $_->name eq $porttype;
                        foreach ($_->operation) {
                            next unless $_->name eq $opername;
                            my $inputmessage = SOAP::Utils::disqualify($_->input->message);
                            foreach my $msg ($s->message) {
                                next unless $msg->name eq $inputmessage;
                                if ($invocationStyle eq "document" && $encodingStyle eq "literal") {
#                  warn "document/literal support is EXPERIMENTAL in SOAP::Lite"
#                  if !$has_warned && ($has_warned = 1);
                                    my ($input_ns,$input_name) = SOAP::Utils::splitqname($msg->part->element);
                                    foreach my $schema ($s->types->schema) {
                                        foreach my $element ($schema->element) {
                                            next unless $element->name eq $input_name;
                                            push @parts,parse_schema_element($element);
                                        }
                                        $services{$opername}->{parameters} = [ @parts ];
                                    }
                                }
                                else {
                                    # TODO - support all combinations of doc|rpc/lit|enc.
                                    #warn "$invocationStyle/$encodingStyle is not supported in this version of SOAP::Lite";
                                    @parts = $msg->part;
                                    $services{$opername}->{parameters} = [ @parts ];
                                }
                            }
                        }

                    for ($services{$opername}) {
                        $_->{endpoint}   = $endpoint;
                        $_->{soapaction} = $soapaction;
                        $_->{namespace}  = $namespace;
                        # $_->{parameters} = [@parts];
                    }
                }
            }
        }
    }
    # fix nonallowed characters in package name, and add 's' if started with digit
    for ($name) { s/\W+/_/g; s/^(\d)/s$1/ }
    push @result, $name => \%services;
    }
    return @result;
}

# ======================================================================

# Naming? SOAP::Service::Schema?
package SOAP::Schema;

use Carp ();

sub DESTROY { SOAP::Trace::objects('()') }

sub new {
    my $self = shift;
    return $self if ref $self;
    unless (ref $self) {
        my $class = $self;
        require LWP::UserAgent;
        $self = bless {
            '_deserializer' => SOAP::Schema::Deserializer->new,
            '_useragent'    => LWP::UserAgent->new,
        }, $class;

        SOAP::Trace::objects('()');
    }

    Carp::carp "Odd (wrong?) number of parameters in new()" if $^W && (@_ & 1);
    no strict qw(refs);
    while (@_) {
        my $method = shift;
        $self->$method(shift) if $self->can($method)
    }

    return $self;
}

sub schema {
    warn "SOAP::Schema->schema has been deprecated. "
        . "Please use SOAP::Schema->schema_url instead.";
    return shift->schema_url(@_);
}

sub BEGIN {
    no strict 'refs';
    for my $method (qw(deserializer schema_url services useragent stub cache_dir cache_ttl)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new;
            @_ ? ($self->{$field} = shift, return $self) : return $self->{$field};
        }
    }
}

sub parse {
    my $self = shift;
    my $s = $self->deserializer->deserialize($self->access)->root;
    # here should be something that defines what schema description we want to use
    $self->services({SOAP::Schema::WSDL->base($self->schema_url)->parse($s, @_)});
}

sub refresh_cache {
    my $self = shift;
    my ($filename,$contents) = @_;
    open CACHE,">$filename" or Carp::croak "Could not open cache file for writing: $!";
    print CACHE $contents;
    close CACHE;
}

sub load {
    my $self = shift->new;
    local $^W; # supress warnings about redefining
    foreach (keys %{$self->services || Carp::croak 'Nothing to load. Schema is not specified'}) {
        # TODO - check age of cached file, and delete if older than configured amount
        if ($self->cache_dir) {
            my $cached_file = File::Spec->catfile($self->cache_dir,$_.".pm");
            my $ttl = $self->cache_ttl || $SOAP::Constants::DEFAULT_CACHE_TTL;
            open (CACHE, "<$cached_file");
            my @stat = stat($cached_file) unless eof(CACHE);
            close CACHE;
            if (@stat) {
                # Cache exists
                my $cache_lived = time() - $stat[9];
                if ($ttl > 0 && $cache_lived > $ttl) {
                    $self->refresh_cache($cached_file,$self->generate_stub($_));
                }
            }
            else {
                # Cache doesn't exist
                $self->refresh_cache($cached_file,$self->generate_stub($_));
            }
            push @INC,$self->cache_dir;
            eval "require $_" or Carp::croak "Could not load cached file: $@";
        }
        else {
            eval $self->generate_stub($_) or Carp::croak "Bad stub: $@";
        }
    }
    $self;
}

sub access {
    my $self = shift->new;
    my $url = shift || $self->schema_url || Carp::croak 'Nothing to access. URL is not specified';
    $self->useragent->env_proxy if $ENV{'HTTP_proxy'};

    my $req = HTTP::Request->new(GET => $url);
    $req->proxy_authorization_basic($ENV{'HTTP_proxy_user'}, $ENV{'HTTP_proxy_pass'})
        if ($ENV{'HTTP_proxy_user'} && $ENV{'HTTP_proxy_pass'});

    my $resp = $self->useragent->request($req);
    $resp->is_success ? $resp->content : die "Service description '$url' can't be loaded: ",  $resp->status_line, "\n";
}

sub generate_stub {
    my $self = shift->new;
    my $package = shift;
    my $services = $self->services->{$package};
    my $schema_url = $self->schema_url;

    $self->{'_stub'} = <<"EOP";
package $package;
# Generated by SOAP::Lite (v$SOAP::Lite::VERSION) for Perl -- soaplite.com
# Copyright (C) 2000-2006 Paul Kulchenko, Byrne Reese
# -- generated at [@{[scalar localtime]}]
EOP
    $self->{'_stub'} .= "# -- generated from $schema_url\n" if $schema_url;
    $self->{'_stub'} .= 'my %methods = ('."\n";
    foreach my $service (keys %$services) {
        $self->{'_stub'} .= "$service => {\n";
        foreach (qw(endpoint soapaction namespace)) {
            $self->{'_stub'} .= "    $_ => '".$services->{$service}{$_}."',\n";
        }
        $self->{'_stub'} .= "    parameters => [\n";
        foreach (@{$services->{$service}{parameters}}) {
            # This is a workaround for https://sourceforge.net/tracker/index.php?func=detail&aid=2001592&group_id=66000&atid=513017
            next unless ref $_;
            $self->{'_stub'} .= "      SOAP::Data->new(name => '".$_->name."', type => '".$_->type."', attr => {";
            $self->{'_stub'} .= do {
                my %attr = %{$_->attr};
                join(', ', map {"'$_' => '$attr{$_}'"}
                    grep {/^xmlns:(?!-)/}
                        keys %attr);
            };
            $self->{'_stub'} .= "}),\n";
        }
        $self->{'_stub'} .= "    ], # end parameters\n";
        $self->{'_stub'} .= "  }, # end $service\n";
    }
    $self->{'_stub'} .= "); # end my %methods\n";
    $self->{'_stub'} .= <<'EOP';

use SOAP::Lite;
use Exporter;
use Carp ();

use vars qw(@ISA $AUTOLOAD @EXPORT_OK %EXPORT_TAGS);
@ISA = qw(Exporter SOAP::Lite);
@EXPORT_OK = (keys %methods);
%EXPORT_TAGS = ('all' => [@EXPORT_OK]);

sub _call {
    my ($self, $method) = (shift, shift);
    my $name = UNIVERSAL::isa($method => 'SOAP::Data') ? $method->name : $method;
    my %method = %{$methods{$name}};
    $self->proxy($method{endpoint} || Carp::croak "No server address (proxy) specified")
        unless $self->proxy;
    my @templates = @{$method{parameters}};
    my @parameters = ();
    foreach my $param (@_) {
        if (@templates) {
            my $template = shift @templates;
            my ($prefix,$typename) = SOAP::Utils::splitqname($template->type);
            my $method = 'as_'.$typename;
            # TODO - if can('as_'.$typename) {...}
            my $result = $self->serializer->$method($param, $template->name, $template->type, $template->attr);
            push(@parameters, $template->value($result->[2]));
        }
        else {
            push(@parameters, $param);
        }
    }
    $self->endpoint($method{endpoint})
       ->ns($method{namespace})
       ->on_action(sub{qq!"$method{soapaction}"!});
EOP
    my $namespaces = $self->deserializer->ids->[1];
    foreach my $key (keys %{$namespaces}) {
        my ($ns,$prefix) = SOAP::Utils::splitqname($key);
        $self->{'_stub'} .= '  $self->serializer->register_ns("'.$namespaces->{$key}.'","'.$prefix.'");'."\n"
            if ($ns eq "xmlns");
    }
    $self->{'_stub'} .= <<'EOP';
    my $som = $self->SUPER::call($method => @parameters);
    if ($self->want_som) {
        return $som;
    }
    UNIVERSAL::isa($som => 'SOAP::SOM') ? wantarray ? $som->paramsall : $som->result : $som;
}

sub BEGIN {
    no strict 'refs';
    for my $method (qw(want_som)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new;
            @_ ? ($self->{$field} = shift, return $self) : return $self->{$field};
        }
    }
}
no strict 'refs';
for my $method (@EXPORT_OK) {
    my %method = %{$methods{$method}};
    *$method = sub {
        my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
            ? ref $_[0]
                ? shift # OBJECT
                # CLASS, either get self or create new and assign to self
                : (shift->self || __PACKAGE__->self(__PACKAGE__->new))
            # function call, either get self or create new and assign to self
            : (__PACKAGE__->self || __PACKAGE__->self(__PACKAGE__->new));
        $self->_call($method, @_);
    }
}

sub AUTOLOAD {
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
    return if $method eq 'DESTROY' || $method eq 'want_som';
    die "Unrecognized method '$method'. List of available method(s): @EXPORT_OK\n";
}

1;
EOP
    return $self->stub;
}

# ======================================================================

package SOAP;

use vars qw($AUTOLOAD);
require URI;

my $soap; # shared between SOAP and SOAP::Lite packages

{
    no strict 'refs';
    *AUTOLOAD = sub {
        local($1,$2);
        my($package, $method) = $AUTOLOAD =~ m/(?:(.+)::)([^:]+)$/;
        return if $method eq 'DESTROY';

        my $soap = ref $_[0] && UNIVERSAL::isa($_[0] => 'SOAP::Lite')
            ? $_[0]
            : $soap
                || die "SOAP:: prefix shall only be used in combination with +autodispatch option\n";

        my $uri = URI->new($soap->uri);
        my $currenturi = $uri->path;
        $package = ref $_[0] && UNIVERSAL::isa($_[0] => 'SOAP::Lite')
            ? $currenturi
            : $package eq 'SOAP'
                ? ref $_[0] || ($_[0] eq 'SOAP'
                    ? $currenturi || Carp::croak "URI is not specified for method call"
                    : $_[0])
                : $package eq 'main'
                    ? $currenturi || $package
                    : $package;

        # drop first parameter if it's a class name
        {
            my $pack = $package;
            for ($pack) { s!^/!!; s!/!::!g; }
            shift @_ if @_ && !ref $_[0] && ($_[0] eq $pack || $_[0] eq 'SOAP')
                || ref $_[0] && UNIVERSAL::isa($_[0] => 'SOAP::Lite');
        }

        for ($package) { s!::!/!g; s!^/?!/!; }
        $uri->path($package);

        my $som = $soap->uri($uri->as_string)->call($method => @_);
        UNIVERSAL::isa($som => 'SOAP::SOM')
            ? wantarray
                ? $som->paramsall
                : $som->result
            : $som;
    };
}

# ======================================================================

package SOAP::Lite;

use vars qw($AUTOLOAD @ISA);
use Carp ();

use SOAP::Lite::Utils;
use SOAP::Constants;
use SOAP::Packager;

use Scalar::Util qw(weaken);

@ISA = qw(SOAP::Cloneable);

# provide access to global/autodispatched object
sub self {
    @_ > 1
        ? $soap = $_[1]
        : $soap
}

# no more warnings about "used only once"
*UNIVERSAL::AUTOLOAD if 0;

sub autodispatched { \&{*UNIVERSAL::AUTOLOAD} eq \&{*SOAP::AUTOLOAD} };

sub soapversion {
    my $self = shift;
    my $version = shift or return $SOAP::Constants::SOAP_VERSION;

    ($version) = grep {
        $SOAP::Constants::SOAP_VERSIONS{$_}->{NS_ENV} eq $version
        } keys %SOAP::Constants::SOAP_VERSIONS
            unless exists $SOAP::Constants::SOAP_VERSIONS{$version};

    die qq!$SOAP::Constants::WRONG_VERSION Supported versions:\n@{[
        join "\n", map {"  $_ ($SOAP::Constants::SOAP_VERSIONS{$_}->{NS_ENV})"} keys %SOAP::Constants::SOAP_VERSIONS
        ]}\n!
        unless defined($version) && defined(my $def = $SOAP::Constants::SOAP_VERSIONS{$version});

    foreach (keys %$def) {
        eval "\$SOAP::Constants::$_ = '$SOAP::Constants::SOAP_VERSIONS{$version}->{$_}'";
    }

    $SOAP::Constants::SOAP_VERSION = $version;

    return $self;
}

BEGIN { SOAP::Lite->soapversion(1.1) }

sub import {
    my $pkg = shift;
    my $caller = caller;
    no strict 'refs';
    # emulate 'use SOAP::Lite 0.99' behavior
    $pkg->require_version(shift) if defined $_[0] && $_[0] =~ /^\d/;

    while (@_) {
        my $command = shift;

        my @parameters = UNIVERSAL::isa($_[0] => 'ARRAY')
            ? @{shift()}
            : shift
                if @_ && $command ne 'autodispatch';

        if ($command eq 'autodispatch' || $command eq 'dispatch_from') {
            $soap = ($soap||$pkg)->new;
            no strict 'refs';
            foreach ($command eq 'autodispatch'
                ? 'UNIVERSAL'
                : @parameters
            ) {
                my $sub = "${_}::AUTOLOAD";
                defined &{*$sub}
                    ? (\&{*$sub} eq \&{*SOAP::AUTOLOAD}
                        ? ()
                        : Carp::croak "$sub already assigned and won't work with DISPATCH. Died")
                    : (*$sub = *SOAP::AUTOLOAD);
            }
        }
        elsif ($command eq 'service') {
            foreach (keys %{SOAP::Schema->schema_url(shift(@parameters))->parse(@parameters)->load->services}) {
                $_->export_to_level(1, undef, ':all');
            }
        }
        elsif ($command eq 'debug' || $command eq 'trace') {
            SOAP::Trace->import(@parameters ? @parameters : 'all');
        }
        elsif ($command eq 'import') {
            local $^W; # supress warnings about redefining
            my $package = shift(@parameters);
            $package->export_to_level(1, undef, @parameters ? @parameters : ':all') if $package;
        }
        else {
            Carp::carp "Odd (wrong?) number of parameters in import(), still continue" if $^W && !(@parameters & 1);
            $soap = ($soap||$pkg)->$command(@parameters);
        }
    }
}

sub DESTROY { SOAP::Trace::objects('()') }

sub new {
    my $self = shift;
    return $self if ref $self;
    unless (ref $self) {
        my $class = $self;
        # Check whether we can clone. Only the SAME class allowed, no inheritance
        $self = ref($soap) eq $class ? $soap->clone : {
            _transport    => SOAP::Transport->new,
            _serializer   => SOAP::Serializer->new,
            _deserializer => SOAP::Deserializer->new,
            _packager     => SOAP::Packager::MIME->new,
            _schema       => undef,
            _autoresult   => 0,
            _on_action    => sub { sprintf '"%s#%s"', shift || '', shift },
            _on_fault     => sub {ref $_[1] ? return $_[1] : Carp::croak $_[0]->transport->is_success ? $_[1] : $_[0]->transport->status},
        };
        bless $self => $class;
        $self->on_nonserialized($self->on_nonserialized || $self->serializer->on_nonserialized);
        SOAP::Trace::objects('()');
    }

    Carp::carp "Odd (wrong?) number of parameters in new()" if $^W && (@_ & 1);
    no strict qw(refs);
    while (@_) {
        my($method, $params) = splice(@_,0,2);
        $self->can($method)
            ? $self->$method(ref $params eq 'ARRAY' ? @$params : $params)
            : $^W && Carp::carp "Unrecognized parameter '$method' in new()"
    }

    return $self;
}

sub init_context {
    my $self = shift->new;
    $self->{'_deserializer'}->{'_context'} = $self;
    # weaken circular reference to avoid a memory hole
    weaken $self->{'_deserializer'}->{'_context'};

    $self->{'_serializer'}->{'_context'} = $self;
    # weaken circular reference to avoid a memory hole
    weaken $self->{'_serializer'}->{'_context'};
}

# Naming? wsdl_parser
sub schema {
    my $self = shift;
    if (@_) {
        $self->{'_schema'} = shift;
        return $self;
    }
    else {
        if (!defined $self->{'_schema'}) {
            $self->{'_schema'} = SOAP::Schema->new;
        }
        return $self->{'_schema'};
    }
}

sub BEGIN {
    no strict 'refs';
    for my $method (qw(serializer deserializer)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new;
            if (@_) {
                my $context = $self->{$field}->{'_context'}; # save the old context
                $self->{$field} = shift;
                $self->{$field}->{'_context'} = $context;    # restore the old context
                return $self;
            }
            else {
                return $self->{$field};
            }
        }
    }

    __PACKAGE__->__mk_accessors(
        qw(endpoint transport outputxml autoresult packager)
    );
    #  for my $method () {
    #    my $field = '_' . $method;
    #    *$method = sub {
    #      my $self = shift->new;
    #      @_ ? ($self->{$field} = shift, return $self) : return $self->{$field};
    #    }
    #  }
    for my $method (qw(on_action on_fault on_nonserialized)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new;
            return $self->{$field} unless @_;
            local $@;
            # commented out because that 'eval' was unsecure
            # > ref $_[0] eq 'CODE' ? shift : eval shift;
            # Am I paranoid enough?
            $self->{$field} = shift;
            Carp::croak $@ if $@;
            Carp::croak "$method() expects subroutine (CODE) or string that evaluates into subroutine (CODE)"
                unless ref $self->{$field} eq 'CODE';
            return $self;
        }
    }
    # SOAP::Transport Shortcuts
    # TODO - deprecate proxy() in favor of new language endpoint_url()
    no strict qw(refs);
    for my $method (qw(proxy)) {
        *$method = sub {
            my $self = shift->new;
            @_ ? ($self->transport->$method(@_), return $self) : return $self->transport->$method();
        }
    }

    # SOAP::Seriailizer Shortcuts
    for my $method (qw(autotype readable envprefix encodingStyle
                    encprefix multirefinplace encoding
                    typelookup header maptype xmlschema
                    uri ns_prefix ns_uri use_prefix use_default_ns
                    ns default_ns)) {
        *$method = sub {
            my $self = shift->new;
            @_ ? ($self->serializer->$method(@_), return $self) : return $self->serializer->$method();
        }
    }

    # SOAP::Schema Shortcuts
    for my $method (qw(cache_dir cache_ttl)) {
        *$method = sub {
            my $self = shift->new;
            @_ ? ($self->schema->$method(@_), return $self) : return $self->schema->$method();
        }
    }
}

sub parts {
    my $self = shift;
    $self->packager->parts(@_);
    return $self;
}

# Naming? wsdl
sub service {
    my $self = shift->new;
    return $self->{'_service'} unless @_;
    $self->schema->schema_url($self->{'_service'} = shift);
    my %services = %{$self->schema->parse(@_)->load->services};

    Carp::croak "More than one service in service description. Service and port names have to be specified\n"
        if keys %services > 1;
    my $service = (keys %services)[0]->new;
    return $service;
}

sub AUTOLOAD {
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
    return if $method eq 'DESTROY';

    ref $_[0] or Carp::croak qq!Can\'t locate class method "$method" via package \"! . __PACKAGE__ .'\"';

    no strict 'refs';
    *$AUTOLOAD = sub {
        my $self = shift;
        my $som = $self->call($method => @_);
        return $self->autoresult && UNIVERSAL::isa($som => 'SOAP::SOM')
            ? wantarray ? $som->paramsall : $som->result
            : $som;
    };
    goto &$AUTOLOAD;
}

sub call {
    SOAP::Trace::trace('()');
    my $self = shift;

    die "A service address has not been specified either by using SOAP::Lite->proxy() or a service description)\n"
        unless defined $self->proxy && UNIVERSAL::isa($self->proxy => 'SOAP::Client');

    $self->init_context();

    my $serializer = $self->serializer;
    $serializer->on_nonserialized($self->on_nonserialized);

    my $response = $self->transport->send_receive(
        context  => $self, # this is provided for context
        endpoint => $self->endpoint,
        action   => scalar($self->on_action->($serializer->uriformethod($_[0]))),
                # leave only parameters so we can later update them if required
        envelope => $serializer->envelope(method => shift, @_),
        encoding => $serializer->encoding,
        parts    => @{$self->packager->parts} ? $self->packager->parts : undef,
    );

    return $response if $self->outputxml;

    my $result = eval { $self->deserializer->deserialize($response) }
        if $response;

    if (!$self->transport->is_success || # transport fault
        $@ ||                            # not deserializible
        # fault message even if transport OK
        # or no transport error (for example, fo TCP, POP3, IO implementations)
        UNIVERSAL::isa($result => 'SOAP::SOM') && $result->fault) {
        return ($self->on_fault->($self, $@
            ? $@ . ($response || '')
            : $result)
                || $result
        );
        # ? # trick editors
    }
    # this might be trouble for connection close...
    return unless $response; # nothing to do for one-ways

    # little bit tricky part that binds in/out parameters
    if (UNIVERSAL::isa($result => 'SOAP::SOM')
        && ($result->paramsout || $result->headers)
        && $serializer->signature) {
        my $num = 0;
        my %signatures = map {$_ => $num++} @{$serializer->signature};
        for ($result->dataof(SOAP::SOM::paramsout), $result->dataof(SOAP::SOM::headers)) {
            my $signature = join $;, $_->name, $_->type || '';
            if (exists $signatures{$signature}) {
                my $param = $signatures{$signature};
                my($value) = $_->value; # take first value

                # fillup parameters
                UNIVERSAL::isa($_[$param] => 'SOAP::Data')
                    ? $_[$param]->SOAP::Data::value($value)
                    : UNIVERSAL::isa($_[$param] => 'ARRAY')
                        ? (@{$_[$param]} = @$value)
                        : UNIVERSAL::isa($_[$param] => 'HASH')
                            ? (%{$_[$param]} = %$value)
                            : UNIVERSAL::isa($_[$param] => 'SCALAR')
                                ? (${$_[$param]} = $$value)
                                : ($_[$param] = $value)
            }
        }
    }
    return $result;
} # end of call()

# ======================================================================

package SOAP::Lite::COM;

require SOAP::Lite;

sub required {
  foreach (qw(
    URI::_foreign URI::http URI::https
    LWP::Protocol::http LWP::Protocol::https LWP::Authen::Basic LWP::Authen::Digest
    HTTP::Daemon Compress::Zlib SOAP::Transport::HTTP
    XMLRPC::Lite XMLRPC::Transport::HTTP
  )) {
    eval join ';', 'local $SIG{__DIE__}', "require $_";
  }
}

sub new    { required; SOAP::Lite->new(@_) }

sub create; *create = \&new; # make alias. Somewhere 'new' is registered keyword

sub soap; *soap = \&new;     # also alias. Just to be consistent with .xmlrpc call

sub xmlrpc { required; XMLRPC::Lite->new(@_) }

sub server { required; shift->new(@_) }

sub data   { SOAP::Data->new(@_) }

sub header { SOAP::Header->new(@_) }

sub hash   { +{@_} }

sub instanceof {
  my $class = shift;
  die "Incorrect class name" unless $class =~ /^(\w[\w:]*)$/;
  eval "require $class";
  $class->new(@_);
}

# ======================================================================

1;

__END__

=pod

=head1 NAME

SOAP::Lite - Perl's Web Services Toolkit

=head1 DESCRIPTION

SOAP::Lite is a collection of Perl modules which provides a simple and
lightweight interface to the Simple Object Access Protocol (SOAP) both on
client and server side.

=head1 PERL VERSION WARNING

SOAP::Lite 0.71 will be the last version of SOAP::Lite running on perl 5.005

Future versions of SOAP::Lite will require at least perl 5.6.0

If you have not had the time to upgrad your perl, you should consider this
now.

=head1 OVERVIEW OF CLASSES AND PACKAGES

=over

=item F<lib/SOAP/Lite.pm>

L<SOAP::Lite> - Main class provides all logic

L<SOAP::Transport> - Transport backend

L<SOAP::Data> - Data objects

L<SOAP::Header> - Header Data Objects

L<SOAP::Serializer> - Serializes data structures to SOAP messages

L<SOAP::Deserializer> - Deserializes SOAP messages into SOAP::SOM objects

L<SOAP::SOM> - SOAP Message objects

L<SOAP::Constants> - Provides access to common constants and defaults

L<SOAP::Trace> - Tracing facilities

L<SOAP::Schema> - Provides access and stub(s) for schema(s)

L<SOAP::Schema::WSDL|SOAP::Schema/SOAP::Schema::WSDL> - WSDL implementation for SOAP::Schema

L<SOAP::Server> - Handles requests on server side

SOAP::Server::Object - Handles objects-by-reference

L<SOAP::Fault> - Provides support for Faults on server side

L<SOAP::Utils> - A set of private and public utility subroutines

=item F<lib/SOAP/Packager.pm>

L<SOAP::Packager> - Provides an abstract class for implementing custom packagers.

L<SOAP::Packager::MIME|SOAP::Packager/SOAP::Packager::MIME> - Provides MIME support to SOAP::Lite

L<SOAP::Packager::DIME|SOAP::Packager/SOAP::Packager::DIME> - Provides DIME support to SOAP::Lite

=item F<lib/SOAP/Transport/HTTP.pm>

L<SOAP::Transport::HTTP::Client|SOAP::Transport/SOAP::Transport::HTTP::Client> - Client interface to HTTP transport

L<SOAP::Transport::HTTP::Server|SOAP::Transport/SOAP::Transport::HTTP::Server> - Server interface to HTTP transport

L<SOAP::Transport::HTTP::CGI|SOAP::Transport/SOAP::Transport::HTTP::CGI> - CGI implementation of server interface

L<SOAP::Transport::HTTP::Daemon|SOAP::Transport/SOAP::Transport::HTTP::Daemon> - Daemon implementation of server interface

L<SOAP::Transport::HTTP::Apache|SOAP::Transport/SOAP::Transport::HTTP::Apache> - mod_perl implementation of server interface

=item F<lib/SOAP/Transport/POP3.pm>

L<SOAP::Transport::POP3::Server|SOAP::Transport/SOAP::Transport::POP3::Server> - Server interface to POP3 protocol

=item F<lib/SOAP/Transport/MAILTO.pm>

L<SOAP::Transport::MAILTO::Client|SOAP::Transport/SOAP::Transport::MAILTO::Client> - Client interface to SMTP/sendmail

=item F<lib/SOAP/Transport/LOCAL.pm>

L<SOAP::Transport::LOCAL::Client|SOAP::Transport/SOAP::Transport::LOCAL::Client> - Client interface to local transport

=item F<lib/SOAP/Transport/TCP.pm>

L<SOAP::Transport::TCP::Server|SOAP::Transport/SOAP::Transport::TCP::Server> - Server interface to TCP protocol

L<SOAP::Transport::TCP::Client|SOAP::Transport/SOAP::Transport::TCP::Client> - Client interface to TCP protocol

=item F<lib/SOAP/Transport/IO.pm>

L<SOAP::Transport::IO::Server|SOAP::Transport/SOAP::Transport::IO::Server> - Server interface to IO transport

=back

=head1 METHODS

All accessor methods return the current value when called with no arguments,
while returning the object reference itself when called with a new value.
This allows the set-attribute calls to be chained together.

=over

=item new(optional key/value pairs)

    $client = SOAP::Lite->new(proxy => $endpoint)

Constructor. Many of the accessor methods defined here may be initialized at
creation by providing their name as a key, followed by the desired value.
The example provides the value for the proxy element of the client.

=item transport(optional transport object)

    $transp = $client->transport( );

Gets or sets the transport object used for sending/receiving SOAP messages.

See L<SOAP::Transport> for details.

=item serializer(optional serializer object)

    $serial = $client->serializer( )

Gets or sets the serializer object used for creating XML messages.

See L<SOAP::Serializer> for details.

=item packager(optional packager object)

    $packager = $client->packager( )

Provides access to the C<SOAP::Packager> object that the client uses to manage
the use of attachments. The default packager is a MIME packager, but unless
you specify parts to send, no MIME formatting will be done.

See also: L<SOAP::Packager>.

=item proxy(endpoint, optional extra arguments)

    $client->proxy('http://soap.xml.info/ endPoint');

The proxy is the server or endpoint to which the client is going to connect.
This method allows the setting of the endpoint, along with any extra
information that the transport object may need when communicating the request.

This method is actually an alias to the proxy method of L<SOAP::Transport>.
It is the same as typing:

    $client->transport( )->proxy(...arguments);

Extra parameters can be passed to proxy() - see below.

=over

=item compress_threshold

See L<COMPRESSION|SOAP::Transport/"COMPRESSION"> in L<HTTP::Transport>.

=item All initialization options from the underlying transport layer

The options for HTTP(S) are the same as for LWP::UserAgent's new() method.

A common option is to create a instance of HTTP::Cookies and pass it as
cookie_jar option:

 my $cookie_jar = HTTP::Cookies->new()
 $client->proxy('http://www.example.org/webservice',
    cookie_jar => $cookie_jar,
 );

=back

For example, if you wish to set the HTTP timeout for a SOAP::Lite client to 5
seconds, use the following code:

  my $soap = SOAP::Lite
   ->uri($uri)
   ->proxy($proxyUrl, timeout => 5 );

See L<LWP::UserAgent>.

=item endpoint(optional new endpoint address)

    $client->endpoint('http://soap.xml.info/ newPoint')

It may be preferable to set a new endpoint without the additional work of
examining the new address for protocol information and checking to ensure the
support code is loaded and available. This method allows the caller to change
the endpoint that the client is currently set to connect to, without
reloading the relevant transport code. Note that the proxy method must have
been called before this method is used.

=item service(service URL)

    $client->service('http://svc.perl.org/Svc.wsdl');

C<SOAP::Lite> offers some support for creating method stubs from service
descriptions. At present, only WSDL support is in place. This method loads
the specified WSDL schema and uses it as the basis for generating stubs.

=item outputxml(boolean)

    $client->outputxml('true');

When set to a true value, the raw XML is returned by the call to a remote
method.

The default is to return the a L<SOAP::SOM> object (false).

=item autotype(boolean)

    $client->autotype(0);

This method is a shortcut for:

    $client->serializer->autotype(boolean);

By default, the serializer tries to automatically deduce types for the data
being sent in a message. Setting a false value with this method disables the
behavior.

=item readable(boolean)

    $client->readable(1);

This method is a shortcut for:

    $client->serializer->readable(boolean);

When this is used to set a true value for this property, the generated XML
sent to the endpoint has extra characters (spaces and new lines) added in to
make the XML itself more readable to human eyes (presumably for debugging).
The default is to not send any additional characters.

=item default_ns($uri)

Sets the default namespace for the request to the specified uri. This
overrides any previous namespace declaration that may have been set using a
previous call to C<ns()> or C<default_ns()>. Setting the default namespace
causes elements to be serialized without a namespace prefix, like this:

  <soap:Envelope>
    <soap:Body>
      <myMethod xmlns="http://www.someuri.com">
        <foo />
      </myMethod>
    </soap:Body>
  </soap:Envelope>

Some .NET web services have been reported to require this XML namespace idiom.

=item ns($uri,$prefix=undef)

Sets the namespace uri and optionally the namespace prefix for the request to
the specified values. This overrides any previous namespace declaration that
may have been set using a previous call to C<ns()> or C<default_ns()>.

If a prefix is not specified, one will be generated for you automatically.
Setting the namespace causes elements to be serialized with a declared
namespace prefix, like this:

  <soap:Envelope>
    <soap:Body>
      <my:myMethod xmlns:my="http://www.someuri.com">
        <my:foo />
      </my:myMethod>
    </soap:Body>
  </soap:Envelope>

=item use_prefix(boolean)

Deprecated. Use the C<ns()> and C<default_ns> methods described above.

Shortcut for C<< serializer->use_prefix() >>. This lets you turn on/off the
use of a namespace prefix for the children of the /Envelope/Body element.
Default is 'true'.

When use_prefix is set to 'true', serialized XML will look like this:

  <SOAP-ENV:Envelope ...attributes skipped>
    <SOAP-ENV:Body>
      <namesp1:mymethod xmlns:namesp1="urn:MyURI" />
    </SOAP-ENV:Body>
  </SOAP-ENV:Envelope>

When use_prefix is set to 'false', serialized XML will look like this:

  <SOAP-ENV:Envelope ...attributes skipped>
    <SOAP-ENV:Body>
      <mymethod xmlns="urn:MyURI" />
    </SOAP-ENV:Body>
  </SOAP-ENV:Envelope>

Some .NET web services have been reported to require this XML namespace idiom.

=item soapversion(optional value)

    $client->soapversion('1.2');

If no parameter is given, returns the current version of SOAP that is being
used by the client object to encode requests. If a parameter is given, the
method attempts to set that as the version of SOAP being used.

The value should be either 1.1 or 1.2.

=item envprefix(QName)

    $client->envprefix('env');

This method is a shortcut for:

    $client->serializer->envprefix(QName);

Gets or sets the namespace prefix for the SOAP namespace. The default is
SOAP.

The prefix itself has no meaning, but applications may wish to chose one
explicitly to denote different versions of SOAP or the like.

=item encprefix(QName)

    $client->encprefix('enc');

This method is a shortcut for:

    $client->serializer->encprefix(QName);

Gets or sets the namespace prefix for the encoding rules namespace.
The default value is SOAP-ENC.

=back

While it may seem to be an unnecessary operation to set a value that isn't
relevant to the message, such as the namespace labels for the envelope and
encoding URNs, the ability to set these labels explicitly can prove to be a
great aid in distinguishing and debugging messages on the server side of
operations.

=over

=item encoding(encoding URN)

    $client->encoding($soap_12_encoding_URN);

This method is a shortcut for:

    $client->serializer->encoding(args);

Where the earlier method dealt with the label used for the attributes related
to the SOAP encoding scheme, this method actually sets the URN to be specified
as the encoding scheme for the message. The default is to specify the encoding
for SOAP 1.1, so this is handy for applications that need to encode according
to SOAP 1.2 rules.

=item typelookup

    $client->typelookup;

This method is a shortcut for:

    $client->serializer->typelookup;

Gives the application access to the type-lookup table from the serializer
object. See the section on L<SOAP::Serializer>.

=item uri(service specifier)

Deprecated - the C<uri> subroutine is deprecated in order to provide a more
intuitive naming scheme for subroutines that set namespaces. In the future,
you will be required to use either the C<ns()> or C<default_ns()> subroutines
instead of C<uri()>.

    $client->uri($service_uri);

This method is a shortcut for:

    $client->serializer->uri(service);

The URI associated with this accessor on a client object is the
service-specifier for the request, often encoded for HTTP-based requests as
the SOAPAction header. While the names may seem confusing, this method
doesn't specify the endpoint itself. In most circumstances, the C<uri> refers
to the namespace used for the request.

Often times, the value may look like a valid URL. Despite this, it doesn't
have to point to an existing resource (and often doesn't). This method sets
and retrieves this value from the object. Note that no transport code is
triggered by this because it has no direct effect on the transport of the
object.

=item multirefinplace(boolean)

    $client->multirefinplace(1);

This method is a shortcut for:

    $client->serializer->multirefinplace(boolean);

Controls how the serializer handles values that have multiple references to
them. Recall from previous SOAP chapters that a value may be tagged with an
identifier, then referred to in several places. When this is the case for a
value, the serializer defaults to putting the data element towards the top of
the message, right after the opening tag of the method-specification. It is
serialized as a standalone entity with an ID that is then referenced at the
relevant places later on. If this method is used to set a true value, the
behavior is different. When the multirefinplace attribute is true, the data
is serialized at the first place that references it, rather than as a separate
element higher up in the body. This is more compact but may be harder to read
or trace in a debugging environment.

=item parts( ARRAY )

Used to specify an array of L<MIME::Entity>'s to be attached to the
transmitted SOAP message. Attachments that are returned in a response can be
accessed by C<SOAP::SOM::parts()>.

=item self

    $ref = SOAP::Lite->self;

Returns an object reference to the default global object the C<SOAP::Lite>
package maintains. This is the object that processes many of the arguments
when provided on the use line.

=back

The following method isn't an accessor style of method but neither does it fit
with the group that immediately follows it:

=over

=item call(arguments)

    $client->call($method => @arguments);

As has been illustrated in previous chapters, the C<SOAP::Lite> client objects
can manage remote calls with auto-dispatching using some of Perl's more
elaborate features. call is used when the application wants a greater degree
of control over the details of the call itself. The method may be built up
from a L<SOAP::Data> object, so as to allow full control over the namespace
associated with the tag, as well as other attributes like encoding. This is
also important for calling methods that contain characters not allowable in
Perl function names, such as A.B.C.

=back

The next four methods used in the C<SOAP::Lite> class are geared towards
handling the types of events than can occur during the message lifecycle. Each
of these sets up a callback for the event in question:

=over

=item on_action(callback)

    $client->on_action(sub { qq("$_[0]") });

Triggered when the transport object sets up the SOAPAction header for an
HTTP-based call. The default is to set the header to the string, uri#method,
in which URI is the value set by the uri method described earlier, and method
is the name of the method being called. When called, the routine referenced
(or the closure, if specified as in the example) is given two arguments, uri
and method, in that order.

.NET web services usually expect C</> as separator for C<uri> and C<method>.
To change SOAP::Lite's behaviour to use uri/method as SOAPAction header, use
the following code:

    $client->on_action( sub { join '/', @_ } );
=item on_fault(callback)

    $client->on_fault(sub { popup_dialog($_[1]) });

Triggered when a method call results in a fault response from the server.
When it is called, the argument list is first the client object itself,
followed by the object that encapsulates the fault. In the example, the fault
object is passed (without the client object) to a hypothetical GUI function
that presents an error dialog with the text of fault extracted from the object
(which is covered shortly under the L<SOAP::SOM> methods).

=item on_nonserialized(callback)

    $client->on_nonserialized(sub { die "$_[0]?!?" });

Occasionally, the serializer may be given data it can't turn into SOAP-savvy
XML; for example, if a program bug results in a code reference or something
similar being passed in as a parameter to method call. When that happens, this
callback is activated, with one argument. That argument is the data item that
could not be understood. It will be the only argument. If the routine returns,
the return value is pasted into the message as the serialization. Generally,
an error is in order, and this callback allows for control over signaling that
error.

=item on_debug(callback)

    $client->on_debug(sub { print @_ });

Deprecated. Use the global +debug and +trace facilities described in
L<SOAP::Trace>

Note that this method will not work as expected: Instead of affecting the
debugging behaviour of the object called on, it will globally affect the
debugging behaviour for all objects of that class.

=back

=head1 WRITING A SOAP CLIENT

This chapter guides you to writing a SOAP client by example.

The SOAP service to be accessed is a simple variation of the well-known
hello world program. It accepts two parameters, a name and a given name,
and returns "Hello $given_name $name".

We will use "Martin Kutter" as the name for the call, so all variants will
print the following message on success:

 Hello Martin Kutter!

=head2 SOAP message styles

There are three common (and one less common) variants of SOAP messages.

These address the message style (positional parameters vs. specified message
documents) and encoding (as-is vs. typed).

The different message styles are:

=over

=item * rpc/encoded

Typed, positional parameters. Widely used in scripting languages.
The type of the arguments is included in the message.
Arrays and the like may be encoded using SOAP encoding rules (or others).

=item * rpc/literal

As-is, positional parameters. The type of arguments is defined by some
pre-exchanged interface definition.

=item * document/encoded

Specified message with typed elements. Rarely used.

=item * document/literal

Specified message with as-is elements. The message specification and
element types are defined by some pre-exchanged interface definition.

=back

As of 2008, document/literal has become the predominant SOAP message
variant. rpc/literal and rpc/encoded are still in use, mainly with scripting
languages, while document/encoded is hardly used at all.

You will see clients for the rpc/encoded and document/literal SOAP variants in
this section.

=head2 Example implementations

=head3 RPC/ENCODED

Rpc/encoded is most popular with scripting languages like perl, php and python
without the use of a WSDL. Usual method descriptions look like this:

 Method: sayHello(string, string)
 Parameters:
    name: string
    givenName: string

Such a description usually means that you can call a method named "sayHello"
with two positional parameters, "name" and "givenName", which both are
strings.

The message corresponding to this description looks somewhat like this:

 <sayHello xmlns="urn:HelloWorld">
   <s-gensym01 xsi:type="xsd:string">Kutter</s-gensym01>
   <s-gensym02 xsi:type="xsd:string">Martin</s-gensym02>
 </sayHello>

Any XML tag names may be used instead of the "s-gensym01" stuff - parameters
are positional, the tag names have no meaning.

A client producing such a call is implemented like this:

 use SOAP::Lite;
 my $soap = SOAP::Lite->new( proxy => 'http://localhost:81/soap-wsdl-test/helloworld.pl');
 $soap->default_ns('urn:HelloWorld');
 my $som = $soap->call('sayHello', 'Kutter', 'Martin');
 die $som->faultstring if ($som->fault);
 print $som->result, "\n";

You can of course use a one-liner, too...

Sometimes, rpc/encoded interfaces are described with WSDL definitions.
A WSDL accepting "named" parameters with rpc/encoded looks like this:

 <definitions xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
   xmlns:s="http://www.w3.org/2001/XMLSchema"
   xmlns:s0="urn:HelloWorld"
   targetNamespace="urn:HelloWorld"
   xmlns="http://schemas.xmlsoap.org/wsdl/">
   <types>
     <s:schema targetNamespace="urn:HelloWorld">
     </s:schema>
   </types>
   <message name="sayHello">
     <part name="name" type="s:string" />
     <part name="givenName" type="s:string" />
   </message>
   <message name="sayHelloResponse">
     <part name="sayHelloResult" type="s:string" />
   </message>

   <portType name="Service1Soap">
     <operation name="sayHello">
       <input message="s0:sayHello" />
       <output message="s0:sayHelloResponse" />
     </operation>
   </portType>

   <binding name="Service1Soap" type="s0:Service1Soap">
     <soap:binding transport="http://schemas.xmlsoap.org/soap/http"
         style="rpc" />
     <operation name="sayHello">
       <soap:operation soapAction="urn:HelloWorld#sayHello"/>
       <input>
         <soap:body use="encoded"
           encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"/>
       </input>
       <output>
         <soap:body use="encoded"
           encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"/>
       </output>
     </operation>
   </binding>
   <service name="HelloWorld">
     <port name="HelloWorldSoap" binding="s0:Service1Soap">
       <soap:address location="http://localhost:81/soap-wsdl-test/helloworld.pl" />
     </port>
   </service>
 </definitions>

The message corresponding to this schema looks like this:

 <sayHello xmlns="urn:HelloWorld">
   <name xsi:type="xsd:string">Kutter</name>
   <givenName xsi:type="xsd:string">Martin</givenName>
 </sayHello>

A web service client using this schema looks like this:

 use SOAP::Lite;
 my $soap = SOAP::Lite->service("file:say_hello_rpcenc.wsdl");
 eval { my $result = $soap->sayHello('Kutter', 'Martin'); };
 if ($@) {
     die $@;
 }
 print $som->result();

You may of course also use the following one-liner:

 perl -MSOAP::Lite -e 'print SOAP::Lite->service("file:say_hello_rpcenc.wsdl")\
   ->sayHello('Kutter', 'Martin'), "\n";'

A web service client (without a service description) looks like this.

 use SOAP::Lite;
 my $soap = SOAP::Lite->new( proxy => 'http://localhost:81/soap-wsdl-test/helloworld.pl');
 $soap->default_ns('urn:HelloWorld');
 my $som = $soap->call('sayHello',
    SOAP::Data->name('name')->value('Kutter'),
    SOAP::Data->name('givenName')->value('Martin')
 );
 die $som->faultstring if ($som->fault);
 print $som->result, "\n";

=head3 RPC/LITERAL

SOAP web services using the document/literal message encoding are usually
described by some Web Service Definition. Our web service has the following
WSDL description:

 <definitions xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
   xmlns:s="http://www.w3.org/2001/XMLSchema"
   xmlns:s0="urn:HelloWorld"
   targetNamespace="urn:HelloWorld"
   xmlns="http://schemas.xmlsoap.org/wsdl/">
   <types>
     <s:schema targetNamespace="urn:HelloWorld">
       <s:complexType name="sayHello">
         <s:sequence>
           <s:element minOccurs="0" maxOccurs="1" name="name"
              type="s:string" />
           <s:element minOccurs="0" maxOccurs="1" name="givenName"
              type="s:string" nillable="1" />
         </s:sequence>
       </s:complexType>

       <s:complexType name="sayHelloResponse">
         <s:sequence>
           <s:element minOccurs="0" maxOccurs="1" name="sayHelloResult"
              type="s:string" />
         </s:sequence>
       </s:complexType>
     </s:schema>
   </types>
   <message name="sayHello">
     <part name="parameters" type="s0:sayHello" />
   </message>
   <message name="sayHelloResponse">
     <part name="parameters" type="s0:sayHelloResponse" />
   </message>

   <portType name="Service1Soap">
     <operation name="sayHello">
       <input message="s0:sayHello" />
       <output message="s0:sayHelloResponse" />
     </operation>
   </portType>

   <binding name="Service1Soap" type="s0:Service1Soap">
     <soap:binding transport="http://schemas.xmlsoap.org/soap/http"
         style="rpc" />
     <operation name="sayHello">
       <soap:operation soapAction="urn:HelloWorld#sayHello"/>
       <input>
         <soap:body use="literal" namespace="urn:HelloWorld"/>
       </input>
       <output>
         <soap:body use="literal" namespace="urn:HelloWorld"/>
       </output>
     </operation>
   </binding>
   <service name="HelloWorld">
     <port name="HelloWorldSoap" binding="s0:Service1Soap">
       <soap:address location="http://localhost:80//helloworld.pl" />
     </port>
   </service>
  </definitions>

The XML message (inside the SOAP Envelope) look like this:


 <ns0:sayHello xmlns:ns0="urn:HelloWorld">
    <parameters>
      <name>Kutter</name>
      <givenName>Martin</givenName>
    </parameters>
 </ns0:sayHello>

 <sayHelloResponse xmlns:ns0="urn:HelloWorld">
    <parameters>
        <sayHelloResult>Hello Martin Kutter!</sayHelloResult>
    </parameters>
 </sayHelloResponse>

This is the SOAP::Lite implementation for the web service client:

 use SOAP::Lite +trace;
 my $soap = SOAP::Lite->new( proxy => 'http://localhost:80/helloworld.pl');

 $soap->on_action( sub { "urn:HelloWorld#sayHello" });
 $soap->autotype(0)->readable(1);
 $soap->default_ns('urn:HelloWorld');

 my $som = $soap->call('sayHello', SOAP::Data->name('parameters')->value(
    \SOAP::Data->value([
        SOAP::Data->name('name')->value( 'Kutter' ),
        SOAP::Data->name('givenName')->value('Martin'),
    ]))
);

 die $som->fault->{ faultstring } if ($som->fault);
 print $som->result, "\n";

=head3 DOCUMENT/LITERAL

SOAP web services using the document/literal message encoding are usually
described by some Web Service Definition. Our web service has the following
WSDL description:

 <definitions xmlns:soap="http://schemas.xmlsoap.org/wsdl/soap/"
    xmlns:s="http://www.w3.org/2001/XMLSchema"
    xmlns:s0="urn:HelloWorld"
    targetNamespace="urn:HelloWorld"
    xmlns="http://schemas.xmlsoap.org/wsdl/">
   <types>
     <s:schema targetNamespace="urn:HelloWorld">
       <s:element name="sayHello">
         <s:complexType>
           <s:sequence>
              <s:element minOccurs="0" maxOccurs="1" name="name" type="s:string" />
               <s:element minOccurs="0" maxOccurs="1" name="givenName" type="s:string" nillable="1" />
           </s:sequence>
          </s:complexType>
        </s:element>

        <s:element name="sayHelloResponse">
          <s:complexType>
            <s:sequence>
              <s:element minOccurs="0" maxOccurs="1" name="sayHelloResult" type="s:string" />
            </s:sequence>
        </s:complexType>
      </s:element>
    </types>
    <message name="sayHelloSoapIn">
      <part name="parameters" element="s0:sayHello" />
    </message>
    <message name="sayHelloSoapOut">
      <part name="parameters" element="s0:sayHelloResponse" />
    </message>

    <portType name="Service1Soap">
      <operation name="sayHello">
        <input message="s0:sayHelloSoapIn" />
        <output message="s0:sayHelloSoapOut" />
      </operation>
    </portType>

    <binding name="Service1Soap" type="s0:Service1Soap">
      <soap:binding transport="http://schemas.xmlsoap.org/soap/http"
          style="document" />
      <operation name="sayHello">
        <soap:operation soapAction="urn:HelloWorld#sayHello"/>
        <input>
          <soap:body use="literal" />
        </input>
        <output>
          <soap:body use="literal" />
        </output>
      </operation>
    </binding>
    <service name="HelloWorld">
      <port name="HelloWorldSoap" binding="s0:Service1Soap">
        <soap:address location="http://localhost:80//helloworld.pl" />
      </port>
    </service>
 </definitions>

The XML message (inside the SOAP Envelope) look like this:

 <sayHello xmlns="urn:HelloWorld">
   <name>Kutter</name>
   <givenName>Martin</givenName>
 </sayHello>

 <sayHelloResponse>
   <sayHelloResult>Hello Martin Kutter!</sayHelloResult>
 </sayHelloResponse>

You can call this web service with the following client code:

 use SOAP::Lite;
 my $soap = SOAP::Lite->new( proxy => 'http://localhost:80/helloworld.pl');

 $soap->on_action( sub { "urn:HelloWorld#sayHello" });
 $soap->autotype(0);
 $soap->default_ns('urn:HelloWorld');

 my $som = $soap->call("sayHello",
    SOAP::Data->name('name')->value( 'Kutter' ),
    SOAP::Data->name('givenName')->value('Martin'),
);

 die $som->fault->{ faultstring } if ($som->fault);
 print $som->result, "\n";

=head2 Differences between the implementations

You may have noticed that there's little difference between the rpc/encoded,
rpc/literal and the document/literal example's implementation. In fact, from
SOAP::Lite's point of view, the only differences between rpc/literal and
document/literal that parameters are always named.

In our example, the rpc/encoded variant already used named parameters (by
using two messages), so there's no difference at all.

You may have noticed the somewhat strange idiom for passing a list of named
paraneters in the rpc/literal example:

 my $som = $soap->call('sayHello', SOAP::Data->name('parameters')->value(
    \SOAP::Data->value([
        SOAP::Data->name('name')->value( 'Kutter' ),
        SOAP::Data->name('givenName')->value('Martin'),
    ]))
 );

While SOAP::Data provides full control over the XML generated, passing
hash-like structures require additional coding.

=head1 WRITING A SOAP SERVER

See L<SOAP::Server>, or L<SOAP::Transport>.

=head1 FEATURES

=head2 ATTACHMENTS

C<SOAP::Lite> features support for the SOAP with Attachments specification.
Currently, SOAP::Lite only supports MIME based attachments. DIME based
attachments are yet to be fully functional.

=head3 EXAMPLES

=head4 Client sending an attachment

C<SOAP::Lite> clients can specify attachments to be sent along with a request
by using the C<SOAP::Lite::parts()> method, which takes as an argument an
ARRAY of C<MIME::Entity>'s.

  use SOAP::Lite;
  use MIME::Entity;
  my $ent = build MIME::Entity
    Type        => "image/gif",
    Encoding    => "base64",
    Path        => "somefile.gif",
    Filename    => "saveme.gif",
    Disposition => "attachment";
  my $som = SOAP::Lite
    ->uri($SOME_NAMESPACE)
    ->parts([ $ent ])
    ->proxy($SOME_HOST)
    ->some_method(SOAP::Data->name("foo" => "bar"));

=head4 Client retrieving an attachment

A client accessing attachments that were returned in a response by using the
C<SOAP::SOM::parts()> accessor.

  use SOAP::Lite;
  use MIME::Entity;
  my $soap = SOAP::Lite
    ->uri($NS)
    ->proxy($HOST);
  my $som = $soap->foo();
  foreach my $part (${$som->parts}) {
    print $part->stringify;
  }

=head4 Server receiving an attachment

Servers, like clients, use the S<SOAP::SOM> module to access attachments
transmitted to it.

  package Attachment;
  use SOAP::Lite;
  use MIME::Entity;
  use strict;
  use vars qw(@ISA);
  @ISA = qw(SOAP::Server::Parameters);
  sub someMethod {
    my $self = shift;
    my $envelope = pop;
    foreach my $part (@{$envelope->parts}) {
      print "AttachmentService: attachment found! (".ref($part).")\n";
    }
    # do something
  }

=head4 Server responding with an attachment

Servers wishing to return an attachment to the calling client need only return
C<MIME::Entity> objects along with SOAP::Data elements, or any other data
intended for the response.

  package Attachment;
  use SOAP::Lite;
  use MIME::Entity;
  use strict;
  use vars qw(@ISA);
  @ISA = qw(SOAP::Server::Parameters);
  sub someMethod {
    my $self = shift;
    my $envelope = pop;
    my $ent = build MIME::Entity
    'Id'          => "<1234>",
    'Type'        => "text/xml",
    'Path'        => "some.xml",
    'Filename'    => "some.xml",
    'Disposition' => "attachment";
    return SOAP::Data->name("foo" => "blah blah blah"),$ent;
  }

=head2 DEFAULT SETTINGS

Though this feature looks similar to
L<autodispatch|/"IN/OUT, OUT PARAMETERS AND AUTOBINDING"> they have (almost)
nothing in common. This capability allows you specify default settings so that
all objects created after that will be initialized with the proper default
settings.

If you wish to provide common C<proxy()> or C<uri()> settings for all
C<SOAP::Lite> objects in your application you may do:

  use SOAP::Lite
    proxy => 'http://localhost/cgi-bin/soap.cgi',
    uri => 'http://my.own.com/My/Examples';

  my $soap1 = new SOAP::Lite; # will get the same proxy()/uri() as above
  print $soap1->getStateName(1)->result;

  my $soap2 = SOAP::Lite->new; # same thing as above
  print $soap2->getStateName(2)->result;

  # or you may override any settings you want
  my $soap3 = SOAP::Lite->proxy('http://localhost/');
  print $soap3->getStateName(1)->result;

B<Any> C<SOAP::Lite> properties can be propagated this way. Changes in object
copies will not affect global settings and you may still change global
settings with C<< SOAP::Lite->self >> call which returns reference to global
object. Provided parameter will update this object and you can even set it to
C<undef>:

  SOAP::Lite->self(undef);

The C<use SOAP::Lite> syntax also lets you specify default event handlers for
your code. If you have different SOAP objects and want to share the same
C<on_action()> (or C<on_fault()> for that matter) handler. You can specify
C<on_action()> during initialization for every object, but you may also do:

  use SOAP::Lite
    on_action => sub {sprintf '%s#%s', @_};

and this handler will be the default handler for all your SOAP objects. You
can override it if you specify a handler for a particular object. See F<t/*.t>
for example of on_fault() handler.

Be warned, that since C<use ...> is executed at compile time B<all> C<use>
statements will be executed B<before> script execution that can make
unexpected results. Consider code:

  use SOAP::Lite proxy => 'http://localhost/';
  print SOAP::Lite->getStateName(1)->result;

  use SOAP::Lite proxy => 'http://localhost/cgi-bin/soap.cgi';
  print SOAP::Lite->getStateName(1)->result;

B<Both> SOAP calls will go to C<'http://localhost/cgi-bin/soap.cgi'>. If you
want to execute C<use> at run-time, put it in C<eval>:

  eval "use SOAP::Lite proxy => 'http://localhost/cgi-bin/soap.cgi'; 1" or die;

Or alternatively,

  SOAP::Lite->self->proxy('http://localhost/cgi-bin/soap.cgi');

=head2 SETTING MAXIMUM MESSAGE SIZE

One feature of C<SOAP::Lite> is the ability to control the maximum size of a
message a SOAP::Lite server will be allowed to process. To control this
feature simply define C<$SOAP::Constants::MAX_CONTENT_SIZE> in your code like
so:

  use SOAP::Transport::HTTP;
  use MIME::Entity;
  $SOAP::Constants::MAX_CONTENT_SIZE = 10000;
  SOAP::Transport::HTTP::CGI
    ->dispatch_to('TemperatureService')
    ->handle;

=head2 IN/OUT, OUT PARAMETERS AND AUTOBINDING

C<SOAP::Lite> gives you access to all parameters (both in/out and out) and
also does some additional work for you. Lets consider following example:

  <mehodResponse>
    <res1>name1</res1>
    <res2>name2</res2>
    <res3>name3</res3>
  </mehodResponse>

In that case:

  $result = $r->result; # gives you 'name1'
  $paramout1 = $r->paramsout;      # gives you 'name2', because of scalar context
  $paramout1 = ($r->paramsout)[0]; # gives you 'name2' also
  $paramout2 = ($r->paramsout)[1]; # gives you 'name3'

or

  @paramsout = $r->paramsout; # gives you ARRAY of out parameters
  $paramout1 = $paramsout[0]; # gives you 'res2', same as ($r->paramsout)[0]
  $paramout2 = $paramsout[1]; # gives you 'res3', same as ($r->paramsout)[1]

Generally, if server returns C<return (1,2,3)> you will get C<1> as the result
and C<2> and C<3> as out parameters.

If the server returns C<return [1,2,3]> you will get an ARRAY reference from
C<result()> and C<undef> from C<paramsout()>.

Results can be arbitrary complex: they can be an array references, they can be
objects, they can be anything and still be returned by C<result()> . If only
one parameter is returned, C<paramsout()> will return C<undef>.

Furthermore, if you have in your output parameters a parameter with the same
signature (name+type) as in the input parameters this parameter will be mapped
into your input automatically. For example:

B<Server Code>:

  sub mymethod {
    shift; # object/class reference
    my $param1 = shift;
    my $param2 = SOAP::Data->name('myparam' => shift() * 2);
    return $param1, $param2;
  }

B<Client Code>:

  $a = 10;
  $b = SOAP::Data->name('myparam' => 12);
  $result = $soap->mymethod($a, $b);

After that, C<< $result == 10 and $b->value == 24 >>! Magic? Sort of.

Autobinding gives it to you. That will work with objects also with one
difference: you do not need to worry about the name and the type of object
parameter. Consider the C<PingPong> example (F<examples/My/PingPong.pm>
and F<examples/pingpong.pl>):

B<Server Code>:

  package My::PingPong;

  sub new {
    my $self = shift;
    my $class = ref($self) || $self;
    bless {_num=>shift} => $class;
  }

  sub next {
    my $self = shift;
    $self->{_num}++;
  }

B<Client Code>:

  use SOAP::Lite +autodispatch =>
    uri => 'urn:',
    proxy => 'http://localhost/';

  my $p = My::PingPong->new(10); # $p->{_num} is 10 now, real object returned
  print $p->next, "\n";          # $p->{_num} is 11 now!, object autobinded

=head2 STATIC AND DYNAMIC SERVICE DEPLOYMENT

Let us scrutinize the deployment process. When designing your SOAP server you
can consider two kind of deployment: B<static> and B<dynamic>. For both,
static and dynamic,  you should specify C<MODULE>, C<MODULE::method>,
C<method> or C<PATH/> when creating C<use>ing the SOAP::Lite module. The
difference between static and dynamic deployment is that in case of 'dynamic',
any module which is not present will be loaded on demand. See the
L</"SECURITY"> section for detailed description.

When statically deploying a SOAP Server, you need to know all modules handling
SOAP requests before.

Dynamic deployment allows extending your SOAP Server's interface by just
installing another module into the dispatch_to path (see below).

=head3 STATIC DEPLOYMENT EXAMPLE

  use SOAP::Transport::HTTP;
  use My::Examples;           # module is preloaded

  SOAP::Transport::HTTP::CGI
     # deployed module should be present here or client will get
     # 'access denied'
    -> dispatch_to('My::Examples')
    -> handle;

For static deployment you should specify the MODULE name directly.

You should also use static binding when you have several different classes in
one file and want to make them available for SOAP calls.

=head3 DYNAMIC DEPLOYMENT EXAMPLE

  use SOAP::Transport::HTTP;
  # name is unknown, module will be loaded on demand

  SOAP::Transport::HTTP::CGI
    # deployed module should be present here or client will get 'access denied'
    -> dispatch_to('/Your/Path/To/Deployed/Modules', 'My::Examples')
    -> handle;

For dynamic deployment you can specify the name either directly (in that case
it will be C<require>d without any restriction) or indirectly, with a PATH. In
that case, the ONLY path that will be available will be the PATH given to the
dispatch_to() method). For information how to handle this situation see
L</"SECURITY"> section.

=head3 SUMMARY

  dispatch_to(
    # dynamic dispatch that allows access to ALL modules in specified directory
    PATH/TO/MODULES
    # 1. specifies directory
    # -- AND --
    # 2. gives access to ALL modules in this directory without limits

    # static dispatch that allows access to ALL methods in particular MODULE
    MODULE
    #  1. gives access to particular module (all available methods)
    #  PREREQUISITES:
    #    module should be loaded manually (for example with 'use ...')
    #    -- OR --
    #    you can still specify it in PATH/TO/MODULES

    # static dispatch that allows access to particular method ONLY
    MODULE::method
    # same as MODULE, but gives access to ONLY particular method,
    # so there is not much sense to use both MODULE and MODULE::method
    # for the same MODULE
  );

In addition to this C<SOAP::Lite> also supports an experimental syntax that
allows you to bind a specific URL or SOAPAction to a CLASS/MODULE or object.

For example:

  dispatch_with({
    URI => MODULE,        # 'http://www.soaplite.com/' => 'My::Class',
    SOAPAction => MODULE, # 'http://www.soaplite.com/method' => 'Another::Class',
    URI => object,        # 'http://www.soaplite.com/obj' => My::Class->new,
  })

C<URI> is checked before C<SOAPAction>. You may use both the C<dispatch_to()>
and C<dispatch_with()> methods in the same server, but note that
C<dispatch_with()> has a higher order of precedence. C<dispatch_to()> will be
checked only after C<URI> and C<SOAPAction> has been checked.

See also:
L<EXAMPLE APACHE::REGISTRY USAGE|SOAP::Transport/"EXAMPLE APACHE::REGISTRY USAGE">,
L</"SECURITY">

=head2 COMPRESSION

C<SOAP::Lite> provides you option to enable transparent compression over the
wire. Compression can be enabled by specifying a threshold value (in the form
of kilobytes) for compression on both the client and server sides:

I<Note: Compression currently only works for HTTP based servers and clients.>

B<Client Code>

  print SOAP::Lite
    ->uri('http://localhost/My/Parameters')
    ->proxy('http://localhost/', options => {compress_threshold => 10000})
    ->echo(1 x 10000)
    ->result;

B<Server Code>

  my $server = SOAP::Transport::HTTP::CGI
    ->dispatch_to('My::Parameters')
    ->options({compress_threshold => 10000})
    ->handle;

For more information see L<COMPRESSION|SOAP::Transport/"COMPRESSION"> in
L<HTTP::Transport>.

=head1 SECURITY

For security reasons, the exisiting path for Perl modules (C<@INC>) will be
disabled once you have chosen dynamic deployment and specified your own
C<PATH/>. If you wish to access other modules in your included package you
have several options:

=over 4

=item 1

Switch to static linking:

   use MODULE;
   $server->dispatch_to('MODULE');

Which can also be useful when you want to import something specific from the
deployed modules:

   use MODULE qw(import_list);

=item 2

Change C<use> to C<require>. The path is only unavailable during the
initialization phase. It is available once more during execution. Therefore,
if you utilize C<require> somewhere in your package, it will work.

=item 3

Wrap C<use> in an C<eval> block:

   eval 'use MODULE qw(import_list)'; die if $@;

=item 4

Set your include path in your package and then specify C<use>. Don't forget to
put C<@INC> in a C<BEGIN{}> block or it won't work. For example,

   BEGIN { @INC = qw(my_directory); use MODULE }

=back

=head1 INTEROPERABILITY

=head2 Microsoft .NET client with SOAP::Lite Server

In order to use a .NET client with a SOAP::Lite server, be sure you use fully
qualified names for your return values. For example:

  return SOAP::Data->name('myname')
                   ->type('string')
                   ->uri($MY_NAMESPACE)
                   ->value($output);

In addition see comment about default incoding in .NET Web Services below.

=head2 SOAP::Lite client with a .NET server

If experiencing problems when using a SOAP::Lite client to call a .NET Web
service, it is recommended you check, or adhere to all of the following
recommendations:

=over 4

=item Declare a proper soapAction in your call

For example, use
C<on_action( sub { 'http://www.myuri.com/WebService.aspx#someMethod'; } )>.

=item Disable charset definition in Content-type header

Some users have said that Microsoft .NET prefers the value of
the Content-type header to be a mimetype exclusively, but SOAP::Lite specifies
a character set in addition to the mimetype. This results in an error similar
to:

  Server found request content type to be 'text/xml; charset=utf-8',
  but expected 'text/xml'

To turn off this behavior specify use the following code:

  use SOAP::Lite;
  $SOAP::Constants::DO_NOT_USE_CHARSET = 1;
  # The rest of your code

=item Use fully qualified name for method parameters

For example, the following code is preferred:

  SOAP::Data->name(Query  => 'biztalk')
            ->uri('http://tempuri.org/')

As opposed to:

  SOAP::Data->name('Query'  => 'biztalk')

=item Place method in default namespace

For example, the following code is preferred:

  my $method = SOAP::Data->name('add')
                         ->attr({xmlns => 'http://tempuri.org/'});
  my @rc = $soap->call($method => @parms)->result;

As opposed to:

  my @rc = $soap->call(add => @parms)->result;
  # -- OR --
  my @rc = $soap->add(@parms)->result;

=item Disable use of explicit namespace prefixes

Some user's have reported that .NET will simply not parse messages that use
namespace prefixes on anything but SOAP elements themselves. For example, the
following XML would not be parsed:

  <SOAP-ENV:Envelope ...attributes skipped>
    <SOAP-ENV:Body>
      <namesp1:mymethod xmlns:namesp1="urn:MyURI" />
    </SOAP-ENV:Body>
  </SOAP-ENV:Envelope>

SOAP::Lite allows users to disable the use of explicit namespaces through the
C<use_prefix()> method. For example, the following code:

  $som = SOAP::Lite->uri('urn:MyURI')
                   ->proxy($HOST)
                   ->use_prefix(0)
                   ->myMethod();

Will result in the following XML, which is more pallatable by .NET:

  <SOAP-ENV:Envelope ...attributes skipped>
    <SOAP-ENV:Body>
      <mymethod xmlns="urn:MyURI" />
    </SOAP-ENV:Body>
  </SOAP-ENV:Envelope>

=item Modify your .NET server, if possible

Stefan Pharies <stefanph@microsoft.com>:

SOAP::Lite uses the SOAP encoding (section 5 of the soap 1.1 spec), and
the default for .NET Web Services is to use a literal encoding. So
elements in the request are unqualified, but your service expects them to
be qualified. .Net Web Services has a way for you to change the expected
message format, which should allow you to get your interop working.
At the top of your class in the asmx, add this attribute (for Beta 1):

  [SoapService(Style=SoapServiceStyle.RPC)]

Another source said it might be this attribute (for Beta 2):

  [SoapRpcService]

Full Web Service text may look like:

  <%@ WebService Language="C#" Class="Test" %>
  using System;
  using System.Web.Services;
  using System.Xml.Serialization;

  [SoapService(Style=SoapServiceStyle.RPC)]
  public class Test : WebService {
    [WebMethod]
    public int add(int a, int b) {
      return a + b;
    }
  }

Another example from Kirill Gavrylyuk <kirillg@microsoft.com>:

"You can insert [SoapRpcService()] attribute either on your class or on
operation level".

  <%@ WebService Language=CS class="DataType.StringTest"%>

  namespace DataType {

    using System;
    using System.Web.Services;
    using System.Web.Services.Protocols;
    using System.Web.Services.Description;

   [SoapRpcService()]
   public class StringTest: WebService {
     [WebMethod]
     [SoapRpcMethod()]
     public string RetString(string x) {
       return(x);
     }
   }
 }

Example from Yann Christensen <yannc@microsoft.com>:

  using System;
  using System.Web.Services;
  using System.Web.Services.Protocols;

  namespace Currency {
    [WebService(Namespace="http://www.yourdomain.com/example")]
    [SoapRpcService]
    public class Exchange {
      [WebMethod]
      public double getRate(String country, String country2) {
        return 122.69;
      }
    }
  }

=back

Special thanks goes to the following people for providing the above
description and details on .NET interoperability issues:

Petr Janata <petr.janata@i.cz>,

Stefan Pharies <stefanph@microsoft.com>,

Brian Jepson <bjepson@jepstone.net>, and others

=head1 TROUBLESHOOTING

=over 4

=item SOAP::Lite serializes "18373" as an integer, but I want it to be a string!

SOAP::Lite guesses datatypes from the content provided, using a set of
common-sense rules. These rules are not 100% reliable, though they fit for
most data.

You may force the type by passing a SOAP::Data object with a type specified:

 my $proxy = SOAP::Lite->proxy('http://www.example.org/soapservice');
 my $som = $proxy->myMethod(
     SOAP::Data->name('foo')->value(12345)->type('string')
 );

You may also change the precedence of the type-guessing rules. Note that this
means fiddling with SOAP::Lite's internals - this may not work as
expected in future versions.

The example above forces everything to be encoded as string (this is because
the string test is normally last and allways returns true):

  my @list = qw(-1 45 foo bar 3838);
  my $proxy = SOAP::Lite->uri($uri)->proxy($proxyUrl);
  $proxy->serializer->typelookup->{string}->[0] = 0;
  $proxy->myMethod(\@list);

See L<SOAP::Serializer|SOAP::Serializer/AUTOTYPING> for more details.

=item C<+autodispatch> doesn't work in Perl 5.8

There is a bug in Perl 5.8's C<UNIVERSAL::AUTOLOAD> functionality that
prevents the C<+autodispatch> functionality from working properly. The
workaround is to use C<dispatch_from> instead. Where you might normally do
something like this:

   use Some::Module;
   use SOAP::Lite +autodispatch =>
       uri => 'urn:Foo'
       proxy => 'http://...';

You would do something like this:

   use SOAP::Lite dispatch_from(Some::Module) =>
       uri => 'urn:Foo'
       proxy => 'http://...';

=item Problems using SOAP::Lite's COM Interface

=over

=item Can't call method "server" on undefined value

You probably did not register F<Lite.dll> using C<regsvr32 Lite.dll>

=item Failed to load PerlCtrl Runtime

It is likely that you have install Perl in two different locations and the
location of ActiveState's Perl is not the first instance of Perl specified
in your PATH. To rectify, rename the directory in which the non-ActiveState
Perl is installed, or be sure the path to ActiveState's Perl is specified
prior to any other instance of Perl in your PATH.

=back

=item Dynamic libraries are not found

If you are using the Apache web server, and you are seeing something like the
following in your webserver log file:

  Can't load '/usr/local/lib/perl5/site_perl/.../XML/Parser/Expat/Expat.so'
    for module XML::Parser::Expat: dynamic linker: /usr/local/bin/perl:
    libexpat.so.0 is NEEDED, but object does not exist at
    /usr/local/lib/perl5/.../DynaLoader.pm line 200.

Then try placing the following into your F<httpd.conf> file and see if it
fixes your problem.

 <IfModule mod_env.c>
     PassEnv LD_LIBRARY_PATH
 </IfModule>

=item SOAP client reports "500 unexpected EOF before status line seen

See L</"Apache is crashing with segfaults">

=item Apache is crashing with segfaults

Using C<SOAP::Lite> (or L<XML::Parser::Expat>) in combination with mod_perl
causes random segmentation faults in httpd processes. To fix, try configuring
Apache with the following:

 RULE_EXPAT=no

If you are using Apache 1.3.20 and later, try configuring Apache with the
following option:

 ./configure --disable-rule=EXPAT

See http://archive.covalent.net/modperl/2000/04/0185.xml for more details and
lot of thanks to Robert Barta <rho@bigpond.net.au> for explaining this weird
behavior.

If this doesn't address the problem, you may wish to try C<-Uusemymalloc>,
or a similar option in order to instruct Perl to use the system's own C<malloc>.

Thanks to Tim Bunce <Tim.Bunce@pobox.com>.

=item CGI scripts do not work under Microsoft Internet Information Server (IIS)

CGI scripts may not work under IIS unless scripts use the C<.pl> extension,
opposed to C<.cgi>.

=item Java SAX parser unable to parse message composed by SOAP::Lite

In some cases SOAP messages created by C<SOAP::Lite> may not be parsed
properly by a SAX2/Java XML parser. This is due to a known bug in
C<org.xml.sax.helpers.ParserAdapter>. This bug manifests itself when an
attribute in an XML element occurs prior to the XML namespace declaration on
which it depends. However, according to the XML specification, the order of
these attributes is not significant.

http://www.megginson.com/SAX/index.html

Thanks to Steve Alpert (Steve_Alpert@idx.com) for pointing on it.

=back

=head1 PERFORMANCE

=over 4

=item Processing of XML encoded fragments

C<SOAP::Lite> is based on L<XML::Parser> which is basically wrapper around
James Clark's expat parser. Expat's behavior for parsing XML encoded string
can affect processing messages that have lot of encoded entities, like XML
fragments, encoded as strings. Providing low-level details, parser will call
char() callback for every portion of processed stream, but individually for
every processed entity or newline. It can lead to lot of calls and additional
memory manager expenses even for small messages. By contrast, XML messages
which are encoded as base64Binary, don't have this problem and difference in
processing time can be significant. For XML encoded string that has about 20
lines and 30 tags, number of call could be about 100 instead of one for
the same string encoded as base64Binary.

Since it is parser's feature there is NO fix for this behavior (let me know
if you find one), especially because you need to parse message you already
got (and you cannot control content of this message), however, if your are
in charge for both ends of processing you can switch encoding to base64 on
sender's side. It will definitely work with SOAP::Lite and it B<may> work with
other toolkits/implementations also, but obviously I cannot guarantee that.

If you want to encode specific string as base64, just do
C<< SOAP::Data->type(base64 => $string) >> either on client or on server
side. If you want change behavior for specific instance of SOAP::Lite, you
may subclass C<SOAP::Serializer>, override C<as_string()> method that is
responsible for string encoding (take a look into C<as_base64Binary()>) and
specify B<new> serializer class for your SOAP::Lite object with:

  my $soap = new SOAP::Lite
    serializer => My::Serializer->new,
    ..... other parameters

or on server side:

  my $server = new SOAP::Transport::HTTP::Daemon # or any other server
    serializer => My::Serializer->new,
    ..... other parameters

If you want to change this behavior for B<all> instances of SOAP::Lite, just
substitute C<as_string()> method with C<as_base64Binary()> somewhere in your
code B<after> C<use SOAP::Lite> and B<before> actual processing/sending:

  *SOAP::Serializer::as_string = \&SOAP::XMLSchema2001::Serializer::as_base64Binary;

Be warned that last two methods will affect B<all> strings and convert them
into base64 encoded. It doesn't make any difference for SOAP::Lite, but it
B<may> make a difference for other toolkits.

=back

=head1 BUGS AND LIMITATIONS

=over 4

=item *

No support for multidimensional, partially transmitted and sparse arrays
(however arrays of arrays are supported, as well as any other data structures,
and you can add your own implementation with SOAP::Data).

=item *

Limited support for WSDL schema.

=item *

XML::Parser::Lite relies on Unicode support in Perl and doesn't do entity decoding.

=item *

Limited support for mustUnderstand and Actor attributes.

=back

=head1 PLATFORM SPECIFICS

=over 4

=item MacOS

Information about XML::Parser for MacPerl could be found here:

http://bumppo.net/lists/macperl-modules/1999/07/msg00047.html

Compiled XML::Parser for MacOS could be found here:

http://www.perl.com/CPAN-local/authors/id/A/AS/ASANDSTRM/XML-Parser-2.27-bin-1-MacOS.tgz

=back

=head1 RELATED MODULES

=head2 Transport Modules

SOAP::Lite allows to add support for additional transport protocols, or
server handlers, via separate modules implementing the SOAP::Transport::* 
interface. The following modules are available from CPAN:

=over 

=item * SOAP-Transport-HTTP-Nginx

L<SOAP::Transport::HTTP::Nginx|SOAP::Transport::HTTP::Nginx> provides a transport module for nginx (<http://nginx.net/>)

=back

=head1 AVAILABILITY

You can download the latest version SOAP::Lite for Unix or SOAP::Lite for
Win32 from the following sources:

 * CPAN:                http://search.cpan.org/search?dist=SOAP-Lite
 * Sourceforge:         http://sourceforge.net/projects/soaplite/

PPM packages are also available from sourceforge.

You are welcome to send e-mail to the maintainers of SOAP::Lite with your
comments, suggestions, bug reports and complaints.

=head1 ACKNOWLEDGEMENTS

Special thanks to Randy J. Ray, author of
I<Programming Web Services with Perl>, who has contributed greatly to the
documentation effort of SOAP::Lite.

Special thanks to O'Reilly publishing which has graciously allowed SOAP::Lite
to republish and redistribute the SOAP::Lite reference manual found in
Appendix B of I<Programming Web Services with Perl>.

And special gratitude to all the developers who have contributed patches,
ideas, time, energy, and help in a million different forms to the development
of this software.

=head1 HACKING

SOAP::Lite's development takes place on sourceforge.net.

There's a subversion repository set up at

 https://soaplite.svn.sourceforge.net/svnroot/soaplite/

=head1 REPORTING BUGS

Please report all suspected SOAP::Lite bugs using Sourceforge. This ensures
proper tracking of the issue and allows you the reporter to know when something
gets fixed.

http://sourceforge.net/tracker/?group_id=66000&atid=513017

=head1 COPYRIGHT

Copyright (C) 2000-2007 Paul Kulchenko. All rights reserved.

Copyright (C) 2007-2008 Martin Kutter

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

This text and all associated documentation for this library is made available
under the Creative Commons Attribution-NoDerivs 2.0 license.
http://creativecommons.org/licenses/by-nd/2.0/

=head1 AUTHORS

Paul Kulchenko (paulclinger@yahoo.com)

Randy J. Ray (rjray@blackperl.com)

Byrne Reese (byrne@majordojo.com)

Martin Kutter (martin.kutter@fen-net.de)

=cut
