package Log::Log4perl::JavaMap::FileAppender;

use Carp;
use strict;
use Log::Dispatch::File;


sub new {
    my ($class, $appender_name, $data) = @_;
    my $stderr;

    my $filename =  $data->{File}{value} || 
                $data->{filename}{value} || 
                die "'File' not supplied for appender '$appender_name', required for a '$data->{value}'\n";

    my $mode;
    if (defined($data->{Append}{value})){
        if (lc $data->{Append}{value} eq 'true' || $data->{Append}{value} == 1){
            $mode = 'append';
        }elsif (lc $data->{Append}{value} eq 'false' || $data->{Append}{value} == 0) {
            $mode = 'write';
        }elsif($data->{Append} =~ /^(write|append)$/){
            $mode = $data->{Append}
        }else{
            die "'$data->{Append}' is not a legal value for Append for appender '$appender_name', '$data->{value}'\n";
        }
    }else{
        $mode = 'append';
    }

    my $autoflush;
    if (defined($data->{BufferedIO}{value})){
        if (lc $data->{BufferedIO}{value} eq 'true' || $data->{BufferedIO}{value}){
            $autoflush = 1;
        }elsif (lc $data->{BufferedIO}{value} eq 'true' || ! $data->{BufferedIO}{value}) {
            $autoflush = 0;
        }else{
            die "'$data->{BufferedIO}' is not a legal value for BufferedIO for appender '$appender_name', '$data->{value}'\n";
        }
    }else{
        $autoflush = 1;
    }


    return Log::Log4perl::Appender->new("Log::Dispatch::File",
        name      => $appender_name,
        filename  => $filename,
        mode      => $mode,
        autoflush => $autoflush,
    );
}

1;

=encoding utf8

=head1 NAME

Log::Log4perl::JavaMap::FileAppender - wraps Log::Dispatch::File

=head1 SYNOPSIS


=head1 DESCRIPTION

Possible config properties for log4j ConsoleAppender are 

    File
    Append      "true|false|1|0" default=true
    BufferedIO  "true|false|1|0" default=false (i.e. autoflush is on)

Possible config properties for Log::Dispatch::File are

    filename
    mode  "write|append"
    autoflush 0|1

=head1 SEE ALSO

http://jakarta.apache.org/log4j/docs/

Log::Log4perl::Javamap

Log::Dispatch::File

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

