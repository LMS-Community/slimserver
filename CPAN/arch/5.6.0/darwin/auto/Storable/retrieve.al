# NOTE: Derived from blib/lib/Storable.pm.
# Changes made here will be lost when autosplit again.
# See AutoSplit.pm.
package Storable;

#line 285 "blib/lib/Storable.pm (autosplit into blib/lib/auto/Storable/retrieve.al)"
#
# retrieve
#
# Retrieve object hierarchy from disk, returning a reference to the root
# object of that tree.
#
sub retrieve {
	_retrieve($_[0], 0);
}

# end of Storable::retrieve
1;
