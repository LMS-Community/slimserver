package Log::Log4perl::JavaMap::RollingFileAppender;

use Carp;
use strict;
use Log::Dispatch::FileRotate 1.10;


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

    my $max;
    if (defined $data->{MaxBackupIndex}{value}) {
        $max = $data->{MaxBackupIndex}{value};
    }elsif (defined $data->{max}{value}){
        $max = $data->{max}{value};
    }else{
        $max = 1;

    }

    my $size;
    if (defined $data->{MaxFileSize}{value}) {
        $size = $data->{MaxFileSize}{value}
    }elsif (defined $data->{size}{value}){
        $size = $data->{size}{value};
    }else{
        $size = 10_000_000;
    }


    return Log::Log4perl::Appender->new("Log::Dispatch::FileRotate",
        name      => $appender_name,
        filename  => $filename,
        mode      => $mode,
        autoflush => $autoflush,
        size      => $size,
        max       => $max,
    );
}

1;

=head1 NAME

Log::Log4perl::JavaMap::RollingFileAppender - wraps Log::Dispatch::FileRotate

=head1 SYNOPSIS


=head1 DESCRIPTION

This maps log4j's RollingFileAppender to Log::Dispatch::FileRotate 
by Mark Pfeiffer, <markpf@mlp-consulting.com.au>.

Possible config properties for log4j ConsoleAppender are 

    File
    Append      "true|false|1|0" default=true
    BufferedIO  "true|false|1|0" default=false (i.e. autoflush is on)
    MaxFileSize default 10_000_000
    MaxBackupIndex default is 1

Possible config properties for Log::Dispatch::FileRotate are

    filename
    mode  "write|append"
    autoflush 0|1
    size
    max

=head1 AUTHORS

    Kevin Goess, <cpan@goess.org> 
    Mike Schilli, <m@perlmeister.com>
    
    November, 2002

=head1 SEE ALSO

http://jakarta.apache.org/log4j/docs/

Log::Log4perl::Javamap

=cut
