package DBI::Shell::Completion;
# vim:ts=4:sw=4:ai:aw:nowrapscan

use strict;
use vars qw(@ISA $VERSION);
use Carp;

$VERSION = sprintf( "%d.%02d", q$Revision: 11.91 $ =~ /(\d+)\.(\d+)/ );

my ($loa, @matches, @tables, @table_list, $tbl_nm, $term, $history);


sub init {
    my ($class, $sh, @args) = @_;
	$class = ref $class || $class;
	$loa = {
		'catalogs'	=> undef,
		'commands' => undef,
		'sql'    => [ sort qw(
		    select insert update delete
			alter grant revoke
			from where order by desc asc
		    join exists spool
			set min max avg count
			into values
		   ) ],
		'select_func' => [ sort qw(
			count(*) min max avg as distinct unique
		) ],
		'schemas' => undef, 
		'system' => undef, 
		'tables'  => undef,
		'ntables'  => undef,	# Maintain a list of columns by table.
		'sql_keywords' => undef,
		'users'   => undef,
		'views'   => undef,
		'term'    => undef, # Maintain a reference to the term type.
		'history' => '.dbish_history',
		'command_prefix' => undef,
		'columns'	=> undef,
	};

	

	# Modify the history location to use the users home directory, if
	# available.
	# TODO: Change this to be less unix more perl
	$loa->{history} = $sh->{home_dir} . '/' . $loa->{history}
		if (exists $sh->{home_dir} and defined $sh->{home_dir});

	$sh->log( "commandline history written to $loa->{history}" );

    my $pi = bless $loa, $class;

	# return if term is not defined.  
	return unless $sh->{term};

	$term = $sh->{term};

    my $attribs = $term->Attribs();
    $attribs->{history_length} = '500';

	$pi->{term} = \$sh->{term};
	$pi->{dbh} = \$sh->{dbh};
	$pi->{command_prefix} = \$sh->{command_prefix};

 	if ($term->ReadLine eq "Term::ReadLine::Gnu") {
		print "Using Term::ReadLine::Gnu\n";

		# Only source the current drivers Completion, if exists.
		$sh->{completion} = $pi;

		# Define the completion function.
		my $ssc = sub {
			return $pi->sql_shell_completion(@_);
		};
    	$attribs->{attempted_completion_function} = $ssc;

    	# read in the history file.
    	if(-e $pi->{history}) {
			$sh->log ("History file $pi->{history} not restored!" )
    			unless($term->ReadHistory($pi->{history}));
		} else { 
			print "Creating ${history} to store your command line history\n";
    		open(HISTORY, "> $pi->{history}") 
				or $sh->log ("Could not create $pi->{history}: $!"); 
			close(HISTORY);
		}

	}

	return $pi;
}

# sub load_completion {
#     my $cpi = shift;
# 	my $sh  = shift;
#     my @pi;
#     foreach my $where (qw(DBI/Shell/Completion DBI_Shell_Completion)) {
# 	my $mod = $where; $mod =~ s!/!::!g; #/ so vim see the syn correctly
# 	my @dir = map { -d "$_/$where" ? ("$_/$where") : () } @INC;
# 		foreach my $dir (@dir) {
# 	    	opendir DIR, $dir or warn "Unable to read $dir: $!\n";
# 	    	push @pi, map { s/\.pm$//; "${mod}::$_" } grep { /\.pm$/ }
# 	        	readdir DIR;
# 	    	closedir DIR;
# 		}
#     }
# 	my $driver = $sh->{data_source};
# 	# print STDERR join( " ", @pi, $driver, "\n");
#     foreach my $pi (sort @pi) {
# 		#local $DBI::Shell::SHELL = $sh; # publish the current shell
# 		eval qq{ use $pi };
# 		$sh->alert("Unable to load $pi: $@") if $@;
#     }
#     # plug-ins should remove options they recognise from (localized) @ARGV
#     # by calling Getopt::Long::GetOptions (which is already in pass_through mode).
#     foreach my $pi (@pi) {
# 		#local *ARGV = $sh->{unhandled_options};
# 	$pi->init($sh);
#     }
# }

sub populate {
	my $sh = shift;
	my $list = shift;

	return $loa unless $list;
	return undef unless exists $loa->{$list};

	# print ( "$list populate ...", join " ", @_, "\n" );

	if (@_) {  # User provided a list of values.
		$loa->{$list} = [ @_ ];
	} 
	return $loa->{$list};
}

# Attempt to complete on the contents of TEXT.  START and END bound
# the region of rl_line_buffer that contains the word to complete.
# TEXT is the word to complete.  We can use the entire contents of
# rl_line_buffer in case we want to do some simple parsing.  Return
# the array of matches, or NULL if there aren't any.
sub sql_shell_completion {
	my $sh = shift;
    my ($text, $line, $start, $end) = @_;

    my @matches = ();

	undef $tbl_nm;

	# Notes for future development.  The $line is the complete line,
	# start is where the text begins, end where text ends (looks like word
	# boundies).  I need to attempt to determine where I'm in the line, and
	# what was the last key word given.

	# print STDERR "text:$text: line:$line: start:$start: end:$end:\n";
	my $cmd_p = ${$sh->{command_prefix}};

	# Load the keywords.
	unless (defined $loa->{sql_keywords}) {
		eval {
			# Not all drivers support the get_info function yet, so we
			# need a fall back plan.
			my $key_words = ${$sh->{dbh}}->get_info( 'SQL_KEYWORDS' );
			die unless (defined $key_words);
			my @key_words = split( /\s+/, $key_words);
			die unless (@key_words); # Keywords not supported by driver, default
			$sh->populate( q{sql_keywords}, @key_words )
				unless (defined $loa->{sql_keywords});
		};

		if($@) {
			$sh->populate( q{sql_keywords}, @{$sh->{sql}} );
		}
	}

	unless (defined $loa->{columns}) {
		eval {
			my $sth = ${$sh->{dbh}}->column_info( undef, undef, undef, undef );
			die unless $sth; # column_info not supported by all drivers.
			my (%catalogs, %schemas, %tables, %columns);
			while ( my $row = $sth->fetchrow_arrayref ) {
				$catalogs{$row->[0]}++ if defined $row->[0];	
				$schemas{$row->[1]}++  if defined $row->[1];	
				$tables{$row->[2]}++   if defined $row->[2];	
				$columns{$row->[3]}++  if defined $row->[3];	

				push ( @{$loa->{ntables}->{$row->[2]}}, $row->[3] );
			}
			push( @{$loa->{catalogs}}, sort keys %catalogs ); 
			push( @{$loa->{schemas}},  sort keys %schemas  ); 
			push( @{$loa->{columns}},  sort keys %columns  ); 
		};

		push( @{$loa->{columns}}, @{$sh->{select_func}} ); 
	}

	# print "line: $line - $cmd_p\n" if $line;
	# Begin by loading all the key words, if available.
    if ( $start == 0 ) {
		# SQL_KEYWORDS
    	@matches = 
			${$sh->{term}}->completion_matches($text,
				\&sql_keywords_gen);
	}
	# If the last word is "from" attempt to match a schema or table name.
	elsif( 
		$line=~ m/
			\bfrom(?:\s*)?(?:['"])?$
			|
			\bfrom(?:\s*)(?:['"])?(?:[\w.]+)
			|
			\binsert\s+into(?:\s+)?$
			|
			\binsert\s+into\s+(?:['"])?(?:\w+|[\w+.]|\w+\.\w+)$
			|
			\bupdate(?:\s*)?(?:['"])?(?:\w+)?$
			|
			^${cmd_p}desc(?:\s*)?(?:['"])?(?:\w+)?
			/xi 
	) {
		$sh->populate(q{tables},
			${$sh->{dbh}}->tables) unless($loa->{tables});
    	@matches = ${$sh->{term}}->completion_matches($text, \&table_generator);
		# |
		# ^${cmd_p}desc(?:\s+)(?:['"])?\w+?$
	} 
	# If we find a select on the line display a column list.
	elsif( $line=~ m/select\s+?$|select\s+\w+?$/i ) {
    	@matches = ${$sh->{term}}->completion_matches($text,
			\&column_generator);
	}
	elsif( $line=~ m/
		^insert\s+
		into\s+
		((?:\w+|\w+\.\w+))\s+?\(			# )
		/xi ) {
		$tbl_nm = $1;
		unless( exists $loa->{ntables}->{$tbl_nm} ) {
			eval {
				my $sth = ${$sh->{dbh}}->column_info( undef, undef, $tbl_nm, undef );
				die unless $sth; # column_info not supported by all drivers.
				push( @{$loa->{ntables}->{$tbl_nm}},
					@{$sth->fetchall_arrayref( [3] )} ); 
				
			};

			if ($@) {
				# Column Info not supported, do it the hard way.
				{
					local (${$sh->{dbh}}->{PrintError},
						${$sh->{dbh}}->{RaiseError});
					${$sh->{dbh}}->{PrintError} = 0;
					${$sh->{dbh}}->{RaiseError} = 0;
					my $sth = ${$sh->{dbh}}->prepare( qq{select * from $tbl_nm where 1 = 2} );
					$sth->execute;

					unless($sth->err) {
						push( @{$loa->{ntables}->{$tbl_nm}}, @{$sth->{NAME}} ); 
					}
					$sth->finish;
				}
			}

		}

    	@matches = ${$sh->{term}}->completion_matches($text,
			\&col_tab_gen );
	}
	else {
		# match commands for now.
    	@matches = 
			${$sh->{term}}->completion_matches($text, \&sql_keywords_gen);
	} 

    return @matches;
}

# Generator function for command completion.  STATE lets us know
# whether to start from scratch; without any state (i.e. STATE == 0),
# then we start at the top of the list.

## Term::ReadLine::Gnu has list_completion_function similar with this
## function.  I defined new one to be compared with original C version.
{
    my $list_index;
    my (@name, @columns, @tables);

    sub column_generator {
	my ($text, $state) = @_;

	# If this is a new word to complete, initialize now.  This
	# includes saving the length of TEXT for efficiency, and
	# initializing the index variable to 0.
	unless ($state) {
	    $list_index = 0;
	    @columns = @{$loa->{columns}};
	}

	# Return the next name which partially matches from the
	# command list.
	while ($list_index <= $#columns) {
	    $list_index++;
	    return $columns[$list_index - 1]
			if ($columns[$list_index - 1] =~ /^$text/i);
	}
	# If no names matched, then return NULL.
	return undef;
    }

    sub col_tab_gen {
	my ($text, $state) = @_;

	# Just return undef for now.

	# If this is a new word to complete, initialize now.  This
	# includes saving the length of TEXT for efficiency, and
	# initializing the index variable to 0.
	unless ($state) {
	    $list_index = 0;
		if (exists $loa->{ntables}->{$tbl_nm}) {
			@columns = @{$loa->{ntables}->{$tbl_nm}};
		}
		else {
	    	@columns = @{$loa->{columns}};
		}
	}

	# Return the next name which partially matches from the
	# command list.
	while ($list_index <= $#columns) {
	    $list_index++;
	    return $columns[$list_index - 1]
			if ($columns[$list_index - 1] =~ /^$text/i);
	}
	# If no names matched, then return NULL.
	return undef;
    }

    sub sql_generator {
	my ($text, $state) = @_;

	# If this is a new word to complete, initialize now.  This
	# includes saving the length of TEXT for efficiency, and
	# initializing the index variable to 0.
	unless ($state) {
	    $list_index = 0;
	    @name = @{$loa->{sql}};
	}

	# Return the next name which partially matches from the
	# command list.
	while ($list_index <= $#name) {
	    $list_index++;
	    return $name[$list_index - 1]
		if ($name[$list_index - 1] =~ /^$text/i);
	}
	# If no names matched, then return NULL.
	return undef;
    }

    sub sql_keywords_gen {
	my ($text, $state) = @_;

	# If this is a new word to complete, initialize now.  This
	# includes saving the length of TEXT for efficiency, and
	# initializing the index variable to 0.
	unless ($state) {
	    $list_index = 0;
	    @name = @{$loa->{sql_keywords}};
	}

	# Return the next name which partially matches from the
	# command list.
	while ($list_index <= $#name) {
	    $list_index++;
	    return $name[$list_index - 1]
			if ($name[$list_index - 1] =~ /^$text/i);
	}
	# If no names matched, then return NULL.
	return undef;
    }
}

{
    my $list_index;

    sub table_generator {
	my ($text, $state) = @_;

	# If this is a new table to complete, initialize now.  This
	# includes saving the length of TEXT for efficiency, and
	# initializing the index variable to 0.
	unless ($state) {
	    $list_index = 0;
	    @tables =	@{$loa->{tables}};
	}

	# Return the next name which partially matches from the
	# command list.
	while ($list_index <= $#tables) {
	    $list_index++;
	    return $tables[$list_index - 1]
		if ($tables[$list_index - 1] =~ /^$text/i);
	}
	# If no names matched, then return NULL.
	return undef;
    }
}

DESTROY {
	my $sh = shift;
	# term is store as a package variable.
 	if ($term && $term->ReadLine eq "Term::ReadLine::Gnu") {
		if($term && $term->history_total_bytes()) {
			my $history = $sh->{completion}->{history};
			if ($history) {
				unless($term->WriteHistory($history)) {
					carp ("Could not write history file $history to history_file}. ");
				}
			}
		}
	}

	$term = undef; $sh->{term} = undef;
}

END { }

1;
__END__
