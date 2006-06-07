package Slim::bootstrap;

# $Id$
#
# SlimServer Copyright (c) 2001-2005 Sean Adams, Slim Devices Inc.
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
use Symbol;

# This begin statement contains some trickery to deal with modules
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
# we include with SlimServer, first checking our CPAN path, then if
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
my @default_required_modules = qw(Time::HiRes DBD::mysql DBI XML::Parser::Expat HTML::Parser Compress::Zlib Digest::SHA1 YAML::Syck);
my @default_optional_modules = qw(GD Locale::Hebrew);

my $d_startup                = (grep { /d_startup/ } @ARGV) ? 1 : 0;

my $sigINTcalled             = 0;

sub loadModules {
	my ($class, $required_modules, $optional_modules) = @_;

	if (!ref($required_modules) || !scalar @$required_modules) {
		$required_modules = \@default_required_modules;
	}

	# It's ok to pass in an empty array ref to not load any optional modules.
	if (!ref($optional_modules) || (!scalar @$optional_modules && !ref($optional_modules))) {
		$optional_modules = \@default_optional_modules;
	}

	if ($] <= 5.007) {
		push @$required_modules, qw(Storable Digest::MD5);
	}

	my @SlimINC = ();

	if (Slim::Utils::OSDetect::isDebian()) {

		@SlimINC = Slim::Utils::OSDetect::dirsFor('lib');

	} else {

		@SlimINC = (
			catdir($Bin,'CPAN','arch',(join ".", map {ord} split //, $^V), $Config::Config{'archname'}),
			catdir($Bin,'CPAN','arch',(join ".", map {ord} split //, $^V), $Config::Config{'archname'}, 'auto'),
			catdir($Bin,'CPAN','arch',(join ".", map {ord} (split //, $^V)[0,1]), $Config::Config{'archname'}),
			catdir($Bin,'CPAN','arch',(join ".", map {ord} (split //, $^V)[0,1]), $Config::Config{'archname'}, 'auto'),
			catdir($Bin,'CPAN','arch',$Config::Config{'archname'}),
			catdir($Bin,'lib'), 
			catdir($Bin,'CPAN'), 
		);
	}

	$d_startup && printf("Got \@INC containing:\n%s\n\n", join("\n", @INC));

	# This works like 'use lib'
	# prepend our directories to @INC so we look there first.
	unshift @INC, @SlimINC;

	$d_startup && printf("Extended \@INC to contain:\n%s\n\n", join("\n", @INC));

	# Try and load the modules - some will fail if we don't include the
	# binaries for that version/architecture combo
	my @required_failed = tryModuleLoad(@$required_modules);
	my @optional_failed = tryModuleLoad(@$optional_modules);

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

	my @required_really_failed = tryModuleLoad(@required_failed);
	my @optional_really_failed = tryModuleLoad(@optional_failed);

	if ($d_startup) {
		print "The following modules are loaded after the second attempt:\n";
		print map { "\t$_ => $INC{$_}\n" } keys %INC;
		print "\n";
	}

	if (scalar @optional_really_failed && $d_startup) {
		printf("The following optional modules failed to load: [%s] after their second try.\n\n", join(', ', @optional_really_failed));
	}

	if (scalar @required_really_failed) {

		printf("The following modules failed to load: %s\n\n", join(' ', @required_really_failed));

		print "To download and compile them, please run: $Bin/Bin/build-perl-modules.pl\n\n";
		print "Exiting..\n";

		exit;
	}

	# And we're done with the trying - put our CPAN path back on @INC.
	unshift @INC, @SlimINC;

	$SIG{'CHLD'} = 'DEFAULT';
	$SIG{'PIPE'} = 'IGNORE';
	$SIG{'TERM'} = \&sigterm;
	$SIG{'INT'}  = \&sigint;
	$SIG{'QUIT'} = \&sigquit;
}

sub tryModuleLoad {
	my @modules = @_;

	my @failed  = ();

	my (%oldINC, @newModules);

	for my $module (@modules) {

		%oldINC = %INC;

		# Don't spit out any redefined warnings
		local $^W = 0;

		eval "use $module";

		if ($@) {
			push @failed, $module;

			@newModules = grep { !$oldINC{$_} } keys %INC;

			for my $newModule (@newModules) {

				# Don't bother removing/reloading
				# these, as they're part of core Perl.
				if ($newModule =~ /^(?:DynaLoader|Carp|overload|IO|Fcntl|Socket|FileHandle)/) {
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

	return @failed;
}

sub sigint {
	$::d_server && Slim::Utils::Misc::msg("Got sigint.\n");

	$sigINTcalled = 1;

	main::cleanup();

	exit();
}

sub sigterm {
	$::d_server && Slim::Utils::Misc::msg("Got sigterm.\n");

	main::cleanup();

	exit();
}

sub ignoresigquit {
	$::d_server && Slim::Utils::Misc::msg("Ignoring sigquit.\n");
}

sub sigquit {
	$::d_server && Slim::Utils::Misc::msg("Got sigquit.\n");

	main::cleanup();

	exit();
}

sub END {

	$::d_server && Slim::Utils::Misc::msg("Got to the END.\n");

	if (!$sigINTcalled && !$main::daemon) {
		sigint();
	}
}

1;

__END__
