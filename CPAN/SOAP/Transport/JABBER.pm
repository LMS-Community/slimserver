# ======================================================================
#
# Copyright (C) 2000-2001 Paul Kulchenko (paulclinger@yahoo.com)
# SOAP::Lite is free software; you can redistribute it
# and/or modify it under the same terms as Perl itself.
#
# $Id$
#
# ======================================================================

package SOAP::Transport::JABBER;

use strict;
use vars qw($VERSION);
$VERSION = sprintf("%d.%s", map {s/_//g; $_} q$Name: release-0_60-public $ =~ /-(\d+)_([\d_]+)/);

use Net::Jabber 1.0021 qw(Client); 
use URI::Escape; 
use URI;
use SOAP::Lite;

my $NAMESPACE = "http://namespaces.soaplite.com/transport/jabber";

{ local $^W; 
  # fix problem with printData in 1.0021
  *Net::Jabber::printData = sub {'nothing'} if Net::Jabber->VERSION == 1.0021;

  # fix problem with Unicode encoding in EscapeXML. Jabber ALWAYS convert latin to utf8
  *Net::Jabber::EscapeXML = *Net::Jabber::EscapeXML = # that's Jabber 1.0021
  *XML::Stream::EscapeXML = *XML::Stream::EscapeXML = # that's Jabber 1.0022
    \&SOAP::Utils::encode_data; 

  # There is also an error in XML::Stream::UnescapeXML 1.12, but
  # we can't do anything there, except hack it also :(
}

# ======================================================================

package URI::jabber; # ok, lets do 'jabber://' scheme
require URI::_server; require URI::_userpass; 
@URI::jabber::ISA=qw(URI::_server URI::_userpass);

  # jabber://soaplite_client:soapliteclient@jabber.org:5222/soaplite_server@jabber.org/Home
  # ^^^^^^   ^^^^^^^^^^^^^^^ ^^^^^^^^^^^^^^ ^^^^^^^^^^ ^^^^ ^^^^^^^^^^^^^^^^^^^^^^^^^^ ^^^^

# ======================================================================

package SOAP::Transport::JABBER::Query;

sub new {
  my $proto = shift;
  bless {} => ref($proto) || $proto;
}

sub SetPayload {
  shift; Net::Jabber::SetXMLData("single",shift->{QUERY},"payload",shift,{});
}

sub GetPayload {
  shift; Net::Jabber::GetXMLData("value",shift->{QUERY},"payload","");
}

# ======================================================================

package SOAP::Transport::JABBER::Client;

use vars qw(@ISA);
@ISA = qw(SOAP::Client Net::Jabber::Client);

sub DESTROY { SOAP::Trace::objects('()') }

sub new { 
  my $self = shift;

  unless (ref $self) {
    my $class = ref($self) || $self;
    my(@params, @methods);
    while (@_) { $class->can($_[0]) ? push(@methods, shift() => shift) : push(@params, shift) }
    $self = $class->SUPER::new(@params);
    while (@methods) { my($method, $params) = splice(@methods,0,2);
      $self->$method(ref $params eq 'ARRAY' ? @$params : $params) 
    }
    SOAP::Trace::objects('()');
  }
  return $self;
}

sub endpoint {
  my $self = shift;

  return $self->SUPER::endpoint unless @_;

  my $endpoint = shift;

  # nothing to do if new endpoint is the same as current one
  return $self if $self->SUPER::endpoint && $self->SUPER::endpoint eq $endpoint;

  my $uri = URI->new($endpoint);
  my($undef, $to, $resource) = split m!/!, $uri->path, 3;
  $self->Connect(
    hostname => $uri->host, 
    port => $uri->port,
  ) or Carp::croak "Can't connect to @{[$uri->host_port]}: $!";

  my @result = $self->AuthSend(
    username => $uri->user, 
    password => $uri->password,
    resource => 'soapliteClient',
  );
  $result[0] eq "ok" or Carp::croak "Can't authenticate to @{[$uri->host_port]}: @result";

  $self->AddDelegate(
    namespace  => $NAMESPACE,
    parent     => 'Net::Jabber::Query',
    parenttype => 'query',
    delegate   => 'SOAP::Transport::JABBER::Query',
  );

  # Get roster and announce presence
  $self->RosterGet();
  $self->PresenceSend();

  $self->SUPER::endpoint($endpoint);
}

sub send_receive {
  my($self, %parameters) = @_;
  my($envelope, $endpoint, $encoding) = 
    @parameters{qw(envelope endpoint encoding)};

  $self->endpoint($endpoint ||= $self->endpoint);

  my($undef, $to, $resource) = split m!/!, URI->new($endpoint)->path, 3;

  # Create a Jabber info/query message
  my $iq = new Net::Jabber::IQ();
  $iq->SetIQ(
    type => 'set',
    to   => join '/', $to => $resource || 'soapliteServer',
  );
  my $query = $iq->NewQuery($NAMESPACE);
  $query->SetPayload($envelope);

  SOAP::Trace::debug($envelope);

  my $iq_rcvd = $self->SendAndReceiveWithID($iq);
  my($query_rcvd) = $iq_rcvd->GetQuery($NAMESPACE) if $iq_rcvd; # expect only one
  my $msg = $query_rcvd->GetPayload() if $query_rcvd;

  SOAP::Trace::debug($msg);

  my $code = $self->GetErrorCode();

  $self->code($code);
  $self->message($code);
  $self->is_success(!defined $code || $code eq '');
  $self->status($code);

  return $msg;
}

# ======================================================================

package SOAP::Transport::JABBER::Server;

use Carp ();
use vars qw(@ISA $AUTOLOAD);
@ISA = qw(SOAP::Server);

sub new {
  my $self = shift;
    
  unless (ref $self) {
    my $class = ref($self) || $self;
    my $uri = URI->new(shift);
    $self = $class->SUPER::new(@_);

    $self->{_jabberserver} = Net::Jabber::Client->new;
    $self->{_jabberserver}->Connect(
      hostname      => $uri->host,
      port          => $uri->port,
    ) or Carp::croak "Can't connect to @{[$uri->host_port]}: $!";

    my($undef, $resource) = split m!/!, $uri->path, 2;
    my @result = $self->AuthSend(
      username => $uri->user, 
      password => $uri->password,
      resource => $resource || 'soapliteServer',
    );
    $result[0] eq "ok" or Carp::croak "Can't authenticate to @{[$uri->host_port]}: @result";

    $self->{_jabberserver}->SetCallBacks(
      iq => sub {
        shift;
        my $iq = new Net::Jabber::IQ(@_);

        my($query) = $iq->GetQuery($NAMESPACE); # expect only one
        my $request = $query->GetPayload();

        SOAP::Trace::debug($request);

        # Set up response
        my $reply = $iq->Reply;
        my $x = $reply->NewQuery($NAMESPACE);

        my $response = $self->SUPER::handle($request);
        $x->SetPayload($response);

        # Send response
        $self->{_jabberserver}->Send($reply);
      }
    );

    $self->AddDelegate(
      namespace  => $NAMESPACE,
      parent     => 'Net::Jabber::Query',
      parenttype => 'query',
      delegate   => 'SOAP::Transport::JABBER::Query',
    );
  
    $self->RosterGet();
    $self->PresenceSend();
  }
  return $self;
}

sub AUTOLOAD {
  my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
  return if $method eq 'DESTROY';

  no strict 'refs';
  *$AUTOLOAD = sub { shift->{_jabberserver}->$method(@_) };
  goto &$AUTOLOAD;
}

sub handle {
  shift->Process();
}

# ======================================================================

1;

__END__

=head1 NAME

SOAP::Transport::JABBER - Server/Client side JABBER support for SOAP::Lite

=head1 SYNOPSIS

=over 4

=item Client

  use SOAP::Lite 
    uri => 'http://my.own.site.com/My/Examples',
    proxy => 'jabber://username:password@jabber.org:5222/soaplite_server@jabber.org/',
    #         proto    username passwd   server     port destination                resource (optional)
  ;

  print getStateName(1);

=item Server

  use SOAP::Transport::JABBER;

  my $server = SOAP::Transport::JABBER::Server
    -> new('jabber://username:password@jabber.org:5222')
    # specify list of objects-by-reference here 
    -> objects_by_reference(qw(My::PersistentIterator My::SessionIterator My::Chat))
    # specify path to My/Examples.pm here
    -> dispatch_to('/Your/Path/To/Deployed/Modules', 'Module::Name', 'Module::method')
  ;

  print "Contact to SOAP server\n";
  do { $server->handle } while sleep 10;

=back

=head1 DESCRIPTION

=head1 COPYRIGHT

Copyright (C) 2000-2001 Paul Kulchenko. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Paul Kulchenko (paulclinger@yahoo.com)

=cut
