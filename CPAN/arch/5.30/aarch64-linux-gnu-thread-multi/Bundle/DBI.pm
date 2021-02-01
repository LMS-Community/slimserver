# -*- perl -*-

package Bundle::DBI;

our $VERSION = "12.008696";

1;

__END__

=head1 NAME

Bundle::DBI - A bundle to install DBI and required modules.

=head1 SYNOPSIS

  perl -MCPAN -e 'install Bundle::DBI'

=head1 CONTENTS

DBI - for to get to know thyself

DBI::Shell 11.91 - the DBI command line shell

Storable 2.06 - for DBD::Proxy, DBI::ProxyServer, DBD::Forward

Net::Daemon 0.37 - for DBD::Proxy and DBI::ProxyServer

RPC::PlServer 0.2016 - for DBD::Proxy and DBI::ProxyServer

DBD::Multiplex 1.19 - treat multiple db handles as one

=head1 DESCRIPTION

This bundle includes all the modules used by the Perl Database
Interface (DBI) module, created by Tim Bunce.

A I<Bundle> is a module that simply defines a collection of other
modules.  It is used by the L<CPAN> module to automate the fetching,
building and installing of modules from the CPAN ftp archive sites.

This bundle does not deal with the various database drivers (e.g.
DBD::Informix, DBD::Oracle etc), most of which require software from
sources other than CPAN. You'll need to fetch and build those drivers
yourself.

=head1 AUTHORS

Jonathan Leffler, Jochen Wiedmann and Tim Bunce.

=cut
