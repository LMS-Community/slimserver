package DBI::Shell;
# vim:ts=4:sw=4:ai:aw:nowrapscan

=head1 NAME

DBI::Shell - Interactive command shell for the DBI

=head1 SYNOPSIS

  perl -MDBI::Shell -e shell [<DBI data source> [<user> [<password>]]]

or

  dbish [<DBI data source> [<user> [<password>]]]
  dbish --debug [<DBI data source> [<user> [<password>]]]
  dbish --batch [<DBI data source> [<user> [<password>]]] < batch file

=head1 DESCRIPTION

The DBI::Shell module (and dbish command, if installed) provide a
simple but effective command line interface for the Perl DBI module.

DBI::Shell is very new, very experimental and very subject to change.
Your mileage I<will> vary. Interfaces I<will> change with each release.

=cut

###
###	See TO DO section in the docs at the end.
###


BEGIN { require 5.004 }
BEGIN { $^W = 1 }

use strict;
use vars qw(@ISA @EXPORT $VERSION $SHELL);
use Exporter ();
use Carp;

@ISA = qw(Exporter DBI::Shell::Std);
@EXPORT = qw(shell);

$VERSION = sprintf( "%d.%02d", q$Revision: 11.93 $ =~ /(\d+)\.(\d+)/ );

my $warning = <<'EOM';

WARNING: The DBI::Shell interface and functionality are
=======  very likely to change in subsequent versions!

EOM

sub new {
	my $class = shift;
    my @args = @_ ? @_ : @ARGV;
    #my $sh = bless {}, $class;
	my $sh = $class->SUPER::new(@args);
	# Load configuration files, system and user.  The user configuration may
	# over ride the system configuration.
	my $myconfig = $sh->configuration;
	# Save the configuration file for this instance.
	$sh->{myconfig} = $myconfig;
	# Pre-init plugins.
	$sh->load_plugins($myconfig->{'plug-ins'}->{'pre-init'});
	# Post-init plugins.
	#$sh->SUPER::init(@args);
    $sh->load_plugins($myconfig->{'plug-ins'}->{'post-init'});
return $sh;
}

sub shell {
    my @args = @_ ? @_ : @ARGV;
    $SHELL = DBI::Shell::Std->new(@args);
    $SHELL->load_plugins;
    $SHELL->run;
}

sub run {
	my $sh = shift;
    die "Unrecognised options: @{$sh->{unhandled_options}}\n"
	if @{$sh->{unhandled_options}};

    $sh->log($warning) unless $sh->{batch};

    # Use valid "dbi:driver:..." to connect with source.
    $sh->do_connect( $sh->{data_source} );

    #
    # Main loop
    #
    $sh->{abbrev} = undef;
    $sh->{abbrev} = Text::Abbrev::abbrev(keys %{$sh->{commands}});
		# unless $sh->{batch};
    $sh->{current_buffer} = '';
	$sh->SUPER::run;

}


# -------------------------------------------------------------
package DBI::Shell::Std;

use vars qw(@ISA);
@ISA = qw(DBI::Shell::Base);

# XXX this package might be used to override commands etc.
sub do_connect {
	my $sh = shift;
    $sh->load_plugins($sh->{myconfig}->{'plug-ins'}->{'pre-connect'})
		if exists $sh->{myconfig}->{'plug-ins'}->{'pre-connect'};
	$sh->SUPER::do_connect(@_);
    $sh->load_plugins($sh->{myconfig}->{'plug-ins'}->{'post-connect'})
		if exists $sh->{myconfig}->{'plug-ins'}->{'post-connect'};
return;
}

sub init {
	my $sh = shift;
	return;
}


# -------------------------------------------------------------
package DBI::Shell::Base;

use Carp;
use Text::Abbrev ();
use Term::ReadLine;
use Getopt::Long 2.17;	# upgrade from CPAN if needed: http://www.perl.com/CPAN
use IO::File;

use DBI 1.00 qw(:sql_types :utils);
use DBI::Format;

use DBI::Shell::FindSqlFile;

use vars qw(@ISA);
@ISA = qw(DBI::Shell::FindSqlFile);

use constant ADD_RH => 1;	# Add the results, to rhistory.
use constant  NO_RH => 0;	# Do not add results, to rhistory.

my $haveTermReadKey;
my $term;


sub usage {
    warn <<USAGE;
Usage: perl -MDBI::Shell -e shell [<DBI data source> [<user> [<password>]]]
USAGE
}

sub log {
    my $sh = shift;
    return ($sh->{batch}) ? warn @_,"\n" : $sh->print_buffer_nop(@_,"\n");	# XXX maybe
}

sub alert {	# XXX not quite sure how alert and err relate
    # for msgs that would pop-up an alert dialog if this was a Tk app
    my $sh = shift;
    return warn @_,"\n";
}

sub err {	# XXX not quite sure how alert and err relate
    my ($sh, $msg, $die) = @_;
    $msg = "DBI::Shell: $msg\n";
    die $msg if $die;
    return $sh->alert($msg);
}



sub add_option {
    my ($sh, $opt, $default) = @_;
    (my $opt_name = $opt) =~ s/[|=].*//;
    croak "Can't add_option '$opt_name', already defined"
		if exists $sh->{$opt_name};
    $sh->{options}->{$opt_name} = $opt;
    $sh->{$opt_name} = $default;
}

sub load_plugins {
	my ($sh, @ppi) = @_;
	# Output must  not  appear  while  loading  plugins:
	# It  might  happen,  that  batch  mode  is  entered
	# later!
	my @pi;
	return unless(@ppi);
	foreach my $n (0 .. $#ppi) {
		next unless ($ppi[$n]);
		my $pi = $ppi[$n];

		if ( ref $pi eq  'HASH' ) {
			# As we descend down the hash reference,
			# we're looking for an array of modules to source in.
			my @mpi = keys %$pi;
			foreach my $opt (@mpi) {
				#print "Working with $opt\n";
				if ($opt =~ /^option/i) {
					# Call the option handling.
					$sh->install_options( @{$pi->{$opt}} );
					next;
				} elsif ( $opt =~ /^database/i ) {
					# Handle plugs for a named # type of database.
					next unless $sh->{dbh};
					# Determine what type of database connection.
					my $db = $sh->{dbh}->{Driver}->{Name};
					$sh->load_plugins( $pi->{$opt}->{$db} )
						if (exists $pi->{$opt}->{$db});
					next;
				} elsif ( $opt =~ /^non-database/i ) {
					$sh->load_plugins( $pi->{$opt} );
				} else  {
					$sh->load_plugins( $pi->{$opt} );
				}
			}
		} elsif ( ref $pi eq 'ARRAY' ) {
			@pi = @$pi;
		} else {
			next unless $pi;
			push(@pi, $pi);
		}
		foreach my $pi (@pi) {
			my $mod = $pi;
			$mod =~ s/\.pm$//;
			#print "Module: $mod\n";
			unshift @DBI::Shell::Std::ISA, $mod;
			eval qq{ use $pi };
			if ($@) {
				warn "Failed: $@";
				shift @DBI::Shell::Std::ISA;
				shift @pi;
			} else {
				$sh->print_buffer_nop("Loaded plugins $mod\n")
					unless $sh->{batch};
			}
		}
	}
	local ($|) = 1;
    # plug-ins should remove options they recognise from (localized) @ARGV
    # by calling Getopt::Long::GetOptions (which is already in pass_through mode).
    foreach my $pi (@pi) {
	local *ARGV = $sh->{unhandled_options};
		$pi->init($sh);
    }
	return @pi;
}

sub default_config {
	my $sh = shift;
    #
    # Set default configuration options
    #
    foreach my $opt_ref (
	 [ 'command_prefix_line=s'	=> '/' ],
	 [ 'command_prefix_end=s'	=> ';' ],
	 [ 'command_prefix=s'	=> '[/;]' ],
	 [ 'chistory_size=i'	=> 50 ],
	 [ 'rhistory_size=i'	=> 50 ],
	 [ 'rhistory_head=i'	=>  5 ],
	 [ 'rhistory_tail=i'	=>  5 ],
	 [ 'user_level=i'		=>  1 ],
	 [ 'editor|ed=s'		=> ($ENV{VISUAL} || $ENV{EDITOR} || 'vi') ],
	 [ 'batch'				=> 0 ],
	 [ 'format=s'				=> 'neat' ],
	 [ 'prompt=s'			=> undef ],
	# defaults for each new database connect:
	 [ 'init_trace|trace=i' => 0 ],
	 [ 'init_autocommit|autocommit=i' => 1 ],
	 [ 'debug|d=i'			=> ($ENV{DBISH_DEBUG} || 0) ],
	 [ 'seperator|sep=s'	=> ',' ],
	 [ 'sqlpath|sql=s'		=> '.' ],
	 [ 'tmp_dir|tmp_d=s'	=> $ENV{DBISH_TMP} ],
	 [ 'tmp_file|tmp_f=s'	=> qq{dbish$$.sql} ],
	 [ 'home_dir|home_d=s'	=> $ENV{HOME} || "$ENV{HOMEDRIVE}$ENV{HOMEPATH}" ],
	 [ 'desc_show_remarks|show_remarks' => 1 ],
	 [ 'desc_show_long|show_long' => 1 ],
	 [ 'desc_format=s'		=> q{partbox} ],
	 [ 'desc_show_columns=s' => q{COLUMN_NAME,DATA_TYPE,TYPE_NAME,COLUMN_SIZE,PK,NULLABLE,COLUMN_DEF,IS_NULLABLE,REMARKS} ],
	 @_,
    ) {
	$sh->add_option(@$opt_ref);
    }

}
    

sub default_commands {
	my $sh = shift;
    #
    # Install default commands
    #
    # The sub is passed a reference to the shell and the @ARGV-style
    # args it was invoked with.
    #
    $sh->{commands} = {
    'help' => {
	    hint => "display this list of commands",
    },
    'quit' => {
	    hint => "exit",
    },
    'exit' => {
	    hint => "exit",
    },
    'trace' => {
	    hint => "set DBI trace level for current database",
    },
    'connect' => {
	    hint => "connect to another data source/DSN",
    },
    'prompt' => {
          hint => "change the displayed prompt",
    },
    # --- execute commands
    'go' => {
	    hint => "execute the current statement",
    },
    'count' => {
	    hint => "execute 'select count(*) from table' (on each table listed).",
    },
    'do' => {
	    hint => "execute the current (non-select) statement",
    },
    'perl' => {
	    hint => "evaluate the current statement as perl code",
    },
    'ping' => {
	    hint => "ping the current connection",
    },
    'commit' => {
	    hint => "commit changes to the database",
    },
    'rollback' => {
	    hint => "rollback changes to the database",
    },
    # --- information commands
    'primary_key_info' => {
	    hint => "display primary keys that exist in current database",
    },
    'col_info' => {
	    hint => "display columns that exist in current database",
    },
    'table_info' => {
	    hint => "display tables that exist in current database",
    },
    'type_info' => {
	    hint => "display data types supported by current server",
    },
    'drivers' => {
	    hint => "display available DBI drivers",
    },

    # --- statement/history management commands
    'clear' => {
	    hint => "erase the current statement",
    },
    'redo' => {
	    hint => "re-execute the previously executed statement",
    },
    'get' => {
	    hint => "make a previous statement current again",
    },
    'current' => {
	    hint => "display current statement",
    },
    'edit' => {
	    hint => "edit current statement in an external editor",
    },
    'chistory' => {
	    hint => "display command history",
    },
    'rhistory' => {
	    hint => "display result history",
    },
    'format' => {
	    hint => "set display format for selected data (Neat|Box)",
    },
    'history' => {
	    hint => "display combined command and result history",
    },
    'option' => {
	    hint => "display or set an option value",
    },
    'describe' => {
	    hint => "display information about a table (columns, data types).",
    },
    'load' => {
	    hint => "load a file from disk to the current buffer.",
    },
    'run' => {
	    hint => "load a file from disk to current buffer, then executes.",
    },
    'save' => {
	    hint => "save the current buffer to a disk file.",
    },
    'spool' => {
	    hint => "send all output to a disk file. usage: spool file name or spool off.",
    },

    };

}

sub default_term {
	my ($sh, $class) = @_;
    #
    # Setup Term
    #
    my $mode;
    if ($sh->{batch} || ! -t STDIN) {
		$sh->{batch} = 1;
		$mode = "in batch mode";
    } else {
		$sh->{term} = new Term::ReadLine($class);
		$mode = "";
    }

	return( $mode );
}

sub new {
    my ($class, @args) = @_;

    my $sh = bless {}, $class;
    
	$sh->default_config;
	$sh->default_commands;

    #
    # Handle command line parameters
    #
    # data_source and user command line parameters overrides both 
    # environment and config settings.
    #

	$DB::single = 1;

    local (@ARGV) = @args;
    my @options = values %{ $sh->{options} };
    Getopt::Long::config('pass_through');	# for plug-ins
    unless (GetOptions($sh, 'help|h', @options)) {
		$class->usage;
		croak "DBI::Shell aborted.\n";
    }
    if ($sh->{help}) {
		$class->usage;
		return;
    }

    $sh->{unhandled_options} = [];
    @args = ();
    foreach my $arg (@ARGV) {
		if ($arg =~ /^-/) {	# expected to be in "--opt=value" format
			push @{$sh->{unhandled_options}}, $arg;
		}
		else {
			push @args, $arg;
		}
    }

    $sh->do_format($sh->{format});

    $sh->{data_source}	= shift(@args) || $ENV{DBI_DSN}  || '';
    $sh->{user}		    = shift(@args) || $ENV{DBI_USER} || '';
    $sh->{password}	    = shift(@args) || $ENV{DBI_PASS} || undef;

    $sh->{chistory} = [];	# command history
    $sh->{rhistory} = [];	# result  history
	$sh->{prompt}   = $sh->{data_source};

# set the default io handle.
	$sh->{out_fh}		= \*STDOUT;

# support for spool command ...
	$sh->{spooling} = 0; $sh->{spool_file} = undef; $sh->{spool_fh} = undef;

	my $mode = $sh->default_term($class);

    $sh->log("DBI::Shell $DBI::Shell::VERSION using DBI $DBI::VERSION $mode");
    $sh->log("DBI::Shell loaded from $INC{'DBI/Shell.pm'}") if $sh->{debug};

    return $sh;
}

# Used to install, configure, or change an option or command.
sub install_options {
	my ($sh, $options) = @_;

	my @po;
	$sh->log( "reference type: " . ref $options )
		if $sh->{debug};

	if ( ref $options eq 'ARRAY' ) {

		foreach my $opt_ref ( @$options )
		#[ 'debug|d=i'		=> ($ENV{DBISH_DEBUG} || 0) ],
		#[ 'seperator|sep=s'		=> ',' ],) 
		{
			if ( ref $opt_ref eq 'ARRAY' ) {
				$sh->install_options( $opt_ref );
			} else {
				push( @po, $opt_ref );
			}
		}
	} elsif ( ref $options eq 'HASH' ) {
		foreach (keys %{$options}) {
			push(@po, $_, $options->{$_});
		}
	} elsif ( ref $options eq 'SCALAR' ) {
		push( @po, $$options );
	} else {
		return unless $options;
		push( @po, $options );
	}

	return unless @po;

	eval{ $sh->add_option(@po) };
	# Option exists, just change it.
	if ($@ =~ /add_option/) {
		$sh->do_option( join( '=',@po ) );
	} else {
		croak "configuration: $@\n" if $@;
	}
}

sub configuration {
	my $sh = shift;

    # Source config file which may override the defaults.
    # Default is $ENV{HOME}/.dbish_config.
    # Can be overridden with $ENV{DBISH_CONFIG}.
    # Make $ENV{DBISH_CONFIG} empty to prevent sourcing config file.
    # XXX all this will change
    my $homedir = $ENV{HOME}				# unix
		|| "$ENV{HOMEDRIVE}$ENV{HOMEPATH}";	# NT
    $sh->{config_file} = $ENV{DBISH_CONFIG} || "$homedir/.dbish_config";
	my $config;
    if ($sh->{config_file} && -f $sh->{config_file}) {
		$config = require $sh->{config_file};
		# allow for custom configuration options.
		if (exists $config->{'options'} ) {
			$sh->install_options( $config->{'options'} );
		}
    }
	return $config;
}


sub run {
    my $sh = shift;

    my $current_line = '';

    while (1) {
	my $prefix = $sh->{command_prefix};

	$current_line = $sh->readline($sh->prompt());
	$current_line = "/quit" unless defined $current_line;

	my $copy_cline = $current_line; my $eat_line = 0;
	# move past command prefix contained within quotes
	while( $copy_cline =~ s/(['"][^'"]*(?:$prefix).*?['"])//og ) {
		$eat_line = $+[0];
	}

	# What's left to check?
	my $line;
	if ($eat_line > 0) {
	    $sh->{current_buffer} .= substr( $current_line, 0, $eat_line ) . "\n";
		$current_line = substr( $current_line, $eat_line )
			if (length($current_line) >= $eat_line );
	} else {
		$current_line = $copy_cline;
	}


	if ( 
		$current_line =~ m/
			^(.*?)
			(?<!\\)
			$prefix
			(?:(\w*)
			([^\|><]*))?
			((?:\||>>?|<<?).+)?
			$
	/x) {
	    my ($stmt, $cmd, $args_string, $output) = ($1, $2, $3, $4||''); 

		# print "$stmt -- $cmd -- $args_string -- $output\n";
	    # $sh->{current_buffer} .= "$stmt\n" if length $stmt;
		if (length $stmt) {
			$stmt =~ s/\\$prefix/$prefix/g;
			$sh->{current_buffer} .= "$stmt\n";
			if ($sh->is_spooling) { print ${$sh->{spool_fh}} ($stmt, "\n\n") }
		}

	    $cmd = 'go' if $cmd eq '';
	    my @args = split ' ', $args_string||'';

	    warn("command='$cmd' args='$args_string' output='$output'") 
		    if $sh->{debug};

	    my $command;
	    if ($sh->{abbrev}) {
			$command = $sh->{abbrev}->{$cmd};
	    }
	    else {
			$command = ($sh->{command}->{$cmd}) ? $cmd : undef;
	    }
	    if ($command) {
			$sh->run_command($command, $output, @args);
	    }
	    else {
		if ($sh->{batch}) {
		    die "Command '$cmd' not recognised";
		}
		$sh->alert("Command '$cmd' not recognised ",
		    "(enter ${prefix}help for help).");
	    }

	}
	elsif ($current_line ne "") {
		if ($sh->is_spooling) { print ${$sh->{spool_fh}} ($current_line, "\n") }
	    $sh->{current_buffer} .= $current_line . "\n";
	    # print whole buffer here so user can see it as
	    # it grows (and new users might guess that unrecognised
	    # inputs are treated as commands)
		unless ($sh->{user_level}) {
	    	$sh->run_command('current', undef,
				"(enter '$prefix' to execute or '${prefix}help' for help)");
		}
	}
    }
}
	

#
# Internal methods
#

sub readline {
    my ($sh, $prompt) = @_;
    my $rv;
    if ($sh->{term}) {
		$rv = $sh->{term}->readline($prompt);
    }
    else {
		chomp($rv = <STDIN>);
    }

    return $rv;
}


sub run_command {
    my ($sh, $command, $output, @args) = @_;
    return unless $command;
    local(*STDOUT) if $output;
    local(*OUTPUT) if $output;
    if ($output) {
		if (open(OUTPUT, $output)) {
			*STDOUT = *OUTPUT;
		} else {
			$sh->err("Couldn't open output '$output': $!");
			$sh->run_command('current', undef, '');
		}
    }
    eval {
		my $code = "do_$command";
		$sh->$code(@args);
    };
    close OUTPUT if $output;
    $sh->err("$command failed: $@") if $@;	
return;
}


sub print_list {
    my ($sh, $list_ref) = @_;
    for(my $i = 0; $i < @$list_ref; $i++) {
		print ${$sh->{out_fh}} ($i+1,":  $$list_ref[$i]\n");
    }
return;
}


#-------------------------------------------------------------------
#
# Print Buffer adding a prompt.
#
#-------------------------------------------------------------------
sub print_buffer {
    my $sh = shift;
	{
		local ($,) = q{ };
		my @out = @_;
		chomp $out[-1];			# Remove any added newline.
		return print ($sh->prompt(), @out,"\n");
	}
}

#-------------------------------------------------------------------
#
# Print Buffer without adding a prompt.
#
#-------------------------------------------------------------------
sub print_buffer_nop {
    my $sh = shift;
	{
		local ($,) = q{ };
		my @out = @_;
		chomp $out[-1];			# Remove any added newline.
		return print  (@out,"\n");
	}
}

sub get_data_source {
    my ($sh, $dsn, @args) = @_;
    my $driver;

    if ($dsn) {
		if ($dsn =~ m/^dbi:.*:/i) {	# has second colon
			return $dsn;		# assumed to be full DSN
		}
		elsif ($dsn =~ m/^dbi:([^:]*)/i) {
			$driver = $1		# use DriverName part
		}
		else {
			$sh->print_buffer_nop ("Ignored unrecognised DBI DSN '$dsn'.\n");
		}
    }

    if ($sh->{batch}) {
		die "Missing or unrecognised DBI DSN.";
    }

    $sh->print_buffer_nop("\n");

    while (!$driver) {
		$sh->print_buffer_nop("Available DBI drivers:\n");
		my @drivers = DBI->available_drivers;
		for( my $cnt = 0; $cnt <= $#drivers; $cnt++ ) {
			$sh->print_buffer_nop(sprintf ("%2d: dbi:%s\n", $cnt+1, $drivers[$cnt]));
		} 
		$driver = $sh->readline(
			"Enter driver name or number, or full 'dbi:...:...' DSN: ");
		exit unless defined $driver;	# detect ^D / EOF
		$sh->print_buffer_nop("\n");

		return $driver if $driver =~ /^dbi:.*:/i; # second colon entered

		if ( $driver =~ /^\s*(\d+)/ ) {
			$driver = $drivers[$1-1];
		} else {
			$driver = $1;
			$driver =~ s/^dbi://i if $driver # incase they entered 'dbi:Name'
		}
		# XXX try to install $driver (if true)
		# unset $driver if install fails.
    }

    my $source;
    while (!defined $source) {
	my $prompt;
	my @data_sources = DBI->data_sources($driver);
	if (@data_sources) {
	    $sh->print_buffer_nop("Enter data source to connect to: \n");
	    for( my $cnt = 0; $cnt <= $#data_sources; $cnt++ ) {
		$sh->print_buffer_nop(sprintf ("%2d: %s\n", $cnt+1, $data_sources[$cnt]));
	    } 
	    $prompt = "Enter data source or number,";
	}
	else {
	    $sh->print_buffer_nop ("(The data_sources method returned nothing.)\n");
	    $prompt = "Enter data source";
	}
	$source = $sh->readline(
		"$prompt or full 'dbi:...:...' DSN: ");
	return if !defined $source;	# detect ^D / EOF
	if ($source =~ /^\s*(\d+)/) {
	    $source = $data_sources[$1-1]
	}
	elsif ($source =~ /^dbi:([^:]+)$/) { # no second colon
	    $driver = $1;		     # possibly new driver
	    $source = undef;
	}
		$sh->print_buffer_nop("\n");
    }

    return $source;
}


sub prompt_for_password {
    my ($sh) = @_;

	# no prompts in batch mode.

	return if ($sh->{batch});

    if (!defined($haveTermReadKey)) {
		$haveTermReadKey = eval { require Term::ReadKey } ? 1 : 0;
    }
    local $| = 1;
    $sh->print_buffer_nop ("Password for $sh->{user} (",
	($haveTermReadKey ? "not " : "Warning: "),
	"echoed to screen): ");
    if ($haveTermReadKey) {
        Term::ReadKey::ReadMode('noecho');
		$sh->{password} = Term::ReadKey::ReadLine(0);
		Term::ReadKey::ReadMode('restore');
    } else {
		$sh->{password} = <STDIN>;
    }
    chomp $sh->{password};
    $sh->print_buffer_nop ("\n");
}

sub prompt {
    my ($sh) = @_;
    return "" if $sh->{batch};
    return "(not connected)> " unless $sh->{dbh};

	if ( ref $sh->{prompt} ) {
		foreach (@{$sh->{prompt}} ) {
			if ( ref $_ eq "CODE" ) {
				$sh->{prompt} .= &$_;
			} else {
				$sh->{prompt} .= $_;
			}
		}
    	return "$sh->{user}\@$sh->{prompt}> ";
	} else {
    	return "$sh->{user}\@$sh->{prompt}> ";
	}
return;
}


sub push_chistory {
    my ($sh, $cmd) = @_;
    $cmd = $sh->{current_buffer} unless defined $cmd;
    $sh->{prev_buffer} = $cmd;
    my $chist = $sh->{chistory};
    shift @$chist if @$chist >= $sh->{chistory_size};
    push @$chist, $cmd;
return;
}


#
# Command methods
#

sub do_help {
    my ($sh, @args) = @_;

    return "" if $sh->{batch};

    my $prefix = $sh->{command_prefix};
    my $commands = $sh->{commands};
    $sh->print_buffer_nop ("Defined commands, in alphabetical order:\n");
    foreach my $cmd (sort keys %$commands) {
	my $hint = $commands->{$cmd}->{hint} || '';
	$sh->print_buffer_nop(sprintf ("  %s%-10s %s\n", $prefix, $cmd, $hint));
    }
    $sh->print_buffer_nop ("Commands can be abbreviated.\n") if $sh->{abbrev};
return;
}


sub do_format {
    my ($sh, @args) = @_;
    my $mode = $args[0] || '';
    my $class = eval { DBI::Format->formatter($mode,1) };
    unless ($class) {
		return $sh->alert("Unable to select '$mode': $@");
    }
    $sh->log("Using formatter class '$class'") if $sh->{debug};
	$sh->{format} = $mode;
    return $sh->{display} = $class->new($sh);
}


sub do_go {
    my ($sh, @args) = @_;

	# print "do_go\n";

	# Modify go to get the last executed statement if called on an
	# empty buffer.

	if ($sh->{current_buffer} eq '') {
		$sh->do_get;
		return if $sh->{current_buffer} eq '';
	}

    $sh->{prev_buffer} = $sh->{current_buffer};

    $sh->push_chistory;
    
    eval {
		# Determine if the single quotes are out of balance.
		my $count = ($sh->{current_buffer} =~ tr/'/'/);
		warn "Quotes out of balance: $count" unless (($count % 2) == 0);

		my $sth = $sh->{dbh}->prepare($sh->{current_buffer});

		$sh->sth_go($sth, 1);
    };
    if ($@) {
		my $err = $@;
		$err =~ s: at \S*DBI/Shell.pm line \d+(,.*?chunk \d+)?::
			if !$sh->{debug} && $err =~ /^DBD::\w+::\w+ \w+/;
		print STDERR "$err";
    }
    # There need to be a better way, maybe clearing the
    # buffer when the next non command is typed.
    # Or sprinkle <$sh->{current_buffer} ||= $sh->{prev_buffer};>
    # around in the code.
return $sh->{current_buffer} = '';
}


sub sth_go {
    my ($sh, $sth, $execute, $rh) = @_;

	$rh = 1 unless defined $rh;  # Add to results history.  Default 1, Yes.
    my $rv;
    if ($execute || !$sth->{Active}) {
	my @params;
	my $params = $sth->{NUM_OF_PARAMS} || 0;
	$sh->print_buffer_nop("Statement has $params parameters:\n") if $params;
	foreach(1..$params) {
	    my $val = $sh->readline("Parameter $_ value: ");
	    push @params, $val;
	}
	$rv = $sth->execute(@params);
    }
	
    if (!$sth->{'NUM_OF_FIELDS'}) { # not a select statement
		local $^W=0;
		$rv = "undefined number of" unless defined $rv;
		$rv = "unknown number of"   if $rv == -1;
		$sh->print_buffer_nop ("[$rv row" . ($rv==1 ? "" : "s") . " affected]\n");
		return;
    }

    $sh->{sth} = $sth;

    #
    # Remove oldest result from history if reached limit
    #
    my $rhist = $sh->{rhistory};
	if ($rh) {
    	shift @$rhist if @$rhist >= $sh->{rhistory_size};
    	push @$rhist, [];
	}

    #
    # Keep a buffer of $sh->{rhistory_tail} many rows,
    # when done with result add those to rhistory buffer.
    # Could use $sth->rows(), but not all DBD's support it.
    #
    my @rtail;
    my $i = 0;
    my $display = $sh->{display} || die "panic: no display set";
    $display->header($sth, $sh->{out_fh}||\*STDOUT, $sh->{seperator});

	OUT_ROWS:
    while (my $rowref = $sth->fetchrow_arrayref()) {
		$i++;

		my $rslt = $display->row($rowref);

		if($rh) {
			if ($i <= $sh->{rhistory_head}) {
				push @{$rhist->[-1]}, [@$rowref];
			}
			else {
				shift @rtail if @rtail == $sh->{rhistory_tail};
				push @rtail, [@$rowref];
			}
		}

		unless(defined $rslt) {
			$sh->print_buffer_nop( "row limit reached" );
			last OUT_ROWS;
		}
    }

    $display->trailer($i);

	if($rh) {
		if (@rtail) {
			my $rows = $i;
			my $ommitted = $i - $sh->{rhistory_head} - @rtail;
# Only include the omitted message if results are omitted.
			if ($ommitted) {
				push(@{$rhist->[-1]},
					 [ "[...$ommitted rows out of $rows ommitted...]"]);
			}
			foreach my $rowref (@rtail) {
				push @{$rhist->[-1]}, $rowref;
			}
		}
	}

return;
}

#------------------------------------------------------------------
#
# Generate a select count(*) from table for each table in list.
#
#------------------------------------------------------------------

sub do_count {
    my ($sh, @args) = @_;
	foreach my $tab (@args) {
		$sh->print_buffer_nop ("Counting: $tab\n");
		$sh->{current_buffer} = "select count(*) as cnt_$tab from $tab";
		$sh->do_go();
	}
    return $sh->{current_buffer} = '';
}

sub do_do {
    my ($sh, @args) = @_;
    $sh->push_chistory;
    my $rv = $sh->{dbh}->do($sh->{current_buffer});
    $sh->print_buffer_nop ("[$rv row" . ($rv==1 ? "" : "s") . " affected]\n")
		if defined $rv;

    # XXX I question setting the buffer to '' here.
    # I may want to edit my line without having to scroll back.
    return $sh->{current_buffer} = '';
}


sub do_disconnect {
    my ($sh, @args) = @_;
    return unless $sh->{dbh};
    $sh->log("Disconnecting from $sh->{data_source}.");
    eval {
	$sh->{sth}->finish if $sh->{sth};
	$sh->{dbh}->rollback unless $sh->{dbh}->{AutoCommit};
	$sh->{dbh}->disconnect;
    };
    $sh->alert("Error during disconnect: $@") if $@;
    $sh->{sth} = undef;
    $sh->{dbh} = undef;
return;
}


sub do_connect {
    my ($sh, $dsn, $user, $pass) = @_;

    $dsn = $sh->get_data_source($dsn);
    return unless $dsn;

    $sh->do_disconnect if $sh->{dbh};

	# Change from Jeff Zucker, convert literal slash and letter n to newline.
	$dsn =~ s/\\n/\n/g;
	$dsn =~ s/\\t/\t/g;


    $sh->{data_source} = $dsn;
    if (defined $user and length $user) {
	$sh->{user}     = $user;
	$sh->{password} = undef;	# force prompt below
    }

    $sh->log("Connecting to '$sh->{data_source}' as '$sh->{user}'...");
    if ($sh->{user} and !defined $sh->{password}) {
	$sh->prompt_for_password();
    }
    $sh->{dbh} = DBI->connect(
	$sh->{data_source}, $sh->{user}, $sh->{password}, {
	    AutoCommit => $sh->{init_autocommit},
	    PrintError => 0,
	    RaiseError => 1,
	    LongTruncOk => 1,	# XXX
    });
    $sh->{dbh}->trace($sh->{init_trace}) if $sh->{init_trace};
return;
}


sub do_current {
    my ($sh, $msg, @args) = @_;
    $msg = $msg ? " $msg" : "";
    return 
		$sh->log("Current statement buffer$msg:\n" . $sh->{current_buffer});
}

sub do_autoflush {

return;
}

sub do_trace {
    return shift->{dbh}->trace(@_);
}

sub do_commit {
    return shift->{dbh}->commit(@_);
}

sub do_rollback {
    return shift->{dbh}->rollback(@_);
}


sub do_quit {
    my ($sh, @args) = @_;
    $sh->do_disconnect if $sh->{dbh};
    undef $sh->{term};
    exit 0;
}

# Until the alias command is working each command requires definition.
sub do_exit { shift->do_quit(@_); }

sub do_clear {
    my ($sh, @args) = @_;
return $sh->{current_buffer} = '';
}


sub do_redo {
    my ($sh, @args) = @_;
    $sh->{current_buffer} = $sh->{prev_buffer} || '';
    $sh->run_command('go') if $sh->{current_buffer};
return;
}


sub do_chistory {
    my ($sh, @args) = @_;
    return $sh->print_list($sh->{chistory});
}

sub do_history {
    my ($sh, @args) = @_;
    for(my $i = 0; $i < @{$sh->{chistory}}; $i++) {
		$sh->print_buffer_nop ($i+1, ":\n", $sh->{chistory}->[$i], "--------\n");
		foreach my $rowref (@{$sh->{rhistory}[$i]}) {
			$sh->print_buffer_nop("    ", join(", ", map { defined $_ ? $_ : q{undef} }@$rowref), "\n");
		}
    }
return;
}

sub do_rhistory {
    my ($sh, @args) = @_;
    for(my $i = 0; $i < @{$sh->{rhistory}}; $i++) {
		$sh->print_buffer_nop ($i+1, ":\n");
		foreach my $rowref (@{$sh->{rhistory}[$i]}) {
			$sh->print_buffer_nop ("    ", join(", ", map { defined $_ ? $_ : q{undef} }@$rowref), "\n");
		}
    }
return;
}


sub do_get {
    my ($sh, $num, @args) = @_;
	# If get is called without a number, retrieve the last command.
	unless( $num ) {
		$num = ($#{$sh->{chistory}} + 1);	

	}
	# Allow for negative history.  If called with -1, get the second
	# to last command execute, -2 third to last, ...
	if ($num and $num =~ /^\-\d+$/) {
		$sh->print_buffer_nop("Negative number $num: \n");
		$num = ($#{$sh->{chistory}} + 1) + $num;
		$sh->print_buffer_nop("Changed number $num: \n");
	}

    if (!$num or $num !~ /^\d+$/ or !defined($sh->{chistory}->[$num-1])) {
		return $sh->err("No such command number '$num'. Use /chistory to list previous commands.");
    }
    $sh->{current_buffer} = $sh->{chistory}->[$num-1];
	$sh->print_buffer($sh->{current_buffer});
    return $num;
}


sub do_perl {
    my ($sh, @args) = @_;
	$DBI::Shell::eval::dbh = $sh->{dbh};
    eval "package DBI::Shell::eval; $sh->{current_buffer}";
    if ($@) { $sh->err("Perl failed: $@") }
    return $sh->run_command('clear');
}

#-------------------------------------------------------------
# Ping the current database connection.
#-------------------------------------------------------------
sub do_ping {
    my ($sh, @args) = @_;
    return $sh->print_buffer_nop (
	"Connection "
	, $sh->{dbh}->ping() == '0' ? 'Is' : 'Is Not'
	, " alive\n" );
}

sub do_edit {
    my ($sh, @args) = @_;

    $sh->run_command('get', '', $&) if @args and $args[0] =~ /^\d+$/;
    $sh->{current_buffer} ||= $sh->{prev_buffer};
	    
    # Find an area to write a temp file into.
    my $tmp_dir = $sh->{tmp_dir} ||
		$ENV{DBISH_TMP} || # Give people the choice.
	    $ENV{TMP}  ||            # Is TMP set?
	    $ENV{TEMP} ||            # How about TEMP?
	    $ENV{HOME} ||            # Look for HOME?
	    $ENV{HOMEDRIVE} . $ENV{HOMEPATH} || # Last env checked.
	    ".";       # fallback: try to write in current directory.

    my $tmp_file = "$tmp_dir/" . ($sh->{tmp_file} || qq{dbish$$.sql});

	$sh->log( "using tmp file: $tmp_file" ) if $sh->{debug};

    local (*FH);
    open(FH, ">$tmp_file") or
	    $sh->err("Can't create $tmp_file: $!\n", 1);
    print FH $sh->{current_buffer} if defined $sh->{current_buffer};
    close(FH) or $sh->err("Can't write $tmp_file: $!\n", 1);

    my $command = "$sh->{editor} $tmp_file";
    system($command);

    # Read changes back in (editor may have deleted and rewritten file)
    open(FH, "<$tmp_file") or $sh->err("Can't open $tmp_file: $!\n");
    $sh->{current_buffer} = join "", <FH>;
    close(FH) or $sh->err( "Close failed: $tmp_file: $!\n" );
    unlink $tmp_file;

    return $sh->run_command('current');
}


#
# Load a command/file from disk to the current buffer.  Currently this
# overwrites the current buffer with the file loaded.  This may change
# in the future.
#
sub do_load {
    my ($sh, $ufile, @args) = @_;

	unless( $ufile ) {
		$sh->err ( qq{load what file?} );
		return;
	}

	# Load file for from sqlpath.
	my $file = $sh->look_for_file($ufile);

	unless( $file ) {
		$sh->err( qq{Unable to locate file $ufile} );
		return;
	}

	unless( -f $file ) {
		$file = q{'undef'} unless $file;
		$sh->err( qq{Can't load $file: $!} );
		return;
	}

	$sh->log("Loading: $ufile : $file") if $sh->{debug};
    local (*FH);
    open(FH, "$file") or $sh->err("Can't open $file: $!");
    $sh->{current_buffer} = join "", <FH>;
    close(FH) or $sh->err( "close$file failed: $!" );

    return $sh->run_command('current');
}

sub do_save {
    my ($sh, $file, @args) = @_;

	unless( $file ) {
		$sh->err ( qq{save to what file?} );
		return;
	}

	$sh->log("Saving... ") if $sh->{debug};
    local (*FH);
    open(FH, "> $file") or $sh->err("Can't open $file: $!");
    print FH $sh->{current_buffer};
    close(FH) or $sh->err( "close$file failed: $!" );

	$sh->log(" $file") if $sh->{debug};
    return $sh->run_command('current');
}

#
# run: combines load and go.
#
sub do_run {
    my ($sh, $file, @args) = @_;
	return unless( ! $sh->do_load( $file ) );
	$sh->log( "running $file" ) if $sh->{debug};
	$sh->run_command('go') if $sh->{current_buffer};
	return;
}

sub do_drivers {
    my ($sh, @args) = @_;
    $sh->log("Available drivers:");
    my @drivers = DBI->available_drivers;
    foreach my $driver (sort @drivers) {
		$sh->log("\t$driver");
    }
return;
}


# $sth = $dbh->column_info( $catalog, $schema, $table, $column );

sub do_col_info {
    my ($sh, @args) = @_;
    my $dbh = $sh->{dbh};

	$sh->log( "col_info( " . join( " ", @args ) . ")" ) if $sh->{debug};

    my $sth = $dbh->column_info(@args);
    unless(ref $sth) {
		$sh->print_buffer_nop ("Driver has not implemented the column_info() method\n");
		$sth = undef;
		return;
	}
return $sh->sth_go($sth, 0, NO_RH);
}


sub do_type_info {
    my ($sh, @args) = @_;
    my $dbh = $sh->{dbh};
    my $ti = $dbh->type_info_all;
    my $ti_cols = shift @$ti;
    my @names = sort { $ti_cols->{$a} <=> $ti_cols->{$b} } keys %$ti_cols;
    my $sth = $sh->prepare_from_data("type_info", $ti, \@names);
    return $sh->sth_go($sth, 0, NO_RH);
}

sub do_describe {
    my ($sh, $tab, @argv) = @_;
    my $dbh = $sh->{dbh};

# Table to describe?
	return $sh->print_buffer_nop( "Describe what?\n" ) unless (defined $tab);

	# First attempt the advanced describe using column_info
	# $sth = $dbh->column_info( $catalog, $schema, $table, $column );
	#$sh->log( "col_info( " . join( " ", @args ) . ")" ) if $sh->{debug};

# Need to determine which columns to include with the describe command.
#	TABLE_CAT,TABLE_SCHEM,TABLE_NAME,COLUMN_NAME,
#	DATA_TYPE,TYPE_NAME,COLUMN_SIZE,BUFFER_LENGTH,
#	DECIMAL_DIGITS,NUM_PREC_RADIX,NULLABLE,
#	REMARKS,COLUMN_DEF,SQL_DATA_TYPE,
#	SQL_DATETIME_SUB,CHAR_OCTET_LENGTH,ORDINAL_POSITION,
#	IS_NULLABLE
#
# desc_format: partbox
# desc_show_long: 1
# desc_show_remarks: 1

	my @names = ();

	# Determine if the short or long display type is used
	if (exists $sh->{desc_show_long} and $sh->{desc_show_long} == 1) {

		if (exists $sh->{desc_show_columns} and defined
			$sh->{desc_show_columns}) {
			@names = map { defined $_ ? uc $_ : () } split( /[,\s+]/,  $sh->{desc_show_columns});
			unless (@names) { # List of columns is empty
				$sh->err ( qq{option desc_show_columns contains an empty list, using default} );
				# set the empty list to undef
				$sh->{desc_show_columns} = undef;
				@names = ();
				push @names, qw/COLUMN_NAME DATA_TYPE TYPE_NAME COLUMN_SIZE PK
					NULLABLE COLUMN_DEF IS_NULLABLE/;
			}
		} else {
			push @names, qw/COLUMN_NAME DATA_TYPE TYPE_NAME COLUMN_SIZE PK
				NULLABLE COLUMN_DEF IS_NULLABLE/;
		}
	} else {
		push @names, qw/COLUMN_NAME TYPE_NAME NULLABLE PK/;
	}

	# my @names = qw/COLUMN_NAME DATA_TYPE NULLABLE PK/;
	push @names, q{REMARKS}
		if (exists $sh->{desc_show_remarks}
			and $sh->{desc_show_remarks} == 1
			and (not grep { m/REMARK/i } @names));

	my $sth = $dbh->column_info(undef, undef, $tab);

    if (ref $sth) {
		
		# Only attempt the primary_key lookup if using the column_info call.

		my @key_column_names = $dbh->primary_key( undef, undef, $tab );
		my %pk_cols;
		# Convert the column names to lower case for matching
		foreach my $idx (0 ..$#key_column_names) {
			$pk_cols{lc($key_column_names[$idx])} = $idx;
		}

		my @t_data = ();  # An array of arrays
			
		while (my $row = $sth->fetchrow_hashref() ) {

			my $col_name	= $row->{COLUMN_NAME};
			my $col_name_lc	= lc $col_name;

			# Use the Type name, unless undefined, they use the data type
			# value.  TODO: Change to resolve the data_type to an ANSI data
			# type ... SQL_
			my $type = $row->{TYPE_NAME} || $row->{DATA_TYPE};

			if (defined $row->{COLUMN_SIZE}) {
				$type .= "(" . $row->{COLUMN_SIZE} . ")";
			}
			my $is_pk = $pk_cols{$col_name_lc} if exists $pk_cols{$col_name_lc};

			my @out_row;
			foreach my $dcol (@names) {

				# Add primary key
				if ($dcol eq q{PK}) {
					push @out_row, defined $is_pk  ? $is_pk : q{};
					next;
				}
				if ($dcol eq q{TYPE_NAME} and
					(exists $sh->{desc_show_long} and $sh->{desc_show_long} == 0)) {
						my $type = $row->{TYPE_NAME} || $row->{DATA_TYPE};
						if (defined $row->{COLUMN_SIZE}) {
							$type .= "(" . $row->{COLUMN_SIZE} . ")";
						}
					push @out_row, $type;
					next;
				}

				# Put a blank if not defined.
				push @out_row, defined $row->{$dcol} ? $row->{$dcol} :  q{};

				# push(my @out_row
				# , $col_name
				# , $type
				# , sprintf( "%4s", ($row->{NULLABLE} eq 0 ? q{N}: q{Y}))
				# );

				# push @out_row, defined $row->{REMARKS} ? $row->{REMARKS} :  q{}
				# 	if (exists $sh->{desc_show_remarks}
				# 	and $sh->{desc_show_remarks} == 1);
			}

			push @t_data, \@out_row;
		}

		$sth->finish; # Complete the handler from column_info


		# Create a new statement handler from the data and names.
		$sth = $sh->prepare_from_data("describe", \@t_data, \@names);

		# Use the built in formatter to handle data.

		my $mode = exists $sh->{desc_format} ? $sh->{desc_format} : 'partbox';
		my $class = eval { DBI::Format->formatter($mode,1) };
		unless ($class) {
			return $sh->alert("Unable to select '$mode': $@");
		}

		my $display = $class->new($sh);

    	$display->header($sth, $sh->{out_fh}||\*STDOUT, $sh->{seperator});

		my $i = 0;
		OUT_ROWS:
    	while (my $rowref = $sth->fetchrow_arrayref()) {
			$i++;
			my $rslt = $display->row($rowref);
    	}

    	return $display->trailer($i);

	}

	#
	# This is the old method, if the driver doesn't support the DBI column_info
	# meta data.
	#
	my $sql = qq{select * from $tab where 1 = 0};
	$sth = $dbh->prepare( $sql );
	$sth->execute;
	my $cnt = $#{$sth->{NAME}};  #
    @names = qw{NAME TYPE NULLABLE};
	my @ti;
	for ( my $c = 0; $c <= $cnt; $c++ ) {
		push( my @j, $sth->{NAME}->[$c] || 0 );
		my $m = $dbh->type_info($sth->{TYPE}->[$c]);
		my $s;
		#print "desc: $c ", $sth->{NAME}->[$c], " ",
			#$sth->{TYPE}->[$c], "\n";
		if (ref $m eq 'HASH') {
			$s = $m->{TYPE_NAME}; #  . q{ } . $sth->{TYPE}->[$c];
		} elsif (not defined $m) {
			 # $s = q{undef } . $sth->{TYPE}->[$c];
			 $s = $sth->{TYPE}->[$c];
		} else {
			warn "describe:  not good.  Not good at all!";
		}

		if (defined $sth->{PRECISION}->[$c]) {
			$s .= "(" . $sth->{PRECISION}->[$c] || '';
			$s .= "," . $sth->{SCALE}->[$c] 
			if ( defined $sth->{SCALE}->[$c] 
				and $sth->{SCALE}->[$c] ne 0);
			$s .= ")";
		}
		push(@j, $s,
			 $sth->{NULLABLE}->[$c] ne 1? qq{N}: qq{Y} );
		push(@ti,\@j);
	}

	$sth->finish;
	$sth = $sh->prepare_from_data("describe", \@ti, \@names);
	return $sh->sth_go($sth, 0, NO_RH);
}


sub prepare_from_data {
    my ($sh, $statement, $data, $names, %attr) = @_;
    my $sponge = DBI->connect("dbi:Sponge:","","",{ RaiseError => 1 });
    my $sth = $sponge->prepare($statement, { rows=>$data, NAME=>$names, %attr });
    return $sth;
}


# Do option: sets or gets an option
sub do_option {
    my ($sh, @args) = @_;

	my $value;
    unless (@args) {
		foreach my $opt (sort keys %{ $sh->{options}}) {
			$value = (defined $sh->{$opt}) ? $sh->{$opt} : 'undef';
			$sh->log(sprintf("%20s: %s", $opt, $value));
		}
		return;
    }

    my $options = Text::Abbrev::abbrev(keys %{$sh->{options}});

    # Expecting the form [option=value] [option=] [option]
    foreach my $opt (@args) {
		my ($opt_name);
		($opt_name, $value) = $opt =~ /^\s*(\w+)(?:=(.*))?/;
		$opt_name = $options->{$opt_name} || $opt_name if $opt_name;
		if (!$opt_name || !$sh->{options}->{$opt_name}) {
			$sh->log("Unknown or ambiguous option name '$opt_name'");
			next;
		}
		my $crnt = (defined $sh->{$opt_name}) ? $sh->{$opt_name} : 'undef';
		if (not defined $value) {
			$sh->log("/option $opt_name=$crnt");
			$value = $crnt;
		}
		else {
			# Need to deal with quoted strings.
			# 1 while ( $value =~ s/[^\\]?["']//g );  #"'
			$sh->log("/option $opt_name=$value  (was $crnt)")
				unless $sh->{batch};
			$sh->{$opt_name} = ($value eq 'undef' ) ? undef : $value;
		}
    }
return (defined $value ? $value : undef);
}

#
# Do prompt: sets or gets a prompt
#
sub do_prompt {
    my ($sh, @args) = @_;

	return $sh->log( $sh->{prompt} ) unless (@args);
return $sh->{prompt} = join( '', @args );
}


sub do_table_info {
    my ($sh, @args) = @_;
    my $dbh = $sh->{dbh};
    my $sth = $dbh->table_info(@args);
    unless(ref $sth) {
	$sh->log("Driver has not implemented the table_info() method, ",
		"trying tables()\n");
	my @tables = $dbh->tables(@args); # else try list context
	unless (@tables) {
	    $sh->print_buffer_nop ("No tables exist ",
		  "(or driver hasn't implemented the tables method)\n");
	    return;
	}
	$sth = $sh->prepare_from_data("tables",
		[ map { [ $_ ] } @tables ],
		[ "TABLE_NAME" ]
	);
    }
return $sh->sth_go($sth, 0, NO_RH);
}

# Support functions.
sub is_spooling	( ) { return shift->{spooling}		}
sub spool_on	( ) { return shift->{spooling} = 1	}
sub spool_off	( ) { return shift->{spooling} = 0	}

1;
__END__

=head1 TO DO

Proper docs - but not yet, too much is changing.

"source file" command to read command file.
Allow to nest via stack of command file handles.
Add command log facility to create batch files.

Commands:

Use Data::ShowTable if available.

Define DBI::Shell plug-in semantics.
	Implement import/export as plug-in module

Clarify meaning of batch mode

Completion hooks

Set/Get DBI handle attributes

Portability

Emulate popular command shell modes (Oracle, Ingres etc)?

=head1 ARGUMENTS

=over 4

=item debug

dbish --debug	enable debug messages

=item batch

dbish --batch < batch_file

=back

=head1 COMMANDS

Many commands - few documented, yet!

=over 4

=item help

  help

=item chistory

  chistory          (display history of all commands entered)
  chistory | YourPager (display history with paging)

=item clear

  clear             (Clears the current command buffer)

=item commit

  commit            (commit changes to the database)

=item connect

  connect           (pick from available drivers and sources)
  connect dbi:Oracle (pick source from based on driver)
  connect dbi:YourDriver:YourSource i.e. dbi:Oracle:mysid

Use this option to change userid or password.

=item count

	count table1 [...]

Run a select count(*) from table on each table listed with this command.

=item current

  current            (Display current statement in the buffer)

=item do

  do                 (execute the current (non-select) statement)

	dbish> create table foo ( mykey integer )
	dbish> /do

	dbish> truncate table OldTable /do (Oracle truncate)

=item drivers

  drivers            (Display available DBI drivers)

=item edit

  edit               (Edit current statement in an external editor)

Editor is defined using the environment variable $VISUAL or
$EDITOR or default is vi.  Use option editor=new editor to change
in the current session.

To read a file from the operating system invoke the editor (edit)
and read the file into the editor buffer.

=item exit

  exit              (Exits the shell)

=item get

	get			Retrieve a previous command to the current buffer.

	get 1			Retrieve the 1 command executed into the current 
					buffer.

	get -1         Retrieve the second to last command executed into
					the current buffer.

=item go

  go                (Execute the current statement)

Run (execute) the statement in the current buffer.  This is the default
action if the statement ends with /

	dbish> select * from user_views/

	dbish> select table_name from user_tables
	dbish> where table_name like 'DSP%'
	dbish> /

	dbish> select table_name from all_tables/ | more

=item history

  history            (Display combined command and result history)
  history | more

=item load

  load file name    (read contains of file into the current buffer)

The contains of the file is loaded as the current buffer.

=item option

  option [option1[=value]] [option2 ...]
  option            (Displays the current options)
  option   MyOption (Displays the value, if exists, of MyOption)
  option   MyOption=4 (defines and/or sets value for MyOption)

=item perl

  perl               (Evaluate the current statement as perl code)

=item quit

  quit               (quit shell.  Same as exit)

=item redo

  redo               (Re-execute the previously executed statement)

=item rhistory

  rhistory           (Display result history)

=item rollback

  rollback           (rollback changes to the database)

For this to be useful, turn the autocommit off. option autocommit=0

=item run

  run file name      (load and execute a file.)

This commands load the file (may include full path) and executes.  The
file is loaded (replaces) the current buffer.  Only 1 statement per
file is allowed (at this time).

=item save

  save file name    (write contains of current buffer to file.)

The contains of the current buffer is written to file.  Currently,
this command will overwrite a file if it exists.

=item spool

  spool file name  (Starts sending all output to file name)
  spool on         (Starts sending all output to on.lst)
  spool off        (Stops sending output)
  spool            (Displays the status of spooling)

When spooling, everything seen in the command window is written to a file
(except some of the prompts).

=item table_info

  table_info         (display all tables that exist in current database)
  table_info | more  (for paging)

=item trace

  trace              (set DBI trace level for current database)

Adjust the trace level for DBI 0 - 4.  0 off.  4 lots of information.
Useful for determining what is really happening in DBI.  See DBI.

=item type_info

  type_info          (display data types supported by current server)

=back

=head1 ENVIRONMENT

=over 4

=item DBISH_TMP

Where to write temporary files.

=item DBISH_CONFIG

Which configuration file used.  Unset to not read any additional
configurations.

=back


=head1 AUTHORS and ACKNOWLEDGEMENTS

The DBI::Shell has a long lineage.

It started life around 1994-1997 as the pmsql script written by Andreas
König. Jochen Wiedmann picked it up and ran with it (adding much along
the way) as I<dbimon>, bundled with his DBD::mSQL driver modules. In
1998, around the time I wanted to bundle a shell with the DBI, Adam
Marks was working on a dbish modeled after the Sybase sqsh utility.

Wanting to start from a cleaner slate than the feature-full but complex
dbimon, I worked with Adam to create a fairly open modular and very
configurable DBI::Shell module. Along the way Tom Lowery chipped in
ideas and patches. As we go further along more useful code and concepts
from Jochen's dbimon is bound to find it's way back in.

=head1 COPYRIGHT

The DBI::Shell module is Copyright (c) 1998 Tim Bunce. England.
All rights reserved. Portions are Copyright by Jochen Wiedmann,
Adam Marks and Tom Lowery.

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.

=cut
