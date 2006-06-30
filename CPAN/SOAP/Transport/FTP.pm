# ======================================================================
#
# Copyright (C) 2000-2001 Paul Kulchenko (paulclinger@yahoo.com)
# SOAP::Lite is free software; you can redistribute it
# and/or modify it under the same terms as Perl itself.
#
# $Id$
#
# ======================================================================

package SOAP::Transport::FTP;

use strict;
use vars qw($VERSION);
$VERSION = sprintf("%d.%s", map {s/_//g; $_} q$Name: release-0_60-public $ =~ /-(\d+)_([\d_]+)/);

use Net::FTP;
use IO::File;
use URI; 

# ======================================================================

package SOAP::Transport::FTP::Client;

use vars qw(@ISA);
@ISA = qw(SOAP::Client);

sub new { 
  my $self = shift;
  my $class = ref($self) || $self;

  unless (ref $self) {
    my $class = ref($self) || $self;
    my(@params, @methods);
    while (@_) { $class->can($_[0]) ? push(@methods, shift() => shift) : push(@params, shift) }
    $self = bless {@params} => $class;
    while (@methods) { my($method, $params) = splice(@methods,0,2);
      $self->$method(ref $params eq 'ARRAY' ? @$params : $params) 
    }
  }
  return $self;
}

sub send_receive {
  my($self, %parameters) = @_;
  my($envelope, $endpoint, $action) = 
    @parameters{qw(envelope endpoint action)};

  $endpoint ||= $self->endpoint; # ftp://login:password@ftp.something/dir/file

  my $uri = URI->new($endpoint);
  my($server, $auth) = reverse split /@/, $uri->authority;
  my $dir = substr($uri->path, 1, rindex($uri->path, '/'));
  my $file = substr($uri->path, rindex($uri->path, '/')+1);

  eval {
    my $ftp = Net::FTP->new($server, %$self) or die "Can't connect to $server: $@\n";
    $ftp->login(split /:/, $auth)            or die "Couldn't login\n";
    $dir and ($ftp->cwd($dir) or
              $ftp->mkdir($dir, 'recurse') and $ftp->cwd($dir) or die "Couldn't change directory to '$dir'\n");
  
    my $FH = IO::File->new_tmpfile; print $FH $envelope; $FH->flush; $FH->seek(0,0);
    $ftp->put($FH => $file)                  or die "Couldn't put file '$file'\n";
    $ftp->quit;
  };

  (my $code = $@) =~ s/\n$//;

  $self->code($code);
  $self->message($code);
  $self->is_success(!defined $code || $code eq '');
  $self->status($code);

  return;
}

# ======================================================================

1;

__END__

=head1 NAME

SOAP::Transport::FTP - Client side FTP support for SOAP::Lite

=head1 SYNOPSIS

  use SOAP::Lite 
    uri => 'http://my.own.site.com/My/Examples',
    proxy => 'ftp://login:password@ftp.somewhere.com/relative/path/to/file.xml', # ftp server
    # proxy => 'ftp://login:password@ftp.somewhere.com//absolute/path/to/file.xml', # ftp server
  ;

  print getStateName(1);

=head1 DESCRIPTION

=head1 COPYRIGHT

Copyright (C) 2000-2001 Paul Kulchenko. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Paul Kulchenko (paulclinger@yahoo.com)

=cut
