# NOTE: Derived from blib/lib/Storable.pm.
# Changes made here will be lost when autosplit again.
# See AutoSplit.pm.
package Storable;

#line 260 "blib/lib/Storable.pm (autosplit into blib/lib/auto/Storable/nfreeze.al)"
#
# nfreeze
#
# Same as freeze but in network order.
#
sub nfreeze {
	_freeze(\&net_mstore, @_);
}

# end of Storable::nfreeze
1;
