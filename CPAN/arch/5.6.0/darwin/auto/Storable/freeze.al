# NOTE: Derived from blib/lib/Storable.pm.
# Changes made here will be lost when autosplit again.
# See AutoSplit.pm.
package Storable;

#line 251 "blib/lib/Storable.pm (autosplit into blib/lib/auto/Storable/freeze.al)"
#
# freeze
#
# Store oject and its hierarchy in memory and return a scalar
# containing the result.
#
sub freeze {
	_freeze(\&mstore, @_);
}

# end of Storable::freeze
1;
