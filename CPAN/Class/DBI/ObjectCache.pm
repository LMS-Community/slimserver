package Class::DBI::ObjectCache;

use strict;
use warnings;
use Cache::Cache qw( $EXPIRES_NOW $EXPIRES_NEVER );
use Cache::FileCache;
use CLASS;

our $VERSION = sprintf '%2d.%02d', q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/;
our %CACHE_OBJ = ();

=head1 NAME

Class::DBI::ObjectCache - Object cache used by Class::DBI::Cacheable

=head1 SYNOPSIS

    package YourClass::Name;
    use base "Class::DBI::ObjectCache";

    sub get {
        my $self = shift;
        if ($self->can('getCache')) {
            my $obj = $self->getCache(@_);
            return $obj if (defined($obj));
        }
        # Do your magic to construct your object
    }

    sub set {
        my $self = shift;
        $self->setCache();
    }

=head1 DESCRIPTION

This method is a generic base-class used for storing and retrieving objects
to and from a L<Cache::Cache> framework.  This is extended by L<Class::DBI::Cacheable>
to provide transparent L<Class::DBI> caching support, though it can be used
for other types of objects as well.

=head1 Method Reference

=cut

=head2 CLASS->getCacheKey( [$data] )

This method composes a unique key to represent this cache with.  This
is used when storing the object in the cache, and for later retrieving
it.  

=cut

sub getCacheKey {
    my $class = shift;
    my $data = undef;
    if (ref($class)) {
        $data = $class;
        $class = ref($class);
    } else {
        $data = shift;
    }

    my @index_fields = ();
    # Attempt to pull the indexable fields from the class' index method
    if ($class->can('CACHE_INDEX')) {
        @index_fields = $class->CACHE_INDEX();
        @index_fields = @{$index_fields[0]} if (ref($index_fields[0]) eq 'ARRAY');
    }
    
    # Since that didn't work, check to see if this object is a Class::DBI
    # object, and retrieve the primary key columns from there.
    elsif ($class->isa('Class::DBI')) {
        @index_fields = sort $class->primary_columns;
        if (ref($data) eq 'ARRAY') {
            my @data_ary = @{$data};
            $data = {};
            foreach ($class->primary_columns) {
                $data->{$_} = shift @data_ary;
            }
        }
    }
    
    # None of that worked.  This seems to be a generic object that hasn't been
    # tuned for this framework.  Assume all the keys are primary keys, and index
    # based on that.
    else {
        @index_fields = sort keys %{$data};
    }

    # Derive the key values to use as the index, and compose a unique string
    # representing this object's state.
    my @key_values = ();
    foreach (@index_fields) {
        return undef unless (exists $data->{$_});
        push @key_values, $data->{$_};
    }
    my $key_str = join(':', @key_values);

    # Return a new cache key for this data
    my $key = new Nacho::Cachable::IndexKey(key => $key_str);
    return $key;
}


=head2 CLASS->getCache( $key )

This method attempts to retrieve an object with the given
key from the cache.  Returns undef if no valid value exists,
or if the supplied key is invalid.

=cut

sub getCache {
    my $class = shift;
    my $key = shift;
    $class = ref($class) if (ref($class));

    # If the supplied key is not a valid IndexKey object, retrieve
    # the cache key for it.
    unless (UNIVERSAL::isa($key, 'Nacho::Cachable::IndexKey')) {
        $key = $class->getCacheKey($key);
    }

    # If the key is valid, pull the value out of the local cache
    # and return what, if anything, it gives us.
    if (defined($key->{key})) {
        return unless defined($class->CACHE);
        return $class->CACHE->get($key->{key});
    }
    return undef;
}

=head2 $obj->setCache( [$key] )

Store this object in the cache with the optionally supplied key.
If no key is supplied, one is computed automatically.

=cut

sub setCache {
    my $self = shift;
    my $key = shift || $self->getCacheKey;

    return unless defined($self->CACHE);

    # Remove the old key first, since the contents may have changed.
    $self->CACHE->remove($key->{key});

    # Set the new key with the current object
    $self->CACHE->set($self->getCacheKey->{key}, $self, $self->EXPIRES());
}

=head2 CACHE()

Class method that stores and returns L<Cache::Cache> objects.

Note: This implementation
uses L<Cache::FileCache> to store objects in the cache framework.  If you want to use
some other back-end cache store, like a database or shared memory, subclass this
class and override this method.

=cut

sub CACHE {
    my $self = shift;
    my $class = ref($self) || $self;

    # To save time and effort, return a cache object that
    # had previously been constructed if one is available.
    return $CACHE_OBJ{$class} if (exists ($CACHE_OBJ{$class}));

    # Since no pre-defined cache object is available, construct
    # one using the class methods that define the root, etc.
    eval {
        $CACHE_OBJ{$class} = new Cache::FileCache({
            cache_root => $class->can('CACHE_ROOT')
                ? $class->CACHE_ROOT()
                : '/tmp/' . $CLASS,
            cache_depth => $class->can('CACHE_DEPTH')
                ? $class->CACHE_DEPTH()
                : 0,
            namespace => $class,
            default_expires_in  => $class->can('EXPIRES')
                ? $class->EXPIRES()
                : $EXPIRES_NEVER,
            auto_purge_interval => $class->can('CACHE_PURGE_INTERVAL')
                ? $class->CACHE_PURGE_INTERVAL()
                : 600,
            #max_size => $class->can('CACHE_SIZE')
            #    ? $class->CACHE_SIZE()
            #    : 20000,
        }) or return undef;
    };
    if ($@) {
        return undef;
    }

    # Return the cache object
    return $CACHE_OBJ{$class};
}

=head2 EXPIRES()

Indicates the default expire time for any object stored in the cache.  Override this in
your subclass to indicate specific expirey times.

Since this method is invoked every time an object is added to the datastore, you can return
different expire durations on a per-object basis, simply by implementing some logic in this
method.

Default: 600 seconds

=cut

sub EXPIRES {
    return 600;
}

=head2 CACHE_ROOT()

Indicates the directory where objects will be stored on disk.  Override this if you wish
different applications, classes or sets of classes to be stored in their own cache directory.

Default: /tmp/Object-Cache

=cut

sub CACHE_ROOT {
    return '/tmp/Object-Cache';
}

=head2 CACHE_DEPTH()

Indicates the directory depth that will be created for storing cached files.

Default: 4

=cut

sub CACHE_DEPTH {
    return 4;
}

package Nacho::Cachable::IndexKey;
sub new {
    my $pkg = shift;
    my $class = ref($pkg) || $pkg || __PACKAGE__;
    my %args = @_;
    my $self = {
        key => $args{key},
    };

    return bless $self, $class;
}

=head1 SEE ALSO

L<Class::DBI::Cacheable>, L<Cache::Cache>, L<Cache::FileCache>

=head1 AUTHOR

Michael A Nachbaur, E<lt>mike@nachbaur.comE<gt>

=head1 COPYRIGHT AND LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
1;
