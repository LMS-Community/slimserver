package Slim::Utils::Log;

# $Id$

# SlimServer Copyright (c) 2001-2006 Dan Sully, Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Utils::Log

=head1 SYNOPSIS

use Slim::Utils::Log;

my $log = logger('category');

$log->warn('foo!');

logBacktrace("Couldn't connect to server.");

=head1 EXPORTS

logger(), logWarning(), logError(), logBacktrace()

=head1 DESCRIPTION

A wrapper around Log::Log4perl

=head1 METHODS

=cut

use strict;
use base qw(Log::Log4perl::Logger);

use Exporter::Lite;
use File::Path;
use File::Spec;
use Log::Log4perl;
use Path::Class;
use Scalar::Util qw(blessed);

use Slim::Utils::OSDetect;

our @EXPORT = qw(logger logWarning logError logBacktrace);

my $rootLogger    = undef;
my $logDir        = undef;
my %categories    = ();
my %descriptions  = ();
my %appenders     = ();
my %runningConfig = ();
my $needsReInit   = 0;
my $hasConfigFile = 0;
my %debugLine     = ();

my @validLevels   = qw(OFF FATAL ERROR WARN INFO DEBUG);

=head2 isInitialized( )

Returns true if the logging system is initialized. False otherwise.

=cut

sub isInitialized {
	my $class = shift;

	return Log::Log4perl->initialized;
}

=head2 init( )

Initialize the logging subsystem.

=cut

sub init {
	my ($class, $args) = @_;

	my %config  = ($class->_defaultCategories, $class->_defaultAppenders);

	# If the user passed logdir, that wins when the file callback is run.
	if ($args->{'logdir'} && -d $args->{'logdir'}) {

		$logDir = $args->{'logdir'};
	}

	# If the user has specified a log config, or there is a log config written
	# out (ie: the user has changed settings in the web UI) - look for that.
	my $logconf = $args->{'logconf'} || $class->defaultConfigFile;
	my $logtype = $args->{'logtype'} || 'server';

	# If the user has specified any --debug commands, parse those.
	if ($args->{'debug'} || $::logCategories) {

		$class->parseDebugLine($args->{'debug'} || $::logCategories);
	}

	# If the user has specified a log file, check for a pipe, etc.
	if ($args->{'logfile'}) {

		# Bug 4407 - specifying a log file is overriden in serverLogFile().
		#$class->addLogAppender({
		#	'filename' => $args->{'logfile'},
		#});
	}

	# Anything passed on the command line will override the config file.
	$class->parseDebugLine($args->{'debug'} || $::logCategories);

	if ($logconf && -r $logconf) {

		%config = $class->_readConfig($logconf);

		$hasConfigFile = 1;
	}

	# And now merge in any command line params
	%config = (%config, $class->_customCategories, $class->_customAppenders);

	# Set a root logger
	if (!$config{'log4perl.rootLogger'} || $config{'log4perl.rootLogger'} !~ /$logtype/) {

		# Add our default root logger
		my @levels = ('WARN', $logtype);

		if ($::daemon || !$::quiet) {
			push @levels, 'screen';
		}

		$config{'log4perl.rootLogger'} = join(', ', @levels);
	}

	# Set so we can access later.
	%runningConfig = %config;

	# And finally call l4p's initialization method.
  	Log::Log4perl->init(\%config);

	$rootLogger = $class->get_logger('');
}

=head2 reInit ( )

Reinitialize the logging subsystem if the log config has changed.

=cut

sub reInit {
	my ($class, $args) = @_;

	# Recreate the config from the running one, and overwritting with the customized ones.
	my %config = (%runningConfig, $class->_customCategories, $class->_customAppenders);

	# For next time.
	%runningConfig = %config;

	# Write out the config if requested
	if ($hasConfigFile && ($args->{'overwriteCustomConfig'} || $debugLine{'persist'})) {

		$class->writeConfig($args->{'logconf'});

	} else {

		$class->writeConfig;
	}

	# and reinitialize.
  	Log::Log4perl->init(\%config);

	$rootLogger = $class->get_logger('');

	$needsReInit = 0;

	# SQL debugging is special - we need to turn on DBIx::Class debugging.
	if ($INC{'Slim/Schema.pm'}) {

		Slim::Schema->updateDebug;
	}
}

=head2 needsReInit ( )

Let's the caller know if the Logging subsystem needs to be reinitialized.

=cut

sub needsReInit {
	my $class = shift;

	return $needsReInit;
}

=head2 logger( [ $category ] )

Get a logger for the category.

=cut

sub logger {
	my $category = shift;

	return Slim::Utils::Log->get_logger($category);
}

=head2 logWarning( [ $msg ] )

Send out an warning message. Will be prefixed with 'Warning: '

Can be called as a function (will use the root logger), or as a log category method.

=cut

sub logWarning {
	my $self    = $rootLogger;
	my $blessed = blessed($_[0]);

	if ($blessed && $blessed =~ /Log/) {
		$self = shift;
	}

	$Log::Log4perl::caller_depth++;

	$self->warn('Warning: ', @_);

	$Log::Log4perl::caller_depth--;
}

=head2 logError( [ $msg ] )

Send out an error message. Will be prefixed with 'Error'

Can be called as a function (will use the root logger), or as a log category method.

=cut

sub logError {
	my $self    = $rootLogger;
	my $blessed = blessed($_[0]);

	if ($blessed && $blessed =~ /Log/) {
		$self = shift;
	}

	$Log::Log4perl::caller_depth++;

	$self->error('Error: ', @_);

	$Log::Log4perl::caller_depth--;
}

=head2 logBacktrace( [ $msg ] )

Print out backtrace.

Can be called as a function (will use the root logger), or as a log category method.

=cut

sub logBacktrace {
	my $self    = $rootLogger;
	my $blessed = blessed($_[0]);

	if ($blessed && $blessed =~ /Log/) {
		shift;
	}

	$Log::Log4perl::caller_depth++;

	if (scalar @_) {
		$self->error("Error: ", @_);
	}

	$self->error(Slim::Utils::Misc::bt(1));

	$Log::Log4perl::caller_depth--;
}

=head2 addLogCategory ( \%args )

Adds a logging category, level & description to the server.

Arguments:

=over 4

=item * category

=item * defaultLevel

=item * description

=back

=cut

sub addLogCategory {
	my $class = shift;
	my $args  = shift;

	if (ref($args) ne 'HASH') {

		logBacktrace("Didn't pass hash args!");
		return;
	}

	if (my $category = $args->{'category'}) {

		$class->setLogLevelForCategory(
			$category, ($debugLine{$category} || $args->{'defaultLevel'} || 'WARN'),
		);

		if (my $desc = $args->{'description'}) {

			$descriptions{$category} = $desc;
		}

		return logger($args->{'category'});
	}

	logBacktrace("No category was passed! Returning rootLogger");

	return $rootLogger;
}

=head2 setLogLevelForCategory ( category, level )

Set/Update the log level for a logging category.

=cut

sub setLogLevelForCategory {
	my ($class, $category, $level) = @_;

	if (!$category) {

		logBacktrace("\$category is not set.");

		return 0;
	}

	if (!defined $level) {

		logBacktrace("\$level is not set.");

		return 0;
	}

	if (!grep { /^$level$/ } @validLevels) {

		logBacktrace("Level [$level] is invalid for category: [$category]");

		return 0;
	}

	if ($category !~ /^log4perl\.logger/) {

		$category = "log4perl.logger.$category";
	}

	# If the level is the same, it's a no-op.
	if (defined $categories{$category} && $categories{$category} eq $level) {

		return -1;
	}

	$categories{$category} = $level;

	$needsReInit = 1;

	return 1;
}

=head2 isValidCategory ( category )

Returns true if the passed category is valid. 

Returns false otherwise.

=cut

sub isValidCategory {
	my ($class, $category) = @_;

	if ($category !~ /^log4perl\.logger/) {

		$category = "log4perl.logger.$category";
	}

	if (defined $runningConfig{$category}) {
		return 1;
	}

	return 0;
}

=head2 allCategories ( )

Returns the list of all logging categories the server knows about.

=cut

sub allCategories {
	my $class = shift;

	my %categories = ();
	my %config     = ($class->_defaultCategories, $class->_customCategories);

	for my $key (keys %config) {

		# hide the following as they are not debugging categories
		next if ($key =~ /additivity|perfmon/);
		my $value = $runningConfig{$key};

		$key =~ s/^log4perl\.logger\.//;

		$categories{$key} = $value;
	}

	return \%categories;
}

sub _customCategories {
	my $class = shift;

	return %categories;
}

=head2 addLogAppender ( \%args )

Adds a log appender.

Arguments:

=over 4

=item * name

=item * appender

=item * filemode

=item * filename

=back

See L<Log::Log4perl> for valid appenders.

=cut

sub addLogAppender {
	my $class = shift;
	my $args  = shift;

	if (ref($args) ne 'HASH') {

		logBacktrace("Didn't pass hash args!");
		return;
	}

	my $name     = $args->{'name'}     || 'server';
	my $filemode = $args->{'filemode'} || 'append';
	my $filename = $args->{'logfile'}  || $::logfile || _logFileFor($name);
	my $appender = $args->{'appender'} || 'Log::Log4perl::Appender::File';

	if ($filename =~ s/|//) {

		$filemode = 'pipe';
	}

	$appenders{$name} = {
		'mode'     => $filemode,
		'appender' => $appender,
		'filename' => $filename,
	};
}

sub _customAppenders {
	my $class = shift;

	return $class->_fixupAppenders(\%appenders);
}

=head2 descriptionForCategory ( category )

Returns the string token for the description of the given category.

=cut

sub descriptionForCategory {
	my ($class, $category) = @_;

	if (exists $descriptions{$category}) {

		return $descriptions{$category};
	}

	my $string = uc("DEBUG_${category}");
	   $string =~ s/\./_/g;

	return $string;
}

=head2 validLevels ( )

Returns the list of valid log levels.

=cut

sub validLevels {
	my $class = shift;

	return @validLevels;
}

=head2 serverLogFile ( )

Returns the location of the server's main log file.

=cut

sub serverLogFile {
	my $class = shift;

	# If the user has requested an override.
	if ($::logfile) {
		return $::logfile;
	}

	return _logFileFor('server');
}

=head2 scannerLogFile ( )

Returns the location of SlimServer's scanner log file.

=cut

sub scannerLogFile {
	my $class = shift;

	# If the user has requested an override.
	if ($::logfile) {
		return $::logfile;
	}

	return _logFileFor('scanner');
}

=head2 perfmonLogFile ( )

Returns the location of SlimServer's performance monitor log file.

=cut

sub perfmonLogFile {
	my $class = shift;

	# If the user has requested an override.
	if ($::logfile) {
		return $::logfile;
	}

	return _logFileFor('perfmon');
}

sub _logFileFor {
	my $file  = shift || return '';

	my $dir   = $logDir || Slim::Utils::OSDetect::dirsFor('log');

	if (!-d $dir) {
		mkpath($dir);
	}

	if (-d $dir) {

		return File::Spec->catdir($dir, "$file.log");
	}

	return '';
}

=head2 parseDebugLine ( line )

Returns the string token for the description of the given category.

$line can look like:

network.protocol.slimproto=info,plugin.itunes=WARN,plugin.rs232

If no log level is given, the category will the verbose 'DEBUG' level.

=cut

sub parseDebugLine {
	my $class = shift;
	my $line  = shift || return;

	for my $statement (split /\s*,\s*/, $line) {

		my ($category, $level) = split /=/, $statement;

		if ($level) {

			$level = uc($level);

		} else {

			$level = 'DEBUG';
		}

		$class->setLogLevelForCategory($category, $level);

		$debugLine{$category} = $level;
	}
}

=head2 defaultConfigFile ( )

Returns the location of the default config file for the platform.

=cut

sub defaultConfigFile {
	my $class = shift;

	my $dir = $logDir || Slim::Utils::OSDetect::dirsFor('log');

	if (defined $dir && -d $dir) {

		return File::Spec->catdir($dir, 'log.conf');
	}
}

=head2 writeConfig ( )

Writes out the current logging categories, levels & appenders

=cut

sub writeConfig {
	my $class    = shift;
	my $filename = shift || $class->defaultConfigFile;

	my $file     = file($filename);
	my $fh       = $file->openw or return 0;

	print $fh "# This file is autogenerated by $class\n\n";
	print $fh "# If you wish to modify, make a copy and call SlimServer\n";
	print $fh "# with the --logconf=customlog.conf option\n\n";

	for my $line (sort keys %runningConfig) {

		print $fh "$line = $runningConfig{$line}\n";
	}

	$fh->close;

	return 1;
}

# Quick config reader to parse into key = value pairs.
sub _readConfig {
	my $class    = shift;
	my $filename = shift;

	my $file     = file($filename);
	my $fh       = $file->open;
	my %config   = ();

	#
	while (my $line = <$fh>) {

		if ($line =~ /^\s*$/) {
			next;
		}

		if ($line =~ /^#/) {
			next;
		}

		if ($line =~ /(\S+?)\s*=\s*(.*)/) {

			$config{$1} = $2;
		}
	}

	$fh->close;

	return %config;
}

# log4perl.logger
sub _defaultCategories {
	my $class = shift;

	my %defaultCategories = (

		'server'                     => 'INFO',
		'server.memory'              => 'OFF',
		'server.plugins'             => 'WARN',
		'server.scheduler'           => 'WARN',
		'server.select'              => 'WARN',
		'server.timers'              => 'WARN',

		'artwork'                    => 'WARN',
		'favorites'                  => 'WARN',
		'prefs'                      => 'WARN',
		'factorytest'                => 'WARN',

		'network.asynchttp'          => 'WARN',
		'network.http'               => 'WARN',
		'network.mdns'               => 'WARN',
		'network.protocol'           => 'WARN',
		'network.protocol.slimproto' => 'WARN',
		'network.protocol.slimp3'    => 'WARN',
		'network.upnp'               => 'WARN',
		'network.jsonrpc'            => 'WARN',

		'formats.audio'              => 'WARN',
		'formats.xml'                => 'WARN',
		'formats.playlists'          => 'WARN',

		'database.info'              => 'WARN',
		'database.mysql'             => 'WARN',
		'database.sql'               => 'WARN',

		'os.files'                   => 'WARN',
		'os.paths'                   => 'WARN',

		'control.command'            => 'WARN',
		'control.queries'            => 'WARN',
		'control.stdio'              => 'WARN',

		'player.display'             => 'WARN',
		'player.fonts'               => 'WARN',
		'player.firmware'            => 'WARN',
		'player.ir'                  => 'WARN',
		'player.menu'                => 'WARN',
		'player.playlist'            => 'WARN',
		'player.source'              => 'WARN',
		'player.streaming'           => 'WARN',
		'player.streaming.direct'    => 'WARN',
		'player.streaming.remote'    => 'WARN',
		'player.sync'                => 'WARN',
		'player.text'                => 'WARN',
		'player.ui'                  => 'WARN',

		'scan'                       => 'INFO',
		'scan.scanner'               => 'INFO',
		'scan.import'                => 'INFO',

		'perfmon'                    => 'WARN, screen-raw, perfmon',
	);

	# Map our shortened names to the ones l4p wants.
	my %mappedCategories = ();

	while (my ($category, $level) = each %defaultCategories) {

		$mappedCategories{"log4perl.logger.$category"} = $level;

		# turn off propagation to default appenders if specific appenders are specified
		if ($level =~ /,/) {
			$mappedCategories{"log4perl.additivity.$category"} = 0;
		}

	}

	return %mappedCategories;
}

# log4perl.appender
sub _defaultAppenders {
	my $class = shift;

	my %defaultAppenders = (

		'screen' => {
			'appender' => 'Log::Log4perl::Appender::Screen',
			'stderr'   => 0,
		},

		'screen-raw' => {
			'appender' => 'Log::Log4perl::Appender::Screen',
			'stderr'   => 0,
			'layout'   => 'raw',
		},

		'server' => {
			'appender' => 'Log::Log4perl::Appender::File',
			'mode'     => 'append',
			'filename' => 'sub { Slim::Utils::Log::serverLogFile() }',
		},

		'scanner' => {
			'appender' => 'Log::Log4perl::Appender::File',
			'mode'     => 'append',
			'filename' => 'sub { Slim::Utils::Log::scannerLogFile() }',
		},

		'perfmon' => {
			'appender' => 'Log::Log4perl::Appender::File',
			'mode'     => 'append',
			'filename' => 'sub { Slim::Utils::Log::perfmonLogFile() }',
			'layout'   => 'raw'
		},
	);

	return $class->_fixupAppenders(\%defaultAppenders);
}

sub _fixupAppenders {
	my $class     = shift;
	my $appenders = shift;

	my $pattern   = '';
	my $rawpattern= '';

	if ($::LogTimestamp) {

		$pattern    = '[%d{HH:mm:ss.SSSS}] %M (%L) %m%n';
		$rawpattern = '[%d{HH:mm:ss.SSSS}] %m%n';

	} else {

		$pattern = '%M (%L) %m%n';
		$rawpattern = '%m%n';
	}

	my %baseProperties = (
		'utf8'   => 1,
		'layout' => 'PatternLayout',
	);

	# Make sure everyone has these properties
	my %mappedAppenders = ();

	while (my ($appender, $data) = each %{$appenders}) {

		my %properties = %baseProperties;

		if ($data->{'layout'} && $data->{'layout'} eq 'raw') {

			$properties{'layout.ConversionPattern'} = $rawpattern;
			delete $data->{'layout'};

		} else {

			$properties{'layout.ConversionPattern'} = $pattern;

		}

		while (my ($property, $value) = each %properties) {

			$mappedAppenders{"log4perl.appender.$appender.$property"} = $value;
		}

		while (my ($property, $value) = each %$data) {

			if ($property eq 'appender') {

				$mappedAppenders{"log4perl.appender.$appender"} = $value;

			} else {

				$mappedAppenders{"log4perl.appender.$appender.$property"} = $value;
			}
		}
	}

	return %mappedAppenders;
}

=head1 SEE ALSO

L<Log::Log4perl>

=cut

package Slim::Utils::Log::Trapper;

use strict;

# prevent pipelines crashing during open2 call
sub FILENO  { 2 }

sub TIEHANDLE {
	my $class = shift;
	bless [], $class;
}

sub PRINT {
	my $self = shift;

	$Log::Log4perl::caller_depth++;

	Slim::Utils::Log::logger('')->warn("Warning: ", @_);

	$Log::Log4perl::caller_depth--;
}

1;

__END__
