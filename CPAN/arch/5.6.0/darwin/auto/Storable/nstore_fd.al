# NOTE: Derived from blib/lib/Storable.pm.
# Changes made here will be lost when autosplit again.
# See AutoSplit.pm.
package Storable;

#line 221 "blib/lib/Storable.pm (autosplit into blib/lib/auto/Storable/nstore_fd.al)"
#
# nstore_fd
#
# Same as store_fd, but in network order.
#
sub nstore_fd {
	my ($self, $file) = @_;
	return _store_fd(\&net_pstore, @_);
}

# end of Storable::nstore_fd
1;
