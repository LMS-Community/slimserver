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

    if (defined $data->{Ident}{value}) {
        $ident = $data->{Ident}{value}
    }elsif (defined $data->{ident}{value}){
        $ident = $data->{ident}{value};
    }else{
        $ident = $0;
    }
    
    return Log::Log4perl::Appender->new("Log::Dispatch::Syslog",
        name      => $appender_name,
        facility  => $facility,
        ident     => $ident,
        min_level => 'debug',
    );
}

1;

=encoding utf8

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

=head1 SEE ALSO

http://jakarta.apache.org/log4j/docs/

Log::Log4perl::Javamap

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

