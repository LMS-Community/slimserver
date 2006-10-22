package Log::Log4perl::JavaMap::SyslogAppender;

use Carp;
use strict;
use Log::Dispatch::Syslog;


sub new {
    my ($class, $appender_name, $data) = @_;
    my $stderr;

    my ($ident,    #defaults to $0
        $logopt,   #Valid options are 'cons', 'pid', 'ndelay', and 'nowait'.
        $facility, #Valid options are 'auth', 'authpriv',
                   #  'cron', 'daemon', 'kern', 'local0' through 'local7',
                   #   'mail, 'news', 'syslog', 'user', 'uucp'.  Defaults to
                   #   'user'
        $socket,   #Valid options are 'unix' or 'inet'. Defaults to 'inet'
        );

    if (defined $data->{Facility}{value}) {
        $facility = $data->{Facility}{value}
    }elsif (defined $data->{facility}{value}){
        $facility = $data->{facility}{value};
    }else{
        $facility = 'user';
    }

    
    return Log::Log4perl::Appender->new("Log::Dispatch::Syslog",
        name      => $appender_name,
        facility  => $facility,
        min_level => 'debug',
    );
}

1;

=head1 NAME

Log::Log4perl::JavaMap::SysLogAppender - wraps Log::Dispatch::Syslog


=head1 DESCRIPTION

This maps log4j's SyslogAppender to Log::Dispatch::Syslog

Possible config properties for log4j SyslogAppender are 

    SyslogHost (Log::Dispatch::Syslog only accepts 'localhost')
    Facility

Possible config properties for Log::Dispatch::Syslog are

    min_level (debug)
    max_level
    ident    (defaults to $0)
    logopt
    facility 
    socket   (defaults to 'inet')

=head1 AUTHORS

    Kevin Goess, <cpan@goess.org> 
    Mike Schilli, <m@perlmeister.com>
    
    December, 2002

=head1 SEE ALSO

http://jakarta.apache.org/log4j/docs/

Log::Log4perl::Javamap

=cut
