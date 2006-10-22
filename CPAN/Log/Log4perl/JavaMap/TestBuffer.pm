package Log::Log4perl::JavaMap::TestBuffer;

use Carp;
use strict;
use Log::Log4perl::Appender::TestBuffer;

use constant _INTERNAL_DEBUG => 0;

sub new {
    my ($class, $appender_name, $data) = @_;
    my $stderr;

    return Log::Log4perl::Appender->new("Log::Log4perl::Appender::TestBuffer",
                                        name => $appender_name);
}

1;

=head1 NAME

Log::Log4perl::JavaMap::TestBuffer - wraps Log::Log4perl::Appender::TestBuffer

=head1 SYNOPSIS

=head1 DESCRIPTION

Just for testing the Java mapping.

=head1 AUTHORS

    Mike Schilli, <m@perlmeister.com>
    Kevin Goess, <cpan@goess.org> 
    
    June, 2002

=head1 SEE ALSO

http://jakarta.apache.org/log4j/docs/

Log::Log4perl::Javamap

Log::Dispatch::Screen

=cut
