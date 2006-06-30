# ======================================================================
#
# Copyright (C) 2000-2001 Paul Kulchenko (paulclinger@yahoo.com)
# SOAP::Lite is free software; you can redistribute it
# and/or modify it under the same terms as Perl itself.
#
# $Id$
#
# ======================================================================

package SOAP::Transport::TCP;

use strict;
use vars qw($VERSION);
$VERSION = sprintf("%d.%s", map {s/_//g; $_} q$Name: release-0_60-public $ =~ /-(\d+)_([\d_]+)/);

use URI;
use IO::Socket;
use IO::Select;
use IO::SessionData;
use SOAP::Lite;

# ======================================================================

package URI::tcp; # ok, let's do 'tcp://' scheme
require URI::_server; 
@URI::tcp::ISA=qw(URI::_server);

# ======================================================================

package SOAP::Transport::TCP::Client;

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
    # use SSL if there is any parameter with SSL_* in the name
    $self->SSL(1) if !$self->SSL && grep /^SSL_/, keys %$self;
    SOAP::Trace::objects('()');
  }
  return $self;
}

sub SSL {
  my $self = shift->new;
  @_ ? ($self->{_SSL} = shift, return $self) : return $self->{_SSL};
}

sub io_socket_class { shift->SSL ? 'IO::Socket::SSL' : 'IO::Socket::INET' }

sub syswrite {
  my($self, $sock, $data) = @_;

  my $timeout = $sock->timeout;

  my $select = IO::Select->new($sock);

  my $len = length $data;
  while (length $data > 0) {
    return unless $select->can_write($timeout);
    local $SIG{PIPE} = 'IGNORE';
    # added length() to make it work on Mac. Thanks to Robin Fuller <rfuller@broadjump.com>
    my $wc = syswrite($sock, $data, length($data));
    if (defined $wc) {
      substr($data, 0, $wc) = '';
    } elsif (!IO::SessionData::WOULDBLOCK($!)) {
      return;
    }
  }
  return $len;
}

sub sysread {
  my($self, $sock) = @_;

  my $timeout = $sock->timeout;
  my $select = IO::Select->new($sock);

  my $result = '';
  my $data;
  while (1) {
    return unless $select->can_read($timeout);
    my $rc = sysread($sock, $data, 4096);
    if ($rc) {
      $result .= $data;
    } elsif (defined $rc) {
      return $result;
    } elsif (!IO::SessionData::WOULDBLOCK($!)) {
      return;
    }
  }
}

sub send_receive {
  my($self, %parameters) = @_;
  my($envelope, $endpoint, $action) = 
    @parameters{qw(envelope endpoint action)};

  $endpoint ||= $self->endpoint;
  warn "URLs with 'tcp:' scheme are deprecated. Use 'tcp://'. Still continue\n"
    if $endpoint =~ s!^tcp:(//)?!tcp://!i && !$1;
  my $uri = URI->new($endpoint);

  local($^W, $@, $!);
  my $socket = $self->io_socket_class; 
  eval "require $socket" or Carp::croak $@ unless UNIVERSAL::can($socket => 'new');
  my $sock = $socket->new (
    PeerAddr => $uri->host, PeerPort => $uri->port, Proto => $uri->scheme, %$self
  );

  SOAP::Trace::debug($envelope);

  # bytelength hack. See SOAP::Transport::HTTP.pm for details.
  my $bytelength = SOAP::Utils::bytelength($envelope);
  $envelope = pack('C0A*', $envelope) 
    if !$SOAP::Constants::DO_NOT_USE_LWP_LENGTH_HACK && length($envelope) != $bytelength;

  my $result;
  if ($sock) {
    $sock->blocking(0);
    $self->syswrite($sock, $envelope)  and 
     $sock->shutdown(1)                and # stop writing
     $result = $self->sysread($sock);
  }

  SOAP::Trace::debug($result);

  my $code = $@ || $!;

  $self->code($code);
  $self->message($code);
  $self->is_success(!defined $code || $code eq '');
  $self->status($code);

  return $result;
}

# ======================================================================

package SOAP::Transport::TCP::Server;

use IO::SessionSet;

use Carp ();
use vars qw($AUTOLOAD @ISA);
@ISA = qw(SOAP::Server);

sub DESTROY { SOAP::Trace::objects('()') }

sub new { 
  my $self = shift;

  unless (ref $self) {
    my $class = ref($self) || $self;

    my(@params, @methods);
    while (@_) { $class->can($_[0]) ? push(@methods, shift() => shift) : push(@params, shift) }
    $self = $class->SUPER::new(@methods);

    # use SSL if there is any parameter with SSL_* in the name
    $self->SSL(1) if !$self->SSL && grep /^SSL_/, @params;

    my $socket = $self->io_socket_class; 
    eval "require $socket" or Carp::croak $@ unless UNIVERSAL::can($socket => 'new');
    $self->{_socket} = $socket->new(Proto => 'tcp', @params) 
      or Carp::croak "Can't open socket: $!";

    SOAP::Trace::objects('()');
  }
  return $self;
}

sub SSL {
  my $self = shift->new;
  @_ ? ($self->{_SSL} = shift, return $self) : return $self->{_SSL};
}

sub io_socket_class { shift->SSL ? 'IO::Socket::SSL' : 'IO::Socket::INET' }

sub AUTOLOAD {
  my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
  return if $method eq 'DESTROY';

  no strict 'refs';
  *$AUTOLOAD = sub { shift->{_socket}->$method(@_) };
  goto &$AUTOLOAD;
}

sub handle {
  my $self = shift->new;
  my $sock = $self->{_socket};
  my $session_set = IO::SessionSet->new($sock);
  my %data;
  while (1) {
    my @ready = $session_set->wait($sock->timeout);
    for my $session (@ready) {
      my $data;
      if (my $rc = $session->read($data, 4096)) {
        $data{$session} .= $data if $rc > 0;
      } else {
        $session->write($self->SUPER::handle(delete $data{$session}));
        $session->close;
      }
    }
  }
}

# ======================================================================

1;

__END__

=head1 NAME

SOAP::Transport::TCP - Server/Client side TCP support for SOAP::Lite

=head1 SYNOPSIS

  use SOAP::Transport::TCP;

  my $daemon = SOAP::Transport::TCP::Server
    -> new (LocalAddr => 'localhost', LocalPort => 82, Listen => 5, Reuse => 1)
    -> objects_by_reference(qw(My::PersistentIterator My::SessionIterator My::Chat))
    -> dispatch_to('/Your/Path/To/Deployed/Modules', 'Module::Name', 'Module::method') 
  ;
  print "Contact to SOAP server at ", join(':', $daemon->sockhost, $daemon->sockport), "\n";
  $daemon->handle;

=head1 DESCRIPTION

=head1 COPYRIGHT

Copyright (C) 2000-2001 Paul Kulchenko. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Paul Kulchenko (paulclinger@yahoo.com)

=cut
