package Class::Inspector;

=pod

=head1 NAME

Class::Inspector - Get information about a class and its structure

=head1 SYNOPSIS

  use Class::Inspector;
  
  # Is a class installed and/or loaded
  Class::Inspector->installed( 'Foo::Class' );
  Class::Inspector->loaded( 'Foo::Class' );
  
  # Filename related information
  Class::Inspector->filename( 'Foo::Class' );
  Class::Inspector->resolved_filename( 'Foo::Class' );
  
  # Get subroutine related information
  Class::Inspector->functions( 'Foo::Class' );
  Class::Inspector->function_refs( 'Foo::Class' );
  Class::Inspector->function_exists( 'Foo::Class', 'bar' );
  Class::Inspector->methods( 'Foo::Class', 'full', 'public' );
  
  # Find all loaded subclasses or something
  Class::Inspector->subclasses( 'Foo::Class' );

=head1 DESCRIPTION

Class::Inspector allows you to get information about a loaded class. Most or
all of this information can be found in other ways, but they aren't always
very friendly, and usually involve a relatively high level of Perl wizardry,
or strange and unusual looking code. Class::Inspector attempts to provide 
an easier, more friendly interface to this information.

=head1 METHODS

=cut

use 5.006;
# We don't want to use strict refs anywhere in this module, since we do a
# lot of things in here that aren't strict refs friendly.
use strict qw{vars subs};
use warnings;
use File::Spec ();

# Globals
use vars qw{$VERSION $RE_IDENTIFIER $RE_CLASS $UNIX};
BEGIN {
	$VERSION = '1.24';

	# If Unicode is available, enable it so that the
	# pattern matches below match unicode method names.
	# We can safely ignore any failure here.
	local $@;
	eval "require utf8; utf8->import";

	# Predefine some regexs
	$RE_IDENTIFIER = qr/\A[^\W\d]\w*\z/s;
	$RE_CLASS      = qr/\A[^\W\d]\w*(?:(?:\'|::)\w+)*\z/s;

	# Are we on something Unix-like?
	$UNIX  = !! ( $File::Spec::ISA[0] eq 'File::Spec::Unix'  );
}





#####################################################################
# Basic Methods

=pod

=head2 installed $class

The C<installed> static method tries to determine if a class is installed
on the machine, or at least available to Perl. It does this by wrapping
around C<resolved_filename>.

Returns true if installed/available, false if the class is not installed,
or C<undef> if the class name is invalid.

=cut

sub installed {
	my $class = shift;
	!! ($class->loaded_filename($_[0]) or $class->resolved_filename($_[0]));
}

=pod

=head2 loaded $class

The C<loaded> static method tries to determine if a class is loaded by
looking for symbol table entries.

This method it uses to determine this will work even if the class does not
have its own file, but is contained inside a single file with multiple
classes in it. Even in the case of some sort of run-time loading class
being used, these typically leave some trace in the symbol table, so an
L<Autoload> or L<Class::Autouse>-based class should correctly appear
loaded.

Returns true if the class is loaded, false if not, or C<undef> if the
class name is invalid.

=cut

sub loaded {
	my $class = shift;
	my $name  = $class->_class(shift) or return undef;
	$class->_loaded($name);
}

sub _loaded {
	my ($class, $name) = @_;

	# Handle by far the two most common cases
	# This is very fast and handles 99% of cases.
	return 1 if defined ${"${name}::VERSION"};
	return 1 if defined @{"${name}::ISA"};

	# Are there any symbol table entries other than other namespaces
	foreach ( keys %{"${name}::"} ) {
		next if substr($_, -2, 2) eq '::';
		return 1 if defined &{"${name}::$_"};
	}

	# No functions, and it doesn't have a version, and isn't anything.
	# As an absolute last resort, check for an entry in %INC
	my $filename = $class->_inc_filename($name);
	return 1 if defined $INC{$filename};

	'';
}

=pod

=head2 filename $class

For a given class, returns the base filename for the class. This will NOT
be a fully resolved filename, just the part of the filename BELOW the
C<@INC> entry.

  print Class->filename( 'Foo::Bar' );
  > Foo/Bar.pm

This filename will be returned with the right seperator for the local
platform, and should work on all platforms.

Returns the filename on success or C<undef> if the class name is invalid.

=cut

sub filename {
	my $class = shift;
	my $name  = $class->_class(shift) or return undef;
	File::Spec->catfile( split /(?:\'|::)/, $name ) . '.pm';
}

=pod

=head2 resolved_filename $class, @try_first

For a given class, the C<resolved_filename> static method returns the fully
resolved filename for a class. That is, the file that the class would be
loaded from.

This is not nescesarily the file that the class WAS loaded from, as the
value returned is determined each time it runs, and the C<@INC> include
path may change.

To get the actual file for a loaded class, see the C<loaded_filename>
method.

Returns the filename for the class, or C<undef> if the class name is
invalid.

=cut

sub resolved_filename {
	my $class     = shift;
	my $filename  = $class->_inc_filename(shift) or return undef;
	my @try_first = @_;

	# Look through the @INC path to find the file
	foreach ( @try_first, @INC ) {
		my $full = "$_/$filename";
		next unless -e $full;
		return $UNIX ? $full : $class->_inc_to_local($full);
	}

	# File not found
	'';
}

=pod

=head2 loaded_filename $class

For a given loaded class, the C<loaded_filename> static method determines
(via the C<%INC> hash) the name of the file that it was originally loaded
from.

Returns a resolved file path, or false if the class did not have it's own
file.

=cut

sub loaded_filename {
	my $class    = shift;
	my $filename = $class->_inc_filename(shift);
	$UNIX ? $INC{$filename} : $class->_inc_to_local($INC{$filename});
}





#####################################################################
# Sub Related Methods

=pod

=head2 functions $class

For a loaded class, the C<functions> static method returns a list of the
names of all the functions in the classes immediate namespace.

Note that this is not the METHODS of the class, just the functions.

Returns a reference to an array of the function names on success, or C<undef>
if the class name is invalid or the class is not loaded.

=cut

sub functions {
	my $class = shift;
	my $name  = $class->_class(shift) or return undef;
	return undef unless $class->loaded( $name );

	# Get all the CODE symbol table entries
	my @functions = sort grep { /$RE_IDENTIFIER/o }
		grep { defined &{"${name}::$_"} }
		keys %{"${name}::"};
	\@functions;
}

=pod

=head2 function_refs $class

For a loaded class, the C<function_refs> static method returns references to
all the functions in the classes immediate namespace.

Note that this is not the METHODS of the class, just the functions.

Returns a reference to an array of C<CODE> refs of the functions on
success, or C<undef> if the class is not loaded.

=cut

sub function_refs {
	my $class = shift;
	my $name  = $class->_class(shift) or return undef;
	return undef unless $class->loaded( $name );

	# Get all the CODE symbol table entries, but return
	# the actual CODE refs this time.
	my @functions = map { \&{"${name}::$_"} }
		sort grep { /$RE_IDENTIFIER/o }
		grep { defined &{"${name}::$_"} }
		keys %{"${name}::"};
	\@functions;
}

=pod

=head2 function_exists $class, $function

Given a class and function name the C<function_exists> static method will
check to see if the function exists in the class.

Note that this is as a function, not as a method. To see if a method
exists for a class, use the C<can> method for any class or object.

Returns true if the function exists, false if not, or C<undef> if the
class or function name are invalid, or the class is not loaded.

=cut

sub function_exists {
	my $class    = shift;
	my $name     = $class->_class( shift ) or return undef;
	my $function = shift or return undef;

	# Only works if the class is loaded
	return undef unless $class->loaded( $name );

	# Does the GLOB exist and its CODE part exist
	defined &{"${name}::$function"};
}

=pod

=head2 methods $class, @options

For a given class name, the C<methods> static method will returns ALL
the methods available to that class. This includes all methods available
from every class up the class' C<@ISA> tree.

Returns a reference to an array of the names of all the available methods
on success, or C<undef> if the class name is invalid or the class is not
loaded.

A number of options are available to the C<methods> method that will alter
the results returned. These should be listed after the class name, in any
order.

  # Only get public methods
  my $method = Class::Inspector->methods( 'My::Class', 'public' );

=over 4

=item public

The C<public> option will return only 'public' methods, as defined by the Perl
convention of prepending an underscore to any 'private' methods. The C<public> 
option will effectively remove any methods that start with an underscore.

=item private

The C<private> options will return only 'private' methods, as defined by the
Perl convention of prepending an underscore to an private methods. The
C<private> option will effectively remove an method that do not start with an
underscore.

B<Note: The C<public> and C<private> options are mutually exclusive>

=item full

C<methods> normally returns just the method name. Supplying the C<full> option
will cause the methods to be returned as the full names. That is, instead of
returning C<[ 'method1', 'method2', 'method3' ]>, you would instead get
C<[ 'Class::method1', 'AnotherClass::method2', 'Class::method3' ]>.

=item expanded

The C<expanded> option will cause a lot more information about method to be 
returned. Instead of just the method name, you will instead get an array
reference containing the method name as a single combined name, ala C<full>,
the seperate class and method, and a CODE ref to the actual function ( if
available ). Please note that the function reference is not guarenteed to 
be available. C<Class::Inspector> is intended at some later time, work 
with modules that have some some of common run-time loader in place ( e.g
C<Autoloader> or C<Class::Autouse> for example.

The response from C<methods( 'Class', 'expanded' )> would look something like
the following.

  [
    [ 'Class::method1',   'Class',   'method1', \&Class::method1   ],
    [ 'Another::method2', 'Another', 'method2', \&Another::method2 ],
    [ 'Foo::bar',         'Foo',     'bar',     \&Foo::bar         ],
  ]

=back

=cut

sub methods {
	my $class     = shift;
	my $name      = $class->_class( shift ) or return undef;
	my @arguments = map { lc $_ } @_;

	# Process the arguments to determine the options
	my %options = ();
	foreach ( @arguments ) {
		if ( $_ eq 'public' ) {
			# Only get public methods
			return undef if $options{private};
			$options{public} = 1;

		} elsif ( $_ eq 'private' ) {
			# Only get private methods
			return undef if $options{public};
			$options{private} = 1;

		} elsif ( $_ eq 'full' ) {
			# Return the full method name
			return undef if $options{expanded};
			$options{full} = 1;

		} elsif ( $_ eq 'expanded' ) {
			# Returns class, method and function ref
			return undef if $options{full};
			$options{expanded} = 1;

		} else {
			# Unknown or unsupported options
			return undef;
		}
	}

	# Only works if the class is loaded
	return undef unless $class->loaded( $name );

	# Get the super path ( not including UNIVERSAL )
	# Rather than using Class::ISA, we'll use an inlined version
	# that implements the same basic algorithm.
	my @path  = ();
	my @queue = ( $name );
	my %seen  = ( $name => 1 );
	while ( my $cl = shift @queue ) {
		push @path, $cl;
		unshift @queue, grep { ! $seen{$_}++ }
			map { s/^::/main::/; s/\'/::/g; $_ }
			( @{"${cl}::ISA"} );
	}

	# Find and merge the function names across the entire super path.
	# Sort alphabetically and return.
	my %methods = ();
	foreach my $namespace ( @path ) {
		my @functions = grep { ! $methods{$_} }
			grep { /$RE_IDENTIFIER/o }
			grep { defined &{"${namespace}::$_"} } 
			keys %{"${namespace}::"};
		foreach ( @functions ) {
			$methods{$_} = $namespace;
		}
	}

	# Filter to public or private methods if needed
	my @methodlist = sort keys %methods;
	@methodlist = grep { ! /^\_/ } @methodlist if $options{public};
	@methodlist = grep {   /^\_/ } @methodlist if $options{private};

	# Return in the correct format
	@methodlist = map { "$methods{$_}::$_" } @methodlist if $options{full};
	@methodlist = map { 
		[ "$methods{$_}::$_", $methods{$_}, $_, \&{"$methods{$_}::$_"} ] 
		} @methodlist if $options{expanded};

	\@methodlist;
}





#####################################################################
# Search Methods

=pod

=head2 subclasses $class

The C<subclasses> static method will search then entire namespace (and thus
B<all> currently loaded classes) to find all classes that are subclasses
of the class provided as a the parameter.

The actual test will be done by calling C<isa> on the class as a static
method. (i.e. C<My::Class-E<gt>isa($class)>.

Returns a reference to a list of the loaded classes that match the class
provided, or false is none match, or C<undef> if the class name provided
is invalid.

=cut

sub subclasses {
	my $class = shift;
	my $name  = $class->_class( shift ) or return undef;

	# Prepare the search queue
	my @found = ();
	my @queue = grep { $_ ne 'main' } $class->_subnames('');
	while ( @queue ) {
		my $c = shift(@queue); # c for class
		if ( $class->_loaded($c) ) {
			# At least one person has managed to misengineer
			# a situation in which ->isa could die, even if the
			# class is real. Trap these cases and just skip
			# over that (bizarre) class. That would at limit
			# problems with finding subclasses to only the
			# modules that have broken ->isa implementation.
			local $@;
			eval {
				if ( $c->isa($name) ) {
					# Add to the found list, but don't add the class itself
					push @found, $c unless $c eq $name;
				}
			};
		}

		# Add any child namespaces to the head of the queue.
		# This keeps the queue length shorted, and allows us
		# not to have to do another sort at the end.
		unshift @queue, map { "${c}::$_" } $class->_subnames($c);
	}

	@found ? \@found : '';
}

sub _subnames {
	my ($class, $name) = @_;
	return sort
		grep {
			substr($_, -2, 2, '') eq '::'
			and
			/$RE_IDENTIFIER/o
		}
		keys %{"${name}::"};
}





#####################################################################
# Children Related Methods

# These can go undocumented for now, until I decide if its best to
# just search the children in namespace only, or if I should do it via
# the file system.

# Find all the loaded classes below us
sub children {
	my $class = shift;
	my $name  = $class->_class(shift) or return ();

	# Find all the Foo:: elements in our symbol table
	no strict 'refs';
	map { "${name}::$_" } sort grep { s/::$// } keys %{"${name}::"};
}

# As above, but recursively
sub recursive_children {
	my $class    = shift;
	my $name     = $class->_class(shift) or return ();
	my @children = ( $name );

	# Do the search using a nicer, more memory efficient 
	# variant of actual recursion.
	my $i = 0;
	no strict 'refs';
	while ( my $namespace = $children[$i++] ) {
		push @children, map { "${namespace}::$_" }
			grep { ! /^::/ } # Ignore things like ::ISA::CACHE::
			grep { s/::$// }
			keys %{"${namespace}::"};
	}

	sort @children;
}





#####################################################################
# Private Methods

# Checks and expands ( if needed ) a class name
sub _class {
	my $class = shift;
	my $name  = shift or return '';

	# Handle main shorthand
	return 'main' if $name eq '::';
	$name =~ s/\A::/main::/;

	# Check the class name is valid
	$name =~ /$RE_CLASS/o ? $name : '';
}

# Create a INC-specific filename, which always uses '/'
# regardless of platform.
sub _inc_filename {
	my $class = shift;
	my $name  = $class->_class(shift) or return undef;
	join( '/', split /(?:\'|::)/, $name ) . '.pm';
}

# Convert INC-specific file name to local file name
sub _inc_to_local {
	# Shortcut in the Unix case
	return $_[1] if $UNIX;

	# On other places, we have to deal with an unusual path that might look
	# like C:/foo/bar.pm which doesn't fit ANY normal pattern.
	# Putting it through splitpath/dir and back again seems to normalise
	# it to a reasonable amount.
	my $class              = shift;
	my $inc_name           = shift or return undef;
	my ($vol, $dir, $file) = File::Spec->splitpath( $inc_name );
	$dir = File::Spec->catdir( File::Spec->splitdir( $dir || "" ) );
	File::Spec->catpath( $vol, $dir, $file || "" );
}

1;

=pod

=head1 SUPPORT

Bugs should be reported via the CPAN bug tracker

L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Class-Inspector>

For other issues, or commercial enhancement or support, contact the author.

=head1 AUTHOR

Adam Kennedy E<lt>adamk@cpan.orgE<gt>

=head1 SEE ALSO

L<http://ali.as/>, L<Class::Handle>

=head1 COPYRIGHT

Copyright 2002 - 2009 Adam Kennedy.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
