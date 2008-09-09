package Slim::Utils::OS;

# $Id: Base.pm 21790 2008-07-15 20:18:07Z andy $

# Base class for OS specific code

use strict;
use Config;
use File::Path;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);

sub new {
	my $class = shift;

	my $self = {
		osDetails  => {},
	};
	
	return bless $self, $class;
}

sub initDetails {
	return shift->{osDetails};
}

sub details {
	return shift->{osDetails};
}

sub initPrefs {};

=head2 initSearchPath( )

Initialises the binary seach path used by Slim::Utils::Misc::findbin to OS specific locations

=cut

sub initSearchPath {
	my $class = shift;
	# Initialise search path for findbin - called later in initialisation than init above

	# Reduce all the x86 architectures down to i386, including x86_64, so we only need one directory per *nix OS. 
	$class->{osDetails}->{'binArch'} = $Config::Config{'archname'};
	$class->{osDetails}->{'binArch'} =~ s/^(?:i[3456]86|x86_64)-([^-]+).*/i386-$1/;

	my @paths = ( catdir($class->dirsFor('Bin'), $class->{osDetails}->{'binArch'}), catdir($class->dirsFor('Bin'), $^O), $class->dirsFor('Bin') );
	
	Slim::Utils::Misc::addFindBinPaths(@paths);
}

=head2 dirsFor( $dir )

Return OS Specific directories.

Argument $dir is a string to indicate which of the SqueezeCenter directories we
need information for.

=cut

sub dirsFor {
	my $class   = shift;
	my $dir     = shift;

	my @dirs    = ();
	
	if ($dir eq "Plugins") {
		push @dirs, catdir($Bin, 'Slim', 'Plugin');
	}

	return wantarray() ? @dirs : $dirs[0];
}

sub scanner {
	return "$Bin/scanner.pl";
}

sub dontSetUserAndGroup { 0 }

=head2 getProxy( )
	Try to read the system's proxy setting by evaluating environment variables,
	registry and browser settings
=cut

sub getProxy {
	my $proxy = '';

	$proxy = $ENV{'http_proxy'};
	my $proxy_port = $ENV{'http_proxy_port'};

	# remove any leading "http://"
	if($proxy) {
		$proxy =~ s/http:\/\///i;
		$proxy = $proxy . ":" .$proxy_port if($proxy_port);
	}

	return $proxy;
}

sub ignoredItems {
	return (
		# Items we should ignore on a linux volume
		'lost+found' => 1,
		'@eaDir'     => 1,
	);
}

=head2 get( 'key' [, 'key2', 'key...'] )

Get a list of values from the osDetails list

=cut


sub get {
	my $class = shift;
	
	return map { $class->{osDetails}->{$_} } 
	       grep { $class->{osDetails}->{$_} } @_;
}


=head2 setPriority( $priority )

Set the priority for the server. $priority should be -20 to 20

=cut

sub setPriority {
	my $class    = shift;
	my $priority = shift;
	return unless defined $priority && $priority =~ /^-?\d+$/;

	# For *nix, including OSX, set whatever priority the user gives us.
	Slim::Utils::Log::logger('server')->info("SqueezeCenter changing process priority to $priority");

	eval { setpriority (0, 0, $priority); };

	if ($@) {
		Slim::Utils::Log->logError("Couldn't set priority to $priority [$@]");
	}
}

=head2 getPriority( )

Get the current priority of the server.

=cut

sub getPriority {

	my $priority = eval { getpriority (0, 0) };

	if ($@) {
		Slim::Utils::Log->logError("Can't get priority [$@]");
	}

	return $priority;
}
1;