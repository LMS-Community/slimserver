package Class::Trigger;

use strict;
use vars qw($VERSION);
$VERSION = 0.08;

use Class::Data::Inheritable;
use Carp ();

sub import {
    my $class = shift;
    my $pkg = caller(0);

    # XXX 5.005_03 isa() is broken with MI
    unless ($pkg->can('mk_classdata')) {
	no strict 'refs';
	push @{"$pkg\::ISA"}, 'Class::Data::Inheritable';
    }

    $pkg->mk_classdata('__triggers');
    $pkg->mk_classdata('__triggerpoints');

    $pkg->__triggerpoints({ map { $_ => 1 } @_ }) if @_;

    # export mixin methods
    no strict 'refs';
    my @methods = qw(add_trigger call_trigger);
    *{"$pkg\::$_"} = \&{$_} for @methods;
}

sub add_trigger {
    my $proto = shift;

    # should be deep copy of the hash: for inheritance
    my $old_triggers = __fetch_triggers($proto) || {};
    my %triggers = __deep_dereference($old_triggers);
    while (my($when, $code) = splice @_, 0, 2) {
	__validate_triggerpoint($proto, $when);
	Carp::croak('add_trigger() needs coderef') unless ref($code) eq 'CODE';
	push @{$triggers{$when}}, $code;
    }
    __update_triggers($proto, \%triggers);
}

sub call_trigger {
    my $self = shift;
    my $all_triggers = __fetch_triggers($self) || return; # any triggers?
    my $when = shift;
    if (my $triggers = $all_triggers->{$when}) {
	for my $trigger (@$triggers) {
	    $trigger->($self, @_);
	}
    }
    else {
	# if validation is enabled we can only add valid trigger points
	# so we only need to check in call_trigger() if there's no
	# trigger with the requested name.
	__validate_triggerpoint($self, $when);
    }
}

sub __validate_triggerpoint {
    my $points = $_[0]->__triggerpoints || return;
    my ($self, $when) = @_;
    Carp::croak("$when is not valid triggerpoint for ".(ref($self) || $self))
	unless $points->{$when};
}

sub __fetch_triggers {
    my $proto = shift;
    # check object based triggers first
    return (ref $proto and $proto->{__triggers}) || $proto->__triggers;
}

sub __update_triggers {
    my($proto, $triggers) = @_;
    if (ref $proto) {
	# object attributes
	$proto->{__triggers} = $triggers;
    }
    else {
	# class data inheritable
	$proto->__triggers($triggers);
    }
}

sub __deep_dereference {
    my $hashref = shift;
    my %copy;
    while (my($key, $arrayref) = each %$hashref) {
	$copy{$key} = [ @$arrayref ];
    }
    return %copy;
}

1;
__END__

=head1 NAME

Class::Trigger - Mixin to add / call inheritable triggers

=head1 SYNOPSIS

  package Foo;
  use Class::Trigger;

  sub foo {
      my $self = shift;
      $self->call_trigger('before_foo');
      # some code ...
      $self->call_trigger('middle_of_foo');
      # some code ...
      $self->call_trigger('after_foo');
  }

  package main;
  Foo->add_trigger(before_foo => \&sub1);
  Foo->add_trigger(after_foo => \&sub2);

  my $foo = Foo->new;
  $foo->foo;			# then sub1, sub2 called

  # triggers are inheritable
  package Bar;
  use base qw(Foo);

  Bar->add_trigger(before_foo => \&sub);

  # triggers can be object based
  $foo->add_trigger(after_foo => \&sub3);
  $foo->foo;			# sub3 would appply only to this object

=head1 DESCRIPTION

Class::Trigger is a mixin class to add / call triggers (or hooks)
that get called at some points you specify.

=head1 METHODS

By using this module, your class is capable of following two methods.

=over 4

=item add_trigger

  Foo->add_trigger($triggerpoint => $sub);
  $foo->add_trigger($triggerpoint => $sub);

Adds triggers for trigger point. You can have any number of triggers
for each point. Each coderef will be passed a the object reference, and
return values will be ignored.

If C<add_trigger> is called as object method, whole current trigger
table will be copied onto the object and the new trigger added to
that. (The object must be implemented as hash.)

  my $foo = Foo->new;

  # this trigger ($sub_foo) would apply only to $foo object
  $foo->add_trigger($triggerpoint => $sub_foo);
  $foo->foo;

  # And not to another $bar object
  my $bar = Foo->new;
  $bar->foo;

Any triggers added to the class after adding a trigger to an object
will not be fired for the object because the object now has a private
copy of the triggers.


=item call_trigger

  $foo->call_trigger($triggerpoint);

Calls triggers for trigger point, which were added via C<add_trigger>
method. Each triggers will be passed a copy of the object.
Triggers are invoked in the same order they were defined.

=back

=head1 TRIGGER POINTS

By default you can make any number of trigger points, but if you want
to declare names of trigger points explicitly, you can do it via
C<import>.

  package Foo;
  use Class::Trigger qw(foo bar baz);

  package main;
  Foo->add_trigger(foo  => \&sub1); # okay
  Foo->add_trigger(hoge => \&sub2); # exception

=head1 FAQ

B<Acknowledgement:> Thanks to everyone at POOP mailing-list
(http://poop.sourceforge.net/).

=over 4

=item Q.

This module lets me add subs to be run before/after a specific
subroutine is run.  Yes?

=item A.

You put various call_trigger() method in your class.  Then your class
users can call add_trigger() method to add subs to be run in points
just you specify (exactly where you put call_trigger()).

=item Q.

Are you aware of the perl-aspects project and the Aspect module?  Very
similar to Class::Trigger by the look of it, but its not nearly as
explicit.  Its not necessary for foo() to actually say "triggers go
*here*", you just add them.

=item A.

Yep ;)

But the difference with Aspect would be that Class::Trigger is so
simple that it's easy to learn, and doesn't require 5.6 or over.

=item Q.

How does this compare to Sub::Versive, or Hook::LexWrap?

=item A.

Very similar. But the difference with Class::Trigger would be the
explicitness of trigger points.

In addition, you can put hooks in any point, rather than pre or post
of a method.

=item Q.

It looks interesting, but I just can't think of a practical example of
its use...

=item A.

(by Tony Bowden)

I originally added code like this to Class::DBI to cope with one
particular case: auto-upkeep of full-text search indices.

So I added functionality in Class::DBI to be able to trigger an
arbitary subroutine every time something happened - then it was a
simple matter of setting up triggers on INSERT and UPDATE to reindex
that row, and on DELETE to remove that index row.

See L<Class::DBI::mysql::FullTextSearch> and its source code to see it
in action.

=back

=head1 AUTHOR

Original idea by Tony Bowden E<lt>tony@kasei.comE<gt> in Class::DBI.

Code by Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>.

Patches by Tim Buce E<lt>Tim.Bunce@pobox.comE<gt>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Class::Data::Inheritable>

=cut

