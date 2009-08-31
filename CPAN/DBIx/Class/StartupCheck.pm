package DBIx::Class::StartupCheck;

=head1 NAME

DBIx::Class::StartupCheck - Run environment checks on startup

=head1 SYNOPSIS

  use DBIx::Class::StartupCheck;

=head1 DESCRIPTION

This module used to check for, and if necessary issue a warning for, a
particular bug found on Red Hat and Fedora systems using their system
perl build. As of September 2008 there are fixed versions of perl for
all current Red Hat and Fedora distributions, but the old check still
triggers, incorrectly flagging those versions of perl to be buggy. A
more comprehensive check has been moved into the test suite in
C<t/99rh_perl_perf_bug.t> and further information about the bug has been
put in L<DBIx::Class::Manual::Troubleshooting>

Other checks may be added from time to time.

Any checks herein can be disabled by setting an appropriate environment
variable. If your system suffers from a particular bug, you will get a
warning message on startup sent to STDERR, explaining what to do about
it and how to suppress the message. If you don't see any messages, you
have nothing to worry about.

=head1 CONTRIBUTORS

Nigel Metheringham

Brandon Black

Matt S. Trout

=head1 AUTHOR

Jon Schutz

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut

1;
