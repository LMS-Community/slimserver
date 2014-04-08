package Slim::Schema::Year;

# $Id$

use strict;
use base 'Slim::Schema::DBI';

use Slim::Schema::ResultSet::Year;

use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

{
	my $class = __PACKAGE__;

	# Magic to create a ResultSource for this inherited class.
	$class->table('years');

	$class->add_columns('id');
	$class->set_primary_key('id');

	$class->has_many('album' => 'Slim::Schema::Album' => 'year');
	$class->has_many('tracks' => 'Slim::Schema::Track' => 'year');

	$class->resultset_class('Slim::Schema::ResultSet::Year');
}

# For saving favorites
sub url {
	my $self = shift;

	return sprintf('db:year.id=%s', Slim::Utils::Misc::escape($self->id));
}

sub name {
	my $self = shift;

	return $self->id || string('UNK');
}

sub namesort {
	my $self = shift;

	return $self->name;
}

sub displayAsHTML {
	my ($self, $form, $descend, $sort) = @_;

	$form->{'text'} = $self->name;
}

# Rescan this year.  Make sure at least 1 track from this year exists, otherwise
# delete the year.
sub rescan {
	my ( $class, @ids ) = @_;
	
	my $dbh = Slim::Schema->dbh;
	
	my $log = logger('scan.scanner');
	
	for my $id ( @ids ) {
		my $sth = $dbh->prepare_cached( qq{
			SELECT COUNT(*) FROM tracks WHERE year = ?
		} );
		$sth->execute($id);
		my ($count) = $sth->fetchrow_array;
		$sth->finish;
	
		if ( !$count ) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Removing unused year: $id");	
			$dbh->do( "DELETE FROM years WHERE id = ?", undef, $id );
		}
	}
}

1;

__END__
