# ======================================================================
#
# Copyright (C) 2000-2001 Paul Kulchenko (paulclinger@yahoo.com)
# SOAP::Lite is free software; you can redistribute it
# and/or modify it under the same terms as Perl itself.
#
# $Id$
#
# ======================================================================

package SOAP::Transport::MAILTO;

use strict;
use vars qw($VERSION);
$VERSION = sprintf("%d.%s", map {s/_//g; $_} q$Name: release-0_60-public $ =~ /-(\d+)_([\d_]+)/);

use MIME::Lite; 
use URI;

# ======================================================================

package SOAP::Transport::MAILTO::Client;

use vars qw(@ISA);
@ISA = qw(SOAP::Client);

sub DESTROY { SOAP::Trace::objects('()') }

sub new { 
  my $self = shift;

  unless (ref $self) {
    my $class = ref($self) || $self;
    my(@params, @methods);
    while (@_) { $class->can($_[0]) ? push(@methods, shift() => shift) : push(@params, shift) }
    $self = bless {@params} => $class;
    while (@methods) { my($method, $params) = splice(@methods,0,2);
      $self->$method(ref $params eq 'ARRAY' ? @$params : $params) 
    }
    SOAP::Trace::objects('()');
  }
  return $self;
}

sub send_receive {
  my($self, %parameters) = @_;
  my($envelope, $endpoint, $action) = 
    @parameters{qw(envelope endpoint action)};

  $endpoint ||= $self->endpoint;
  my $uri = URI->new($endpoint);
  %parameters = (%$self, map {URI::Escape::uri_unescape($_)} map {split/=/,$_,2} split /[&;]/, $uri->query || '');

  my $msg = MIME::Lite->new(
    To         => $uri->to,
    Type       => 'text/xml',
    Encoding   => $parameters{Encoding} || 'base64',
    Data       => $envelope,
    $parameters{From}       ? (From       => $parameters{From}) : (),
    $parameters{'Reply-To'} ? ('Reply-To' => $parameters{'Reply-To'}) : (),
    $parameters{Subject}    ? (Subject    => $parameters{Subject}) : (),
  );
  $msg->replace('X-Mailer' => join '/', 'SOAP::Lite', 'Perl', SOAP::Transport::MAILTO->VERSION);
  $msg->add(SOAPAction => $action);

  SOAP::Trace::transport($msg);
  SOAP::Trace::debug($msg->as_string);
    
  MIME::Lite->send(map {exists $parameters{$_} ? ($_ => $parameters{$_}) : ()} 'smtp', 'sendmail');
  eval { local $SIG{__DIE__}; $MIME::Lite::AUTO_CC = 0; $msg->send };
  (my $code = $@) =~ s/ at .*\n//;

  $self->code($code);
  $self->message($code);
  $self->is_success(!defined $code || $code eq '');
  $self->status($code);

  return;
}

# ======================================================================

1;

=head1 NAME

SOAP::Transport::MAILTO - Client side SMTP/sendmail support for SOAP::Lite

=head1 SYNOPSIS

  use SOAP::Lite;

  SOAP::Lite
    -> uri('http://soaplite.com/My/Examples')                
    -> proxy('mailto:destination.email@address', smtp => 'smtp.server', From => 'your.email', Subject => 'SOAP message')

    # or 
    # -> proxy('mailto:destination.email@address?From=your.email&Subject=SOAP%20message', smtp => 'smtp.server')

    # or if you want to send with sendmail
    # -> proxy('mailto:destination.email@address?From=your.email&Subject=SOAP%20message')

    # or if your sendmail is in undiscoverable place
    # -> proxy('mailto:destination.email@address?From=your.email&Subject=SOAP%20message', sendmail => 'command to run your sendmail')

    -> getStateName(12)
  ;

=head1 DESCRIPTION

=head1 COPYRIGHT

Copyright (C) 2000-2001 Paul Kulchenko. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Paul Kulchenko (paulclinger@yahoo.com)

=cut
