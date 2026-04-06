package PerlLanguageServerBootstrap;

use strict;
use Config;
use File::Basename qw(dirname);
use File::Spec::Functions qw(catdir rel2abs);

# VS Code Debug Adapter sends SIGINT to pause the debuggee. Slim::bootstrap installs
# custom INT/TERM/QUIT handlers inside loadModules(), which is called from slimserver.pl's
# BEGIN block. This INIT block runs AFTER all BEGIN blocks, so it safely overrides
# those handlers before the main program starts. Use DB::catch for INT (if available),
# otherwise Perl debugger pause/continue can get stuck.
INIT {
	if (($ENV{LMS_VSCODE_DEBUG} || '') eq '1') {
		if (defined &DB::catch) {
			$SIG{'INT'} = \&DB::catch;
		}
		else {
			$SIG{'INT'} = 'DEFAULT';
		}
		$SIG{'TERM'} = 'DEFAULT';
		$SIG{'QUIT'} = 'DEFAULT';
	}
}

sub import {
	no strict 'refs';

	my $bootstrapDir = dirname(__FILE__);
	my $repoRoot = rel2abs(catdir($bootstrapDir, '..'));
	my $isSlimserverRun = (($0 || '') =~ m{(?:^|[\\/])slimserver\.pl$}i) ? 1 : 0;
	my %constants = (
		SCANNER       => 0,
		RESIZER       => 0,
		ISWINDOWS     => 0,
		ISMAC         => 0,
		TRANSCODING   => 1,
		PERFMON       => 0,
		DEBUGLOG      => 1,
		INFOLOG       => 1,
		STATISTICS    => 1,
		SB1SLIMP3SYNC => 1,
		WEBUI         => 1,
		NOMYSB        => 1,
		LOCALFILE     => 0,
		NOBROWSECACHE => 0,
		SLIM_SERVICE  => 0,
		NOUPNP        => 0,
		ISACTIVEPERL  => 0,
	);

	# Needed by some modules during static analysis, but conflicts with slimserver.pl runtime sub declaration.
	$constants{HAS_AIO} = 0 if !$isSlimserverRun;

	for my $name (keys %constants) {
		*{"main::$name"} = sub () { $constants{$name} } unless defined &{"main::$name"};
	}

	$main::VERSION ||= '9.2.0';
	@main::argv = @ARGV unless @main::argv;

	# Perl::LanguageServer expects AnyEvent::CondVar->new, but LMS ships AnyEvent 5.x.
	eval {
		require AnyEvent;
		if (!AnyEvent::CondVar->can('new')) {
			no warnings 'redefine';
			*AnyEvent::CondVar::new = sub {
				shift;
				return AnyEvent->condvar(@_);
			};
		}
	};

	# Some modules (eg. Slim::Utils::Unicode) require OS detection during compile time.
	# Avoid this side effect for the actual server runtime/debug launch.
	if (!$isSlimserverRun) {
		my $perlmajorversion = $Config{'version'};
		$perlmajorversion =~ s/\.\d+$//;

		my $arch = $Config::Config{'archname'};
		my @lmsInc = (
			catdir($repoRoot, 'CPAN', 'arch', $perlmajorversion, $arch),
			catdir($repoRoot, 'CPAN', 'arch', $perlmajorversion, $arch, 'auto'),
			catdir($repoRoot, 'CPAN', 'arch', $perlmajorversion),
			catdir($repoRoot, 'CPAN'),
			catdir($repoRoot, 'lib'),
			$repoRoot,
		);

		my $repoCpanArch = quotemeta(catdir($repoRoot, 'CPAN', 'arch'));
		my $currentArchVersion = quotemeta(catdir($repoRoot, 'CPAN', 'arch', $perlmajorversion));
		@INC = grep {
			!(m{^$repoCpanArch/} && !m{^$currentArchVersion(?:/|$)})
		} @INC;

		for my $path (reverse @lmsInc) {
			next if !-d $path;
			unshift @INC, $path unless grep { $_ eq $path } @INC;
		}

		my $cacheDir = catdir($repoRoot, 'Cache');
		$main::cachedir = $cacheDir unless defined $main::cachedir;
		$main::tmpdir = catdir($cacheDir, 'tmp') unless defined $main::tmpdir;

		eval {
			require Slim::Utils::OSDetect;
			Slim::Utils::OSDetect::init();
		};
	}
}

1;
