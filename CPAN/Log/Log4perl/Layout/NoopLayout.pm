##################################################
package Log::Log4perl::Layout::NoopLayout;
##################################################


##################################################
sub new {
##################################################
    my $class = shift;
    $class = ref ($class) || $class;

    my $self = {
        format      => undef,
        info_needed => {},
        stack       => [],
    };

    bless $self, $class;

    return $self;
}

##################################################
sub render {
##################################################
    #my($self, $message, $category, $priority, $caller_level) = @_;
    return $_[1];;
}

1;

__END__

=head1 NAME

Log::Log4perl::Layout::NoopLayout - Pass-thru Layout

=head1 SYNOPSIS

  use Log::Log4perl::Layout::NoopLayout;
  my $layout = Log::Log4perl::Layout::NoopLayout->new();

=head1 DESCRIPTION

This is a no-op layout, returns the logging message unaltered,
useful for implementing the DBI logger.

=head1 SEE ALSO

=head1 AUTHOR

Kevin Goess, <cpan@goess.org>  12/2002

=cut
