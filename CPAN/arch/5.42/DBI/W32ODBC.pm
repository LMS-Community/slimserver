package
  DBI;	# hide this non-DBI package from simple indexers

# $Id: W32ODBC.pm 8696 2007-01-24 23:12:38Z Tim $
#
# Copyright (c) 1997,1999 Tim Bunce
# With many thanks to Patrick Hollins for polishing.
#
# You may distribute under the terms of either the GNU General Public
# License or the Artistic License, as specified in the Perl README file.

=head1 NAME

DBI::W32ODBC - An experimental DBI emulation layer for Win32::ODBC

=head1 SYNOPSIS

  use DBI::W32ODBC;

  # apart from the line above everything is just the same as with
  # the real DBI when using a basic driver with few features.

=head1 DESCRIPTION

This is an experimental pure perl DBI emulation layer for Win32::ODBC

If you can improve this code I'd be interested in hearing about it. If
you are having trouble using it please respect the fact that it's very
experimental. Ideally fix it yourself and send me the details.

=head2 Some Things Not Yet Implemented

	Most attributes including PrintError & RaiseError.
	type_info and table_info

Volunteers welcome!

=cut

${'DBI::VERSION'}	# hide version from PAUSE indexer
   = "0.01";

my $Revision = sprintf("12.%06d", q$Revision: 8696 $ =~ /(\d+)/o);


sub DBI::W32ODBC::import { }	# must trick here since we're called DBI/W32ODBC.pm


use Carp;

use Win32::ODBC;

@ISA = qw(Win32::ODBC);

use strict;

$DBI::dbi_debug = $ENV{PERL_DBI_DEBUG} || 0;
carp "Loaded (W32ODBC) DBI.pm ${'DBI::VERSION'} (debug $DBI::dbi_debug)"
	if $DBI::dbi_debug;



sub connect {
    my ($class, $dbname, $dbuser, $dbpasswd, $module, $attr) = @_;
    $dbname .= ";UID=$dbuser"   if $dbuser;
    $dbname .= ";PWD=$dbpasswd" if $dbpasswd;
    my $h = new Win32::ODBC $dbname;
    warn "Error connecting to $dbname: ".Win32::ODBC::Error()."\n" unless $h;
    bless $h, $class if $h;	# rebless into our class
    $h;
}


sub quote {
    my ($h, $string) = @_;
    return "NULL" if !defined $string;
    $string =~ s/'/''/g;	# standard
    # This hack seems to be required for Access but probably breaks for
	# other databases when using \r and \n. It would be better if we could
	# use ODBC options to detect that we're actually using Access.
    $string =~ s/\r/' & chr\$(13) & '/g;
    $string =~ s/\n/' & chr\$(10) & '/g;
    "'$string'";
}

sub do {
    my($h, $statement, $attribs, @params) = @_;
    Carp::carp "\$h->do() attribs unused" if $attribs;
    my $new_h = $h->prepare($statement) or return undef;    ##
    pop @{ $h->{'___sths'} };                               ## certain death assured
    $new_h->execute(@params) or return undef;               ##
    my $rows = $new_h->rows;                                ##
    $new_h->finish;                                         ## bang bang
    ($rows == 0) ? "0E0" : $rows;
}

# ---

sub prepare {
    my ($h, $sql) = @_;
	## opens a new connection with every prepare to allow
	## multiple, concurrent queries
	my $new_h = new Win32::ODBC $h->{DSN};	##
	return undef if not $new_h;             ## bail if no connection
	bless $new_h;					        ## shouldn't be sub-classed...
    $new_h->{'__prepare'} = $sql;			##
	$new_h->{NAME} = [];				    ##
	$new_h->{NUM_OF_FIELDS} = -1;			##
	push @{ $h->{'___sths'} } ,$new_h;		## save sth in parent for mass destruction
    return $new_h;					        ##
}

sub execute {
    my ($h) = @_;
    my $rc = $h->Sql($h->{'__prepare'});
    return undef if $rc;
    my @fields = $h->FieldNames;
    $h->{NAME} = \@fields;
    $h->{NUM_OF_FIELDS} = scalar @fields;
    $h;	# return dbh as pseudo sth
}


sub fetchrow_hashref {					## provide DBI compatibility
	my $h = shift;
	my $NAME = shift || "NAME";
	my $row = $h->fetchrow_arrayref or return undef;
	my %hash;
	@hash{ @{ $h->{$NAME} } } = @$row;
	return \%hash;
}

sub fetchrow {
    my $h = shift;
    return unless $h->FetchRow();
    my $fields_r = $h->{NAME};
    return $h->Data(@$fields_r);
}
sub fetch {
    my @row = shift->fetchrow;
    return undef unless @row;
    return \@row;
}
*fetchrow_arrayref = \&fetch;			## provide DBI compatibility
*fetchrow_array    = \&fetchrow;		## provide DBI compatibility

sub rows {
    shift->RowCount;
}

sub finish {
    shift->Close;						## uncommented this line
}

# ---

sub commit {
	shift->Transact(ODBC::SQL_COMMIT);
}
sub rollback {
	shift->Transact(ODBC::SQL_ROLLBACK);
}

sub disconnect {
	my ($h) = shift; 					## this will kill all the statement handles
	foreach (@{$h->{'___sths'}}) {		## created for a specific connection
		$_->Close if $_->{DSN};			##
	}							        ##
    $h->Close;  						##
}

sub err {
    (shift->Error)[0];
}
sub errstr {
    scalar( shift->Error );
}

# ---

1;
