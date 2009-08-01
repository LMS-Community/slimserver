package  # hide me from PAUSE
    next;

use strict;
use warnings;
no warnings 'redefine'; # for 00load.t w/ core support

use Scalar::Util 'blessed';

our $VERSION = '0.06';

our %METHOD_CACHE;

sub method {
    my $self     = $_[0];
    my $class    = blessed($self) || $self;
    my $indirect = caller() =~ /^(?:next|maybe::next)$/;
    my $level = $indirect ? 2 : 1;

    my ($method_caller, $label, @label);
    while ($method_caller = (caller($level++))[3]) {
      @label = (split '::', $method_caller);
      $label = pop @label;
      last unless
        $label eq '(eval)' ||
        $label eq '__ANON__';
    }

    my $method;

    my $caller   = join '::' => @label;

    $method = $METHOD_CACHE{"$class|$caller|$label"} ||= do {

        my @MRO = Class::C3::calculateMRO($class);

        my $current;
        while ($current = shift @MRO) {
            last if $caller eq $current;
        }

        no strict 'refs';
        my $found;
        foreach my $class (@MRO) {
            next if (defined $Class::C3::MRO{$class} &&
                     defined $Class::C3::MRO{$class}{methods}{$label});
            last if (defined ($found = *{$class . '::' . $label}{CODE}));
        }

        $found;
    };

    return $method if $indirect;

    die "No next::method '$label' found for $self" if !$method;

    goto &{$method};
}

sub can { method($_[0]) }

package  # hide me from PAUSE
    maybe::next;

use strict;
use warnings;
no warnings 'redefine'; # for 00load.t w/ core support

our $VERSION = '0.02';

sub method { (next::method($_[0]) || return)->(@_) }

1;

__END__

=pod

=head1 NAME

Class::C3::next - Pure-perl next::method and friends

=head1 DESCRIPTION

This module is used internally by L<Class::C3> when
neccesary, and shouldn't be used (or required in
distribution dependencies) directly.  It
defines C<next::method>, C<next::can>, and
C<maybe::next::method> in pure perl.

=head1 AUTHOR

Stevan Little, E<lt>stevan@iinteractive.comE<gt>

Brandon L. Black, E<lt>blblack@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2005, 2006 by Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
