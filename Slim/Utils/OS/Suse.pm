package Slim::Utils::OS::Suse;

use strict;
use base qw(Slim::Utils::OS::RedHat);

sub initDetails {
	my $class = shift;

	$class->{osDetails} = $class->SUPER::initDetails();

	$class->{osDetails}->{osName} = 'SUSE';
	$class->{osDetails}->{isSuse} = 1 if $0 =~ m{^/usr/libexec/squeezecenter};
	
	delete $class->{osDetails}->{isRedHat} if defined $class->{osDetails}->{isRedHat};

	return $class->{osDetails};
}

=head2 dirsFor( $dir )

Return OS Specific directories.

Argument $dir is a string to indicate which of the SqueezeCenter directories we
need information for.

=cut

sub dirsFor {
	my ($class, $dir) = @_;

	my @dirs = ();
	
	if ($class->{osDetails}->{isSuse} && $dir eq 'libpath') {

		push @dirs, "/usr/share/squeezecenter";

	} elsif ($class->{osDetails}->{isSuse} && $dir eq 'mysql-language') {

		push @dirs, "/usr/share/mysql/english";

	} else {

		@dirs = $class->SUPER::dirsFor($dir);
	}

	return wantarray() ? @dirs : $dirs[0];
}

1;