# NOTE: Derived from blib/lib/Storable.pm.
# Changes made here will be lost when autosplit again.
# See AutoSplit.pm.
package Storable;

#line 212 "blib/lib/Storable.pm (autosplit into blib/lib/auto/Storable/store_fd.al)"
#
# store_fd
#
# Same as store, but perform on an already opened file descriptor instead.
# Returns undef if an I/O error occurred.
#
sub store_fd {
	return _store_fd(\&pstore, @_);
}

# end of Storable::store_fd
1;
