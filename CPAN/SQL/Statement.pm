package SQL::Statement;
#########################################################################
#
# This module is copyright (c), 2001 by Jeff Zucker, All Rights Reserved
#
# It may be freely distributed under the same terms as Perl itself.
#
# See below for help (search for SYNOPSIS)
#########################################################################

use strict;
use SQL::Parser;
use SQL::Eval;
use vars qw($VERSION $numexp $s2pops $arg_num $dlm $warg_num $HAS_DBI);
BEGIN {
    eval { require 'DBI.pm' };
    $HAS_DBI = 1 unless $@;
    *is_number = ($HAS_DBI)
               ? *DBI::looks_like_number
	       : sub {
                     my @strs = @_;
                     for my $x(@strs) {
                         return 0 if !defined $x;
                         return 0 if $x !~ $numexp;
                     }
                     return 1;
                 };
}

#use locale;

$VERSION = '1.09';

$dlm = '~';
$arg_num=0;
$warg_num=0;
$s2pops = {
              'LIKE'   => {'s'=>'LIKE',n=>'LIKE'},
              'CLIKE'  => {'s'=>'CLIKE',n=>'CLIKE'},
              'RLIKE'  => {'s'=>'RLIKE',n=>'RLIKE'},
              '<'  => {'s'=>'lt',n=>'<'},
              '>'  => {'s'=>'gt',n=>'>'},
              '>=' => {'s'=>'ge',n=>'>='},
              '<=' => {'s'=>'le',n=>'<='},
              '='  => {'s'=>'eq',n=>'=='},
              '<>' => {'s'=>'ne',n=>'!='},
};
BEGIN {
  if ($] < 5.005 ) {
    sub qr {}
  }
}

sub new {
    my $class  = shift;
    my $sql    = shift;
    my $flags  = shift;
    #
    # IF USER DEFINED extend_csv IN SCRIPT
    # USE THE ANYDATA DIALECT RATHER THAN THE CSV DIALECT
    # WITH DBD::CSV
    #
    if ($main::extend_csv or $main::extend_sql ) {
       $flags = SQL::Parser->new('AnyData');
    }
    my $parser = $flags;
    my $self   = new2($class);
    $flags->{"PrintError"}    = 1 unless defined $flags->{"PrintError"};
    $flags->{"text_numbers"}  = 1 unless defined $flags->{"text_numbers"};
    $flags->{"alpha_compare"} = 1 unless defined $flags->{"alpha_compare"};
    for (keys %$flags) {
        $self->{$_}=$flags->{$_};
    }
    my $parser_dialect = $flags->{"dialect"} || 'AnyData';
    $parser_dialect = 'AnyData' if $parser_dialect =~ /^(CSV|Excel)$/;

    if (!ref($parser) or (ref($parser) and ref($parser) !~ /^SQL::Parser/)) {
 #   if (!ref($parser)) {
#         print "NEW PARSER\n";
        $parser = new SQL::Parser($parser_dialect,$flags);
    }
#       unless ref $parser and ref $parser =~ /^SQL::Parser/;
#    $parser = new SQL::Parser($parser_dialect,$flags) ;

    if ($] < 5.005 ) {
    $numexp = exists $self->{"text_numbers"}
        ? '^([+-]?|\s+)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$'
        : '^\s*[+-]?\s*\.?\s*\d';
  }
    else {
    $numexp = exists $self->{"text_numbers"}
###new
#        ? qr/^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/
        ? qr/^([+-]?|\s+)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/
###endnew
        : qr/^\s*[+-]?\s*\.?\s*\d/;
    }
    $self->prepare($sql,$parser);
    return $self;
}

sub new2 {
    my $class  = shift;
    my $self   = {};
    return bless $self, $class;
}

sub prepare {
    my $self   = shift;
    my $sql    = shift;
    return $self if $self->{"already_prepared"}->{"$sql"};
    my $parser =  shift;
    my $rv;
    if( $rv = $parser->parse($sql) ) {
       %$self = (%$self,%{$parser->{"struct"}});
       my $tables  = $self->{"table_names"};
       my $columns = $parser->{"struct"}->{"column_names"};
       if ($columns and scalar @$columns == 1 and $columns->[0] eq '*') {
        $self->{"asterisked_columns"} = 1;
       }
       undef $self->{"columns"};
       my $values  = $self->{"values"};
       my $param_num = -1;
       if ($self->{"limit_clause"}) {
	 $self->{"limit_clause"} =
             SQL::Statement::Limit->new( $self->{"limit_clause"} );
       }
       my $max_placeholders = $self->{num_placeholders} || 0;
       #print $self->command, " [$max_placeholders]\n";
       if ($max_placeholders) {
           for my $i(0..$max_placeholders-1) {
               $self->{"params"}->[$i] = SQL::Statement::Param->new($i);
           }
       }
       if ($self->{"sort_spec_list"}) {
           for my $i(0..scalar @{$self->{"sort_spec_list"}} -1 ) {
                my($col,$direction) = each %{ $self->{"sort_spec_list"}->[$i] };
                my $tname;
                 if ($col && $col=~/(.*)\.(.*)/) {
                    $tname = $1; $col=$2;
                }
               undef $direction unless $direction && $direction eq 'DESC';
               $self->{"sort_spec_list"}->[$i] =
                    SQL::Statement::Order->new(
                        col   => SQL::Statement::Column->new($col,[$tname]),
                        desc  => $direction,
                    );
           }
       }
       for (@$columns) {
           push @{ $self->{"columns"} },
                SQL::Statement::Column->new($_,$tables);
       }
       for (@$tables) {
           push @{ $self->{"tables"} },
                SQL::Statement::Table->new($_);
       }
       if ($self->{"where_clause"}) {
           if ($self->{"where_clause"}->{"combiners"}) {
               for ( @{ $self->{"where_clause"}->{"combiners"} } ) {
                   if(/OR/i) { $self->{"has_OR"} = 1; last;}
               }
           }
       }
       $self->{"already_prepared"}->{"$sql"}++;
       return $self;
    }
    else {
       $self->{"errstr"} =  $parser->errstr;
       $self->{"already_prepared"}->{"$sql"}++;
       return undef;
    }
}

sub execute {
    my($self, $data, $params) = @_;
    $self->{'params'}= $params;
    my($table, $msg);
    my($command) = $self->command();
    return $self->do_err( 'No command found!') unless $command;
    ($self->{'NUM_OF_ROWS'}, $self->{'NUM_OF_FIELDS'},
          $self->{'data'}) = $self->$command($data, $params);
#=pod
    my $names = $self->{NAME};
    @$names = map {
        my $org = $self->{ORG_NAME}->{$_}; # from the file header
        $org =~ s/^"//;
        $org =~ s/"$//;
        $org =~ s/""/"/g;
        $org;
    } @$names  if $self->{asterisked_columns};
    $names = $self->{org_col_names} unless $self->{asterisked_columns};

    $self->{NAME} = $names;
if ($command eq 'SELECT') {
#use mylibs; zwarn $self;
#print "\n\n";
#print "[" . ($self->{asterisked_columns}||'') . "]";
#print "~@$names~" if $names;
#print "\n\n";
    }
#=cut
    my $tables;
    @$tables = map {$_->{"name"}} @{ $self->{"tables"} };
    delete $self->{'tables'};  # Force closing the tables
    for (@$tables) {
        push @{ $self->{"tables"} }, SQL::Statement::Table->new($_);
    }
    $self->{'NUM_OF_ROWS'} || '0E0';
}

sub CONNECT ($$$) {
    my($self, $data, $params) = @_;
    if ($self->can('open_connection')) {
        my $dsn = $self->{connection}->{dsn};
        my $tbl = $self->{connection}->{tbl};
        return $self->open_connection($dsn,$tbl,$data,$params)
    }
    (0, 0);
}

sub CREATE ($$$) {
    my($self, $data, $params) = @_;
    my($eval,$foo) = $self->open_tables($data, 1, 1);
    return undef unless $eval;
    $eval->params($params);
    my($row) = [];
    my($col);
    my($table) = $eval->table($self->tables(0)->name());
    foreach $col ($self->columns()) {
        push(@$row, $col->name());
    }
    $table->push_names($data, $row);
    (0, 0);
}

sub DROP ($$$) {
    my($self, $data, $params) = @_;
    if ($self->{ignore_missing_table}) {
         eval { $self->open_tables($data,0,0) };
         if ($@ and $@ =~ /no such (table|file)/i ) {
             return (-1,0);
	 }
    }
    my($eval) = $self->open_tables($data, 0, 1);
#    return undef unless $eval;
    return (-1,0) unless $eval;
#    $eval->params($params);
    my($table) = $eval->table($self->tables(0)->name());
    $table->drop($data);
#use mylibs; zwarn $self->{f_stmt};
    (-1, 0);
}

sub INSERT ($$$) {
    my($self, $data, $params) = @_;
    my($eval,$all_cols) = $self->open_tables($data, 0, 1);
    return undef unless $eval;
    $eval->params($params);
    $self->verify_columns($eval, $all_cols) if scalar ($self->columns());
    my($table) = $eval->table($self->tables(0)->name());
    $table->seek($data, 0, 2);
    my($array) = [];
    my($val, $col, $i);
    my($cNum) = scalar($self->columns());
    my $param_num = 0;
    if ($cNum) {
        # INSERT INTO $table (row, ...) VALUES (value, ...)
        for ($i = 0;  $i < $cNum;  $i++) {
            $col = $self->columns($i);
            $val = $self->row_values($i);
            if ($val and ref($val) eq 'SQL::Statement::Param') {
                $val = $eval->param($val->num());
          }
          elsif ($val and $val->{type} eq 'placeholder') {
                $val = $eval->param($param_num++);
	    }
            else {
	         $val = $self->get_row_value($val,$eval);
	    }
            $array->[$table->column_num($col->name())] = $val;
        }
    } else {
        return $self->do_err("Bad col names in INSERT");
    }
    $table->push_row($data, $array);
    (1, 0);
}

sub DELETE ($$$) {
    my($self, $data, $params) = @_;
    my($eval,$all_cols) = $self->open_tables($data, 0, 1);
    return undef unless $eval;
    $eval->params($params);
    $self->verify_columns($eval, $all_cols);
    my($table) = $eval->table($self->tables(0)->name());
    my($affected) = 0;
    my(@rows, $array);
    if ( $table->can('delete_one_row') ) {
        while (my $array = $table->fetch_row($data)) {
            if ($self->eval_where($eval,'',$array)) {
                ++$affected;
                $array = $self->{fetched_value} if $self->{fetched_from_key};
                $table->delete_one_row($data,$array);
                return ($affected, 0) if $self->{fetched_from_key};
	      }
        }
        return ($affected, 0);
    }
    while ($array = $table->fetch_row($data)) {
        if ($self->eval_where($eval,'',$array)) {
            ++$affected;
        } else {
            push(@rows, $array);
        }
    }
    $table->seek($data, 0, 0);
    foreach $array (@rows) {
        $table->push_row($data, $array);
    }
    $table->truncate($data);
    ($affected, 0);
}

sub UPDATE ($$$) {
    my($self, $data, $params) = @_;
    my $valnum = $self->{num_val_placeholders};
#print "@$params -- $valnum\n";
    if ($valnum) {
#print "[$valnum]";
#my @val_params;
        my @val_params   = splice @$params, 0,$valnum;
        @$params = (@$params,@val_params);
#        my @where_params = $params->[$valnum+1..scalar @$params-1];
#        @$params = (@where_params,@val_params);
    }
#print "@$params\n"; exit;
    my($eval,$all_cols) = $self->open_tables($data, 0, 1);
    return undef unless $eval;
    $eval->params($params);
    $self->verify_columns($eval, $all_cols);
    my($table) = $eval->table($self->tables(0)->name());
    my $tname = $self->tables(0)->name();
    my($affected) = 0;
    my(@rows, $array, $f_array, $val, $col, $i);
    while ($array = $table->fetch_row($data)) {
        if ($self->eval_where($eval,$tname,$array)) {
            if( $self->{fetched_from_key} and $table->can('update_one_row') ){
                $array = $self->{fetched_value};
            }
        my $param_num =$arg_num;
        #print $param_num;
        #print $eval->param($param_num); print "@$params"; exit;
        #$arg_num = 0;
    my $col_nums = $eval->{"tables"}->{"$tname"}->{"col_nums"} ;
    my $cols;
    %$cols   = reverse %{ $col_nums };
    my $rowhash;
    #print "$tname -- @$rowary\n";
    for (sort keys %$cols) {
        $rowhash->{$cols->{$_}} = $array->[$_];
    }
            for ($i = 0;  $i < $self->columns();  $i++) {
                $col = $self->columns($i);
                $val = $self->row_values($i);
                if (ref($val) eq 'SQL::Statement::Param') {
                    $val = $eval->param($val->num());
                }
                elsif ($val->{type} eq 'placeholder') {
                    $val = $eval->param($param_num++);
	        }
                else {
     	            $val = $self->get_row_value($val,$eval,$rowhash);
	        }
                $array->[$table->column_num($col->name())] = $val;
            }
            ++$affected;
        }
        if ($self->{fetched_from_key}){
            $table->update_one_row($data,$array);
            return ($affected, 0);
        }
        push(@rows, $array);
    }
    $table->seek($data, 0, 0);
    foreach $array (@rows) {
        $table->push_row($data, $array);
    }
    $table->truncate($data);
    ($affected, 0);
}

sub find_join_columns {
    my $self = shift;
    my @all_cols = @_;
    my $display_combine = 'NONE';
    $display_combine = 'NATURAL' if $self->{"join"}->{"type"} =~ /NATURAL/;
    $display_combine = 'USING'   if $self->{"join"}->{"clause"} =~ /USING/;
    $display_combine = 'NAMED' if !$self->{"asterisked_columns"};
    my @display_cols;
    my @keycols = ();
    @keycols = @{ $self->{"join"}->{"keycols"} } if $self->{"join"}->{"keycols"};
    @keycols  = map {s/\./$dlm/; $_} @keycols;
    my %is_key_col;
    %is_key_col = map { $_=> 1 } @keycols;

    # IF NAMED COLUMNS, USE NAMED COLUMNS
    #
    if ($display_combine eq 'NAMED') {
        @display_cols =  $self->columns;
        @display_cols = map {$_->table . $dlm . $_->name} @display_cols;
    }

    # IF ASTERISKED COLUMNS AND NOT NATURAL OR USING
    # USE ALL COLUMNS, IN ORDER OF NAMING OF TABLES
    #
    elsif ($display_combine eq 'NONE') {
        @display_cols =  @all_cols;
    }

    # IF NATURAL, COMBINE ALL SHARED COLUMNS
    # IF USING, COMBINE ALL KEY COLUMNS
    #
    else  {
        my %is_natural;
        for my $full_col(@all_cols) {
            my($table,$col) = $full_col =~ /^([^$dlm]+)$dlm(.+)$/;
            next if $display_combine eq 'NATURAL' and $is_natural{$col};
            next if $display_combine eq 'USING' and $is_natural{$col} and
                 $is_key_col{$col};
            push @display_cols,  $full_col;
            $is_natural{$col}++;
        }
    }
    my @shared = ();
    my %is_shared;
    if ($self->{"join"}->{"type"} =~ /NATURAL/ ) {
        for my $full_col(@all_cols) {
            my($table,$col) = $full_col =~ /^([^$dlm]+)$dlm(.+)$/;
            push @shared, $col if  $is_shared{$col}++;
        }
    }
    else {
        @shared = @keycols;
        # @shared = map {s/^[^_]*_(.+)$/$1/; $_} @keycols;
        # @shared = grep !$is_shared{$_}++, @shared
    }
    #print "<@display_cols>\n";
    $self->{"join"}->{"shared_cols"} = \@shared;
    $self->{"join"}->{"display_cols"} = \@display_cols;
    # print "@shared : @display_cols\n";
}

sub JOIN {
    my($self, $data, $params) = @_;
    if ($self->{"join"}->{"type"} =~ /RIGHT/ ) {
        my @tables = $self->tables;
        $self->{"tables"}->[0] = $tables[1];
        $self->{"tables"}->[1] = $tables[0];
    }
    my($eval,$all_cols) = $self->open_tables($data, 0, 0);
    return undef unless $eval;
    $eval->params($params);
    $self->verify_columns( $eval, $all_cols );
    if ($self->{"join"}->{"keycols"} 
     and $self->{"join"}->{"table_order"}
     and scalar @{$self->{"join"}->{"table_order"}} == 0
    ) {
        $self->{"join"}->{"table_order"} = $self->order_joins(
            $self->{"join"}->{"keycols"}
        );
    }
    my  @tables = $self->tables;
    # GET THE LIST OF QUALIFIED COLUMN NAMES FOR DISPLAY
    # *IN ORDER BY NAMING OF TABLES*
    #
    my @all_cols;
    for my $table(@tables) {
        my @cols = @{ $eval->table($table->{name})->col_names };
        for (@cols) {
            push @all_cols, $table . $dlm . $_;
	}
    }
    $self->find_join_columns(@all_cols);

    # JOIN THE TABLES
    # *IN ORDER *BY JOINS*
    #
    @tables = @{ $self->{"join"}->{"table_order"} }
           if $self->{"join"}->{"table_order"}
           and $self->{"join"}->{"type"} !~ /RIGHT/;
    my $tableA;
    my $tableB;
    $tableA = shift @tables;
    $tableB = shift @tables;
    $tableA = $tableA->{name} if ref $tableA;
    $tableB = $tableB->{name} if ref $tableB;
    my $tableAobj = $eval->table($tableA);
    my $tableBobj = $eval->table($tableB);
    $self->join_2_tables($data,$params,$tableAobj,$tableBobj);
    for my $next_table(@tables) {
        $tableAobj = $self->{"join"}->{"table"};
        $tableBobj = $eval->table($next_table);
        $tableBobj->{"NAME"} ||= $next_table;
        $self->join_2_tables($data,$params,$tableAobj,$tableBobj);
        $self->{"cur_table"} = $next_table;
    }
    return $self->SELECT($data,$params);
}

sub join_2_tables {
    my($self, $data, $params, $tableAobj, $tableBobj) = @_;
    #print "<< ".$self->{"cur_table"}." >>\n" if $self->{"cur_table"};
    my $tableA = $tableAobj->{"NAME"};
    my $tableB = $tableBobj->{"NAME"};
    my $share_type = 'IMPLICIT';
    $share_type    = 'NATURAL' if $self->{"join"}->{"type"} =~ /NATURAL/;
    $share_type    = 'USING'   if $self->{"join"}->{"clause"} =~ /USING/;
    $share_type    = 'ON' if $self->{"join"}->{"clause"} =~ /ON/;
    $share_type    = 'USING' if $share_type eq 'ON'
                            and scalar @{ $self->{join}->{keycols} } == 1;
    my $join_type  = 'INNER';
    $join_type     = 'LEFT'  if $self->{"join"}->{"type"} =~ /LEFT/;
    $join_type     = 'RIGHT' if $self->{"join"}->{"type"} =~ /RIGHT/;
    $join_type     = 'FULL'  if $self->{"join"}->{"type"} =~ /FULL/;
    my @colsA = @{$tableAobj->col_names};
    my @colsB = @{$tableBobj->col_names};
    my %iscolA = map { $_=>1} @colsA;
    my %iscolB = map { $_=>1} @colsB;
    my %isunqualA = map { $_=>1} @colsA;
    my %isunqualB = map { $_=>1} @colsB;
    my @shared_cols;
    my %is_shared;
    my @tmpshared = @{ $self->{"join"}->{"shared_cols"} };
    if ($share_type eq 'ON' and $join_type eq 'RIGHT') {
        @tmpshared = reverse @tmpshared;
    }
    if ($share_type eq 'USING') {
        for (@tmpshared) {
             push @shared_cols, $tableA . $dlm . $_;
             push @shared_cols, $tableB . $dlm . $_;
        }
    }
    if ($share_type eq 'NATURAL') {
        for my $c(@colsA) {
            $c =~ s/^[^$dlm]+$dlm(.+)$/$1/ if $tableA eq "${dlm}tmp";
 	    if ($iscolB{$c}) {
                push @shared_cols, $tableA . $dlm . $c;
                push @shared_cols, $tableB . $dlm . $c;
	    }
        }
    }
    my @all_cols = map { $tableA . $dlm . $_ } @colsA;
    @all_cols = ( @all_cols, map { $tableB . $dlm . $_ } @colsB);
    @all_cols = map { s/${dlm}tmp$dlm//; $_; } @all_cols;
    if ($tableA eq "${dlm}tmp") {
        #@colsA = map {s/^[^_]+_(.+)$/$1/; $_; } @colsA;
    }
    else {
        @colsA = map { $tableA . $dlm . $_ } @colsA;
    }
    @colsB = map { $tableB . $dlm . $_ } @colsB;
    my %isa;
    my $i=0;
    my $col_numsA = { map { $_=>$i++}  @colsA };
    $i=0;
    my $col_numsB = { map { $_=>$i++} @colsB };
    %iscolA = map { $_=>1} @colsA;
    %iscolB = map { $_=>1} @colsB;
    my @blankA = map {undef} @colsA;
    my @blankB = map {undef} @colsB;
    if ($share_type =~/^(ON|IMPLICIT)$/ ) {
        while (@tmpshared) {
            my $k1 = shift @tmpshared;
            my $k2 = shift @tmpshared;
            next unless ($iscolA{$k1} or $iscolB{$k1});
            next unless ($iscolA{$k2} or $iscolB{$k2});
            next if !$iscolB{$k1} and !$iscolB{$k2};
            my($t,$c) = $k1 =~ /^([^$dlm]+)$dlm(.+)$/;
            next if !$isunqualA{$c};
            push @shared_cols, $k1 unless $is_shared{$k1}++;
            ($t,$c) = $k2 =~ /^([^$dlm]+)$dlm(.+)$/;
            next if !$isunqualB{$c};
            push @shared_cols, $k2 if !$is_shared{$k2}++;
        }
    }
    %is_shared = map {$_=>1} @shared_cols;
    for my $c(@shared_cols) {
      if ( !$iscolA{$c} and !$iscolB{$c} ) {
          $self->do_err("Can't find shared columns!");
      }
    }
    my($posA,$posB)=([],[]);
    for my $f(@shared_cols) {
         push @$posA, $col_numsA->{$f} if $iscolA{$f};
         push @$posB, $col_numsB->{$f} if $iscolB{$f};
    }
#use mylibs; zwarn $self->{join};
    # CYCLE THROUGH TABLE B, CREATING A HASH OF ITS VALUES
    #
    my $hashB={};
    while (my $array = $tableBobj->fetch_row($data)) {
        my $has_null_key=0;
        my @key_vals = @$array[@$posB];
        for (@key_vals) { next if defined $_; $has_null_key++; last; }
        next if $has_null_key and  $join_type eq 'INNER';
        my $hashkey = join ' ',@key_vals;
        push @{$hashB->{"$hashkey"}}, $array;
    }
    # CYCLE THROUGH TABLE A
    #
    my $joined_table;
    my %visited;
    while (my $arrayA = $tableAobj->fetch_row($data)) {
        my $has_null_key = 0;
        my @key_vals = @$arrayA[@$posA];
        for (@key_vals) { next if defined $_; $has_null_key++; last; }
        next if ($has_null_key and  $join_type eq 'INNER');
        my $hashkey = join ' ',@key_vals;
        my $rowsB = $hashB->{"$hashkey"};
        if (!defined $rowsB and $join_type ne 'INNER' ) {
            push @$rowsB, \@blankB;
	}
        for my $arrayB(@$rowsB) {
            my @newRow = (@$arrayA,@$arrayB);
            if ($join_type ne 'UNION' ) {
                 push @$joined_table,\@newRow;
             }
        }
        $visited{$hashkey}++; #        delete $hashB->{"$hashkey"};
    }

    # ADD THE LEFTOVER B ROWS IF NEEDED
    #
    if ($join_type=~/(FULL|UNION)/) {
      while (my($k,$v)= each%$hashB) {
         next if $visited{$k};
 	 for my $rowB(@$v) {
             my @arrayA;
             my @tmpB;
             my $rowhash;
             @{$rowhash}{@colsB}=@$rowB;
             for my $c(@all_cols) {
                 my($table,$col) = $c =~ /^([^$dlm]+)$dlm(.+)/;
                 push @arrayA,undef if $table eq $tableA;
                 push @tmpB,$rowhash->{$c} if $table eq $tableB;
	     }
             @arrayA[@$posA]=@tmpB[@$posB] if $share_type =~ /(NATURAL|USING)/;
             my @newRow = (@arrayA,@tmpB);
             push @$joined_table, \@newRow;
	 }
      }
    }
    undef $hashB;
    undef $tableAobj;
    undef $tableBobj;
    $self->{"join"}->{"table"} =
        SQL::Statement::TempTable->new(
            $dlm . 'tmp',
            \@all_cols,
            $self->{"join"}->{"display_cols"},
            $joined_table
    );
}

sub SELECT ($$) {
    my($self, $data, $params) = @_;
    $self->{"params"} ||= $params;
    my($eval,$all_cols,$tableName,$table);
    if (defined $self->{"join"} ) {
        return $self->JOIN($data,$params) if !defined $self->{"join"}->{"table"};
        $tableName = $dlm . 'tmp';
        $table     = $self->{"join"}->{"table"};
    }
    else {
        ($eval,$all_cols) = $self->open_tables($data, 0, 0);
        return undef unless $eval;
        $eval->params($params);
        $self->verify_columns( $eval, $all_cols );
        $tableName = $self->tables(0)->name();
        $table = $eval->table($tableName);
    }
    my $rows = [];

    # In a loop, build the list of columns to retrieve; this will be
    # used both for fetching data and ordering.
    my($cList, $col, $tbl, $ar, $i, $c);
    my $numFields = 0;
    my %columns;
    my @names;
    if ($self->{"join"}) {
          @names = @{ $table->col_names };
          for my $col(@names) {
             $columns{$tableName}->{"$col"} = $numFields++;
             push(@$cList, $table->column_num($col));
          }
    }
    else {
        foreach my $column ($self->columns()) {
            #next unless defined $column and ref $column;
            if (ref($column) eq 'SQL::Statement::Param') {
                my $val = $eval->param($column->num());
                if ($val =~ /(.*)\.(.*)/) {
                    $col = $1;
                    $tbl = $2;
                } else {
                    $col = $val;
                    $tbl = $tableName;
                }
            } else {
                ($col, $tbl) = ($column->name(), $column->table());
        }
        if ($col eq '*') {
            $ar = $table->col_names();

#@$ar = map {lc $_} @$ar;
            for ($i = 0;  $i < @$ar;  $i++) {
                my $cName = $ar->[$i];
                $columns{$tbl}->{"$cName"} = $numFields++;
                $c = SQL::Statement::Column->new({'table' => $tableName,
                                                  'column' => $cName});
                push(@$cList, $i);
                push(@names, $cName);
            }
        } else {
            $columns{$tbl}->{"$col"} = $numFields++;
            push(@$cList, $table->column_num($col));
            push(@names, $col);
        }
    }
    }
    $cList = [] unless defined $cList;
    $self->{'NAME'} = \@names;
    if ($self->{"join"}) {
        @{$self->{'NAME'}} = map { s/^[^$dlm]+$dlm//; $_} @names;
    }
    $self->verify_order_cols($table);
    my @order_by = $self->order();
    my @extraSortCols = ();
    my $distinct = $self->distinct();
    if ($distinct) {
        # Silently extend the ORDER BY clause to the full list of
        # columns.
        my %ordered_cols;
        foreach my $column (@order_by) {
            ($col, $tbl) = ($column->column(), $column->table());
            $tbl ||= $self->colname2table($col);
            $ordered_cols{$tbl}->{"$col"} = 1;
        }
        while (my($tbl, $cref) = each %columns) {
            foreach my $col (keys %$cref) {
                if (!$ordered_cols{$tbl}->{"$col"}) {
                    $ordered_cols{$tbl}->{"$col"} = 1;
                    push(@order_by,
                         SQL::Statement::Order->new
                         ('col' => SQL::Statement::Column->new
                          ({'table' => $tbl,
                            'column' => $col}),
                          'desc' => 0));
                }
            }
        }
    }
    if (@order_by) {
        my $nFields = $numFields;
        # It is possible that the user gave an ORDER BY clause with columns
        # that are not part of $cList yet. These columns will need to be
        # present in the array of arrays for sorting, but will be stripped
        # off later.
        my $i=-1;
        foreach my $column (@order_by) {
            $i++;
            ($col, $tbl) = ($column->column(), $column->table());
            my $pos;
            if ($self->{"join"}) {
                  $tbl ||= $self->colname2table($col);
                  $pos = $table->column_num($tbl."$dlm$col");
                  if (!defined $pos) {
                  $tbl = $self->colname2table($col);
                  $pos = $table->column_num($tbl."_$col");
		  }
	    }
            $tbl ||= $self->colname2table($col);
            #print "$tbl~\n";
            next if exists($columns{$tbl}->{"$col"});
            $pos = $table->column_num($col) unless defined $pos;
            push(@extraSortCols, $pos);
            $columns{$tbl}->{"$col"} = $nFields++;
        }
    }
    my $e = $eval;
    if ($self->{"join"}) {
          $e = $table;
    }
    while (my $array = $table->fetch_row($data)) {
        if ($self->eval_where($e,$tableName,$array)) {
            $array = $self->{fetched_value} if $self->{fetched_from_key};
            # Note we also include the columns from @extraSortCols that
            # have to be ripped off later!
            my @row;
            #            if (!scalar @$cList or !scalar @extraSortCols) {
            #               @row = @$array;
            #	    }
            #            else {
                @extraSortCols = () unless @extraSortCols;
            #print "[$_]" for @$cList; print "\n";

            @row = map { defined $_ and defined $array->[$_] ? $array->[$_] : undef } (@$cList, @extraSortCols);
            push(@$rows, \@row);
            return (scalar(@$rows),scalar @{$self->{column_names}},$rows)
 	        if $self->{fetched_from_key};
            #	    }
        }
    }
    if (@order_by) {
        my @sortCols = map {
            my $col = $_->column();
            my $tbl = $_->table();
 	    if ($self->{"join"}) {
               $tbl = 'shared' if $table->is_shared($col);
               $tbl ||= $self->colname2table($col);
	    }
            #print $table->col_table(0),'~',$tbl,'~',$_->column(); exit;
             $tbl ||= $self->colname2table($col);
             ($columns{$tbl}->{"$col"}, $_->desc())
        } @order_by;
        #die "\n<@sortCols>@order_by\n";
        my($c, $d, $colNum, $desc);
        my $sortFunc = sub {
            my $result;
            $i = 0;
            do {
                $colNum = $sortCols[$i++];
                $desc = $sortCols[$i++];
                $c = $a->[$colNum];
                $d = $b->[$colNum];
                if (!defined($c)) {
                    $result = defined $d ? -1 : 0;
                } elsif (!defined($d)) {
                    $result = 1;
	        } elsif ( is_number($c,$d) ) {
#	        } elsif ( $c =~ $numexp && $d =~ $numexp ) {
                    $result = ($c <=> $d);
                } else {
  		    if ($self->{"case_fold"}) {
                        $result = lc $c cmp lc $d || $c cmp $d;
		    }
                    else {
                        $result = $c cmp $d;
		    }
                }
                if ($desc) {
                    $result = -$result;
                }
            } while (!$result  &&  $i < @sortCols);
            $result;
        };
        if ($distinct) {
            my $prev;
            @$rows = map {
                if ($prev) {
                    $a = $_;
                    $b = $prev;
                    if (&$sortFunc() == 0) {
                        ();
                    } else {
                        $prev = $_;
                    }
                } else {
                    $prev = $_;
                }
            } ($] > 5.00504 ?
               sort $sortFunc @$rows :
               sort { &$sortFunc } @$rows);
        } else {
            @$rows = $] > 5.00504 ?
                (sort $sortFunc @$rows) :
                (sort { &$sortFunc } @$rows)
        }

        # Rip off columns that have been added for @extraSortCols only
        if (@extraSortCols) {
            foreach my $row (@$rows) {
                splice(@$row, $numFields, scalar(@extraSortCols));
            }
        }
    }
    if ($self->{"join"}) {
        my @final_cols = @{$self->{"join"}->{"display_cols"}};
        @final_cols = map {$table->column_num($_)} @final_cols;
        my @names = map { $self->{"NAME"}->[$_]} @final_cols;
#        my @names = map { $self->{"REAL_NAME"}->[$_]} @final_cols;
        $numFields = scalar @names;
        $self->{"NAME"} = \@names;
        my $i = -1;
        for my $row(@$rows) {
            $i++;
            @{ $rows->[$i] } = @$row[@final_cols];
        }
    }
    if (defined $self->{"limit_clause"}) {
        my $offset = $self->{"limit_clause"}->offset || 0;
        my $limit  = $self->{"limit_clause"}->limit  || 0;
        @$rows = splice @$rows, $offset, $limit;
    }
    if ($self->{"set_function"}) {
        my $numrows = scalar( @$rows );
        my $numcols = scalar @{ $self->{"NAME"} };
        my $i=0;
        my %colnum = map {$_=>$i++} @{ $self->{"NAME"} };
        for my $i(0 .. scalar @{$self->{"set_function"}} -1 ) {
            my $arg = $self->{"set_function"}->[$i]->{"arg"};
            $self->{"set_function"}->[$i]->{"sel_col_num"} = $colnum{$arg} if defined $colnum{$arg};
        }
        my($name,$arg,$sel_col_num);
        my @set;
        my $final=0;
        $numrows=0;
        my @final_row = map {undef} @{$self->{"set_function"}};
  #      my $start;
        for my $c(@$rows) {
            $numrows++;
            my $sf_index = -1;
 	    for my $sf(@{$self->{"set_function"}}) {
              $sf_index++;
	      if ($sf->{arg} and $sf->{"arg"} eq '*') {
                  $final_row[$sf_index]++;
	      }
              else {
                my $v = $c->[$sf->{"sel_col_num"}];
                my $name = $sf->{"name"};
                next unless defined $v;
                my $final = $final_row[$sf_index];
                $final++      if $name =~ /COUNT/;
#                $final += $v  if $name =~ /SUM|AVG/;
                if( $name =~ /SUM|AVG/) {
                    return $self->do_err("Can't use $name on a string!")
#                      unless $v =~ $numexp;
                      unless is_number($v);
                    $final += $v;
                }
                #
                # Thanks Dean Kopesky dean.kopesky@reuters.com
                # submitted patch to make MIN/MAX do cmp on strings
                # and == on numbers
                #
                # but thanks also to Michael Kovacs mkovacs@turing.une.edu.au
                # for catching a problem when a MAX column is 0
                # necessitating !$final instead of ! defined $final
                #
                $final  = $v  if !$final
                              or ( $name eq 'MAX'
                                   and $v
                                   and $final
                                   and anycmp($v,$final) > 0
                                 );
                $final  = $v  if !$final
                              or ( $name eq 'MIN' 
                                   and defined $v
                                   and anycmp($v,$final) < 0
                                  );
                $final_row[$sf_index] = $final;
	      }
	    }
	}
        for my $i(0..$#final_row) {
	  if ($self->{"set_function"}->[$i]->{"name"} eq 'AVG') {
              $final_row[$i] = $final_row[$i]/$numrows;
	  }
	}
        return ( $numrows, scalar @final_row, [\@final_row]);
    }
    (scalar(@$rows), $numFields, $rows);
}

sub anycmp($$) {
    my ($a,$b) = @_;
    $a = '' unless defined $a;
    $b = '' unless defined $b;
#    return ($a =~ $numexp && $b =~ $numexp)
    return ( is_number($a,$b) )
        ? ($a <=> $b)
        : ($a cmp $b);
}

sub eval_where {
    my $self   = shift;
    my $eval   = shift;
    my $tname  = shift;
    my $rowary = shift;
    $tname ||= $self->tables(0)->name();
    my $where = $self->{"where_clause"} || return 1;
    my $cols;
    my $col_nums;
    if ($self->{"join"}) {
        $col_nums = $eval->{"col_nums"};
    }
    else {
        $col_nums = $eval->{"tables"}->{"$tname"}->{"col_nums"} ;
    }
    %$cols   = reverse %{ $col_nums };
    my $rowhash;
    #print "$tname -- @$rowary\n";
    for (sort keys %$cols) {
        $rowhash->{$cols->{$_}} = $rowary->[$_];
    }
    my @truths;
    $arg_num=0;
    return $self->process_predicate ($where,$eval,$rowhash);
}

sub process_predicate {
    my($self,$pred,$eval,$rowhash) = @_;
    if ($pred->{op} eq 'OR') {
        my $match1 = $self->process_predicate($pred->{"arg1"},$eval,$rowhash);
        return 1 if $match1 and !$pred->{"neg"};
        my $match2 = $self->process_predicate($pred->{"arg2"},$eval,$rowhash);
        if ($pred->{"neg"}) {
            return (!$match1 and !$match2) ? 1 : 0;
        }
        else {
	    return $match2 ? 1 : 0;
	}
    }
    elsif ($pred->{op} eq 'AND') {
        my $match1 = $self->process_predicate($pred->{"arg1"},$eval,$rowhash);
        if ($pred->{"neg"}) {
	    return 1 unless $match1;
        }
        else {
	    return 0 unless $match1;
	}
        my $match2 = $self->process_predicate($pred->{"arg2"},$eval,$rowhash);
        if ($pred->{"neg"}) {
            return $match2 ? 0 : 1;
        }
        else {
	    return $match2 ? 1 : 0;
	}
    }
    else {
        my $val1 = $self->get_row_value( $pred->{"arg1"}, $eval, $rowhash );
        my $val2 = $self->get_row_value( $pred->{"arg2"}, $eval, $rowhash );
        my $op   = $pred->{op};
        if ("DBD or AnyData") {
  	    if ( $op !~ /^IS/i and (
              !defined $val1 or $val1 eq '' or
              !defined $val2 or $val2 eq '' 
            )) {
                  $op = $s2pops->{"$op"}->{'s'};
	    }
            else {
                if (defined $val1 and defined $val2 and $op !~ /^IS/i ) {
#                    $op = ( $val1 =~ $numexp && $val2 =~ $numexp )
                    $op = ( is_number($val1,$val2) )
                        ? $s2pops->{"$op"}->{'n'}
                        : $s2pops->{"$op"}->{'s'};
                }
	    }
	}
        else {
            if (defined $val1 and defined $val2 and $op !~ /^IS/i ) {
#                $op = ( $val1 =~ $numexp && $val2 =~ $numexp )
                $op = ( is_number($val1,$val2) )
                    ? $s2pops->{"$op"}->{'n'}
                    : $s2pops->{"$op"}->{'s'};
	    }
        }
        my $neg = $pred->{"neg"};
        if (ref $eval !~ /TempTable/) {
            my($table) = $eval->table($self->tables(0)->name());
            if ($pred->{op} eq '=' and !$neg and $table->can('fetch_one_row')){
                my $key_col = $table->fetch_one_row(1,1);
                if ($pred->{arg1}->{value} =~ /^$key_col$/i) {
                    $self->{fetched_from_key}=1;
                    $self->{fetched_value} = $table->fetch_one_row(0,$val2);
                    return 1;
	        }
            }
	}
        my $match = $self->is_matched($val1,$op,$val2) || 0;
        if ($pred->{"neg"}) {
           $match = $match ? 0 : 1;
        }
        return $match;
    }
}

sub is_matched {
    my($self,$val1,$op,$val2)=@_;
    #print "[$val1] [$op] [$val2]\n";

    # if DBD::CSV or AnyData
        if ($op eq 'IS') {
            return 1 if (!defined $val1 or $val1 eq '');
            return 0;
        }
        $val1 = '' unless defined $val1;
        $val2 = '' unless defined $val2;
    # else
#print "$val1 ~ $op ~ $val2\n";
        if ($op eq 'IS') {
            return defined $val1 ? 0 : 1;
        }
    return undef if !defined $val1 or !defined $val2;
    if ($op =~ /LIKE|CLIKE/i) {
        $val2 = quotemeta($val2);
        $val2 =~ s/\\%/.*/g;
        $val2 =~ s/_/./g;
    }
    if ( !$self->{"alpha_compare"} && $op =~ /lt|gt|le|ge/ ) {
        return 0;
    }
    # print "[$val1] [$val2]\n";
    if ($op eq 'LIKE' )  { return $val1 =~ /^$val2$/s;  }
    if ($op eq 'CLIKE' ) { return $val1 =~ /^$val2$/si; }
    if ($op eq 'RLIKE' ) { return $val1 =~ /$val2/is;   }
    if ($op eq '<' ) { return $val1 <  $val2; }
    if ($op eq '>' ) { return $val1 >  $val2; }
    if ($op eq '==') { return $val1 == $val2; }
    if ($op eq '!=') { return $val1 != $val2; }
    if ($op eq '<=') { return $val1 <= $val2; }
    if ($op eq '>=') { return $val1 >= $val2; }
    if ($op eq 'lt') { return $val1 lt $val2; }
    if ($op eq 'gt') { return $val1 gt $val2; }
    if ($op eq 'eq') { return $val1 eq $val2; }
    if ($op eq 'ne') { return $val1 ne $val2; }
    if ($op eq 'le') { return $val1 le $val2; }
    if ($op eq 'ge') { return $val1 ge $val2; }
}

sub open_tables {
    my($self, $data, $createMode, $lockMode) = @_;
    my @call = caller 4;
    my $caller = $call[3];
    if ($caller) {
        $caller =~ s/^([^:]*::[^:]*)::.*$/$1/;
    }
    my @c;
    my $t;
    my $is_col;
    my @tables = $self->tables;
    my $count=-1;
    for ( @tables) {
        $count++;
        my $name = $_->{"name"};
        undef $@;
        eval{
            my $open_name = $self->{org_table_names}->[$count];
           if ($caller && $caller =~ /^DBD::AnyData/) {
               $caller .= '::Statement' if $caller !~ /::Statement/;
               $t->{"$name"} = $caller->open_table($data, $open_name,
                                                   $createMode, $lockMode);
	   }
           else {
               $t->{"$name"} = $self->open_table($data, $open_name,
                                                 $createMode, $lockMode);
	   }

	};
        my $err = $t->{"$name"}->{errstr};
        return $self->do_err($err) if $err;
        return $self->do_err($@) if $@;
my @cnames;
for my $c(@{$t->{"$name"}->{"col_names"}}) {
  my $newc;
  if ($c =~ /^"/) {
 #    $c =~ s/^"(.+)"$/$1/;
     $newc = $c;
  }
  else {
#     $newc = lc $c;
     $newc = uc $c;
  }
   push @cnames, $newc;
   $self->{ORG_NAME}->{$newc}=$c;
}
my $col_nums;
my $i=0;
for (@cnames) {
  $col_nums->{$_} = $i++;
}
$t->{"$name"}->{"col_nums"}  = $col_nums; # upper cased
$t->{"$name"}->{"col_names"} = \@cnames;
#use mylibs; zwarn $t->{$name};
        my $tcols = $t->{"$name"}->col_names;
# @$tcols = map{lc $_} @$tcols ;
    ###z        @$tcols = map{$name.'.'.$_} @$tcols ;
        my @newcols;
        for (@$tcols) {
            next unless defined $_;
            my $ncol = $_;
            $ncol = $name.'.'.$ncol unless $ncol =~ /\./;
            push @newcols, $ncol;
	}
        @c = ( @c, @newcols );
    }
    my $all_cols = $self->{all_cols} || [];
    @$all_cols = (@$all_cols,@c);
    $self->{all_cols} = $all_cols;
    return SQL::Eval->new({'tables' => $t}), \@c;
}

sub verify_columns {
    my( $self, $eval, $all_cols )  = @_;
    $all_cols ||= [];
    my @tmp_cols  = @$all_cols;
#    my @tmp_cols  = map{lc $_} @$all_cols;
    my $usr_cols;
    my $cnum=0;
    my @tmpcols = $self->columns;

###z
#    for (@tmpcols) {
#        $_->{"table"} = lc $_->{"table"};
#    }
#use mylibs; print $self->command; zwarn \@tmpcols;
###z
    for my $c(@tmpcols) {
       if ($c->{"name"} eq '*' and defined $c->{"table"}) {
          return $self->do_err("Can't find table ". $c->{"table"})
              unless $eval->{"tables"}->{$c->{"table"}};
          my $tcols = $eval->{"tables"}->{$c->{"table"}}->col_names;
# @$tcols = map{lc $_} @$tcols ;
          return $self->do_err("Couldn't find column names!")
              unless $tcols and ref $tcols eq 'ARRAY' and @$tcols;
          for (@$tcols) {
              push @$usr_cols, SQL::Statement::Column->new( $_,
                                                            [$c->{"table"}]
                                                          );
	  }
       }
       else {
	  push @$usr_cols, SQL::Statement::Column->new( $c->{"name"},
                                                        [$c->{"table"}]
                                                      );
       }
    }
    $self->{"columns"} = $usr_cols;
    @tmpcols = map {$_->{name}} @$usr_cols;
#     @tmpcols = map {lc $_->{name}} @$usr_cols;
    my $fully_qualified_cols=[];

    my %col_exists   = map {$_=>1} @tmp_cols;

    my %short_exists = map {s/^([^.]*)\.(.*)/$1/; $2=>$1} @tmp_cols;
    my(%is_member,@duplicates,%is_duplicate);
    @duplicates = map {s/[^.]*\.(.*)/$1/; $_} @$all_cols;
    @duplicates = grep($is_member{$_}++, @duplicates);
    %is_duplicate = map { $_=>1} @duplicates;
    my $is_fully;
    my $i=-1;
    my $num_tables = $self->tables;
    for my $c(@tmpcols) {
       my($table,$col);
       if ($c =~ /(\S+)\.(\S+)/) {
           $table = $1;
           $col   = $2;
       }
       else {
       $i++;
       ($table,$col) = ( $usr_cols->[$i]->{"table"},
                         $usr_cols->[$i]->{"name"}
                       );
       }
       next unless $col;
###new
       if (ref $table eq 'SQL::Statement::Table') {
          $table = $table->name;
       }
###endnew
#print "Content-type: text/html\n\n"; print $self->command; print "$col!!!<p>";
       if ( $col eq '*' and $num_tables == 1) {
          $table ||= $self->tables->[0]->{"name"};
          if (ref $table eq 'SQL::Statement::Table') {
            $table = $table->name;
          }
          my @table_names = $self->tables;
          my $tcols = $eval->{"tables"}->{"$table"}->col_names;
# @$tcols = map{lc $_} @$tcols ;
          return $self->do_err("Couldn't find column names!")
              unless $tcols and ref $tcols eq 'ARRAY' and @$tcols;
          for (@$tcols) {
              push @{ $self->{"columns"} },
                    SQL::Statement::Column->new($_,\@table_names);
          }
          $fully_qualified_cols = $tcols;
          my @newcols;
	  for (@{$self->{"columns"}}) {
              push @newcols,$_ unless $_->{"name"} eq '*';
	  }
          $self->{"columns"} = \@newcols;
       }
       elsif ( $col eq '*' and defined $table) {
              $table = $table->name if ref $table eq 'SQL::Statement::Table';
              my $tcols = $eval->{"tables"}->{"$table"}->col_names;
# @$tcols = map{lc $_} @$tcols ;
          return $self->do_err("Couldn't find column names!")
              unless $tcols and ref $tcols eq 'ARRAY' and @$tcols;
              for (@$tcols) {
                  push @{ $self->{"columns"} },
                        SQL::Statement::Column->new($_,[$table]);
              }
              @{$fully_qualified_cols} = (@{$fully_qualified_cols}, @$tcols);
       }
       elsif ( $col eq '*' and $num_tables > 1) {
          my @table_names = $self->tables;
          for my $table(@table_names) {
              $table = $table->name if ref $table eq 'SQL::Statement::Table';
              my $tcols = $eval->{"tables"}->{"$table"}->col_names;
# @$tcols = map{lc $_} @$tcols ;
          return $self->do_err("Couldn't find column names!")
              unless $tcols and ref $tcols eq 'ARRAY' and @$tcols;
              for (@$tcols) {
                  push @{ $self->{"columns"} },
                        SQL::Statement::Column->new($_,[$table]);
              }
              @{$fully_qualified_cols} = (@{$fully_qualified_cols}, @$tcols);
              my @newcols;
  	      for (@{$self->{"columns"}}) {
                  push @newcols,$_ unless $_->{"name"} eq '*';
	      }
              $self->{"columns"} = \@newcols;
	  }
       }
       else {
#print "[$c~$col]\n";
#use mylibs; zwarn \%col_exists;
           if (!$table) {
               return $self->do_err("Ambiguous column name '$c'")
                   if $is_duplicate{$c};
               return $self->do_err("No such column '$c'")
                      unless $short_exists{"$c"} or ($c !~ /^"/ and $short_exists{"\U$c"});
               $table = $short_exists{"$c"};
               $col   = $c;
           }
           else {
	     if ($self->command eq 'SELECT') {
#print "$table.$col\n";
#if ($col_exists{qq/$table."/.$self->{ORG_NAME}->{$col}.qq/"/}) {
#    $col = q/"/.$self->{ORG_NAME}->{$col}.q/"/;
#} 
#print qq/$table."$col"/;
# use mylibs; zwarn $self->{ORG_NAME};
	     }
#use mylibs; zwarn \%col_exists;
#print "<$table . $col>";
               return $self->do_err("No such column '$table.$col'")
                     unless $col_exists{"$table.$col"}
                      or $col_exists{"\L$table.".$col};
;#                        or $col_exists{qq/$table."/.$self->{ORG_NAME}->{$col}.qq/"/}
;
           }
           next if $is_fully->{"$table.$col"};
####
  $self->{"columns"}->[$i]->{"name"} = $col;
####
           $self->{"columns"}->[$i]->{"table"} = $table;
           push @$fully_qualified_cols, "$table.$col";
           $is_fully->{"$table.$col"}++;
       }
       if ( $col eq '*' and defined $table) {
              my @newcols;
  	      for (@{$self->{"columns"}}) {
                  push @newcols,$_ unless $_->{"name"} eq '*';
	      }
              $self->{"columns"} = \@newcols;
       }
    }
#use mylibs; zwarn $fully_qualified_cols;

    return $fully_qualified_cols;
}


sub distinct {
    my $self = shift;
    return 1 if $self->{"set_quantifier"}
       and $self->{"set_quantifier"} eq 'DISTINCT';
    return 0;
}

sub command { shift->{"command"} }

sub params {
    my $self = shift;
    my $val_num = shift;
    if (!$self->{"params"}) { return 0; }
    if (defined $val_num) {
        return $self->{"params"}->[$val_num];
    }
    if (wantarray) {
        return @{$self->{"params"}};
    }
    else {
        return scalar @{ $self->{"params"} };
    }

}
sub row_values {
    my $self = shift;
    my $val_num = shift;
    if (!$self->{"values"}) { return 0; }
    if (defined $val_num) {
        #        return $self->{"values"}->[$val_num]->{"value"};
        return $self->{"values"}->[$val_num];
    }
    if (wantarray) {
        return map{$_->{"value"} } @{$self->{"values"}};
    }
    else {
        return scalar @{ $self->{"values"} };
    }

}

sub get_row_value {
    my($self,$structure,$eval,$rowhash) = @_;
    my $type = $structure->{"type"};
    $type = $structure->{"name"} if $type and $type eq 'function';
    return undef unless $type;
    for ( $type ) {
        /string|number|null/      &&do { return $structure->{"value"} };
        /column/                  &&do {
                my $val = $structure->{"value"};
                my $tbl;
 		    if ($val =~ /^(.+)\.(.+)$/ ) {
                      ($tbl,$val) = ($1,$2);
		    }
                if ($self->{"join"}) {
                    # $tbl = 'shared' if $eval->is_shared($val);
                    $tbl ||= $self->colname2table($val);
                    $val = $tbl . "$dlm$val";
		}
                return $rowhash->{"$val"};
	};
        /placeholder/             &&do {
           my $val;
           if ($self->{"join"}) {
               $val = $self->params($arg_num);
             }
           else {
                $val = $eval->param($arg_num);  
           }

         #my @params = $self->params;
         #die "@params";
         #print "$val ~ $arg_num\n";
                $arg_num++;
#print "<$arg_num>";
                return $val;
        };
        /str_concat/              &&do {
                my $valstr ='';
        	for (@{ $structure->{"value"} }) {
                    my $newval = $self->get_row_value($_,$eval,$rowhash);
                    return undef unless defined $newval;
                    $valstr .= $newval;
	        }
                return $valstr;
        };
        /numeric_exp/             &&do {
           my @vals = @{ $structure->{"vals"} };
           my $str  = $structure->{"str"};
           for my $i(0..$#vals) {
#	     use mylibs; zwarn $rowhash;
               my $val = $self->get_row_value($vals[$i],$eval,$rowhash);
               return $self->do_err(
                   qq{Bad numeric expression '$vals[$i]->{"value"}'!}
#               ) unless defined $val and $val =~ $numexp;
               ) unless defined $val and is_number($val);
               $str =~ s/\?$i\?/$val/;
	   }
           $str =~ s/\s//g;
           $str =~ s/^([\)\(+\-\*\/0-9]+)$/$1/; # untaint
           return eval $str;
        };

#z      my $vtype = $structure->{"value"}->{"type"};
        my $vtype = $structure->{"type"};
#z

        my $value = $structure->{"value"}->{"value"};
        $value = $self->get_row_value($structure->{"value"},$eval,$rowhash)
               if $vtype eq 'function';
        /UPPER/                   &&do {
                return uc $value;
        };
        /LOWER/                   &&do {
                return lc $value;
        };
        /TRIM/                    &&do {
                my $trim_char = $structure->{"trim_char"} || ' ';
                my $trim_spec = $structure->{"trim_spec"} || 'BOTH';
                $trim_char = quotemeta($trim_char);
                if ($trim_spec =~ /LEADING|BOTH/ ) {
                    $value =~ s/^$trim_char+(.*)$/$1/;
		}
                if ($trim_spec =~ /TRAILING|BOTH/ ) {
                    $value =~ s/^(.*[^$trim_char])$trim_char+$/$1/;
		}
                return $value;
            };
        /SUBSTRING/                   &&do {
                my $start  = $structure->{"start"}->{"value"} || 1;
                my $offset = $structure->{"length"}->{"value"} || length $value;
                $value ||= '';
                return substr($value,$start-1,$offset)
                   if length $value >= $start-2+$offset;
        };
    }
}

sub columns {
    my $self = shift;
    my $col_num = shift;
    if (!$self->{"columns"}) { return 0; }
    if (defined $col_num ) {
        return $self->{"columns"}->[$col_num];
    }
    if (wantarray) {
        return @{$self->{"columns"}};
    }
    else {
        return scalar @{ $self->{"columns"} };
    }

}
sub colname2table {
    my $self = shift;
    my $col_name = shift;
    return undef unless defined $col_name;
    my $found_table;
    for my $full_col(@{$self->{all_cols}}) {
        my($table,$col) = $full_col =~ /^(.+)\.(.+)$/;
        next unless $col eq $col_name;
        $found_table = $table;
        last;
    }
    return $found_table;
}

sub colname2tableOLD {
    my $self = shift;
    my $col_name = shift;
    return undef unless defined $col_name;
    my $found;
    my $table;
    my $name;
    my @cur_cols;
print "<$col_name>";
    for my $c(@{$self->{"columns"}}) {
         $name  = $c->{"name"};
print "[$name]\n";
         $table = $c->{"table"};
         push @cur_cols,$name;
         next unless $name eq $col_name;
         $found++;
         last;
    }
    #print "$table - $name - $col_name\n";
    undef $table unless $found;
    return $table;
    #print "$col_name $table @cur_cols\n";
    if ($found and $found > 1) {
        for (@{$self->{"join"}->{"keycols"}}) {
            return 'shared' if /^$col_name$/;
        }
        # return $self->do_err("Ambiguous column name '$col_name'!");
    }

    #    print "$table ~ $col_name ~ @cur_cols\n";
    return $table;
}

sub verify_order_cols {
    my $self  = shift;
    my $table = shift;
    return unless $self->{"sort_spec_list"};
    my @ocols = $self->order;
    my @tcols = @{$table->col_names};
    my @n_ocols;
#die "@ocols";
#use mylibs; zwarn \@ocols; exit;
    for my $colnum(0..$#ocols) {
        my $col = $self->order($colnum);
#        if (!defined $col->table and defined $self->columns($colnum)) {
        if (!defined $col->table ) {
            my $cname = $ocols[$colnum]->{col}->name;
            my $tname = $self->colname2table($cname);
            return $self->do_err("No such column '$cname'.") unless $tname;
            $self->{"sort_spec_list"}->[$colnum]->{"col"}->{"table"}=$tname;
            push @n_ocols,$tname;
        }
    }
#    for (@n_ocols) {
#        die "$_" unless colname2table($_);
#    }
#use mylibs; zwarn $self->{"sort_spec_list"}; exit;
}

sub order {
    my $self = shift;
    my $o_num = shift;
    if (!defined $self->{"sort_spec_list"}) { return (); }
    if (defined $o_num) {
        return $self->{"sort_spec_list"}->[$o_num];
    }
    if (wantarray) {
        return @{$self->{"sort_spec_list"}};
    }
    else {
        return scalar @{ $self->{"sort_spec_list"} };
    }

}
sub tables {
    my $self = shift;
    my $table_num = shift;
    if (defined $table_num) {
        return $self->{"tables"}->[$table_num];
    }
    if (wantarray) {
        return @{ $self->{"tables"} };
    }
    else {
#        return scalar @{ $self->{"table_names"} };
        return scalar @{ $self->{"tables"} };
    }

}
sub order_joins {
    my $self = shift;
    my $links = shift;
    my @new_keycols;
    for (@$links) {
       push @new_keycols, $self->colname2table($_) . ".$_";
    }
    my @tmp = @new_keycols;
    @tmp = map { s/\./$dlm/g; $_ } @tmp;
    $self->{"join"}->{"keycols"}  = \@tmp;
    @$links = map { s/^(.+)\..*$/$1/; $_; } @new_keycols;
    my @all_tables;
    my %relations;
    my %is_table;
    while (@$links) {
        my $t1 = shift @$links;
        my $t2 = shift @$links;
        return undef unless defined $t1 and defined $t2;
        push @all_tables, $t1 unless $is_table{$t1}++;
        push @all_tables, $t2 unless $is_table{$t2}++;
        $relations{$t1}{$t2}++;
        $relations{$t2}{$t1}++;
    }
    my @tables = @all_tables;
    my @order = shift @tables;
    my %is_ordered = ( $order[0] => 1 );
    my %visited;
    while(@tables) {
        my $t = shift @tables;
        my @rels = keys %{$relations{$t}};
        for my $t2(@rels) {
            next unless $is_ordered{$t2};
            push @order, $t;
            $is_ordered{$t}++;
            last;
        }
        if (!$is_ordered{$t}) {
            push @tables, $t if $visited{$t}++ < @all_tables;
        }
    }
    return $self->do_err(
        "Unconnected tables in equijoin statement!"
    ) if @order < @all_tables;
    $self->{"join"}->{"table_order"} = \@order;
    return \@order;
}

sub do_err {
    my $self = shift;
    my $err  = shift;
    my $errtype  = shift;
    my @c = caller 6;
    #$err = "[" . $self->{"original_string"} . "]\n$err\n\n";
    #    $err = "$err\n\n";
    my $prog = $c[1];
    my $line = $c[2];
    $prog = defined($prog) ? " called from $prog" : '';
    $prog .= defined($line) ? " at $line" : '';
    $err =  "\nExecution ERROR: $err$prog.\n\n";

    $self->{"errstr"} = $err;
    warn $err if $self->{"PrintError"};
    die "$err" if $self->{"RaiseError"};
    return undef;
}

sub errstr {
    my $self = shift;
    $self->{"errstr"};
}

sub where {
    my $self = shift;
    return undef unless $self->{"where_clause"};
   $warg_num = 0;
    return SQL::Statement::Op->new(
        $self->{"where_clause"},
        $self->{"tables"},
    );
}

sub where_hash {
    my $self = shift;
    return $self->{where_clause};
}


package SQL::Statement::Op;

sub new {
    my($class,$wclause,$tables) = @_;
    if (ref $tables->[0]) {
        @$tables = map {$_->name} @$tables;
    }
    my $self = {};
    $self->{"op"}   = $wclause->{"op"};
    $self->{"neg"}  = $wclause->{"neg"};
    $self->{"arg1"} = get_pred( $wclause->{"arg1"}, $tables );
    $self->{"arg2"} = get_pred( $wclause->{"arg2"}, $tables );
    return bless $self, $class;
}
sub get_pred {
    my $arg    = shift;
    my $tables = shift;
    if (defined $arg->{type}) {
        if ( $arg->{type} eq 'column') {
            return SQL::Statement::Column->new( $arg->{value}, $tables );
        }
        elsif ( $arg->{type} eq 'placeholder') {
            return SQL::Statement::Param->new( $main::warg_num++ );
        }
        else {
            return $arg->{value};
        }
    }
    else {
        return SQL::Statement::Op->new( $arg, $tables );
    }
}
sub op {
    my $self = shift;
    return $self->{"op"};
}
sub arg1 {
    my $self = shift;
    return $self->{"arg1"};
}
sub arg2 {
    my $self = shift;
    return $self->{"arg2"};
}
sub neg {
    my $self = shift;
    return $self->{"neg"};
}


package SQL::Statement::TempTable;

sub new {
    my $class      = shift;
    my $name       = shift;
    my $col_names  = shift;
    my $table_cols = shift;
    my $table      = shift;
    my $col_nums;
    for my $i(0..scalar @$col_names -1) {
      $col_names->[$i]= uc $col_names->[$i];
      $col_nums->{"$col_names->[$i]"}=$i;
    }
    my @display_order = map { $col_nums->{$_} } @$table_cols;
    my $self = {
        col_names  => $col_names,
        table_cols => \@display_order,
        col_nums   => $col_nums,
        table      => $table,
        NAME       => $name,
    };
    # use mylibs; zwarn $self; exit;
    return bless $self, $class;
}
sub is_shared {my($s,$colname)=@_;return $s->{"is_shared"}->{"$colname"}}
sub col_nums { shift->{"col_nums"} }
sub col_names { shift->{"col_names"} }
sub column_num  { 
    my($s,$col) = @_;
    my $new_col = $s->{"col_nums"}->{"$col"};
    if (! defined $new_col) {
        my @tmp = split '~',$col;
        $new_col = lc($tmp[0]) . '~' . uc($tmp[1]);
        $new_col = $s->{"col_nums"}->{"$new_col"};
    }
    return $new_col
}
sub fetch_row { my $s=shift; return shift @{ $s->{"table"} } }


package SQL::Statement::Order;

sub new ($$) {
    my $proto = shift;
    my $self = {@_};
    bless($self, (ref($proto) || $proto));
}
sub table ($) { shift->{'col'}->table(); }
sub column ($) { shift->{'col'}->name(); }
sub desc ($) { shift->{'desc'}; }


package SQL::Statement::Limit;

sub new ($$) {
    my $proto = shift;
    my $self  = shift;
    bless($self, (ref($proto) || $proto));
}
sub limit ($) { shift->{'limit'}; }
sub offset ($) { shift->{'offset'}; }

package SQL::Statement::Param;

sub new {
    my $class = shift;
    my $num   = shift;
    my $self = { 'num' => $num };
    return bless $self, $class;
}

sub num ($) { shift->{'num'}; }


package SQL::Statement::Column;

sub new {
    my $class = shift;
    my $col_name = shift;
    my $tables = shift;
    my $table_name = $col_name;
    #my @c = caller 0; print $c[2];
    if (ref $col_name eq 'HASH') {
        $tables   = [ $col_name->{"table"} ];
        $col_name = $col_name->{"column"}  ;
    }
    # print " $col_name !\n";
    my $num_tables = scalar @{ $tables };
    if ($table_name && (
           $table_name =~ /^(".+")\.(.*)$/
        or $table_name =~ /^([^.]*)\.(.*)$/
        )) {
            $table_name = $1;
            $col_name = $2;
    }
    elsif ($num_tables == 1) {
        $table_name = $tables->[0];
    }
    else {
        undef $table_name;
    }
    my $self = {
        name => $col_name,
        table => $table_name,
    };
    return bless $self, $class;
}

sub name  { shift->{"name"} }
sub table { shift->{"table"} }

package SQL::Statement::Table;

sub new {
    my $class = shift;
    my $table_name = shift;
    my $self = {
        name => $table_name,
    };
    return bless $self, $class;
}

sub name  { shift->{"name"} }
1;
__END__

=head1 NAME

SQL::Statement - SQL parsing and processing engine

=head1 SYNOPSIS

    require SQL::Statement;

    # Create a parser
    my($parser) = SQL::Parser->new('Ansi');

    # Parse an SQL statement
    $@ = '';
    my ($stmt) = eval {
        SQL::Statement->new("SELECT id, name FROM foo WHERE id > 1",
                            $parser);
    };
    if ($@) {
        die "Cannot parse statement: $@";
    }

    # Query the list of result columns;
    my $numColums = $stmt->columns();  # Scalar context
    my @columns = $stmt->columns();    # Array context
    # @columns now contains SQL::Statement::Column instances

    # Likewise, query the tables being used in the statement:
    my $numTables = $stmt->tables();   # Scalar context
    my @tables = $stmt->tables();      # Array context
    # @tables now contains SQL::Statement::Table instances

    # Query the WHERE clause; this will retrieve an
    # SQL::Statement::Op instance
    my $where = $stmt->where();

    # Evaluate the WHERE clause with concrete data, represented
    # by an SQL::Eval object
    my $result = $stmt->eval_where($eval);

    # Execute a statement:
    $stmt->execute($data, $params);


=head1 DESCRIPTION

For installing the module, see L<"INSTALLATION"> below.

At the moment this POD is lifted straight from Jochen
Wiedmann's SQL::Statement with the exception of the
section labeled L<"PURE PERL VERSION"> below which is
a must read.

The SQL::Statement module implements a small, abstract SQL engine. This
module is not usefull itself, but as a base class for deriving concrete
SQL engines. The implementation is designed to work fine with the
DBI driver DBD::CSV, thus probably not so well suited for a larger
environment, but I'd hope it is extendable without too much problems.

By parsing an SQL query you create an SQL::Statement instance. This
instance offers methods for retrieving syntax, for WHERE clause and
statement evaluation.

=head1 PURE PERL VERSION

This version is a pure perl version of Jochen's original SQL::Statement.  Eventually I will re-write the POD but for now I will document in this section the ways it differs from Jochen's version only and you can assume that things not mentioned in this section remain as described in the rest of this POD.

=head2 Dialect Files

In the ...SQL/Dialect directory are files that define the valid types, reserved words, and other features of the dialects.  Currently the ANSI dialect is available only for prepare() not execute() while the CSV and AnyData dialect support both prepare() and execute().

=head2 New flags

In addition to the dialect files, features of SQL::Statement can be defined by flags sent by subclasses in the call to new, for example:

   my $stmt = SQL::Statement->new($sql_str,$flags);

   my $stmt = SQL::Statement->new($sql_str, {text_numbers=>1});

=over

=item  dialect

 Dialect is one of 'ANSI', 'CSV', or 'AnyData'; the default is CSV,
 i.e. the behaviour of the original XS SQL::Statement.

=item  text_numbers

 If true, this allows texts that look like numbers (e.g. 2001-01-09
 or 15.3.2) to be sorted as text.  In the original version these
 were treated as numbers and threw warnings as well as failed to sort
 as text.  The default is false, i.e. the original behaviour.  The
 AnyData dialect sets this to true by default, i.e. it allows sorting
 of these kinds of columns.

=item alpha_compare

 If true this allows alphabetic comparison.  The original version would
 ignore SELECT statements with clauses like "WHERE col3 < 'c'".  The
 default is false, i.e. the original style.  The AnyData dialect sets
 this to true by default, i.e. it allows such comparisons.

=item LIMIT

 The LIMIT clause as described by Jochen below never actually made it
 into the execute() portion of his SQL::Statement, it is now supported.

=item RLIKE

 There is an experimental RLIKE operator similar to LIKE but takes a
 perl regular expression, e.g.

      SELECT * FROM foo WHERE bar RLIKE '^\s*Baz[^:]*:$'

 Currently this is only available in the AnyData dialect.

=back

=head2 It's Pure Perl

All items in the pod referring to yacc, C, bison, etc. are now only historical since this version has ported all of those portions into perl.

=head2 Creating a parser object

What's accepted as valid SQL, depends on the parser object. There is
a set of so-called features that the parsers may have or not. Usually
you start with a builtin parser:

    my $parser = SQL::Parser->new($name, [ \%attr ]);

Currently two parsers are builtin: The I<Ansi> parser implements a proper
subset of ANSI SQL. (At least I hope so. :-) The I<SQL::Statement> parser
is used by the DBD:CSV driver.

You can query or set individual features. Currently available are:

=over 8

=item create.type_blob

=item create.type_real

=item create.type_text

These enable the respective column types in a I<CREATE TABLE> clause.
They are all disabled in the I<Ansi> parser, but enabled in the
I<SQL::Statement> parser. Example:

=item select.join

This enables the use of multiple tables in a SELECT statement, for
example

  SELECT a.id, b.name FROM a, b WHERE a.id = b.id AND a.id = 2

=back

To enable or disable a feature, for example I<select.join>, use the
following:

  # Enable feature
  $parser->feature("select", "join", 1);
  # Disable feature
  $parser->feature("select", "join", 0);

Of course you can query features:

  # Query feature
  my $haveSelectJoin = $parser->feature("select", "join");

The C<new> method allows a shorthand for setting features. For example,
the following is equivalent to the I<SQL::Statement> parser:

  $parser = SQL::Statement->new('Ansi',
                                { 'create' => { 'type_text' => 1,
                                                'type_real' => 1,
                                                'type_blob' => 1 },
                                  'select' => { 'join' => 0 }});


=head2 Parsing a query

A statement can be parsed with

    my $stmt = SQL::Statement->new($query, $parser);

In case of syntax errors or other problems, the method throws a Perl
exception. Thus, if you want to catch exceptions, the above becomes

    $@ = '';
    my $stmt = eval { SQL::Statement->new($query, $parser) };
    if ($@) { print "An error occurred: $@"; }

The accepted SQL syntax is restricted, though easily extendable. See
L<SQL syntax> below. See L<Creating a parser object> above.


=head2 Retrieving query information

The following methods can be used to obtain information about a
query:

=over 8

=item command

Returns the SQL command, currently one of I<SELECT>, I<INSERT>, I<UPDATE>,
I<DELETE>, I<CREATE> or I<DROP>, the last two referring to
I<CREATE TABLE> and I<DROP TABLE>. See L<SQL syntax> below. Example:

    my $command = $stmt->command();

=item columns

    my $numColumns = $stmt->columns();  # Scalar context
    my @columnList = $stmt->columns();  # Array context
    my($col1, $col2) = ($stmt->columns(0), $stmt->columns(1));

This method is used to retrieve column lists. The meaning depends on
the query command:

    SELECT $col1, $col2, ... $colN FROM $table WHERE ...
    UPDATE $table SET $col1 = $val1, $col2 = $val2, ...
        $colN = $valN WHERE ...
    INSERT INTO $table ($col1, $col2, ..., $colN) VALUES (...)

When used without arguments, the method returns a list of the
columns $col1, $col2, ..., $colN, you may alternatively use a
column number as argument. Note that the column list may be
empty, like in

    INSERT INTO $table VALUES (...)

and in I<CREATE> or I<DROP> statements.

But what does "returning a column" mean? It is returning an
SQL::Statement::Column instance, a class that implements the
methods C<table> and C<name>, both returning the respective
scalar. For example, consider the following statements:

    INSERT INTO foo (bar) VALUES (1)
    SELECT bar FROM foo WHERE ...
    SELECT foo.bar FROM foo WHERE ...

In all these cases exactly one column instance would be returned
with

    $col->name() eq 'bar'
    $col->table() eq 'foo'

=item tables

    my $tableNum = $stmt->tables();  # Scalar context
    my @tables = $stmt->tables();    # Array context
    my($table1, $table2) = ($stmt->tables(0), $stmt->tables(1));

Similar to C<columns>, this method returns instances of
C<SQL::Statement::Table>.  For I<UPDATE>, I<DELETE>, I<INSERT>,
I<CREATE> and I<DROP>, a single table will always be returned.
I<SELECT> statements can return more than one table, in case
of joins. Table objects offer a single method, C<name> which

returns the table name.

=item params

    my $paramNum = $stmt->params();  # Scalar context
    my @params = $stmt->params();    # Array context
    my($p1, $p2) = ($stmt->params(0), $stmt->params(1));

The C<params> method returns information about the input parameters
used in a statement. For example, consider the following:

    INSERT INTO foo VALUES (?, ?)

This would return two instances of SQL::Statement::Param. Param objects
implement a single method, C<$param->num()>, which retrieves the
parameter number. (0 and 1, in the above example). As of now, not very
usefull ... :-)

=item row_values

    my $rowValueNum = $stmt->row_values(); # Scalar context
    my @rowValues = $stmt->row_values();   # Array context
    my($rval1, $rval2) = ($stmt->row_values(0),
                          $stmt->row_values(1));

This method is used for statements like

    UPDATE $table SET $col1 = $val1, $col2 = $val2, ...
        $colN = $valN WHERE ...
    INSERT INTO $table (...) VALUES ($val1, $val2, ..., $valN)

to read the values $val1, $val2, ... $valN. It returns scalar values
or SQL::Statement::Param instances.

=item order

    my $orderNum = $stmt->order();   # Scalar context
    my @order = $stmt->order();      # Array context
    my($o1, $o2) = ($stmt->order(0), $stmt->order(1));

In I<SELECT> statements you can use this for looking at the ORDER
clause. Example:

    SELECT * FROM FOO ORDER BY id DESC, name

In this case, C<order> could return 2 instances of SQL::Statement::Order.
You can use the methods C<$o-E<gt>table()>, C<$o-E<gt>column()> and
C<$o-E<gt>desc()> to examine the order object.

=item limit

    my $l = $stmt->limit();
    if ($l) {
      my $offset = $l->offset();
      my $limit = $l->limit();
    }

In a SELECT statement you can use a C<LIMIT> clause to implement
cursoring:

    SELECT * FROM FOO LIMIT 5
    SELECT * FROM FOO LIMIT 5, 5
    SELECT * FROM FOO LIMIT 10, 5

These three statements would retrieve the rows 0..4, 5..9, 10..14
of the table FOO, respectively. If no C<LIMIT> clause is used, then
the method C<$stmt-E<gt>limit> returns undef. Otherwise it returns
an instance of SQL::Statement::Limit. This object has the methods
C<offset> and C<limit> to retrieve the index of the first row and
the maximum number of rows, respectively.

=item where

    my $where = $stmt->where();

This method is used to examine the syntax tree of the C<WHERE> clause.
It returns undef (if no WHERE clause was used) or an instance of
SQL::Statement::Op. The Op instance offers 4 methods:

=over 12

=item op

returns the operator, one of C<AND>, C<OR>, C<=>, C<E<lt>E<gt>>, C<E<gt>=>,
C<E<gt>>, C<E<lt>=>, C<E<lt>>, C<LIKE>, C<CLIKE> or C<IS>.

=item arg1

=item arg2

returns the left-hand and right-hand sides of the operator. This can be a
scalar value, an SQL::Statement::Param object or yet another
SQL::Statement::Op instance.

=item neg

returns a TRUE value, if the operation result must be negated after
evalution.

=back

To evaluate the I<WHERE> clause, fetch the topmost Op instance with
the C<where> method. Then evaluate the left-hand and right-hand side
of the operation, perhaps recursively. Once that is done, apply the
operator and finally negate the result, if required.

=back

To illustrate the above, consider the following WHERE clause:

    WHERE NOT (id > 2 AND name = 'joe') OR name IS NULL

We can represent this clause by the following tree:

              (id > 2)   (name = 'joe')
                     \   /
          NOT         AND
                         \      (name IS NULL)
                          \    /
                            OR

Thus the WHERE clause would return an SQL::Statement::Op instance with
the op() field set to 'OR'. The arg2() field would return another
SQL::Statement::Op instance with arg1() being the SQL::Statement::Column
instance representing id, the arg2() field containing the value undef
(NULL) and the op() field being 'IS'.

The arg1() field of the topmost Op instance would return an Op instance
with op() eq 'AND' and neg() returning TRUE. The arg1() and arg2()
fields would be Op's representing "id > 2" and "name = 'joe'".

Of course there's a ready-for-use method for WHERE clause evaluation:


=head2 Evaluating a WHERE clause

The WHERE clause evaluation depends on an object being used for
fetching parameter and column values. Usually this can be an
SQL::Eval object, but in fact it can be any object that supplies
the methods

    $val = $eval->param($paramNum);
    $val = $eval->column($table, $column);

See L<SQL::Eval> for a detailed description of these methods.
Once you have such an object, you can call a

    $match = $stmt->eval_where($eval);


=head2 Evaluating queries

So far all methods have been concrete. However, the interface for
executing and evaluating queries is abstract. That means, for using
them you have to derive a subclass from SQL::Statement that implements
at least certain missing methods and/or overwrites others. See the
C<test.pl> script for an example subclass.

Something that all methods have in common is that they simply throw
a Perl exception in case of errors.


=over 8

=item execute

After creating a statement, you must execute it by calling the C<execute>
method. Usually you put an eval statement around this call:

    $@ = '';
    my $rows = eval { $self->execute($data); };
    if ($@) { die "An error occurred!"; }

In case of success the method returns the number of affected rows or -1,
if unknown. Additionally it sets the attributes

    $self->{'NUM_OF_FIELDS'}
    $self->{'NUM_OF_ROWS'}
    $self->{'data'}

the latter being an array ref of result rows. The argument $data is for
private use by concrete subclasses and will be passed through to all
methods. (It is intentionally not implemented as attribute: Otherwise
we might well become self referencing data structures which could
prevent garbage collection.)


=item CREATE

=item DROP

=item INSERT

=item UPDATE

=item DELETE

=item SELECT

Called by C<execute> for doing the real work. Usually they create an
SQL::Eval object by calling C<$self-E<gt>open_tables()>, call
C<$self-E<gt>verify_columns()> and then do their job. Finally they return
the triple

    ($self->{'NUM_OF_ROWS'}, $self->{'NUM_OF_FIELDS'},
     $self->{'data'})

so that execute can setup these attributes. Example:

    ($self->{'NUM_OF_ROWS'}, $self->{'NUM_OF_FIELDS'},
     $self->{'data'}) = $self->SELECT($data);


=item verify_columns

Called for verifying the row names that are used in the statement.
Example:

    $self->verify_columns($eval, $data);


=item open_tables

Called for creating an SQL::Eval object. In fact what it returns
doesn't need to be derived from SQL::Eval, it's completely sufficient
to implement the same interface of methods. See L<SQL::Eval> for
details. The arguments C<$data>, C<$createMode> and C<$lockMode>
are corresponding to those of SQL::Eval::Table::open_table and
usually passed through. Example:

    my $eval = $self->open_tables($data, $createMode, $lockMode);

The eval object can be used for calling C<$self->verify_columns> or
C<$self->eval_where>.

=item open_table

This method is completely abstract and *must* be implemented by subclasses.
The default implementation of C<$self->open_tables> calls this method for
any table used by the statement. See the C<test.pl> script for an example
of imlplementing a subclass.

=back


=head1 SQL syntax

The SQL::Statement module is far away from ANSI SQL or something similar,
it is designed for implementing the DBD::CSV module. See L<DBD::CSV(3)>.

I do not want to give a formal grammar here, more an informal
description: Read the statement definition in sql_yacc.y, if you need
something precise.

The main lexical elements of the grammar are:

=over 8

=item Integers

=item Reals

Syntax obvious

=item Strings

Surrounded by either single or double quotes; some characters need to
be escaped with a backslash, in particular the backslash itself (\\),
the NUL byte (\0), Line feeds (\n), Carriage return (\r), and the
quotes (\' or \").

=item Parameters

Parameters represent scalar values, like Integers, Reals and Strings
do. However, their values are read inside Execute() and not inside
Prepare(). Parameters are represented by question marks (?).

=item Identifiers

Identifiers are table or column names. Syntactically they consist of
alphabetic characters, followed by an arbitrary number of alphanumeric
characters. Identifiers like SELECT, INSERT, INTO, ORDER, BY, WHERE,
... are forbidden and reserved for other tokens.

=back

What it offers is the following:

=head2 CREATE

This is the CREATE TABLE command:

    CREATE TABLE $table ( $col1 $type1, ..., $colN $typeN,
                          [ PRIMARY KEY ($col1, ... $colM) ] )

The column names are $col1, ... $colN. The column types can be
C<INTEGER>, C<CHAR(n)>, C<VARCHAR(n)>, C<REAL> or C<BLOB>. These
types are currently completely ignored. So is the (optional)
C<PRIMARY KEY> clause.

=head2 DROP

Very simple:

    DROP TABLE $table

=head2 INSERT

This can be

    INSERT INTO $table [ ( $col1, ..., $colN ) ]
        VALUES ( $val1, ... $valN )

=head2 DELETE

    DELETE FROM $table [ WHERE $where_clause ]

See L<SELECT> below for a decsription of $where_clause

=head2 UPDATE

    UPDATE $table SET $col1 = $val1, ... $colN = $valN
        [ WHERE $where_clause ]

See L<SELECT> below for a decsription of $where_clause

=head2 SELECT

    SELECT [DISTINCT] $col1, ... $colN FROM $table
        [ WHERE $where_clause ] [ ORDER BY $ocol1, ... $ocolM ]

The $where_clause is based on boolean expressions of the form
$val1 $op $val2, with $op being one of '=', '<>', '>', '<', '>=',
'<=', 'LIKE', 'CLIKE' or IS. You may use OR, AND and brackets to combine
such boolean expressions or NOT to negate them.


=head1 INSTALLATION

For the moment, just unpack the tarball in a private directory.  For the moment, I suggest this be somewhere other than where you store your current SQL::Statement and you use this version by a "use lib" referencing the private directory where you unpack it.

There's no Makefile at this time.


=head1 INTERNALS

Internally the module is splitted into three parts:


=head2 Perl-independent C part

This part, contained in the files C<sql_yacc.y>, C<sql_data.h>,
C<sql_data.c> and C<sql_op.c>, is completely independent from Perl.
It might well be used from within another script language, Tcl say,
or from a true C application.

You probably ask, why Perl independence? Well, first of all, I
think this is a valuable target in itself. But the main reason was
the impossibility to use the Perl headers inside bison generated
code. The Perl headers export almost the complete Yacc interface
to XS, for whatever reason, thus redefining constants and structures
created by your own bison code. :-(


=head2 Perl-dependent C part

This is contained in C<Statement.xs>. The both C parts communicate via
a C structure sql_stmt_t. In fact, an SQL::Statement object is nothing
else than a pointer to such a structure. The XS calls columns(), Table(),
where(), ... do nothing more than fetching data from this structure
and converting it to Perl objects. See L<The sql_stmt_t structure>
below for details on the structure.


=head2 Perl part

Besides some stub functions for retrieving statement data, this is
mainly the query processing with the exception of WHERE clause
evaluation.


=head2 The sql_stmt_t structure

This structure is designed for optimal performance. A typical query
will be parsed with only 4 or 5 malloc() calls; in particular no
memory will be aquired for storing strings; only pointers into the
query string are used.

The statement stores its tokens in the values array. The array elements
are of type sql_val_t, a union, that can represent the most interesting
tokens; for example integers and reals are stored in the data.i and
data.d parts of the union, strings are stored in the data.str part,
columns in the data.col part and so on. Arrays are allocated in chunks
of 64 elements, thus a single malloc() will be usually sufficient for
allocating the complete array. Some types use pointers into the values
array: For example, operations are stored in an sql_op_t structure that
containes elements arg1 and arg2 which are pointers into the value
table, pointing to other operations or scalars. These pointers are
stored as indices, so that the array can be extended using realloc().

The sql_stmt_t structure contains other arrays: columns, tables,
rowvals, order, ... representing the data returned by the columns(),
tables(), row_values() and order() methods. All of these contain
pointers into the values array, again stored as integers.

Arrays are initialized with the _InitArray call in SQL_Statement_Prepare
and deallocated with _DestroyArray in SQL_Statement_Destroy. Array
elements are obtained by calling _AllocData, which returns an index.
The number -1 is used for errors or as a NULL value.


=head2 The WHERE clause evaluation

A WHERE clause is evaluated by calling SQL_Statement_EvalWhere(). This
function is in the Perl independent part, but it needs the possibility
to retrieve data from the Perl part, for example column or parameter
values. These values are retrieved via callbacks, stored in the
sql_eval_t structure. The field stmt->evalData points to such a
structure. Of course the calling method can extend the sql_eval_t
structure (like eval_where in Statement.xs does) to include private data
not used by SQL_Statement_EvalWhere.


=head2 Features

Different parsers are implemented via the sql_parser_t structure. This
is mainly a set of yes/no flags. If you'd like to add features, do
the following:

First of all, extend the sql_parser_t structure. If your feature is
part of a certain statement, place it into the statements section,
for example "select.join". Otherwise choose a section like "misc"
or "general". (There's no particular for the section design, but
structure never hurts.)

Second, add your feature to sql_yacc.y. If your feature needs to
extend the lexer, do it like this:

    if (FEATURE(misc, myfeature) {
        /*  Scan your new symbols  */
        ...
    }

See the I<BOOL> symbol as an example.

If you need to extend the parser, do it like this:

    my_new_rule:
        /*  NULL, old behaviour, doesn't use my feature  */
        | my_feature
            { YFEATURE(misc, myfeature); }
    ;

Thus all parsers not having FEATURE(misc, myfeature) set will produce
a parse error here. Again, see the BOOL symbol for an example.

Third thing is to extend the builtin parsers. If they support your
feature, add a 1, otherwise a 0. Currently there are two builtin
parsers: The I<ansiParser> in sql_yacc.y and the sqlEvalParser in
Statement.xs.

Finally add support for your feature to the C<feature> method in
Statement.xs. That's it!


=head1 MULTITHREADING

The complete module code is reentrant. In particular the parser is
created with C<%pure_parser>. See L<bison(1)> for details on
reentrant parsers. That means, the module is ready for multithreading,
as long as you don't share handles between threads. Read-only handles,
for example parsers, can even be shared.

Statement handles cannot be shared among threads, at least not, if
you don't grant serialized access. Per-thread handles are always safe.


=head1 AUTHOR AND COPYRIGHT

The original version of this module is Copyright (C) 1998 by

    Jochen Wiedmann
    Am Eisteich 9
    72555 Metzingen
    Germany

    Email: joe@ispsoft.de
    Phone: +49 7123 14887

The current version is Copyright (c) 2001 by

    Jeff Zucker

    Email: jeff@vpservices.com

All rights reserved.

You may distribute this module under the terms of either the GNU
General Public License or the Artistic License, as specified in
the Perl README file.


=head1 SEE ALSO

L<DBI(3)>, L<DBD::CSV(3)>, L<DBD::AnyData>

=cut
