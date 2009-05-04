package Win32::Process::List;

use 5.006;
use strict;
use warnings;
use Carp;
use Data::Dumper;

require Exporter;
require DynaLoader;
use AutoLoader;

our @ISA = qw(Exporter DynaLoader);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Win32::Process::List ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);
our $VERSION = '0.09';

#sub AUTOLOAD {
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.  If a constant is not found then control is passed
    # to the AUTOLOAD in AutoLoader.

#    my $constname;
#   our $AUTOLOAD;
#    ($constname = $AUTOLOAD) =~ s/.*:://;
#    croak "& not defined" if $constname eq 'constant';
#    local $! = 0;
#    my $val = constant($constname, @_ ? $_[0] : 0);
#    if ($! != 0) {
#	if ($! =~ /Invalid/ || $!{EINVAL}) {
#	    $AutoLoader::AUTOLOAD = $AUTOLOAD;
#	    goto &AutoLoader::AUTOLOAD;
#	}
#	else {
#	    croak "Your vendor has not defined Win32::Process::List macro $constname";
#	}
#   }
#    {
#	no strict 'refs';
	# Fixed between 5.005_53 and 5.005_61
#	if ($] >= 5.00561) {
#	    *$AUTOLOAD = sub () { $val };
#	}
#	else {
#	    *$AUTOLOAD = sub { $val };
#	}
#   }
#    goto &$AUTOLOAD;
#}

bootstrap Win32::Process::List $VERSION;

# Preloaded methods go here.

sub new
{
	my $class = shift;
	my $self = {
		nProcesses=>0,
		processes=>[],
		isError=>0,
		Error=>undef
		};
	bless $self, $class;
	my $error = undef;
	my $err = ListProcesses($error);
	if($error) { 
		$self->{isError} = 1;
		$self->{Error} = $error;
	}
	#my @arr = @{ $err };
	# $self->{processes} = [ @arr ];
	$self->{processes} = [ $err ];
	my %h = %{ $err };
	my $nProcesses = (scalar keys %h);
	$self->{nProcesses} = $nProcesses;
	return $self;
	
}

sub ProcessAliveNa
{
	my $self = shift;
	my $process =shift;
	if($process !~ /\.exe$/ )
	{
		$process .= '.exe';
	}

	$self->{Error}="";
	$self->{isError}=0;
	my $ret =ProcessAliveN($process, $self->{Error});
	if($ret == -1) { $self->{isError}=1; }
	return $ret;
	
	
}

sub ProcessAlivePid
{
	my $self = shift;
	$self->{Error}="";
	$self->{isError}=0;
	my $ret = ProcessAliveP(shift,$self->{Error});
	if($ret == -1) { $self->{isError}=1; }
	return $ret;

}

sub ProcessAliveName
{
	my $self = shift;
	my $process=shift;
	$process=lc($process);
	my @procArr=();
	my $alive = 0;
	my %ret;
	$self->{isError}=0;
	$self->{Error}="";
	if(ref($process) eq "ARRAY")
	{
		#my $count=0;
		#@procArr=@{$process};
		#foreach (@procArr)
		#{
		#	if($procArr[$count] !~ /\.exe$/ && $usePID == 0)
		#	{
		#		$procArr[$count]= $procArr[$count] . '.exe';
		#	}
		#	$count++;
		#}
		$self->{isError} = 1;
		$self->{Error} = "ARRAY of processes not yet supported!";
		return;
	} else { 
		if($process !~ /\.exe$/ )
		{
			$process .= '.exe';
		}
		push(@procArr, $process);
	}
	my $error = undef;
	my $y = undef;
	my $processes=ListProcesses($error);
	my %h=%{$processes};
	foreach my $p (keys %h)
	{
		if(lc($h{$p}) eq $process) { $ret{$process} = 1; $alive=1; }
	}
	return %ret;
}

sub GetNProcesses
{
	my $self = shift;
	return $self->{nProcesses};
}

sub GetProcessPid
{
	my $self = shift;
	my $pr = shift;
	my %ret;
	$pr=lc($pr);
	$self->{isError} = 0;
	my @a = @{ $self->{processes} };
	my %h = %{ $a[0] };
	my $count = 0;
	foreach my $key (keys %h)
	{
		if(lc($h{$key}) =~ /$pr/) { 
			#$a[$count] = $key;
			$ret{$h{$key}}=$key;
			$count++;
		}
	}
	if($count > 0) {
		return %ret;
	}
	$self->{isError} = 1;
	$self->{Error} = "Error: no PID found for $pr";
	return;
}

sub GetProcesses
{
	my $self = shift;
	$self->{isError} = 0;
	my @tmp = @{ $self->{processes} };
	my %h = %{ $tmp[0] };
	return %h;
	
}

sub IsError
{
	my $self = shift;
	return $self->{isError};
}

sub GetErrorText
{
	my $self = shift;
	if($self->{isError} == 1)
	{
		return $self->{Error};
	}
	return;
}

DESTROY
{
	my $self = shift;
	#print "destroying!\n";
}

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

Win32::Process::List - Perl extension to get all processes and thier PID on a Win32 system

=head1 SYNOPSIS

  use Win32::Process::List;
  my $P = Win32::Process::List->new();	constructor
  my %list = $P->GetProcesses();	returns the hashes with PID and process name
  foreach my $key ( keys %list ) {
	# $list{$key} is now the process name and $key is the PID
	print sprintf("%30s has PID %15s", $list{$key}, $key) . "\n";
  }
  my $PID = $P->GetProcessPid("explorer"); get the PID of process explorer.exe
  my $np = $P->GetNProcesses();  returns the number of processes

=head1 DESCRIPTION

  Win32::Process::List is a module to get the running processes with their PID's from
  a Win32 System. Please look at Win32/Process/List/processes.pl.

=head2 EXPORT

None by default.


=head1 AUTHOR

Reinhard Pagitsch, E<lt>rpirpag@gmx.atE<gt>

=head1 SEE ALSO

L<perl>.

=cut
