package PerlLanguageServerBootstrap;

# Bootstrap for the Perl Language Server and VS Code debug adapter.
#
# For Language Server (static analysis / syntax checking):
#   Replicates the two-pass module loading strategy from Slim::bootstrap::loadModules():
#   1. Prepend CPAN (incl. arch-specific) paths to @INC
#   2. Try loading known XS modules from bundled CPAN
#   3. If any fail (XS version mismatch), remove CPAN from @INC, retry from system Perl
#   4. Put CPAN paths back so pure-Perl modules (File::Slurp, etc.) remain reachable
#
# For debug adapter (slimserver.pl under -d):
#   Slim::bootstrap::loadModules() handles the full two-pass @INC setup itself.
#   We only define constants here. CPAN must NOT be in PERL5LIB for debug launches,
#   otherwise PERL5DB's DebuggerInterface finds CPAN/JSON/XS.pm (v2.34) early but
#   XSLoader picks up the system .so (v2.3) first — version mismatch kills the load,
#   and Slim::bootstrap can never recover it. Without CPAN in PERL5LIB, DebuggerInterface
#   falls back to JSON::PP harmlessly, and Slim::bootstrap's unshift puts arch paths
#   first in @INC so .pm and .so versions match.

use strict;
use Config;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Spec::Functions qw(catdir rel2abs);
use Symbol;

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

# XS modules known to ship in CPAN/arch — same list as Slim::bootstrap's
# @default_required_modules, plus IO::AIO which the Language Server pulls via Coro::AIO.
my @xs_modules = qw(version Time::HiRes DBI EV XML::Parser::Expat HTML::Parser JSON::XS Digest::SHA1 YAML::XS Sub::Name IO::AIO);

# Guard against double-import (e.g. -MPerlLanguageServerBootstrap on command line AND in PERL5OPT).
my $imported = 0;

# Normalize arch name and build @SlimINC — same logic as Slim::bootstrap::loadModules().
# Returns the list of paths (not all may exist on disk).
sub _buildSlimINC {
	my ($repoRoot) = @_;

	my $arch = $Config::Config{'archname'};
	$arch =~ s/^i[3456]86-/i386-/;
	$arch =~ s/gnu-//;
	my $is64bitint = $arch =~ /64int/;
	if ($arch =~ /^aarch64.*linux/) {
		$arch = 'aarch64-linux-thread-multi';
	}
	elsif ($arch =~ /^arm.*linux/) {
		$arch = $arch =~ /gnueabihf/
			? 'arm-linux-gnueabihf-thread-multi'
			: 'arm-linux-gnueabi-thread-multi';
		$arch .= '-64int' if $is64bitint;
	}
	if ($arch =~ /^(?:ppc|powerpc).*linux/) {
		$arch = 'powerpc-linux-thread-multi';
		$arch .= '-64int' if $is64bitint;
	}

	my $perlmajorversion = $Config{'version'};
	$perlmajorversion =~ s/\.\d+$//;

	return (
		catdir($repoRoot, 'CPAN', 'arch', $perlmajorversion, $arch),
		catdir($repoRoot, 'CPAN', 'arch', $perlmajorversion, $arch, 'auto'),
		catdir($repoRoot, 'CPAN', 'arch', $Config{'version'}, $Config::Config{'archname'}),
		catdir($repoRoot, 'CPAN', 'arch', $Config{'version'}, $Config::Config{'archname'}, 'auto'),
		catdir($repoRoot, 'CPAN', 'arch', $perlmajorversion, $Config::Config{'archname'}),
		catdir($repoRoot, 'CPAN', 'arch', $perlmajorversion, $Config::Config{'archname'}, 'auto'),
		catdir($repoRoot, 'CPAN', 'arch', $Config::Config{'archname'}),
		catdir($repoRoot, 'CPAN', 'arch', $perlmajorversion),
		catdir($repoRoot, 'lib'),
		catdir($repoRoot, 'CPAN'),
		$repoRoot,
	);
}

sub import {
	return if $imported;
	$imported = 1;

	no strict 'refs';

	my $bootstrapDir = dirname(__FILE__);
	my $repoRoot = abs_path(rel2abs(catdir($bootstrapDir, '..'))) || rel2abs(catdir($bootstrapDir, '..'));
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

	if (!$isSlimserverRun) {
		# Language Server / static analysis: full two-pass XS loading.
		my @SlimINC = _buildSlimINC($repoRoot);

		# Remove any bare CPAN path that crept in via -I flags (perlInc) or PERL5LIB
		# BEFORE we do the controlled two-pass load.
		my $cpanDir = catdir($repoRoot, 'CPAN');
		@INC = grep { $_ ne $cpanDir } @INC;

		# Prepend our paths (like 'use lib')
		unshift @INC, @SlimINC;

		# --- Two-pass XS module loading (Slim::bootstrap strategy) ---
		# Pass 1: try loading from bundled CPAN (arch-specific XS binaries)
		my @failed = _tryModuleLoad(@xs_modules);

		if (@failed) {
			# Pass 2: remove our CPAN paths from @INC so we try system Perl only
			splice(@INC, 0, scalar @SlimINC);
			_tryModuleLoad(@failed);
			# Put CPAN paths back so pure-Perl modules remain reachable
			unshift @INC, @SlimINC;
		}

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

		my $cacheDir = catdir($repoRoot, 'Cache');
		$main::cachedir = $cacheDir unless defined $main::cachedir;
		$main::tmpdir = catdir($cacheDir, 'tmp') unless defined $main::tmpdir;

		eval {
			require Slim::Utils::OSDetect;
			Slim::Utils::OSDetect::init();
		};
	}
}

# Two-pass module loader — adapted from Slim::bootstrap::tryModuleLoad().
# Tries to 'use' each module; on failure, cleans up the symbol table and %INC
# so the module can be retried from a different @INC in the next pass.
sub _tryModuleLoad {
	my @modules = @_;
	my @failed;

	for my $module (@modules) {
		next unless $module;

		my %oldINC = %INC;

		local $^W = 0;    # suppress redefined warnings
		eval "use $module ()";

		if ($@) {
			push @failed, $module;

			# Clean up partially-loaded symbols (same logic as Slim::bootstrap).
			# Note: IO(?!/AIO) skips core IO modules but NOT IO::AIO so it can be
			# retried from system Perl in pass 2.
			for my $newModule (grep { !$oldINC{$_} } keys %INC) {
				next if $newModule =~ /^(?:AutoLoader|DynaLoader|XSLoader|Carp|overload|IO(?!\/AIO)|Fcntl|Socket|FileHandle|SelectSaver)/;

				my $symbol = $newModule;
				$symbol =~ s|/|::|g;
				$symbol =~ s|\.pm$||;

				if (eval { Symbol::delete_package($symbol) }) {
					delete $INC{$newModule};
				}
			}
		}
	}

	return @failed;
}

1;
