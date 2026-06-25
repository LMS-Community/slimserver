package Log::Log4perl::JavaMap::JDBCAppender;

use Carp;
use strict;

sub new {
    my ($class, $appender_name, $data) = @_;
    my $stderr;

    my $pwd =  $data->{password}{value} || 
                die "'password' not supplied for appender '$appender_name', required for a '$data->{value}'\n";

    my $username =  $data->{user}{value} || 
                $data->{username}{value} || 
                die "'user' not supplied for appender '$appender_name', required for a '$data->{value}'\n";


    my $sql =  $data->{sql}{value} || 
                die "'sql' not supplied for appender '$appender_name', required for a '$data->{value}'\n";


    my $dsn;

    my $databaseURL = $data->{URL}{value};
    if ($databaseURL) {
        $databaseURL =~ m|^jdbc:(.+?):(.+?)://(.+?):(.+?);(.+)|;
        my $driverName = $1;
        my $databaseName = $2;
        my $hostname = $3;
        my $port = $4;
        my $params = $5;
        $dsn = "dbi:$driverName:database=$databaseName;host=$hostname;port=$port;$params";
    }elsif ($data->{datasource}{value}){
        $dsn = $data->{datasource}{value};
    }else{
        die "'databaseURL' not supplied for appender '$appender_name', required for a '$data->{value}'\n";
    }


    #this part isn't supported by log4j, it's my Log4perl
    #hack, but I think it's so useful I'm going to implement it
    #anyway
    my %bind_value_params;
    foreach my $p (keys %{$data->{params}}){
        $bind_value_params{$p} =  $data->{params}{$p}{value};
    }

    return Log::Log4perl::Appender->new("Log::Log4perl::Appender::DBI",
        datasource    => $dsn,
        username      => $username,
        password      => $pwd, 
        sql           => $sql,
        params        => \%bind_value_params,
            #warp_message also not a log4j thing, but see above
        warp_message=> $data->{warp_message}{value},  
    );
}

1;

=encoding utf8

=head1 NAME

Log::Log4perl::JavaMap::JDBCAppender - wraps Log::Log4perl::Appender::DBI

=head1 SYNOPSIS


=head1 DESCRIPTION

Possible config properties for log4j JDBCAppender are 

    bufferSize 
    sql
    password
    user
    URL - attempting to translate a JDBC URL into DBI parameters,
        let me know if you find problems

Possible config properties for Log::Log4perl::Appender::DBI are

    bufferSize 
    sql
    password
    username
    datasource
    
    usePreparedStmt 0|1
    
    (patternLayout).dontCollapseArrayRefs 0|1
    
    
=head1 SEE ALSO

http://jakarta.apache.org/log4j/docs/

Log::Log4perl::Javamap

Log::Log4perl::Appender::DBI

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

