package HTTP::Message;

# $Id: Message.pm,v 1.1 2004/02/21 22:26:08 daniel Exp $

use strict;
use vars qw($VERSION $AUTOLOAD);
$VERSION = sprintf("%d.%02d", q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/);

require HTTP::Headers;
require Carp;

$HTTP::URI_CLASS ||= $ENV{PERL_HTTP_URI_CLASS} || "URI";
eval "require $HTTP::URI_CLASS"; die $@ if $@;



sub new
{
    my($class, $header, $content) = @_;
    if (defined $header) {
	Carp::croak("Bad header argument") unless ref $header;
	$header = $header->clone;
    }
    else {
	$header = HTTP::Headers->new;
    }
    $content = '' unless defined $content;
    bless {
	'_headers' => $header,
	'_content' => $content,
    }, $class;
}


sub clone
{
    my $self  = shift;
    my $clone = HTTP::Message->new($self->{'_headers'}, $self->{'_content'});
    $clone;
}


sub protocol { shift->_elem('_protocol',  @_); }
sub content  { shift->_elem('_content',  @_); }


sub add_content
{
    my $self = shift;
    if (ref($_[0])) {
	$self->{'_content'} .= ${$_[0]};  # for backwards compatability
    }
    else {
	$self->{'_content'} .= $_[0];
    }
}


sub content_ref
{
    my $self = shift;
    \$self->{'_content'};
}


sub as_string
{
    "";  # To be overridden in subclasses
}


sub headers            { shift->{'_headers'};                }
sub headers_as_string  { shift->{'_headers'}->as_string(@_); }


# delegate all other method calls the the _headers object.
sub AUTOLOAD
{
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::')+2);
    return if $method eq "DESTROY";

    # We create the function here so that it will not need to be
    # autoloaded the next time.
    no strict 'refs';
    *$method = eval "sub { shift->{'_headers'}->$method(\@_) }";
    goto &$method;
}


# Private method to access members in %$self
sub _elem
{
    my $self = shift;
    my $elem = shift;
    my $old = $self->{$elem};
    $self->{$elem} = $_[0] if @_;
    return $old;
}


1;


__END__

=head1 NAME

HTTP::Message - HTTP style message base class

=head1 SYNOPSIS

 package HTTP::Request;  # or HTTP::Response
 require HTTP::Message;
 @ISA=qw(HTTP::Message);

=head1 DESCRIPTION

An C<HTTP::Message> object contains some headers and a content body.
The class is abstract, i.e. it only used as a base class for
C<HTTP::Request> and C<HTTP::Response> and should never instantiated
as itself.  The following methods are available:

=over 4

=item $mess->content

=item $mess->content( $content )

The content() method sets the content if an argument is given.  If no
argument is given the content is not touched.  In either case the
previous content is returned.

Note that the content should be a string of bytes.  Strings in perl
can contain characters outside the range of a byte.  The C<Encode>
module can be used to turn such strings into a string of bytes.

=item $mess->add_content( $data )

The add_content() methods appends more data to the end of the current
content buffer.

=item $mess->content_ref

The content_ref() method will return a reference to content buffer string.
It can be more efficient to access the content this way if the content
is huge, and it can even be used for direct manipulation of the content,
for instance:

  ${$res->content_ref} =~ s/\bfoo\b/bar/g;

This example would modify the content buffer in-place.

=item $mess->headers

Returns the embedded HTTP::Headers object.

=item $mess->headers_as_string

=item $mess->headers_as_string( $endl )

Call the as_string() method for the headers in the
message.  This will be the same as

    $mess->headers->as_string

but it will make your program a whole character shorter :-)

=item $mess->protocol

=item $mess->protocol( $proto )

Sets the HTTP protocol used for the message.  The protocol() is a string
like C<HTTP/1.0> or C<HTTP/1.1>.

=item $mess->clone

Returns a copy of the message object.

=back

All methods unknown to C<HTTP::Message> itself are delegated to the
C<HTTP::Headers> object that is part of every message.  This allows
convenient access to these methods.  Refer to L<HTTP::Headers> for
details of these methods:

    $mess->header( $field => $val )
    $mess->push_header( $field => $val )
    $mess->init_header( $field => $val )
    $mess->remove_header( $field )
    $mess->scan( \&doit )

    $mess->date
    $mess->expires
    $mess->if_modified_since
    $mess->if_unmodified_since
    $mess->last_modified
    $mess->content_type
    $mess->content_encoding
    $mess->content_length
    $mess->content_language
    $mess->title
    $mess->user_agent
    $mess->server
    $mess->from
    $mess->referer
    $mess->www_authenticate
    $mess->authorization
    $mess->proxy_authorization
    $mess->authorization_basic
    $mess->proxy_authorization_basic

=head1 COPYRIGHT

Copyright 1995-2001 Gisle Aas.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

