package # hide package from pause
  DBIx::Class::PK::Auto::MySQL;

use strict;
use warnings;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/PK::Auto/);

1;

=head1 NAME

DBIx::Class::PK::Auto::MySQL - (DEPRECATED) Automatic primary key class for MySQL

=head1 SYNOPSIS

Just load PK::Auto instead; auto-inc is now handled by Storage.

=head1 AUTHORS

Matt S Trout <mst@shadowcatsystems.co.uk>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

=cut
