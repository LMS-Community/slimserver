package # hide from PAUSE
    Package::Stash::Conflicts;

use strict;
use warnings;

# this module was generated with Dist::Zilla::Plugin::Conflicts 0.19

use Dist::CheckConflicts
    -dist      => 'Package::Stash',
    -conflicts => {
        'Class::MOP' => '1.08',
        'MooseX::Method::Signatures' => '0.36',
        'MooseX::Role::WithOverloading' => '0.08',
        'namespace::clean' => '0.18',
    },
    -also => [ qw(
        B
        Carp
        Dist::CheckConflicts
        Getopt::Long
        Module::Implementation
        Scalar::Util
        Symbol
        constant
        strict
        warnings
    ) ],

;

1;

# ABSTRACT: Provide information on conflicts for Package::Stash
# Dist::Zilla: -PodWeaver
