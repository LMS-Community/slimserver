##################################################
package Log::Log4perl::Appender::Screen;
##################################################

our @ISA = qw(Log::Log4perl::Appender);

use warnings;
use strict;

use IO::Handle;

##################################################
sub new {
##################################################
    my($class, @options) = @_;

    my $self = {
        autoflush   => 0,
        name        => "unknown name",
        stderr      => 1,
        utf8        => undef,
        @options,
    };

    if( $self->{utf8} ) {
        if( $self->{stderr} ) {
            binmode STDERR, ":utf8";
        } else {
            binmode STDOUT, ":utf8";
        }
    }

    if( $self->{autoflush} ) {
        if( $self->{stderr} ) {
            STDERR->autoflush(1);
        } else {
            STDOUT->autoflush(1);
        }
    }

    bless $self, $class;
}

##################################################
sub log {
##################################################
    my($self, %params) = @_;

    my $fh = \*STDOUT;
    if (ref $self->{stderr}) {
        $fh = \*STDERR if $self->{stderr}{ $params{'log4p_level'} }
                            || $self->{stderr}{ lc $params{'log4p_level'} };
    } elsif ($self->{stderr}) {
        $fh = \*STDERR;
    }

    print $fh $params{message};
}

1;

__END__

=encoding utf8

=head1 NAME

Log::Log4perl::Appender::Screen - Log to STDOUT/STDERR

=head1 SYNOPSIS

    use Log::Log4perl::Appender::Screen;

    my $app = Log::Log4perl::Appender::Screen->new(
      autoflush => 1,
      stderr    => 0,
      utf8      => 1,
    );

    $file->log(message => "Log me\n");

=head1 DESCRIPTION

This is a simple appender for writing to STDOUT or STDERR.

The constructor C<new()> takes an optional parameter C<stderr>:

=over

=item *

If set to a false value, it will log all levels to STDOUT (or, more
accurately, whichever file handle is selected via C<select()>, STDOUT
by default).

=item *

If set to a hash, then any C<log4p_level> with a truthy value will
dynamically use STDERR, or STDOUT otherwise.

=item *

Otherwise, if a true value (the default setting is 1), messages will be
logged to STDERR.

=back

    # All messages/levels to STDERR
    my $app = Log::Log4perl::Appender::Screen->new(
        stderr  => 1,
    );

    # Only ERROR and FATAL to STDERR (case-sensitive)
    my $app = Log::Log4perl::Appender::Screen->new(
        stderr  => { ERROR => 1, FATAL => 1},
    );

Design and implementation of this module has been greatly inspired by
Dave Rolsky's C<Log::Dispatch> appender framework.

To enable printing wide utf8 characters, set the utf8 option to a true
value:

    my $app = Log::Log4perl::Appender::Screen->new(
      stderr    => 1,
      utf8      => 1,
    );

This will issue the necessary binmode command to the selected output
channel (stderr/stdout).

To enable L<autoflush|perlvar/"HANDLE-E<gt>autoflush( EXPR )">, set the
C<autoflush> option to a true value:

    my $app = Log::Log4perl::Appender::Screen->new(
      autoflush => 1,
    );

This will issue the necessary autoflush command to the selected output
channel (stderr/stdout).

This is required in containers, especially when the log volume is low, to
not buffer the log messages and cause a significant delay.

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

