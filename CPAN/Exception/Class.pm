package Exception::Class;

use 5.008001;

use strict;
use warnings;

our $VERSION = '1.45';

use Carp qw( croak );
use Exception::Class::Base;
use Scalar::Util qw( blessed reftype );

our $BASE_EXC_CLASS;
BEGIN { $BASE_EXC_CLASS ||= 'Exception::Class::Base'; }

our %CLASSES;

sub import {
    my $class = shift;

    ## no critic (Variables::ProhibitPackageVars)
    local $Exception::Class::Caller = caller();

    my %c;

    my %needs_parent;
    while ( my $subclass = shift ) {
        my $def = ref $_[0] ? shift : {};
        $def->{isa}
            = $def->{isa}
            ? ( ref $def->{isa} ? $def->{isa} : [ $def->{isa} ] )
            : [];

        $c{$subclass} = $def;
    }

    # We need to sort by length because if we check for keys in the
    # Foo::Bar:: stash, this creates a "Bar::" key in the Foo:: stash!
MAKE_CLASSES:
    foreach my $subclass ( sort { length $a <=> length $b } keys %c ) {
        my $def = $c{$subclass};

        # We already made this one.
        next if $CLASSES{$subclass};

        {
            ## no critic (TestingAndDebugging::ProhibitNoStrict)
            no strict 'refs';
            foreach my $parent ( @{ $def->{isa} } ) {
                unless ( keys %{"$parent\::"} ) {
                    $needs_parent{$subclass} = {
                        parents => $def->{isa},
                        def     => $def
                    };
                    next MAKE_CLASSES;
                }
            }
        }

        $class->_make_subclass(
            subclass => $subclass,
            def      => $def || {},
        );
    }

    foreach my $subclass ( keys %needs_parent ) {

        # This will be used to spot circular references.
        my %seen;
        $class->_make_parents( \%needs_parent, $subclass, \%seen );
    }
}

sub _make_parents {
    my $class    = shift;
    my $needs    = shift;
    my $subclass = shift;
    my $seen     = shift;
    my $child    = shift;    # Just for error messages.

    ## no critic (TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitProlongedStrictureOverride)
    no strict 'refs';

    # What if someone makes a typo in specifying their 'isa' param?
    # This should catch it. Either it's been made because it didn't
    # have missing parents OR it's in our hash as needing a parent.
    # If neither of these is true then the _only_ place it is
    # mentioned is in the 'isa' param for some other class, which is
    # not a good enough reason to make a new class.
    die
        "Class $subclass appears to be a typo as it is only specified in the 'isa' param for $child\n"
        unless exists $needs->{$subclass}
        || $CLASSES{$subclass}
        || keys %{"$subclass\::"};

    foreach my $c ( @{ $needs->{$subclass}{parents} } ) {

        # It's been made
        next if $CLASSES{$c} || keys %{"$c\::"};

        die "There appears to be some circularity involving $subclass\n"
            if $seen->{$subclass};

        $seen->{$subclass} = 1;

        $class->_make_parents( $needs, $c, $seen, $subclass );
    }

    return if $CLASSES{$subclass} || keys %{"$subclass\::"};

    $class->_make_subclass(
        subclass => $subclass,
        def      => $needs->{$subclass}{def}
    );
}

sub _make_subclass {
    my $class = shift;
    my %p     = @_;

    my $subclass = $p{subclass};
    my $def      = $p{def};

    my $isa;
    if ( $def->{isa} ) {
        $isa = ref $def->{isa} ? join q{ }, @{ $def->{isa} } : $def->{isa};
    }
    $isa ||= $BASE_EXC_CLASS;

    my $version_name = 'VERSION';

    my $code = <<"EOPERL";
package $subclass;

use base qw($isa);

our \$$version_name = '1.1';

1;

EOPERL

    if ( $def->{description} ) {
        ( my $desc = $def->{description} ) =~ s/([\\\'])/\\$1/g;
        $code .= <<"EOPERL";
sub description
{
    return '$desc';
}
EOPERL
    }

    my @fields;
    if ( my $fields = $def->{fields} ) {
        @fields
            = ref $fields && reftype $fields eq 'ARRAY' ? @$fields : $fields;

        $code
            .= 'sub Fields { return ($_[0]->SUPER::Fields, '
            . join( ', ', map {"'$_'"} @fields )
            . ") }\n\n";

        foreach my $field (@fields) {
            croak
                "Invalid field name <$field>. A field name must be a legal Perl identifier."
                unless $field =~ /\A[a-z_][a-z0-9_]*\z/i;
            $code .= sprintf( "sub %s { \$_[0]->{%s} }\n", $field, $field );
        }
    }

    if ( my $alias = $def->{alias} ) {
        ## no critic (Variables::ProhibitPackageVars)
        die 'Cannot make alias without caller'
            unless defined $Exception::Class::Caller;

        ## no critic (TestingAndDebugging::ProhibitNoStrict)
        no strict 'refs';
        *{"$Exception::Class::Caller\::$alias"}
            = sub { $subclass->throw(@_) };
    }

    if ( my $defaults = $def->{defaults} ) {
        $code
            .= "sub _defaults { return shift->SUPER::_defaults, our \%_DEFAULTS }\n";
        ## no critic (TestingAndDebugging::ProhibitNoStrict)
        no strict 'refs';
        *{"$subclass\::_DEFAULTS"} = {%$defaults};
    }

    ## no critic (BuiltinFunctions::ProhibitStringyEval, ErrorHandling::RequireCheckingReturnValueOfEval)
    eval $code;
    die $@ if $@;

    ( my $filename = "$subclass.pm" ) =~ s{::}{/}g;
    $INC{$filename} = __FILE__;

    $CLASSES{$subclass} = 1;
}

sub caught {
    my $e = $@;

    return $e unless $_[1];

    return unless blessed($e) && $e->isa( $_[1] );
    return $e;
}

sub Classes { sort keys %Exception::Class::CLASSES }

1;

# ABSTRACT: A module that allows you to declare real exception classes in Perl

__END__

=pod

=encoding UTF-8

=head1 NAME

Exception::Class - A module that allows you to declare real exception classes in Perl

=head1 VERSION

version 1.45

=head1 SYNOPSIS

  use Exception::Class (
      'MyException',

      'AnotherException' => { isa => 'MyException' },

      'YetAnotherException' => {
          isa         => 'AnotherException',
          description => 'These exceptions are related to IPC'
      },

      'ExceptionWithFields' => {
          isa    => 'YetAnotherException',
          fields => [ 'grandiosity', 'quixotic' ],
          alias  => 'throw_fields',
      },
  );
  use Scalar::Util qw( blessed );
  use Try::Tiny;

  try {
      MyException->throw( error => 'I feel funny.' );
  }
  catch {
      die $_ unless blessed $_ && $_->can('rethrow');

      if ( $_->isa('Exception::Class') ) {
          warn $_->error, "\n", $_->trace->as_string, "\n";
          warn join ' ', $_->euid, $_->egid, $_->uid, $_->gid, $_->pid, $_->time;

          exit;
      }
      elsif ( $_->isa('ExceptionWithFields') ) {
          if ( $_->quixotic ) {
              handle_quixotic_exception();
          }
          else {
              handle_non_quixotic_exception();
          }
      }
      else {
          $_->rethrow;
      }
  };

  # without Try::Tiny
  eval { ... };
  if ( my $e = Exception::Class->caught ) { ... }

  # use an alias - without parens subroutine name is checked at
  # compile time
  throw_fields error => "No strawberry", grandiosity => "quite a bit";

=head1 DESCRIPTION

B<RECOMMENDATION 1>: If you are writing modern Perl code with L<Moose> or
L<Moo> I highly recommend using L<Throwable> instead of this module.

B<RECOMMENDATION 2>: Whether or not you use L<Throwable>, you should use
L<Try::Tiny>.

Exception::Class allows you to declare exception hierarchies in your modules in
a "Java-esque" manner.

It features a simple interface allowing programmers to 'declare' exception
classes at compile time. It also has a base exception class,
L<Exception::Class::Base>, that can be easily extended.

It is designed to make structured exception handling simpler and better by
encouraging people to use hierarchies of exceptions in their applications, as
opposed to a single catch-all exception class.

This module does not implement any try/catch syntax. Please see the "OTHER
EXCEPTION MODULES (try/catch syntax)" section for more information on how to
get this syntax.

You will also want to look at the documentation for L<Exception::Class::Base>,
which is the default base class for all exception objects created by this
module.

=for Pod::Coverage     Classes
    caught

=head1 DECLARING EXCEPTION CLASSES

Importing C<Exception::Class> allows you to automagically create
L<Exception::Class::Base> subclasses. You can also create subclasses via the
traditional means of defining your own subclass with C<@ISA>.  These two
methods may be easily combined, so that you could subclass an exception class
defined via the automagic import, if you desired this.

The syntax for the magic declarations is as follows:

  'MANDATORY CLASS NAME' => \%optional_hashref

The hashref may contain the following options:

=over 4

=item * isa

This is the class's parent class. If this isn't provided then the class name in
C<$Exception::Class::BASE_EXC_CLASS> is assumed to be the parent (see below).

This parameter lets you create arbitrarily deep class hierarchies.  This can be
any other L<Exception::Class::Base> subclass in your declaration I<or> a
subclass loaded from a module.

To change the default exception class you will need to change the value of
C<$Exception::Class::BASE_EXC_CLASS> I<before> calling C<import>. To do this
simply do something like this:

  BEGIN { $Exception::Class::BASE_EXC_CLASS = 'SomeExceptionClass'; }

If anyone can come up with a more elegant way to do this please let me know.

CAVEAT: If you want to automagically subclass an L<Exception::Class::Base>
subclass loaded from a file, then you I<must> compile the class (via use or
require or some other magic) I<before> you import C<Exception::Class> or you'll
get a compile time error.

=item * fields

This allows you to define additional attributes for your exception class. Any
field you define can be passed to the C<throw> or C<new> methods as additional
parameters for the constructor. In addition, your exception object will have an
accessor method for the fields you define.

This parameter can be either a scalar (for a single field) or an array
reference if you need to define multiple fields.

Each field name must be a legal Perl identifier: it starts with a ASCII letter
or underscore, and is followed by zero or more ASCII letters, ASCII digits, or
underscores. If a field name does not match this, the creation of that
exception class croaks.

Fields will be inherited by subclasses.

=item * alias

Specifying an alias causes this class to create a subroutine of the specified
name in the I<caller's> namespace. Calling this subroutine is equivalent to
calling C<< <class>->throw(@_) >> for the given exception class.

Besides convenience, using aliases also allows for additional compile time
checking. If the alias is called I<without parentheses>, as in C<throw_fields
"an error occurred">, then Perl checks for the existence of the C<throw_fields>
subroutine at compile time. If instead you do C<<
ExceptionWithFields->throw(...) >>, then Perl checks the class name at runtime,
meaning that typos may sneak through.

=item * description

Each exception class has a description method that returns a fixed string. This
should describe the exception I<class> (as opposed to any particular exception
object). This may be useful for debugging if you start catching exceptions you
weren't expecting (particularly if someone forgot to document them) and you
don't understand the error messages.

=back

The C<Exception::Class> magic attempts to detect circular class hierarchies and
will die if it finds one. It also detects missing links in a chain, for example
if you declare Bar to be a subclass of Foo and never declare Foo.

=head1 L<Try::Tiny>

If you are interested in adding try/catch/finally syntactic sugar to your code
then I recommend you check out L<Try::Tiny>. This is a great module that helps
you ignore some of the weirdness with C<eval> and C<$@>. Here's an example of
how the two modules work together:

  use Exception::Class ( 'My::Exception' );
  use Scalar::Util qw( blessed );
  use Try::Tiny;

  try {
      might_throw();
  }
  catch {
      if ( blessed $_ && $_->isa('My::Exception') ) {
          handle_it();
      }
      else {
          die $_;
      }
  };

Note that you B<cannot> use C<< Exception::Class->caught >> with L<Try::Tiny>.

=head1 Catching Exceptions Without L<Try::Tiny>

C<Exception::Class> provides some syntactic sugar for catching exceptions in a
safe manner:

  eval {...};

  if ( my $e = Exception::Class->caught('My::Error') ) {
      cleanup();
      do_something_with_exception($e);
  }

The C<caught> method takes a class name and returns an exception object if the
last thrown exception is of the given class, or a subclass of that class. If it
is not given any arguments, it simply returns C<$@>.

You should B<always> make a copy of the exception object, rather than using
C<$@> directly. This is necessary because if your C<cleanup> function uses
C<eval>, or calls something which uses it, then C<$@> is overwritten. Copying
the exception preserves it for the call to C<do_something_with_exception>.

Exception objects also provide a caught method so you can write:

  if ( my $e = My::Error->caught ) {
      cleanup();
      do_something_with_exception($e);
  }

=head2 Uncatchable Exceptions

Internally, the C<caught> method will call C<isa> on the exception object. You
could make an exception "uncatchable" by overriding C<isa> in that class like
this:

 package Exception::Uncatchable;

 sub isa { shift->rethrow }

Of course, this only works if you always call C<< Exception::Class->caught >>
after an C<eval>.

=head1 USAGE RECOMMENDATION

If you're creating a complex system that throws lots of different types of
exceptions, consider putting all the exception declarations in one place. For
an app called Foo you might make a C<Foo::Exceptions> module and use that in
all your code. This module could just contain the code to make
C<Exception::Class> do its automagic class creation. Doing this allows you to
more easily see what exceptions you have, and makes it easier to keep track of
them.

This might look something like this:

  package Foo::Bar::Exceptions;

  use Exception::Class (
      Foo::Bar::Exception::Senses =>
          { description => 'sense-related exception' },

      Foo::Bar::Exception::Smell => {
          isa         => 'Foo::Bar::Exception::Senses',
          fields      => 'odor',
          description => 'stinky!'
      },

      Foo::Bar::Exception::Taste => {
          isa         => 'Foo::Bar::Exception::Senses',
          fields      => [ 'taste', 'bitterness' ],
          description => 'like, gag me with a spoon!'
      },

      ...
  );

You may want to create a real module to subclass L<Exception::Class::Base> as
well, particularly if you want your exceptions to have more methods.

=head2 Subclassing Exception::Class::Base

As part of your usage of C<Exception::Class>, you may want to create your own
base exception class which subclasses L<Exception::Class::Base>. You should
feel free to subclass any of the methods documented above. For example, you may
want to subclass C<new> to add additional information to your exception
objects.

=head1 Exception::Class FUNCTIONS

The C<Exception::Class> method offers one function, C<Classes>, which is not
exported. This method returns a list of the classes that have been created by
calling the C<Exception::Class> C<import> method.  Note that this is I<all> the
subclasses that have been created, so it may include subclasses created by
things like CPAN modules, etc. Also note that if you simply define a subclass
via the normal Perl method of setting C<@ISA> or C<use base>, then your
subclass will not be included.

=head1 SUPPORT

Bugs may be submitted at L<https://github.com/houseabsolute/Exception-Class/issues>.

I am also usually active on IRC as 'autarch' on C<irc://irc.perl.org>.

=head1 SOURCE

The source code repository for Exception-Class can be found at L<https://github.com/houseabsolute/Exception-Class>.

=head1 DONATIONS

If you'd like to thank me for the work I've done on this module, please
consider making a "donation" to me via PayPal. I spend a lot of free time
creating free software, and would appreciate any support you'd care to offer.

Please note that B<I am not suggesting that you must do this> in order for me
to continue working on this particular software. I will continue to do so,
inasmuch as I have in the past, for as long as it interests me.

Similarly, a donation made in this way will probably not make me work on this
software much more, unless I get so many donations that I can consider working
on free software full time (let's all have a chuckle at that together).

To donate, log into PayPal and send money to autarch@urth.org, or use the
button at L<https://www.urth.org/fs-donation.html>.

=head1 AUTHOR

Dave Rolsky <autarch@urth.org>

=head1 CONTRIBUTORS

=for stopwords Alexander Batyrshin brian d foy Leon Timmermans Ricardo Signes

=over 4

=item *

Alexander Batyrshin <0x62ash@gmail.com>

=item *

brian d foy <brian.d.foy@gmail.com>

=item *

Leon Timmermans <fawaka@gmail.com>

=item *

Ricardo Signes <rjbs@cpan.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2021 by Dave Rolsky.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

The full text of the license can be found in the
F<LICENSE> file included with this distribution.

=cut
