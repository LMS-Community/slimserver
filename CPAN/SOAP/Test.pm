# ======================================================================
#
# Copyright (C) 2000-2001 Paul Kulchenko (paulclinger@yahoo.com)
# SOAP::Lite is free software; you can redistribute it
# and/or modify it under the same terms as Perl itself.
#
# $Id$
#
# ======================================================================

package SOAP::Test;

use 5.004;
use vars qw($VERSION $TIMEOUT);
$VERSION = sprintf("%d.%s", map {s/_//g; $_} q$Name: release-0_60-public $ =~ /-(\d+)_([\d_]+)/);

$TIMEOUT = 5;

# ======================================================================

package My::PingPong; # we'll use this package in our tests

sub new { 
  my $self = shift;
  my $class = ref($self) || $self;
  bless {_num=>shift} => $class;
}

sub next {
  my $self = shift;
  $self->{_num}++;
}

sub value {
  my $self = shift;
  $self->{_num};
}

# ======================================================================

package SOAP::Test::Server;

use strict;
use Test;
use SOAP::Lite;

sub run_for {
  my $proxy = shift or die "Proxy/endpoint is not specified";

  # ------------------------------------------------------
  my $s = SOAP::Lite->uri('http://something/somewhere')->proxy($proxy)->on_fault(sub{});
  eval { $s->transport->timeout($SOAP::Test::TIMEOUT) };
  my $r = $s->test_connection;

  unless (defined $r && defined $r->envelope) {
    print "1..0 # Skip: ", $s->transport->status, "\n";
    exit;
  }
  # ------------------------------------------------------

  plan tests => 53;

  eval q!use SOAP::Lite on_fault => sub{ref $_[1] ? $_[1] : new SOAP::SOM}; 1! or die;

  print STDERR "Perl SOAP server test(s)...\n";

  $s = SOAP::Lite
    -> uri('urn:/My/Examples')
      -> proxy($proxy);

  ok($s->getStateName(1)->result eq 'Alabama'); 
  ok($s->getStateNames(1,4,6,13)->result =~ /^Alabama\s+Arkansas\s+Colorado\s+Illinois\s*$/); 

  $r = $s->getStateList([1,2,3,4])->result;
  ok(ref $r && $r->[0] eq 'Alabama'); 

  $r = $s->getStateStruct({item1 => 1, item2 => 4})->result;
  ok(ref $r && $r->{item2} eq 'Arkansas'); 

  {
    my $autoresult = $s->autoresult;
    $s->autoresult(1);
    ok($s->getStateName(1) eq 'Alabama');
    $s->autoresult($autoresult);
  }

  print STDERR "Autobinding of output parameters test(s)...\n";

  $s->uri('urn:/My/Parameters');
  my $param1 = 10;
  my $param2 = SOAP::Data->name('myparam' => 12);
  my $result = $s->autobind($param1, $param2)->result;
  ok($result == $param1 && $param2->value == 24); 

  print STDERR "Header manipulation test(s)...\n";
  $a = $s->addheader(2, SOAP::Header->name(my => 123)); 
  ok(ref $a->header && $a->header->{my} eq '123123'); 
  ok($a->headers eq '123123'); 

  print STDERR "Echo untyped data test(s)...\n";
  $a = $s->echotwo(11, 12);
  ok($a->result == 11); 

  print STDERR "mustUnderstand test(s)...\n";
  $s->echo(SOAP::Header->name(somethingelse => 123)
                       ->mustUnderstand(1));
  ok($s->call->faultstring =~ /[Hh]eader has mustUnderstand attribute/);

  if ($proxy =~ /^http/) {
    ok($s->transport->status =~ /^500/);
  } else {
    skip('No Status checks for non http protocols on server side' => undef);
  }

  $s->echo(SOAP::Header->name(somethingelse => 123)
                       ->mustUnderstand(1)
                       ->actor('http://notme/'));
  ok(!defined $s->call->fault);

  print STDERR "dispatch_from test(s)...\n";
  eval "use SOAP::Lite
    uri => 'http://my.own.site.com/My/Examples',
    dispatch_from => ['A', 'B'],
    proxy => '$proxy',
  ; 1" or die;

  eval { C->c };
  ok($@ =~ /Can't locate object method "c"/);

  eval { A->a };
  ok(!$@ && SOAP::Lite->self->call->faultstring =~ /Failed to access class \(A\)/);

  eval "use SOAP::Lite
    dispatch_from => 'A',
    uri => 'http://my.own.site.com/My/Examples',
    proxy => '$proxy',
  ; 1" or die;

  eval { A->a };
  ok(!$@ && SOAP::Lite->self->call->faultstring =~ /Failed to access class \(A\)/);

  print STDERR "Object autobinding and SOAP:: prefix test(s)...\n";

  eval "use SOAP::Lite +autodispatch =>
    uri => 'urn:', proxy => '$proxy'; 1" or die;

  ok(SOAP::Lite->autodispatched);

  eval { SOAP->new(1) };
  ok($@ =~ /^URI is not specified/);

  eval "use SOAP::Lite +autodispatch =>
    uri => 'urn:/A/B', proxy => '$proxy'; 1" or die;

  # should call My::PingPong, not A::B
  my $p = My::PingPong->SOAP::new(10);
  ok(ref $p && $p->SOAP::next+1 == $p->value);

  # forget everything
  SOAP::Lite->self(undef); 

  $s = SOAP::Lite
    -> uri('urn:/My/PingPong')                
    -> proxy($proxy)
  ;

  # should return object EXACTLY as after My::PingPong->SOAP::new(10)
  $p = $s->SOAP::new(10); 
  ok(ref $p && $s->SOAP::next($p)+1 == $p->value);

  print STDERR "VersionMismatch test(s)...\n";

  {
    local $SOAP::Constants::NS_ENV = 'http://schemas.xmlsoap.org/new/envelope/';
    my $s = SOAP::Lite
      -> uri('http://my.own.site.com/My/Examples')                
      -> proxy($proxy)
      -> on_fault(sub{})
    ;
    $r = $s->dosomething;
    ok(ref $r && $r->faultcode =~ /:VersionMismatch/);
  }

  print STDERR "Objects-by-reference test(s)...\n";

  eval "use SOAP::Lite +autodispatch =>
    uri => 'urn:', proxy => '$proxy'; 1" or die;

  print STDERR "Session iterator\n";
  $r = My::SessionIterator->new(10); 
  if (!ref $r || exists $r->{id}) {
    ok(ref $r && $r->next && $r->next == 11);
  } else {
    skip('No persistent objects (o-b-r) supported on server side' => undef);
  }

  print STDERR "Persistent iterator\n";
  $r = My::PersistentIterator->new(10); 
  if (!ref $r || exists $r->{id}) {
    my $first = ($r->next, $r->next) if ref $r;   

    $r = My::PersistentIterator->new(10);
    ok(ref $r && $r->next && $r->next == $first+2);
  } else {
    skip('No persistent objects (o-b-r) supported on server side' => undef);
  }

  { local $^W; # disable warnings about deprecated AUTOLOADing for nonmethods
    print STDERR "Parameters-by-name test(s)...\n";
    print STDERR "You can see warning about AUTOLOAD for non-method...\n" if $^W;

    eval "use SOAP::Lite +autodispatch => 
      uri => 'http://my.own.site.com/My/Parameters', proxy => '$proxy'; 1" or die;

    my @parameters = (
      SOAP::Data->name(b => 222), 
      SOAP::Data->name(c => 333), 
      SOAP::Data->name(a => 111)
    );

    # switch to 'main' package, because nonqualified methods should be there
    ok(main::byname(@parameters) eq "a=111, b=222, c=333");

    ok(main::bynameororder(@parameters) eq "a=111, b=222, c=333");

    ok(main::bynameororder(111, 222, 333) eq "a=111, b=222, c=333");

    print STDERR "Function call test(s)...\n";
    print STDERR "You can see warning about AUTOLOAD for non-method...\n" if $^W;
    ok(main::echo(11) == 11);
  }

  print STDERR "SOAPAction test(s)...\n";
  if ($proxy =~ /^tcp:/) {
    for (1..2) {skip('No SOAPAction checks for tcp: protocol on server side' => undef)}
  } else {
    my $s = SOAP::Lite
      -> uri('http://my.own.site.com/My/Examples')                
      -> proxy($proxy)
      -> on_action(sub{'""'})
    ;
    ok($s->getStateName(1)->result eq 'Alabama'); 

    $s->on_action(sub{'"wrong_SOAPAction_here"'});
    ok($s->getStateName(1)->faultstring =~ /SOAPAction shall match/); 
  }

  print STDERR "UTF8 test(s)...\n";
  if (!eval "pack('U*', 0)") {
    for (1) {skip('No UTF8 test. No support for pack("U*") modifier' => undef)}
  } else {
    $s = SOAP::Lite
      -> uri('http://my.own.site.com/My/Parameters')                
      -> proxy($proxy);

     my $latin1 = 'привет';
     my $utf8 = pack('U*', unpack('C*', $latin1));
     my $result = $s->echo(SOAP::Data->type(string => $utf8))->result;

     ok(pack('U*', unpack('C*', $result)) eq $utf8                       # should work where XML::Parser marks resulting strings as UTF-8
     || join('', unpack('C*', $result)) eq join('', unpack('C*', $utf8)) # should work where it doesn't
     );
  }

  {
    my $on_fault_was_called = 0;
    print STDERR "Die in server method test(s)...\n";
    my $s = SOAP::Lite
      -> uri('http://my.own.site.com/My/Parameters')                
      -> proxy($proxy)
      -> on_fault(sub{$on_fault_was_called++;return})
    ;
    ok($s->die_simply()->faultstring =~ /Something bad/);
    ok($on_fault_was_called > 0);
    my $detail = $s->die_with_object()->dataof(SOAP::SOM::faultdetail . '/[1]');
    ok($on_fault_was_called > 1);
    ok(ref $detail && $detail->name =~ /(^|:)something$/);

    # get Fault as hash of subelements
    my $fault = $s->die_with_fault()->fault;
    ok($fault->{faultcode} =~ ':Server.Custom');
    ok($fault->{faultstring} eq 'Died in server method');
    ok(ref $fault->{detail}->{BadError} eq 'BadError');
    ok($fault->{faultactor} eq 'http://www.soaplite.com/custom');
  }

  print STDERR "Method with attributes test(s)...\n";

  $s = SOAP::Lite
    -> uri('urn:/My/Examples')                
    -> proxy($proxy)
  ;

  ok($s->call(SOAP::Data->name('getStateName')->attr({xmlns => 'urn:/My/Examples'}), 1)->result eq 'Alabama');

  print STDERR "Call with empty uri test(s)...\n";
  $s = SOAP::Lite
    -> uri('')                
    -> proxy($proxy)
  ;

  ok($s->getStateName(1)->faultstring =~ /Denied access to method \(getStateName\) in class \(main\)/);

  ok($s->call('a:getStateName' => 1)->faultstring =~ /Denied access to method \(getStateName\) in class \(main\)/);

  print STDERR "Number of parameters test(s)...\n";

  $s = SOAP::Lite
    -> uri('http://my.own.site.com/My/Parameters')                
    -> proxy($proxy)
  ;
  { my @all = $s->echo->paramsall; ok(@all == 0) }
  { my @all = $s->echo(1)->paramsall; ok(@all == 1) }
  { my @all = $s->echo((1) x 10)->paramsall; ok(@all == 10) }

  print STDERR "Memory refresh test(s)...\n";

  # Funny test. 
  # Let's forget about ALL settings we did before with 'use SOAP::Lite...'
  SOAP::Lite->self(undef); 
  ok(!defined SOAP::Lite->self);

  print STDERR "Call without uri test(s)...\n";
  $s = SOAP::Lite
    -> proxy($proxy)
  ;

  ok($s->getStateName(1)->faultstring =~ /Denied access to method \(getStateName\) in class \(main\)/);

  print STDERR "Different settings for method and namespace test(s)...\n";

  ok($s->call(SOAP::Data
    ->name('getStateName')
    ->attr({xmlns => 'urn:/My/Examples'}), 1)->result eq 'Alabama');

  ok($s->call(SOAP::Data
    ->name('a:getStateName')
    ->uri('urn:/My/Examples'), 1)->result eq 'Alabama');

  ok($s->call(SOAP::Data
    ->name('getStateName')
    ->uri('urn:/My/Examples'), 1)->result eq 'Alabama');

  ok($s->call(SOAP::Data
    ->name('a:getStateName')
    ->attr({'xmlns:a' => 'urn:/My/Examples'}), 1)->result eq 'Alabama');

  eval { $s->call(SOAP::Data->name('a:getStateName')) };

  ok($@ =~ /Can't find namespace for method \(a:getStateName\)/);

  $s->serializer->namespaces->{'urn:/My/Examples'} = '';

  ok($s->getStateName(1)->result eq 'Alabama');

  eval "use SOAP::Lite 
    uri => 'urn:/My/Examples', proxy => '$proxy'; 1" or die;

  print STDERR "Global settings test(s)...\n";
  $s = new SOAP::Lite;

  ok($s->getStateName(1)->result eq 'Alabama');

  SOAP::Trace->import(transport => 
    sub {$_[0]->content_type('something/wrong') if UNIVERSAL::isa($_[0] => 'HTTP::Request')}
  );

  if ($proxy =~ /^tcp:/) {
    skip('No Content-Type checks for tcp: protocol on server side' => undef);
  } else {
    ok($s->getStateName(1)->faultstring =~ /Content-Type must be/);
  }
}

# ======================================================================

1;

__END__

=head1 NAME

SOAP::Test - Test framework for SOAP::Lite

=head1 SYNOPSIS

  use SOAP::Test;

  SOAP::Test::Server::run_for('http://localhost/cgi-bin/soap.cgi');

=head1 DESCRIPTION

SOAP::Test provides simple framework for testing server implementations.
Specify your address (endpoint) and run provided tests against your server.
See t/1*.t for examples.

=head1 COPYRIGHT

Copyright (C) 2000-2001 Paul Kulchenko. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Paul Kulchenko (paulclinger@yahoo.com)

=cut
