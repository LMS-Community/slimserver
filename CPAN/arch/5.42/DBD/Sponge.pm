{
    package DBD::Sponge;

    require DBI;
    require Carp;

    our @EXPORT = qw(); # Do NOT @EXPORT anything.
    our $VERSION = "12.010003";

#   $Id: Sponge.pm 10002 2007-09-26 21:03:25Z Tim $
#
#   Copyright (c) 1994-2003 Tim Bunce Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

    $drh = undef;	# holds driver handle once initialised
    my $methods_already_installed;

    sub driver{
	return $drh if $drh;

	DBD::Sponge::db->install_method("sponge_test_installed_method")
		unless $methods_already_installed++;

	my($class, $attr) = @_;
	$class .= "::dr";
	($drh) = DBI::_new_drh($class, {
	    'Name' => 'Sponge',
	    'Version' => $VERSION,
	    'Attribution' => "DBD::Sponge $VERSION (fake cursor driver) by Tim Bunce",
	    });
	$drh;
    }

    sub CLONE {
        undef $drh;
    }
}


{   package DBD::Sponge::dr; # ====== DRIVER ======
    $imp_data_size = 0;
    # we use default (dummy) connect method
}


{   package DBD::Sponge::db; # ====== DATABASE ======
    $imp_data_size = 0;
    use strict;

    sub prepare {
	my($dbh, $statement, $attribs) = @_;
	my $rows = delete $attribs->{'rows'}
	    or return $dbh->set_err($DBI::stderr,"No rows attribute supplied to prepare");
	my ($outer, $sth) = DBI::_new_sth($dbh, {
	    'Statement'   => $statement,
	    'rows'        => $rows,
	    (map { exists $attribs->{$_} ? ($_=>$attribs->{$_}) : () }
		qw(execute_hook)
	    ),
	});
	if (my $behave_like = $attribs->{behave_like}) {
	    $outer->{$_} = $behave_like->{$_}
		foreach (qw(RaiseError PrintError HandleError ShowErrorStatement));
	}

	if ($statement =~ /^\s*insert\b/) {	# very basic, just for testing execute_array()
	    $sth->{is_insert} = 1;
	    my $NUM_OF_PARAMS = $attribs->{NUM_OF_PARAMS}
		or return $dbh->set_err($DBI::stderr,"NUM_OF_PARAMS not specified for INSERT statement");
	    $sth->STORE('NUM_OF_PARAMS' => $attribs->{NUM_OF_PARAMS} );
	}
	else {	#assume select

	    # we need to set NUM_OF_FIELDS
	    my $numFields;
	    if ($attribs->{'NUM_OF_FIELDS'}) {
		$numFields = $attribs->{'NUM_OF_FIELDS'};
	    } elsif ($attribs->{'NAME'}) {
		$numFields = @{$attribs->{NAME}};
	    } elsif ($attribs->{'TYPE'}) {
		$numFields = @{$attribs->{TYPE}};
	    } elsif (my $firstrow = $rows->[0]) {
		$numFields = scalar @$firstrow;
	    } else {
		return $dbh->set_err($DBI::stderr, 'Cannot determine NUM_OF_FIELDS');
	    }
	    $sth->STORE('NUM_OF_FIELDS' => $numFields);
	    $sth->{NAME} = $attribs->{NAME}
		    || [ map { "col$_" } 1..$numFields ];
	    $sth->{TYPE} = $attribs->{TYPE}
		    || [ (DBI::SQL_VARCHAR()) x $numFields ];
	    $sth->{PRECISION} = $attribs->{PRECISION}
		    || [ map { length($sth->{NAME}->[$_]) } 0..$numFields -1 ];
	    $sth->{SCALE} = $attribs->{SCALE}
		    || [ (0) x $numFields ];
	    $sth->{NULLABLE} = $attribs->{NULLABLE}
		    || [ (2) x $numFields ];
	}

	$outer;
    }

    sub type_info_all {
	my ($dbh) = @_;
	my $ti = [
	    {	TYPE_NAME	=> 0,
		DATA_TYPE	=> 1,
		PRECISION	=> 2,
		LITERAL_PREFIX	=> 3,
		LITERAL_SUFFIX	=> 4,
		CREATE_PARAMS	=> 5,
		NULLABLE	=> 6,
		CASE_SENSITIVE	=> 7,
		SEARCHABLE	=> 8,
		UNSIGNED_ATTRIBUTE=> 9,
		MONEY		=> 10,
		AUTO_INCREMENT	=> 11,
		LOCAL_TYPE_NAME	=> 12,
		MINIMUM_SCALE	=> 13,
		MAXIMUM_SCALE	=> 14,
	    },
	    [ 'VARCHAR', DBI::SQL_VARCHAR(), undef, "'","'", undef, 0, 1, 1, 0, 0,0,undef,0,0 ],
	];
	return $ti;
    }

    sub FETCH {
        my ($dbh, $attrib) = @_;
        # In reality this would interrogate the database engine to
        # either return dynamic values that cannot be precomputed
        # or fetch and cache attribute values too expensive to prefetch.
        return 1 if $attrib eq 'AutoCommit';
        # else pass up to DBI to handle
        return $dbh->SUPER::FETCH($attrib);
    }

    sub STORE {
        my ($dbh, $attrib, $value) = @_;
        # would normally validate and only store known attributes
        # else pass up to DBI to handle
        if ($attrib eq 'AutoCommit') {
            return 1 if $value; # is already set
            Carp::croak("Can't disable AutoCommit");
        }
        return $dbh->SUPER::STORE($attrib, $value);
    }

    sub sponge_test_installed_method {
	my ($dbh, @args) = @_;
	return $dbh->set_err(42, "not enough parameters") unless @args >= 2;
	return \@args;
    }
}


{   package DBD::Sponge::st; # ====== STATEMENT ======
    $imp_data_size = 0;
    use strict;

    sub execute {
	my $sth = shift;

        # hack to support ParamValues (when not using bind_param)
        $sth->{ParamValues} = (@_) ? { map { $_ => $_[$_-1] } 1..@_ } : undef;

	if (my $hook = $sth->{execute_hook}) {
	    &$hook($sth, @_) or return;
	}

	if ($sth->{is_insert}) {
	    my $row;
	    $row = (@_) ? [ @_ ] : die "bind_param not supported yet" ;
	    my $NUM_OF_PARAMS = $sth->{NUM_OF_PARAMS};
	    return $sth->set_err($DBI::stderr, @$row." values bound (@$row) but $NUM_OF_PARAMS expected")
		if @$row != $NUM_OF_PARAMS;
	    { local $^W; $sth->trace_msg("inserting (@$row)\n"); }
	    push @{ $sth->{rows} }, $row;
	}
	else {	# mark select sth as Active
	    $sth->STORE(Active => 1);
	}
	# else do nothing for select as data is already in $sth->{rows}
	return 1;
    }

    sub fetch {
	my ($sth) = @_;
	my $row = shift @{$sth->{'rows'}};
	unless ($row) {
	    $sth->STORE(Active => 0);
	    return undef;
	}
	return $sth->_set_fbav($row);
    }
    *fetchrow_arrayref = \&fetch;

    sub FETCH {
	my ($sth, $attrib) = @_;
	# would normally validate and only fetch known attributes
	# else pass up to DBI to handle
	return $sth->SUPER::FETCH($attrib);
    }

    sub STORE {
	my ($sth, $attrib, $value) = @_;
	# would normally validate and only store known attributes
	# else pass up to DBI to handle
	return $sth->SUPER::STORE($attrib, $value);
    }
}

1;

__END__

=pod

=head1 NAME

DBD::Sponge - Create a DBI statement handle from Perl data

=head1 SYNOPSIS

  my $sponge = DBI->connect("dbi:Sponge:","","",{ RaiseError => 1 });
  my $sth = $sponge->prepare($statement, {
          rows => $data,
          NAME => $names,
          %attr
      }
  );

=head1 DESCRIPTION

DBD::Sponge is useful for making a Perl data structure accessible through a
standard DBI statement handle. This may be useful to DBD module authors who
need to transform data in this way.

=head1 METHODS

=head2 connect()

  my $sponge = DBI->connect("dbi:Sponge:","","",{ RaiseError => 1 });

Here's a sample syntax for creating a database handle for the Sponge driver.
No username and password are needed.

=head2 prepare()

  my $sth = $sponge->prepare($statement, {
          rows => $data,
          NAME => $names,
          %attr
      }
  );

=over 4

=item *

The C<$statement> here is an arbitrary statement or name you want
to provide as identity of your data. If you're using DBI::Profile
it will appear in the profile data.

Generally it's expected that you are preparing a statement handle
as if a C<select> statement happened.

=item *

C<$data> is a reference to the data you are providing, given as an array of arrays.

=item *

C<$names> is a reference an array of column names for the C<$data> you are providing.
The number and order should match the number and ordering of the C<$data> columns.

=item *

C<%attr> is a hash of other standard DBI attributes that you might pass to a prepare statement.

Currently only NAME, TYPE, and PRECISION are supported.

=back

=head1 BUGS

Using this module to prepare INSERT-like statements is not currently documented.

=head1 AUTHOR AND COPYRIGHT

This module is Copyright (c) 2003 Tim Bunce

Documentation initially written by Mark Stosberg

The DBD::Sponge module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. In particular permission
is granted to Tim Bunce for distributing this as a part of the DBI.

=head1 SEE ALSO

L<DBI>

=cut
