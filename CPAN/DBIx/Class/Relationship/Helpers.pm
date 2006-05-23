package # hide from PAUSE
    DBIx::Class::Relationship::Helpers;

use strict;
use warnings;

use base qw/DBIx::Class/;

__PACKAGE__->load_components(qw/
    Relationship::HasMany
    Relationship::HasOne
    Relationship::BelongsTo
    Relationship::ManyToMany
/);

1;
