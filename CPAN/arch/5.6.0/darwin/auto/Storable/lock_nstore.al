# NOTE: Derived from blib/lib/Storable.pm.
# Changes made here will be lost when autosplit again.
# See AutoSplit.pm.
package Storable;

#line 169 "blib/lib/Storable.pm (autosplit into blib/lib/auto/Storable/lock_nstore.al)"
#
# lock_nstore
#
# Same as nstore, but flock the file first (advisory locking).
#
sub lock_nstore {
	return _store(\&net_pstore, @_, 1);
}

# end of Storable::lock_nstore
1;
