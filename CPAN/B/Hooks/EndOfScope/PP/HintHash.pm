# Implementation of a pure-perl on_scope_end for perls < 5.10
# (relies on lack of compile/runtime duality of %^H before 5.10
# which makes guard object operation possible)

package # hide from the pauses
  B::Hooks::EndOfScope::PP::HintHash;

use strict;
use warnings;

our $VERSION = '0.28';

use Scalar::Util ();
use constant _NEEDS_MEMORY_CORRUPTION_FIXUP => (
  "$]" >= 5.008
    and
  "$]" < 5.008004
) ? 1 : 0;


use constant _PERL_VERSION => "$]";

# This is the original implementation, which sadly is broken
# on perl 5.10+ within string evals
sub on_scope_end (&) {

  # the scope-implicit %^H localization is a 5.8+ feature
  $^H |= 0x020000
    if _PERL_VERSION >= 5.008;

  # the explicit localization of %^H works on anything < 5.10
  # but we use it only on 5.6 where fiddling $^H has no effect
  local %^H = %^H
    if _PERL_VERSION < 5.008;

  # Workaround for memory corruption during implicit $^H-induced
  # localization of %^H on 5.8.0~5.8.3, see extended comment below
  bless \%^H, 'B::Hooks::EndOfScope::PP::HintHash::__GraveyardTransport' if (
    _NEEDS_MEMORY_CORRUPTION_FIXUP
      and
    ref \%^H eq 'HASH'  # only bless if it is a "pure hash" to start with
  );

  # localised %^H behaves funny on 5.8 - a
  # 'local %^H;'
  # is in effect the same as
  # 'local %^H = %^H;'
  # therefore make sure we use different keys so that things do not
  # fire too early due to hashkey overwrite
  push @{
    $^H{sprintf '__B_H_EOS__guardstack_0X%x', Scalar::Util::refaddr(\%^H) }
      ||= bless ([], 'B::Hooks::EndOfScope::PP::_SG_STACK')
  }, $_[0];
}

sub B::Hooks::EndOfScope::PP::_SG_STACK::DESTROY {
  B::Hooks::EndOfScope::PP::__invoke_callback($_) for @{$_[0]};
}

# This scope implements a clunky yet effective workaround for a core perl bug
# https://rt.perl.org/Public/Bug/Display.html?id=27040#txn-82797
#
# While we can not prevent the hinthash being marked for destruction twice,
# we *can* intercept the first DESTROY pass, and squirrel away the entire
# structure, until a time it can (hopefully) no longer do any visible harm
#
# There still *will* be corruption by the time we get to free it for real,
# since we can not prevent Perl's erroneous SAVEFREESV mark. What we hope is
# that by then the corruption will no longer matter
#
# Yes, this code does leak by design. Yes it is better than the alternative.
{
  my @Hint_Hash_Graveyard;

  # "Leak" this entire structure: ensures it and its contents will not be
  # garbage collected until the very very very end
  push @Hint_Hash_Graveyard, \@Hint_Hash_Graveyard
    if _NEEDS_MEMORY_CORRUPTION_FIXUP;

  sub B::Hooks::EndOfScope::PP::HintHash::__GraveyardTransport::DESTROY {

    # Resurrect the hinthash being destroyed, persist it into the graveyard
    push @Hint_Hash_Graveyard, $_[0];

    # ensure we won't try to re-resurrect during GlobalDestroy
    bless $_[0], 'B::Hooks::EndOfScope::PP::HintHash::__DeactivateGraveyardTransport';

    # Perform explicit free of elements (if any) triggering all callbacks
    # This is what would have happened without this code being active
    %{$_[0]} = ();
  }
}

1;
