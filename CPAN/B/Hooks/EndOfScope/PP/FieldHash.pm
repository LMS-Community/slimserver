# Implementation of a pure-perl on_scope_end for perls > 5.10
# (relies on Hash::Util:FieldHash)

package # hide from pause
  B::Hooks::EndOfScope::PP::FieldHash;

use strict;
use warnings;

our $VERSION = '0.28';

use Tie::Hash ();
use Hash::Util::FieldHash 'fieldhash';

# Here we rely on a combination of several behaviors:
#
# * %^H is deallocated on scope exit, so any references to it disappear
# * A lost weakref in a fieldhash causes the corresponding key to be deleted
# * Deletion of a key on a tied hash triggers DELETE
#
# Therefore the DELETE of a tied fieldhash containing a %^H reference will
# be the hook to fire all our callbacks.

fieldhash my %hh;
{
  package # hide from pause too
    B::Hooks::EndOfScope::PP::_TieHintHashFieldHash;
  our @ISA = ( 'Tie::StdHash' );  # in Tie::Hash, in core
  sub DELETE {
    my $ret = shift->SUPER::DELETE(@_);
    B::Hooks::EndOfScope::PP::__invoke_callback($_) for @$ret;
    $ret;
  }
}

sub on_scope_end (&) {
  $^H |= 0x020000;

  tie(%hh, 'B::Hooks::EndOfScope::PP::_TieHintHashFieldHash')
    unless tied %hh;

  push @{ $hh{\%^H} ||= [] }, $_[0];
}

1;
