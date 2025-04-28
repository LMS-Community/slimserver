package Data::Dump::Filtered;

use Data::Dump ();
use Carp ();

use base 'Exporter';
our @EXPORT_OK = qw(add_dump_filter remove_dump_filter dump_filtered);

sub add_dump_filter {
    my $filter = shift;
    unless (ref($filter) eq "CODE") {
	Carp::croak("add_dump_filter argument must be a code reference");
    }
    push(@Data::Dump::FILTERS, $filter);
    return $filter;
}

sub remove_dump_filter {
    my $filter = shift;
    @Data::Dump::FILTERS = grep $_ ne $filter, @Data::Dump::FILTERS;
}

sub dump_filtered {
    my $filter = pop;
    if (defined($filter) && ref($filter) ne "CODE") {
	Carp::croak("Last argument to dump_filtered must be undef or a code reference");
    }
    local @Data::Dump::FILTERS = ($filter ? $filter : ());
    return &Data::Dump::dump;
}

1;

=head1 NAME

Data::Dump::Filtered - Pretty printing with filtering

=head1 DESCRIPTION

The following functions are provided:

=over

=item add_dump_filter( \&filter )

This registers a filter function to be used by the regular Data::Dump::dump()
function.  By default no filters are active.

Since registering filters has a global effect is might be more appropriate
to use the dump_filtered() function instead.

=item remove_dump_filter( \&filter )

Unregister the given callback function as filter callback.
This undoes the effect of L<add_filter>.

=item dump_filtered(..., \&filter )

Works like Data::Dump::dump(), but the last argument should
be a filter callback function.  As objects are visited the
filter callback is invoked at it might influence how objects are dumped.

Any filters registered with L<add_filter()> are ignored when
this interface is invoked.  Actually, passing C<undef> as \&filter
is allowed and C<< dump_filtered(..., undef) >> is the official way to
force unfiltered dumps.

=back

=head2 Filter callback

A filter callback is a function that will be invoked with 2 arguments;
a context object and reference to the object currently visited.  The return
value should either be a hash reference or C<undef>.

    sub filter_callback {
        my($ctx, $object_ref) = @_;
	...
	return { ... }
    }

If the filter callback returns C<undef> (or nothing) then normal
processing and formatting of the visited object happens.
If the filter callback returns a hash it might replace
or annotate the representation of the current object.

=head2 Filter context

The context object provide methods that can be used to determine what kind of
object is currently visited and where it's located.  The context object has the
following interface:

=over

=item $ctx->object_ref

Alternative way to obtain a reference to the current object

=item $ctx->class

If the object is blessed this return the class.  Returns ""
for objects not blessed.

=item $ctx->reftype

Returns what kind of object this is.  It's a string like "SCALAR",
"ARRAY", "HASH", "CODE",...

=item $ctx->is_ref

Returns true if a reference was provided.

=item $ctx->is_blessed

Returns true if the object is blessed.  Actually, this is just an alias
for C<< $ctx->class >>.

=item $ctx->is_array

Returns true if the object is an array

=item $ctx->is_hash

Returns true if the object is a hash

=item $ctx->is_scalar

Returns true if the object is a scalar (a string or a number)

=item $ctx->is_code

Returns true if the object is a function (aka subroutine)

=item $ctx->container_class

Returns the class of the innermost container that contains this object.
Returns "" if there is no blessed container.

=item $ctx->container_self

Returns an textual expression relative to the container object that names this
object.  The variable C<$self> in this expression is the container itself.

=item $ctx->object_isa( $class )

Returns TRUE if the current object is of the given class or is of a subclass.

=item $ctx->container_isa( $class )

Returns TRUE if the innermost container is of the given class or is of a
subclass.

=item $ctx->depth

Returns how many levels deep have we recursed into the structure (from the
original dump_filtered() arguments).

=item $ctx->expr

=item $ctx->expr( $top_level_name )

Returns an textual expression that denotes the current object.  In the
expression C<$var> is used as the name of the top level object dumped.  This
can be overridden by providing a different name as argument.

=back

=head2 Filter return hash

The following elements has significance in the returned hash:

=over

=item dump => $string

incorporate the given string as the representation for the
current value

=item object => $value

dump the given value instead of the one visited and passed in as $object.
Basically the same as specifying C<< dump => Data::Dump::dump($value) >>.

=item comment => $comment

prefix the value with the given comment string

=item bless => $class

make it look as if the current object is of the given $class
instead of the class it really has (if any).  The internals of the object
is dumped in the regular way.  The $class can be the empty string
to make Data::Dump pretend the object wasn't blessed at all.

=item hide_keys => ['key1', 'key2',...]

=item hide_keys => \&code

If the $object is a hash dump is as normal but pretend that the
listed keys did not exist.  If the argument is a function then
the function is called to determine if the given key should be
hidden.

=back

=head1 SEE ALSO

L<Data::Dump>
