package Log::Log4perl::Appender::String;
our @ISA = qw(Log::Log4perl::Appender);

##################################################
# Log dispatcher writing to a string buffer
##################################################

##################################################
sub new {
##################################################
    my $proto  = shift;
    my $class  = ref $proto || $proto;
    my %params = @_;

    my $self = {
        name      => "unknown name",
        string    => "",
        %params,
    };

    bless $self, $class;
}

##################################################
sub log {   
##################################################
    my $self = shift;
    my %params = @_;

    $self->{string} .= $params{message};
}

##################################################
sub string {   
##################################################
    my($self, $new) = @_;

    if(defined $new) {
        $self->{string} = $new;
    }

    return $self->{string};
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Appender::String - Append to a string

=head1 SYNOPSIS

  use Log::Log4perl::Appender::String;

  my $appender = Log::Log4perl::Appender::String->new( 
      name      => 'my string appender',
  );

      # Append to the string
  $appender->log( 
      message => "I'm searching the city for sci-fi wasabi\n" 
  );

      # Retrieve the result
  my $result = $appender->string();

      # Reset the buffer to the empty string
  $appender->string("");

=head1 DESCRIPTION

This is a simple appender used internally by C<Log::Log4perl>. It
appends messages to a scalar instance variable.

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

