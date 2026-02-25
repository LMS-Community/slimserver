use strict;
use warnings;

package namespace::autoclean; # git description: 0.30-TRIAL-2-ga0e6aea
# ABSTRACT: Keep imports out of your namespace
# KEYWORDS: namespaces clean dirty imports exports subroutines methods development

our $VERSION = '0.31';

use B::Hooks::EndOfScope 0.12;
use List::Util qw( first );

BEGIN {
    if (eval { require Sub::Util } && defined &Sub::Util::subname) {
        *subname = \&Sub::Util::subname;
    }
    else {
        require B;
        *subname = sub {
            my ($coderef) = @_;
            die 'Not a subroutine reference'
                unless ref $coderef;
            my $cv = B::svref_2object($coderef);
            die 'Not a subroutine reference'
                unless $cv->isa('B::CV');
            my $gv = $cv->GV;
            return undef
                if $gv->isa('B::SPECIAL');
            my $stash = $gv->STASH;
            my $package = $stash->isa('B::SPECIAL') ? '__ANON__' : $stash->NAME;
            return $package . '::' . $gv->NAME;
        };
    }
}

use namespace::clean 0.20;

#pod =head1 SYNOPSIS
#pod
#pod     package Foo;
#pod     use namespace::autoclean;
#pod     use Some::Package qw/imported_function/;
#pod
#pod     sub bar { imported_function('stuff') }
#pod
#pod     # later on:
#pod     Foo->bar;               # works
#pod     Foo->imported_function; # will fail. imported_function got cleaned after compilation
#pod
#pod =head1 DESCRIPTION
#pod
#pod When you import a function into a Perl package, it will naturally also be
#pod available as a method.
#pod
#pod The C<namespace::autoclean> pragma will remove all imported symbols at the end
#pod of the current package's compile cycle. Functions called in the package itself
#pod will still be bound by their name, but they won't show up as methods on your
#pod class or instances.
#pod
#pod This module is very similar to L<namespace::clean|namespace::clean>, except it
#pod will clean all imported functions, no matter if you imported them before or
#pod after you C<use>d the pragma. It will also not touch anything that looks like a
#pod method.
#pod
#pod If you're writing an exporter and you want to clean up after yourself (and your
#pod peers), you can use the C<-cleanee> switch to specify what package to clean:
#pod
#pod   package My::MooseX::namespace::autoclean;
#pod   use strict;
#pod
#pod   use namespace::autoclean (); # no cleanup, just load
#pod
#pod   sub import {
#pod       namespace::autoclean->import(
#pod         -cleanee => scalar(caller),
#pod       );
#pod   }
#pod
#pod =head1 WHAT IS AND ISN'T CLEANED
#pod
#pod C<namespace::autoclean> will leave behind anything that it deems a method.  For
#pod L<Moose> classes, this the based on the C<get_method_list> method
#pod on from the L<Class::MOP::Class|metaclass>.  For non-Moose classes, anything
#pod defined within the package will be identified as a method.  This should match
#pod Moose's definition of a method.  Additionally, the magic subs installed by
#pod L<overload> will not be cleaned.
#pod
#pod =head1 PARAMETERS
#pod
#pod =head2 -also => [ ITEM | REGEX | SUB, .. ]
#pod
#pod =head2 -also => ITEM
#pod
#pod =head2 -also => REGEX
#pod
#pod =head2 -also => SUB
#pod
#pod Sometimes you don't want to clean imports only, but also helper functions
#pod you're using in your methods. The C<-also> switch can be used to declare a list
#pod of functions that should be removed additional to any imports:
#pod
#pod     use namespace::autoclean -also => ['some_function', 'another_function'];
#pod
#pod If only one function needs to be additionally cleaned the C<-also> switch also
#pod accepts a plain string:
#pod
#pod     use namespace::autoclean -also => 'some_function';
#pod
#pod In some situations, you may wish for a more I<powerful> cleaning solution.
#pod
#pod The C<-also> switch can take a Regex or a CodeRef to match against local
#pod function names to clean.
#pod
#pod     use namespace::autoclean -also => qr/^_/
#pod
#pod     use namespace::autoclean -also => sub { $_ =~ m{^_} };
#pod
#pod     use namespace::autoclean -also => [qr/^_/ , qr/^hidden_/ ];
#pod
#pod     use namespace::autoclean -also => [sub { $_ =~ m/^_/ or $_ =~ m/^hidden/ }, sub { uc($_) == $_ } ];
#pod
#pod =head2 -except => [ ITEM | REGEX | SUB, .. ]
#pod
#pod =head2 -except => ITEM
#pod
#pod =head2 -except => REGEX
#pod
#pod =head2 -except => SUB
#pod
#pod This takes exactly the same options as C<-also> except that anything this
#pod matches will I<not> be cleaned.
#pod
#pod =head1 CAVEATS
#pod
#pod When used with L<Moo> classes, the heuristic used to check for methods won't
#pod work correctly for methods from roles consumed at compile time.
#pod
#pod   package My::Class;
#pod   use Moo;
#pod   use namespace::autoclean;
#pod
#pod   # Bad, any consumed methods will be cleaned
#pod   BEGIN { with 'Some::Role' }
#pod
#pod   # Good, methods from role will be maintained
#pod   with 'Some::Role';
#pod
#pod Additionally, method detection may not work properly in L<Mouse> classes in
#pod perls earlier than 5.10.
#pod
#pod =head1 SEE ALSO
#pod
#pod =for :list
#pod * L<namespace::clean>
#pod * L<B::Hooks::EndOfScope>
#pod * L<namespace::sweep>
#pod * L<Sub::Exporter::ForMethods>
#pod * L<Sub::Name>
#pod * L<Sub::Install>
#pod * L<Test::CleanNamespaces>
#pod * L<Dist::Zilla::Plugin::Test::CleanNamespaces>
#pod
#pod =cut

sub import {
    my ($class, %args) = @_;

    my $subcast = sub {
        my $i = shift;
        return $i if ref $i eq 'CODE';
        return sub { $_ =~ $i } if ref $i eq 'Regexp';
        return sub { $_ eq $i };
    };

    my $runtest = sub {
        my ($code, $method_name) = @_;
        local $_ = $method_name;
        return $code->();
    };

    my $cleanee = exists $args{-cleanee} ? $args{-cleanee} : scalar caller;

    my @also = map $subcast->($_), (
        exists $args{-also}
        ? (ref $args{-also} eq 'ARRAY' ? @{ $args{-also} } : $args{-also})
        : ()
    );

    my @except = map $subcast->($_), (
        exists $args{-except}
        ? (ref $args{-except} eq 'ARRAY' ? @{ $args{-except} } : $args{-except})
        : ()
    );

    on_scope_end {
        my $subs = namespace::clean->get_functions($cleanee);
        my $method_check = _method_check($cleanee);

        my @clean = grep {
          my $method = $_;
          ! first { $runtest->($_, $method) } @except
            and ( !$method_check->($method)
              or first { $runtest->($_, $method) } @also)
        } keys %$subs;

        namespace::clean->clean_subroutines($cleanee, @clean);
    };
}

sub _method_check {
    my $package = shift;
    if (
      (defined &Class::MOP::class_of and my $meta = Class::MOP::class_of($package))
    ) {
        my %methods = map +($_ => 1), $meta->get_method_list;
        $methods{meta} = 1
          if $meta->isa('Moose::Meta::Role') && Moose->VERSION < 0.90;
        return sub { $_[0] =~ /^\(/ || $methods{$_[0]} };
    }
    else {
        my $does = $package->can('does') ? 'does'
                 : $package->can('DOES') ? 'DOES'
                 : undef;
        return sub {
            return 1 if $_[0] =~ /^\(/;
            my $coderef = do { no strict 'refs'; \&{ $package . '::' . $_[0] } };
            my ($code_stash) = subname($coderef) =~ /\A(.*)::/s;
            return 1 if $code_stash eq $package;
            return 1 if $code_stash eq 'constant';
            # TODO: consider if we really need this eval
            return 1 if $does && eval { $package->$does($code_stash) };
            return 0;
        };
    }
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

namespace::autoclean - Keep imports out of your namespace

=head1 VERSION

version 0.31

=head1 SYNOPSIS

    package Foo;
    use namespace::autoclean;
    use Some::Package qw/imported_function/;

    sub bar { imported_function('stuff') }

    # later on:
    Foo->bar;               # works
    Foo->imported_function; # will fail. imported_function got cleaned after compilation

=head1 DESCRIPTION

When you import a function into a Perl package, it will naturally also be
available as a method.

The C<namespace::autoclean> pragma will remove all imported symbols at the end
of the current package's compile cycle. Functions called in the package itself
will still be bound by their name, but they won't show up as methods on your
class or instances.

This module is very similar to L<namespace::clean|namespace::clean>, except it
will clean all imported functions, no matter if you imported them before or
after you C<use>d the pragma. It will also not touch anything that looks like a
method.

If you're writing an exporter and you want to clean up after yourself (and your
peers), you can use the C<-cleanee> switch to specify what package to clean:

  package My::MooseX::namespace::autoclean;
  use strict;

  use namespace::autoclean (); # no cleanup, just load

  sub import {
      namespace::autoclean->import(
        -cleanee => scalar(caller),
      );
  }

=head1 WHAT IS AND ISN'T CLEANED

C<namespace::autoclean> will leave behind anything that it deems a method.  For
L<Moose> classes, this the based on the C<get_method_list> method
on from the L<Class::MOP::Class|metaclass>.  For non-Moose classes, anything
defined within the package will be identified as a method.  This should match
Moose's definition of a method.  Additionally, the magic subs installed by
L<overload> will not be cleaned.

=head1 PARAMETERS

=head2 -also => [ ITEM | REGEX | SUB, .. ]

=head2 -also => ITEM

=head2 -also => REGEX

=head2 -also => SUB

Sometimes you don't want to clean imports only, but also helper functions
you're using in your methods. The C<-also> switch can be used to declare a list
of functions that should be removed additional to any imports:

    use namespace::autoclean -also => ['some_function', 'another_function'];

If only one function needs to be additionally cleaned the C<-also> switch also
accepts a plain string:

    use namespace::autoclean -also => 'some_function';

In some situations, you may wish for a more I<powerful> cleaning solution.

The C<-also> switch can take a Regex or a CodeRef to match against local
function names to clean.

    use namespace::autoclean -also => qr/^_/

    use namespace::autoclean -also => sub { $_ =~ m{^_} };

    use namespace::autoclean -also => [qr/^_/ , qr/^hidden_/ ];

    use namespace::autoclean -also => [sub { $_ =~ m/^_/ or $_ =~ m/^hidden/ }, sub { uc($_) == $_ } ];

=head2 -except => [ ITEM | REGEX | SUB, .. ]

=head2 -except => ITEM

=head2 -except => REGEX

=head2 -except => SUB

This takes exactly the same options as C<-also> except that anything this
matches will I<not> be cleaned.

=head1 CAVEATS

When used with L<Moo> classes, the heuristic used to check for methods won't
work correctly for methods from roles consumed at compile time.

  package My::Class;
  use Moo;
  use namespace::autoclean;

  # Bad, any consumed methods will be cleaned
  BEGIN { with 'Some::Role' }

  # Good, methods from role will be maintained
  with 'Some::Role';

Additionally, method detection may not work properly in L<Mouse> classes in
perls earlier than 5.10.

=head1 SEE ALSO

=over 4

=item *

L<namespace::clean>

=item *

L<B::Hooks::EndOfScope>

=item *

L<namespace::sweep>

=item *

L<Sub::Exporter::ForMethods>

=item *

L<Sub::Name>

=item *

L<Sub::Install>

=item *

L<Test::CleanNamespaces>

=item *

L<Dist::Zilla::Plugin::Test::CleanNamespaces>

=back

=head1 SUPPORT

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=namespace-autoclean>
(or L<bug-namespace-autoclean@rt.cpan.org|mailto:bug-namespace-autoclean@rt.cpan.org>).

There is also a mailing list available for users of this distribution, at
L<http://lists.perl.org/list/moose.html>.

There is also an irc channel available for users of this distribution, at
L<C<#moose> on C<irc.perl.org>|irc://irc.perl.org/#moose>.

=head1 AUTHOR

Florian Ragwitz <rafl@debian.org>

=head1 CONTRIBUTORS

=for stopwords Karen Etheridge Graham Knop Dave Rolsky Kent Fredric Tomas Doran Shawn M Moore Felix Ostmann Andrew Rodland Chris Prather

=over 4

=item *

Karen Etheridge <ether@cpan.org>

=item *

Graham Knop <haarg@haarg.org>

=item *

Dave Rolsky <autarch@urth.org>

=item *

Kent Fredric <kentfredric@gmail.com>

=item *

Tomas Doran <bobtfish@bobtfish.net>

=item *

Shawn M Moore <cpan@sartak.org>

=item *

Felix Ostmann <sadrak@cpan.org>

=item *

Andrew Rodland <arodland@cpan.org>

=item *

Chris Prather <chris@prather.org>

=back

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2009 by Florian Ragwitz.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
