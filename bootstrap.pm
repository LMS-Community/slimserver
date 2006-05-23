package bootstrap;

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
my @defaultModules = qw(Time::HiRes DBD::SQLite DBI XML::Parser HTML::Parser Compress::Zlib);

sub loadModules {
	my $class   = shift;
	my @modules = @_;

	if (!scalar @modules) {
		@modules = @defaultModules;
	}

	# Perl 5.6.x doesn't ship with these modules..
	if ($] <= 5.007) {
		push @modules, qw(Storable Digest::MD5);
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

	my %libPaths = map { $_ => 1 } @SlimINC;

	# This works like 'use lib'
	# prepend our directories to @INC so we look there first.
	unshift @INC, @SlimINC;

	# Try and load the modules - some will fail if we don't include the
	# binaries for that version/architecture combo
	my @failed = tryModuleLoad(@modules);

	# Remove our paths so we can try loading the failed modules from the default system @INC
	@INC = grep { !$libPaths{$_} } @INC;

	my @reallyFailed = tryModuleLoad(@failed);

	if (scalar @reallyFailed) {

		printf("The following modules failed to load: %s\n\n", join(' ', @reallyFailed));

		print "To download and compile them, please run: $Bin/Bin/build-perl-modules.pl\n\n";
		print "Exiting..\n";

		exit;
	}

	# And we're done with the trying - put our CPAN path back on @INC.
	unshift @INC, @SlimINC;

	# $SIG{'CHLD'} = 'IGNORE';
	$SIG{'PIPE'} = 'IGNORE';
	$SIG{'TERM'} = \&sigterm;
	$SIG{'INT'}  = \&sigint;
	$SIG{'QUIT'} = \&sigquit;
}

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

# Given a list of modules, attempt to load them, otherwise pass back
# the failed list to the caller.
sub tryModuleLoad {
	my @modules = @_;

	my @failed  = ();

	for my $module (@modules) {

		eval "use $module";

		if ($@) {
			Symbol::delete_package($module);

			push @failed, $module;

			$module =~ s|::|/|g;
			$module .= '.pm';

			delete $INC{$module};
		}
	}

	return @failed;
}

sub sigint {
	$::d_server && Slim::Utils::Misc::msg("Got sigint.\n");

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

	sigint();
}

1;

__END__
