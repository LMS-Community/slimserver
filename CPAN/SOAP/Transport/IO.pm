# ======================================================================
#
# Copyright (C) 2000-2001 Paul Kulchenko (paulclinger@yahoo.com)
# SOAP::Lite is free software; you can redistribute it
# and/or modify it under the same terms as Perl itself.
#
# $Id$
#
# ======================================================================

package SOAP::Transport::IO;

use strict;
use vars qw($VERSION);
$VERSION = sprintf("%d.%s", map {s/_//g; $_} q$Name: release-0_60-public $ =~ /-(\d+)_([\d_]+)/);

use IO::File;
use SOAP::Lite;

# ======================================================================

package SOAP::Transport::IO::Server;

use strict;
use Carp ();
use vars qw(@ISA);
@ISA = qw(SOAP::Server);

sub new {
  my $self = shift;
    
  unless (ref $self) {
    my $class = ref($self) || $self;
    $self = $class->SUPER::new(@_);
  }
  return $self;
}

sub BEGIN {
  no strict 'refs';
  my %modes = (in => '<', out => '>');
  for my $method (keys %modes) {
    my $field = '_' . $method;
    *$method = sub {
      my $self = shift->new;
      return $self->{$field} unless @_;

      my $file = shift;
      if (defined $file && !ref $file && !defined fileno($file)) {
        my $name = $file;
        open($file = new IO::File, $modes{$method} . $name) or Carp::croak "$name: $!";
      }
      $self->{$field} = $file;
      return $self;
    }
  }
}

sub handle {
  my $self = shift->new;

  $self->in(*STDIN)->out(*STDOUT) unless defined $self->in;
  my $in = $self->in;
  my $out = $self->out;

  my $result = $self->SUPER::handle(join '', <$in>);
  no strict 'refs'; print {$out} $result if defined $out;
}

# ======================================================================

1;

__END__

=head1 NAME

SOAP::Transport::IO - Server side IO support for SOAP::Lite

=head1 SYNOPSIS

  use SOAP::Transport::IO;

  SOAP::Transport::IO::Server

    # you may specify as parameters for new():
    # -> new( in => 'in_file_name' [, out => 'out_file_name'] )
    # -> new( in => IN_HANDLE      [, out => OUT_HANDLE] )
    # -> new( in => *IN_HANDLE     [, out => *OUT_HANDLE] )
    # -> new( in => \*IN_HANDLE    [, out => \*OUT_HANDLE] )
  
    # -- OR --
    # any combinations
    # -> new( in => *STDIN, out => 'out_file_name' )
    # -> new( in => 'in_file_name', => \*OUT_HANDLE )
  
    # -- OR --
    # use in() and/or out() methods
    # -> in( *STDIN ) -> out( *STDOUT )
  
    # -- OR --
    # use default (when nothing specified):
    #      in => *STDIN, out => *STDOUT
  
    # don't forget, if you want to accept parameters from command line
    # \*HANDLER will be understood literally, so this syntax won't work 
    # and server will complain
  
    -> new(@ARGV)
  
    # specify path to My/Examples.pm here
    -> dispatch_to('/Your/Path/To/Deployed/Modules', 'Module::Name', 'Module::method') 
    -> handle
  ;

=head1 DESCRIPTION

=head1 COPYRIGHT

Copyright (C) 2000-2001 Paul Kulchenko. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Paul Kulchenko (paulclinger@yahoo.com)

=cut
