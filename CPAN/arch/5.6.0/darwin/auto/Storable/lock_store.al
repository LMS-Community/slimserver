# NOTE: Derived from blib/lib/Storable.pm.
# Changes made here will be lost when autosplit again.
# See AutoSplit.pm.
package Storable;

#line 160 "blib/lib/Storable.pm (autosplit into blib/lib/auto/Storable/lock_store.al)"
#
# lock_store
#
# Same as store, but flock the file first (advisory locking).
#
sub lock_store {
	return _store(\&pstore, @_, 1);
}

# end of Storable::lock_store
1;
