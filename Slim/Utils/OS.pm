package Slim::Utils::OS;

# $Id: Base.pm 21790 2008-07-15 20:18:07Z andy $

# Base class for OS specific code

use strict;
use Config;
use File::Path;
use File::Copy;
use File::Spec::Functions qw(:ALL);
use FindBin qw($Bin);
use POSIX qw(LC_CTYPE LC_TIME);

use constant MAX_LOGSIZE => 1024 * 1024 * 100;

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

=head2 logRotate( $dir )

Simple log rotation for systems which don't do this automatically (OSX/Windows).

=cut

sub logRotate {
	my $class   = shift;
	my $dir     = shift || Slim::Utils::OSDetect::dirsFor('log');

	opendir(DIR, $dir) or return;

	while ( defined (my $file = readdir(DIR)) ) {

		next if $file !~ /\.log$/i;
		
		$file = catdir($dir, $file);

		# max. log size 10MB
		if (-s $file > MAX_LOGSIZE) {

			# keep one old copy		
			my $oldfile = "$file.0";
			unlink $oldfile if -e $oldfile;
			
			move($file, $oldfile);
		}
	}
	
	closedir(DIR);
}


=head2 decodeExternalHelperPath( $filename )

When calling calling external helper apps (transcoding, MySQL etc.)
we might need to encode the path to correctly handle non-latin characters.

=cut

sub decodeExternalHelperPath {
	my $path = $_[1];
	
	# Bug 8118, only decode if filename can't be found
	if ( !-e $path ) {
		$path = Slim::Utils::Unicode::utf8decode_locale($path);
	}
	
	return $path;
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

=head2 localeDetails()

Get details about the locale, system language etc.

=cut

sub localeDetails {
	my $lc_time  = POSIX::setlocale(LC_TIME)  || 'C';
	my $lc_ctype = POSIX::setlocale(LC_CTYPE) || 'C';

	# If the locale is C or POSIX, that's ASCII - we'll set to iso-8859-1
	# Otherwise, normalize the codeset part of the locale.
	if ($lc_ctype eq 'C' || $lc_ctype eq 'POSIX') {
		$lc_ctype = 'iso-8859-1';
	} else {
		$lc_ctype = lc((split(/\./, $lc_ctype))[1]);
	}

	# Locale can end up with nothing, if it's invalid, such as "en_US"
	if (!defined $lc_ctype || $lc_ctype =~ /^\s*$/) {
		$lc_ctype = 'iso-8859-1';
	}

	# Sometimes underscores can be aliases - Solaris
	$lc_ctype =~ s/_/-/g;

	# ISO encodings with 4 or more digits use a hyphen after "ISO"
	$lc_ctype =~ s/^iso(\d{4})/iso-$1/;

	# Special case ISO 2022 and 8859 to be nice
	$lc_ctype =~ s/^iso-(2022|8859)([^-])/iso-$1-$2/;

	$lc_ctype =~ s/utf-8/utf8/gi;

	# CJK Locales
	$lc_ctype =~ s/eucjp/euc-jp/i;
	$lc_ctype =~ s/ujis/euc-jp/i;
	$lc_ctype =~ s/sjis/shiftjis/i;
	$lc_ctype =~ s/euckr/euc-kr/i;
	$lc_ctype =~ s/big5/big5-eten/i;
	$lc_ctype =~ s/gb2312/euc-cn/i;
	
	return ($lc_ctype, $lc_time);
}

=head2 getSystemLanguage()

Return the system's language or 'EN' as default value

=cut

sub getSystemLanguage {
	my $class = shift;
	$class->_parseLanguage(POSIX::setlocale(LC_CTYPE)); 
}

sub _parseLanguage {
	my ($class, $language) = @_;
	
	$language = uc($language);
	$language =~ s/\.UTF.*$//;
	$language =~ s/(?:_|-|\.)\w+$//;
	
	return $language || 'EN';
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