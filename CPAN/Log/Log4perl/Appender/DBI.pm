package Log::Log4perl::Appender::DBI;

our @ISA = qw(Log::Log4perl::Appender);

use Carp;

use strict;
use DBI;

sub new {
    my($proto, %p) = @_;
    my $class = ref $proto || $proto;

    my $self = bless {}, $class;

    $self->_init(%p);

    my %defaults = (
        reconnect_attempts => 1,
        reconnect_sleep    => 0,
    );

    for (keys %defaults) {
        if(exists $p{$_}) {
            $self->{$_} = $p{$_};
        } else {
            $self->{$_} = $defaults{$_};
        }
    }

    #e.g.
    #log4j.appender.DBAppndr.params.1 = %p    
    #log4j.appender.DBAppndr.params.2 = %5.5m
    foreach my $pnum (keys %{$p{params}}){
        $self->{bind_value_layouts}{$pnum} = 
                Log::Log4perl::Layout::PatternLayout->new({
                   ConversionPattern  => {value  => $p{params}->{$pnum}},
                   undef_column_value => undef,
                });
    }
    #'bind_value_layouts' now contains a PatternLayout
    #for each parameter heading for the Sql engine

    $self->{SQL} = $p{sql}; #save for error msg later on

    $self->{MAX_COL_SIZE} = $p{max_col_size};

    $self->{BUFFERSIZE} = $p{bufferSize} || 1; 

    if ($p{usePreparedStmt}) {
        $self->{sth} = $self->create_statement($p{sql});
        $self->{usePreparedStmt} = 1;
    }else{
        $self->{layout} = Log::Log4perl::Layout::PatternLayout->new({
            ConversionPattern  => {value  => $p{sql}},
            undef_column_value => undef,
        });
    }

    if ($self->{usePreparedStmt} &&  $self->{bufferSize}){
        warn "Log4perl: you've defined both usePreparedStmt and bufferSize \n".
        "in your appender '$p{name}'--\n".
        "I'm going to ignore bufferSize and just use a prepared stmt\n";
    }

    return $self;
}


sub _init {
    my $self = shift;
    my %params = @_;

    if ($params{dbh}) {
        $self->{dbh} = $params{dbh};
    } else {
        $self->{connect} = sub {
            DBI->connect(@params{qw(datasource username password)},
                         {PrintError => 0, $params{attrs} ? %{$params{attrs}} : ()})
                            or croak "Log4perl: $DBI::errstr";
        };
        $self->{dbh} = $self->{connect}->();
        $self->{_mine} = 1;
    }
}

sub create_statement {
    my ($self, $stmt) = @_;

    $stmt || croak "Log4perl: sql not set in Log4perl::Appender::DBI";

    return $self->{dbh}->prepare($stmt) || croak "Log4perl: DBI->prepare failed $DBI::errstr\n$stmt";

}


sub log {
    my $self = shift;
    my %p = @_;

    #%p is
    #    { name    => $appender_name,
    #      level   => loglevel
    #      message => $message,
    #      log4p_category => $category,
    #      log4p_level  => $level,);
    #    },

        #getting log4j behavior with no specified ConversionPattern
    chomp $p{message} unless ref $p{message}; 

        
    my $qmarks = $self->calculate_bind_values(\%p);


    if ($self->{usePreparedStmt}) {

        $self->query_execute($self->{sth}, @$qmarks);

    }else{

        #first expand any %x's in the statement
        my $stmt = $self->{layout}->render(
                        $p{message},
                        $p{log4p_category},
                        $p{log4p_level},
                        5 + $Log::Log4perl::caller_depth,  
                        );

        push @{$self->{BUFFER}}, $stmt, $qmarks;

        $self->check_buffer();
    }
}

sub query_execute {
    my($self, $sth, @qmarks) = @_;

    my $errstr = "[no error]";

    for my $attempt (0..$self->{reconnect_attempts}) {
        #warn "Exe: @qmarks"; # TODO
        if(! $sth->execute(@qmarks)) {

                  # save errstr because ping() would override it [RT 56145]
                $errstr = $self->{dbh}->errstr();

                # Exe failed -- was it because we lost the DB
                # connection?
                if($self->{dbh}->ping()) {
                    # No, the connection is ok, we failed because there's
                    # something wrong with the execute(): Bad SQL or 
                    # missing parameters or some such). Abort.
                    croak "Log4perl: DBI appender error: '$errstr'";
                }

                if($attempt == $self->{reconnect_attempts}) {
                    croak "Log4perl: DBI appender failed to " .
                          ($self->{reconnect_attempts} == 1 ? "" : "re") .
                          "connect " .
                          "to database after " .
                          "$self->{reconnect_attempts} attempt" .
                          ($self->{reconnect_attempts} == 1 ? "" : "s") .
                          " (last error error was [$errstr]";
                }
            if(! $self->{dbh}->ping()) {
                # Ping failed, try to reconnect
                if($attempt) {
                    #warn "Sleeping"; # TODO
                    sleep($self->{reconnect_sleep}) if $self->{reconnect_sleep};
                }

                eval {
                    #warn "Reconnecting to DB"; # TODO
                    $self->{dbh} = $self->{connect}->();
                };
            }

            if ($self->{usePreparedStmt}) {
                $sth = $self->create_statement($self->{SQL});
                $self->{sth} = $sth if $self->{sth};
            } else {
                #warn "Pending stmt: $self->{pending_stmt}"; #TODO
                $sth = $self->create_statement($self->{pending_stmt});
            }

            next;
        }
        return 1;
    }
    croak "Log4perl: DBI->execute failed $errstr, \n".
          "on $self->{SQL}\n @qmarks";
}

sub calculate_bind_values {
    my ($self, $p) = @_;

    my @qmarks;
    my $user_ph_idx = 0;

    my $i=0;
    
    if ($self->{bind_value_layouts}) {

        my $prev_pnum = 0;
        my $max_pnum = 0;
    
        my @pnums = sort {$a <=> $b} keys %{$self->{bind_value_layouts}};
        $max_pnum = $pnums[-1];
        
        #Walk through the integers for each possible bind value.
        #If it doesn't have a layout assigned from the config file
        #then shift it off the array from the $log call
        #This needs to be reworked now that we always get an arrayref? --kg 1/2003
        foreach my $pnum (1..$max_pnum){
            my $msg;
    
                #we've got a bind_value_layout to fill the spot
            if ($self->{bind_value_layouts}{$pnum}){
               $msg = $self->{bind_value_layouts}{$pnum}->render(
                        $p->{message},
                        $p->{log4p_category},
                        $p->{log4p_level},
                        5 + $Log::Log4perl::caller_depth,  
                    );

               #we don't have a bind_value_layout, so get
               #a message bit
            }elsif (ref $p->{message} eq 'ARRAY' && @{$p->{message}}){
                #$msg = shift @{$p->{message}};
                $msg = $p->{message}->[$i++];

               #here handle cases where we ran out of message bits
               #before we ran out of bind_value_layouts, just keep going
            }elsif (ref $p->{message} eq 'ARRAY'){
                $msg = undef;
                $p->{message} = undef;

               #here handle cases where we didn't get an arrayref
               #log the message in the first placeholder and nothing in the rest
            }elsif (! ref $p->{message} ){
                $msg = $p->{message};
                $p->{message} = undef;

            }

            if ($self->{MAX_COL_SIZE} &&
                length($msg) > $self->{MAX_COL_SIZE}){
                substr($msg, $self->{MAX_COL_SIZE}) = '';
            }
            push @qmarks, $msg;
        }
    }

    #handle leftovers
    if (ref $p->{message} eq 'ARRAY' && @{$p->{message}} ) {
        #push @qmarks, @{$p->{message}};
        push @qmarks, @{$p->{message}}[$i..@{$p->{message}}-1];

    }

    return \@qmarks;
}


sub check_buffer {
    my $self = shift;

    return unless ($self->{BUFFER} && ref $self->{BUFFER} eq 'ARRAY');

    if (scalar @{$self->{BUFFER}} >= $self->{BUFFERSIZE} * 2) {

        my ($sth, $stmt, $prev_stmt);

        $prev_stmt = ""; # Init to avoid warning (ms 5/10/03)

        while (@{$self->{BUFFER}}) {
            my ($stmt, $qmarks) = splice (@{$self->{BUFFER}},0,2);

            $self->{pending_stmt} = $stmt;

                #reuse the sth if the stmt doesn't change
            if ($stmt ne $prev_stmt) {
                $sth->finish if $sth;
                $sth = $self->create_statement($stmt);
            }

            $self->query_execute($sth, @$qmarks);

            $prev_stmt = $stmt;

        }

        $sth->finish;

        my $dbh = $self->{dbh};

        if ($dbh && ! $dbh->{AutoCommit}) {
            $dbh->commit;
        }
    }
}

sub DESTROY {
    my $self = shift;

    $self->{BUFFERSIZE} = 1;

    $self->check_buffer();

    if ($self->{_mine} && $self->{dbh}) {
        $self->{dbh}->disconnect;
    }
}


1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Appender::DBI - implements appending to a DB

=head1 SYNOPSIS

    my $config = q{
     log4j.category = WARN, DBAppndr
     log4j.appender.DBAppndr             = Log::Log4perl::Appender::DBI
     log4j.appender.DBAppndr.datasource  = DBI:CSV:f_dir=t/tmp
     log4j.appender.DBAppndr.username    = bobjones
     log4j.appender.DBAppndr.password    = 12345
     log4j.appender.DBAppndr.sql         = \
        insert into log4perltest           \
        (loglevel, custid, category, message, ipaddr) \
        values (?,?,?,?,?)
     log4j.appender.DBAppndr.params.1 = %p    
                                   #2 is custid from the log() call
     log4j.appender.DBAppndr.params.3 = %c
                                   #4 is the message from log()
                                   #5 is ipaddr from log()

     log4j.appender.DBAppndr.usePreparedStmt = 1
      #--or--
     log4j.appender.DBAppndr.bufferSize = 2

     #just pass through the array of message items in the log statement
     log4j.appender.DBAppndr.layout    = Log::Log4perl::Layout::NoopLayout
     log4j.appender.DBAppndr.warp_message = 0

     #driver attributes support
     log4j.appender.DBAppndr.attrs.f_encoding = utf8
    };

    Log::Log4perl::init ( \$config ) ;                                      

    my $logger = Log::Log4perl->get_logger () ;                             
    $logger->warn( $custid, 'big problem!!', $ip_addr );

=head1 CAVEAT

This is a very young module and there are a lot of variations
in setups with different databases and connection methods,
so make sure you test thoroughly!  Any feedback is welcome!

=head1 DESCRIPTION

This is a specialized Log::Dispatch object customized to work with
log4perl and its abilities, originally based on Log::Dispatch::DBI 
by Tatsuhiko Miyagawa but with heavy modifications.

It is an attempted compromise between what Log::Dispatch::DBI was 
doing and what log4j's JDBCAppender does.  Note the log4j docs say
the JDBCAppender "is very likely to be completely replaced in the future."

The simplest usage is this:

    log4j.category = WARN, DBAppndr
    log4j.appender.DBAppndr            = Log::Log4perl::Appender::DBI
    log4j.appender.DBAppndr.datasource = DBI:CSV:f_dir=t/tmp
    log4j.appender.DBAppndr.username   = bobjones
    log4j.appender.DBAppndr.password   = 12345
    log4j.appender.DBAppndr.sql        = \
       INSERT INTO logtbl                \
          (loglevel, message)            \
          VALUES ('%c','%m')

    log4j.appender.DBAppndr.layout    = Log::Log4perl::Layout::PatternLayout


    $logger->fatal('fatal message');
    $logger->warn('warning message');

    ===============================
    |FATAL|fatal message          |
    |WARN |warning message        |
    ===============================


But the downsides to that usage are:

=over 4

=item * 

You'd better be darn sure there are not quotes in your log message, or your
insert could have unforeseen consequences!  This is a very insecure way to
handle database inserts, using place holders and bind values is much better, 
keep reading. (Note that the log4j docs warn "Be careful of quotes in your 
messages!") B<*>.

=item *

It's not terribly high-performance, a statement is created and executed
for each log call.

=item *

The only run-time parameter you get is the %m message, in reality
you probably want to log specific data in specific table columns.

=back

So let's try using placeholders, and tell the logger to create a
prepared statement handle at the beginning and just reuse it 
(just like Log::Dispatch::DBI does)


    log4j.appender.DBAppndr.sql = \
       INSERT INTO logtbl \
          (custid, loglevel, message) \
          VALUES (?,?,?)

    #---------------------------------------------------
    #now the bind values:
                                  #1 is the custid
    log4j.appender.DBAppndr.params.2 = %p    
                                  #3 is the message
    #---------------------------------------------------

    log4j.appender.DBAppndr.layout    = Log::Log4perl::Layout::NoopLayout
    log4j.appender.DBAppndr.warp_message = 0
    
    log4j.appender.DBAppndr.usePreparedStmt = 1
    
    
    $logger->warn( 1234, 'warning message' ); 


Now see how we're using the '?' placeholders in our statement?  This
means we don't have to worry about messages that look like 

    invalid input: 1234';drop table custid;

fubaring our database!

Normally a list of things in the logging statement gets concatenated into 
a single string, but setting C<warp_message> to 0 and using the 
NoopLayout means that in

    $logger->warn( 1234, 'warning message', 'bgates' );

the individual list values will still be available for the DBI appender later 
on.  (If C<warp_message> is not set to 0, the default behavior is to
join the list elements into a single string.   If PatternLayout or SimpleLayout
are used, their attempt to C<render()> your layout will result in something 
like "ARRAY(0x841d8dc)" in your logs.  More information on C<warp_message>
is in Log::Log4perl::Appender.)

In your insert SQL you can mix up '?' placeholders with conversion specifiers 
(%c, %p, etc) as you see fit--the logger will match the question marks to 
params you've defined in the config file and populate the rest with values 
from your list.  If there are more '?' placeholders than there are values in 
your message, it will use undef for the rest.  For instance, 

	log4j.appender.DBAppndr.sql =                 \
	   insert into log4perltest                   \
	   (loglevel, message, datestr, subpoena_id)\
	   values (?,?,?,?)
	log4j.appender.DBAppndr.params.1 = %p
	log4j.appender.DBAppndr.params.3 = %d

	log4j.appender.DBAppndr.warp_message=0


	$logger->info('arrest him!', $subpoena_id);

results in the first '?' placeholder being bound to %p, the second to
"arrest him!", the third to the date from "%d", and the fourth to your
$subpoenaid.  If you forget the $subpoena_id and just log

	$logger->info('arrest him!');

then you just get undef in the fourth column.


If the logger statement is also being handled by other non-DBI appenders,
they will just join the list into a string, joined with 
C<$Log::Log4perl::JOIN_MSG_ARRAY_CHAR> (default is an empty string).

And see the C<usePreparedStmt>?  That creates a statement handle when
the logger object is created and just reuses it.  That, however, may
be problematic for long-running processes like webservers, in which case
you can use this parameter instead

    log4j.appender.DBAppndr.bufferSize=2

This copies log4j's JDBCAppender's behavior, it saves up that many
log statements and writes them all out at once.  If your INSERT
statement uses only ? placeholders and no %x conversion specifiers
it should be quite efficient because the logger can re-use the
same statement handle for the inserts.

If the program ends while the buffer is only partly full, the DESTROY
block should flush the remaining statements, if the DESTROY block
runs of course.

* I<As I was writing this, Danko Mannhaupt was coming out with his
improved log4j JDBCAppender (http://www.mannhaupt.com/danko/projects/)
which overcomes many of the drawbacks of the original JDBCAppender.>

=head1 DESCRIPTION 2

Or another way to say the same thing:

The idea is that if you're logging to a database table, you probably
want specific parts of your log information in certain columns.  To this
end, you pass an list to the log statement, like 

    $logger->warn('big problem!!',$userid,$subpoena_nr,$ip_addr);

and the array members drop into the positions defined by the placeholders
in your SQL statement. You can also define information in the config
file like

    log4j.appender.DBAppndr.params.2 = %p    

in which case those numbered placeholders will be filled in with
the specified values, and the rest of the placeholders will be
filled in with the values from your log statement's array.

=head1 MISC PARAMETERS


=over 4

=item usePreparedStmt

See above.

=item warp_message

see Log::Log4perl::Appender

=item max_col_size

If you're used to just throwing debugging messages like huge stacktraces
into your logger, some databases (Sybase's DBD!!) may surprise you 
by choking on data size limitations.  Normally, the data would
just be truncated to fit in the column, but Sybases's DBD it turns out
maxes out at 255 characters.  Use this parameter in such a situation
to truncate long messages before they get to the INSERT statement.

=back

=head1 CHANGING DBH CONNECTIONS (POOLING)

If you want to get your dbh from some place in particular, like
maybe a pool, subclass and override _init() and/or create_statement(), 
for instance 

    sub _init {
        ; #no-op, no pooling at this level
    }
    sub create_statement {
        my ($self, $stmt) = @_;
    
        $stmt || croak "Log4perl: sql not set in ".__PACKAGE__;
    
        return My::Connections->getConnection->prepare($stmt) 
            || croak "Log4perl: DBI->prepare failed $DBI::errstr\n$stmt";
    }


=head1 LIFE OF CONNECTIONS

If you're using C<log4j.appender.DBAppndr.usePreparedStmt>
this module creates an sth when it starts and keeps it for the life
of the program.  For long-running processes (e.g. mod_perl), connections
might go stale, but if C<Log::Log4perl::Appender::DBI> tries to write
a message and figures out that the DB connection is no longer working
(using DBI's ping method), it will reconnect.

The reconnection process can be controlled by two parameters,
C<reconnect_attempts> and C<reconnect_sleep>. C<reconnect_attempts>
specifies the number of reconnections attempts the DBI appender 
performs until it gives up and dies. C<reconnect_sleep> is the
time between reconnection attempts, measured in seconds.
C<reconnect_attempts> defaults to 1,  C<reconnect_sleep> to 0.

Alternatively, use C<Apache::DBI> or C<Apache::DBI::Cache> and read
CHANGING DB CONNECTIONS above.

Note that C<Log::Log4perl::Appender::DBI> holds one connection open
for every appender, which might be too many.

=head1 SEE ALSO

L<Log::Dispatch::DBI>

L<Log::Log4perl::JavaMap::JDBCAppender>

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

