package DBIx::ContextualFetch;

$VERSION = '1.03';

use strict;
use warnings;
no warnings 'uninitialized';

use base 'DBI';

package DBIx::ContextualFetch::db;
use base 'DBI::db';

package DBIx::ContextualFetch::st;
use base 'DBI::st';

sub execute {
	my ($sth) = shift;

	my $rv;

	# Allow $sth->execute(\@param, \@cols) and
	# $sth->execute(undef, \@cols) syntax.
	if (  @_ == 2
		and (!defined $_[0] || ref $_[0] eq 'ARRAY')
		and ref $_[1] eq 'ARRAY') {
		my ($bind_params, $bind_cols) = @_;
		$rv = $sth->_untaint_execute(@$bind_params);
		$sth->SUPER::bind_columns(@$bind_cols);
		} else {
		$sth->_disallow_references(@_);
		$rv = $sth->_untaint_execute(@_);
	}
	return $rv;
}

sub _disallow_references {
	my $self = shift;
	foreach (@_) {
		next unless ref $_;
		next if overload::Method($_, q{""});
		next if overload::Method($_, q{0+});
		die "Cannot call execute with a reference ($_)\n";
	}
}

# local $sth->{Taint} leaks in old perls :(
sub _untaint_execute {
	my $sth = shift;
	my $old_value = $sth->{Taint};
	$sth->{Taint} = 0;
	my $ret = $sth->SUPER::execute(@_);
	$sth->{Taint} = $old_value;
	return $ret;
}

sub fetch {
	my ($sth) = shift;
	return wantarray
		? $sth->SUPER::fetchrow_array
		: $sth->SUPER::fetchrow_arrayref;
}

sub fetch_hash {
	my ($sth) = shift;
	my $row = $sth->SUPER::fetchrow_hashref;
	return unless defined $row;
	return wantarray ? %$row : $row;
}

sub fetchall {
	my ($sth) = shift;
	my $rows = $sth->SUPER::fetchall_arrayref;
	return wantarray ? @$rows : $rows;
}

# There may be some code in DBI->fetchall_arrayref, but its undocumented.
sub fetchall_hash {
	my ($sth) = shift;
	my (@rows, $row);
	push @rows, $row while ($row = $sth->SUPER::fetchrow_hashref);
	return wantarray ? @rows : \@rows;
}

sub select_row {
	my ($sth, @args) = @_;
	$sth->execute(@args);
	my @row = $sth->fetchrow_array;
	$sth->finish;
	return @row;
}

sub select_col {
	my ($sth, @args) = @_;
	my (@row, $cur);
	$sth->execute(@args);
	$sth->bind_col(1, \$cur);
	push @row, $cur while $sth->fetch;
	$sth->finish;
	return @row;
}

sub select_val {
	my ($sth, @args) = @_;
	return ($sth->select_row(@args))[0];
}

return 1;

__END__

=head1 NAME

DBIx::ContextualFetch - Add contextual fetches to DBI

=head1 SYNOPSIS

	my $dbh = DBI->connect(...., { RootClass => "DBIx::ContextualFetch" });

	# Modified statement handle methods.
	my $rv = $sth->execute;
	my $rv = $sth->execute(@bind_values);
	my $rv = $sth->execute(\@bind_values, \@bind_cols);

	# In addition to the normal DBI sth methods...
	my $row_ref = $sth->fetch;
	my @row     = $sth->fetch;

	my $row_ref = $sth->fetch_hash;
	my %row     = $sth->fetch_hash;

	my $rows_ref = $sth->fetchall;
	my @rows     = $sth->fetchall;

	my $rows_ref = $sth->fetchall_hash;
	my @tbl      = $sth->fetchall_hash;

=head1 DESCRIPTION

It always struck me odd that DBI didn't take much advantage of Perl's
context sensitivity. DBIx::ContextualFetch redefines some of the various
fetch methods to fix this oversight. It also adds a few new methods for
convenience (though not necessarily efficiency).

=head1 SET-UP

	my $dbh = DBIx::ContextualFetch->connect(@info);
	my $dbh = DBI->connect(@info, { RootClass => "DBIx::ContextualFetch" });

To use this method, you can either make sure that everywhere you normall
call DBI->connect() you either call it on DBIx::ContextualFetch, or that
you pass this as your RootClass. After this DBI will Do The Right Thing
and pass all its calls through us.

=head1 EXTENSIONS

=head2 execute

	$rv = $sth->execute;
	$rv = $sth->execute(@bind_values);
	$rv = $sth->execute(\@bind_values, \@bind_cols);
 
execute() is enhanced slightly:

If called with no arguments, or with a simple list, execute() operates
normally.  When when called with two array references, it performs
the functions of bind_param, execute and bind_columns similar to the
following:

	$sth->execute(@bind_values);
	$sth->bind_columns(undef, @bind_cols);

In addition, execute will accept tainted @bind_values.  I can't think of
what a malicious user could do with a tainted bind value (in the general
case. Your application may vary.)

Thus a typical idiom would be:

	$sth->execute([$this, $that], [\($foo, $bar)]);

Of course, this method provides no way of passing bind attributes
through to bind_param or bind_columns. If that is necessary, then you
must perform the bind_param, execute, bind_col sequence yourself.

=head2 fetch

	$row_ref = $sth->fetch;
	@row     = $sth->fetch;

A context sensitive version of fetch(). When in scalar context, it will
act as fetchrow_arrayref. In list context it will use fetchrow_array.

=head2 fetch_hash

	$row_ref = $sth->fetch_hash;
	%row     = $sth->fetch_hash;

A modification on fetchrow_hashref. When in scalar context, it acts just
as fetchrow_hashref() does. In list context it returns the complete hash.

=head2 fetchall

	$rows_ref = $sth->fetchall;
	@rows     = $sth->fetchall;

A modification on fetchall_arrayref. In scalar context it acts as
fetchall_arrayref. In list it returns an array of references to rows
fetched.

=head2 fetchall_hash

	$rows_ref = $sth->fetchall_hash;
	@rows     = $sth->fetchall_hash;

A mating of fetchall_arrayref() with fetchrow_hashref(). It gets all rows
from the hash, each as hash references. In scalar context it returns
a reference to an array of hash references. In list context it returns
a list of hash references.

=head1 ORIGINAL AUTHOR 

Michael G Schwern as part of Ima::DBI

=head1 CURRENT MAINTAINER

Tony Bowden <tony@tmtm.com>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<DBI>. L<Ima::DBI>. L<Class::DBI>.

