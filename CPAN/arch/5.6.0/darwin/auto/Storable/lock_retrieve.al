# NOTE: Derived from blib/lib/Storable.pm.
# Changes made here will be lost when autosplit again.
# See AutoSplit.pm.
package Storable;

#line 294 "blib/lib/Storable.pm (autosplit into blib/lib/auto/Storable/lock_retrieve.al)"
#
# lock_retrieve
#
# Same as retrieve, but with advisory locking.
#
sub lock_retrieve {
	_retrieve($_[0], 1);
}

# end of Storable::lock_retrieve
1;
