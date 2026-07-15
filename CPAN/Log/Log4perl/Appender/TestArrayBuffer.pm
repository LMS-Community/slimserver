##################################################
package Log::Log4perl::Appender::TestArrayBuffer;
##################################################
# Like Log::Log4perl::Appender::TestBuffer, just with 
# array capability.
# For testing only.
##################################################

use base qw( Log::Log4perl::Appender::TestBuffer );

##################################################
sub log {   
##################################################
    my $self = shift;
    my %params = @_;

    $self->{buffer} .= "[$params{level}]: " if $LOG_PRIORITY;

    if(ref($params{message}) eq "ARRAY") {
        $self->{buffer} .= "[" . join(',', @{$params{message}}) . "]";
    } else {
        $self->{buffer} .= $params{message};
    }
}

1;

=encoding utf8

=head1 NAME

Log::Log4perl::Appender::TestArrayBuffer - Subclass of Appender::TestBuffer

=head1 SYNOPSIS

  use Log::Log4perl::Appender::TestArrayBuffer;

  my $appender = Log::Log4perl::Appender::TestArrayBuffer->new( 
      name      => 'buffer',
  );

      # Append to the buffer
  $appender->log( 
      level =  > 'alert', 
      message => ['first', 'second', 'third'],
  );

      # Retrieve the result
  my $result = $appender->buffer();

      # Reset the buffer to the empty string
  $appender->reset();

=head1 DESCRIPTION

This class is a subclass of Log::Log4perl::Appender::TestBuffer and
just provides message array refs as an additional feature. 

Just like Log::Log4perl::Appender::TestBuffer, 
Log::Log4perl::Appender::TestArrayBuffer is used for internal
Log::Log4perl testing only.

=head1 LICENSE

Copyright 2002-2013 by Mike Schilli E<lt>m@perlmeister.comE<gt> 
and Kevin Goess E<lt>cpan@goess.orgE<gt>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=head1 AUTHOR

Please contribute patches to the project on Github:

    http://github.com/mschilli/log4perl

Send bug reports or requests for enhancements to the authors via our

MAILING LIST (questions, bug reports, suggestions/patches): 
log4perl-devel@lists.sourceforge.net

Authors (please contact them via the list above, not directly):
Mike Schilli <m@perlmeister.com>,
Kevin Goess <cpan@goess.org>

Contributors (in alphabetical order):
Ateeq Altaf, Cory Bennett, Jens Berthold, Jeremy Bopp, Hutton
Davidson, Chris R. Donnelly, Matisse Enzer, Hugh Esco, Anthony
Foiani, James FitzGibbon, Carl Franks, Dennis Gregorovic, Andy
Grundman, Paul Harrington, Alexander Hartmaier  David Hull, 
Robert Jacobson, Jason Kohles, Jeff Macdonald, Markus Peter, 
Brett Rann, Peter Rabbitson, Erik Selberg, Aaron Straup Cope, 
Lars Thegler, David Viner, Mac Yang.

