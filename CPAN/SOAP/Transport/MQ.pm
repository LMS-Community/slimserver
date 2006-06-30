# ======================================================================
#
# Copyright (C) 2000-2001 Paul Kulchenko (paulclinger@yahoo.com)
# SOAP::Lite is free software; you can redistribute it
# and/or modify it under the same terms as Perl itself.
#
# $Id$
#
# ======================================================================

package SOAP::Transport::MQ;

use strict;
use vars qw($VERSION);
$VERSION = sprintf("%d.%s", map {s/_//g; $_} q$Name: release-0_60-public $ =~ /-(\d+)_([\d_]+)/);

use MQClient::MQSeries; 
use MQSeries::QueueManager;
use MQSeries::Queue;
use MQSeries::Message;

use URI;
use URI::Escape; 
use SOAP::Lite;

# ======================================================================

package URI::mq; # ok, lets do 'mq://' scheme
require URI::_server; require URI::_userpass; 
@URI::mq::ISA=qw(URI::_server URI::_userpass);

  # mq://user@host:port?Channel=A;QueueManager=B;RequestQueue=C;ReplyQueue=D
  # ^^   ^^^^ ^^^^ ^^^^ ^^^^^^^^^ ^^^^^^^^^^^^^^ ^^^^^^^^^^^^^^ ^^^^^^^^^^^^

# ======================================================================

package SOAP::Transport::MQ::Client;

use vars qw(@ISA);
@ISA = qw(SOAP::Client);

use MQSeries qw(:constants);

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

sub BEGIN {
  no strict 'refs';
  for my $method (qw(requestqueue replyqueue)) {
    my $field = '_' . $method;
    *$method = sub {
      my $self = shift->new;
      @_ ? ($self->{$field} = shift, return $self) : return $self->{$field};
    }
  }
}

sub endpoint {
  my $self = shift;

  return $self->SUPER::endpoint unless @_;

  my $endpoint = shift;

  # nothing to do if new endpoint is the same as the current one
  return $self if $self->SUPER::endpoint eq $endpoint;

  my $uri = URI->new($endpoint);
  my %parameters = (%$self, map {URI::Escape::uri_unescape($_)} map {split/=/,$_,2} split /[&;]/, $uri->query || '');

  $ENV{MQSERVER} = sprintf "%s/TCP/%s(%s)", $parameters{Channel}, $uri->host, $uri->port
    if $uri->host;

  my $qmgr = MQSeries::QueueManager->new(QueueManager => $parameters{QueueManager}) ||
    die "Unable to connect to queue manager $parameters{QueueManager}\n";

  $self->requestqueue(MQSeries::Queue->new (
    QueueManager => $qmgr,
    Queue        => $parameters{RequestQueue},
    Mode         => 'output',
  ) || die "Unable to open $parameters{RequestQueue}\n");

  $self->replyqueue(MQSeries::Queue->new (
    QueueManager => $qmgr,
    Queue        => $parameters{ReplyQueue},
    Mode         => 'input',
  ) || die "Unable to open $parameters{ReplyQueue}\n");

  $self->SUPER::endpoint($endpoint);
}

sub send_receive {
  my($self, %parameters) = @_;
  my($envelope, $endpoint) = 
    @parameters{qw(envelope endpoint)};

  $self->endpoint($endpoint ||= $self->endpoint);

  %parameters = (%$self, %parameters);
  my $expiry = $parameters{Expiry} || 60000;

  SOAP::Trace::debug($envelope);

  my $request = MQSeries::Message->new (
    MsgDesc => {Format => MQFMT_STRING, Expiry => $expiry},
    Data => $envelope,
  );

  $self->requestqueue->Put(Message => $request) ||
    die "Unable to put message to queue\n";

  my $reply = MQSeries::Message->new (
    MsgDesc => {CorrelId => $request->MsgDesc('MsgId')},
  );

  my $result = $self->replyqueue->Get (
    Message => $reply,
    Wait => $expiry,
  );

  my $msg = $reply->Data if $result > 0;

  SOAP::Trace::debug($msg);

  my $code = $result > 0 ? undef : 
             $result < 0 ? 'Timeout' : 'Error occured while waiting for response';

  $self->code($code);
  $self->message($code);
  $self->is_success(!defined $code || $code eq '');
  $self->status($code);

  return $msg;
}

# ======================================================================

package SOAP::Transport::MQ::Server;

use Carp ();
use vars qw(@ISA $AUTOLOAD);
@ISA = qw(SOAP::Server);

use MQSeries qw(:constants);

sub new {
  my $self = shift;
    
  unless (ref $self) {
    my $class = ref($self) || $self;
    my $uri = URI->new(shift);
    $self = $class->SUPER::new(@_);

    my %parameters = (%$self, map {URI::Escape::uri_unescape($_)} map {split/=/,$_,2} split /[&;]/, $uri->query || '');

    $ENV{MQSERVER} = sprintf "%s/TCP/%s(%s)", $parameters{Channel}, $uri->host, $uri->port
      if $uri->host;

    my $qmgr = MQSeries::QueueManager->new(QueueManager => $parameters{QueueManager}) ||
      Carp::croak "Unable to connect to queue manager $parameters{QueueManager}";

    $self->requestqueue(MQSeries::Queue->new (
      QueueManager => $qmgr,
      Queue        => $parameters{RequestQueue},
      Mode         => 'input',
    ) || Carp::croak  "Unable to open $parameters{RequestQueue}");

    $self->replyqueue(MQSeries::Queue->new (
      QueueManager => $qmgr,
      Queue        => $parameters{ReplyQueue},
      Mode         => 'output',
    ) || Carp::croak  "Unable to open $parameters{ReplyQueue}");
  }
  return $self;
}

sub BEGIN {
  no strict 'refs';
  for my $method (qw(requestqueue replyqueue)) {
    my $field = '_' . $method;
    *$method = sub {
      my $self = shift->new;
      @_ ? ($self->{$field} = shift, return $self) : return $self->{$field};
    }
  }
}

sub handle {
  my $self = shift->new;

  my $msg = 0;
  while (1) {
    my $request = MQSeries::Message->new;

    # nonblock waiting
    $self->requestqueue->Get (
      Message => $request,
    ) || die "Error occured while waiting for requests\n";

    return $msg if $self->requestqueue->Reason == MQRC_NO_MSG_AVAILABLE;

    my $reply = MQSeries::Message->new (
      MsgDesc => {
        CorrelId => $request->MsgDesc('MsgId'),
        Expiry   => $request->MsgDesc('Expiry'),
      },
      Data => $self->SUPER::handle($request->Data),
    );

    $self->replyqueue->Put (
      Message => $reply,
    ) || die "Unable to put reply message\n";

    $msg++;
  }
}

# ======================================================================

1;

__END__

=head1 NAME

SOAP::Transport::MQ - Server/Client side MQ support for SOAP::Lite

=head1 SYNOPSIS

=over 4

=item Client

  use SOAP::Lite 
    uri => 'http://my.own.site.com/My/Examples',
    proxy => 'mq://server:port?Channel=CHAN1;QueueManager=QM_SOAP;RequestQueue=SOAPREQ1;ReplyQueue=SOAPRESP1',
  ;

  print getStateName(1);

=item Server

  use SOAP::Transport::MQ;

  my $server = SOAP::Transport::MQ::Server
    ->new('mq://server:port?Channel=CHAN1;QueueManager=QM_SOAP;RequestQueue=SOAPREQ1;ReplyQueue=SOAPRESP1')
    # specify list of objects-by-reference here 
    -> objects_by_reference(qw(My::PersistentIterator My::SessionIterator My::Chat))
    # specify path to My/Examples.pm here
    -> dispatch_to('/Your/Path/To/Deployed/Modules', 'Module::Name', 'Module::method')
  ;

  print "Contact to SOAP server\n";
  do { $server->handle } while sleep 1;

=back

=head1 DESCRIPTION

=head1 COPYRIGHT

Copyright (C) 2000-2001 Paul Kulchenko. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Paul Kulchenko (paulclinger@yahoo.com)

=cut
