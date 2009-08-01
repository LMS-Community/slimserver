package Devel::Leak::Object;

use 5.005;
# We abuse refs a LOT
use strict qw{ vars subs };
use Carp         ();
use Scalar::Util ();

use vars qw{ $VERSION @ISA @EXPORT_OK };
use vars qw{ %OBJECT_COUNT %TRACKED %DESTROY_ORIGINAL %DESTROY_STUBBED %DESTROY_NEXT };
BEGIN {
	$VERSION     = '0.92';

    # Set up exports
	require Exporter;
	@ISA         = qw(Exporter);
	@EXPORT_OK   = qw(track bless status);

    # Set up state storage (primary for clarity)
    %OBJECT_COUNT     = ();
    %TRACKED          = ();
    %DESTROY_ORIGINAL = ();
    %DESTROY_STUBBED  = ();
}

sub import {
    my $class  = shift;
    my @import = ();
    while ( @_ ) {
        my $function = shift;
        unless ( $function =~ /^GLOBAL_(.*)$/ ) {
            push @import, $function;
            next;
        }
        my $global = $1;
        *{'CORE::GLOBAL::' . $global} = \&{$global};
    }
    return $class->SUPER::import(@import);
}

sub bless {
    my $reference = shift;
    my $class     = @_ ? shift : scalar caller;
    my $object    = CORE::bless($reference, $class);
    Devel::Leak::Object::track($object);
    return $object;
};

sub track {
	my $object = shift;
    my $class  = Scalar::Util::blessed($object);
    unless ( defined $class ) {
        Carp::carp("Devel::Leak::Object::track was passed a non-object");
    }
    my $address = Scalar::Util::refaddr($object);
    if ( $TRACKED{$address} ) {
        if ( $class eq $TRACKED{$address} ) {
            # Reblessing into the same class, ignore
            return $OBJECT_COUNT{$class};
        } else {
            # Reblessing into a different class
            $OBJECT_COUNT{$TRACKED{$address}}--;
        }
    }

    # Set or over-write the class name for the tracked object
    $TRACKED{$address} = $class;

    # If needed, initialise the new class
    unless ( $DESTROY_STUBBED{$class} ) {
        if ( exists ${$class.'::'}{DESTROY} and *{$class.'::DESTROY'}{CODE} ) {
            # Stash the pre-existing DESTROY function
            $DESTROY_ORIGINAL{$class} = \&{$class . '::DESTROY'};
        }
        $DESTROY_STUBBED{$class} = 1;
        eval <<"END_DESTROY";
package $class;\
no warnings;
sub DESTROY {
    my \$class   = Scalar::Util::blessed(\$_[0]);
    my \$address = Scalar::Util::refaddr(\$_[0]);
    unless ( defined \$class ) {
        die "Unexpected error: First param to DESTROY is no an object";
    }

    # Don't do anything unless tracking for the specific object is set
    my \$original = \$Devel::Leak::Object::TRACKED{\$address};
    if ( \$original ) {
        ### TODO - We COULD add a check that $class eq
        #          \$Devel::Leak::Object::TRACKED{\$address}
        #          and then not decrement unless it is the same.
        #          However, in practice it should ALWAYS be the same if
        #          we already have \$Devel::Leak::Object::TRACKED{\$address}
        #          true still, and if for some reason this is wrong, we get
        #          a false positive in the leak counting.
        #          This additional check may be able to be added at a later
        #          date if it turns out to be needed.
        #          if ( \$class eq \$Devel::Leak::Object::TRACKED{\$address} ) { ... }
        if ( \$class ne \$original ) {
            warn "Object class '\$class' does not match original \$Devel::Leak::Object::TRACKED{\$address}";
        }
        \$Devel::Leak::Object::OBJECT_COUNT{\$original}--;
        if ( \$Devel::Leak::Object::OBJECT_COUNT{\$original} < 0 ) {
            warn "Object count for \$Devel::Leak::Object::TRACKED{\$address} negative (\$Devel::Leak::Object::OBJECT_COUNT{\$original})";
        }
        delete \$Devel::Leak::Object::TRACKED{\$address};

        # Hand of to the regular DESTROY method, or pass up to the SUPERclass if there isn't one
        if ( \$Devel::Leak::Object::DESTROY_ORIGINAL{\$original} ) {
            goto \&{\$Devel::Leak::Object::DESTROY_ORIGINAL{\$original}};
        }
    } else {
        \$original = \$class;
    }

    # If we don't have the DESTROY_NEXT for this class, populate it
    unless ( \$Devel::Leak::Object::DESTROY_NEXT{\$original} ) {
        Devel::Leak::Object::make_next(\$original);
    }
    my \$super = \$Devel::Leak::Object::DESTROY_NEXT{\$original}->{'$class'};
    unless ( defined \$super ) {
        die "Failed to find super-method for class \$class in package $class";
    }
    if ( \$super ) {
        goto \&{\$super.'::DESTROY'};
    }
    return;
}
END_DESTROY
        if ( $@ ) {
            die "Failed to generate DESTROY method for $class: $@";
        }

        # Pre-emptively populate the DESTROY_NEXT map
        unless ( $DESTROY_NEXT{$class} ) {
            make_next($class);
        }
    }

    $OBJECT_COUNT{$TRACKED{$address}}++;
}

sub make_next {
        my $class = shift;

        # Build the %DESTROY_NEXT entries to support DESTROY_stub
        $DESTROY_NEXT{$class} = {};
        my @stack = ( $class );
        my %seen  = ( UNIVERSAL => 1 );
        my @queue = ();
        while ( my $c = shift @stack ) {
            next if $seen{$c}++;
        
            # Does the class have it's own DESTROY method
            my $has_destroy = $DESTROY_STUBBED{$c}
                ? !! exists $DESTROY_ORIGINAL{$c}
                : !! (exists ${"${c}::"}{DESTROY} and *{"${c}::DESTROY"}{CODE});
            if ( $has_destroy ) {
                # Everything in the queue has this class as it's next call
                while ( @queue ) {
                    $DESTROY_NEXT{$class}->{shift(@queue)} = $c;
                }
            } else {
                # This class goes onto the queue
                push @queue, $c;
            }

            # Add the @ISA to the search stack.
            unshift @stack, @{"${c}::ISA"};
        }

        # Any else has no target to go to
        while ( @queue ) {
            $DESTROY_NEXT{$class}->{shift @queue} = '';
        }

        return 1;
}

sub status {
	print "Tracked objects by class:\n";
	for (sort keys %OBJECT_COUNT) {
        next unless $OBJECT_COUNT{$_}; # Don't list class with count zero
		printf "%-40s %d\n", $_, $OBJECT_COUNT{$_};
	}
}

END {
	status();
}

1;

__END__


=head1 NAME

Devel::Leak::Object - Detect leaks of objects 

=head1 SYNOPSIS

  # Track a single object
  use Devel::Leak::Object;
  my $obj = Foo::Bar->new;
  Devel::Leak::Object::track($obj);
  
  # Track every object
  use Devel::Leak::Object qw{ GLOBAL_bless };

=head1 DESCRIPTION

This module provides tracking of objects, for the purpose of detecting memory
leaks due to circular references or innappropriate caching schemes.

Object tracking can be enabled on a per object basis. Any objects
thus tracked are remembered until DESTROYed; details of any objects
left are printed out to stderr at END-time.

  use Devel::Leak::Object qw(GLOBAL_bless);

This form overloads B<bless> to track construction and destruction of all
objects. As an alternative, by importing bless, you can just track the
objects of the caller code that is doing the use.

If you use GLOBAL_bless to overload the bless function, please note that
it will ONLY apply to bless for modules loaded AFTER Devel::Leak::Object
has enabled the hook.

Any modules already loaded will have already bound to CORE::bless and will
not be impacted.

=head1 BUGS

Please report bugs to http://rt.cpan.org

=head1 AUTHOR

Adam Kennedy <adamk@cpan.org>

=head1 SEE ALSO

L<Devel::Leak>

=head1 COPYRIGHT

Copyright 2007 Adam Kennedy.

Rewritten from original copyright 2004 Ivor Williams.

Some documentation also copyright 2004 Ivor Williams.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
