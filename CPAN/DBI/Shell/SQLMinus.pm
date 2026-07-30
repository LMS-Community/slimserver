#!perl -w
# vim:ts=4:sw=4:aw:ai:nowrapscan
#
#

package DBI::Shell::SQLMinus;

use strict;
use Text::Abbrev ();
use Text::ParseWords;
use Text::Wrap;
use IO::File;
use IO::Tee;
use Carp;

use vars qw(@ISA $show $set $VERSION);

$VERSION = sprintf( "%d.%02d", q$Revision: 11.91 $ =~ /(\d+)\.(\d+)/ );

sub init {
    my ($class, $sh, @args) = @_;
	$class = ref $class || $class;
	my $sqlminus = {
		archive	=> {
			log	=> undef,
		},
		'breaks' => {
			skip		=> [ qw{text} ],
			skip_page	=> [ qw{text} ],
			dup			=> [ qw{text} ],
			nodup		=> [ qw{text} ],
		},
		break_current => {
		},
		'clear'	=> {
			break	=> undef,
			buffer	=> undef,
			columns	=> undef,
			computes	=> undef,
			screen	=> undef,
			sql		=> undef,
			timing	=> undef,
		},
		db	=> undef,
		dbh => undef,
		column => {
			column_name	=> [ qw{text} ],
			alias		=> [ qw{text} ],
			clear		=> [ qw{command} ],
			fold_after	=> [ qw{text} ],
			fold_before	=> [ qw{text} ],
			format		=> [ qw{text} ],
			heading		=> [ qw{text} ],
			justify		=> [ qw{c l r f} ],
			like		=> [ qw{text} ],
			'length'	=> [ qw{text} ],
			newline		=> [ qw{text} ],
			new_value	=> [ qw{text} ],
			noprint		=> [ qw{on off} ],
			'print'		=> [ qw{on off} ],
			null		=> [ qw{text} ],
			on			=> 1,
			off			=> 0,
			truncated	=> [ qw{on off} ],
			type		=> [ qw{text} ],
			wordwrapped	=> [ qw{on off} ],
			wrapped		=> [ qw{on off} ],
			column_format	=> undef,
			format_function => undef,
			precision	=>	undef,
			scale		=> undef,
		},
		# hash ref contains formats for code.
		column_format => {
		},
		# Hash ref contains the formats for the column headers.
		column_header_format => {
		},
		commands => {
			'@'		=> undef,
			'accept'=> undef,
			append	=> undef,
			attribute => undef,
			break	=> undef,
			btitle	=> undef,
			change	=> undef,
			clear	=> undef,
			copy	=> undef,
			column	=> undef,
			compute	=> undef,
			define	=> undef,
			edit	=> undef,
			'exec'	=> undef,
			get		=> undef,
			pause	=> undef,
			prompt	=> undef,
			repheader=> undef,
			repfooter=> undef,
			run		=> undef,
			save	=> undef,
			set		=> undef,
			show	=> undef,
			start	=> undef,
			ttitle	=> undef,
			undefine=> undef,
		},
		set_current	=> {
			appinfo		=> undef,
			arraysize	=> undef,
			autocommit	=> undef,
			autoprint	=> undef,
			autorecovery=> undef,
			autotrace	=> undef,
			blockterminator=> undef,
			buffer		=> undef,
			closecursor	=> undef,
			cmdsep		=> undef,
			compatibility=> undef,
			concat		=> undef,
			copycommit	=> undef,
			copytypecheck=> undef,
			define		=> undef,
			document	=> undef,
			echo		=> undef,
			editfile	=> undef,
			embedded	=> undef,
			escape		=> undef,
			feedback	=> undef,
			flagger		=> undef,
			flush		=> undef,
			heading 	=> 1,
			headsep 	=> ' ',
			instance 	=> undef,
			linesize	=> 72,
			limit		=> undef,
			loboffset	=> undef,
			logsource	=> undef,
			long		=> undef,
			longchunksize	=> undef,
			maxdata		=> undef,
			newpage		=> undef,
			null		=> undef,
			numwidth	=> undef,
			pagesize	=> undef,
			pause		=> undef,
			recsep 		=> 1,
			recsepchar 	=> ' ',
			scan		=> qq{obsolete command: use 'set define' instead},
			serveroutput=> undef,
			shiftinout	=> undef,
			showmode	=> undef,
			space		=> qq{obsolete command: use 'set define' instead},
			sqlblanklines=> undef,
			sqlcase		=> undef,
			sqlcontinue	=> undef,
			sqlnumber	=> undef,
			sqlprefix	=> undef,
			sqlprompt	=> undef,
			sqlterminator=> undef,
			suffix		=> undef,
			tab			=> undef,
			termout		=> undef,
			'time'		=> undef,
			'timing'	=> undef,
			trimout		=> undef,
			trimspool	=> undef,
			'truncate'	=> undef,
			underline	=> '-',
			verify		=> undef,
			wrap		=> undef,
		},
		# Each set command may call a custom function.  Included are
		# currently defined sets.  For simple set/get, the value is
		# stored set_current.
		set_commands => {

			appinfo		=> ['_unimp'],
			arraysize	=> ['_unimp'],
			autocommit	=> ['_unimp'],
			autoprint	=> ['_unimp'],
			autorecovery	=> ['_unimp'],
			autotrace	=> ['_unimp'],

			blockterminator	=> ['_unimp'],
			buffer		=> ['_unimp'],

			closecursor	=> ['_unimp'],
			cmdsep		=> ['_unimp'],
			compatibility	=> ['_unimp'],
			concat		=> ['_unimp'],
			copycommit	=> ['_unimp'],
			copytypecheck	=> ['_unimp'],

			define		=> ['_unimp'],
			document	=> ['_unimp'],

			echo		=> ['_set_get'],
			editfile	=> ['_unimp'],
			embedded	=> ['_unimp'],
			escape		=> ['_unimp'],

			feedback	=> ['_unimp'],
			flagger		=> ['_unimp'],
			flush		=> ['_unimp'],

			heading 	=> ['_set_get'],
			headsep 	=> ['_set_get'],

			instance 	=> ['_unimp'],

			linesize	=> ['_set_get'],
			limit		=> ['_set_get'],
			loboffset	=> ['_unimp'],
			logsource	=> ['_unimp'],
			long		=> ['_unimp'],
			longchunksize	=> ['_unimp'],

			maxdata		=> ['_unimp'],

			newpage		=> ['_unimp'],
			null		=> ['_set_get'],
			numwidth	=> ['_unimp'],

			pagesize	=> ['_set_get'],
			pause		=> ['_unimp'],

			recsep 		=> ['_set_get'],
			recsepchar 	=> ['_set_get'],

			scan		=> ['_print_buffer', 
				qq{obsolete command: use 'set define' instead}],
			serveroutput	=> ['_unimp'],
			shiftinout	=> ['_unimp'],
			showmode	=> ['_unimp'],
			space		=> ['_print_buffer', 
				qq{obsolete command: use 'set define' instead}],
			sqlblanklines	=> ['_unimp'],
			sqlcase		=> ['_unimp'],
			sqlcontinue	=> ['_unimp'],
			sqlnumber	=> ['_unimp'],
			sqlprefix	=> ['_unimp'],
			sqlprompt	=> ['_unimp'],
			sqlterminator	=> ['_unimp'],
			suffix		=> ['_unimp'],

			tab			=> ['_unimp'],
			termout		=> ['_unimp'],
			'time'		=> ['_unimp'],
			'timing'	=> ['_unimp'],
			trimout		=> ['_unimp'],
			trimspool	=> ['_unimp'],
			'truncate'	=> ['_unimp'],

			underline	=> ['_set_get'],

			verify		=> ['_unimp'],

			wrap		=> ['_unimp'],
		},
		show => {
			all           => ['_all'],

			btitle        => ['_unimp'],

			catalogs      => ['_unimp'],
			columns       => ['_unimp'],

			errors        => ['_unimp'],

			grants        => ['_unimp'],

			help          => ['_help'],
			hints         => ['_hints'],

			lno           => ['_hints'],

			me            => ['_me'],

			objects       => ['_unimp'],

			packages      => ['_unimp'],
			parameters    => ['_unimp'],
			password      => ['_print_buffer', qq{I don\'t think so!}],
			pno           => ['_unimp'],

			release       => ['_unimp'],
			repfooter     => ['_unimp'],
			repheader     => ['_unimp'],
			roles         => ['_unimp'],

			schemas       => ['_schemas'],
			sga           => ['_unimp'],
			show          => ['_show_all_commands'],
			spool         => ['_spool'],
			sqlcode       => ['_sqlcode'],

			ttitle        => ['_unimp'],
			tables        => ['_tables'],
			types	      => ['_types'],

			users         => ['_unimp'],

			views         => ['_views'],
		},
		sql => {
			pno	=> undef,
			lno	=> undef,
			release	=> undef,
			user	=> undef,
		},
	};

    my $pi = bless $sqlminus, $class;

# add the sqlminus object to the plugin list for reference later.
	$sh->{plugin}->{sqlminus} = $pi;

	$pi->{dbh} = \$sh->{dbh};

	my $com_ref = $sh->{commands};

	foreach (sort keys %{$pi->{commands}}) {
		$com_ref->{$_} = {
			hint => "SQLMinus: $_",
		};
	}
	return $pi;
}
#	'btittle' => {
#		off => undef,
#		on	=> undef,
#		col	=> undef,
#		skip	=> undef,
#		tab	=> undef,
#		left	=> undef,
#		center	=> undef,
#		right	=> undef,
#		bold	=> undef,
#		format	=> undef,
#		text	=> undef,
#		variable	=> undef,
#	},
#
# break.
#
# BRE[AK] [ON report_element [action [action]]] ...
# 
# where:
# 
# report_element
# 
# Requires the following syntax:
# 
# {column|expr|ROW|REPORT}
# 
# action
# 
# Requires the following syntax:
# 
# [SKI[P] n|[SKI[P]] PAGE][NODUP[LICATES]|DUP[LICATES]]
# 
sub do_break {
	my ($self, $command, @args) = @_;

	# print "break command:\n";

	my $breaks = $self->{plugin}->{sqlminus}->{breaks};
	my $cbreaks = $self->{plugin}->{sqlminus}->{break_current};

	unless( $command ) {
		my $maxlen = 0;
		foreach (keys %$cbreaks ) {
			$maxlen = (length $_ > $maxlen? length $_ : $maxlen );
		}
		my $format = sprintf("%%-%ds", $maxlen );
		foreach my $col_name (sort keys %$cbreaks) { 
			$self->log( sprintf( $format, $col_name ));
			foreach my $col (sort keys %$breaks) {
				next unless $cbreaks->{$col_name}->{$col};
				$self->print_buffer_nop(sprintf( "\t%-15s %s\n", $col, 
					($cbreaks->{$col_name}->{$col}||'undef') ));
			}
		}
		return;
	}

	my @words = quotewords('\s+', 0, join( " ", @args));

	WORD:
	while(@words) {
		my $val = shift @words;

		if		($val =~ m/row/i	) {
		} elsif	($val =~ m/report/i	) {
		} elsif	($val =~ m/on/i		) { # Skip on
			next WORD;
		} else {
			# Handle a column.
			if (exists $cbreaks->{$val}) {
				delete $cbreaks->{$val};
			}
			$cbreaks->{$val} = {
				  skip => undef
				, nodup => undef
			}; # Create the column in the break group.

			ACTION:
			while(@words) {
				my $action = shift @words;
				$self->print_buffer_nop( "actin $action" );
				last unless $action =~ m/\bskip|\bpage|\bnodup|\bdup/i;
				
# These are the accepted action given to a break.
				if		($action =~ m/\bskip/i	) {
# Skip consumes the next value, either page or a number.
					my $skip_val = shift @words if (@words);
					unless ($skip_val) {
						$self->print_buffer( 
							qq{break: action $action number lines|page} );
						last;
					}

					$self->print_buffer_nop( "action $action $skip_val" );
					if ($skip_val =~ m/(\d+)/) {
						$cbreaks->{$val}->{skip} =  $skip_val;
						delete $cbreaks->{$val}->{skip_page} 
							if (exists $cbreaks->{$val}->{skip_page});
					} else {
						$cbreaks->{$val}->{skip_page} = 1;
						delete $cbreaks->{$val}->{skip} 
							if (exists $cbreaks->{$val}->{skip});
					}
# Default value, if nodup/dup is not defined, add.
					unshift @words, 'nodup';
					unshift @words, 'nodup' unless (exists
						$cbreaks->{$val}->{dup} or exists
						$cbreaks->{$val}->{nodup});

				} elsif ($action =~ m/\bnodup/i	) {
					$cbreaks->{$val}->{nodup} =  1;
					delete $cbreaks->{$val}->{dup} 
							if (exists $cbreaks->{$val}->{dup});
				} elsif ($action =~ m/\bdup/i	) {
					$cbreaks->{$val}->{dup} =  1;
					delete $cbreaks->{$val}->{nodup} 
							if (exists $cbreaks->{$val}->{nodup});
				} elsif ($action =~ m/\bpage/i	) {
# Put skip in front of the value and let the skip command handle it.
					unshift @words, 'skip', $action;
				} else {
					$self->print_buffer( 
						qq{break: action $action unknown, ambiguous, or not supported.} );
					last;
				}
			}
		}
		return;
	}

	return 
	$self->print_buffer( 
		qq{break: $command unknown, ambiguous, or not supported.} );
}

#
# set
#
sub do_set {
	my ($self, $command, @args) = @_;


	# print "set command:\n";

	my $set = $self->{plugin}->{sqlminus}->{set_current};

	unless( $command ) {
		my $maxlen = 0;
		foreach (keys %$set ) {
			$maxlen = (length $_ > $maxlen? length $_ : $maxlen );
		}
		my $format = sprintf("%%-%ds %%s", $maxlen );
		foreach (sort keys %$set) { 
			$self->log( 
				sprintf( $format, $_, $set->{$_} || 'undef' )
			);
		}
		return;
	}

    my $options = Text::Abbrev::abbrev(keys %$set);

	my $ref = $self->{plugin}->{sqlminus};

	if (my $c = $options->{$command}) {
		$self->log( "command: $command " . ref $c . "" );
		if (my $c = $options->{$command}) {
			my ($cmd, @cargs) = @{$ref->{set_commands}->{$c}};
			push(@args, @cargs) if @cargs;
			return $self->{plugin}->{sqlminus}->$cmd(\$self,$c,@args);
		}
	}
	my %l;
	foreach (keys %$options) { $l{$options->{$_}}++ if m/^$command/ }
	my $sug = wrap( "\t(", "\t\t", sort keys %l );
	$sug = "\n$sug)"	if defined $sug;
	$sug = q{}			unless defined $sug;
return 
	$self->print_buffer( 
		qq{set: $command unknown, ambiguous, or not supported.$sug} );
}

# show
sub do_show {
	my ($self, $command, @args) = @_;

	return unless $command;

	my $show = $self->{plugin}->{sqlminus}->{show};
	my $ref = $self->{plugin}->{sqlminus};

    my $options = Text::Abbrev::abbrev(keys %$show);
	if (my $c = $options->{$command}) {
		my ($cmd, @cargs) = @{$ref->{show}->{$c}};
		push(@args, @cargs) if @cargs;
		return $self->{plugin}->{sqlminus}->$cmd(\$self,@args);
	}
	my %l;
	foreach (keys %$options) { $l{$options->{$_}}++ if m/^$command/ }
	my $sug = wrap( "\t(", "\t\t", sort keys %l );
	$sug = "\n$sug)"	if		defined $sug;
	$sug = q{}			unless	defined $sug;  # rid warnings
return 
	$self->print_buffer( 
		qq{show: $command unknown, ambiguous, or not supported.$sug} );
}

#
# Attempt to allow the user to define format string for query results.
#


sub do_column {
	my ($self, $command, @args) = @_;

	# print "column command:\n" if $self->{debug};

	# my $set = $column_format;
	my $ref						= $self->{plugin}->{sqlminus};
	my $column					= $ref->{column};
	my $column_format			= $ref->{column_format};
	my $column_header_format	= $ref->{column_header_format};

	# If just the format command is issued, print all the current formatted
	# columns.  Currently, only the column name is printed.
	unless( $command ) {
		my $maxlen = 0;
		foreach (keys %$column_format ) {
			$maxlen = (length $_ > $maxlen? length $_ : $maxlen );
		}
		my $format = sprintf("%%-%ds", $maxlen );
		foreach my $col_name (sort keys %$column_format) { 
			$self->log( sprintf( $format, $col_name ));
			foreach my $col (sort keys %$column) {
				next unless $column_format->{$col_name}->{$col};
				$self->print_buffer_nop(sprintf( "\t%-15s %s\n", $col, 
					($column_format->{$col_name}->{$col}||'undef') ));
			}
		}
		return;
	}

	if ( $command =~ m/clear/i ) {
		# clear the format for either one or all columns.
		if (@args) {
			# Next argument column to clear.
			my $f = shift @args;
			# Format defined?
			$self->_clear_format( \$column_format, $f );
		} else {
			# remove all column formats.

			foreach my $column (keys %$column_format) {
				# warn "Removing format for : $column :\n";
				$self->_clear_format( \$column_format, $column );
			}

			# map { delete $column_format->{$_} } keys %$column_format 
				# if exists $ref->{column_format};
			# map { delete $column_header_format->{$_} } 
				# keys %$column_header_format 
				# if exists $ref->{column_header_format};
		}

	return $self->log( "format cleared" );
	}

	#
	# If column called with only a column name, display the current format.
	#

	unless( @args ) {
		return $self->log( "$command: no column format defined." ) 
			unless exists $column_format->{$command};

		$self->log( "column $command format: " );
		foreach my $col (sort keys %{$column_format->{$command}}) {
			next unless $column_format->{$command}->{$col};
			$self->print_buffer_nop(sprintf( "\t%-15s %s"
				, $col
				, ($column_format->{$command}->{$col}||'undef') ));
		}
		return;
	}

	# print "column: $command ", join( " ", @args) , "\n" if $self->{debug};

	#
	# column: column name.
	#

	# Builds a structure of attributes supported in column formats.
	my ($col, $col_head);
	unless ( exists $column_format->{$command} ) {
		my $struct = {};
		foreach (keys %$column) {
			$struct->{$_} = undef;
		}
		$column_format->{$command} = $struct;

		$col = $column_format->{$command};

		$col->{on} = 1;
		$col->{off} = 0;
	}

	$col = $column_format->{$command} unless $col;
	$col_head = $column_header_format->{$command} unless $col_head;


    my $options = Text::Abbrev::abbrev(keys %$column);

	# Handle quoted words or phrases.
	my @words = quotewords('\s+', 0, join( " ", @args));

	print "column: $command ", join( " ", @words) , "\n" 
		if $self->{debug};

	while(@words) {
		my ( $text, $on, $off, $justify );
		my $argv = shift @words;
		my $c = exists $options->{$argv} ? $options->{$argv} : undef;
		# determine if the current argument is part of the format
		# string or a value.
		if ($c) {
			if    ( $c =~ m/alias/i ) {
				########################################################
				# Alias
				########################################################
				$col->{$c} = shift @words;
				$self->log( "setting alias ... $col->{$c} ..." ) 
					if $self->{debug};
			} elsif ( $c =~ m/clear/i ) {
				########################################################
				# Clear: syntax column column_name clear
				########################################################
				$self->_clear_format( \$column_format, $command );
				return $self->log( "format cleared" );
			} elsif ( $c =~ m/fold_after/i ) {
				########################################################
				# Fold After
				########################################################
			} elsif ( $c =~ m/fold_before/i ) {
				########################################################
				# Fold Before
				########################################################
			} elsif ( $c =~ m/format/i ) {
				########################################################
				# Format
				########################################################
				# Begin with format of A# strings, 9 numeric.
				my $f = shift @words;
				return $self->column_usage( {format => 'undef'} )
					unless $f;

					$self->_determine_format( $f, \$col );

			} elsif ( $c =~ m/heading/i ) {
				########################################################
				# Heading
				########################################################
				$col->{$c} = shift @words;
				$self->log( "setting heading ... $col->{$c} ..." )
					if $self->{debug};
			} elsif ( $c =~ m/justify/i ) {
				########################################################
				# Justify
				########################################################
				# unset current justification.
				my $f = shift @words;
				# Handle special conditions.
				if ($f =~ m/(?:of(?:f)?)/) {
					$col->{$c} = undef;
					$self->log( "justify cleared ... $f ..." ) if
						$self->{debug};
					next;
				}

				$col->{$c} = undef;

				foreach my $just (@{$column->{$c}}) {
					#$self->log( "\ttesting $f $just" ) if $self->{debug};
					if ($f =~ m/^($just)/i) {
						#$self->log( "\tmatch $f and $just" ) if $self->{debug};
						$col->{$c} = $1;
						last;
					}
				}
				return $self->log( "invalid justification $f" ) unless
					$col->{$c};
				$self->log( "setting justify ... $col->{$c}  $f ..." )
					if $self->{debug};
			} elsif ( $c =~ m/like/i ) {
				########################################################
				# Like
				########################################################
				$col->{$c} = shift @words;
			} elsif ( $c =~ m/newline/i ) {
				########################################################
				# Newline
				########################################################
			} elsif ( $c =~ m/new_value/i ) {
				########################################################
				# New Value
				########################################################
			} elsif ( $c =~ m/noprint/i ) {
				########################################################
				# No Print
				########################################################
				$col->{$c}		= 1;
				$col->{'print'}	= 0;
				$self->log( "setting noprint ... $col->{$c} ..." )
					if $self->{debug};
			} elsif ( $c =~ m/print/i ) {
				########################################################
				# Print
				########################################################
				$col->{$c}			= 1;
				$col->{'noprint'}	= 0;
				$self->log( "setting print ... $col->{$c} ..." )
					if $self->{debug};
			} elsif ( $c =~ m/null/i ) {
				########################################################
				# Null
				########################################################
				$col->{$c} = shift @words;
				$self->log( "setting null text ... $col->{$c} ..." )
					if $self->{debug};
			} elsif ( $c =~ m/on/i ) {
				########################################################
				# On
				########################################################
				$col->{$c}			= 1;
				$col->{off}			= 0;
				$self->log( "setting format on ... $col->{$c} ..." )
					if $self->{debug};
			} elsif ( $c =~ m/off/i ) {
				########################################################
				# Off
				########################################################
				$col->{$c}			= 1;
				$col->{on}			= 0;
				$self->log( "setting format off ... $col->{$c} ..." )
					if $self->{debug};
			} elsif ( $c =~ m/truncated/i ) {
				########################################################
				# Truncated
				########################################################
				$col->{$c} = 1;
				$col->{'wrapped'} = 0;
				$self->log( "setting truncated ... $col->{$c} ..." )
					if $self->{debug};
			} elsif ( $c =~ m/wordwrapped/i ) {
				########################################################
				# Word Wrapped
				########################################################
				$self->log( "setting wordwrapped ... $col->{$c} ..." )
					if $self->{debug};
			} elsif ( $c =~ m/wrapped/i ) {
				########################################################
				# Wrapped
				########################################################
				$col->{$c} = 1;
				$col->{'truncated'} = 0;
				$self->log( "setting wrapped ... $col->{$c} ..." )
					if $self->{debug};
			} else {
				########################################################
				# Unknown
				########################################################
				$self->log( "column unknown option: ... $c ..." )
					if $self->{debug};
			}

		}
	}
	#
	# At this point the format is defined for the current column, now build
	# the format string.
	#
	{
		# Default justify is left.
		my $justify = '<';

		$self->log ("Truncated and Warpped both set for this column: $col->{name}" )
			if (exists $col->{truncated}	and
				exists $col->{wrapped}		and
				$col->{truncated}			and 
				$col->{wrapped}
			);

		$justify = '<' if defined $col->{truncated};
		$justify = '[' if defined $col->{wrapped};

		if (defined $col->{'justify'}) {
			if ($col->{'justify'} eq 'l') {
				$justify = 
					(defined $col->{wrapped} ? '[' : '<');
			} elsif ( $col->{'justify'} eq 'r' ) {
				$justify =
					(defined $col->{wrapped} ? ']' : '>');
			} elsif ( $col->{'justify'} eq 'c' ) {
				$justify = 
					(defined $col->{wrapped} ? '|' : '^');
			} else {
				$self->log( "unknown justify $col->{'justify'}" )
					if $self->{debug};
				$justify = '<';
			}
		}

		# warn "build format for column: " . $command . "\n";

		unless (defined $col->{'length'}) {
			$col->{'length'} = length $command;
		}

		# Allow for head and column format differences.
		$col_head->{'format'} = $justify x $col->{'length'};
		$col->{'format'} = $justify x $col->{'length'};

		# foreach my $col (sort keys %{$column_format->{$command}}) {
		# 	next unless $column_format->{$command}->{$col};
		# 	printf( "\t%-15s %s\n", $col, ($column_format->{$command}->{$col}||'undef') );
		# }

	}

return;
}

sub column_usage {
	my ($self, $error ) = @_;
	return $self->print_buffer( 
		join( " ",
			qq{usage column:  },
			(map { "$_ is $error->{$_}" } keys %$error ),
		)
	);
}

sub _clear_format {
	my ($self, $column_formats, $column) = @_;

	# warn "Removing format for : $column :\n";

	if (exists $$column_formats->{$column}) {
		# Out of here!
		delete $$column_formats->{$column};
		# delete $$column_header_format->{$column};
	} else {
		# Can clear it, not defined.
		$self->alert( "column clear $column: format not defined." );
	}

}


sub _determine_format {
	my ($self, $format_requested, $mycol) = @_;

	my $col = ${$mycol};
	my $numeric = ();

	# Determine what type of format?

	if ( $format_requested =~ m/a(\d+)/i ) {				# Character
		$col->{'length'}	= $1;
		$col->{'type'}		= 'char';
		$col->{'format_function'} = undef;
	} elsif ( $format_requested =~ m/^date$/ ) { # Date
		$col->{'length'}	= 8;
		$col->{'type'}		= 'date';
		$col->{'format_function'} = undef;
	} elsif ( $format_requested =~ m/(\d+)/ ) { # Numeric 9's
		#       999.99 
		# ^^^^^^^^^ ^^^^^
		# PRECISION SCALE

		$col->{'format_function'} = undef;

		$col->{'type'}		= 'numeric';

		my $len = $format_requested		=~ tr /[0-9]/[0-9]/;
		$len++ while($format_requested	=~ m/[BSVG\.\$]|MI/ig);
		$len += $format_requested		=~ tr/,/,/;

		# Length is defined as total length of the formatted results.
		$col->{'length'}	= $len;

		# Determine precision and scale:
		my ($p,$s) = (0,0);
		my ($p1,$s1) = split(/\./, $format_requested);
		$p = $p1  =~ tr /[0-9]/[0-9]/ if $p1;
		$s = $s1  =~ tr /[0-9]/[0-9]/ if $s1;

		# warn "$format_requested/precision($p)/scale($s)/length($len)\n";

		$col->{'precision'}	= $p;
		$col->{'scale'}		= $s;

		# default the commify to NO.
		$col->{'commify'} = 0;

		# $ 		$9999
		if ($format_requested =~ m/\$/) {
			# warn "adding function dollarsign\n";
			$col->{'format_function'} = \&dollarsign;
		}

		# B 		B9999
		$numeric->{B}++			if $format_requested =~ m/B/i;
		# MI 		9999MI
		$numeric->{MI}++		if $format_requested =~ m/MI/i;
		# S 		S9999
		$numeric->{S}++			if $format_requested =~ m/S/i;
		# PR 		9999PR
		$numeric->{PR}++		if $format_requested =~ m/PR/i;
		# D 		99D99
		$numeric->{D}++			if $format_requested =~ m/D/i;
		# G			9G999
		$numeric->{G}++			if $format_requested =~ m/G/i;
		# C 		C999
		$numeric->{C}++			if $format_requested =~ m/C/i;
		# L			L999
		$numeric->{L}++			if $format_requested =~ m/L/i;
		# . (period) 99.99
		$numeric->{period}++	if $format_requested =~ m/\./;
		# V 		999V99
		$numeric->{V}++			if $format_requested =~ m/V/i;
		# EEEE 		9.999EEEE
		$numeric->{EEEE}++		if $format_requested =~ m/EEEE/i;

		# , (comma) 9,999
		if ($format_requested =~ m/\,/) {
				$col->{'commify'} = 1;
		}
	} else {
		return $self->column_usage( {format => "$format_requested invalid" });
	}
	# Save orignal format value.
	$col->{'column_format'} = $format_requested;

	$self->log( "setting format ... $col->{'length'} $col->{'type'} ..." ) 
		if $self->{debug};

return;
}

# Document from Oracle 9i SQL*Plus reference.
#
# FOR[MAT] format
# 
# Specifies the display format of the column. The format specification
# must be a text constant such as A10 or $9,999--not a variable.
# 
# Character Columns The default width of CHAR, NCHAR, VARCHAR2 (VARCHAR)
# and NVARCHAR2 (NCHAR VARYING) columns is the width of the column in
# the database. SQL*Plus formats these datatypes left-justified. If a
# value does not fit within the column width, SQL*Plus wraps or
# truncates the character string depending on the setting of SET WRAP.
# 
# A LONG, CLOB or NCLOB column's width defaults to the value of SET
# LONGCHUNKSIZE or SET LONG, whichever one is smaller.
# 
# To change the width of a datatype to n, use FORMAT An. (A stands for
# alphanumeric.) If you specify a width shorter than the column heading,
# SQL*Plus truncates the heading. If you specify a width for a LONG,
# CLOB, or NCLOB column, SQL*Plus uses the LONGCHUNKSIZE or the
# specified width, whichever is smaller, as the column width.
# 
# DATE Columns The default width and format of unformatted DATE columns
# in SQL*Plus is derived from the NLS parameters in effect. Otherwise,
# the default width is A9. In Oracle9i, the NLS parameters may be set in
# your database parameter file or may be environment variables or an
# equivalent platform-specific mechanism. They may also be specified for
# each session with the ALTER SESSION command. (See the documentation
# for Oracle9i for a complete description of the NLS parameters).
# 
# You can change the format of any DATE column using the SQL function
# TO_CHAR in your SQL SELECT statement. You may also wish to use an
# explicit COLUMN FORMAT command to adjust the column width.
# 
# When you use SQL functions like TO_CHAR, Oracle automatically allows
# for a very wide column.
# 
# To change the width of a DATE column to n, use the COLUMN command with
# FORMAT An. If you specify a width shorter than the column heading, the
# heading is truncated.
# 
# NUMBER Columns To change a NUMBER column's width, use FORMAT followed
# by an element as specified in Table 8-1.
# 
# Table 8-1 Number Formats 
# Element  Examples  Description  
# 9			9999
# 
#   Number of "9"s specifies number of significant digits returned.
#   Blanks are displayed for leading zeroes. A zero (0) is displayed for
#   a value of zero.
#  
# 0			0999 9990
# 
#   Displays a leading zero or a value of zero in this position as 0. 
#  
# $ 		$9999
# 
#   Prefixes value with dollar sign. 
#  
# B 		B9999
# 
#   Displays a zero value as blank, regardless of "0"s in the format model. 
#  
# MI 		9999MI
# 
#   Displays "-" after a negative value. For a positive value, a trailing space is displayed. 
#  
# S 		S9999
# 
#   Returns "+" for positive values and "-" for negative values in this position. 
#  
# PR 		9999PR
# 
#   Displays a negative value in <angle brackets>. For a positive value,
#   a leading and trailing space is displayed.
#  
# D 		99D99
# 
#   Displays the decimal character in this position, separating the
#   integral and fractional parts of a number.
#  
# G			9G999
# 
#   Displays the group separator in this position.
#  
# C 		C999
# 
#   Displays the ISO currency symbol in this position. 
#  
# L			L999
# 
#   Displays the local currency symbol in this position.
#  
# , (comma) 9,999
# 
#   Displays a comma in this position. 
#  
# . (period) 99.99
# 
#   Displays a period (decimal point) in this position, separating the
#   integral and fractional parts of a number.
#  
# V 		999V99
# 
#   Multiplies value by 10n, where n is number of "9"s after "V". 
#  
# EEEE 		9.999EEEE
# 
#   Displays value in scientific notation (format must contain exactly four "E"s). 
#  
# RN or rn 	RN
# 
#   Displays upper- or lowercase Roman numerals. Value can be an integer between 1 and 3999. 
#  
# DATE 		DATE
# 
#   Displays value as a date in MM/DD/YY format; used to format NUMBER
#   columns that represent Julian dates.
#  
#  
# 
# The MI and PR format elements can only appear in the last position of
# a number format model. The S format element can only appear in the
# first or last position.
# 
# If a number format model does not contain the MI, S or PR format
# elements, negative return values automatically contain a leading
# negative sign and positive values automatically contain a
# leading space.
# 
# A number format model can contain only a single decimal character (D)
# or period (.), but it can contain multiple group separators (G) or
# commas (,). A group separator or comma cannot appear to the right of a
# decimal character or period in a number format model.
# 
# SQL*Plus formats NUMBER data right-justified. A NUMBER column's width
# equals the width of the heading or the width of the FORMAT plus one
# space for the sign, whichever is greater. If you do not explicitly use
# FORMAT, then the column's width will always be at least the value of
# SET NUMWIDTH.
# 
# SQL*Plus may round your NUMBER data to fit your format or field width.
# 
# If a value cannot fit within the column width, SQL*Plus indicates
# overflow by displaying a pound sign (#) in place of each digit the
# width allows.
# 
# If a positive value is extremely large and a numeric overflow occurs
# when rounding a number, then the infinity sign (~) replaces the value.
# Likewise, if a negative value is extremely small and a numeric
# overflow occurs when rounding a number, then the negative infinity
# sign replaces the value (-~).

# Commify used from the Perl CookBook
sub commify($) {
        my $num = reverse $_[0];
		$num =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
        return scalar reverse $num;
}

sub dollarsign($$$$) {
        my ($num, $fmtnum, $dlen, $commify) = @_;
        my $formatted = sprintf "\$%${fmtnum}.${dlen}lf", $num;
        return ($commify ? commify($formatted) : $formatted);
}

sub zerofill($$$$) {
        my ($num, $fmtnum, $dlen, $commify) = @_;
        my $formatted = sprintf "%0${fmtnum}.${dlen}lf", $num;
        return ($commify ? commify($formatted) : $formatted);
}

sub signednum($$$$) {
        my ($num, $fmtnum, $dlen, $commify) = @_;
        my $formatted = sprintf "%+${fmtnum}.${dlen}lf", $num;
        return ($commify ? commify($formatted) : $formatted);
}

sub leadsign($$$$) {
        my ($num, $fmtnum, $dlen, $commify) = @_;
        my $formatted = sprintf "%+${fmtnum}.${dlen}lf", $num;
        return ($commify ? commify($formatted) : $formatted);
}

sub trailsign($$$$) {
        my ($num, $fmtnum, $dlen, $commify) = @_;
		$dlen--;
        my $formatted = sprintf "%${fmtnum}.${dlen}lf", abs($num);
		$formatted .= ($num > 0 ? '+' : '-');
        return ($commify ? commify($formatted) : $formatted);
}

sub ltgtsign($$$$) {
        my ($num, $fmtnum, $dlen, $commify) = @_;
		$dlen--;
        my $formatted = sprintf "%s%${fmtnum}.${dlen}lf%s" 
			,($num > 0 ? '' : '<')
			,abs($num),
			,($num > 0 ? '' : '>');
        return ($commify ? commify($formatted) : $formatted);
}

#
# Private methods.
#

sub _me {
        my $pi   = shift;
        my $self = shift;
        return ${$self}->print_buffer("show me what???")
                unless @_;
        return ${$self}->do_show(@_);
}

sub _all {
        my $pi = shift;
        my $self = shift;
        return ${$self}->print_buffer("show all of what???")
                unless @_;
        return ${$self}->do_show(@_);
}

sub _show_all_commands {
        my $pi = shift;
        my $self = shift;
return
        ${$self}->print_buffer("Show supports the following commands:\n\t" .
                join( "\n\t", keys %{$pi->{show}}));
}

sub _unimp {
        my $pi = shift;
        my $self = shift;
        return ${$self}->print_buffer("unimplemented");
}

sub _obsolete {
        my $pi = shift;
        my $self = shift;
        return ${$self}->print_buffer("obsolete: use " . join( " ", @_) );
}

sub _print_buffer {
        my $pi = shift;
        my $self = shift;
        return ${$self}->print_buffer(@_);
}

sub _set_get {
        my $pi = shift;
        my $self = shift;
        my $command = shift;

        carp "command undefined: " and return unless defined $command;

# Use the off to undefine/null a value.
        if (@_) {
				my $val = shift;
				if ($val =~ m/off/i) {
                	$pi->{set_current}->{$command} = undef;
				} else {
                	$pi->{set_current}->{$command} = $val
				}

        }
        ${$self}->print_buffer(
                        qq{$command: } .  ($pi->{set_current}->{$command}||
						'null')
        );
return $pi->{set_current}->{$command};
}

#------------------------------------------------------------------
#
# Display a list of all schemas.
#
#------------------------------------------------------------------
sub _schemas {
        my ($pi, $sh, @args) = @_;
	#
	# Allow types to accept a list of types to display.
	#
	my $sth;

	my $dbh = ${$sh}->{dbh};
	$sth = $dbh->table_info('', '%', '', '');

	unless(ref $sth) {
		${$sh}->log( "Advance table_info not supported\n");
		return;
	}
	return ${$sh}->sth_go($sth, 0, 0);
}

#------------------------------------------------------------------
#
# Display the last sql code, error, and error string.
#
#------------------------------------------------------------------
sub _sqlcode {
        my ($pi, $sh, @args) = @_;

	my $dbh = ${$sh}->{dbh};

	my $codes;
	
	$codes .= "last dbi error        : " . $dbh->err . "\n"		if $dbh->err;
	$codes .= "last dbi error string : " . $dbh->errstr . "\n"	if $dbh->err;
	$codes .= "last dbi error state  : " . $dbh->state	. "\n"	if $dbh->err;

	${$sh}->print_buffer_nop( $codes ) if defined $codes;

	return $dbh->err||0;
}

#------------------------------------------------------------------
#
# Display a list of all tables.
#
#------------------------------------------------------------------
sub _tables {
        my ($pi, $sh, @args) = @_;
	return $pi->_sup_types( $sh, 'TABLE', @args );
}

#------------------------------------------------------------------
#
# Display a list of all types.
#
#------------------------------------------------------------------
sub _types {
        my ($pi, $sh, @args) = @_;
	#
	# Allow types to accept a list of types to display.
	#
	my $sth;
	if (@args) {
		return $pi->_sup_types( $sh, @args );
	} 

	my $dbh = ${$sh}->{dbh};
	$sth = $dbh->table_info('', '', '', '%');

	unless(ref $sth) {
		${$sh}->log( "Advance table_info not supported\n" );
		return;
	}
	return ${$sh}->sth_go($sth, 0, 0);
}

#------------------------------------------------------------------
#
# Display a list of all views.
#
#------------------------------------------------------------------
sub _views {
        my ($pi, $sh, @args) = @_;

	return $pi->_sup_types( $sh, 'VIEW', @args );
}

#------------------------------------------------------------------
#
# Handle different types.
#
#------------------------------------------------------------------
sub _sup_types {
        my ($pi, $sh, $type, @args) = @_;

	$sh = ${$sh}; # Need to dereference the shell object.

	my $dbh = $sh->{dbh};

	return unless (defined $type);

	my $sth;
	if (@args) {
		my $tbl = join( ",", @args );
		$sth = $dbh->table_info(undef, undef, $tbl, $type);
	} else {
		$sth = $dbh->table_info(undef, undef, undef, $type);
	}

	unless (ref $sth) {
		${$sh}->log( "Advance table_info not supported\n" );
		return;
	}

	return $sh->sth_go($sth, 0, 0);
}

1;


