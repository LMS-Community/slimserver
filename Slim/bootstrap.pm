package Slim::bootstrap;

# $Id$
#
# SqueezeCenter Copyright (c) 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, version 2

# This code originally lived in slimserver.pl - but with other programs
# needing to use the same @INC, was broken out into a separate package.
#
# 2005-11-09 - dsully

use strict;
use warnings;

use Config;
use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);
use POSIX ":sys_wait_h";
use Symbol;

use Slim::Utils::OSDetect;

# loadModules contains some trickery to deal with modules
# that need to load XS code. Previously, we would check in a module
# under CPAN/arch/$VERSION/auto/... including it's binary parts and
# the pure perl parts. This got to be messy and unwieldly, as we have
# many copies of DBI.pm (and associated modules) in each version and
# arch directory. The new world has only the binary modules in the
# arch/$VERSION/auto directories - and single copies of the
# corresponding .pm files at the top CPAN/ level.
#
# This causes a problem in that when we 'use' one of these modules,
# the CPAN/Foo.pm would be loaded, and then Dynaloader would be
# called, which loads the architecture specifc parts - But Dynaloader
# ignores @INC, and tries to pull from the system install of perl. If
# that module exists in the system perl, but the $VERSION's aren't the
# same, Dynaloader fails.
#
# The workaround is to munge @INC and eval'ing the known modules that
# we include with SqueezeCenter, first checking our CPAN path, then if
# there are any modules that couldn't be loaded, splicing CPAN/ out,
# and attempting to load the system version of the module. When we are
# done, put our CPAN/ path back in @INC.
#
# We use Symbol's (included with 5.6+) delete_package() function &
# removing the "require" style name from %INC and attempt to load
# these modules two different ways. Only the failed modules are tried again.
#
# Hopefully the actual implmentation below is fairly straightforward
# once the problem domain is understood.

# Here's what we want to try and load. This will need to be updated
# when a new XS based module is added to our CPAN tree.
my @default_required_modules = qw(Time::HiRes DBD::mysql DBI XML::Parser::Expat HTML::Parser JSON::XS Compress::Zlib Digest::SHA1 YAML::Syck);
my @default_optional_modules = qw(GD Locale::Hebrew);

my $d_startup                = (grep { /d_startup/ } @ARGV) ? 1 : 0;

my $sigINTcalled             = 0;

my $sigCHLD                  = {};

sub loadModules {
	my ($class, $required_modules, $optional_modules, $libPath) = @_;

	if (!ref($required_modules) || !scalar @$required_modules) {
		$required_modules = \@default_required_modules;
	}

	# It's ok to pass in an empty array ref to not load any optional modules.
	if (!ref($optional_modules) || (!scalar @$optional_modules && !ref($optional_modules))) {
		$optional_modules = \@default_optional_modules;
	}

	# If the caller passed in a libPath, use that. Otherwise, default to $Bin
	if (!$libPath) {
		$libPath = $Bin;
	}

	# NB: Fedora Core 5 (and other SELinux work-arounds)
	# Change the security context of the .so files we distribute.
	# Apparently this is doable by a non-root user. So much for secure.
	if (-d '/etc/selinux' && -x '/usr/bin/chcon') {

		my $archDir = catdir($libPath, 'CPAN', 'arch');

		$d_startup && printf("Found SELinux - setting security context to: texrel_shlib_t for *.so files.\n");

		#system("/usr/bin/chcon -R -t texrel_shlib_t $archDir");
	}

	if ($] <= 5.007) {
		push @$required_modules, qw(Storable Digest::MD5);
	}

	my @SlimINC = ();

	if (Slim::Utils::OSDetect::isDebian() || Slim::Utils::OSDetect::isRHELorFC()) {

		@SlimINC = Slim::Utils::OSDetect::dirsFor('lib');

	} else {

		# NB: The user may be on a platform who's perl reports a
		# different x86 version than we've supplied - but it may work
		# anyways.
		my $arch = $Config::Config{'archname'};
		   $arch =~ s/^i[3456]86-/i386-/;
		   $arch =~ s/gnu-//;

		@SlimINC = (
			catdir($libPath,'CPAN','arch',(join ".", map {ord} (split //, $^V)[0,1]), $arch),
			catdir($libPath,'CPAN','arch',(join ".", map {ord} (split //, $^V)[0,1]), $arch, 'auto'),
			catdir($libPath,'CPAN','arch',(join ".", map {ord} split //, $^V), $Config::Config{'archname'}),
			catdir($libPath,'CPAN','arch',(join ".", map {ord} split //, $^V), $Config::Config{'archname'}, 'auto'),
			catdir($libPath,'CPAN','arch',(join ".", map {ord} (split //, $^V)[0,1]), $Config::Config{'archname'}),
			catdir($libPath,'CPAN','arch',(join ".", map {ord} (split //, $^V)[0,1]), $Config::Config{'archname'}, 'auto'),
			catdir($libPath,'CPAN','arch',$Config::Config{'archname'}),
			catdir($libPath,'lib'), 
			catdir($libPath,'CPAN'), 
			$libPath,
		);
	}

	$d_startup && printf("Got \@INC containing:\n%s\n\n", join("\n", @INC));

	# This works like 'use lib'
	# prepend our directories to @INC so we look there first.
	unshift @INC, @SlimINC;

	$d_startup && printf("Extended \@INC to contain:\n%s\n\n", join("\n", @INC));

	# Try and load the modules - some will fail if we don't include the
	# binaries for that version/architecture combo
	my @required_failed = tryModuleLoad(@$required_modules, 'nowarn');
	my @optional_failed = tryModuleLoad(@$optional_modules, 'nowarn');

	if ($d_startup) {
		print "The following modules are loaded after the first attempt:\n";
		print map { "\t$_ => $INC{$_}\n" } keys %INC;
		print "\n";
	}

	if (scalar @optional_failed && $d_startup) {
		printf("The following optional modules failed to load on the first attempt: [%s] - will try again\n\n", join(', ', @optional_failed));
	}

	if (scalar @required_failed && $d_startup) {
		printf("The following modules failed to load on the first attempt: [%s] - will try again.\n\n", join(', ', @required_failed));
	}

	# Remove our paths so we can try loading the failed modules from the default system @INC
	splice(@INC, 0, scalar @SlimINC);

	my @required_really_failed = tryModuleLoad(@required_failed, 'nowarn');
	my @optional_really_failed = tryModuleLoad(@optional_failed, 'nowarn');

	if ($d_startup) {
		print "The following modules are loaded after the second attempt:\n";
		print map { "\t$_ => $INC{$_}\n" } keys %INC;
		print "\n";
	}

	if (scalar @optional_really_failed && $d_startup) {
		printf("The following optional modules failed to load: [%s] after their second try.\n\n", join(', ', @optional_really_failed));
	}

	if (scalar @required_really_failed) {

		my $failed = join(' ', @required_really_failed);

		print "The following modules failed to load: $failed\n\n";

		print "To download and compile them, please run: $libPath/Bin/build-perl-modules.pl $failed\n\n";
		print "Exiting..\n";

		exit;
	}

	# And we're done with the trying - put our CPAN path back on @INC.
	unshift @INC, @SlimINC;
	
	# Check that all of our CPAN modules are the correct minimum version
	my $failed = check_valid_versions();
	if ( scalar keys %{$failed} ) {
	
		print "The following CPAN modules were found but are too old to work with SqueezeCenter:\n";
		
		for my $module ( sort keys %{$failed} ) {
			print "  $module (loaded " . $failed->{$module}->{loaded} . ", need " . $failed->{$module}->{need} . ")\n";
		}
		
		print "\n";		
		print "To fix this problem you have several options:\n";
		print "1. Install the latest version of the module(s) using CPAN: sudo cpan Some::Module\n";
		print "2. Update the module's package using apt-get, yum, etc.\n";
		print "3. Run the .tar.gz version of SqueezeCenter which includes all required CPAN modules.\n";
		print "\n";
		
		exit;
	}
	
	sub REAPER {
		my $kid;
		
		# Reap all dead children
		while (($kid = waitpid(-1, WNOHANG)) > 0) {
			if ( exists $sigCHLD->{$kid} ) {
				
				my $cb = $sigCHLD->{$kid}->{cb};
				my $pt = $sigCHLD->{$kid}->{pt} || [];
				$cb->( @{$pt} );
				
				delete $sigCHLD->{$kid};
			}
		}
		
		$SIG{'CHLD'} = \&REAPER;
	}
	$SIG{'CHLD'} = \&REAPER;
	
	$SIG{'PIPE'} = 'IGNORE';
	$SIG{'TERM'} = \&sigterm;
	$SIG{'INT'}  = \&sigint;
	$SIG{'QUIT'} = \&sigquit;
}

sub sigCHLDCallback {
	my ( $pid, $cb, @args ) = @_;
	
	$sigCHLD->{$pid} = {
		cb => $cb,
		pt => \@args,
	};
}

sub tryModuleLoad {
	my @modules = @_;

	# if called from loadModules don't warn for modules which fail to load
	my $warnOnFail = (@modules && $modules[$#modules] eq 'nowarn' && pop @modules) ? 0 : 1;

	my @failed  = ();

	my (%oldINC, @newModules);

	for my $module (@modules) {

		%oldINC = %INC;

		# Don't spit out any redefined warnings
		local $^W = 0;

		eval "use $module ()";

		# NB: YAML::Syck has a local $@; in it's BEGIN, so if XSLoader
		# or Dynaloader fails, the module still appears to load. Try
		# to run a function to see if it's really been loaded.
		if ($module eq 'YAML::Syck') {

			eval { no warnings; YAML::Syck::Dump({}) };
		}

		if ($@) {

			if ($d_startup || $warnOnFail) {

				print STDERR "Module [$module] failed to load:\n$@\n";
			}

			# NB: More FC5 / SELinux - in case the above chcon doesn't work.
			if ($@ =~ /cannot restore segment prot after reloc/) {

				print STDERR "** SqueezeCenter Error:\n";
				print STDERR "** SELinux settings prevented SqueezeCenter from starting.\n";
				print STDERR "** See http://wiki.slimdevices.com/index.cgi?RPM for more information.\n\n";
				exit;
			}

			push @failed, $module;

			@newModules = grep { !$oldINC{$_} } keys %INC;

			for my $newModule (@newModules) {

				# Don't bother removing/reloading
				# these, as they're part of core Perl.
				if ($newModule =~ /^(?:AutoLoader|DynaLoader|XSLoader|Carp|overload|IO|Fcntl|Socket|FileHandle|SelectSaver)/) {
					next;
				}

				my $newModuleSymbol = $newModule;

				$newModuleSymbol =~ s|/|::|g;
				$newModuleSymbol =~ s|\.pm$||;

				# This relies on delete_package returning a true value if it succeeded.
				my $removed = eval {
					Symbol::delete_package($newModuleSymbol);
				};

				if ($removed) {
					$d_startup && print "Removing [$newModuleSymbol] from the symbol table - load failed.\n";
					delete $INC{$newModule};
				}
			}

		} else {

			$d_startup && print "Loaded module: [$module] ok!\n";
		}
	}

	if (wantarray) {
		return @failed;
	} else {
		return scalar @failed ? 1 : 0;
	}
}

sub check_valid_versions {
	my $modules;
	my $failed = {};
	
	my ($dir) = Slim::Utils::OSDetect::dirsFor('types');
	
	open my $fh, '<', catfile( $dir, 'modules.conf' ) or die 'modules.conf not found';
	do { local $/ = undef; $modules = <$fh> };
	close $fh;

	for my $line ( split /\n/, $modules ) {
		next unless $line =~ /^\w+/;
		chomp $line;
		
		my ($mod, $ver) = split /\s+/, $line;
		
		# Could parse the module file here using code from Module::Build,
		# but we will be loading these later anyway, so this is easier.
		eval "use $mod";
		if ( !$@ ) {
			eval { $mod->VERSION( $ver || 0 ); 1; };
		}
		if ( $@ ) {
			$failed->{$mod} = {
				loaded => $mod->VERSION || '<not found>',
				need   => $ver,
			};
		}
	}		
	
	return $failed;
}

sub sigint {
	Slim::Utils::Log::logger('server')->info('Got sigint');

	$sigINTcalled = 1;

	if ( !$Slim::Web::HTTP::inChild ) {
		main::cleanup() if defined &main::cleanup;
	}

	exit();
}

sub sigterm {
	Slim::Utils::Log::logger('server')->info('Got sigterm');

	main::cleanup() if defined &main::cleanup;

	exit();
}

sub ignoresigquit {

	Slim::Utils::Log::logger('server')->info('Ignoring sigquit');
}

sub sigquit {
	Slim::Utils::Log::logger('server')->info('Got sigquit');

	main::cleanup() if defined &main::cleanup;

	exit();
}

# Aliased to END in slimserver & scanner, as Log::Log4perl installs an END
# handler, which needs to run last.
sub theEND {

	Slim::Utils::Log::logger('server')->info('Got to the END');

	if (!$sigINTcalled && !$main::daemon) {
		sigint();
	}
}

1;

__END__
