package Slim::DataStores::DBI::Comment;

# $Id: Comment.pm,v 1.1 2004/12/17 20:33:03 dsully Exp $

use strict;
use base 'Slim::DataStores::DBI::DataModel';

{
	my $class = __PACKAGE__;

	$class->table('comments');
	$class->columns(Essential => qw/id track value/);

	$class->has_a(track => 'Slim::DataStores::DBI::Track');

	$class->add_constructor('commentsOf' => 'track = ?');
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
