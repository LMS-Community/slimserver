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

=head1 SEE ALSO

=head1 AUTHOR

2006, Mike Schilli, E<lt>m@perlmeister.comE<gt>

=cut
