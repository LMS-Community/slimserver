package Package::Stash::PP;
use strict;
use warnings;
# ABSTRACT: Pure perl implementation of the Package::Stash API

our $VERSION = '0.40';

use B;
use Carp qw(confess);
use Scalar::Util qw(blessed reftype weaken);
use Symbol;
# before 5.12, assigning to the ISA glob would make it lose its magical ->isa
# powers
use constant BROKEN_ISA_ASSIGNMENT => ($] < 5.012);
# before 5.10, stashes don't ever seem to drop to a refcount of zero, so
# weakening them isn't helpful
use constant BROKEN_WEAK_STASH     => ($] < 5.010);
# before 5.10, the scalar slot was always treated as existing if the
# glob existed
use constant BROKEN_SCALAR_INITIALIZATION => ($] < 5.010);
# add_method on anon stashes triggers rt.perl #1804 otherwise
# fixed in perl commit v5.13.3-70-g0fe688f
use constant BROKEN_GLOB_ASSIGNMENT => ($] < 5.013004);
# pre-5.10, ->isa lookups were cached in the ::ISA::CACHE:: slot
use constant HAS_ISA_CACHE => ($] < 5.010);

#pod =head1 SYNOPSIS
#pod
#pod   use Package::Stash;
#pod
#pod =head1 DESCRIPTION
#pod
#pod This is a backend for L<Package::Stash> implemented in pure perl, for those without a compiler or who would like to use this inline in scripts.
#pod
#pod =cut

sub new {
    my $class = shift;
    my ($package) = @_;

    if (!defined($package) || (ref($package) && reftype($package) ne 'HASH')) {
        confess "Package::Stash->new must be passed the name of the "
              . "package to access";
    }
    elsif (ref($package) && reftype($package) eq 'HASH') {
        confess "The PP implementation of Package::Stash does not support "
              . "anonymous stashes before perl 5.14"
            if BROKEN_GLOB_ASSIGNMENT;

        return bless {
            'namespace' => $package,
        }, $class;
    }
    elsif ($package =~ /\A[0-9A-Z_a-z]+(?:::[0-9A-Z_a-z]+)*\z/) {
        return bless {
            'package' => $package,
        }, $class;
    }
    else {
        confess "$package is not a module name";
    }

}

sub name {
    confess "Can't call name as a class method"
        unless blessed($_[0]);
    confess "Can't get the name of an anonymous package"
        unless defined($_[0]->{package});
    return $_[0]->{package};
}

sub namespace {
    confess "Can't call namespace as a class method"
        unless blessed($_[0]);

    if (BROKEN_WEAK_STASH) {
        no strict 'refs';
        return \%{$_[0]->name . '::'};
    }
    else {
        return $_[0]->{namespace} if defined $_[0]->{namespace};

        {
            no strict 'refs';
            $_[0]->{namespace} = \%{$_[0]->name . '::'};
        }

        weaken($_[0]->{namespace});

        return $_[0]->{namespace};
    }
}

{
    my %SIGIL_MAP = (
        '$' => 'SCALAR',
        '@' => 'ARRAY',
        '%' => 'HASH',
        '&' => 'CODE',
        ''  => 'IO',
    );

    sub _deconstruct_variable_name {
        my ($variable) = @_;

        my @ret;
        if (ref($variable) eq 'HASH') {
            @ret = @{$variable}{qw[name sigil type]};
        }
        else {
            (defined $variable && length $variable)
                || confess "You must pass a variable name";

            my $sigil = substr($variable, 0, 1, '');

            if (exists $SIGIL_MAP{$sigil}) {
                @ret = ($variable, $sigil, $SIGIL_MAP{$sigil});
            }
            else {
                @ret = ("${sigil}${variable}", '', $SIGIL_MAP{''});
            }
        }

        # XXX in pure perl, this will access things in inner packages,
        # in xs, this will segfault - probably look more into this at
        # some point
        ($ret[0] !~ /::/)
            || confess "Variable names may not contain ::";

        return @ret;
    }
}

sub _valid_for_type {
    my ($value, $type) = @_;
    if ($type eq 'HASH' || $type eq 'ARRAY'
     || $type eq 'IO'   || $type eq 'CODE') {
        return reftype($value) eq $type;
    }
    else {
        my $ref = reftype($value);
        return !defined($ref) || $ref eq 'SCALAR' || $ref eq 'REF' || $ref eq 'LVALUE' || $ref eq 'REGEXP' || $ref eq 'VSTRING';
    }
}

sub add_symbol {
    my ($self, $variable, $initial_value, %opts) = @_;

    my ($name, $sigil, $type) = _deconstruct_variable_name($variable);

    if (@_ > 2) {
        _valid_for_type($initial_value, $type)
            || confess "$initial_value is not of type $type";

        # cheap fail-fast check for PERLDBf_SUBLINE and '&'
        if ($^P and $^P & 0x10 && $sigil eq '&') {
            my $filename = $opts{filename};
            my $first_line_num = $opts{first_line_num};

            (undef, $filename, $first_line_num) = caller
                if not defined $filename;

            my $last_line_num = $opts{last_line_num} || ($first_line_num ||= 0);

            # http://perldoc.perl.org/perldebguts.html#Debugger-Internals
            $DB::sub{$self->name . '::' . $name} = "$filename:$first_line_num-$last_line_num";
        }
    }

    if (BROKEN_GLOB_ASSIGNMENT) {
        if (@_ > 2) {
            no strict 'refs';
            no warnings 'redefine';
            *{ $self->name . '::' . $name } = ref $initial_value
                ? $initial_value : \$initial_value;
        }
        else {
            no strict 'refs';
            if (BROKEN_ISA_ASSIGNMENT && $name eq 'ISA') {
                *{ $self->name . '::' . $name };
            }
            else {
                my $undef = _undef_ref_for_type($type);
                *{ $self->name . '::' . $name } = $undef;
            }
        }
    }
    else {
        my $namespace = $self->namespace;
        {
            # using glob aliasing instead of Symbol::gensym, because otherwise,
            # magic doesn't get applied properly.
            # see <20120710063744.19360.qmail@lists-nntp.develooper.com> on p5p
            local *__ANON__:: = $namespace;
            no strict 'refs';
            no warnings 'void';
            no warnings 'once';
            *{"__ANON__::$name"};
        }

        if (@_ > 2) {
            no warnings 'redefine';
            *{ $namespace->{$name} } = ref $initial_value
                ? $initial_value : \$initial_value;
        }
        else {
            return if BROKEN_ISA_ASSIGNMENT && $name eq 'ISA';
            *{ $namespace->{$name} } = _undef_ref_for_type($type);
        }
    }
}

sub _undef_ref_for_type {
    my ($type) = @_;

    if ($type eq 'ARRAY') {
        return [];
    }
    elsif ($type eq 'HASH') {
        return {};
    }
    elsif ($type eq 'SCALAR') {
        return \undef;
    }
    elsif ($type eq 'IO') {
        return Symbol::geniosym;
    }
    elsif ($type eq 'CODE') {
        confess "Don't know how to vivify CODE variables";
    }
    else {
        confess "Unknown type $type in vivication";
    }
}

sub remove_glob {
    my ($self, $name) = @_;
    delete $self->namespace->{$name};
}

sub has_symbol {
    my ($self, $variable) = @_;

    my ($name, $sigil, $type) = _deconstruct_variable_name($variable);

    my $namespace = $self->namespace;

    return unless exists $namespace->{$name};

    my $entry_ref = \$namespace->{$name};
    if (reftype($entry_ref) eq 'GLOB') {
        if ($type eq 'SCALAR') {
            if (BROKEN_SCALAR_INITIALIZATION) {
                return defined ${ *{$entry_ref}{$type} };
            }
            else {
                my $sv = B::svref_2object($entry_ref)->SV;
                return $sv->isa('B::SV')
                    || ($sv->isa('B::SPECIAL')
                     && $B::specialsv_name[$$sv] ne 'Nullsv');
            }
        }
        else {
            return defined *{$entry_ref}{$type};
        }
    }
    else {
        # a symbol table entry can be -1 (stub), string (stub with prototype),
        # or reference (constant)
        return $type eq 'CODE';
    }
}

sub get_symbol {
    my ($self, $variable, %opts) = @_;

    my ($name, $sigil, $type) = _deconstruct_variable_name($variable);

    my $namespace = $self->namespace;

    if (!exists $namespace->{$name}) {
        if ($opts{vivify}) {
            $self->add_symbol($variable);
        }
        else {
            return undef;
        }
    }

    my $entry_ref = \$namespace->{$name};

    if (ref($entry_ref) eq 'GLOB') {
        return *{$entry_ref}{$type};
    }
    else {
        if ($type eq 'CODE') {
            if (BROKEN_GLOB_ASSIGNMENT || defined($self->{package})) {
                no strict 'refs';
                return \&{ $self->name . '::' . $name };
            }

            # XXX we should really be able to support arbitrary anonymous
            # stashes here... (not just via Package::Anon)
            if (blessed($namespace) && $namespace->isa('Package::Anon')) {
                # ->can will call gv_init for us, which inflates the glob
                # don't know how to do this in general
                $namespace->bless(\(my $foo))->can($name);
            }
            else {
                confess "Don't know how to inflate a " . ref($entry_ref)
                      . " into a full coderef (perhaps you could use"
                      . " Package::Anon instead of a bare stash?)"
            }

            return *{ $namespace->{$name} }{CODE};
        }
        else {
            return undef;
        }
    }
}

sub get_or_add_symbol {
    my $self = shift;
    $self->get_symbol(@_, vivify => 1);
}

sub remove_symbol {
    my ($self, $variable) = @_;

    my ($name, $sigil, $type) = _deconstruct_variable_name($variable);

    # FIXME:
    # no doubt this is grossly inefficient and
    # could be done much easier and faster in XS

    my %desc = (
        SCALAR => { sigil => '$', type => 'SCALAR', name => $name },
        ARRAY  => { sigil => '@', type => 'ARRAY',  name => $name },
        HASH   => { sigil => '%', type => 'HASH',   name => $name },
        CODE   => { sigil => '&', type => 'CODE',   name => $name },
        IO     => { sigil => '',  type => 'IO',     name => $name },
    );
    confess "This should never ever ever happen" if !$desc{$type};

    my @types_to_store = grep { $type ne $_ && $self->has_symbol($desc{$_}) }
                              keys %desc;
    my %values = map { $_, $self->get_symbol($desc{$_}) } @types_to_store;

    $values{SCALAR} = $self->get_symbol($desc{SCALAR})
      if !defined $values{SCALAR}
        && $type ne 'SCALAR'
        && BROKEN_SCALAR_INITIALIZATION;

    $self->remove_glob($name);

    $self->add_symbol($desc{$_} => $values{$_})
        for grep { defined $values{$_} } keys %values;
}

sub list_all_symbols {
    my ($self, $type_filter) = @_;

    my $namespace = $self->namespace;
    if (HAS_ISA_CACHE) {
        return grep { $_ ne '::ISA::CACHE::' } keys %{$namespace}
            unless defined $type_filter;
    }
    else {
        return keys %{$namespace}
            unless defined $type_filter;
    }

    # NOTE:
    # or we can filter based on
    # type (SCALAR|ARRAY|HASH|CODE)
    if ($type_filter eq 'CODE') {
        return grep {
            # any non-typeglob in the symbol table is a constant or stub
            ref(\$namespace->{$_}) ne 'GLOB'
                # regular subs are stored in the CODE slot of the typeglob
                || defined(*{$namespace->{$_}}{CODE})
        } keys %{$namespace};
    }
    elsif ($type_filter eq 'SCALAR') {
        return grep {
            !(HAS_ISA_CACHE && $_ eq '::ISA::CACHE::') &&
            (BROKEN_SCALAR_INITIALIZATION
                ? (ref(\$namespace->{$_}) eq 'GLOB'
                      && defined(${*{$namespace->{$_}}{'SCALAR'}}))
                : (do {
                      my $entry = \$namespace->{$_};
                      ref($entry) eq 'GLOB'
                          && B::svref_2object($entry)->SV->isa('B::SV')
                  }))
        } keys %{$namespace};
    }
    else {
        return grep {
            ref(\$namespace->{$_}) eq 'GLOB'
                && defined(*{$namespace->{$_}}{$type_filter})
        } keys %{$namespace};
    }
}

sub get_all_symbols {
    my ($self, $type_filter) = @_;

    my $namespace = $self->namespace;
    return { %{$namespace} } unless defined $type_filter;

    return {
        map { $_ => $self->get_symbol({name => $_, type => $type_filter}) }
            $self->list_all_symbols($type_filter)
    }
}

__END__

=pod

=encoding UTF-8

=head1 NAME

Package::Stash::PP - Pure perl implementation of the Package::Stash API

=head1 VERSION

version 0.40

=head1 SYNOPSIS

  use Package::Stash;

=head1 DESCRIPTION

This is a backend for L<Package::Stash> implemented in pure perl, for those without a compiler or who would like to use this inline in scripts.

=head1 BUGS

=for stopwords TODO

=over 4

=item * remove_symbol also replaces the associated typeglob

This can cause unexpected behavior when doing manipulation at compile time -
removing subroutines will still allow them to be called from within the package
as subroutines (although they will not be available as methods). This can be
considered a feature in some cases (this is how L<namespace::clean> works, for
instance), but should not be relied upon - use C<remove_glob> directly if you
want this behavior.

=item * Some minor memory leaks

The pure perl implementation has a couple minor memory leaks (see the TODO
tests in t/20-leaks.t) that I'm having a hard time tracking down - these may be
core perl bugs, it's hard to tell.

=back

=head1 SEE ALSO

=over 4

=item * L<Class::MOP::Package>

This module is a factoring out of code that used to live here

=back

=for Pod::Coverage BROKEN_ISA_ASSIGNMENT
add_symbol
get_all_symbols
get_or_add_symbol
get_symbol
has_symbol
list_all_symbols
name
namespace
new
remove_glob

=head1 SUPPORT

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Package-Stash>
(or L<bug-Package-Stash@rt.cpan.org|mailto:bug-Package-Stash@rt.cpan.org>).

=head1 AUTHOR

Mostly copied from code from L<Class::MOP::Package>, by Stevan Little and the
Moose Cabal.

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2022 by Jesse Luehrs.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
