package Log::Log4perl::JavaMap::ConsoleAppender;

use Carp;
use strict;
use Log::Dispatch::Screen;


sub new {
    my ($class, $appender_name, $data) = @_;
    my $stderr;

    if (my $t = $data->{Target}{value}) {
        if ($t eq 'System.out') {
            $stderr = 0;
        }elsif ($t eq 'System.err') {
            $stderr = 1;
        }else{
            die "ERROR: illegal value '$t' for $data->{value}.Target' in appender $appender_name\n";
        }
    }elsif (defined $data->{stderr}{value}){
        $stderr = $data->{stderr}{value};
    }else{
        $stderr = 0;
    }

    return Log::Log4perl::Appender->new("Log::Dispatch::Screen",
        name   => $appender_name,
        stderr => $stderr );
}


1;


=head1 NAME

Log::Log4perl::JavaMap::ConsoleAppender - wraps Log::Dispatch::Screen

=head1 SYNOPSIS


=head1 DESCRIPTION

Possible config properties for log4j ConsoleAppender are 

    Target (System.out, System.err, default is System.out)

Possible config properties for Log::Dispatch::Screen are

    stderr (0 or 1)

=head1 AUTHORS

    Kevin Goess, <cpan@goess.org> 
    Mike Schilli, <m@perlmeister.com>
    
    June, 2002

=head1 SEE ALSO

http://jakarta.apache.org/log4j/docs/

Log::Log4perl::Javamap

Log::Dispatch::Screen

=cut
