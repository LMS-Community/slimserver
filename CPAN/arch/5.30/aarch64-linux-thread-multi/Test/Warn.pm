=head1 NAME

Test::Warn - Perl extension to test methods for warnings

=head1 SYNOPSIS

  use Test::Warn;

  warning_is    {foo(-dri => "/")} "Unknown Parameter 'dri'", "dri != dir gives warning";
  warnings_are  {bar(1,1)} ["Width very small", "Height very small"];

  warning_is    {add(2,2)} undef, "No warnings for calc 2+2"; # or
  warnings_are  {add(2,2)} [],    "No warnings for calc 2+2"; # what reads better :-)

  warning_like  {foo(-dri => "/")} qr/unknown param/i, "an unknown parameter test";
  warnings_like {bar(1,1)} [qr/width.*small/i, qr/height.*small/i];

  warning_is    {foo()} {carped => "didn't found the right parameters"};
  warnings_like {foo()} [qr/undefined/,qr/undefined/,{carped => qr/no result/i}];

  warning_like {foo(undef)}                 'uninitialized';
  warning_like {bar(file => '/etc/passwd')} 'io';

  warning_like {eval q/"$x"; $x;/} 
               [qw/void uninitialized/], 
               "some warnings at compile time";

  warnings_exist {...} [qr/expected warning/], "Expected warning is thrown";

=head1 DESCRIPTION

A good style of Perl programming calls for a lot of diverse regression tests.

This module provides a few convenience methods for testing warning based code.

If you are not already familiar with the Test::More manpage 
now would be the time to go take a look.

=head2 FUNCTIONS

=over 4

=item warning_is BLOCK STRING, TEST_NAME

Tests that BLOCK gives exactly the one specified warning.
The test fails if the BLOCK warns more then one times or doesn't warn.
If the string is undef, 
then the tests succeeds if the BLOCK doesn't give any warning.
Another way to say that there aren't any warnings in the block,
is C<warnings_are {foo()} [], "no warnings in">.

If you want to test for a warning given by carp,
You have to write something like:
C<warning_is {carp "msg"} {carped =E<gt> 'msg'}, "Test for a carped warning">.
The test will fail,
if a "normal" warning is found instead of a "carped" one.

Note: C<warn "foo"> would print something like C<foo at -e line 1>. 
This method ignores everything after the at. That means, to match this warning
you would have to call C<warning_is {warn "foo"} "foo", "Foo succeeded">.
If you need to test for a warning at an exactly line,
try better something like C<warning_like {warn "foo"} qr/at XYZ.dat line 5/>.

warning_is and warning_are are only aliases to the same method.
So you also could write
C<warning_is {foo()} [], "no warning"> or something similar.
I decided to give two methods to have some better readable method names.

A true value is returned if the test succeeds, false otherwise.

The test name is optional, but recommended.


=item warnings_are BLOCK ARRAYREF, TEST_NAME

Tests to see that BLOCK gives exactly the specified warnings.
The test fails if the BLOCK warns a different number than the size of the ARRAYREf
would have expected.
If the ARRAYREF is equal to [], 
then the test succeeds if the BLOCK doesn't give any warning.

Please read also the notes to warning_is as these methods are only aliases.

If you want more than one tests for carped warnings look that way:
C<warnings_are {carp "c1"; carp "c2"} {carped => ['c1','c2'];> or
C<warnings_are {foo()} ["Warning 1", {carped => ["Carp 1", "Carp 2"]}, "Warning 2"]>.
Note that C<{carped => ...}> has always to be a hash ref.

=item warning_like BLOCK REGEXP, TEST_NAME

Tests that BLOCK gives exactly one warning and it can be matched to the given regexp.
If the string is undef, 
then the tests succeeds iff the BLOCK doesn't give any warning.

The REGEXP is matched after the whole warn line,
which consists in general of "WARNING at __FILE__ line __LINE__".
So you can check for a warning in at File Foo.pm line 5 with
C<warning_like {bar()} qr/at Foo.pm line 5/, "Testname">.
I don't know whether it's sensful to do such a test :-(
However, you should be prepared as a matching with 'at', 'file', '\d'
or similar will always pass. 
Think to the qr/^foo/ if you want to test for warning "foo something" in file foo.pl.

You can also write the regexp in a string as "/.../"
instead of using the qr/.../ syntax.
Note that the slashes are important in the string,
as strings without slashes are reserved for warning categories
(to match warning categories as can be seen in the perllexwarn man page).

Similar to C<warning_is>,
you can test for warnings via C<carp> with:
C<warning_like {bar()} {carped => qr/bar called too early/i};>

Similar to C<warning_is>/C<warnings_are>,
C<warning_like> and C<warnings_like> are only aliases to the same methods.

A true value is returned if the test succeeds, false otherwise.

The test name is optional, but recommended.

=item warning_like BLOCK STRING, TEST_NAME

Tests whether a BLOCK gives exactly one warning of the passed category.
The categories are grouped in a tree,
like it is expressed in perllexwarn.
Note, that they have the hierarchical structure from perl 5.8.0,
wich has a little bit changed to 5.6.1 or earlier versions
(You can access the internal used tree with C<$Test::Warn::Categorization::tree>, 
although I wouldn't recommend it)

Thanks to the grouping in a tree,
it's simple possible to test for an 'io' warning,
instead for testing for a 'closed|exec|layer|newline|pipe|unopened' warning.

Note, that warnings occuring at compile time,
can only be catched in an eval block. So

  warning_like {eval q/"$x"; $x;/} 
               [qw/void uninitialized/], 
               "some warnings at compile time";

will work,
while it wouldn't work without the eval.

Note, that it isn't possible yet,
to test for own categories,
created with warnings::register.

=item warnings_like BLOCK ARRAYREF, TEST_NAME

Tests to see that BLOCK gives exactly the number of the specified warnings
and all the warnings have to match in the defined order to the 
passed regexes.

Please read also the notes to warning_like as these methods are only aliases.

Similar to C<warnings_are>,
you can test for multiple warnings via C<carp>
and for warning categories, too:

  warnings_like {foo()} 
                [qr/bar warning/,
                 qr/bar warning/,
                 {carped => qr/bar warning/i},
                 'io'
                ],
                "I hope, you'll never have to write a test for so many warnings :-)";

=item warnings_exist BLOCK STRING|ARRAYREF, TEST_NAME

Same as warning_like, but will warn() all warnings that do not match the supplied regex/category,
instead of registering an error. Use this test when you just want to make sure that specific
warnings were generated, and couldn't care less if other warnings happened in the same block
of code.

  warnings_exist {...} [qr/expected warning/], "Expected warning is thrown";

  warnings_exist {...} ['uninitialized'], "Expected warning is thrown";

=back

=head2 EXPORT

C<warning_is>,
C<warnings_are>,
C<warning_like>,
C<warnings_like>,
C<warnings_exist> by default.

=head1 BUGS

Please note that warnings with newlines inside are making a lot of trouble.
The only sensible way to handle them is to use are the C<warning_like> or
C<warnings_like> methods. Background for these problems is that there is no
really secure way to distinguish between warnings with newlines and a tracing
stacktrace.

If a method has it's own warn handler,
overwriting C<$SIG{__WARN__}>,
my test warning methods won't get these warnings.

The C<warning_like BLOCK CATEGORY, TEST_NAME> method isn't extremely tested.
Please use this calling style with higher attention and
tell me if you find a bug.

=head1 TODO

Improve this documentation.

The code has some parts doubled - especially in the test scripts.
This is really awkward and has to be changed.

Please feel free to suggest me any improvements.

=head1 SEE ALSO

Have a look to the similar L<Test::Exception> module. Test::Trap

=head1 THANKS

Many thanks to Adrian Howard, chromatic and Michael G. Schwern,
who have given me a lot of ideas.

=head1 AUTHOR

Janek Schleicher, E<lt>bigj AT kamelfreund.deE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2002 by Janek Schleicher

Copyright 2007-2011 by Alexandr Ciornii, L<http://chorny.net/>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut


package Test::Warn;

use 5.006;
use strict;
use warnings;

#use Array::Compare;
use Sub::Uplevel 0.12;

our $VERSION = '0.23';

require Exporter;

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw(
    @EXPORT	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
    warning_is   warnings_are
    warning_like warnings_like
    warnings_exist
);

use Test::Builder;
my $Tester = Test::Builder->new;

{
no warnings 'once';
*warning_is = *warnings_are;
*warning_like = *warnings_like;
}

sub warnings_are (&$;$) {
    my $block       = shift;
    my @exp_warning = map {_canonical_exp_warning($_)}
                          _to_array_if_necessary( shift() || [] );
    my $testname    = shift;
    my @got_warning = ();
    local $SIG{__WARN__} = sub {
        my ($called_from) = caller(0);  # to find out Carping methods
        push @got_warning, _canonical_got_warning($called_from, shift());
    };
    uplevel 1,$block;
    my $ok = _cmp_is( \@got_warning, \@exp_warning );
    $Tester->ok( $ok, $testname );
    $ok or _diag_found_warning(@got_warning),
           _diag_exp_warning(@exp_warning);
    return $ok;
}


sub warnings_like (&$;$) {
    my $block       = shift;
    my @exp_warning = map {_canonical_exp_warning($_)}
                          _to_array_if_necessary( shift() || [] );
    my $testname    = shift;
    my @got_warning = ();
    local $SIG{__WARN__} = sub {
        my ($called_from) = caller(0);  # to find out Carping methods
        push @got_warning, _canonical_got_warning($called_from, shift());
    };
    uplevel 1,$block;
    my $ok = _cmp_like( \@got_warning, \@exp_warning );
    $Tester->ok( $ok, $testname );
    $ok or _diag_found_warning(@got_warning),
           _diag_exp_warning(@exp_warning);
    return $ok;
}

sub warnings_exist (&$;$) {
    my $block       = shift;
    my @exp_warning = map {_canonical_exp_warning($_)}
                          _to_array_if_necessary( shift() || [] );
    my $testname    = shift;
    my @got_warning = ();
    local $SIG{__WARN__} = sub {
        my ($called_from) = caller(0);  # to find out Carping methods
        my $wrn_text=shift;
        my $wrn_rec=_canonical_got_warning($called_from, $wrn_text);
        foreach my $wrn (@exp_warning) {
          if (_cmp_got_to_exp_warning_like($wrn_rec,$wrn)) {
            push @got_warning, $wrn_rec;
            return;
          }
        }
        warn $wrn_text;
    };
    uplevel 1,$block;
    my $ok = _cmp_like( \@got_warning, \@exp_warning );
    $Tester->ok( $ok, $testname );
    $ok or _diag_found_warning(@got_warning),
           _diag_exp_warning(@exp_warning);
    return $ok;
}


sub _to_array_if_necessary {
    return (ref($_[0]) eq 'ARRAY') ? @{$_[0]} : ($_[0]);
}

sub _canonical_got_warning {
    my ($called_from, $msg) = @_;
    my $warn_kind = $called_from eq 'Carp' ? 'carped' : 'warn';
    my @warning_stack = split /\n/, $msg;     # some stuff of uplevel is included
    return {$warn_kind => $warning_stack[0]}; # return only the real message
}

sub _canonical_exp_warning {
    my ($exp) = @_;
    if (ref($exp) eq 'HASH') {             # could be {carped => ...}
        my $to_carp = $exp->{carped} or return; # undefined message are ignored
        return (ref($to_carp) eq 'ARRAY')  # is {carped => [ ..., ...] }
            ? map({ {carped => $_} } grep {defined $_} @$to_carp)
            : +{carped => $to_carp};
    }
    return {warn => $exp};
}

sub _cmp_got_to_exp_warning {
    my ($got_kind, $got_msg) = %{ shift() };
    my ($exp_kind, $exp_msg) = %{ shift() };
    return 0 if ($got_kind eq 'warn') && ($exp_kind eq 'carped');
    my $cmp = $got_msg =~ /^\Q$exp_msg\E at .+ line \d+\.?$/;
    return $cmp;
}

sub _cmp_got_to_exp_warning_like {
    my ($got_kind, $got_msg) = %{ shift() };
    my ($exp_kind, $exp_msg) = %{ shift() };
    return 0 if ($got_kind eq 'warn') && ($exp_kind eq 'carped');
    if (my $re = $Tester->maybe_regex($exp_msg)) { #qr// or '//'
        my $cmp = $got_msg =~ /$re/;
        return $cmp;
    } else {
        return Test::Warn::Categorization::warning_like_category($got_msg,$exp_msg);
    }
}


sub _cmp_is {
    my @got  = @{ shift() };
    my @exp  = @{ shift() };
    scalar @got == scalar @exp or return 0;
    my $cmp = 1;
    $cmp &&= _cmp_got_to_exp_warning($got[$_],$exp[$_]) for (0 .. $#got);
    return $cmp;
}

sub _cmp_like {
    my @got  = @{ shift() };
    my @exp  = @{ shift() };
    scalar @got == scalar @exp or return 0;
    my $cmp = 1;
    $cmp &&= _cmp_got_to_exp_warning_like($got[$_],$exp[$_]) for (0 .. $#got);
    return $cmp;
}

sub _diag_found_warning {
    foreach (@_) {
        if (ref($_) eq 'HASH') {
            ${$_}{carped} ? $Tester->diag("found carped warning: ${$_}{carped}")
                          : $Tester->diag("found warning: ${$_}{warn}");
        } else {
            $Tester->diag( "found warning: $_" );
        }
    }
    $Tester->diag( "didn't find a warning" ) unless @_;
}

sub _diag_exp_warning {
    foreach (@_) {
        if (ref($_) eq 'HASH') {
            ${$_}{carped} ? $Tester->diag("expected to find carped warning: ${$_}{carped}")
                          : $Tester->diag("expected to find warning: ${$_}{warn}");
        } else {
            $Tester->diag( "expected to find warning: $_" );
        }
    }
    $Tester->diag( "didn't expect to find a warning" ) unless @_;
}

package Test::Warn::DAG_Node_Tree;

use strict;
use warnings;
use base 'Tree::DAG_Node';


sub nice_lol_to_tree {
    my $class = shift;
    $class->new(
    {
        name      => shift(),
        daughters => [_nice_lol_to_daughters(shift())]
    });
}

sub _nice_lol_to_daughters {
    my @names = @{ shift() };
    my @daughters = ();
    my $last_daughter = undef;
    foreach (@names) {
        if (ref($_) ne 'ARRAY') {
            $last_daughter = Tree::DAG_Node->new({name => $_});
            push @daughters, $last_daughter;
        } else {
            $last_daughter->add_daughters(_nice_lol_to_daughters($_));
        }
    }
    return @daughters;
}

sub depthsearch {
    my ($self, $search_name) = @_;
    my $found_node = undef;
    $self->walk_down({callback => sub {
        my $node = shift();
        $node->name eq $search_name and $found_node = $node,!"go on";
        "go on with searching";
    }});
    return $found_node;
}

package Test::Warn::Categorization;

use Carp;

our $tree = Test::Warn::DAG_Node_Tree->nice_lol_to_tree(
   all => [ 'closure',
            'deprecated',
            'exiting',
            'glob',
            'io'           => [ 'closed',
                                'exec',
                                'layer',
                                'newline',
                                'pipe',
                                'unopened'
                              ],
            'misc',
            'numeric',
            'once',
            'overflow',
            'pack',
            'portable',
            'recursion',
            'redefine',
            'regexp',
            'severe'       => [ 'debugging',
                                'inplace',
                                'internal',
                                'malloc'
                              ],
            'signal',
            'substr',
            'syntax'       => [ 'ambiguous',
                                'bareword',
                                'digit',
                                'parenthesis',
                                'precedence',
                                'printf',
                                'prototype',
                                'qw',
                                'reserved',
                                'semicolon'
                              ],
            'taint',
            'threads',
            'uninitialized',
            'unpack',
            'untie',
            'utf8',
            'void',
            'y2k'
           ]
);

sub _warning_category_regexp {
    my $sub_tree = $tree->depthsearch(shift()) or return;
    my $re = join "|", map {$_->name} $sub_tree->leaves_under;
    return qr/(?=\w)$re/;
}

sub warning_like_category {
    my ($warning, $category) = @_;
    my $re = _warning_category_regexp($category) or 
        carp("Unknown warning category '$category'"),return;
    my $ok = $warning =~ /$re/;
    return $ok;
}
 
1;
