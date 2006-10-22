##################################################
package Log::Log4perl::Appender::TestFileCreeper;
##################################################
# Test appender, intentionally slow. It writes 
# out one byte at a time to provoke sync errors.
# Don't use it, unless for testing.
##################################################

use warnings;
use strict;

use Log::Log4perl::Appender::File;

our @ISA = qw(Log::Log4perl::Appender::File);

##################################################
sub log {
##################################################
    my($self, %params) = @_;

    my $fh = $self->{fh};

    for (split //, $params{message}) {
        print $fh $_;
        my $oldfh = select $self->{fh}; 
        $| = 1; 
        select $oldfh;
    }
}

1;

__END__

=head1 NAME

Log::Log4perl::Appender::TestFileCreeper - Intentionally slow test appender

=head1 SYNOPSIS

    use Log::Log4perl::Appender::TestFileCreeper;

    my $app = Log::Log4perl::Appender::TestFileCreeper->new(
      filename  => 'file.log',
      mode      => 'append',
    );

    $file->log(message => "Log me\n");

=head1 DESCRIPTION

This is a test appender, and it is intentionally slow. It writes 
out one byte at a time to provoke sync errors. Don't use it, unless 
for testing.

=head1 AUTHOR

Mike Schilli <log4perl@perlmeister.com>, 2003

=cut
