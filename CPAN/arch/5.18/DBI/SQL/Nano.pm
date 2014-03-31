#######################################################################
#
#  DBI::SQL::Nano - a very tiny SQL engine
#
#  Copyright (c) 2010 by Jens Rehsack < rehsack AT cpan.org >
#  Copyright (c) 2004 by Jeff Zucker < jzucker AT cpan.org >
#
#  All rights reserved.
#
#  You may freely distribute and/or modify this  module under the terms
#  of either the GNU  General Public License (GPL) or the Artistic License,
#  as specified in the Perl README file.
#
#  See the pod at the bottom of this file for help information
#
#######################################################################

#######################
package DBI::SQL::Nano;
#######################
use strict;
use warnings;
use vars qw( $VERSION $versions );

use Carp qw(croak);

require DBI;    # for looks_like_number()

BEGIN
{
    $VERSION = "1.015544";

    $versions->{nano_version} = $VERSION;
    if ( $ENV{DBI_SQL_NANO} || !eval { require SQL::Statement; $SQL::Statement::VERSION ge '1.400' } )
    {
        @DBI::SQL::Nano::Statement::ISA = qw(DBI::SQL::Nano::Statement_);
        @DBI::SQL::Nano::Table::ISA     = qw(DBI::SQL::Nano::Table_);
    }
    else
    {
        @DBI::SQL::Nano::Statement::ISA = qw( SQL::Statement );
        @DBI::SQL::Nano::Table::ISA     = qw( SQL::Eval::Table);
        $versions->{statement_version}  = $SQL::Statement::VERSION;
    }
}

###################################
package DBI::SQL::Nano::Statement_;
###################################

use Carp qw(croak);
use Errno;

if ( eval { require Clone; } )
{
    Clone->import("clone");
}
else
{
    require Storable;    # in CORE since 5.7.3
    *clone = \&Storable::dclone;
}

sub new
{
    my ( $class, $sql ) = @_;
    my $self = {};
    bless $self, $class;
    return $self->prepare($sql);
}

#####################################################################
# PREPARE
#####################################################################
sub prepare
{
    my ( $self, $sql ) = @_;
    $sql =~ s/\s+$//;
    for ($sql)
    {
        /^\s*CREATE\s+TABLE\s+(.*?)\s*\((.+)\)\s*$/is
          && do
        {
            $self->{command}      = 'CREATE';
            $self->{table_name}   = $1;
	    defined $2 and $2 ne "" and
            $self->{column_names} = parse_coldef_list($2);
            $self->{column_names} or croak "Can't find columns";
        };
        /^\s*DROP\s+TABLE\s+(IF\s+EXISTS\s+)?(.*?)\s*$/is
          && do
        {
            $self->{command}              = 'DROP';
            $self->{table_name}           = $2;
	    defined $1 and $1 ne "" and
            $self->{ignore_missing_table} = 1;
        };
        /^\s*SELECT\s+(.*?)\s+FROM\s+(\S+)((.*))?/is
          && do
        {
            $self->{command} = 'SELECT';
	    defined $1 and $1 ne "" and
            $self->{column_names} = parse_comma_list($1);
            $self->{column_names} or croak "Can't find columns";
            $self->{table_name} = $2;
            if ( my $clauses = $4 )
            {
                if ( $clauses =~ /^(.*)\s+ORDER\s+BY\s+(.*)$/is )
                {
                    $clauses = $1;
                    $self->{order_clause} = $self->parse_order_clause($2);
                }
                $self->{where_clause} = $self->parse_where_clause($clauses) if ($clauses);
            }
        };
        /^\s*INSERT\s+(?:INTO\s+)?(\S+)\s*(\((.*?)\))?\s*VALUES\s*\((.+)\)/is
          && do
        {
            $self->{command}      = 'INSERT';
            $self->{table_name}   = $1;
	    defined $2 and $2 ne "" and
            $self->{column_names} = parse_comma_list($2);
	    defined $4 and $4 ne "" and
            $self->{values}       = $self->parse_values_list($4);
            $self->{values} or croak "Can't parse values";
        };
        /^\s*DELETE\s+FROM\s+(\S+)((.*))?/is
          && do
        {
            $self->{command}      = 'DELETE';
            $self->{table_name}   = $1;
	    defined $3 and $3 ne "" and
            $self->{where_clause} = $self->parse_where_clause($3);
        };
        /^\s*UPDATE\s+(\S+)\s+SET\s+(.+)(\s+WHERE\s+.+)/is
          && do
        {
            $self->{command}    = 'UPDATE';
            $self->{table_name} = $1;
	    defined $2 and $2 ne "" and
            $self->parse_set_clause($2);
	    defined $3 and $3 ne "" and
            $self->{where_clause} = $self->parse_where_clause($3);
        };
    }
    croak "Couldn't parse" unless ( $self->{command} and $self->{table_name} );
    return $self;
}

sub parse_order_clause
{
    my ( $self, $str ) = @_;
    my @clause = split /\s+/, $str;
    return { $clause[0] => 'ASC' } if ( @clause == 1 );
    croak "Bad ORDER BY clause '$str'" if ( @clause > 2 );
    $clause[1] ||= '';
    return { $clause[0] => uc $clause[1] }
      if $clause[1] =~ /^ASC$/i
          or $clause[1] =~ /^DESC$/i;
    croak "Bad ORDER BY clause '$clause[1]'";
}

sub parse_coldef_list
{    # check column definitions
    my @col_defs;
    for ( split ',', shift )
    {
        my $col = clean_parse_str($_);
        if ( $col =~ /^(\S+?)\s+.+/ )
        {    # doesn't check what it is
            $col = $1;    # just checks if it exists
        }
        else
        {
            croak "No column definition for '$_'";
        }
        push @col_defs, $col;
    }
    return \@col_defs;
}

sub parse_comma_list
{
    [ map { clean_parse_str($_) } split( ',', shift ) ];
}
sub clean_parse_str { local $_ = shift; s/\(//; s/\)//; s/^\s+//; s/\s+$//; $_; }

sub parse_values_list
{
    my ( $self, $str ) = @_;
    [ map { $self->parse_value( clean_parse_str($_) ) } split( ',', $str ) ];
}

sub parse_set_clause
{
    my $self = shift;
    my @cols = split /,/, shift;
    my $set_clause;
    for my $col (@cols)
    {
        my ( $col_name, $value ) = $col =~ /^\s*(.+?)\s*=\s*(.+?)\s*$/s;
        push @{ $self->{column_names} }, $col_name;
        push @{ $self->{values} },       $self->parse_value($value);
    }
    croak "Can't parse set clause" unless ( $self->{column_names} and $self->{values} );
}

sub parse_value
{
    my ( $self, $str ) = @_;
    return unless ( defined $str );
    $str =~ s/\s+$//;
    $str =~ s/^\s+//;
    if ( $str =~ /^\?$/ )
    {
        push @{ $self->{params} }, '?';
        return {
                 value => '?',
                 type  => 'placeholder'
               };
    }
    return {
             value => undef,
             type  => 'NULL'
           } if ( $str =~ /^NULL$/i );
    return {
             value => $1,
             type  => 'string'
           } if ( $str =~ /^'(.+)'$/s );
    return {
             value => $str,
             type  => 'number'
           } if ( DBI::looks_like_number($str) );
    return {
             value => $str,
             type  => 'column'
           };
}

sub parse_where_clause
{
    my ( $self, $str ) = @_;
    $str =~ s/\s+$//;
    if ( $str =~ /^\s*WHERE\s+(.*)/i )
    {
        $str = $1;
    }
    else
    {
        croak "Couldn't find WHERE clause in '$str'";
    }
    my ($neg) = $str =~ s/^\s*(NOT)\s+//is;
    my $opexp = '=|<>|<=|>=|<|>|LIKE|CLIKE|IS';
    my ( $val1, $op, $val2 ) = $str =~ /^(.+?)\s*($opexp)\s*(.+)\s*$/iso;
    croak "Couldn't parse WHERE expression '$str'" unless ( defined $val1 and defined $op and defined $val2 );
    return {
             arg1 => $self->parse_value($val1),
             arg2 => $self->parse_value($val2),
             op   => $op,
             neg  => $neg,
           };
}

#####################################################################
# EXECUTE
#####################################################################
sub execute
{
    my ( $self, $data, $params ) = @_;
    my $num_placeholders = $self->params;
    my $num_params = scalar @$params || 0;
    croak "Number of params '$num_params' does not match number of placeholders '$num_placeholders'"
      unless ( $num_placeholders == $num_params );
    if ( scalar @$params )
    {
        for my $i ( 0 .. $#{ $self->{values} } )
        {
            if ( $self->{values}->[$i]->{type} eq 'placeholder' )
            {
                $self->{values}->[$i]->{value} = shift @$params;
            }
        }
        if ( $self->{where_clause} )
        {
            if ( $self->{where_clause}->{arg1}->{type} eq 'placeholder' )
            {
                $self->{where_clause}->{arg1}->{value} = shift @$params;
            }
            if ( $self->{where_clause}->{arg2}->{type} eq 'placeholder' )
            {
                $self->{where_clause}->{arg2}->{value} = shift @$params;
            }
        }
    }
    my $command = $self->{command};
    ( $self->{'NUM_OF_ROWS'}, $self->{'NUM_OF_FIELDS'}, $self->{'data'}, ) = $self->$command( $data, $params );
    $self->{NAME} ||= $self->{column_names};
    return $self->{'NUM_OF_ROWS'} || '0E0';
}

my $enoentstr = "Cannot open .*\(" . Errno::ENOENT . "\)";
my $enoentrx  = qr/$enoentstr/;

sub DROP ($$$)
{
    my ( $self, $data, $params ) = @_;

    my $table;
    my @err;
    eval {
        local $SIG{__WARN__} = sub { push @err, @_ };
        ($table) = $self->open_tables( $data, 0, 1 );
    };
    if ( $self->{ignore_missing_table} and ( $@ or @err ) and grep { $_ =~ $enoentrx } ( @err, $@ ) )
    {
        $@ = '';
        return ( -1, 0 );
    }

    croak( $@ || $err[0] ) if ( $@ || @err );
    return ( -1, 0 ) unless $table;

    $table->drop($data);
    ( -1, 0 );
}

sub CREATE ($$$)
{
    my ( $self, $data, $params ) = @_;
    my $table = $self->open_tables( $data, 1, 1 );
    $table->push_names( $data, $self->{column_names} );
    ( 0, 0 );
}

sub INSERT ($$$)
{
    my ( $self, $data, $params ) = @_;
    my $table = $self->open_tables( $data, 0, 1 );
    $self->verify_columns($table);
    my $all_columns = $table->{col_names};
    $table->seek( $data, 0, 2 ) unless ( $table->can('insert_one_row') );
    my ($array) = [];
    my ( $val, $col, $i );
    $self->{column_names} = $table->col_names() unless ( $self->{column_names} );
    my $cNum = scalar( @{ $self->{column_names} } ) if ( $self->{column_names} );
    my $param_num = 0;

    $cNum or
        croak "Bad col names in INSERT";

    my $maxCol = $#$all_columns;

    for ( $i = 0; $i < $cNum; $i++ )
    {
       $col = $self->{column_names}->[$i];
       $array->[ $self->column_nums( $table, $col ) ] = $self->row_values($i);
    }

    # Extend row to put values in ALL fields
    $#$array < $maxCol and $array->[$maxCol] = undef;

    $table->can('insert_new_row') ? $table->insert_new_row( $data, $array ) : $table->push_row( $data, $array );

    return ( 1, 0 );
}

sub DELETE ($$$)
{
    my ( $self, $data, $params ) = @_;
    my $table = $self->open_tables( $data, 0, 1 );
    $self->verify_columns($table);
    my ($affected) = 0;
    my ( @rows, $array );
    my $can_dor = $table->can('delete_one_row');
    while ( $array = $table->fetch_row($data) )
    {
        if ( $self->eval_where( $table, $array ) )
        {
            ++$affected;
            if ( $self->{fetched_from_key} )
            {
                $array = $self->{fetched_value};
                $table->delete_one_row( $data, $array );
                return ( $affected, 0 );
            }
            push( @rows, $array ) if ($can_dor);
        }
        else
        {
            push( @rows, $array ) unless ($can_dor);
        }
    }
    if ($can_dor)
    {
        foreach $array (@rows)
        {
            $table->delete_one_row( $data, $array );
        }
    }
    else
    {
        $table->seek( $data, 0, 0 );
        foreach $array (@rows)
        {
            $table->push_row( $data, $array );
        }
        $table->truncate($data);
    }
    return ( $affected, 0 );
}

sub _anycmp($$;$)
{
    my ( $a, $b, $case_fold ) = @_;

    if ( !defined($a) || !defined($b) )
    {
        return defined($a) - defined($b);
    }
    elsif ( DBI::looks_like_number($a) && DBI::looks_like_number($b) )
    {
        return $a <=> $b;
    }
    else
    {
        return $case_fold ? lc($a) cmp lc($b) || $a cmp $b : $a cmp $b;
    }
}

sub SELECT ($$$)
{
    my ( $self, $data, $params ) = @_;
    my $table = $self->open_tables( $data, 0, 0 );
    $self->verify_columns($table);
    my $tname = $self->{table_name};
    my ($affected) = 0;
    my ( @rows, %cols, $array, $val, $col, $i );
    while ( $array = $table->fetch_row($data) )
    {
        if ( $self->eval_where( $table, $array ) )
        {
            $array = $self->{fetched_value} if ( $self->{fetched_from_key} );
            unless ( keys %cols )
            {
                my $col_nums = $self->column_nums($table);
                %cols = reverse %{$col_nums};
            }

            my $rowhash;
            for ( sort keys %cols )
            {
                $rowhash->{ $cols{$_} } = $array->[$_];
            }
            my @newarray;
            for ( $i = 0; $i < @{ $self->{column_names} }; $i++ )
            {
                $col = $self->{column_names}->[$i];
                push @newarray, $rowhash->{$col};
            }
            push( @rows, \@newarray );
            return ( scalar(@rows), scalar @{ $self->{column_names} }, \@rows )
              if ( $self->{fetched_from_key} );
        }
    }
    if ( $self->{order_clause} )
    {
        my ( $sort_col, $desc ) = each %{ $self->{order_clause} };
        my @sortCols = ( $self->column_nums( $table, $sort_col, 1 ) );
        $sortCols[1] = uc $desc eq 'DESC' ? 1 : 0;

        @rows = sort {
            my ( $result, $colNum, $desc );
            my $i = 0;
            do
            {
                $colNum = $sortCols[ $i++ ];
                $desc   = $sortCols[ $i++ ];
                $result = _anycmp( $a->[$colNum], $b->[$colNum] );
                $result = -$result if ($desc);
            } while ( !$result && $i < @sortCols );
            $result;
        } @rows;
    }
    ( scalar(@rows), scalar @{ $self->{column_names} }, \@rows );
}

sub UPDATE ($$$)
{
    my ( $self, $data, $params ) = @_;
    my $table = $self->open_tables( $data, 0, 1 );
    $self->verify_columns($table);
    return undef unless $table;
    my $affected = 0;
    my $can_usr  = $table->can('update_specific_row');
    my $can_uor  = $table->can('update_one_row');
    my $can_rwu  = $can_usr || $can_uor;
    my ( @rows, $array, $f_array, $val, $col, $i );

    while ( $array = $table->fetch_row($data) )
    {
        if ( $self->eval_where( $table, $array ) )
        {
            $array = $self->{fetched_value} if ( $self->{fetched_from_key} and $can_rwu );
            my $orig_ary = clone($array) if ($can_usr);
            for ( $i = 0; $i < @{ $self->{column_names} }; $i++ )
            {
                $col = $self->{column_names}->[$i];
                $array->[ $self->column_nums( $table, $col ) ] = $self->row_values($i);
            }
            $affected++;
            if ( $self->{fetched_value} )
            {
                if ($can_usr)
                {
                    $table->update_specific_row( $data, $array, $orig_ary );
                }
                elsif ($can_uor)
                {
                    $table->update_one_row( $data, $array );
                }
                return ( $affected, 0 );
            }
            push( @rows, $can_usr ? [ $array, $orig_ary ] : $array );
        }
        else
        {
            push( @rows, $array ) unless ($can_rwu);
        }
    }
    if ($can_rwu)
    {
        foreach my $array (@rows)
        {
            if ($can_usr)
            {
                $table->update_specific_row( $data, @$array );
            }
            elsif ($can_uor)
            {
                $table->update_one_row( $data, $array );
            }
        }
    }
    else
    {
        $table->seek( $data, 0, 0 );
        foreach my $array (@rows)
        {
            $table->push_row( $data, $array );
        }
        $table->truncate($data);
    }

    return ( $affected, 0 );
}

sub verify_columns
{
    my ( $self, $table ) = @_;
    my @cols = @{ $self->{column_names} };
    if ( $self->{where_clause} )
    {
        if ( my $col = $self->{where_clause}->{arg1} )
        {
            push @cols, $col->{value} if $col->{type} eq 'column';
        }
        if ( my $col = $self->{where_clause}->{arg2} )
        {
            push @cols, $col->{value} if $col->{type} eq 'column';
        }
    }
    for (@cols)
    {
        $self->column_nums( $table, $_ );
    }
}

sub column_nums
{
    my ( $self, $table, $stmt_col_name, $find_in_stmt ) = @_;
    my %dbd_nums = %{ $table->col_nums() };
    my @dbd_cols = @{ $table->col_names() };
    my %stmt_nums;
    if ( $stmt_col_name and !$find_in_stmt )
    {
        while ( my ( $k, $v ) = each %dbd_nums )
        {
            return $v if uc $k eq uc $stmt_col_name;
        }
        croak "No such column '$stmt_col_name'";
    }
    if ( $stmt_col_name and $find_in_stmt )
    {
        for my $i ( 0 .. @{ $self->{column_names} } )
        {
            return $i if uc $stmt_col_name eq uc $self->{column_names}->[$i];
        }
        croak "No such column '$stmt_col_name'";
    }
    for my $i ( 0 .. $#dbd_cols )
    {
        for my $stmt_col ( @{ $self->{column_names} } )
        {
            $stmt_nums{$stmt_col} = $i if uc $dbd_cols[$i] eq uc $stmt_col;
        }
    }
    return \%stmt_nums;
}

sub eval_where
{
    my ( $self, $table, $rowary ) = @_;
    my $where    = $self->{"where_clause"} || return 1;
    my $col_nums = $table->col_nums();
    my %cols     = reverse %{$col_nums};
    my $rowhash;
    for ( sort keys %cols )
    {
        $rowhash->{ uc $cols{$_} } = $rowary->[$_];
    }
    return $self->process_predicate( $where, $table, $rowhash );
}

sub process_predicate
{
    my ( $self, $pred, $table, $rowhash ) = @_;
    my $val1 = $pred->{arg1};
    if ( $val1->{type} eq 'column' )
    {
        $val1 = $rowhash->{ uc $val1->{value} };
    }
    else
    {
        $val1 = $val1->{value};
    }
    my $val2 = $pred->{arg2};
    if ( $val2->{type} eq 'column' )
    {
        $val2 = $rowhash->{ uc $val2->{value} };
    }
    else
    {
        $val2 = $val2->{value};
    }
    my $op  = $pred->{op};
    my $neg = $pred->{neg};
    if ( $op eq '=' and !$neg and $table->can('fetch_one_row') )
    {
        my $key_col = $table->fetch_one_row( 1, 1 );
        if ( $pred->{arg1}->{value} =~ /^$key_col$/i )
        {
            $self->{fetched_from_key} = 1;
            $self->{fetched_value} = $table->fetch_one_row( 0, $pred->{arg2}->{value} );
            return 1;
        }
    }
    my $match = $self->is_matched( $val1, $op, $val2 ) || 0;
    if ($neg) { $match = $match ? 0 : 1; }
    return $match;
}

sub is_matched
{
    my ( $self, $val1, $op, $val2 ) = @_;
    if ( $op eq 'IS' )
    {
        return 1 if ( !defined $val1 or $val1 eq '' );
        return 0;
    }
    $val1 = '' unless ( defined $val1 );
    $val2 = '' unless ( defined $val2 );
    if ( $op =~ /LIKE|CLIKE/i )
    {
        $val2 = quotemeta($val2);
        $val2 =~ s/\\%/.*/g;
        $val2 =~ s/_/./g;
    }
    if ( $op eq 'LIKE' )  { return $val1 =~ /^$val2$/s; }
    if ( $op eq 'CLIKE' ) { return $val1 =~ /^$val2$/si; }
    if ( DBI::looks_like_number($val1) && DBI::looks_like_number($val2) )
    {
        if ( $op eq '<' )  { return $val1 < $val2; }
        if ( $op eq '>' )  { return $val1 > $val2; }
        if ( $op eq '=' )  { return $val1 == $val2; }
        if ( $op eq '<>' ) { return $val1 != $val2; }
        if ( $op eq '<=' ) { return $val1 <= $val2; }
        if ( $op eq '>=' ) { return $val1 >= $val2; }
    }
    else
    {
        if ( $op eq '<' )  { return $val1 lt $val2; }
        if ( $op eq '>' )  { return $val1 gt $val2; }
        if ( $op eq '=' )  { return $val1 eq $val2; }
        if ( $op eq '<>' ) { return $val1 ne $val2; }
        if ( $op eq '<=' ) { return $val1 ge $val2; }
        if ( $op eq '>=' ) { return $val1 le $val2; }
    }
}

sub params
{
    my ( $self, $val_num ) = @_;
    if ( !$self->{"params"} ) { return 0; }
    if ( defined $val_num )
    {
        return $self->{"params"}->[$val_num];
    }

    return wantarray ? @{ $self->{"params"} } : scalar @{ $self->{"params"} };
}

sub open_tables
{
    my ( $self, $data, $createMode, $lockMode ) = @_;
    my $table_name = $self->{table_name};
    my $table;
    eval { $table = $self->open_table( $data, $table_name, $createMode, $lockMode ) };
    if ($@)
    {
        chomp $@;
        croak $@;
    }
    croak "Couldn't open table '$table_name'" unless $table;
    if ( !$self->{column_names} or $self->{column_names}->[0] eq '*' )
    {
        $self->{column_names} = $table->col_names();
    }
    return $table;
}

sub row_values
{
    my ( $self, $val_num ) = @_;
    if ( !$self->{"values"} ) { return 0; }
    if ( defined $val_num )
    {
        return $self->{"values"}->[$val_num]->{value};
    }
    if (wantarray)
    {
        return map { $_->{"value"} } @{ $self->{"values"} };
    }
    else
    {
        return scalar @{ $self->{"values"} };
    }
}

sub column_names
{
    my ($self) = @_;
    my @col_names;
    if ( $self->{column_names} and $self->{column_names}->[0] ne '*' )
    {
        @col_names = @{ $self->{column_names} };
    }
    return @col_names;
}

###############################
package DBI::SQL::Nano::Table_;
###############################

use Carp qw(croak);

sub new ($$)
{
    my ( $proto, $attr ) = @_;
    my ($self) = {%$attr};

    defined( $self->{col_names} ) and "ARRAY" eq ref( $self->{col_names} )
      or croak("attribute 'col_names' must be defined as an array");
    exists( $self->{col_nums} ) or $self->{col_nums} = _map_colnums( $self->{col_names} );
    defined( $self->{col_nums} ) and "HASH" eq ref( $self->{col_nums} )
      or croak("attribute 'col_nums' must be defined as a hash");

    bless( $self, ( ref($proto) || $proto ) );
    return $self;
}

sub _map_colnums
{
    my $col_names = $_[0];
    my %col_nums;
    for my $i ( 0 .. $#$col_names )
    {
        next unless $col_names->[$i];
        $col_nums{ $col_names->[$i] } = $i;
    }
    return \%col_nums;
}

sub row()         { return $_[0]->{row}; }
sub column($)     { return $_[0]->{row}->[ $_[0]->column_num( $_[1] ) ]; }
sub column_num($) { $_[0]->{col_nums}->{ $_[1] }; }
sub col_nums()    { $_[0]->{col_nums} }
sub col_names()   { $_[0]->{col_names}; }

sub drop ($$)        { croak "Abstract method " . ref( $_[0] ) . "::drop called" }
sub fetch_row ($$$)  { croak "Abstract method " . ref( $_[0] ) . "::fetch_row called" }
sub push_row ($$$)   { croak "Abstract method " . ref( $_[0] ) . "::push_row called" }
sub push_names ($$$) { croak "Abstract method " . ref( $_[0] ) . "::push_names called" }
sub truncate ($$)    { croak "Abstract method " . ref( $_[0] ) . "::truncate called" }
sub seek ($$$$)      { croak "Abstract method " . ref( $_[0] ) . "::seek called" }

1;
__END__

=pod

=head1 NAME

DBI::SQL::Nano - a very tiny SQL engine

=head1 SYNOPSIS

 BEGIN { $ENV{DBI_SQL_NANO}=1 } # forces use of Nano rather than SQL::Statement
 use DBI::SQL::Nano;
 use Data::Dumper;
 my $stmt = DBI::SQL::Nano::Statement->new(
     "SELECT bar,baz FROM foo WHERE qux = 1"
 ) or die "Couldn't parse";
 print Dumper $stmt;

=head1 DESCRIPTION

C<< DBI::SQL::Nano >> is meant as a I<very> minimal SQL engine for use in
situations where SQL::Statement is not available. In most situations you are
better off installing L<SQL::Statement> although DBI::SQL::Nano may be faster
for some B<very> simple tasks.

DBI::SQL::Nano, like SQL::Statement is primarily intended to provide a SQL
engine for use with some pure perl DBDs including L<DBD::DBM>, L<DBD::CSV>,
L<DBD::AnyData>, and L<DBD::Excel>. It is not of much use in and of itself.
You can dump out the structure of a parsed SQL statement, but that is about
it.

=head1 USAGE

=head2 Setting the DBI_SQL_NANO flag

By default, when a C<< DBD >> uses C<< DBI::SQL::Nano >>, the module will
look to see if C<< SQL::Statement >> is installed. If it is, SQL::Statement
objects are used.  If SQL::Statement is not available, DBI::SQL::Nano
objects are used.

In some cases, you may wish to use DBI::SQL::Nano objects even if
SQL::Statement is available.  To force usage of DBI::SQL::Nano objects
regardless of the availability of SQL::Statement, set the environment
variable DBI_SQL_NANO to 1.

You can set the environment variable in your shell prior to running your
script (with SET or EXPORT or whatever), or else you can set it in your
script by putting this at the top of the script:

 BEGIN { $ENV{DBI_SQL_NANO} = 1 }

=head2 Supported SQL syntax

 Here's a pseudo-BNF.  Square brackets [] indicate optional items;
 Angle brackets <> indicate items defined elsewhere in the BNF.

  statement ::=
      DROP TABLE [IF EXISTS] <table_name>
    | CREATE TABLE <table_name> <col_def_list>
    | INSERT INTO <table_name> [<insert_col_list>] VALUES <val_list>
    | DELETE FROM <table_name> [<where_clause>]
    | UPDATE <table_name> SET <set_clause> <where_clause>
    | SELECT <select_col_list> FROM <table_name> [<where_clause>]
                                                 [<order_clause>]

  the optional IF EXISTS clause ::=
    * similar to MySQL - prevents errors when trying to drop
      a table that doesn't exist

  identifiers ::=
    * table and column names should be valid SQL identifiers
    * especially avoid using spaces and commas in identifiers
    * note: there is no error checking for invalid names, some
      will be accepted, others will cause parse failures

  table_name ::=
    * only one table (no multiple table operations)
    * see identifier for valid table names

  col_def_list ::=
    * a parens delimited, comma-separated list of column names
    * see identifier for valid column names
    * column types and column constraints may be included but are ignored
      e.g. these are all the same:
        (id,phrase)
        (id INT, phrase VARCHAR(40))
        (id INT PRIMARY KEY, phrase VARCHAR(40) NOT NULL)
    * you are *strongly* advised to put in column types even though
      they are ignored ... it increases portability

  insert_col_list ::=
    * a parens delimited, comma-separated list of column names
    * as in standard SQL, this is optional

  select_col_list ::=
    * a comma-separated list of column names
    * or an asterisk denoting all columns

  val_list ::=
    * a parens delimited, comma-separated list of values which can be:
       * placeholders (an unquoted question mark)
       * numbers (unquoted numbers)
       * column names (unquoted strings)
       * nulls (unquoted word NULL)
       * strings (delimited with single quote marks);
       * note: leading and trailing percent mark (%) and underscore (_)
         can be used as wildcards in quoted strings for use with
         the LIKE and CLIKE operators
       * note: escaped single quotation marks within strings are not
         supported, neither are embedded commas, use placeholders instead

  set_clause ::=
    * a comma-separated list of column = value pairs
    * see val_list for acceptable value formats

  where_clause ::=
    * a single "column/value <op> column/value" predicate, optionally
      preceded by "NOT"
    * note: multiple predicates combined with ORs or ANDs are not supported
    * see val_list for acceptable value formats
    * op may be one of:
         < > >= <= = <> LIKE CLIKE IS
    * CLIKE is a case insensitive LIKE

  order_clause ::= column_name [ASC|DESC]
    * a single column optional ORDER BY clause is supported
    * as in standard SQL, if neither ASC (ascending) nor
      DESC (descending) is specified, ASC becomes the default

=head1 TABLES

DBI::SQL::Nano::Statement operates on exactly one table. This table will be
opened by inherit from DBI::SQL::Nano::Statement and implements the
C<< open_table >> method.

  sub open_table ($$$$$)
  {
      ...
      return Your::Table->new( \%attributes );
  }

DBI::SQL::Nano::Statement_ expects a rudimentary interface is implemented by
the table object, as well as SQL::Statement expects.

  package Your::Table;

  use vars qw(@ISA);
  @ISA = qw(DBI::SQL::Nano::Table);

  sub drop ($$)        { ... }
  sub fetch_row ($$$)  { ... }
  sub push_row ($$$)   { ... }
  sub push_names ($$$) { ... }
  sub truncate ($$)    { ... }
  sub seek ($$$$)      { ... }

The base class interfaces are provided by DBI::SQL::Nano::Table_ in case of
relying on DBI::SQL::Nano or SQL::Eval::Table (see L<SQL::Eval> for details)
otherwise.

=head1 BUGS AND LIMITATIONS

There are no known bugs in DBI::SQL::Nano::Statement. If you find a one
and want to report, please see L<DBI> for how to report bugs.

DBI::SQL::Nano::Statement is designed to provide a minimal subset for
executing SQL statements.

The most important limitation might be the restriction on one table per
statement. This implies, that no JOINs are supported and there cannot be
any foreign key relation between tables.

The where clause evaluation of DBI::SQL::Nano::Statement is very slow
(SQL::Statement uses a precompiled evaluation).

INSERT can handle only one row per statement. To insert multiple rows,
use placeholders as explained in DBI.

The DBI::SQL::Nano parser is very limited and does not support any
additional syntax such as brackets, comments, functions, aggregations
etc.

In contrast to SQL::Statement, temporary tables are not supported.

=head1 ACKNOWLEDGEMENTS

Tim Bunce provided the original idea for this module, helped me out of the
tangled trap of namespaces, and provided help and advice all along the way.
Although I wrote it from the ground up, it is based on Jochen Wiedmann's
original design of SQL::Statement, so much of the credit for the API goes
to him.

=head1 AUTHOR AND COPYRIGHT

This module is originally written by Jeff Zucker < jzucker AT cpan.org >

This module is currently maintained by Jens Rehsack < jrehsack AT cpan.org >

Copyright (C) 2010 by Jens Rehsack, all rights reserved.
Copyright (C) 2004 by Jeff Zucker, all rights reserved.

You may freely distribute and/or modify this module under the terms of
either the GNU General Public License (GPL) or the Artistic License,
as specified in the Perl README file.

=cut

