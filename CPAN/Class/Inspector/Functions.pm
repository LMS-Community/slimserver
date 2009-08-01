package Class::Inspector::Functions;

use 5.006;
use strict;
use warnings;
use Exporter         ();
use Class::Inspector ();

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION);
BEGIN {
	$VERSION = '1.24';
	@ISA     = 'Exporter';


	@EXPORT = qw(
		installed
		loaded

		filename
		functions
		methods

		subclasses
	);

	@EXPORT_OK = qw(
		resolved_filename
		loaded_filename

		function_refs
		function_exists
	);
		#children
		#recursive_children

	%EXPORT_TAGS = ( ALL => [ @EXPORT_OK, @EXPORT ] );

	foreach my $meth (@EXPORT, @EXPORT_OK) {
	    my $sub = Class::Inspector->can($meth);
	    no strict 'refs';
	    *{$meth} = sub {&$sub('Class::Inspector', @_)};
	}

}

1;

__END__

=pod

=head1 NAME

Class::Inspector::Functions - Get information about a class and its structure

=head1 SYNOPSIS

  use Class::Inspector::Functions;
  # Class::Inspector provides a non-polluting,
  # method based interface!
  
  # Is a class installed and/or loaded
  installed( 'Foo::Class' );
  loaded( 'Foo::Class' );
  
  # Filename related information
  filename( 'Foo::Class' );
  resolved_filename( 'Foo::Class' );
  
  # Get subroutine related information
  functions( 'Foo::Class' );
  function_refs( 'Foo::Class' );
  function_exists( 'Foo::Class', 'bar' );
  methods( 'Foo::Class', 'full', 'public' );
  
  # Find all loaded subclasses or something
  subclasses( 'Foo::Class' );

=head1 DESCRIPTION

Class::Inspector::Functions is a function based interface of
L<Class::Inspector>. For a thorough documentation of the available
functions, please check the manual for the main module.

=head2 Exports

The following functions are exported by default.

  installed
  loaded
  filename
  functions
  methods
  subclasses

The following functions are exported only by request.

  resolved_filename
  loaded_filename
  function_refs
  function_exists

All the functions may be imported using the C<:ALL> tag.

=head1 SUPPORT

Bugs should be reported via the CPAN bug tracker

L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Class-Inspector>

For other issues, or commercial enhancement or support, contact the author.

=head1 AUTHOR

Adam Kennedy E<lt>adamk@cpan.orgE<gt>

Steffen Mueller E<lt>smueller@cpan.orgE<gt>

=head1 SEE ALSO

L<http://ali.as/>, L<Class::Handle>

=head1 COPYRIGHT

Copyright 2002 - 2009 Adam Kennedy.

Class::Inspector::Functions copyright 2008 - 2009 Steffen Mueller.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
