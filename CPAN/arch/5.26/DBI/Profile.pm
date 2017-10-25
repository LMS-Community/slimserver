package DBI::Profile;

=head1 NAME

DBI::Profile - Performance profiling and benchmarking for the DBI

=head1 SYNOPSIS

The easiest way to enable DBI profiling is to set the DBI_PROFILE
environment variable to 2 and then run your code as usual:

  DBI_PROFILE=2 prog.pl

This will profile your program and then output a textual summary
grouped by query when the program exits.  You can also enable profiling by
setting the Profile attribute of any DBI handle:

  $dbh->{Profile} = 2;

Then the summary will be printed when the handle is destroyed.

Many other values apart from are possible - see L<"ENABLING A PROFILE"> below.

=head1 DESCRIPTION

The DBI::Profile module provides a simple interface to collect and
report performance and benchmarking data from the DBI.

For a more elaborate interface, suitable for larger programs, see
L<DBI::ProfileDumper|DBI::ProfileDumper> and L<dbiprof|dbiprof>.
For Apache/mod_perl applications see
L<DBI::ProfileDumper::Apache|DBI::ProfileDumper::Apache>.

=head1 OVERVIEW

Performance data collection for the DBI is built around several
concepts which are important to understand clearly.

=over 4

=item Method Dispatch

Every method call on a DBI handle passes through a single 'dispatch'
function which manages all the common aspects of DBI method calls,
such as handling the RaiseError attribute.

=item Data Collection

If profiling is enabled for a handle then the dispatch code takes
a high-resolution timestamp soon after it is entered. Then, after
calling the appropriate method and just before returning, it takes
another high-resolution timestamp and calls a function to record
the information.  That function is passed the two timestamps
plus the DBI handle and the name of the method that was called.
That data about a single DBI method call is called a I<profile sample>.

=item Data Filtering

If the method call was invoked by the DBI or by a driver then the call is
ignored for profiling because the time spent will be accounted for by the
original 'outermost' call for your code.

For example, the calls that the selectrow_arrayref() method makes
to prepare() and execute() etc. are not counted individually
because the time spent in those methods is going to be allocated
to the selectrow_arrayref() method when it returns. If this was not
done then it would be very easy to double count time spent inside
the DBI.

=item Data Storage Tree

The profile data is accumulated as 'leaves on a tree'. The 'path' through the
branches of the tree to a particular leaf is determined dynamically for each sample.
This is a key feature of DBI profiling.

For each profiled method call the DBI walks along the Path and uses each value
in the Path to step into and grow the Data tree.

For example, if the Path is

  [ 'foo', 'bar', 'baz' ]

then the new profile sample data will be I<merged> into the tree at

  $h->{Profile}->{Data}->{foo}->{bar}->{baz}

But it's not very useful to merge all the call data into one leaf node (except
to get an overall 'time spent inside the DBI' total).  It's more common to want
the Path to include dynamic values such as the current statement text and/or
the name of the method called to show what the time spent inside the DBI was for.

The Path can contain some 'magic cookie' values that are automatically replaced
by corresponding dynamic values when they're used. These magic cookies always
start with a punctuation character.

For example a value of 'C<!MethodName>' in the Path causes the corresponding
entry in the Data to be the name of the method that was called.
For example, if the Path was:

  [ 'foo', '!MethodName', 'bar' ]

and the selectall_arrayref() method was called, then the profile sample data
for that call will be merged into the tree at:

  $h->{Profile}->{Data}->{foo}->{selectall_arrayref}->{bar}

=item Profile Data

Profile data is stored at the 'leaves' of the tree as references
to an array of numeric values. For example:

  [
    106,                  # 0: count of samples at this node
    0.0312958955764771,   # 1: total duration
    0.000490069389343262, # 2: first duration
    0.000176072120666504, # 3: shortest duration
    0.00140702724456787,  # 4: longest duration
    1023115819.83019,     # 5: time of first sample
    1023115819.86576,     # 6: time of last sample
  ]

After the first sample, later samples always update elements 0, 1, and 6, and
may update 3 or 4 depending on the duration of the sampled call.

=back

=head1 ENABLING A PROFILE

Profiling is enabled for a handle by assigning to the Profile
attribute. For example:

  $h->{Profile} = DBI::Profile->new();

The Profile attribute holds a blessed reference to a hash object
that contains the profile data and attributes relating to it.

The class the Profile object is blessed into is expected to
provide at least a DESTROY method which will dump the profile data
to the DBI trace file handle (STDERR by default).

All these examples have the same effect as each other:

  $h->{Profile} = 0;
  $h->{Profile} = "/DBI::Profile";
  $h->{Profile} = DBI::Profile->new();
  $h->{Profile} = {};
  $h->{Profile} = { Path => [] };

Similarly, these examples have the same effect as each other:

  $h->{Profile} = 6;
  $h->{Profile} = "6/DBI::Profile";
  $h->{Profile} = "!Statement:!MethodName/DBI::Profile";
  $h->{Profile} = { Path => [ '!Statement', '!MethodName' ] };

If a non-blessed hash reference is given then the DBI::Profile
module is automatically C<require>'d and the reference is blessed
into that class.

If a string is given then it is processed like this:

    ($path, $module, $args) = split /\//, $string, 3

    @path = split /:/, $path
    @args = split /:/, $args

    eval "require $module" if $module
    $module ||= "DBI::Profile"

    $module->new( Path => \@Path, @args )

So the first value is used to select the Path to be used (see below).
The second value, if present, is used as the name of a module which
will be loaded and it's C<new> method called. If not present it
defaults to DBI::Profile. Any other values are passed as arguments
to the C<new> method. For example: "C<2/DBIx::OtherProfile/Foo:42>".

Numbers can be used as a shorthand way to enable common Path values.
The simplest way to explain how the values are interpreted is to show the code:

    push @Path, "DBI"           if $path_elem & 0x01;
    push @Path, "!Statement"    if $path_elem & 0x02;
    push @Path, "!MethodName"   if $path_elem & 0x04;
    push @Path, "!MethodClass"  if $path_elem & 0x08;
    push @Path, "!Caller2"      if $path_elem & 0x10;

So "2" is the same as "!Statement" and "6" (2+4) is the same as
"!Statement:!Method".  Those are the two most commonly used values.  Using a
negative number will reverse the path. Thus "-6" will group by method name then
statement.

The splitting and parsing of string values assigned to the Profile
attribute may seem a little odd, but there's a good reason for it.
Remember that attributes can be embedded in the Data Source Name
string which can be passed in to a script as a parameter. For
example:

    dbi:DriverName(Profile=>2):dbname
    dbi:DriverName(Profile=>{Username}:!Statement/MyProfiler/Foo:42):dbname

And also, if the C<DBI_PROFILE> environment variable is set then
The DBI arranges for every driver handle to share the same profile
object. When perl exits a single profile summary will be generated
that reflects (as nearly as practical) the total use of the DBI by
the application.


=head1 THE PROFILE OBJECT

The DBI core expects the Profile attribute value to be a hash
reference and if the following values don't exist it will create
them as needed:

=head2 Data

A reference to a hash containing the collected profile data.

=head2 Path

The Path value is a reference to an array. Each element controls the
value to use at the corresponding level of the profile Data tree.

If the value of Path is anything other than an array reference,
it is treated as if it was:

	[ '!Statement' ]

The elements of Path array can be one of the following types:

=head3 Special Constant

B<!Statement>

Use the current Statement text. Typically that's the value of the Statement
attribute for the handle the method was called with. Some methods, like
commit() and rollback(), are unrelated to a particular statement. For those
methods !Statement records an empty string.

For statement handles this is always simply the string that was
given to prepare() when the handle was created.  For database handles
this is the statement that was last prepared or executed on that
database handle. That can lead to a little 'fuzzyness' because, for
example, calls to the quote() method to build a new statement will
typically be associated with the previous statement. In practice
this isn't a significant issue and the dynamic Path mechanism can
be used to setup your own rules.

B<!MethodName>

Use the name of the DBI method that the profile sample relates to.

B<!MethodClass>

Use the fully qualified name of the DBI method, including
the package, that the profile sample relates to. This shows you
where the method was implemented. For example:

  'DBD::_::db::selectrow_arrayref' =>
      0.022902s
  'DBD::mysql::db::selectrow_arrayref' =>
      2.244521s / 99 = 0.022445s avg (first 0.022813s, min 0.022051s, max 0.028932s)

The "DBD::_::db::selectrow_arrayref" shows that the driver has
inherited the selectrow_arrayref method provided by the DBI.

But you'll note that there is only one call to
DBD::_::db::selectrow_arrayref but another 99 to
DBD::mysql::db::selectrow_arrayref. Currently the first
call doesn't record the true location. That may change.

B<!Caller>

Use a string showing the filename and line number of the code calling the method.

B<!Caller2>

Use a string showing the filename and line number of the code calling the
method, as for !Caller, but also include filename and line number of the code
that called that. Calls from DBI:: and DBD:: packages are skipped.

B<!File>

Same as !Caller above except that only the filename is included, not the line number.

B<!File2>

Same as !Caller2 above except that only the filenames are included, not the line number.

B<!Time>

Use the current value of time(). Rarely used. See the more useful C<!Time~N> below.

B<!Time~N>

Where C<N> is an integer. Use the current value of time() but with reduced precision.
The value used is determined in this way:

    int( time() / N ) * N

This is a useful way to segregate a profile into time slots. For example:

    [ '!Time~60', '!Statement' ]

=head3 Code Reference

The subroutine is passed the handle it was called on and the DBI method name.
The current Statement is in $_. The statement string should not be modified,
so most subs start with C<local $_ = $_;>.

The list of values it returns is used at that point in the Profile Path.

The sub can 'veto' (reject) a profile sample by including a reference to undef
in the returned list. That can be useful when you want to only profile
statements that match a certain pattern, or only profile certain methods.

=head3 Subroutine Specifier

A Path element that begins with 'C<&>' is treated as the name of a subroutine
in the DBI::ProfileSubs namespace and replaced with the corresponding code reference.

Currently this only works when the Path is specified by the C<DBI_PROFILE>
environment variable.

Also, currently, the only subroutine in the DBI::ProfileSubs namespace is
C<'&norm_std_n3'>. That's a very handy subroutine when profiling code that
doesn't use placeholders. See L<DBI::ProfileSubs> for more information.

=head3 Attribute Specifier

A string enclosed in braces, such as 'C<{Username}>', specifies that the current
value of the corresponding database handle attribute should be used at that
point in the Path.

=head3 Reference to a Scalar

Specifies that the current value of the referenced scalar be used at that point
in the Path.  This provides an efficient way to get 'contextual' values into
your profile.

=head3 Other Values

Any other values are stringified and used literally.

(References, and values that begin with punctuation characters are reserved.)


=head1 REPORTING

=head2 Report Format

The current accumulated profile data can be formatted and output using

    print $h->{Profile}->format;

To discard the profile data and start collecting fresh data
you can do:

    $h->{Profile}->{Data} = undef;


The default results format looks like this:

  DBI::Profile: 0.001015s 42.7% (5 calls) programname @ YYYY-MM-DD HH:MM:SS
  '' =>
      0.000024s / 2 = 0.000012s avg (first 0.000015s, min 0.000009s, max 0.000015s)
  'SELECT mode,size,name FROM table' =>
      0.000991s / 3 = 0.000330s avg (first 0.000678s, min 0.000009s, max 0.000678s)

Which shows the total time spent inside the DBI, with a count of
the total number of method calls and the name of the script being
run, then a formatted version of the profile data tree.

If the results are being formatted when the perl process is exiting
(which is usually the case when the DBI_PROFILE environment variable
is used) then the percentage of time the process spent inside the
DBI is also shown. If the process is not exiting then the percentage is
calculated using the time between the first and last call to the DBI.

In the example above the paths in the tree are only one level deep and
use the Statement text as the value (that's the default behaviour).

The merged profile data at the 'leaves' of the tree are presented
as total time spent, count, average time spent (which is simply total
time divided by the count), then the time spent on the first call,
the time spent on the fastest call, and finally the time spent on
the slowest call.

The 'avg', 'first', 'min' and 'max' times are not particularly
useful when the profile data path only contains the statement text.
Here's an extract of a more detailed example using both statement
text and method name in the path:

  'SELECT mode,size,name FROM table' =>
      'FETCH' =>
          0.000076s
      'fetchrow_hashref' =>
          0.036203s / 108 = 0.000335s avg (first 0.000490s, min 0.000152s, max 0.002786s)

Here you can see the 'avg', 'first', 'min' and 'max' for the
108 calls to fetchrow_hashref() become rather more interesting.
Also the data for FETCH just shows a time value because it was only
called once.

Currently the profile data is output sorted by branch names. That
may change in a later version so the leaf nodes are sorted by total
time per leaf node.


=head2 Report Destination

The default method of reporting is for the DESTROY method of the
Profile object to format the results and write them using:

    DBI->trace_msg($results, 0);  # see $ON_DESTROY_DUMP below

to write them to the DBI trace() filehandle (which defaults to
STDERR). To direct the DBI trace filehandle to write to a file
without enabling tracing the trace() method can be called with a
trace level of 0. For example:

    DBI->trace(0, $filename);

The same effect can be achieved without changing the code by
setting the C<DBI_TRACE> environment variable to C<0=filename>.

The $DBI::Profile::ON_DESTROY_DUMP variable holds a code ref
that's called to perform the output of the formatted results.
The default value is:

  $ON_DESTROY_DUMP = sub { DBI->trace_msg($results, 0) };

Apart from making it easy to send the dump elsewhere, it can also
be useful as a simple way to disable dumping results.

=head1 CHILD HANDLES

Child handles inherit a reference to the Profile attribute value
of their parent.  So if profiling is enabled for a database handle
then by default the statement handles created from it all contribute
to the same merged profile data tree.


=head1 PROFILE OBJECT METHODS

=head2 format

See L</REPORTING>.

=head2 as_node_path_list

  @ary = $dbh->{Profile}->as_node_path_list();
  @ary = $dbh->{Profile}->as_node_path_list($node, $path);

Returns the collected data ($dbh->{Profile}{Data}) restructured into a list of
array refs, one for each leaf node in the Data tree. This 'flat' structure is
often much simpler for applications to work with.

The first element of each array ref is a reference to the leaf node.
The remaining elements are the 'path' through the data tree to that node.

For example, given a data tree like this:

    {key1a}{key2a}[node1]
    {key1a}{key2b}[node2]
    {key1b}{key2a}{key3a}[node3]

The as_node_path_list() method  will return this list:

    [ [node1], 'key1a', 'key2a' ]
    [ [node2], 'key1a', 'key2b' ]
    [ [node3], 'key1b', 'key2a', 'key3a' ]

The nodes are ordered by key, depth-first.

The $node argument can be used to focus on a sub-tree.
If not specified it defaults to $dbh->{Profile}{Data}.

The $path argument can be used to specify a list of path elements that will be
added to each element of the returned list. If not specified it defaults to a
ref to an empty array.

=head2 as_text

  @txt = $dbh->{Profile}->as_text();
  $txt = $dbh->{Profile}->as_text({
      node      => undef,
      path      => [],
      separator => " > ",
      format    => '%1$s: %11$fs / %10$d = %2$fs avg (first %12$fs, min %13$fs, max %14$fs)'."\n";
      sortsub   => sub { ... },
  );

Returns the collected data ($dbh->{Profile}{Data}) reformatted into a list of formatted strings.
In scalar context the list is returned as a single concatenated string.

A hashref can be used to pass in arguments, the default values are shown in the example above.

The C<node> and <path> arguments are passed to as_node_path_list().

The C<separator> argument is used to join the elements of the path for each leaf node.

The C<sortsub> argument is used to pass in a ref to a sub that will order the list.
The subroutine will be passed a reference to the array returned by
as_node_path_list() and should sort the contents of the array in place.
The return value from the sub is ignored. For example, to sort the nodes by the
second level key you could use:

  sortsub => sub { my $ary=shift; @$ary = sort { $a->[2] cmp $b->[2] } @$ary }

The C<format> argument is a C<sprintf> format string that specifies the format
to use for each leaf node.  It uses the explicit format parameter index
mechanism to specify which of the arguments should appear where in the string.
The arguments to sprintf are:

     1:  path to node, joined with the separator
     2:  average duration (total duration/count)
         (3 thru 9 are currently unused)
    10:  count
    11:  total duration
    12:  first duration
    13:  smallest duration
    14:  largest duration
    15:  time of first call
    16:  time of first call

=head1 CUSTOM DATA MANIPULATION

Recall that C<< $h->{Profile}->{Data} >> is a reference to the collected data.
Either to a 'leaf' array (when the Path is empty, i.e., DBI_PROFILE env var is 1),
or a reference to hash containing values that are either further hash
references or leaf array references.

Sometimes it's useful to be able to summarise some or all of the collected data.
The dbi_profile_merge_nodes() function can be used to merge leaf node values.

=head2 dbi_profile_merge_nodes

  use DBI qw(dbi_profile_merge_nodes);

  $time_in_dbi = dbi_profile_merge_nodes(my $totals=[], @$leaves);

Merges profile data node. Given a reference to a destination array, and zero or
more references to profile data, merges the profile data into the destination array.
For example:

  $time_in_dbi = dbi_profile_merge_nodes(
      my $totals=[],
      [ 10, 0.51, 0.11, 0.01, 0.22, 1023110000, 1023110010 ],
      [ 15, 0.42, 0.12, 0.02, 0.23, 1023110005, 1023110009 ],
  );

$totals will then contain

  [ 25, 0.93, 0.11, 0.01, 0.23, 1023110000, 1023110010 ]

and $time_in_dbi will be 0.93;

The second argument need not be just leaf nodes. If given a reference to a hash
then the hash is recursively searched for leaf nodes and all those found
are merged.

For example, to get the time spent 'inside' the DBI during an http request,
your logging code run at the end of the request (i.e. mod_perl LogHandler)
could use:

  my $time_in_dbi = 0;
  if (my $Profile = $dbh->{Profile}) { # if DBI profiling is enabled
      $time_in_dbi = dbi_profile_merge_nodes(my $total=[], $Profile->{Data});
      $Profile->{Data} = {}; # reset the profile data
  }

If profiling has been enabled then $time_in_dbi will hold the time spent inside
the DBI for that handle (and any other handles that share the same profile data)
since the last request.

Prior to DBI 1.56 the dbi_profile_merge_nodes() function was called dbi_profile_merge().
That name still exists as an alias.

=head1 CUSTOM DATA COLLECTION

=head2 Using The Path Attribute

  XXX example to be added later using a selectall_arrayref call
  XXX nested inside a fetch loop where the first column of the
  XXX outer loop is bound to the profile Path using
  XXX bind_column(1, \${ $dbh->{Profile}->{Path}->[0] })
  XXX so you end up with separate profiles for each loop
  XXX (patches welcome to add this to the docs :)

=head2 Adding Your Own Samples

The dbi_profile() function can be used to add extra sample data
into the profile data tree. For example:

    use DBI;
    use DBI::Profile (dbi_profile dbi_time);

    my $t1 = dbi_time(); # floating point high-resolution time

    ... execute code you want to profile here ...

    my $t2 = dbi_time();
    dbi_profile($h, $statement, $method, $t1, $t2);

The $h parameter is the handle the extra profile sample should be
associated with. The $statement parameter is the string to use where
the Path specifies !Statement. If $statement is undef
then $h->{Statement} will be used. Similarly $method is the string
to use if the Path specifies !MethodName. There is no
default value for $method.

The $h->{Profile}{Path} attribute is processed by dbi_profile() in
the usual way.

The $h parameter is usually a DBI handle but it can also be a reference to a
hash, in which case the dbi_profile() acts on each defined value in the hash.
This is an efficient way to update multiple profiles with a single sample,
and is used by the L<DashProfiler> module.

=head1 SUBCLASSING

Alternate profile modules must subclass DBI::Profile to help ensure
they work with future versions of the DBI.


=head1 CAVEATS

Applications which generate many different statement strings
(typically because they don't use placeholders) and profile with
!Statement in the Path (the default) will consume memory
in the Profile Data structure for each statement. Use a code ref
in the Path to return an edited (simplified) form of the statement.

If a method throws an exception itself (not via RaiseError) then
it won't be counted in the profile.

If a HandleError subroutine throws an exception (rather than returning
0 and letting RaiseError do it) then the method call won't be counted
in the profile.

Time spent in DESTROY is added to the profile of the parent handle.

Time spent in DBI->*() methods is not counted. The time spent in
the driver connect method, $drh->connect(), when it's called by
DBI->connect is counted if the DBI_PROFILE environment variable is set.

Time spent fetching tied variables, $DBI::errstr, is counted.

Time spent in FETCH for $h->{Profile} is not counted, so getting the profile
data doesn't alter it.

DBI::PurePerl does not support profiling (though it could in theory).

For asynchronous queries, time spent while the query is running on the
backend is not counted.

A few platforms don't support the gettimeofday() high resolution
time function used by the DBI (and available via the dbi_time() function).
In which case you'll get integer resolution time which is mostly useless.

On Windows platforms the dbi_time() function is limited to millisecond
resolution. Which isn't sufficiently fine for our needs, but still
much better than integer resolution. This limited resolution means
that fast method calls will often register as taking 0 time. And
timings in general will have much more 'jitter' depending on where
within the 'current millisecond' the start and end timing was taken.

This documentation could be more clear. Probably needs to be reordered
to start with several examples and build from there.  Trying to
explain the concepts first seems painful and to lead to just as
many forward references.  (Patches welcome!)

=cut


use strict;
use vars qw(@ISA @EXPORT @EXPORT_OK $VERSION);
use Exporter ();
use UNIVERSAL ();
use Carp;

use DBI qw(dbi_time dbi_profile dbi_profile_merge_nodes dbi_profile_merge);

$VERSION = "2.015065";

@ISA = qw(Exporter);
@EXPORT = qw(
    DBIprofile_Statement
    DBIprofile_MethodName
    DBIprofile_MethodClass
    dbi_profile
    dbi_profile_merge_nodes
    dbi_profile_merge
    dbi_time
);
@EXPORT_OK = qw(
    format_profile_thingy
);

use constant DBIprofile_Statement	=> '!Statement';
use constant DBIprofile_MethodName	=> '!MethodName';
use constant DBIprofile_MethodClass	=> '!MethodClass';

our $ON_DESTROY_DUMP = sub { DBI->trace_msg(shift, 0) };
our $ON_FLUSH_DUMP   = sub { DBI->trace_msg(shift, 0) };

sub new {
    my $class = shift;
    my $profile = { @_ };
    return bless $profile => $class;
}


sub _auto_new {
    my $class = shift;
    my ($arg) = @_;

    # This sub is called by DBI internals when a non-hash-ref is
    # assigned to the Profile attribute. For example
    #	dbi:mysql(RaiseError=>1,Profile=>!Statement:!MethodName/DBIx::MyProfile/arg1:arg2):dbname
    # This sub works out what to do and returns a suitable hash ref.

    $arg =~ s/^DBI::/2\/DBI::/
        and carp "Automatically changed old-style DBI::Profile specification to $arg";

    # it's a path/module/k1:v1:k2:v2:... list
    my ($path, $package, $args) = split /\//, $arg, 3;
    my @args = (defined $args) ? split(/:/, $args, -1) : ();
    my @Path;

    for my $element (split /:/, $path) {
        if (DBI::looks_like_number($element)) {
            my $reverse = ($element < 0) ? ($element=-$element, 1) : 0;
            my @p;
            # a single "DBI" is special-cased in format()
            push @p, "DBI"			if $element & 0x01;
            push @p, DBIprofile_Statement	if $element & 0x02;
            push @p, DBIprofile_MethodName	if $element & 0x04;
            push @p, DBIprofile_MethodClass	if $element & 0x08;
            push @p, '!Caller2'            	if $element & 0x10;
            push @Path, ($reverse ? reverse @p : @p);
        }
        elsif ($element =~ m/^&(\w.*)/) {
            my $name = "DBI::ProfileSubs::$1"; # capture $1 early
            require DBI::ProfileSubs;
            my $code = do { no strict; *{$name}{CODE} };
            if (defined $code) {
                push @Path, $code;
            }
            else {
                warn "$name: subroutine not found\n";
                push @Path, $element;
            }
        }
        else {
            push @Path, $element;
        }
    }

    eval "require $package" if $package; # silently ignores errors
    $package ||= $class;

    return $package->new(Path => \@Path, @args);
}


sub empty {             # empty out profile data
    my $self = shift;
    DBI->trace_msg("profile data discarded\n",0) if $self->{Trace};
    $self->{Data} = undef;
}

sub filename {          # baseclass method, see DBI::ProfileDumper
    return undef;
}

sub flush_to_disk {     # baseclass method, see DBI::ProfileDumper & DashProfiler::Core
    my $self = shift;
    return unless $ON_FLUSH_DUMP;
    return unless $self->{Data};
    my $detail = $self->format();
    $ON_FLUSH_DUMP->($detail) if $detail;
}


sub as_node_path_list {
    my ($self, $node, $path) = @_;
    # convert the tree into an array of arrays
    # from
    #   {key1a}{key2a}[node1]
    #   {key1a}{key2b}[node2]
    #   {key1b}{key2a}{key3a}[node3]
    # to
    #   [ [node1], 'key1a', 'key2a' ]
    #   [ [node2], 'key1a', 'key2b' ]
    #   [ [node3], 'key1b', 'key2a', 'key3a' ]

    $node ||= $self->{Data} or return;
    $path ||= [];
    if (ref $node eq 'HASH') {    # recurse
        $path = [ @$path, undef ];
        return map {
            $path->[-1] = $_;
            ($node->{$_}) ? $self->as_node_path_list($node->{$_}, $path) : ()
        } sort keys %$node;
    }
    return [ $node, @$path ];
}


sub as_text {
    my ($self, $args_ref) = @_;
    my $separator = $args_ref->{separator} || " > ";
    my $format_path_element = $args_ref->{format_path_element}
        || "%s"; # or e.g., " key%2$d='%s'"
    my $format    = $args_ref->{format}
        || '%1$s: %11$fs / %10$d = %2$fs avg (first %12$fs, min %13$fs, max %14$fs)'."\n";

    my @node_path_list = $self->as_node_path_list(undef, $args_ref->{path});

    $args_ref->{sortsub}->(\@node_path_list) if $args_ref->{sortsub};

    my $eval = "qr/".quotemeta($separator)."/";
    my $separator_re = eval($eval) || quotemeta($separator);
    #warn "[$eval] = [$separator_re]";
    my @text;
    my @spare_slots = (undef) x 7;
    for my $node_path (@node_path_list) {
        my ($node, @path) = @$node_path;
        my $idx = 0;
        for (@path) {
            s/[\r\n]+/ /g;
            s/$separator_re/ /g;
            $_ = sprintf $format_path_element, $_, ++$idx;
        }
        push @text, sprintf $format,
            join($separator, @path),                  # 1=path
            ($node->[0] ? $node->[1]/$node->[0] : 0), # 2=avg
            @spare_slots,
            @$node; # 10=count, 11=dur, 12=first_dur, 13=min, 14=max, 15=first_called, 16=last_called
    }
    return @text if wantarray;
    return join "", @text;
}


sub format {
    my $self = shift;
    my $class = ref($self) || $self;

    my $prologue = "$class: ";
    my $detail = $self->format_profile_thingy(
	$self->{Data}, 0, "    ",
	my $path = [],
	my $leaves = [],
    )."\n";

    if (@$leaves) {
	dbi_profile_merge_nodes(my $totals=[], @$leaves);
	my ($count, $time_in_dbi, undef, undef, undef, $t1, $t2) = @$totals;
	(my $progname = $0) =~ s:.*/::;
	if ($count) {
	    $prologue .= sprintf "%fs ", $time_in_dbi;
	    my $perl_time = ($DBI::PERL_ENDING) ? time() - $^T : $t2-$t1;
	    $prologue .= sprintf "%.2f%% ", $time_in_dbi/$perl_time*100 if $perl_time;
	    my @lt = localtime(time);
	    my $ts = sprintf "%d-%02d-%02d %02d:%02d:%02d",
		1900+$lt[5], $lt[4]+1, @lt[3,2,1,0];
	    $prologue .= sprintf "(%d calls) $progname \@ $ts\n", $count;
	}
	if (@$leaves == 1 && ref($self->{Data}) eq 'HASH' && $self->{Data}->{DBI}) {
	    $detail = "";	# hide the "DBI" from DBI_PROFILE=1
	}
    }
    return ($prologue, $detail) if wantarray;
    return $prologue.$detail;
}


sub format_profile_leaf {
    my ($self, $thingy, $depth, $pad, $path, $leaves) = @_;
    croak "format_profile_leaf called on non-leaf ($thingy)"
	unless UNIVERSAL::isa($thingy,'ARRAY');

    push @$leaves, $thingy if $leaves;
    my ($count, $total_time, $first_time, $min, $max, $first_called, $last_called) = @$thingy;
    return sprintf "%s%fs\n", ($pad x $depth), $total_time
	if $count <= 1;
    return sprintf "%s%fs / %d = %fs avg (first %fs, min %fs, max %fs)\n",
	($pad x $depth), $total_time, $count, $count ? $total_time/$count : 0,
	$first_time, $min, $max;
}


sub format_profile_branch {
    my ($self, $thingy, $depth, $pad, $path, $leaves) = @_;
    croak "format_profile_branch called on non-branch ($thingy)"
	unless UNIVERSAL::isa($thingy,'HASH');
    my @chunk;
    my @keys = sort keys %$thingy;
    while ( @keys ) {
	my $k = shift @keys;
	my $v = $thingy->{$k};
	push @$path, $k;
	push @chunk, sprintf "%s'%s' =>\n%s",
	    ($pad x $depth), $k,
	    $self->format_profile_thingy($v, $depth+1, $pad, $path, $leaves);
	pop @$path;
    }
    return join "", @chunk;
}


sub format_profile_thingy {
    my ($self, $thingy, $depth, $pad, $path, $leaves) = @_;
    return "undef" if not defined $thingy;
    return $self->format_profile_leaf(  $thingy, $depth, $pad, $path, $leaves)
	if UNIVERSAL::isa($thingy,'ARRAY');
    return $self->format_profile_branch($thingy, $depth, $pad, $path, $leaves)
	if UNIVERSAL::isa($thingy,'HASH');
    return "$thingy\n";
}


sub on_destroy {
    my $self = shift;
    return unless $ON_DESTROY_DUMP;
    return unless $self->{Data};
    my $detail = $self->format();
    $ON_DESTROY_DUMP->($detail) if $detail;
    $self->{Data} = undef;
}

sub DESTROY {
    my $self = shift;
    local $@;
    DBI->trace_msg("profile data DESTROY\n",0)
        if (($self->{Trace}||0) >= 2);
    eval { $self->on_destroy };
    if ($@) {
        chomp $@;
        my $class = ref($self) || $self;
        DBI->trace_msg("$class on_destroy failed: $@", 0);
    }
}

1;

