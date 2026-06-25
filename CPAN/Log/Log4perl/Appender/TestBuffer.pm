package Log::Log4perl::Appender::TestBuffer;
our @ISA = qw(Log::Log4perl::Appender);

##################################################
# Log dispatcher writing to a string buffer
# For testing.
# This is like having a Log::Log4perl::Appender::TestBuffer
##################################################

our %POPULATION       = ();
our $LOG_PRIORITY     = 0;
our $DESTROY_MESSAGES = "";

##################################################
sub new {
##################################################
    my $proto  = shift;
    my $class  = ref $proto || $proto;
    my %params = @_;

    my $self = {
        name      => "unknown name",
        %params,
    };

    bless $self, $class;

    $self->{stderr} = exists $params{stderr} ? $params{stderr} : 1;
    $self->{buffer} = "";

    $POPULATION{$self->{name}} = $self;

    return $self;
}

##################################################
sub log {   
##################################################
    my $self = shift;
    my %params = @_;

    if( !defined $params{level} ) {
        die "No level defined in log() call of " . __PACKAGE__;
    }
    $self->{buffer} .= "[$params{level}]: " if $LOG_PRIORITY;
    $self->{buffer} .= $params{message};
}

###########################################
sub clear {
###########################################
    my($self) = @_;

    $self->{buffer} = "";
}

##################################################
sub buffer {   
##################################################
    my($self, $new) = @_;

    if(defined $new) {
        $self->{buffer} = $new;
    }

    return $self->{buffer};
}

##################################################
sub reset {   
##################################################
    my($self) = @_;

    %POPULATION = ();
    $self->{buffer} = "";
}

##################################################
sub DESTROY {   
##################################################
    my($self) = @_;

    $DESTROY_MESSAGES .= __PACKAGE__ . " destroyed";

    #this delete() along with &reset() above was causing
    #Attempt to free unreferenced scalar at 
    #blib/lib/Log/Log4perl/TestBuffer.pm line 69.
    #delete $POPULATION{$self->name};
}

##################################################
sub by_name {   
##################################################
    my($self, $name) = @_;

    # Return a TestBuffer by appender name. This is useful if
    # test buffers are created behind our back (e.g. via the
    # Log4perl config file) and later on we want to 
    # retrieve an instance to query its content.

    die "No name given"  unless defined $name;

    return $POPULATION{$name};

}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Appender::TestBuffer - Appender class for testing

=head1 SYNOPSIS

  use Log::Log4perl::Appender::TestBuffer;

  my $appender = Log::Log4perl::Appender::TestBuffer->new( 
      name      => 'mybuffer',
  );

      # Append to the buffer
  $appender->log( 
      level =  > 'alert', 
      message => "I'm searching the city for sci-fi wasabi\n" 
  );

      # Retrieve the result
  my $result = $appender->buffer();

      # Clear the buffer to the empty string
  $appender->clear();

=head1 DESCRIPTION

This class is used for internal testing of C<Log::Log4perl>. It
is a C<Log::Dispatch>-style appender, which writes to a buffer 
in memory, from where actual results can be easily retrieved later
to compare with expected results.

Every buffer created is stored in an internal global array, and can
later be referenced by name:

    my $app = Log::Log4perl::Appender::TestBuffer->by_name("mybuffer");

retrieves the appender object of a previously created buffer "mybuffer".
To reset this global array and have it forget all of the previously 
created testbuffer appenders (external references to those appenders
nonwithstanding), use

    Log::Log4perl::Appender::TestBuffer->reset();

=head1 SEE ALSO

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

