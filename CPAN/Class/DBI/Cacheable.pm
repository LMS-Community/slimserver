package Class::DBI::Cacheable;

use strict;
use warnings;
use base qw( Class::DBI::ObjectCache Class::DBI );
use CLASS;

our $VERSION = sprintf '%2d.%02d', q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/;

=head1 NAME

Class::DBI::Cacheable - Class::DBI object cache framework

=head1 SYNOPSIS

    package YourApp::DB;
    use base 'Class::DBI::Cacheable';
    __PACKAGE__->set_db( Main => 'dbi:Pg:dbname=database', 'username', 'password' );

=head1 DESCRIPTION

Class::DBI::Cacheable transparently acts as a cacheing wrapper around L<Class::DBI>, storing
retrieved and created data in a local object cache, and returning data out of the cache
wherever possible.

Intended for better performance of L<Class::DBI>-based applications, this can prevent unnecessary
database queries by using previously-retrieved object data rather than having to go to the
database server every time a object is retrieved.

It is highly configurable so you can customize both on an per-application and per-class basis
the directory root where objects are stored, expire times, and other important parameters.

=head1 Method Reference

=cut

=head2 CLASS->retrieve( [args] )

This method overrides the C<retrieve()> method of L<Class::DBI>, and adds
caching capabilities.  It first constructs a cache key from the supplied
arguments, and tries to retrieve that object from the data store.  If a
valid object is returned, that is given to the caller and the entire
L<Class::DBI>->retrieve method is bypassed.

However, in the event the object does not exist in the cache, Class::DBI
is used to retrieve the object.

=cut

sub retrieve {
    my $class = shift;

    my $key = $class->getCacheKey(\@_);
    if ($class->can('getCache')) {
        my $obj = $class->getCache($key);
        return $obj if (defined($obj));
    }

    return $class->SUPER::retrieve(@_);
}

=head2 CLASS->construct(data)

This method overrides the C<construct()> method of L<Class::DBI>, which is responsible
for constructing an object from searched or otherwise retrieved database data.  This
method circumvents this system to try and retrieve a cached object first.  Next, the
real C<construct()> method is called, after which this data is then stored in the cache.

=cut

sub construct {
    my $class = shift;
    my $data = shift;

    if ($class->can('getCache')) {
        my $obj = $class->getCache($data);
        if (defined($obj)) {
            return $obj;
        }
    }

    my $obj = $class->SUPER::construct($data);
    $obj->setCache() if ($obj->can('setCache'));
    return $obj;
}

=head2 CLASS->update([args])

This simple wrapper around L<Class::DBI>'s C<update()> method simply passes the
update action on to L<Class::DBI>, after which the object is refreshed in the
cache.  This ensures that, if database data is altered, the cache will always
accurately reflect the database contents.

Note: this will only work properly when updates are made through L<Class::DBI::Cachable>.
If changes are made to the database via direct SQL calls the cache will be out-of-sync
with the real database.

=cut

sub update {
    my $self = shift;
    my $key = $self->getCacheKey;
    my $result = $self->SUPER::update(@_);
    $self->setCache($key);
    return $result;
}

=head1 TIPS AND USAGE NOTES

Most customization for this package is possible by overriding the class
methods exposed by L<Class::DBI::ObjectCache>, so visit the documentation
for that class to see what all can be changed and customized.

=head2 USE A DIFFERENT CACHE_ROOT FOR EACH APPLICATION

By overriding C<CACHE_ROOT> in the base class used to connect to your
database, you can indicate a separate cache directory for each of your
database connections.  In this way, if you need to perform debugging,
you are changing database contents outside of your framework, or you
simply are not certain if you have some old and tainted data in the
cache, you can remove the entire directory structure to start from a
clean slate.

=head2 OVERRIDE EXPIRES FOR YOUR OBJECTS

If you have data that can change often, override the C<EXPIRES> class
method in your perl modules.  Anything within your framework, if your
base class inherits from this module, can override C<EXPIRES>.  In fact,
by putting logic inside the C<EXPIRES> method for one of your classes,
you can return different expirey times depending on the values stored
in the object.

=head1 SEE ALSO

L<Class::DBI::ObjectCache>, L<Class::DBI>, L<Cache::Cache>

=head1 AUTHOR

Michael A Nachbaur, E<lt>mike@nachbaur.comE<gt>

=head1 COPYRIGHT AND LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
