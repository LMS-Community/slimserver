{
    package DBD::NullP;

    require DBI;

    @EXPORT = qw(); # Do NOT @EXPORT anything.
    $VERSION = sprintf("%d.%02d", q$Revision: 1.2 $ =~ /(\d+)\.(\d+)/o);

#   $Id: NullP.pm,v 1.2 2004/12/11 23:50:48 vidur Exp $
#
#   Copyright (c) 1994, Tim Bunce
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

    $drh = undef;	# holds driver handle once initialised
    $err = 0;		# The $DBI::err value

    sub driver{
	return $drh if $drh;
	my($class, $attr) = @_;
	$class .= "::dr";
	($drh) = DBI::_new_drh($class, {
	    'Name' => 'NullP',
	    'Version' => $VERSION,
	    'Attribution' => 'DBD Example Null Perl stub by Tim Bunce',
	    }, [ qw'example implementors private data']);
	$drh;
    }

    sub CLONE {
        undef $drh;
    }
}


{   package DBD::NullP::dr; # ====== DRIVER ======
    $imp_data_size = 0;
    use strict;
    # we use default (dummy) connect method

    sub DESTROY { undef }
}


{   package DBD::NullP::db; # ====== DATABASE ======
    $imp_data_size = 0;
    use strict;

    sub prepare {
	my($dbh, $statement)= @_;

	my($outer, $sth) = DBI::_new_sth($dbh, {
	    'Statement'     => $statement,
	    }, [ qw'example implementors private data']);

	$outer;
    }

    sub FETCH {
	my ($dbh, $attrib) = @_;
	# In reality this would interrogate the database engine to
	# either return dynamic values that cannot be precomputed
	# or fetch and cache attribute values too expensive to prefetch.
	return 1 if $attrib eq 'AutoCommit';
	# else pass up to DBI to handle
	return $dbh->DBD::_::db::FETCH($attrib);
	}

    sub STORE {
	my ($dbh, $attrib, $value) = @_;
	# would normally validate and only store known attributes
	# else pass up to DBI to handle
	if ($attrib eq 'AutoCommit') {
	    return 1 if $value; # is already set
	    croak("Can't disable AutoCommit");
	}
	return $dbh->DBD::_::db::STORE($attrib, $value);
    }

    sub DESTROY { undef }
}


{   package DBD::NullP::st; # ====== STATEMENT ======
    $imp_data_size = 0;
    use strict;

    sub execute {
	my($sth, $data) = @_;
	$sth->{dbd_nullp_data} = $data if $data;
	$sth->{NAME} = [ "fieldname" ];
	1;
    }

    sub fetch {
	my($sth) = @_;
	my $data = $sth->{dbd_nullp_data};
        if ($data) {
	    $sth->{dbd_nullp_data} = undef;
	    return [ $data ];
	}
	$sth->finish;     # no more data so finish
	return undef;
    }

    sub finish {
	my($sth) = @_;
    }

    sub FETCH {
	my ($sth, $attrib) = @_;
	# would normally validate and only fetch known attributes
	# else pass up to DBI to handle
	return $sth->DBD::_::st::FETCH($attrib);
    }

    sub STORE {
	my ($sth, $attrib, $value) = @_;
	# would normally validate and only store known attributes
	# else pass up to DBI to handle
	return $sth->DBD::_::st::STORE($attrib, $value);
    }

    sub DESTROY { undef }
}

1;
