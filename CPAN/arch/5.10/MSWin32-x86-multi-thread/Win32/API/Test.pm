#
# Win32::API::Test - Test helper package for Win32::API
# 
# Version: 0.01
# Date: 23 Dec 2006
# Author: Cosimo Streppone <cosimo@cpan.org>
#
# $Id$
# 
package Win32::API::Test;

sub compiler_name () {
	use Config;
	my $cc = $Config{ccname};
	if($cc eq 'cl' || $cc eq 'cl.exe')
	{
		$cc = 'cl';
	}
	return($cc);
}

sub compiler_version () {
	use Config;
	my $ver = $Config{ccversion} || 0;
	if( $ver =~ /^(\d+\.\d+)/ )
	{
		$ver = 0 + $1; 
	}
	return($ver);
}

#
# Run the compiler and get version from there...
# User might be running a compiler different from
# that used to build perl.
# For example, Cosimo does. For testing, of course.
#
# ***
# *** IT DOES NOT WORK NOW.
# *** FOR REASONS I DON'T KNOW, CL.EXE OUTPUTS ITS
# *** VERSION STRING IN THE FIRST TWO LINES THAT
# *** I'M NOT ABLE TO CATCH...
# ***
#
sub compiler_version_from_shell () {
	my $cc = compiler_name();
	my $ver;
	# MSVC
	if($cc eq 'cl')
	{
		my @ver = `$cc`;
		my $ver = join('',@ver);
		print 'VER:'.$ver.':'."\n";
		if($ver =~ /Version (\d[\d\.]+)/ms )
		{
			$ver = $1;
		}
	}
	# GCC
	elsif($cc eq 'cc' || $cc eq 'gcc' || $cc eq 'winegcc' )
	{
		$ver = join('', `$cc --version`);
		if($ver =~ /gcc.*(\d[\d+]+)/ms )
		{
			$ver = $1;
		}
	}
	# Borland C
	elsif($cc eq 'bcc32' || $cc eq 'bcc')
	{
		$ver = join('', `$cc`);
		if($ver =~ /Borland C\+\+ (\d[\d\.]+)/ms )
		{
			$ver = $1;
		}
	}
	return($ver);
}

sub find_test_dll () {
	require File::Spec;
	my $dll_name = $_[0];
	my @paths = qw(.. ../t ../t/dll . ./dll ./t/dll);
	while(my $path = shift @paths)
	{
		$dll = File::Spec->catfile($path, $dll_name);
		return $dll if -s $dll;
	}
	return(undef);
}

1;

__END__


#######################################################################
# DOCUMENTATION
#

=head1 NAME

Win32::API::Test - Test helper package for Win32::API

=head1 SYNOPSIS

    my $test_dll = Win32::API::Test::find_test_dll('API_test.dll');

Check the t/*.t test scripts for more details.

=head1 DESCRIPTION

Simple package to hold Win32::API test suite helper functions.
No more, no less.

=head1 AUTHOR

Cosimo Streppone ( I<cosimo@cpan.org> )

=cut
