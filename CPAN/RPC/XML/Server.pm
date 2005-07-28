###############################################################################
#
# This file copyright (c) 2001 by Randy J. Ray <rjray@blackperl.com>,
# all rights reserved
#
# Copying and distribution are permitted under the terms of the Artistic
# License as distributed with Perl versions 5.002 and later. See
# http://www.opensource.org/licenses/artistic-license.php
#
###############################################################################
#
#   $Id: Server.pm,v 1.43 2005/05/02 09:50:16 rjray Exp $
#
#   Description:    This class implements an RPC::XML server, using the core
#                   XML::RPC transaction code. The server may be created with
#                   or without an HTTP::Daemon object instance to answer the
#                   requests.
#
#   Functions:      new
#                   version
#                   url
#                   product_tokens
#                   started
#                   path
#                   host
#                   port
#                   requests
#                   response
#                   compress
#                   compress_thresh
#                   compress_re
#                   message_file_thresh
#                   message_temp_dir
#                   xpl_path
#                   add_method
#                   method_from_file
#                   get_method
#                   server_loop
#                   post_configure_hook
#                   pre_loop_hook
#                   process_request
#                   dispatch
#                   call
#                   add_default_methods
#                   add_methods_in_dir
#                   delete_method
#                   list_methods
#                   share_methods
#                   copy_methods
#                   timeout
#
#   Libraries:      AutoLoader
#                   HTTP::Daemon
#                   HTTP::Response
#                   HTTP::Status
#                   URI
#                   RPC::XML
#                   RPC::XML::Parser
#                   RPC::XML::Procedure
#
#   Global Consts:  $VERSION
#                   $INSTALL_DIR
#
###############################################################################

package RPC::XML::Server;

use 5.005;
use strict;
use vars qw($VERSION @ISA $INSTANCE $INSTALL_DIR @XPL_PATH);

use Carp 'carp';
use AutoLoader 'AUTOLOAD';
use File::Spec;

BEGIN {
    $INSTALL_DIR = (File::Spec->splitpath(__FILE__))[1];
    @XPL_PATH = ($INSTALL_DIR, File::Spec->curdir);
}

use HTTP::Status;
require HTTP::Response;
require URI;

use RPC::XML 'bytelength';
require RPC::XML::Parser;
require RPC::XML::Procedure;

$VERSION = do { my @r=(q$Revision: 1.43 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };

###############################################################################
#
#   Sub Name:       new
#
#   Description:    Create a new RPC::XML::Server object. This entails getting
#                   a HTTP::Daemon object, saving several internal values, and
#                   other operations.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $class    in      scalar    Ref or string for the class
#                   %args     in      hash      Additional arguments
#
#   Returns:        Success:    object reference
#                   Failure:    error string
#
###############################################################################
sub new
{
    my $class = shift;
    my %args = @_;

    my ($self, $http, $resp, $host, $port, $queue, $path, $URI, $srv_name,
        $srv_version, $timeout);

    $class = ref($class) || $class;
    $self = bless {}, $class;

    $srv_version = $args{server_version} || $self->version;
    $srv_name    = $args{server_name}    || $class;
    $self->{__version} = "$srv_name/$srv_version";

    if ($args{no_http})
    {
        $self->{__host} = $args{host} || '';
        $self->{__port} = $args{port} || '';
        delete @args{qw(host port)};
    }
    else
    {
        require HTTP::Daemon;

        $host = $args{host}   || '';
        $port = $args{port}   || '';
        $queue = $args{queue} || 5;
        $http = HTTP::Daemon->new(Reuse => 1,
                                  ($host ? (LocalHost => $host) : ()),
                                  ($port ? (LocalPort => $port) : ()),
                                  ($queue ? (Listen => $queue)  : ()));
        return "${class}::new: Unable to create HTTP::Daemon object"
            unless $http;
        $URI = URI->new($http->url);
        $self->{__host} = $URI->host;
        $self->{__port} = $URI->port;
        $self->{__daemon} = $http;

        # Remove those we've processed
        delete @args{qw(host port queue)};
    }
    $resp = HTTP::Response->new();
    return "${class}::new: Unable to create HTTP::Response object"
        unless $resp;
    $resp->header(# This is essentially the same string returned by the
                  # default "identity" method that may be loaded from a
                  # XPL file. But it hasn't been loaded yet, and may not
                  # be, hence we set it here (possibly from option values)
                  RPC_Server   => $self->{__version},
                  RPC_Encoding => 'XML-RPC',
                  # Set any other headers as well
                  Accept       => 'text/xml');
    $resp->content_type('text/xml');
    $resp->code(RC_OK);
    $resp->message('OK');
    $self->{__response} = $resp;

    $self->{__path}            = $args{path} || '';
    $self->{__started}         = 0;
    $self->{__method_table}    = {};
    $self->{__requests}        = 0;
    $self->{__auto_methods}    = $args{auto_methods} || 0;
    $self->{__auto_updates}    = $args{auto_updates} || 0;
    $self->{__debug}           = $args{debug} || 0;
    $self->{__parser}          = RPC::XML::Parser->new($args{parser} ?
                                                       @{$args{parser}} : ());
    $self->{__xpl_path}        = $args{xpl_path} || [];
    $self->{__timeout}         = $args{timeout}  || 10;

    $self->add_default_methods unless ($args{no_default});
    $self->{__compress} = '';
    unless ($args{no_compress})
    {
        eval "require Compress::Zlib";
        $self->{__compress} = $@ ? '' : 'deflate';
        # Add some more headers to the default response object for compression.
        # It looks wasteful to keep using the hash key, but it makes it easier
        # to change the string in just one place (above) if I have to.
        $resp->header(Accept_Encoding  => $self->{__compress})
            if $self->{__compress};
        $self->{__compress_thresh} = $args{compress_thresh} || 4096;
        # Yes, I know this is redundant. It's for future expansion/flexibility.
        $self->{__compress_re} =
            $self->{__compress} ? qr/$self->{__compress}/ : qr/deflate/;
    }

    # Parameters to control the point at which messages are shunted to temp
    # files due to size, and where to home the temp files. Start with a size
    # threshhold of 1Meg and no specific dir (which will fall-through to the
    # tmpdir() method of File::Spec).
    $self->{__message_file_thresh} = $args{message_file_thresh} || 1048576;
    $self->{__message_temp_dir}    = $args{message_temp_dir}    || '';

    # Remove the args we've already dealt with directly
    delete @args{qw(no_default no_http debug path server_name server_version
                    no_compress compress_thresh parser message_file_thresh
                    message_temp_dir)};
    # Copy the rest over untouched
    $self->{$_} = $args{$_} for (keys %args);

    $self;
}

# Most of these tiny subs are accessors to the internal hash keys. They not
# only control access to the internals, they ease sub-classing.

sub version { $RPC::XML::Server::VERSION }

sub INSTALL_DIR { $INSTALL_DIR }

sub url
{
    my $self = shift;

    return $self->{__daemon}->url if $self->{__daemon};
    return undef unless (my $host = $self->host);

    my $path = $self->path;
    my $port = $self->port;
    if ($port == 443)
    {
        return "https://$host$path";
    }
    elsif ($port == 80)
    {
        return "http://$host$path";
    }
    else
    {
        return "http://$host:$port$path";
    }
}

sub product_tokens
{
    sprintf "%s/%s", (ref $_[0] || $_[0]), $_[0]->version;
}

# This fetches/sets the internal "started" timestamp
sub started
{
    my $self = shift;
    my $set  = shift || 0;

    my $old = $self->{__started} || 0;
    $self->{__started} = time if $set;

    $old;
}

# Fetch/set the compression threshhold
sub compress_thresh
{
    my $self = shift;
    my $set = shift || 0;

    my $old = $self->{__compress_thresh};
    $self->{__compress_thresh} = $set if ($set);

    $old;
}

# Fetch/set the threshhold for spooling messages to files
sub message_file_thresh
{
    my $self = shift;
    my $set = shift || 0;

    my $old = $self->{__message_file_thresh};
    $self->{__message_file_thresh} = $set if ($set);

    $old;
}

# Fetch/set the temp dir to use for spooling large messages to files
sub message_temp_dir
{
    my $self = shift;
    my $set = shift || 0;

    my $old = $self->{__message_temp_dir};
    $self->{__message_temp_dir} = $set if ($set);

    $old;
}

BEGIN
{
    no strict 'refs';

    # These are immutable member values, so this simple block applies to all
    for my $method (qw(path host port requests response compress compress_re
                       parser))
    {
        *$method = sub { shift->{"__$method"} }
    }
}

# Get/set the search path for XPL files
sub xpl_path
{
    my $self = shift;
    my $ret = $self->{__xpl_path};

    $self->{__xpl_path} = $_[0] if ($_[0] and ref($_[0]) eq 'ARRAY');
    $ret;
}

###############################################################################
#
#   Sub Name:       add_method
#
#   Description:    Add a funtion-to-method mapping to the server object.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object to add to
#                   $meth     in      scalar    Hash ref of data or file name
#
#   Returns:        Success:    $self
#                   Failure:    error string
#
###############################################################################
sub add_method
{
    my $self = shift;
    my $meth = shift;

    my ($name, $val);

    my $me = ref($self) . '::add_method';

    if (! ref($meth))
    {
        $val = $self->method_from_file($meth);
        if (! ref($val))
        {
            return "$me: Error loading from file $meth: $val";
        }
        else
        {
            $meth = $val;
        }
    }
    elsif (ref($meth) eq 'HASH')
    {
        my $class = 'RPC::XML::' . ucfirst ($meth->{type} || 'method');
        $meth = $class->new($meth);
    }
    elsif (! UNIVERSAL::isa($meth, 'RPC::XML::Procedure'))
    {
        return "$me: Method argument must be a file name, a hash " .
            'reference or an object derived from RPC::XML::Procedure';
    }

    # Do some sanity-checks
    return "$me: Method missing required data; check name, code and/or " .
        'signature' unless $meth->is_valid;

    $name = $meth->name;
    $self->{__method_table}->{$name} = $meth;

    $self;
}

1;

=pod

=head1 NAME

RPC::XML::Server - A sample server implementation based on RPC::XML

=head1 SYNOPSIS

    use RPC::XML::Server;

    ...
    $srv = RPC::XML::Server->new(port => 9000);
    # Several of these, most likely:
    $srv->add_method(...);
    ...
    $srv->server_loop; # Never returns

=head1 DESCRIPTION

This is a sample XML-RPC server built upon the B<RPC::XML> data classes, and
using B<HTTP::Daemon> and B<HTTP::Response> for the communication layer.

=head1 USAGE

Use of the B<RPC::XML::Server> is based on an object model. A server is
instantiated from the class, methods (subroutines) are made public by adding
them through the object interface, and then the server object is responsible
for dispatching requests (and possibly for the HTTP listening, as well).

=head2 Methods

The following methods are provided by the B<RPC::XML::Server> class. Unless
otherwise explicitly noted, all methods return the invoking object reference
upon success, and a non-reference error string upon failure.

See L</Content Compression> below for details of how the server class manages
gzip-based compression and expansion of messages.

=over 4

=item new(OPTIONS)

Creates a new object of the class and returns the blessed reference. Depending
on the options, the object will contain some combination of an HTTP listener,
a pre-populated B<HTTP::Response> object, a B<RPC::XML::Parser> object, and
a dispatch table with the set of default methods pre-loaded. The options that
B<new> accepts are passed as a hash of key/value pairs (not a hash reference).
The accepted options are:

=over 4

=item B<no_http>

If passed with a C<true> value, prevents the creation and storage of the
B<HTTP::Daemon> object. This allows for deployment of a server object in other
environments. Note that if this is set, the B<server_loop> method described
below will silently attempt to use the B<Net::Server> module.

=item B<no_default>

If passed with a C<true> value, prevents the loading of the default methods
provided with the B<RPC::XML> distribution. These may be later loaded using
the B<add_default_methods> interface described later. The methods themselves
are described below (see L<"The Default Methods Provided">).

=item B<path>

=item B<host>

=item B<port>

=item B<queue>

These four are specific to the HTTP-based nature of the server.  The B<path>
argument sets the additional URI path information that clients would use to
contact the server.  Internally, it is not used except in outgoing status and
introspection reports.  The B<host>, B<port> and B<queue> arguments are passed
to the B<HTTP::Daemon> constructor if they are passed. They set the hostname,
TCP/IP port, and socket listening queue, respectively. They may also be used
if the server object tries to use B<Net::Server> as an alternative server
core.

=item B<xpl_path>

If you plan to add methods to the server object by passing filenames to the
C<add_method> call, this argument may be used to specify one or more
additional directories to be searched when the passed-in filename is a
relative path. The value for this must be an array reference. See also
B<add_method> and B<xpl_path>, below.

=item B<timeout>

Specify a value (in seconds) for the B<HTTP::Daemon> server to use as a
timeout value when reading request data from an inbound connection. The
default value is 10 seconds. This value is not used except by B<HTTP::Daemon>.

=item B<auto_methods>

If specified and set to a true value, enables the automatic searching for a
requested remote method that is unknown to the server object handling the
request. If set to "no" (or not set at all), then a request for an unknown
function causes the object instance to report an error. If the routine is
still not found, the error is reported. Enabling this is a security risk, and
should only be permitted by a server administrator with fully informed
acknowledgement and consent.

=item B<auto_updates>

If specified and set to a "true" value, enables the checking of the
modification time of the file from which a method was originally loaded. If
the file has changed, the method is re-loaded before execution is handed
off. As with the auto-loading of methods, this represents a security risk, and
should only be permitted by a server administrator with fully informed
acknowledgement and consent.

=item B<parser>

If this parameter is passed, the value following it is expected to be an
array reference. The contents of that array are passed to the B<new> method
of the B<RPC::XML::Parser> object that the server object caches for its use.
See the B<RPC::XML::Parser> manual page for a list of recognized parameters
to the constructor.

=item B<message_file_thresh>

If this key is passed, the value associated with it is assumed to be a
numerical limit to the size of in-memory messages. Any out-bound request that
would be larger than this when stringified is instead written to an anonynous
temporary file, and spooled from there instead. This is useful for cases in
which the request includes B<RPC::XML::base64> objects that are themselves
spooled from file-handles. This test is independent of compression, so even
if compression of a request would drop it below this threshhold, it will be
spooled anyway. The file itself is unlinked after the file-handle is created,
so once it is freed the disk space is immediately freed.

=item B<message_temp_dir>

If a message is to be spooled to a temporary file, this key can define a
specific directory in which to open those files. If this is not given, then
the C<tmpdir> method from the B<File::Spec> package is used, instead.

=back

Any other keys in the options hash not explicitly used by the constructor are
copied over verbatim onto the object, for the benefit of sub-classing this
class. All internal keys are prefixed with C<__> to avoid confusion. Feel
free to use this prefix only if you wish to re-introduce confusion.

=item version

Returns the version string associated with this package.

=item product_tokens

This returns the identifying string for the server, in the format
C<NAME/VERSION> consistent with other applications such as Apache and
B<LWP>. It is provided here as part of the compatibility with B<HTTP::Daemon>
that is required for effective integration with B<Net::Server>.

=item url

This returns the HTTP URL that the server will be responding to, when it is in
the connection-accept loop. If the server object was created without a
built-in HTTP listener, then this method returns C<undef>.

=item requests

Returns the number of requests this server object has marshalled. Note that in
multi-process environments (such as Apache or Net::Server::PreFork) the value
returned will only reflect the messages dispatched by the specific process
itself.

=item response

Each instance of this class (and any subclasses that do not completely
override the C<new> method) creates and stores an instance of
B<HTTP::Response>, which is then used by the B<HTTP::Daemon> or B<Net::Server>
processing loops in constructing the response to clients. The response object
has all common headers pre-set for efficiency. This method returns a reference
to that object.

=item started([BOOL])

Gets and possibly sets the clock-time when the server starts accepting
connections. If a value is passed that evaluates to true, then the current
clock time is marked as the starting time. In either case, the current value
is returned. The clock-time is based on the internal B<time> command of Perl,
and thus is represented as an integer number of seconds since the system
epoch. Generally, it is suitable for passing to either B<localtime> or to the
C<time2iso8601> routine exported by the B<RPC::XML> package.

=item timeout(INT)

You can call this method to set the timeout of new connections after
they are received.  This function returns the old timeout value.  If
you pass in no value then it will return the old value without
modifying the current value.  The default value is 10 seconds.

=item add_method(FILE | HASHREF | OBJECT)

=item add_proc(FILE | HASHREF | OBJECT)

This adds a new published method or procedure to the server object that
invokes it. The new method may be specified in one of three ways: as a
filename, a hash reference or an existing object (generally of either
B<RPC::XML::Procedure> or B<RPC::XML::Method> classes).

If passed as a hash reference, the following keys are expected:

=over 4

=item B<name>

The published (externally-visible) name for the method.

=item B<version>

An optional version stamp. Not used internally, kept mainly for informative
purposes.

=item B<hidden>

If passed and evaluates to a C<true> value, then the method should be hidden
from any introspection API implementations. This parameter is optional, the
default behavior being to make the method publically-visible.

=item B<code>

A code reference to the actual Perl subroutine that handles this method. A
symbolic reference is not accepted. The value can be passed either as a
reference to an existing routine, or possibly as a closure. See
L</"How Methods are Called"> for the semantics the referenced subroutine must
follow.

=item B<signature>

A list reference of the signatures by which this routine may be invoked. Every
method has at least one signature. Though less efficient for cases of exactly
one signature, a list reference is always used for sake of consistency.

=item B<help>

Optional documentation text for the method. This is the text that would be
returned, for example, by a B<system.methodHelp> call (providing the server
has such an externally-visible method).

=back

If a file is passed, then it is expected to be in the XML-based format,
described in the B<RPC::XML::Procedure> manual (see L<RPC::XML::Procedure>).
If the name passed is not an absolute pathname, then the file will be searched
for in any directories specified when the object was instantiated, then in the
directory into which this module was installed, and finally in the current
working directory. If the operation fails, the return value will be a
non-reference, an error message. Otherwise, the return value is the object
reference.

The B<add_method> and B<add_proc> calls are essentialy identical unless called
with hash references. Both files and objects contain the information that
defines the type (method vs. procedure) of the funtionality to be added to the
server. If B<add_method> is called with a file that describes a procedure, the
resulting addition to the server object will be a B<RPC::XML::Procedure>
object, not a method object.

For more on the creation and manipulation of procedures and methods as
objects, see L<RPC::XML::Procedure>.

=item delete_method(NAME)

=item delete_proc(NAME)

Delete the named method or procedure from the calling object. Removes the
entry from the internal table that the object maintains. If the method is
shared across more than one server object (see L</share_methods>), then the
underlying object for it will only be destroyed when the last server object
releases it. On error (such as no method by that name known), an error string
is returned.

The B<delete_proc> call is identical, supplied for the sake of symmetry. Both
calls return the matched object regardless of its underlying type.

=item list_methods

=item list_procs

This returns a list of the names of methods and procedures the server current
has published.  Note that the returned values are not the method objects, but
rather the names by which they are externally known. The "hidden" status of a
method is not consulted when this list is created; all methods and procedures
known are listed. The list is not sorted in any specific order.

The B<list_procs> call is provided for symmetry. Both calls list all published
routines on the calling server object, regardless of underlying type.

=item xpl_path([LISTREF])

Get and/or set the object-specific search path for C<*.xpl> files (files that
specify methods) that are specified in calls to B<add_method>, above. If a
list reference is passed, it is installed as the new path (each element of the
list being one directory name to search). Regardless of argument, the current
path is returned as a list reference. When a file is passed to B<add_method>,
the elements of this path are searched first, in order, before the
installation directory or the current working directory are searched.

=item get_method(NAME)

=item get_proc(NAME)

Returns a reference to an object of the class B<RPC::XML::Method> or
B<RPC::XML::Procedure>, which is the current binding for the published method
NAME. If there is no such method known to the server, then C<undef> is
returned. The object is implemented as a hash, and has the same key and value
pairs as for C<add_method>, above. Thus, the reference returned is suitable
for passing back to C<add_method>. This facilitates temporary changes in what
a published name maps to. Note that this is a referent to the object as stored
on the server object itself, and thus changes to it could affect the behavior
of the server.

The B<get_proc> interface is provided for symmetry.

=item server_loop(HASH)

Enters the connection-accept loop, which generally does not return. This is
the C<accept()>-based loop of B<HTTP::Daemon> if the object was created with
an instance of that class as a part. Otherwise, this enters the run-loop of
the B<Net::Server> class. It listens for requests, and marshalls them out via
the C<dispatch> method described below. It answers HTTP-HEAD requests
immediately (without counting them on the server statistics) and efficiently
by using a cached B<HTTP::Response> object.

Because infinite loops requiring a C<HUP> or C<KILL> signal to terminate are
generally in poor taste, the B<HTTP::Daemon> side of this sets up a localized
signal handler which causes an exit when triggered. By default, this is
attached to the C<INT> signal. If the B<Net::Server> module is being used
instead, it provides its own signal management.

The arguments, if passed, are interpreted as a hash of key/value options (not
a hash reference, please note). For B<HTTP::Daemon>, only one is recognized:

=over 4

=item B<signal>

If passed, should be the traditional name for the signal that should be bound
to the exit function. If desired, a reference to an array of signal names may
be passed, in which case all signals will be given the same handler. The user
is responsible for not passing the name of a non-existent signal, or one that
cannot be caught. If the value of this argument is 0 (a C<false> value) or the
string C<B<NONE>>, then the signal handler will I<not> be installed, and the
loop may only be broken out of by killing the running process (unless other
arrangements are made within the application).

=back

The options that B<Net::Server> responds to are detailed in the manual pages
for that package. All options passed to C<server_loop> in this situation are
passed unaltered to the C<run()> method in B<Net::Server>.

=item dispatch(REQUEST)

This is the server method that actually manages the marshalling of an incoming
request into an invocation of a Perl subroutine. The parameter passed in may
be one of: a scalar containing the full XML text of the request, a scalar
reference to such a string, or a pre-constructed B<RPC::XML::request> object.
Unless an object is passed, the text is parsed with any errors triggering an
early exit. Once the object representation of the request is on hand, the
parameter data is extracted, as is the method name itself. The call is sent
along to the appropriate subroutine, and the results are collated into an
object of the B<RPC::XML::response> class, which is returned. Any non-reference
return value should be presumed to be an error string.

The dispatched method may communicate error in several ways.  First, any
non-reference return value is presumed to be an error string, and is encoded
and returned as an B<RPC::XML::fault> response.  The method is run under an
C<eval()>, so errors conveyed by C<$@> are similarly encoded and returned.  As
a special case, a method may explicitly C<die()> with a fault response, which
is passed on unmodified.

=item add_default_methods([DETAILS])

This method adds all the default methods (those that are shipped with this
extension) to the calling server object. The files are denoted by their
C<*.xpl> extension, and are installed into the same directory as this
B<Server.pm> file. The set of default methods are described below (see
L<"The Default Methods Provided">).

If any names are passed as a list of arguments to this call, then only those
methods specified are actually loaded. If the C<*.xpl> extension is absent on
any of these names, then it is silently added for testing purposes. Note that
the methods shipped with this package have file names without the leading
C<status.> part of the method name. If the very first element of the list of
arguments is C<except> (or C<-except>), then the rest of the list is
treated as a set of names to I<not> load, while all others do get read. The
B<Apache::RPC::Server> module uses this to prevent the loading of the default
C<system.status> method while still loading all the rest of the defaults. (It
then provides a more Apache-centric status method.)

Note that there is no symmetric call in this case. The provided API is
implemented as methods, and thus only this interface is provided.

=item add_methods_in_dir(DIR [, DETAILS])

=item add_procs_in_dir(DIR [, DETAILS])

This is exactly like B<add_default_methods> above, save that the caller
specifies which directory to scan for C<*.xpl> files. In fact, the
B<add_default_methods> routine simply calls this routine with the installation
directory as the first argument. The definition of the additional arguments is
the same as above.

B<add_procs_in_dir> is provided for symmetry.

=item share_methods(SERVER, NAMES)

=item share_procs(SERVER, NAMES)

The calling server object shares the methods and/or procedures listed in
B<NAMES> with the source-server passed as the first object. The source must
derive from this package in order for this operation to be permitted. At least
one method must be specified, and all are specified by name (not by object
refernce). Both objects will reference the same exact B<RPC::XML::Procedure>
(or B<Method>, or derivative thereof) object in this case, meaning that
call-statistics and the like will reflect the combined data. If one or more of
the passed names are not present on the source server, an error message is
returned and none are copied to the calling object.

Alternately, one or more of the name parameters passed to this call may be
regular-expression objects (the result of the B<qr> operator). Any of these
detected are applied against the list of all available methods known to the
source server. All matching ones are inserted into the list (the list is pared
for redundancies in any case). This allows for easier addition of whole
classes such as those in the C<system.*> name space (via B<C<qr/^system\./>>),
for example. There is no substring matching provided. Names listed in the
parameters to this routine must be either complete strings or regular
expressions.

The B<share_procs> interface is provided for symmetry.

=item copy_methods(SERVER, NAMES)

=item copy_procs(SERVER, NAMES)

This behaves like the method B<share_methods> above, with the exception that
the calling object is given a clone of each method, rather than referencing
the same exact method as the source server. The code reference part of the
method is shared between the two, but all other data are copied (including a
fresh copy of any list references used) into a completely new
B<RPC::XML::Procedure> (or derivative) object, using the C<clone()> method
from that class. Thus, while the calling object has the same methods
available, and is re-using existing code in the Perl runtime, the method
objects (and hence the statistics and such) are kept separate. As with the
above, an error is flagged if one or more are not found.

This routine also accepts regular-expression objects with the same behavior
and limitations. Again, B<copy_procs> is simply provided for symmetry.

=back

=head2 Specifying Server-Side Remote Methods

Specifying the methods themselves can be a tricky undertaking. Some packages
(in other languages) delegate a specific class to handling incoming requests.
This works well, but it can lead to routines not intended for public
availability to in fact be available. There are also issues around the access
that the methods would then have to other resources within the same running
system.

The approach taken by B<RPC::XML::Server> (and the B<Apache::RPC::Server>
subclass of it) require that methods be explicitly published in one of the
several ways provided. Methods may be added directly within code by using
C<add_method> as described above, with full data provided for the code
reference, signature list, etc. The C<add_method> technique can also be used
with a file that conforms to a specific XML-based format (detailed in the
manual page for the B<RPC::XML::Procedure> class, see L<RPC::XML::Procedure>).
Entire directories of files may be added using C<add_methods_in_dir>, which
merely reads the given directory for files that appear to be method
definitions.

=head2 How Methods Are Called

When a routine is called via the server dispatcher, it is called with the
arguments that the client request passed. Depending on whether the routine is
considered a "procedure" or a "method", there may be an extra argument at the
head of the list. The extra argument is present when the routine being
dispatched is part of a B<RPC::XML::Method> object. The extra argument is a
reference to a B<RPC::XML::Server> object (or a subclass thereof). This is
derived from a hash reference, and will include two special keys:

=over 4

=item method_name

This is the name by which the method was called in the client. Most of the
time, this will probably be consistent for all calls to the server-side
method. But it does not have to be, hence the passing of the value.

=item signature

This is the signature that was used, when dispatching. Perl has a liberal
view of lists and scalars, so it is not always clear what arguments the client
specifically has in mind when calling the method. The signature is an array
reference containing one or more datatypes, each a simple string. The first
of the datatypes specifies the expected return type. The remainder (if any)
refer to the arguments themselves.

=back

Note that by passing the server object reference first, method-classed
routines are essentially expected to behave as actual methods of the server
class, as opposed to ordinary functions. Of course, they can also discard the
initial argument completely.

The routines should not make (excessive) use of global variables, for obvious
reasons. When the routines are loaded from XPL files, the code is created as a
closure that forces execution in the B<RPC::XML::Procedure> package. If the
code element of a procedure/method is passed in as a direct code reference by
one of the other syntaxes allowed by the constructor, the package may well be
different. Thus, routines should strive to be as localized as possible,
independant of specific namespaces. If a group of routines are expected to
work in close concert, each should explicitly set the namespace with a
C<package> declaration as the first statement within the routines themselves.

=head2 The Default Methods Provided

The following methods are provided with this package, and are the ones
installed on newly-created server objects unless told not to. These are
identified by their published names, as they are compiled internally as
anonymous subroutines and thus cannot be called directly:

=over 4

=item B<system.identity>

Returns a B<string> value identifying the server name, version, and possibly a
capability level. Takes no arguments.

=item B<system.introspection>

Returns a series of B<struct> objects that give overview documentation of one
or more of the published methods. It may be called with a B<string>
identifying a single routine, in which case the return value is a
B<struct>. It may be called with an B<array> of B<string> values, in which
case an B<array> of B<struct> values, one per element in, is returned. Lastly,
it may be called with no input parameters, in which case all published
routines are documented.  Note that routines may be configured to be hidden
from such introspection queries.

=item B<system.listMethods>

Returns a list of the published methods or a subset of them as an B<array> of
B<string> values. If called with no parameters, returns all (non-hidden)
method names. If called with a single B<string> pattern, returns only those
names that contain the string as a substring of their name (case-sensitive,
and this is I<not> a regular expression evaluation).

=item B<system.methodHelp>

Takes either a single method name as a B<string>, or a series of them as an
B<array> of B<string>. The return value is the help text for the method, as
either a B<string> or B<array> of B<string> value. If the method(s) have no
help text, the string will be null.

=item B<system.methodSignature>

As above, but returns the signatures that the method accepts, as B<array> of
B<string> representations. If only one method is requests via a B<string>
parameter, then the return value is the corresponding array. If the parameter
in is an B<array>, then the returned value will be an B<array> of B<array> of
B<string>.

=item B<system.multicall>

This is a simple implementation of composite function calls in a single
request. It takes an B<array> of B<struct> values. Each B<struct> has at least
a C<methodName> member, which provides the name of the method to call. If
there is also a C<params> member, it refers to an B<array> of the parameters
that should be passed to the call.

=item B<system.status>

Takes no arguments and returns a B<struct> containing a number of system
status values including (but not limited to) the current time on the server,
the time the server was started (both of these are returned in both ISO 8601
and UNIX-style integer formats), number of requests dispatched, and some
identifying information (hostname, port, etc.).

=back

In addition, each of these has an accompanying help file in the C<methods>
sub-directory of the distribution.

These methods are installed as C<*.xpl> files, which are generated from files
in the C<methods> directory of the distribution using the B<make_method> tool
(see L<make_method>). The files there provide the Perl code that implements
these, their help files and other information.

=head2 Content Compression

The B<RPC::XML::Server> class now supports compressed messages, both incoming
and outgoing. If a client indicates that it can understand compressed content,
the server will use the B<Compress::Zlib> (available from CPAN) module, if
available, to compress any outgoing messages above a certain threshhold in
size (the default threshhold is set to 4096 bytes). The following methods are
all related to the compression support within the server class:

=over 4

=item compress

Returns a false value if compression is not available to the server object.
This is based on the availability of the B<Compress::Zlib> module at start-up
time, and cannot be changed.

=item compress_thresh([MIN_LIMIT])

Return or set the compression threshhold value. Messages smaller than this
size in bytes will not be compressed, even when compression is available, to
save on CPU resources. If a value is passed, it becomes the new limit and the
old value is returned.

=back

=head2 Spooling Large Messages

If the server anticipates handling large out-bound messages (for example, if
the hosted code returns large Base64 values pre-encoded from file handles),
the C<message_file_thresh> and C<message_temp_dir> settings may be used in a
manner similar to B<RPC::XML::Client>. Specifically, the threshhold is used to
determine when a message should be spooled to a filehandle rather than made
into an in-memory string (the B<RPC::XML::base64> type can use a filehandle,
thus eliminating the need for the data to ever be completely in memory). An
anonymous temporary file is used for these operations.

Note that the message size is checked before compression is applied, since the
size of the compressed output cannot be known until the full message is
examined. It is possible that a message will be spooled even if its compressed
size is below the threshhold, if the uncompressed size exceeds the threshhold.

=over 4

=item message_file_thresh

=item message_temp_dir

These methods may be used to retrieve or alter the values of the given keys
as defined earlier for the C<new> method.

=back

=head1 DIAGNOSTICS

Unless explicitly stated otherwise, all methods return some type of reference
on success, or an error string on failure. Non-reference return values should
always be interpreted as errors unless otherwise noted.

=head1 CAVEATS

This began as a reference implementation in which clarity of process and
readability of the code took precedence over general efficiency. It is now
being maintained as production code, but may still have parts that could be
written more efficiently.

=head1 CREDITS

The B<XML-RPC> standard is Copyright (c) 1998-2001, UserLand Software, Inc.
See <http://www.xmlrpc.com> for more information about the B<XML-RPC>
specification. A helpful patch was sent in by Tino Wuensche to fix problems
in the signal-setting and signal-catching code in server_loop().

=head1 LICENSE

This module is licensed under the terms of the Artistic License that covers
Perl. See <http://www.opensource.org/licenses/artistic-license.php> for the
license.

=head1 SEE ALSO

L<RPC::XML>, L<RPC::XML::Client>, L<RPC::XML::Parser>

=head1 AUTHOR

Randy J. Ray <rjray@blackperl.com>

=cut

__END__

###############################################################################
#
#   Sub Name:       add_proc
#
#   Description:    This filters through to add_method, but unlike the other
#                   front-ends defined later, this one may have to alter the
#                   data in one type of calling-convention.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object reference
#                   $meth     in      scalar    Procedure to add
#
#   Returns:        threads through to add_method
#
###############################################################################
sub add_proc
{
    my ($self, $meth) = @_;

    # Anything else but a hash-reference goes through unaltered
    $meth->{type} = 'procedure' if (ref($meth) eq 'HASH');

    $self->add_method($meth);
}

###############################################################################
#
#   Sub Name:       method_from_file
#
#   Description:    Create a RPC::XML::Procedure (or ::Method) object from the
#                   passed-in file name, using the object's search path if the
#                   name is not already absolute.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $file     in      scalar    Name of file to load
#
#   Returns:        Success:    Method-object reference
#                   Failure:    error message
#
###############################################################################
sub method_from_file
{
    my $self = shift;
    my $file = shift;

    unless (File::Spec->file_name_is_absolute($file))
    {
        my ($path, @path);
        push(@path, @{$self->xpl_path}) if (ref $self);
        for (@path, @XPL_PATH)
        {
            $path = File::Spec->catfile($_, $file);
            if (-e $path) { $file = File::Spec->canonpath($path); last; }
        }
    }
    # Just in case it still didn't appear in the path, we really want an
    # absolute path:
    $file = File::Spec->rel2abs($file)
        unless (File::Spec->file_name_is_absolute($file));

    RPC::XML::Procedure::new(undef, $file);
}

# Same as above, but for name-symmetry
sub proc_from_file { shift->method_from_file(@_) }

###############################################################################
#
#   Sub Name:       get_method
#
#   Description:    Get the current binding for the remote-side method $name.
#                   Returns undef if the method is not defined for the server
#                   instance.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Class instance
#                   $name     in      scalar    Name of the method being looked
#                                                 up
#
#   Returns:        Success:    Method-class reference
#                   Failure:    error string
#
###############################################################################
sub get_method
{
    my $self = shift;
    my $name = shift;

    my $meth = $self->{__method_table}->{$name};
    unless (defined $meth)
    {
        if ($self->{__auto_methods})
        {
            # Try to load this dynamically on the fly, from any of the dirs
            # that are in this object's @xpl_path
            (my $loadname = $name) =~ s/^system\.//;
            $self->add_method("$loadname.xpl");
        }
        # If method is still not in the table, we were unable to load it
        return "Unknown method: $name"
            unless $meth = $self->{__method_table}->{$name};
    }
    # Check the mod-time of the file the method came from, if the test is on
    if ($self->{__auto_updates} && $meth->{file} &&
        ($meth->{mtime} < (stat $meth->{file})[9]))
    {
        my $ret = $meth->reload;
        return "Reload of method $name failed: $ret" unless ref($ret);
    }

    $meth;
}

# Same as above, but for name-symmetry
sub get_proc { shift->get_method(@_) }

###############################################################################
#
#   Sub Name:       server_loop
#
#   Description:    Enter a server-loop situation, using the accept() loop of
#                   HTTP::Daemon if $self has such an object, or falling back
#                   Net::Server otherwise.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   %args     in      hash      Additional parameters to set up
#                                                 before calling the superclass
#                                                 Run method
#
#   Returns:        string if error, otherwise void
#
###############################################################################
sub server_loop
{
    my $self = shift;

    if ($self->{__daemon})
    {
        my ($conn, $req, $resp, $reqxml, $return, $respxml, $exit_now,
            $timeout);

        my %args = @_;

        # Localize and set the signal handler as an exit route
        my @exit_signals;

        if (exists $args{signal} and $args{signal} ne 'NONE')
        {
            @exit_signals =
                (ref $args{signal}) ? @{$args{signal}} : $args{signal};
        }
        else
        {
            push @exit_signals, 'INT';
        }

        local @SIG{@exit_signals} = ( sub { $exit_now++ } ) x @exit_signals;

        $self->started('set');
        $exit_now = 0;
        $timeout = $self->{__daemon}->timeout(1);
        while (! $exit_now)
        {
            $conn = $self->{__daemon}->accept;

            last if $exit_now;
            next unless $conn;
            $conn->timeout($self->timeout);
            $self->process_request($conn);
            $conn->close;
            undef $conn; # Free up any lingering resources
        }

        $self->{__daemon}->timeout($timeout) if defined $timeout;
    }
    else
    {
        # This is the Net::Server block, but for now HTTP::Daemon is needed
        # for the code that converts socket data to a HTTP::Request object
        require HTTP::Daemon;

        my $conf_file_flag = 0;
        my $port_flag = 0;
        my $host_flag = 0;

        for (my $i = 0; $i < @_; $i += 2)
        {
            $conf_file_flag = 1 if ($_[$i] eq 'conf_file');
            $port_flag = 1 if ($_[$i] eq 'port');
            $host_flag = 1 if ($_[$i] eq 'host');
        }

        # An explicitly-given conf-file trumps any specified at creation
        if (exists($self->{conf_file}) and (! $conf_file_flag))
        {
            push (@_, 'conf_file', $self->{conf_file});
            $conf_file_flag = 1;
        }

        # Don't do this next part if they've already given a port, or are
        # pointing to a config file:
        unless ($conf_file_flag or $port_flag)
        {
            push (@_, 'port', $self->{port} || $self->port || 9000);
            push (@_, 'host', $self->{host} || $self->host || '*');
        }

        # Try to load the Net::Server::MultiType module
        eval { require Net::Server::MultiType; };
        return ref($self) .
            "::server_loop: Error loading Net::Server::MultiType: $@"
                if ($@);
        unshift(@RPC::XML::Server::ISA, 'Net::Server::MultiType');

        $self->started('set');
        # ...and we're off!
        $self->run(@_);
    }

    return;
}

###############################################################################
#
#   Sub Name:       post_configure_loop
#
#   Description:    Called by the Net::Server classes after all the config
#                   steps have been done and merged.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Class object
#
#   Returns:        $self
#
###############################################################################
sub post_configure_hook
{
    my $self = shift;

    $self->{__host} = $self->{server}->{host};
    $self->{__port} = $self->{server}->{port};

    $self;
}

###############################################################################
#
#   Sub Name:       pre_loop_hook
#
#   Description:    Called by Net::Server classes after the post_bind method,
#                   but before the socket-accept loop starts.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object instance
#
#   Globals:       %ENV
#
#   Returns:        $self
#
###############################################################################
sub pre_loop_hook
{
    # We have to disable the __DIE__ handler for the sake of XML::Parser::Expat
    $SIG{__DIE__} = '';
}

###############################################################################
#
#   Sub Name:       process_request
#
#   Description:    This is provided for the case when we run as a subclass
#                   of Net::Server.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       This class object
#                   $conn     in      ref       If present, it's a connection
#                                                 object from HTTP::Daemon
#
#   Returns:        void
#
###############################################################################
sub process_request
{
    my $self = shift;
    my $conn = shift;

    my ($req, $reqxml, $resp, $respxml, $do_compress, $parser, $com_engine,
        $length, $read, $buf, $resp_fh, $tmpfile);

    my $me = ref($self) . '::process_request';
    unless ($conn and ref($conn))
    {
        $conn = $self->{server}->{client};
        bless $conn, 'HTTP::Daemon::ClientConn';
        ${*$conn}{'httpd_daemon'} = $self;
    }

    while ($req = $conn->get_request('headers only'))
    {
        if ($req->method eq 'HEAD')
        {
            # The HEAD method will be answered with our return headers,
            # both as a means of self-identification and a verification
            # of live-status. All the headers were pre-set in the cached
            # HTTP::Response object. Also, we don't count this for stats.
            $conn->send_response($self->response);
        }
        elsif ($req->method eq 'POST')
        {
            # Get a XML::Parser::ExpatNB object
            $parser = $self->parser->parse();

            if (($req->content_encoding || '') =~ $self->compress_re)
            {
                unless ($self->compress)
                {
                    $conn->send_error(RC_BAD_REQUEST,
                                      "$me: Compression not permitted in " .
                                      'requests');
                    next;
                }

                $do_compress = 1;
            }

            if (($req->content_encoding || '') =~ /chunked/i)
            {
                # Technically speaking, we're not supposed to honor chunked
                # transfer-encoding...
            }
            else
            {
                $length = $req->content_length;
                if ($do_compress)
                {
                    # Spin up the compression engine
                    unless ($com_engine = Compress::Zlib::inflateInit())
                    {
                        $conn->send_error(RC_INTERNAL_SERVER_ERROR,
                                          "$me: Unable to initialize the " .
                                          'Compress::Zlib engine');
                        next;
                    }
                }

                $buf = '';
                while ($length > 0)
                {
                    if ($buf = $conn->read_buffer)
                    {
                        # Anything that get_request read, but didn't use, was
                        # left in the read buffer. The call to sysread() should
                        # NOT be made until we've emptied this source, first.
                        $read = length($buf);
                        $conn->read_buffer(''); # Clear it, now that it's read
                    }
                    else
                    {
                        $read = sysread($conn, $buf,
                                        ($length < 2048) ? $length : 2048);
                    }
                    $length -= $read;
                    if ($do_compress)
                    {
                        unless ($buf = $com_engine->inflate($buf))
                        {
                            $conn->send_error(RC_INTERNAL_SERVER_ERROR,
                                              "$me: Error inflating " .
                                              'compressed data');
                            # This error also means that even if Keep-Alive
                            # is set, we don't know how much of the stream
                            # is corrupted.
                            $conn->force_last_request;
                            next;
                        }
                    }

                    eval { $parser->parse_more($buf); };
                    if ($@)
                    {
                        $conn->send_error(RC_INTERNAL_SERVER_ERROR,
                                          "$me: Parse error in (compressed) " .
                                          "XML request (mid): $@");
                        # Again, the stream is likely corrupted
                        $conn->force_last_request;
                        next;
                    }
                }

                eval { $reqxml = $parser->parse_done(); };
                if ($@)
                {
                    $conn->send_error(RC_INTERNAL_SERVER_ERROR,
                                      "$me: Parse error in (compressed) " .
                                      "XML request (end): $@");
                    next;
                }
            }

            # Dispatch will always return a RPC::XML::response
            $respxml = $self->dispatch($reqxml);

            # Clone the pre-fab response and set headers
            $resp = $self->response->clone;
            # Should we apply compression to the outgoing response?
            $do_compress = 0; # In case it was set above for incoming data
            if ($self->compress and
                ($respxml->length > $self->compress_thresh) and
                (($req->header('Accept-Encoding') || '') =~
                 $self->compress_re))
            {
                $do_compress = 1;
                $resp->content_encoding($self->compress);
            }
            # Next step, determine the response disposition. If it is above the
            # threshhold for a requested file cut-off, send it to a temp file
            if ($self->message_file_thresh and
                $self->message_file_thresh < $respxml->length)
            {
                require File::Spec;
                # Start by creating a temp-file
                $tmpfile = $self->message_temp_dir || File::Spec->tmpdir;
                $tmpfile = File::Spec->catfile($tmpfile,
                                               __PACKAGE__ . $$ . time);
                unless (open($resp_fh, "+> $tmpfile"))
                {
                    $conn->send_error(RC_INTERNAL_SERVER_ERROR,
                                      "$me: Error opening $tmpfile: $!");
                    next;
                }
                unlink $tmpfile;
                # Make it auto-flush
                my $old_fh = select($resp_fh); $| = 1; select($old_fh);

                # Now that we have it, spool the response to it. This is a
                # little hairy, since we still have to allow for compression.
                # And though the response could theoretically be HUGE, in
                # order to compress we have to write it to a second temp-file
                # first, so that we can compress it into the primary handle.
                if ($do_compress)
                {
                    my $fh2;
                    $tmpfile .= '-2';
                    unless (open($fh2, "+> $tmpfile"))
                    {
                        $conn->send_error(RC_INTERNAL_SERVER_ERROR,
                                          "$me: Error opening $tmpfile: $!");
                        next;
                    }
                    unlink $tmpfile;
                    # Make it auto-flush
                    $old_fh = select($fh2); $| = 1; select($old_fh);

                    # Write the request to the second FH
                    $respxml->serialize($fh2);
                    seek($fh2, 0, 0);

                    # Spin up the compression engine
                    unless ($com_engine = Compress::Zlib::deflateInit())
                    {
                        $conn->send_error(RC_INTERNAL_SERVER_ERROR,
                                          "$me: Unable to initialize the " .
                                          'Compress::Zlib engine');
                        next;
                    }

                    # Spool from the second FH through the compression engine,
                    # into the intended FH.
                    $buf = '';
                    my $out;
                    while (read($fh2, $buf, 4096))
                    {
                        unless (defined($out = $com_engine->deflate(\$buf)))
                        {
                            $conn->send_error(RC_INTERNAL_SERVER_ERROR,
                                              "$me: Compression failure in " .
                                              'deflate()');
                            next;
                        }
                        print $resp_fh $out;
                    }
                    # Make sure we have all that's left
                    unless (defined($out = $com_engine->flush))
                    {
                        $conn->send_error(RC_INTERNAL_SERVER_ERROR,
                                          "$me: Compression flush failure in" .
                                          ' deflate()');
                        next;
                    }
                    print $resp_fh $out;

                    # Close the secondary FH. Rewinding the primary is done
                    # later.
                    close($fh2);
                }
                else
                {
                    $respxml->serialize($resp_fh);
                }
                seek($resp_fh, 0, 0);

                $resp->content_length(-s $resp_fh);
                $resp->content(sub {
                                   my $b = '';
                                   return undef unless
                                       defined(read($resp_fh, $b, 4096));
                                   $b;
                               });
            }
            else
            {
                # Treat the content strictly in-memory
                $buf = $respxml->as_string;
                $buf = Compress::Zlib::compress($buf) if $do_compress;
                $resp->content($buf);
                $resp->content_length($respxml->length);
            }

            $conn->send_response($resp);
            undef $resp;
        }
        else
        {
            $conn->send_error(RC_FORBIDDEN);
        }
    }

    return;
}

###############################################################################
#
#   Sub Name:       dispatch
#
#   Description:    Route the request by parsing it, determining what the
#                   Perl routine should be, etc.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $xml      in      ref       Reference to the XML text, or
#                                                 a RPC::XML::request object.
#                                                 If it is a listref, assume
#                                                 [ name, @args ].
#                   $reftable in      hashref   If present, a reference to the
#                                                 current-running table of
#                                                 back-references
#
#   Returns:        RPC::XML::response object
#
###############################################################################
sub dispatch
{
    my ($self, $xml) = @_;

    my ($reqobj, @data, $response, $name, $meth);

    if (ref($xml) eq 'SCALAR')
    {
        $reqobj = $self->parser->parse($$xml);
        return RPC::XML::response
            ->new(RPC::XML::fault->new(200, "XML parse failure: $reqobj"))
                unless (ref $reqobj);
    }
    elsif (ref($xml) eq 'ARRAY')
    {
        # This is sort of a cheat, to make the system.multicall API call a
        # lot easier. The syntax isn't documented in the manual page, for good
        # reason.
        $reqobj = RPC::XML::request->new(shift(@$xml), @$xml);
    }
    elsif (UNIVERSAL::isa($xml, 'RPC::XML::request'))
    {
        $reqobj = $xml;
    }
    else
    {
        $reqobj = $self->parser->parse($xml);
        return RPC::XML::response
            ->new(RPC::XML::fault->new(200, "XML parse failure: $reqobj"))
                unless (ref $reqobj);
    }

    @data = @{$reqobj->args};
    $name = $reqobj->name;

    # Get the method, call it, and bump the internal requests counter. Create
    # a fault object if there is problem with the method object itself.
    if (ref($meth = $self->get_method($name)))
    {
        $response = $meth->call($self, @data);
        $self->{__requests}++
            unless (($name eq 'system.status') && @data &&
                    ($data[0]->type eq 'boolean') && ($data[0]->value));
    }
    else
    {
        $response = RPC::XML::fault->new(300, $meth);
    }

    # All the eval'ing and error-trapping happened within the method class
    RPC::XML::response->new($response);
}

###############################################################################
#
#   Sub Name:       call
#
#   Description:    This is an internal, end-run-around-dispatch() method to
#                   allow the RPC methods that this server has and knows about
#                   to call each other through their reference to the server
#                   object.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $name     in      scalar    Name of the method to call
#                   @args     in      list      Arguments (if any) to pass
#
#   Returns:        Success:    return value of the call
#                   Failure:    error string
#
###############################################################################
sub call
{
    my ($self, $name, @args) = @_;

    my $meth;

    #
    # Two VERY important notes here: The values in @args are not pre-treated
    # in any way, so not only should the receiver understand what they're
    # getting, there's no signature checking taking place, either.
    #
    # Second, if the normal return value is not distinguishable from a string,
    # then the caller may not recognize if an error occurs.
    #

    return $meth unless ref($meth = $self->get_method($name));
    $meth->call($self, @args);
}

###############################################################################
#
#   Sub Name:       add_default_methods
#
#   Description:    This adds all the methods that were shipped with this
#                   package, by threading through to add_methods_in_dir()
#                   with the global constant $INSTALL_DIR.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object reference/static class
#                   @details  in      ref       Details of names to add or skip
#
#   Globals:        $INSTALL_DIR
#
#   Returns:        $self
#
###############################################################################
sub add_default_methods
{
    shift->add_methods_in_dir($INSTALL_DIR, @_);
}

###############################################################################
#
#   Sub Name:       add_methods_in_dir
#
#   Description:    This adds all methods specified in the directory passed,
#                   in accordance with the details specified.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Class instance
#                   $dir      in      scalar    Directory to scan
#                   @details  in      list      Possible hanky-panky with the
#                                                 list of methods to install
#
#   Returns:        $self
#
###############################################################################
sub add_methods_in_dir
{
    my $self = shift;
    my $dir = shift;
    my @details = @_;

    my $negate = 0;
    my $detail = 0;
    my (%details, $ret);

    if (@details)
    {
        $detail = 1;
        if ($details[0] =~ /^-?except/i)
        {
            $negate = 1;
            shift(@details);
        }
        for (@details) { $_ .= '.xpl' unless /\.xpl$/ }
        @details{@details} = (1) x @details;
    }

    local(*D);
    opendir(D, $dir) || return "Error opening $dir for reading: $!";
    my @files = grep($_ =~ /\.xpl$/, readdir(D));
    closedir D;

    for (@files)
    {
        # Use $detail as a short-circuit to avoid the other tests when we can
        next if ($detail and
                 $negate ? $details{$_} : ! $details{$_});
        # n.b.: Giving the full path keeps add_method from having to search
        $ret = $self->add_method(File::Spec->catfile($dir, $_));
        return $ret unless ref $ret;
    }

    $self;
}

# Same as above, but for name-symmetry
sub add_procs_in_dir { shift->add_methods_in_dir(@_) }

###############################################################################
#
#   Sub Name:       delete_method
#
#   Description:    Remove any current binding for the named method on the
#                   calling server object. Note that if this method is shared
#                   across other server objects, it won't be destroyed until
#                   the last server deletes it.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $name     in      scalar    Name of method to lost
#
#   Returns:        Success:    $self
#                   Failure:    error message
#
###############################################################################
sub delete_method
{
    my $self = shift;
    my $name = shift;

    if ($name)
    {
        if ($self->{__method_table}->{$name})
        {
            delete $self->{__method_table}->{$name};
            return $self;
        }
    }
    else
    {
        return ref($self) . "::delete_method: No such method $name";
    }
}

# Same as above, but for name-symmetry
sub delete_proc { shift->delete_method(@_) }

###############################################################################
#
#   Sub Name:       list_methods
#
#   Description:    Return a list of the methods this object has published.
#                   Returns the names, not the objects.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#
#   Returns:        List of names, possibly empty
#
###############################################################################
sub list_methods
{
    keys %{$_[0]->{__method_table}};
}

# Same as above, but for name-symmetry
sub list_procs { shift->list_methods(@_) }

###############################################################################
#
#   Sub Name:       share_methods
#
#   Description:    Share the named methods as found on $src_srv into the
#                   method table of the calling object.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $src_srv  in      ref       Another object of this class
#                   @names    in      list      One or more method names
#
#   Returns:        Success:    $self
#                   Failure:    error message
#
###############################################################################
sub share_methods
{
    my $self    = shift;
    my $src_srv = shift;
    my @names   = @_;

    my ($me, $pkg, %tmp, @tmp, $tmp, $meth, @list, @missing);

    $me = ref($self) . '::share_methods';
    $pkg = __PACKAGE__; # So it can go inside quoted strings

    return "$me: First arg not derived from $pkg, cannot share"
        unless ((ref $src_srv) && (UNIVERSAL::isa($src_srv, $pkg)));
    return "$me: Must specify at least one method name for sharing"
        unless @names;

    #
    # Scan @names for any regez objects, and if found insert the matches into
    # the list.
    #
    # Only do this once:
    #
    @tmp = keys %{$src_srv->{__method_table}};
    for $tmp (@names)
    {
        if (ref($names[$tmp]) eq 'Regexp')
        {
            $tmp{$_}++ for (grep($_ =~ $tmp, @tmp));
        }
        else
        {
            $tmp{$tmp}++;
        }
    }
    # This has the benefit of trimming any redundancies caused by regex's
    @names = keys %tmp;

    #
    # Note that the method refs are saved until we've verified all of them.
    # If we have to return a failure message, I don't want to leave a half-
    # finished job or have to go back and undo (n-1) additions because of one
    # failure.
    #
    for (@names)
    {
        $meth = $src_srv->get_method($_);
        if (ref $meth)
        {
            push(@list, $meth);
        }
        else
        {
            push(@missing, $_);
        }
    }

    if (@missing)
    {
        return "$me: One or more methods not found on source object: @missing";
    }
    else
    {
        $self->add_method($_) for (@list);
    }

    $self;
}

# Same as above, but for name-symmetry
sub share_procs { shift->share_methods(@_) }

###############################################################################
#
#   Sub Name:       copy_methods
#
#   Description:    Copy the named methods as found on $src_srv into the
#                   method table of the calling object. This differs from
#                   share() above in that only the coderef is shared, the
#                   rest of the method is a completely new object.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $src_srv  in      ref       Another object of this class
#                   @names    in      list      One or more method names
#
#   Returns:        Success:    $self
#                   Failure:    error message
#
###############################################################################
sub copy_methods
{
    my $self    = shift;
    my $src_srv = shift;
    my @names   = shift;

    my ($me, $pkg, %tmp, @tmp, $tmp, $meth, @list, @missing);

    $me = ref($self) . '::copy_methods';
    $pkg = __PACKAGE__; # So it can go inside quoted strings

    return "$me: First arg not derived from $pkg, cannot copy"
        unless ((ref $src_srv) && (UNIVERSAL::isa($src_srv, $pkg)));
    return "$me: Must specify at least one method name/regex for copying"
        unless @names;

    #
    # Scan @names for any regez objects, and if found insert the matches into
    # the list.
    #
    # Only do this once:
    #
    @tmp = keys %{$src_srv->{__method_table}};
    for $tmp (@names)
    {
        if (ref($names[$tmp]) eq 'Regexp')
        {
            $tmp{$_}++ for (grep($_ =~ $tmp, @tmp));
        }
        else
        {
            $tmp{$tmp}++;
        }
    }
    # This has the benefit of trimming any redundancies caused by regex's
    @names = keys %tmp;

    #
    # Note that the method clones are saved until we've verified all of them.
    # If we have to return a failure message, I don't want to leave a half-
    # finished job or have to go back and undo (n-1) additions because of one
    # failure.
    #
    for (@names)
    {
        $meth = $src_srv->get_method($_);
        if (ref $meth)
        {
            push(@list, $meth->clone);
        }
        else
        {
            push(@missing, $_);
        }
    }

    if (@missing)
    {
        return "$me: One or more methods not found on source object: @missing";
    }
    else
    {
        $self->add_method($_) for (@list);
    }

    $self;
}

# Same as above, but for name-symmetry
sub copy_procs { shift->copy_methods(@_) }

###############################################################################
#
#   Sub Name:       timeout
#
#   Description:    This sets the timeout for processing connections after
#                   a new connection has been accepted.  It returns the old
#                   timeout value.  If you pass in no value, it returns
#                   the current timeout.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object reference/static class
#                   $timeout  in      ref       New timeout value
#
#   Returns:        $self->{__timeout}
#
###############################################################################
sub timeout
{
    my $self    = shift;
    my $timeout = shift;

    my $old_timeout = $self->{__timeout};
    if ($timeout)
    {
        $self->{__timeout} = $timeout;
    }
    return $old_timeout;
}
