######################################################################
package SQL::Parser;
######################################################################
#
# This module is copyright (c), 2001,2002 by Jeff Zucker.
# All rights resered.
#
# It may be freely distributed under the same terms as Perl itself.
# See below for help and copyright information (search for SYNOPSIS).
#
######################################################################

use strict;
use warnings;
use vars qw($VERSION);
use constant FUNCTION_NAMES => join '|', qw(
    TRIM SUBSTRING UPPER LOWER TO_CHAR
);

$VERSION = '1.09';

BEGIN { if( $ENV{SQL_USER_DEFS} ) { require SQL::UserDefs; } }


#############################
# PUBLIC METHODS
#############################

sub new {
    my $class   = shift;
    my $dialect = shift || 'ANSI';
    $dialect = 'ANSI'    if uc $dialect eq 'ANSI';
    $dialect = 'AnyData' if uc $dialect eq 'ANYDATA' or uc $dialect eq 'CSV';
#    $dialect = 'CSV'     if uc $dialect eq 'CSV';
    if ($dialect eq 'SQL::Eval') {
       $dialect = 'AnyData';
    }
    my $flags  = shift || {};
    $flags->{"dialect"}      = $dialect;
    $flags->{"PrintError"}   = 1 unless defined $flags->{"PrintError"};
    my $self = bless_me($class,$flags);
    $self->dialect( $self->{"dialect"} );
    $self->set_feature_flags($self->{"select"},$self->{"create"});
    return bless $self,$class;
}

sub parse {
    my $self = shift;
    my $sql = shift;
#printf "<%s>", $self->{dialect_set};
    $self->dialect( $self->{"dialect"} )  unless $self->{"dialect_set"};
    $sql =~ s/^\s+//;
    $sql =~ s/\s+$//;
    $self->{"struct"} = {};
    $self->{"tmp"} = {};
    $self->{"original_string"} = $sql;
    $self->{struct}->{"original_string"} = $sql;

    ################################################################
    #
    # COMMENTS

    # C-STYLE
    #
    my $comment_re = $self->{"comment_re"} || '(\/\*.*?\*\/)';
    $self->{"comment_re"} = $comment_re;
    my $starts_with_comment;
    if ($sql =~ /^\s*$comment_re(.*)$/s) {
       $self->{"comment"} = $1;
       $sql = $2;
       $starts_with_comment=1;
    }
    # SQL STYLE
    #
    if ($sql =~ /^\s*--(.*)(\n|$)/) {
       $self->{"comment"} = $1;
       return 1;
    }
    ################################################################

    $sql = $self->clean_sql($sql);
    my($com) = $sql =~ /^\s*(\S+)\s+/s ;
    if (!$com) {
        return 1 if $starts_with_comment;
        return $self->do_err("Incomplete statement!");
    }
    $com = uc $com;
    if ($self->{"opts"}->{"valid_commands"}->{$com}) {
        #print "<$sql>\n";
        my $rv = $self->$com($sql);
        delete $self->{"struct"}->{"literals"};
#        return $self->do_err("No table names found!")
#               unless $self->{"struct"}->{"table_names"};
        return $self->do_err("No command found!")
               unless $self->{"struct"}->{"command"};
        if ( $self->{"struct"}->{join}
         and scalar keys %{$self->{"struct"}->{join}}==0
         ) {
            delete $self->{"struct"}->{join};
	}
        $self->replace_quoted_ids();
#print "<@{$self->{struct}->{table_names}}>";
	for (@{$self->{struct}->{table_names}}) {
            push @{$self->{struct}->{org_table_names}},$_;
	}
#$self->{struct}->{org_table_names} = $self->{struct}->{table_names};
my @uTables = map {uc $_ } @{$self->{struct}->{table_names}};
$self->{struct}->{table_names} = \@uTables unless $com eq 'CREATE';
#print "[",@{$self->{struct}->{column_names}},"]\n" if $self->{struct}->{column_names} and $com eq 'SELECT';
	if ($self->{struct}->{column_names}) {
	for (@{$self->{struct}->{column_names}}) {
            push @{$self->{struct}->{org_col_names}},
                 $self->{struct}->{ORG_NAME}->{uc $_};
	}
	}
$self->{struct}->{join}->{table_order}
    = $self->{struct}->{table_names}
   if $self->{struct}->{join}->{table_order}
  and scalar(@{$self->{struct}->{join}->{table_order}}) == 0;
@{$self->{struct}->{join}->{keycols}}
     = map {uc $_ } @{$self->{struct}->{join}->{keycols}}
    if $self->{struct}->{join}->{keycols};
@{$self->{struct}->{join}->{shared_cols}}
    = map {uc $_ } @{$self->{struct}->{join}->{shared_cols}}
    if $self->{struct}->{join}->{shared_cols};
my @uCols = map {uc $_ } @{$self->{struct}->{column_names}};
$self->{struct}->{column_names} = \@uCols unless $com eq 'CREATE';
	if ($self->{original_string} =~ /Y\.\*/) {
#use mylibs; zwarn $self; exit;
	}
	if ($com eq 'SELECT') {
#use Data::Dumper;
#print Dumper $self->{struct}->{join};
#exit;
	}
        delete $self->{struct}->{join}
               if $self->{struct}->{join}
              and scalar keys %{$self->{struct}->{join}}==0;
        return $rv;
    } 
    else {
       $self->{struct}={};
       if ($ENV{SQL_USER_DEFS}) {
           return SQL::UserDefs::user_parse($self,$sql);
       }
       return $self->do_err("Command '$com' not recognized or not supported!");
    }
}

sub replace_quoted_ids {
    my $self = shift;
    my $id = shift;
    return $id unless $self->{struct}->{quoted_ids};
    if ($id) {
      if ($id =~ /^\?QI(\d+)\?$/) {
        return '"'.$self->{struct}->{quoted_ids}->[$1].'"';
      } 
      else {
	return $id;
      }
    }
    my @tables = @{$self->{struct}->{table_names}};
    for my $t(@tables) {
        if ($t =~ /^\?QI(.+)\?$/ ) {
            $t = '"'.$self->{struct}->{quoted_ids}->[$1].'"';
#            $t = $self->{struct}->{quoted_ids}->[$1];
        }
    }
    $self->{struct}->{table_names} = \@tables;
    delete $self->{struct}->{quoted_ids};
}

sub structure { shift->{"struct"} }
sub command { my $x = shift->{"struct"}->{command} || '' }

sub feature {
    my($self,$opt_class,$opt_name,$opt_value) = @_;
    if (defined $opt_value) {
        if ( $opt_class eq 'select' ) {
            $self->set_feature_flags( {"join"=>$opt_value} );
        }
        elsif ( $opt_class eq 'create' ) {
            $self->set_feature_flags( undef, {$opt_name=>$opt_value} );
        }
        else {
	  $self->{$opt_class}->{$opt_name} = $opt_value;
	} 
    }
    else {
        return $self->{"opts"}->{$opt_class}->{$opt_name};
    }
}

sub errstr  { shift->{"struct"}->{"errstr"} }

sub list {
    my $self = shift;
    my $com  = uc shift;
    return () if $com !~ /COMMANDS|RESERVED|TYPES|OPS|OPTIONS|DIALECTS/i;
    $com = 'valid_commands' if $com eq 'COMMANDS';
    $com = 'valid_comparison_operators' if $com eq 'OPS';
    $com = 'valid_data_types' if $com eq 'TYPES';
    $com = 'valid_options' if $com eq 'OPTIONS';
    $com = 'reserved_words' if $com eq 'RESERVED';
    $self->dialect( $self->{"dialect"} ) unless $self->{"dialect_set"};

    return sort keys %{ $self->{"opts"}->{$com} } unless $com eq 'DIALECTS';
    my $dDir = "SQL/Dialects";
    my @dialects;
    for my $dir(@INC) {
      local *D;

      if ( opendir(D,"$dir/$dDir")  ) {
          @dialects = grep /.*\.pm$/, readdir(D);
          last;
      } 
    }
    @dialects = map { s/\.pm$//; $_} @dialects;
    return @dialects;
}

sub dialect {
    my($self,$dialect) = @_;
    return $self->{"dialect"} unless $dialect;
    return $self->{"dialect"} if $self->{dialect_set};
    $self->{"opts"} = {};
    my $mod = "SQL/Dialects/$dialect.pm";
    undef $@;
    eval {
        require "$mod";
    };
    return $self->do_err($@) if $@;
    $mod =~ s/\.pm//;
    $mod =~ s"/"::"g;
    my @data = split /\n/, $mod->get_config;
    my $feature;
    for (@data) {
        chomp;
        s/^\s+//;
        s/\s+$//;
        next unless $_;
        if (/^\[(.*)\]$/i) {
            $feature = lc $1;
            $feature =~ s/\s+/_/g;
            next;
        }
        my $newopt = uc $_;
        $newopt =~ s/\s+/ /g;
        $self->{"opts"}->{$feature}->{$newopt} = 1;
    }
    $self->{"dialect"} = $dialect;
    $self->{"dialect_set"}++;
}

##################################################################
# SQL COMMANDS
##################################################################

####################################################
# DROP TABLE <table_name>
####################################################
sub DROP {
    my $self = shift;
    my $stmt = shift;
    my $table_name;
    $self->{"struct"}->{"command"}     = 'DROP';
    if ($stmt =~ /^\s*DROP\s+TABLE\s+IF\s+EXISTS\s+(.*)$/si ) {
        $stmt = "DROP TABLE $1";
        $self->{"struct"}->{ignore_missing_table}=1;
    }
    if ($stmt =~ /^\s*DROP\s+(\S+)\s+(.+)$/si ) {
       my $com2    = $1 || '';
       $table_name = $2;
       if ($com2 !~ /^TABLE$/i) {
          return $self->do_err(
              "The command 'DROP $com2' is not recognized or not supported!"
          );
      }
      $table_name =~ s/^\s+//;
      $table_name =~ s/\s+$//;
      if ( $table_name =~ /(\S+) (RESTRICT|CASCADE)/i) {
          $table_name = $1;
          $self->{"struct"}->{"drop_behavior"} = uc $2;
      }
    }
    else {
        return $self->do_err( "Incomplete DROP statement!" );

    }
    return undef unless $self->TABLE_NAME($table_name);
    $table_name = $self->replace_quoted_ids($table_name);
    $self->{"tmp"}->{"is_table_name"}  = {$table_name => 1};
    $self->{"struct"}->{"table_names"} = [$table_name];
    return 1;
}

####################################################
# DELETE FROM <table_name> WHERE <search_condition>
####################################################
sub DELETE {
    my($self,$str) = @_;
    $self->{"struct"}->{"command"}     = 'DELETE';
    my($table_name,$where_clause) = $str =~
        /^DELETE FROM (\S+)(.*)$/i;
    return $self->do_err(
        'Incomplete DELETE statement!'
    ) if !$table_name;
    return undef unless $self->TABLE_NAME($table_name);
    $self->{"tmp"}->{"is_table_name"}  = {$table_name => 1};
    $self->{"struct"}->{"table_names"} = [$table_name];
    $self->{"struct"}->{"column_names"} = ['*'];
    $where_clause =~ s/^\s+//;
    $where_clause =~ s/\s+$//;
    if ($where_clause) {
        $where_clause =~ s/^WHERE\s*(.*)$/$1/i;
        return undef unless $self->SEARCH_CONDITION($where_clause);
    }
    return 1;
}

##############################################################
# SELECT
##############################################################
#    SELECT [<set_quantifier>] <select_list>
#           | <set_function_specification>
#      FROM <from_clause>
#    [WHERE <search_condition>]
# [ORDER BY <order_by_clause>]
#    [LIMIT <limit_clause>]
##############################################################

sub SELECT {
    my($self,$str) = @_;
    $self->{"struct"}->{"command"} = 'SELECT';
    my($from_clause,$where_clause,$order_clause,$limit_clause);
    $str =~ s/^SELECT (.+)$/$1/i;
    if ( $str =~ s/^(.+) LIMIT (.+)$/$1/i ) { $limit_clause = $2; }
    if ( $str =~ s/^(.+) ORDER BY (.+)$/$1/i     ) { $order_clause = $2; }
    if ( $str =~ s/^(.+?) WHERE (.+)$/$1/i        ) { $where_clause = $2; }
    if ( $str =~ s/^(.+?) FROM (.+)$/$1/i        ) { $from_clause  = $2; }
    else {
        return $self->do_err("Couldn't find FROM clause in SELECT!");
    }
    return undef unless $self->FROM_CLAUSE($from_clause);
    return undef unless $self->SELECT_CLAUSE($str);
    if ($where_clause) {
        return undef unless $self->SEARCH_CONDITION($where_clause);
    }
    if ($order_clause) {
        return undef unless $self->SORT_SPEC_LIST($order_clause);
    }
    if ($limit_clause) {
        return undef unless $self->LIMIT_CLAUSE($limit_clause);
    }
    if ( ( $self->{"struct"}->{join}->{"clause"}
           and $self->{"struct"}->{join}->{"clause"} eq 'ON'
         )
      or ( $self->{"struct"}->{"multiple_tables"}
###new
            and !(scalar keys %{$self->{"struct"}->{join}})
#            and !$self->{"struct"}->{join}
###
       ) ) {
           return undef unless $self->IMPLICIT_JOIN();
    }
    return 1;
}

sub IMPLICIT_JOIN {
    my $self = shift;
    delete $self->{"struct"}->{"multiple_tables"};
    if ( !$self->{"struct"}->{join}->{"clause"}
           or $self->{"struct"}->{join}->{"clause"} ne 'ON'
    ) {
        $self->{"struct"}->{join}->{"type"}    = 'INNER';
        $self->{"struct"}->{join}->{"clause"}  = 'IMPLICIT';
    }
    if (defined $self->{"struct"}->{"keycols"} ) {
        my @keys;
        my @keys2 = @keys = @{ $self->{"struct"}->{"keycols"} };
        $self->{"struct"}->{join}->{"table_order"} = $self->order_joins(\@keys2);
        @{$self->{"struct"}->{join}->{"keycols"}} = @keys;
        delete $self->{"struct"}->{"keycols"};
    }
    else {
        return $self->do_err("No equijoin condition in WHERE or ON clause");
    }
    return 1;
}

sub EXPLICIT_JOIN {
    my $self = shift;
    my $remainder = shift;
    return undef unless $remainder;
    my($tableA,$tableB,$keycols,$jtype,$natural);
    if ($remainder =~ /^(.+?) (NATURAL|INNER|LEFT|RIGHT|FULL|UNION|JOIN)(.+)$/s){
        $tableA = $1;
        $remainder = $2.$3;
    }
    else {
        ($tableA,$remainder) = $remainder =~ /^(\S+) (.*)/;
    }
        if ( $remainder =~ /^NATURAL (.+)/) {
            $self->{"struct"}->{join}->{"clause"} = 'NATURAL';
            $natural++;
            $remainder = $1;
        }
        if ( $remainder =~ 
           /^(INNER|LEFT|RIGHT|FULL|UNION) JOIN (.+)/
        ) {
          $jtype = $self->{"struct"}->{join}->{"clause"} = $1;
          $remainder = $2;
          $jtype = "$jtype OUTER" if $jtype !~ /INNER|UNION/;
      }
        if ( $remainder =~ 
           /^(LEFT|RIGHT|FULL) OUTER JOIN (.+)/
        ) {
          $jtype = $self->{"struct"}->{join}->{"clause"} = $1 . " OUTER";
          $remainder = $2;
      }
      if ( $remainder =~ /^JOIN (.+)/) {
          $jtype = 'INNER';
          $self->{"struct"}->{join}->{"clause"} = 'DEFAULT INNER';
          $remainder = $1;
      }
      if ( $self->{"struct"}->{join} ) {
          if ( $remainder && $remainder =~ /^(.+?) USING \(([^\)]+)\)(.*)/) {
              $self->{"struct"}->{join}->{"clause"} = 'USING';
              $tableB = $1;
              my $keycolstr = $2;
              $remainder = $3;
              @$keycols = split /,/,$keycolstr;
          }
          if ( $remainder && $remainder =~ /^(.+?) ON (.+)/) {
              $self->{"struct"}->{join}->{"clause"} = 'ON';
              $tableB = $1;
#zzz
#print "here";
#print 9 if $self->can('TABLE_NAME_LIST');
#return undef unless $self->TABLE_NAME_LIST($tableA.','.$tableB);
#print "there";
#exit;

              my $keycolstr = $2;
              $remainder = $3;
              if ($keycolstr =~ / OR /i ) {
                  return $self->do_err(qq~Can't use OR in an ON clause!~,1);
	      }
              @$keycols = split / AND /i,$keycolstr;
#zzz
return undef unless $self->TABLE_NAME_LIST($tableA.','.$tableB);
#              $self->{"tmp"}->{"is_table_name"}->{"$tableA"} = 1;
#              $self->{"tmp"}->{"is_table_name"}->{"$tableB"} = 1;
              for (@$keycols) {
                  my %is_done;
                  my($arg1,$arg2) = split / = /;
                  my($c1,$c2)=($arg1,$arg2);
                  $c1 =~ s/^.*\.([^\.]+)$/$1/;
                  $c2 =~ s/^.*\.([^\.]+)$/$1/;
                  if ($c1 eq $c2) {
                      return undef unless $arg1 = $self->ROW_VALUE($c1);
                      if ( $arg1->{type} eq 'column' and !$is_done{$c1}
                      ){
                          push @{$self->{struct}->{keycols}},$arg1->{value};
                          $is_done{$c1}=1;
 	              }
                  }
                  else {
                      return undef unless $arg1 = $self->ROW_VALUE($arg1);
                      return undef unless $arg2 = $self->ROW_VALUE($arg2);
                      if ( $arg1->{"type"}eq 'column'
                      and $arg2->{"type"}eq 'column'){
                          push @{ $self->{"struct"}->{"keycols"} }
                              , $arg1->{"value"};
                           push @{ $self->{"struct"}->{"keycols"} }
                              , $arg2->{"value"};
                           # delete $self->{"struct"}->{"where_clause"};
	              }
                  }
              }
          }
          elsif ($remainder =~ /^(.+?)$/i) {
  	      $tableB = $1;
              $remainder = $2;
          }
          $remainder =~ s/^\s+// if $remainder;
      }

      if ($jtype) {
          $jtype = "NATURAL $jtype" if $natural;
          if ($natural and $keycols) {
              return $self->do_err(
                  qq~Can't use NATURAL with a USING or ON clause!~
              );
	  }
          return undef unless $self->TABLE_NAME_LIST("$tableA,$tableB");
          $self->{"struct"}->{join}->{"type"}    = $jtype;
          $self->{"struct"}->{join}->{"keycols"} = $keycols if $keycols;
          return 1;
      }
      return $self->do_err("Couldn't parse explicit JOIN!");
}

sub SELECT_CLAUSE {
    my($self,$str) = @_;
    return undef unless $str;
    if ($str =~ s/^(DISTINCT|ALL) (.+)$/$2/i) {
        $self->{"struct"}->{"set_quantifier"} = uc $1;
    }
    if ($str =~ /[()]/) {
        return undef unless $self->SET_FUNCTION_SPEC($str);
    }
    else {
        return undef unless $self->SELECT_LIST($str);
    }
}

sub FROM_CLAUSE {
    my($self,$str) = @_;
    return undef unless $str;
    if ($str =~ / JOIN /i ) {
        return undef unless $self->EXPLICIT_JOIN($str);
    }
    else {
        return undef unless $self->TABLE_NAME_LIST($str);
    }
}

sub INSERT {
    my($self,$str) = @_;
    my $col_str;
    my($table_name,$val_str) = $str =~
        /^INSERT\s+INTO\s+(.+?)\s+VALUES\s+\((.+?)\)$/i;
    if ($table_name and $table_name =~ /[()]/ ) {
    ($table_name,$col_str,$val_str) = $str =~
        /^INSERT\s+INTO\s+(.+?)\s+\((.+?)\)\s+VALUES\s+\((.+?)\)$/i;
    }
    return $self->do_err('No table name specified!') unless $table_name;
    return $self->do_err('Missing values list!') unless defined $val_str;
    return undef unless $self->TABLE_NAME($table_name);
    $self->{"struct"}->{"command"} = 'INSERT';
    $self->{"struct"}->{"table_names"} = [$table_name];
    if ($col_str) {
        return undef unless $self->COLUMN_NAME_LIST($col_str);
    }
    else {
          $self->{"struct"}->{"column_names"} = ['*'];
    }
    return undef unless $self->LITERAL_LIST($val_str);
    return 1;
}

###################################################################
# UPDATE ::=
#
# UPDATE <table> SET <set_clause_list> [ WHERE <search_condition>]
#
###################################################################
sub UPDATE {
    my($self,$str) = @_;
    $self->{"struct"}->{"command"} = 'UPDATE';
    my($table_name,$remainder) = $str =~
        /^UPDATE (.+?) SET (.+)$/i;
    return $self->do_err(
        'Incomplete UPDATE clause'
    ) if !$table_name or !$remainder;
    return undef unless $self->TABLE_NAME($table_name);
    $self->{"tmp"}->{"is_table_name"}  = {$table_name => 1};
    $self->{"struct"}->{"table_names"} = [$table_name];
    my($set_clause,$where_clause) = $remainder =~
        /(.*?) WHERE (.*)$/i;
    $set_clause = $remainder if !$set_clause;
    return undef unless $self->SET_CLAUSE_LIST($set_clause);
    if ($where_clause) {
        return undef unless $self->SEARCH_CONDITION($where_clause);
    }
    my @vals = @{$self->{"struct"}->{"values"}};
    my $num_val_placeholders=0;
    for my $v(@vals) {
       $num_val_placeholders++ if $v->{"type"} eq 'placeholder';
    }
    $self->{"struct"}->{"num_val_placeholders"}=$num_val_placeholders;
    return 1;
}

#########
# CREATE
#########

sub CREATE {
    my $self = shift;
    my $stmt = shift;
    $self->{"struct"}->{"command"} = 'CREATE';
    my($table_name,$table_element_def,%is_col_name);
    if ($stmt =~ /^CREATE (LOCAL|GLOBAL) TEMPORARY TABLE(.*)$/si ) {
        $self->{"struct"}->{"table_type"} = "$1 TEMPORARY";
        $stmt = "CREATE TABLE$2";
    }
    if ($stmt =~ /^(.*) ON COMMIT (DELETE|PRESERVE) ROWS\s*$/si ) {
        $stmt = $1;
        $self->{"struct"}->{"commit_behaviour"} = $2;
        return $self->do_err(
           "Can't specify commit behaviour for permanent tables."
        )
           if !defined $self->{"struct"}->{"table_type"}
              or $self->{"struct"}->{"table_type"} !~ /TEMPORARY/;
    }
    if ($stmt =~ /^CREATE TABLE (\S+) \((.*)\)$/si ) {
       $table_name        = $1;
       $table_element_def = $2;
    } 
    else {
        return $self->do_err( "Can't find column definitions!" );
    }
    return undef unless $self->TABLE_NAME($table_name);
    $table_element_def =~ s/\s+\(/(/g;
    my $primary_defined;
    for my $col(split ',',$table_element_def) {
        my($name,$type,$constraints)=($col =~/\s*(\S+)\s+(\S+)\s*(.*)/);
        if (!$type) {
            return $self->do_err( "Column definition is missing a data type!" );
	}
        return undef if !($self->IDENTIFIER($name));
#        if ($name =~ /^\?QI(.+)\?$/ ) {
            $name = $self->replace_quoted_ids($name);
#        }
        $constraints =~ s/^\s+//;
        $constraints =~ s/\s+$//;
        if ($constraints) {
           $constraints =~ s/PRIMARY KEY/PRIMARY_KEY/i;
           $constraints =~ s/NOT NULL/NOT_NULL/i;
           my @c = split /\s+/, $constraints;
           my %has_c;
           for my $constr(@c) {
   	       if ( $constr =~ /^\s*(UNIQUE|NOT_NULL|PRIMARY_KEY)\s*$/i ) {
                   my $cur_c = uc $1;
                   if ($has_c{$cur_c}++) {
  		       return $self->do_err(
                           qq~Duplicate column constraint: '$constr'!~
                       );
		   }
                   if ($cur_c eq 'PRIMARY_KEY' and $primary_defined++ ) {
  		       return $self->do_err(
                           qq~Can't have two PRIMARY KEYs in a table!~
                        );
		   }
                   $constr =~ s/_/ /g;
                   push @{$self->{"struct"}->{"column_defs"}->{"$name"}->{"constraints"} }, $constr;

	       }
               else {
		   return $self->do_err("Unknown column constraint: '$constr'!");
	       }
	   }
	}
        $type = uc $type;
        my $length;
        if ( $type =~ /(.+)\((.+)\)/ ) {
            $type = $1;
            $length = $2;
	}
        if (!$self->{"opts"}->{"valid_data_types"}->{"$type"}) {
            return $self->do_err("'$type' is not a recognized data type!");
	}
        $self->{"struct"}->{"column_defs"}->{"$name"}->{"data_type"} = $type;
        $self->{"struct"}->{"column_defs"}->{"$name"}->{"data_length"} = $length;
        push @{$self->{"struct"}->{"column_names"}},$name;
        #push @{$self->{"struct"}->{ORG_NAME}},$name;
        my $tmpname = $name;
        $tmpname = uc $tmpname unless $tmpname =~ /^"/;
        return $self->do_err("Duplicate column names!") 
          if $is_col_name{$tmpname}++;

    } 
    $self->{"struct"}->{"table_names"} = [$table_name];
    return 1;
}


###############
# SQL SUBRULES
###############

sub SET_CLAUSE_LIST {
    my $self       = shift;
    my $set_string = shift;
    my @sets = split /,/,$set_string;
    my(@cols,@vals);
    for(@sets) {
        my($col,$val) = split / = /,$_;
        return $self->do_err('Incomplete SET clause!') if !defined $col or !defined $val;
        push @cols, $col;
        push @vals, $val;
    }
    return undef unless $self->COLUMN_NAME_LIST(join ',',@cols);
    return undef unless $self->LITERAL_LIST(join ',',@vals);
    return 1;
}

sub SET_QUANTIFIER {
    my($self,$str) = @_;
    if ($str =~ /^(DISTINCT|ALL)\s+(.*)$/si) {
        $self->{"struct"}->{"set_quantifier"} = uc $1;
        $str = $2;
    }
    return $str;
}

sub SELECT_LIST {
    my $self = shift;
    my $col_str = shift;
    if ( $col_str =~ /^\s*\*\s*$/ ) {
        $self->{"struct"}->{"column_names"} = ['*'];
        return 1;
    }
    my @col_list = split ',',$col_str;
    if (!(scalar @col_list)) {
        return $self->do_err('Missing column name list!');
    }
    my(@newcols,$newcol);
    for my $col(@col_list) {
#        $col = trim($col);
    $col =~ s/^\s+//;
    $col =~ s/\s+$//;
        if ($col =~ /^(\S+)\.\*$/) {
        my $table = $1;
        my %is_table_alias = %{$self->{"tmp"}->{"is_table_alias"}};
        $table = $is_table_alias{$table} if $is_table_alias{$table};
        $table = $is_table_alias{"\L$table"} if $is_table_alias{"\L$table"};
#        $table = uc $table unless $table =~ /^"/;
#use mylibs; zwarn \%is_table_alias;
#print "\n<<$table>>\n";
            return undef unless $self->TABLE_NAME($table);
            $table = $self->replace_quoted_ids($table);
            push @newcols, "$table.*";
        }
        else {
            return undef unless $newcol = $self->COLUMN_NAME($col);
            push @newcols, $newcol;
	}
    }
    $self->{"struct"}->{"column_names"} = \@newcols;
    return 1;
}

sub SET_FUNCTION_SPEC {
    my($self,$col_str) = @_;
    my @funcs = split /,/, $col_str;
    my %iscol;
    for my $func(@funcs) {
        if ($func =~ /^(COUNT|AVG|SUM|MAX|MIN) \((.*)\)\s*$/i ) {
            my $set_function_name = uc $1;
            my $set_function_arg  = $2;
            my $distinct;
            if ( $set_function_arg =~ s/(DISTINCT|ALL) (.+)$/$2/i ) {
                $distinct = uc $1;
                $self->{"struct"}->{"set_quantifier"} = $distinct;
	    } 
            my $count_star = 1 if $set_function_name eq 'COUNT'
                              and $set_function_arg eq '*';
            my $ok = $self->COLUMN_NAME($set_function_arg)
                     if !$count_star;
            return undef if !$count_star and !$ok;
	    if ($set_function_arg !~ /^"/) {
                $set_function_arg = uc $set_function_arg;
	    } 
            push @{ $self->{"struct"}->{'set_function'}}, {
                name     => $set_function_name,
                arg      => $set_function_arg,
                distinct => $distinct,
            };
            push( @{ $self->{"struct"}->{"column_names"} }, $set_function_arg)
                 if !$iscol{$set_function_arg}++
                and ($set_function_arg ne '*');
        }
        else {
	  return $self->do_err("Bad set function before FROM clause.");
	}
    }
    my $cname = $self->{"struct"}->{"column_names"};
    if ( !$cname or not scalar @$cname ) {
         $self->{"struct"}->{"column_names"} = ['*'];
    } 
    return 1;
}

sub LIMIT_CLAUSE {
    my($self,$limit_clause) = @_;
#    $limit_clause = trim($limit_clause);
    $limit_clause =~ s/^\s+//;
    $limit_clause =~ s/\s+$//;

    return 1 if !$limit_clause;
    my($offset,$limit,$junk) = split /,/, $limit_clause;
    return $self->do_err('Bad limit clause!')
         if (defined $limit and $limit =~ /[^\d]/)
         or ( defined $offset and $offset =~ /[^\d]/ )
         or defined $junk;
    if (defined $offset and !defined $limit) {
        $limit = $offset;
        undef $offset;
    }
    $self->{"struct"}->{"limit_clause"} = {
        limit  => $limit,
        offset => $offset,
     };
     return 1;
}

sub is_number {
    my $x=shift;
    return 0 if !defined $x;
    return 1 if $x =~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/;
    return 0;
}

sub SORT_SPEC_LIST {
        my($self,$order_clause) = @_;
        return 1 if !$order_clause;
        my %is_table_name = %{$self->{"tmp"}->{"is_table_name"}};
        my %is_table_alias = %{$self->{"tmp"}->{"is_table_alias"}};
        my @ocols;
        my @order_columns = split ',',$order_clause;
        for my $col(@order_columns) {
            my $newcol;
            my $newarg;
	    if ($col =~ /\s*(\S+)\s+(ASC|DESC)/si ) {
                $newcol = $1;
                $newarg = uc $2;
	    }
	    elsif ($col =~ /^\s*(\S+)\s*$/si ) {
                $newcol = $1;
            }
            else {
	      return $self->do_err(
                 'Junk after column name in ORDER BY clause!'
              );
	    }
            return undef if !($newcol = $self->COLUMN_NAME($newcol));
            if ($newcol =~ /^(.+)\..+$/s ) {
              my $table = $1;
              if ($table =~ /^'/) {
	          if (!$is_table_name{"$table"} and !$is_table_alias{"$table"} ) {
                return $self->do_err( "Table '$table' in ORDER BY clause "
                             . "not in FROM clause."
                             );
	      }}
	      elsif (!$is_table_name{"\L$table"} and !$is_table_alias{"\L$table"} ) {
                return $self->do_err( "Table '$table' in ORDER BY clause "
                             . "not in FROM clause."
                             );
	      }
	    }
            push @ocols, {$newcol => $newarg};
	}
        $self->{"struct"}->{"sort_spec_list"} = \@ocols;
        return 1;
}

sub SEARCH_CONDITION {
    my $self = shift;
    my $str  = shift;
    $str =~ s/^\s*WHERE (.+)/$1/;
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    return $self->do_err("Couldn't find WHERE clause!") unless $str;
    $str = get_btwn( $str );
    $str = get_in( $str );
    my $open_parens  = $str =~ tr/\(//;
    my $close_parens = $str =~ tr/\)//;
    if ($open_parens != $close_parens) {
        return $self->do_err("Mismatched parentheses in WHERE clause!");
    }
    $str = nongroup_numeric( nongroup_string( $str ) );
    my $pred = $open_parens
        ? $self->parens_search($str,[])
        : $self->non_parens_search($str,[]);
    return $self->do_err("Couldn't find predicate!") unless $pred;
    $self->{"struct"}->{"where_clause"} = $pred;
    return 1;
}

############################################################
# UTILITY FUNCTIONS CALLED TO PARSE PARENS IN WHERE CLAUSE
############################################################

# get BETWEEN clause
#
sub get_btwn {
    my $str = shift;
    if ($str =~ /^(.+?) BETWEEN (.+)$/i ) {
        my($col,$in,$out,$contents);
        my $front = $1;
        my $back  = $2;
        my $not = 1 if $front =~ s/^(.+) NOT$/$1/i;
        if ($front =~ s/^(.+? )(AND|OR|\() (.+)$/$1$2/i) {
            $col = $3;
	} 
        else {
            $col = $front;
            $front = '';
	}
        $front .= " NOT" if $not;
        my($val1,$val2);
        if ($back =~ s/^(.+?) AND (.+)$/$2/) {
            $val1 = $1;
	}
        if ($back =~ s/^(.+?) (AND|OR)(.+)$/$2$3/i) {
            $val2 = $1;
	} 
        else {
            $val2 = $back;
            $back = '';
	}
        $str = "$front ($col > $val1 AND $col < $val2) $back";
        return get_btwn($str);
    }
    return $str;
}

# get IN clause
#
#  a IN (b,c)     -> (a=b OR a=c)
#  a NOT IN (b,c) -> (a<>b AND a<>c)
#
sub get_in {
    my $str = shift;
    my $in_inside_parens;
    if ($str =~ /^(.+?) IN (\(.+)$/i ) {
        my($col,$in,$out,$contents);
        my $front = $1;
        my $back  = $2;
        my $not;
        $not++ if $front =~ s/^(.+) NOT$/$1/i;
        if ($front =~ s/^(.+? )(AND|OR|\() (.+)$/$1$2/i) {
            $col = $3;
	} 
        else {
            $col = $front;
            $not++ if $col =~ s/^NOT (.+)/$1/i;
            $front = '';
	}
            if ( $col =~ s/^\(// ) {
                $in_inside_parens++;
	    }
#print "~$not~\n";
 #       $front .= " NOT" if $not;
#        $not++ if $front =~ s/^(.+) NOT$/$1/i;
        my @chars = split '', $back;
        for (0..$#chars) {
            my $char = shift @chars;
            $contents .= $char;
	    $in++ if $char eq '(';
            if ( $char eq ')' ) {
                $out++;
                last if $in == $out;
	    }
	}
        $back = join '', @chars;
        $back =~ s/\)$// if $in_inside_parens;
        # print "\n[$front][$col][$contents][$back]\n";
        #die "\n[$contents]\n";
        $contents =~ s/^\(//;
        $contents =~ s/\)$//;
        my @vals = split /,/, $contents;
my $op       = '=';
my $combiner = 'OR';
if ($not) {
    $op       = '<>';
    $combiner = 'AND';
}
        @vals = map { "$col $op $_" } @vals;
        my $valStr = join " $combiner ", @vals;
        $str = "$front ($valStr) $back";
        $str =~ s/\s+/ /g;
        return get_in($str);
    }
$str =~ s/^\s+//;
$str =~ s/\s+$//;
$str =~ s/\(\s+/(/;
$str =~ s/\s+\)/)/;
#print "$str:\n";
    return $str;
}

# groups clauses by nested parens
#
sub parens_search {
    my $self = shift;
    my $str  = shift;
    my $predicates = shift;
    my $index = scalar @$predicates;

    # to handle WHERE (a=b) AND (c=d)
    # but needs escape space to not foul up AND/OR
    if ($str =~ /\(([^()]+?)\)/ ) {
        my $pred = quotemeta $1;
        if ($pred !~ / (AND|OR)\\ / ) {
          $str =~ s/\(($pred)\)/$1/;
        }
    }
    #

    if ($str =~ s/\(([^()]+)\)/^$index^/ ) {
        push @$predicates, $1;
    }
    # patch from Chromatic
    if ($str =~ /\((?!\))/ ) {
        return $self->parens_search($str,$predicates);
    }
    else {
        return $self->non_parens_search($str,$predicates);
    }
}

# creates predicates from clauses that either have no parens
# or ANDs or have been previously grouped by parens and ANDs
#
sub non_parens_search {
    my $self = shift;
    my $str = shift;
    my $predicates = shift;
    my $neg  = 0;
    my $nots = {};
    if ( $str =~ s/^NOT (\^.+)$/$1/i ) {
        $neg  = 1;
        $nots = {pred=>1};
    }
    my( $pred1, $pred2, $op );
    my $and_preds =[];
    ($str,$and_preds) = group_ands($str);
    $str =~ s/^\s*\^0\^\s*$/$predicates->[0]/;
    return if $str =~ /^\s*~0~\s*$/;
    if ( ($pred1, $op, $pred2) = $str =~ /^(.+) (AND|OR) (.+)$/i ) {
        $pred1 =~ s/\~(\d+)\~$/$and_preds->[$1]/g;
        $pred2 =~ s/\~(\d+)\~$/$and_preds->[$1]/g;
        $pred1 = $self->non_parens_search($pred1,$predicates);
        $pred2 = $self->non_parens_search($pred2,$predicates);
        # print $op;
        return {
            neg  => $neg,
            nots => $nots,
            arg1 => $pred1,
            op   => uc $op,
            arg2 => $pred2,
        };
    }
    else {
        my $xstr = $str;
        $xstr =~ s/\?(\d+)\?/$self->{"struct"}->{"literals"}->[$1]/g;
        my($k,$v) = $xstr =~ /^(\S+?)\s+\S+\s*(.+)\s*$/;
        #print "$k,$v\n" if defined $k;
        push @{ $self->{struct}->{where_cols}->{$k}}, $v if defined $k;
        # print " [$str] ";
        return $self->PREDICATE($str);
    }
}

# groups AND clauses that aren't already grouped by parens
#
sub group_ands{
    my $str       = shift;
    my $and_preds = shift || [];
    return($str,$and_preds) unless $str =~ / AND / and $str =~ / OR /;
    if ($str =~ /^(.*?) AND (.*)$/i ) {
        my $index = scalar @$and_preds;
        my($front, $back)=($1,$2);
        if ($front =~ /^.* OR (.*)$/i ) {
            $front = $1;
        }
        if ($back =~ /^(.*?) (OR|AND) (.*)$/i ) {
            $back = $1;
        }
        my $newpred = "$front AND $back";
        push @$and_preds, $newpred;
        $str =~ s/\Q$newpred/~$index~/i;
        return group_ands($str,$and_preds);
    }
    else {
        return $str,$and_preds;
    }
}

# replaces string function parens with square brackets
# e.g TRIM (foo) -> TRIM[foo]
#

sub nongroup_string {
    my $f= FUNCTION_NAMES;
    my $str = shift;
#    $str =~ s/(TRIM|SUBSTRING|UPPER|LOWER) \(([^()]+)\)/$1\[$2\]/gi;
    $str =~ s/($f) \(([^()]+)\)/$1\[$2\]/gi;
#    if ( $str =~ /(TRIM|SUBSTRING|UPPER|LOWER) \(/i ) {
    if ( $str =~ /($f) \(/i ) {
        return nongroup_string($str);
    }
    else {
        return $str;
    }
}

# replaces math parens with square brackets
# e.g (4-(6+7)*9) -> MATH[4-MATH[6+7]*9]
#
sub nongroup_numeric {
    my $str = shift;
    my $has_op;
    if ( $str =~ /\(([0-9 \*\/\+\-_a-zA-Z\[\]\?]+)\)/ ) {
        my $match = $1;
        if ($match !~ /(LIKE |IS|BETWEEN|IN)/ ) {
            my $re    = quotemeta($match);
            $str =~ s/\($re\)/MATH\[$match\]/;
	}
        else {
	    $has_op++;
	}
    }
    if ( !$has_op and $str =~ /\(([0-9 \*\/\+\-_a-zA-Z\[\]\?]+)\)/ ) {
        return nongroup_numeric($str);
    }
    else {
        return $str;
    }
}
############################################################


#########################################################
# LITERAL_LIST ::= <literal> [,<literal>]
#########################################################
sub LITERAL_LIST {
    my $self = shift;
    my $str  = shift;
    my @tokens = split /,/, $str;
    my @values;
    for my $tok(@tokens) {
        my $val  = $self->ROW_VALUE($tok);
        return $self->do_err(
            qq('$tok' is not a valid value or is not quoted!)
        ) unless $val;
        push @values, $val;
    }
    $self->{"struct"}->{"values"} = \@values;
    return 1;
}


###################################################################
# LITERAL ::= <quoted_string> | <question mark> | <number> | NULL
###################################################################
sub LITERAL {
    my $self = shift;
    my $str  = shift;
    return 'null' if $str =~ /^NULL$/i;    # NULL
#    return 'empty_string' if $str =~ /^~E~$/i;    # NULL
    if ($str eq '?') {
          $self->{struct}->{num_placeholders}++;
          return 'placeholder';
    } 
#    return 'placeholder' if $str eq '?';   # placeholder question mark
    return 'string' if $str =~ /^'.*'$/s;  # quoted string
    return 'number' if $str =~             # number
       /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/;
    return undef;
}
###################################################################
# PREDICATE
###################################################################
sub PREDICATE {
    my $self = shift;
    my $str  = shift;
    my @allops = keys %{ $self->{"opts"}->{"valid_comparison_operators"} };
    my @notops;
    for (@allops) { push (@notops, $_) if /NOT/i };
    my $ops = join '|', @notops;
    my $opexp = "^\\s*(.+)\\s+($ops)\\s+(.*)\\s*\$";
    my($arg1,$op,$arg2) = $str =~ /$opexp/i;
    if (!defined $op) {
        my @compops;
        for (@allops) { push (@compops, $_) if /<=|>=|<>/ };
        $ops = join '|', @compops;
        $opexp = "^\\s*(.+)\\s+($ops)\\s+(.*)\\s*\$";
        ($arg1,$op,$arg2) = $str =~ /$opexp/i;
    }
    if (!defined $op) {
        $ops = join '|', @allops;
        $opexp = "^\\s*(.+)\\s+($ops)\\s+(.*)\\s*\$";
        ($arg1,$op,$arg2) = $str =~ /$opexp/i;
    }
    $op = uc $op;
    if (!defined $arg1 || !defined $op || !defined $arg2) {
        return $self->do_err("Bad predicate: '$str'!");
    }
    my $negated = 0;  # boolean value showing if predicate is negated
    my %not;          # hash showing elements modified by NOT
    #
    # e.g. "NOT bar = foo"        -> %not = (arg1=>1)
    #      "bar NOT LIKE foo"     -> %not = (op=>1)
    #      "NOT bar NOT LIKE foo" -> %not = (arg1=>1,op=>1);
    #      "NOT bar IS NOT NULL"  -> %not = (arg1=>1,op=>1);
    #      "bar = foo"            -> %not = undef;
    #
    if ( $arg1 =~ s/^NOT (.+)$/$1/i ) {
        $not{arg1}++;
    }
    if ( $op =~ s/^(.+) NOT$/$1/i
      || $op =~ s/^NOT (.+)$/$1/i ) {
        $not{op}++;
    }
    $negated = 1 if %not and scalar keys %not == 1;
    return undef unless $arg1 = $self->ROW_VALUE($arg1);
    return undef unless $arg2 = $self->ROW_VALUE($arg2);
    if ( $arg1->{"type"}eq 'column'
     and $arg2->{"type"}eq 'column'
     and $op eq '='
       ) {
        push @{ $self->{"struct"}->{"keycols"} }, $arg1->{"value"};
        push @{ $self->{"struct"}->{"keycols"} }, $arg2->{"value"};
    }
    return {
        neg  => $negated,
        nots => \%not,
        arg1 => $arg1,
        op   => $op,
        arg2 => $arg2,
    };
}

sub undo_string_funcs {
    my $str = shift;
    my $f= FUNCTION_NAMES;
#    $str =~ s/(TRIM|UPPER|LOWER|SUBSTRING)\[([^\]\[]+?)\]/$1 ($2)/;
#    if ($str =~ /(TRIM|UPPER|LOWER|SUBSTRING)\[/) {
    $str =~ s/($f)\[([^\]\[]+?)\]/$1 ($2)/;
    if ($str =~ /($f)\[/) {
        return undo_string_funcs($str);
    }
    return $str;
}

sub undo_math_funcs {
    my $str = shift;
    $str =~ s/MATH\[([^\]\[]+?)\]/($1)/;
    if ($str =~ /MATH\[/) {
        return undo_math_funcs($str);
    }
    return $str;
}


###################################################################
# ROW_VALUE ::= <literal> | <column_name>
###################################################################
sub ROW_VALUE {
    my $self = shift;
    my $str  = shift;
    $str = undo_string_funcs($str);
    $str = undo_math_funcs($str);
    my $type;

    # MATH
    #
    if ($str =~ /[\*\+\-\/]/ ) {
        my @vals;
        my $i=-1;
        $str =~ s/([^\s\*\+\-\/\)\(]+)/push @vals,$1;$i++;"?$i?"/ge;
        my @newvalues;
        for (@vals) {
            my $val = $self->ROW_VALUE($_);
            if ($val && $val->{"type"} !~ /number|column|placeholder/) {
                 return $self->do_err(qq[
                     String '$val' not allowed in Numeric expression!
                 ]);
	    }
            push @newvalues,$val;
	}
        return {
            type => 'function',
            name => 'numeric_exp',
            str  => $str,
            vals => \@newvalues,
        }
    }

    # SUBSTRING (value FROM start [FOR length])
    #
    if ($str =~ /^SUBSTRING \((.+?) FROM (.+)\)\s*$/i ) {
        my $name  = 'SUBSTRING';
        my $start = $2;
        my $value = $self->ROW_VALUE($1);
        my $length;
        if ($start =~ /^(.+?) FOR (.+)$/i) {
            $start  = $1;
            $length = $2;
            $length = $self->ROW_VALUE($length);
	}
        $start = $self->ROW_VALUE($start);
        $str =~ s/\?(\d+)\?/$self->{"struct"}->{"literals"}->[$1]/g;
        return $self->do_err(
                "Can't use a string as a SUBSTRING position: '$str'!")
               if $start->{"type"} eq 'string'
               or ($start->{"length"} and $start->{"length"}->{"type"} eq 'string');
        return undef unless $value;
        return $self->do_err(
                "Can't use a number in SUBSTRING: '$str'!")
               if $value->{"type"} eq 'number';
        return {
            "type"   => 'function',
            "name"   => $name,
            "value"  => $value,
            "start"  => $start,
            "length" => $length,
        };
    }

    # TO_CHAR (value)
    #
    if ($str =~ /^TO_CHAR \((.+)\)\s*$/i ) {
        my $name  = 'TO_CHAR';
        my $value = $self->ROW_VALUE($1);
        return undef unless $value;
        return {
            type  => 'function',
            name  => $name,
            value => $value,
        };
    }

    # UPPER (value) and LOWER (value)
    #
    if ($str =~ /^(UPPER|LOWER) \((.+)\)\s*$/i ) {
        my $name  = uc $1;
        my $value = $self->ROW_VALUE($2);
        return undef unless $value;
        $str =~ s/\?(\d+)\?/$self->{"struct"}->{"literals"}->[$1]/g;
        return $self->do_err(
                "Can't use a number in UPPER/LOWER: '$str'!")
               if $value->{"type"} eq 'number';
        return {
            type  => 'function',
            name  => $name,
            value => $value,
        };
    }

    # TRIM ( [ [TRAILING|LEADING|BOTH] ['char'] FROM ] value )
    #
    if ($str =~ /^(TRIM) \((.+)\)\s*$/i ) {
        my $name  = uc $1;
        my $value = $2;
        my($trim_spec,$trim_char);
        if ($value =~ /^(.+) FROM ([^\(\)]+)$/i ) {
            my $front = $1;
            $value    = $2;
            if ($front =~ /^\s*(TRAILING|LEADING|BOTH)(.*)$/i ) {
                $trim_spec = uc $1;
#                $trim_char = trim($2);
    $trim_char = $2;
    $trim_char =~ s/^\s+//;
    $trim_char =~ s/\s+$//;
                undef $trim_char if length($trim_char)==0;
	    }
            else {
#	        $trim_char = trim($front);
    $trim_char = $front;
    $trim_char =~ s/^\s+//;
    $trim_char =~ s/\s+$//;
	    }
	}
        $trim_char =~ s/\?(\d+)\?/$self->{"struct"}->{"literals"}->[$1]/g if $trim_char;
        $value = $self->ROW_VALUE($value);
        return undef unless $value;
        $str =~ s/\?(\d+)\?/$self->{"struct"}->{"literals"}->[$1]/g;
        return $self->do_err(
                "Can't use a number in TRIM: '$str'!")
               if $value->{"type"} eq 'number';
        return {
            type      => 'function',
            name      => $name,
            value     => $value,
            trim_spec => $trim_spec,
            trim_char => $trim_char,
        };
    }

    # STRING CONCATENATION
    #
    if ($str =~ /\|\|/ ) {
        my @vals = split / \|\| /,$str;
        my @newvals;
        for my $val(@vals) {
            my $newval = $self->ROW_VALUE($val);
            return undef unless $newval;
            return $self->do_err(
                "Can't use a number in string concatenation: '$str'!")
                if $newval->{"type"} eq 'number';
            push @newvals,$newval;
	}
        return {
            type  => 'function',
            name  => 'str_concat',
            value => \@newvals,
        };
    }

    # NULL, PLACEHOLDER, NUMBER
    #
    if ( $type = $self->LITERAL($str) ) {
        undef $str if $type eq 'null';
#        if ($type eq 'empty_string') {
#           $str = '';
#           $type = 'string';
#	} 
        $str = '' if $str and $str eq q('');
        return { type => $type, value => $str };
    }

    # QUOTED STRING LITERAL
    #
    if ($str =~ /\?(\d+)\?/) {
        return { type  =>'string',
                 value  => $self->{"struct"}->{"literals"}->[$1] };
    }
    # COLUMN NAME
    #
    return undef unless $str = $self->COLUMN_NAME($str);
    if ( $str =~ /^(.*)\./ && !$self->{"tmp"}->{"is_table_name"}->{"\L$1"}
       and !$self->{"tmp"}->{"is_table_alias"}->{"\L$1"} ) {
        return $self->do_err(
            "Table '$1' in WHERE clause not in FROM clause!"
        );
    }
#    push @{ $self->{"struct"}->{"where_cols"}},$str
#       unless $self->{"tmp"}->{"where_cols"}->{"$str"};
    $self->{"tmp"}->{"where_cols"}->{"$str"}++;
    return { type => 'column', value => $str };
}

###############################################
# COLUMN NAME ::= [<table_name>.] <identifier>
###############################################

sub COLUMN_NAME {
    my $self   = shift;
    my $str = shift;
    my($table_name,$col_name);
    if ( $str =~ /^\s*(\S+)\.(\S+)$/s ) {
      if (!$self->{"opts"}->{"valid_options"}->{"SELECT_MULTIPLE_TABLES"}) {
          return $self->do_err('Dialect does not support multiple tables!');
      }
      $table_name = $1;
      $col_name   = $2;
#      my $alias = $self->{struct}->{table_alias} || [];
#      $table_name = shift @$alias if $alias;
      return undef unless $self->TABLE_NAME($table_name);
      $table_name = $self->replace_quoted_ids($table_name);
      my $ref;
      if ($table_name =~ /^"/) { #"
          if (!$self->{"tmp"}->{"is_table_name"}->{"$table_name"}
          and !$self->{"tmp"}->{"is_table_alias"}->{"$table_name"}
         ) {
          $self->do_err(
                "Table '$table_name' referenced but not found in FROM list!"
          );
          return undef;
      } 
      }
      elsif (!$self->{"tmp"}->{"is_table_name"}->{"\L$table_name"}
       and !$self->{"tmp"}->{"is_table_alias"}->{"\L$table_name"}
         ) {
          $self->do_err(
                "Table '$table_name' referenced but not found in FROM list!"
          );
          return undef;
      } 
    }
    else {
      $col_name = $str;
    }
#    $col_name = trim($col_name);
    $col_name =~ s/^\s+//;
    $col_name =~ s/\s+$//;
    return undef unless $col_name eq '*' or $self->IDENTIFIER($col_name);
#
# MAKE COL NAMES ALL UPPER CASE
    my $orgcol = $col_name;
    if ($col_name =~ /^\?QI(\d+)\?$/) {
        $col_name = $self->replace_quoted_ids($col_name);
    }
    else {
#      $col_name = lc $col_name;
      $col_name = uc $col_name unless $self->{struct}->{command} eq 'CREATE';

    } 
    $self->{struct}->{ORG_NAME}->{$col_name} = $orgcol;

#
#
    if ($table_name) {
       my $alias = $self->{tmp}->{is_table_alias}->{"\L$table_name"};
#use mylibs; print "$table_name"; zwarn $self->{tmp};
       $table_name = $alias if defined $alias;
$table_name = uc $table_name;
       $col_name = "$table_name.$col_name";
#print "<<$col_name>>"; 
    }
    return $col_name;
}

#########################################################
# COLUMN NAME_LIST ::= <column_name> [,<column_name>...]
#########################################################
sub COLUMN_NAME_LIST {
    my $self = shift;
    my $col_str = shift;
    my @col_list = split ',',$col_str;
    if (!(scalar @col_list)) {
        return $self->do_err('Missing column name list!');
    }
    my @newcols;
    my $newcol;
    for my $col(@col_list) {
    $col =~ s/^\s+//;
    $col =~ s/\s+$//;
#        return undef if !($newcol = $self->COLUMN_NAME(trim($col)));
        return undef if !($newcol = $self->COLUMN_NAME($col));
        push @newcols, $newcol;
    }
    $self->{"struct"}->{"column_names"} = \@newcols;
    return 1;
}


#####################################################
# TABLE_NAME_LIST := <table_name> [,<table_name>...]
#####################################################
sub TABLE_NAME_LIST {
    my $self = shift;
    my $table_name_str = shift;
    my %aliases = ();
    my @tables;
    my @table_names = split ',', $table_name_str;
    if ( scalar @table_names > 1
        and !$self->{"opts"}->{"valid_options"}->{'SELECT_MULTIPLE_TABLES'}
    ) {
        return $self->do_err('Dialect does not support multiple tables!');
    }
    my %is_table_alias;
    for my $table_str(@table_names) {
        my($table,$alias);
        my(@tstr) = split / /,$table_str;
        if    (@tstr == 1) { $table = $tstr[0]; }
        elsif (@tstr == 2) { $table = $tstr[0]; $alias = $tstr[1]; }
#        elsif (@tstr == 2) { $table = $tstr[1]; $alias = $tstr[0]; }
        elsif (@tstr == 3) {
            return $self->do_err("Can't find alias in FROM clause!")
                   unless uc($tstr[1]) eq 'AS';
            $table = $tstr[0]; $alias = $tstr[2];
#            $table = $tstr[2]; $alias = $tstr[0];
        }
        else {
	    return $self->do_err("Can't find table names in FROM clause!")
	}
        return undef unless $self->TABLE_NAME($table);
        $table = $self->replace_quoted_ids($table);
# zzz
        push @tables, $table;
        if ($alias) {
#die $alias, $table;
            return undef unless $self->TABLE_NAME($alias);
            $alias = $self->replace_quoted_ids($alias);
            if ($alias =~ /^"/) {
                push @{$aliases{$table}},"$alias";
                $is_table_alias{"$alias"}=$table;
	    }
            else {
                push @{$aliases{$table}},"\L$alias";
                $is_table_alias{"\L$alias"}=$table;
	    }
#            $aliases{$alias} = $table;
	}
    }
#    my %is_table_name = map { $_ => 1 } @tables,keys %aliases;
    my %is_table_name = map { lc $_ => 1 } @tables;
    #%is_table_alias = map { lc $_ => 1 } @aliases;
    $self->{"tmp"}->{"is_table_alias"}  = \%is_table_alias;
    $self->{"tmp"}->{"is_table_name"}  = \%is_table_name;
    $self->{"struct"}->{"table_names"} = \@tables;
    $self->{"struct"}->{"table_alias"} = \%aliases;
    $self->{"struct"}->{"multiple_tables"} = 1 if @tables > 1;
    return 1;
}

#############################
# TABLE_NAME := <identifier>
#############################
sub TABLE_NAME {
    my $self = shift;
    my $table_name = shift;
    if ($table_name =~ /\s*(\S+)\s+\S+/s) {
          return $self->do_err("Junk after table name '$1'!");
    }
    $table_name =~ s/\s+//s;
    if (!$table_name) {
        return $self->do_err('No table name specified!');
    }
    return $self->IDENTIFIER($table_name);
#    return undef if !($self->IDENTIFIER($table_name));
#    return 1;
}


###################################################################
# IDENTIFIER ::= <alphabetic_char> { <alphanumeric_char> | _ }...
#
# and must not be a reserved word or over 128 chars in length
###################################################################
sub IDENTIFIER {
    my $self = shift;
    my $id   = shift;
    if ($id =~ /^\?QI(.+)\?$/ ) {
        return 1;
    }
    return 1 if $id =~ /^".+?"$/s; # QUOTED IDENTIFIER
    my $err  = "Bad table or column name '$id' ";        # BAD CHARS
    if ($id =~ /\W/) {
        $err .= "has chars not alphanumeric or underscore!";
        return $self->do_err( $err );
    }
    if ($id =~ /^_/ or $id =~ /^\d/) {                    # BAD START
        $err .= "starts with non-alphabetic character!";
        return $self->do_err( $err );
    }
    if ( length $id > 128 ) {                              # BAD LENGTH
        $err .= "contains more than 128 characters!";
        return $self->do_err( $err );
    }
$id = uc $id;
#print "<$id>";
#use mylibs; zwarn $self->{opts}->{reserved_words};
#exit;
    if ( $self->{"opts"}->{"reserved_words"}->{$id} ) {   # BAD RESERVED WORDS
        $err .= "is a SQL reserved word!";
        return $self->do_err( $err );
    }
    return 1;
}

########################################
# PRIVATE METHODS AND UTILITY FUNCTIONS
########################################
sub order_joins {
    my $self = shift;
    my $links = shift;
    for my $link(@$links) {
      if ($link !~ /\./) {
          return [];
      }
    }
    @$links = map { s/^(.+)\..*$/$1/; $1; } @$links;
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
    return \@order;
}

sub bless_me {
    my $class  = shift;
    my $self   = shift || {};
    return bless $self, $class;
}

# PROVIDE BACKWARD COMPATIBILIT FOR JOCHEN'S FEATURE ATTRIBUTES TO NEW
#
#
sub set_feature_flags {
    my($self,$select,$create) = @_;
    if (defined $select) {
        delete $self->{"select"};
        $self->{"opts"}->{"valid_options"}->{"SELECT_MULTIPLE_TABLES"} =
            $self->{"opts"}->{"select"}->{join} =  $select->{join};
    }
    if (defined $create) {
        delete $self->{"create"};
        for my $key(keys %$create) {
            my $type = $key;
            $type =~ s/type_(.*)/\U$1/;
            $self->{"opts"}->{"valid_data_types"}->{"$type"} =
                $self->{"opts"}->{"create"}->{"$key"} = $create->{"$key"};
	}
    }
}

sub clean_sql {
    my $self = shift;
    my $sql  = shift;
    my $fields;
    my $i=-1;
    my $e = '\\';
    $e = quotemeta($e);
###new
# CAN'T HANDLE BLOBS!!!
#    $sql = quotemeta($sql);
 #   print "[$sql]\n";
#    if ($sql =~ s/^(.*,\s*)''(\s*[,\)].*)$/${1}NULL$2/g ) {
#    }
#    $sql =~ s/^([^\\']+?)''(.*)$/${1} NULL $2/g;

    # $sql =~ s/([^\\]+?)''/$1 ~E~ /g;

 #       print "$sql\n";
###newend

#    $sql =~ s~'(([^'$e]|$e.)+)'~push(@$fields,$1);$i++;"?$i?"~ge;
     $sql =~ s~'(([^'$e]|$e.|'')+)'~push(@$fields,$1);$i++;"?$i?"~ge;

#     $sql =~ s/([^\\]+?)''/$1 ~E~ /g;
     #print "<$sql>";
     @$fields = map { s/''/\\'/g; $_ } @$fields;

###new
#    if ( $sql =~ /'/) {
    if ( $sql =~ tr/[^\\]'// % 2 == 1 ) {
###endnew
        $sql =~ s/^.*\?(.+)$/$1/;
        die "Mismatched single quote before: '$sql\n";
    }
    if ($sql =~ /\?\?(\d)\?/) {
        $sql = $fields->[$1];
        die "Mismatched single quote: '$sql\n";
    }
    @$fields = map { s/$e'/'/g; s/^'(.*)'$/$1/; $_} @$fields;
    $self->{"struct"}->{"literals"} = $fields;

    my $qids;
    $i=-1;
    $e = q/""/;
#    $sql =~ s~"(([^"$e]|$e.)+)"~push(@$qids,$1);$i++;"?QI$i?"~ge;
    $sql =~ s~"(([^"]|"")+)"~push(@$qids,$1);$i++;"?QI$i?"~ge;
    #@$qids = map { s/$e'/'/g; s/^'(.*)'$/$1/; $_} @$qids;
    $self->{"struct"}->{"quoted_ids"} = $qids if $qids;

#    $sql =~ s~'(([^'\\]|\\.)+)'~push(@$fields,$1);$i++;"?$i?"~ge;
#    @$fields = map { s/\\'/'/g; s/^'(.*)'$/$1/; $_} @$fields;
#print "$sql [@$fields]\n";# if $sql =~ /SELECT/;

## before line 1511
    my $comment_re = $self->{"comment_re"};
#    if ( $sql =~ s/($comment_re)//gs) {
#       $self->{"comment"} = $1;
#    }
    if ( $sql =~ /(.*)$comment_re$/s) {
       $sql = $1;
       $self->{"comment"} = $2;
    }
    if ($sql =~ /^(.*)--(.*)(\n|$)/) {
       $sql               = $1;
       $self->{"comment"} = $2;
    }

    $sql =~ s/\n/ /g;
    $sql =~ s/\s+/ /g;
    $sql =~ s/(\S)\(/$1 (/g; # ensure whitespace before (
    $sql =~ s/\)(\S)/) $1/g; # ensure whitespace after )
    $sql =~ s/\(\s*/(/g;     # trim whitespace after (
    $sql =~ s/\s*\)/)/g;     # trim whitespace before )
       #
       # $sql =~ s/\s*\(/(/g;   # trim whitespace before (
       # $sql =~ s/\)\s*/)/g;   # trim whitespace after )
    for my $op( qw( = <> < > <= >= \|\|) ) {
        $sql =~ s/(\S)$op/$1 $op/g;
        $sql =~ s/$op(\S)/$op $1/g;
    }
    $sql =~ s/< >/<>/g;
    $sql =~ s/< =/<=/g;
    $sql =~ s/> =/>=/g;
    $sql =~ s/\s*,/,/g;
    $sql =~ s/,\s*/,/g;
    $sql =~ s/^\s+//;
    $sql =~ s/\s+$//;
    return $sql;
}

sub trim {
    my $str = shift or return '';
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    return $str;
}

sub do_err {
    my $self = shift;
    my $err  = shift;
    my $errtype  = shift;
    my @c = caller 4;
    $err = "$err\n\n";
#    $err = $errtype ? "DIALECT ERROR: $err in $c[3]"
#                    : "SQL ERROR: $err in $c[3]";
    $err = $errtype ? "DIALECT ERROR: $err"
                    : "SQL ERROR: $err";
    $self->{"struct"}->{"errstr"} = $err;
    #$self->{"errstr"} = $err;
    warn $err if $self->{"PrintError"};
    die $err if $self->{"RaiseError"};
    return undef;
}

1;

__END__


=head1 NAME

 SQL::Parser -- validate, parse, or build SQL strings

=head1 SYNOPSIS

 use SQL::Parser;                                     # CREATE A PARSER OBJECT
 my $parser = SQL::Parser->new( $dialect, \%attrs );

 my $success = $parser->parse( $sql_string );         # PARSE A SQL STRING &
 if ($success) {                                      # DISPLAY RESULTING DATA
     use Data::Dumper;                                # STRUCTURE
     print Dumper $parser->structure;
 }

 $parser->feature( $class, $name, $value );           # SET OR FIND STATUS OF
 my $has_feature = $parser->feature( $class, $name ); # A PARSER FEATURE

 $parser->dialect( $dialect_name );                   # SET OR FIND STATUS OF
 my $current_dialect = $parser->dialect;              # A PARSER DIALECT

 print $parser->errstr;                               # DISPLAY CURRENT ERROR
                                                      # STRING


=head1 DESCRIPTION

 SQL::Parser is a parser, builder, and sytax validator for a
 small but useful subset of SQL (Structured Query Language).  It
 accepts SQL strings and returns either a detailed error message
 if the syntax is invalid or a data structure containing the
 results of the parse if the syntax is valid.  It will soon also
 work in reverse to build a SQL string from a supplied data
 structure.

 The module can be used in batch mode to validate a series of
 statements, or as middle-ware for DBI drivers or other related
 projects.  When combined with SQL::Statement version 0.2 or
 greater, the module can be used to actually perform the SQL
 commands on a variety of file formats using DBD::AnyData, or
 DBD::CSV, or DBD::Excel.

 The module makes use of a variety of configuration files
 located in the SQL/Dialects directory, each of which is
 essentially a simple text file listing things like supported
 data types, reserved words, and other features specific to a
 given dialect of SQL.  These features can also be turned on or
 off during program execution.

=head1 SUPPORTED SQL SYNTAX

This module is meant primarly as a base class for DBD drivers
and as such concentrates on a small but useful subset of SQL 92.
It does *not* in any way pretend to be a complete SQL 92 parser.
The module will continue to add new supported syntax, currently,
this is what is supported:

=head2 CREATE TABLE

 CREATE [ {LOCAL|GLOBAL} TEMPORARY ] TABLE $table
        (
           $col_1 $col_type1 $col_constraints1,
           ...,
           $col_N $col_typeN $col_constraintsN,
        )
        [ ON COMMIT {DELETE|PRESERVE} ROWS ]

     * col_type must be a valid data type as defined in the
       "valid_data_types" section of the dialect file for the
       current dialect

     * col_constriaints may be "PRIMARY KEY" or one or both of
       "UNIQUE" and/or "NOT NULL"

     * IMPORTANT NOTE: temporary tables, data types and column
       constraints are checked for syntax violations but are
       currently otherwise *IGNORED* -- they are recognized by
       the parser, but not by the execution engine

     * The following valid ANSI SQL92 options are not currently
       supported: table constraints, named constraints, check
       constriants, reference constraints, constraint
       attributes, collations, default clauses, domain names as
       data types

=head2 DROP TABLE

 DROP TABLE $table [ RESTRICT | CASCADE ]

     * IMPORTANT NOTE: drop behavior (cascade or restrict) is
       checked for valid syntax but is otherwise *IGNORED* -- it
       is recognized by the parser, but not by the execution
       engine

=head2 INSERT INTO

 INSERT INTO $table [ ( $col1, ..., $colN ) ] VALUES ( $val1, ... $valN )

     * default values are not currently supported
     * inserting from a subquery is not currently supported

=head2 DELETE FROM

 DELETE FROM $table [ WHERE search_condition ]

     * see "search_condition" below

=head2 UPDATE

 UPDATE $table SET $col1 = $val1, ... $colN = $valN [ WHERE search_condition ]

     * default values are not currently supported
     * see "search_condition" below

=head2 SELECT

      SELECT select_clause
        FROM from_clause
     [ WHERE search_condition ]
  [ ORDER BY $ocol1 [ASC|DESC], ... $ocolN [ASC|DESC] ]
     [ LIMIT [start,] length ]

      * select clause ::=
              [DISTINCT|ALL] *
           | [DISTINCT|ALL] col1 [,col2, ... colN]
           | set_function1 [,set_function2, ... set_functionN]

      * set function ::=
             COUNT ( [DISTINCT|ALL] * )
           | COUNT | MIN | MAX | AVG | SUM ( [DISTINCT|ALL] col_name )

      * from clause ::=
             table1 [, table2, ... tableN]
           | table1 NATURAL [join_type] JOIN table2
           | table1 [join_type] table2 USING (col1,col2, ... colN)
           | table1 [join_type] JOIN table2 ON table1.colA = table2.colB

      * join type ::=
             INNER
           | [OUTER] LEFT | RIGHT | FULL

      * if join_type is not specified, INNER is the default
      * if DISTINCT or ALL is not specified, ALL is the default
      * if start position is omitted from LIMIT clause, position 0 is
        the default
      * ON clauses may only contain equal comparisons and AND combiners
      * self-joins are not currently supported
      * if implicit joins are used, the WHERE clause must contain
        and equijoin condition for each table


=head2 SEARCH CONDITION

       [NOT] $val1 $op1 $val1 [ ... AND|OR $valN $opN $valN ]


=head2 OPERATORS

       $op  = |  <> |  < | > | <= | >=
              | IS NULL | IS NOT NULL | LIKE | CLIKE | BETWEEN | IN

  The "CLIKE" operator works exactly the same as the "LIKE"
  operator, but is case insensitive.  For example:

      WHERE foo LIKE 'bar%'   # succeeds if foo is "barbaz"
                              # fails if foo is "BARBAZ" or "Barbaz"

      WHERE foo CLIKE 'bar%'  # succeeds for "barbaz", "Barbaz", and "BARBAZ"


=head2 STRING FUNCTIONS & MATH EXPRESSIONS

  String functions and math expressions are supported in WHERE
  clauses, in the VALUES part of an INSERT and UPDATE
  statements.  They are not currently supported in the SELECT
  statement.  For example:

    SELECT * FROM foo WHERE UPPER(bar) = 'baz'   # SUPPORTED

    SELECT UPPER(foo) FROM bar                   # NOT SUPPORTED

=over

=item  TRIM ( [ [LEADING|TRAILING|BOTH] ['trim_char'] FROM ] string )

Removes all occurrences of <trim_char> from the front, back, or
both sides of a string.

 BOTH is the default if neither LEADING nor TRAILING is specified.

 Space is the default if no trim_char is specified.

 Examples:

 TRIM( string )
   trims leading and trailing spaces from string

 TRIM( LEADING FROM str )
   trims leading spaces from string

 TRIM( 'x' FROM str )
   trims leading and trailing x's from string

=item  SUBSTRING( string FROM start_pos [FOR length] )

Returns the substring starting at start_pos and extending for
"length" character or until the end of the string, if no
"length" is supplied.  Examples:

  SUBSTRING( 'foobar' FROM 4 )       # returns "bar"

  SUBSTRING( 'foobar' FROM 4 FOR 2)  # returns "ba"


=item UPPER(string) and LOWER(string)

These return the upper-case and lower-case variants of the string:

   UPPER('foo') # returns "FOO"
   LOWER('FOO') # returns "foo"

=back

=head2 Identifiers (table & column names)

Regular identifiers (table and column names *without* quotes around them) are case INSENSITIVE so column foo, fOo, FOO all refer to the same column.

Delimited identifiers (table and column names *with* quotes around them) are case SENSITIVE so column "foo", "fOo", "FOO" each refer to different columns.

A delimited identifier is *never* equal to a regular identifer (so "foo" and foo are two different columns).  But don't do that :-).

Remember thought that, in DBD::CSV if table names are used directly as file names, the case sensitivity depends on the OS e.g. on Windows files named foo, FOO, and fOo are the same as each other while on Unix they are different.


=head1 METHODS

=head2 new()

The new() method creates a SQL::Parser object which can then be
used to parse, validate, or build SQL strings.  It takes one
required parameter -- the name of the SQL dialect that will
define the rules for the parser.  A second optional parameter is
a reference to a hash which can contain additional attributes of
the parser.

 use SQL::Parser;
 my $parser = SQL::Parser->new( $dialect_name, \%attrs );

The dialect_name parameter is a string containing any valid
dialect such as 'ANSI', 'AnyData', or 'CSV'.  See the section on
the dialect() method below for details.

The attribute parameter is a reference to a hash that can
contain error settings for the PrintError and RaiseError
attributes.  See the section below on the parse() method for
details.

An example:

  use SQL::Parser;
  my $parser = SQL::Parser->new('AnyData', {RaiseError=>1} );

  This creates a new parser that uses the grammar rules
  contained in the .../SQL/Dialects/AnyData.pm file and which
  sets the RaiseError attribute to true.

For those needing backwards compatibility with SQL::Statement
version 0.1x and lower, the attribute hash may also contain
feature settings.  See the section "FURTHER DETAILS - Backwards
Compatibility" below for details.


=head2 parse()

Once a SQL::Parser object has been created with the new()
method, the parse() method can be used to parse any number of
SQL strings.  It takes a single required parameter -- a string
containing a SQL command.  The SQL string may optionally be
terminated by a semicolon.  The parse() method returns a true
value if the parse is successful and a false value if the parse
finds SQL syntax errors.

Examples:

  1) my $success = $parser->parse('SELECT * FROM foo');

  2) my $sql = 'SELECT * FROM foo';
     my $success = $parser->parse( $sql );

  3) my $success = $parser->parse(qq!
         SELECT id,phrase
           FROM foo
          WHERE id < 7
            AND phrase <> 'bar'
       ORDER BY phrase;
   !);

  4) my $success = $parser->parse('SELECT * FRoOM foo ');

In examples #1,#2, and #3, the value of $success will be true
because the strings passed to the parse() method are valid SQL
strings.

In example #4, however, the value of $success will be false
because the string contains a SQL syntax error ('FRoOM' instead
of 'FROM').

In addition to checking the return value of parse() with a
variable like $success, you may use the PrintError and
RaiseError attributes as you would in a DBI script:

 * If PrintError is true, then SQL syntax errors will be sent as
   warnings to STDERR (i.e. to the screen or to a file if STDERR
   has been redirected).  This is set to true by default which
   means that unless you specifically turn it off, all errors
   will be reported.

 * If RaiseError is true, then SQL syntax errors will cause the
   script to die, (i.e. the script will terminate unless wrapped
   in an eval).  This is set to false by default which means
   that unless you specifically turn it on, scripts will
   continue to operate even if there are SQL syntax errors.

Basically, you should leave PrintError on or else you will not
be warned when an error occurs.  If you are simply validating a
series of strings, you will want to leave RaiseError off so that
the script can check all strings regardless of whether some of
them contain SQL errors.  However, if you are going to try to
execute the SQL or need to depend that it is correct, you should
set RaiseError on so that the program will only continue to
operate if all SQL strings use correct syntax.

IMPORTANT NOTE #1: The parse() method only checks syntax, it
does NOT verify if the objects listed actually exist.  For
example, given the string "SELECT model FROM cars", the parse()
method will report that the string contains valid SQL but that
will not tell you whether there actually is a table called
"cars" or whether that table contains a column called 'model'.
Those kinds of verifications can be performed by the
SQL::Statement module, not by SQL::Parser by itself.

IMPORTANT NOTE #2: The parse() method uses rules as defined by
the selected dialect configuration file and the feature()
method.  This means that a statement that is valid in one
dialect may not be valid in another.  For example the 'CSV' and
'AnyData' dialects define 'BLOB' as a valid data type but the
'ANSI' dialect does not.  Therefore the statement 'CREATE TABLE
foo (picture BLOB)' would be valid in the first two dialects but
would produce a syntax error in the 'ANSI' dialect.

=head2 structure()

After a SQL::Parser object has been created and the parse()
method used to parse a SQL string, the structure() method
returns the data structure of that string.  This data structure
may be passed on to other modules (e.g. SQL::Statement) or it
may be printed out using, for example, the Data::Dumper module.

The data structure contains all of the information in the SQL
string as parsed into its various components.  To take a simple
example:

 $parser->parse('SELECT make,model FROM cars');
 use Data::Dumper;
 print Dumper $parser->structure;

Would produce:

 $VAR1 = {
          'column_names' => [
                              'make',
                              'model'
                            ],
          'command' => 'SELECT',
          'table_names' => [
                             'cars'
                           ]
        };

Please see the section "FURTHER DETAILS -- Parse structures"
below for further examples.

=head2 build()

This method is in progress and should be available soon.

=head2 dialect()

 $parser->dialect( $dialect_name );     # load a dialect configuration file
 my $dialect = $parser->dialect;        # get the name of the current dialect

 For example:

   $parser->dialect('AnyData');  # loads the AnyData config file
   print $parser->dialect;       # prints 'AnyData'

 The $dialect_name parameter may be the name of any dialect
 configuration file on your system.  Use the
 $parser->list('dialects') method to see a list of available
 dialects.  At a minimum it will include "ANSI", "CSV", and
 "AnyData".  For backwards compatiblity 'Ansi' is accepted as a
 synonym for 'ANSI', otherwise the names are case sensitive.

 Loading a new dialect configuration file erases all current
 parser features and resets them to those defined in the
 configuration file.

 See the section above on "Dialects" for details of these
 configuration files.

=head2 feature()

Features define the rules to be used by a specific parser
instance.  They are divided into the following classes:

    * valid_commands
    * valid_options
    * valid_comparison_operators
    * valid_data_types
    * reserved_words

Within each class a feature name is either enabled or
disabled. For example, under "valid_data_types" the name "BLOB"
may be either disabled or enabled.  If it is not eneabled
(either by being specifically disabled, or simply by not being
specified at all) then any SQL string using "BLOB" as a data
type will throw a syntax error "Invalid data type: 'BLOB'".

The feature() method allows you to enable, disable, or check the
status of any feature.

 $parser->feature( $class, $name, 1 );             # enable a feature

 $parser->feature( $class, $name, 0 );             # disable a feature

 my $feature = $parser->feature( $class, $name );  # show status of a feature

 For example:

 $parser->feature('reserved_words','FOO',1);       # make 'FOO' a reserved word

 $parser->feature('valid_data_types','BLOB',0);    # disallow 'BLOB' as a
                                                   # data type

                                                   # determine if the LIKE
                                                   # operator is supported
 my $LIKE = $parser->feature('valid_operators','LIKE');

See the section below on "Backwards Compatibility" for use of
the feature() method with SQL::Statement 0.1x style parameters.

=head2 list()

=head2 errstr()

=head1 FURTHER DETAILS

=head2 Dialect Configuration Files

These will change completely when Tim finalizes the DBI get_info method.

=head2 Parse Structures

Here are some further examples of the data structures returned
by the structure() method after a call to parse().  Only
specific details are shown for each SQL instance, not the entire
struture.

 'SELECT make,model, FROM cars'

      command => 'SELECT',
      table_names => [ 'cars' ],
      column_names => [ 'make', 'model' ],

 'CREATE TABLE cars ( id INTEGER, model VARCHAR(40) )'

      column_defs => {
          id    => { data_type => INTEGER     },
          model => { data_type => VARCHAR(40) },
      },

 'SELECT DISTINCT make FROM cars'

      set_quantifier => 'DISTINCT',

 'SELECT MAX (model) FROM cars'

    set_function   => {
        name => 'MAX',
        arg  => 'models',
    },

 'SELECT * FROM cars LIMIT 5,10'

    limit_clause => {
        offset => 5,
        limit  => 10,
    },

 'SELECT * FROM vars ORDER BY make, model DESC'

    sort_spec_list => [
        { make  => 'ASC'  },
        { model => 'DESC' },
    ],

 "INSERT INTO cars VALUES ( 7, 'Chevy', 'Impala' )"

    values => [ 7, 'Chevy', 'Impala' ],


=head2 Backwards Compatibility

This module can be used in conjunction with SQL::Statement,
version 0.2 and higher.  Earlier versions of SQL::Statement
included a SQL::Parser as a submodule that used slightly
different syntax than the current version.  The current version
supports all of this earlier syntax although new users are
encouraged to use the new syntax listed above.  If the syntax
listed below is used, the module should be able to be subclassed
exactly as it was with the older SQL::Statement versions and
will therefore not require any modules or scripts that used it
to make changes.

In the old style, features of the parser were accessed with this
syntax:

 feature('create','type_blob',1); # allow BLOB as a data type
 feature('create','type_blob',0); # disallow BLOB as a data type
 feature('select','join',1);      # allow multi-table statements

The same settings could be acheieved in calls to new:

  my $parser = SQL::Parser->new(
      'Ansi',
      {
          create => {type_blob=>1},
          select => {join=>1},
      },
  );

Both of these styles of setting features are supported in the
current SQL::Parser.

=head1 ACKNOWLEDGEMENTS

*Many* thanks to Ilya Sterin who wrote most of code for the
 build() method and who assisted on the parentheses parsing code
 and who proved a great deal of support, advice, and testing
 throughout the development of the module.

=head1 AUTHOR & COPYRIGHT

 This module is copyright (c) 2001 by Jeff Zucker.
 All rights reserved.

 The module may be freely distributed under the same terms as
 Perl itself using either the "GPL License" or the "Artistic
 License" as specified in the Perl README file.

 Jeff can be reached at: jeff@vpservices.com.

=cut
