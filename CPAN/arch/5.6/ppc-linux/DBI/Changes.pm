=head1 NAME

DBI::Changes - List of significant changes to the DBI

=cut

=head1 CHANGES in DBI 1.43 (svn rev 373),    28th June 2004

  Fixed connect() and connect_cached() RaiseError/PrintError
    which would sometimes show "(no error string)" as the error.
  Fixed compiler warning thanks to Paul Marquess.
  Fixed "trace level set to" trace message thanks to H.Merijn Brand.
  Fixed DBD::DBM $dbh->{dbm_tables}->{...} to be keyed by the
    table name not the file name thanks to Jeff Zucker.
  Fixed last_insert_id(...) thanks to Rudy Lippan.
  Fixed propagation of scalar/list context into proxied methods.
  Fixed DBI::Profile::DESTROY to not alter $@.
  Fixed DBI::ProfileDumper new() docs thanks to Michael Schwern.
  Fixed _load_class to propagate $@ thanks to Drew Taylor.
  Fixed compile warnings on Win32 thanks to Robert Baron.
  Fixed problem building with recent versions of MakeMaker.
  Fixed DBD::Sponge not to generate warning with threads.
  Fixed DBI_AUTOPROXY to work more than once thanks to Steven Hirsch.

  Changed TraceLevel 1 to not show recursive/nested calls.
  Changed getting or setting an invalid attribute to no longer be
    a fatal error but generate a warning instead.
  Changed selectall_arrayref() to call finish() if
    $attr->{MaxRows} is defined.
  Changed all tests to use Test::More and enhanced the tests thanks
    to Stevan Little and Andy Lester. See http://qa.perl.org/phalanx/
  Changed Test::More minimum prerequisite version to 0.40 (2001).
  Change DBI::Profile header to include timestamp.

  Added DBI->parse_dsn($dsn) method.
  Added warning if build directory path contains whitespace.
  Added docs for parse_trace_flags() and parse_trace_flag().
  Removed "may change" warnings from the docs for table_info(),
    primary_key_info(), and foreign_key_info() methods.

=head1 CHANGES in DBI 1.42 (svn rev 222),    12th March 2004

  Fixed $sth->{NUM_OF_FIELDS} of non-executed statement handle
    to be undef as per the docs (it was 0).
  Fixed t/41prof_dump.t to work with perl5.9.1.
  Fixed DBD_ATTRIB_DELETE macro thanks to Marco Paskamp.
  Fixed DBI::PurePerl looks_like_number() and $DBI::rows.
  Fixed ref($h)->can("foo") to not croak.

  Changed attributes (NAME, TYPE etc) of non-executed statement
    handle to be undef instead of triggering an error.
  Changed ShowErrorStatement to apply to more $dbh methods.
  Changed DBI_TRACE env var so just does this at load time:
    DBI->trace(split '=', $ENV{DBI_TRACE}, 2);
  Improved "invalid number of parameters" error message.
  Added DBI::common as base class for DBI::db, DBD::st etc.
  Moved methods common to all handles into DBI::common.

  Major tracing enhancement:

  Added $h->parse_trace_flags("foo|SQL|7") to map a group of
    trace flags into the corresponding trace flag bits.
  Added automatic calling of parse_trace_flags() if
    setting the trace level to a non-numeric value:
    $h->{TraceLevel}="foo|SQL|7"; $h->trace("foo|SQL|7");
    DBI->connect("dbi:Driver(TraceLevel=SQL|foo):...", ...);
    Currently no trace flags have been defined.
  Added to, and reworked, the trace documentation.
  Added dbivport.h for driver authors to use.

  Major driver additions that Jeff Zucker and I have been working on:

  Added DBI::SQL::Nano a 'smaller than micro' SQL parser
    with an SQL::Statement compatible API. If SQL::Statement
    is installed then DBI::SQL::Nano becomes an empty subclass
    of SQL::Statement, unless the DBI_SQL_NANO env var is true.
  Added DBD::File, modified to use DBI::SQL::Nano.
  Added DBD::DBM, an SQL interface to DBM files using DBD::File.

  Documentation changes:

  Corrected typos in docs thanks to Steffen Goeldner.
  Corrected execute_for_fetch example thanks to Dean Arnold.

=head1 CHANGES in DBI 1.41 (svn rev 130),    22nd February 2004

  Fixed execute_for_array() so tuple_status parameter is optional
    as per docs, thanks to Ed Avis.
  Fixed execute_for_array() docs to say that it returns undef if
    any of the execute() calls fail.
  Fixed take_imp_data() test on m68k reported by Christian Hammers.
  Fixed write_typeinfo_pm inconsistencies in DBI::DBD::Metadata
    thanks to Andy Hassall.
  Fixed $h->{TraceLevel} to not return DBI->trace trace level
    which it used to if DBI->trace trace level was higher.

  Changed set_err() to append to errstr, with a leading "\n" if it's
    not empty, so that multiple error/warning messages are recorded.
  Changed trace to limit elements dumped when an array reference is
    returned from a method to the max(40, $DBI::neat_maxlen/10)
    so that fetchall_arrayref(), for example, doesn't flood the trace.
  Changed trace level to be a four bit integer (levels 0 thru 15)
    and a set of topic flags (no topics have been assigned yet).
  Changed column_info() to check argument count.
  Extended bind_param() TYPE attribute specification to imply
    standard formating of value, eg SQL_DATE implies 'YYYY-MM-DD'.

  Added way for drivers to indicate 'success with info' or 'warning'
    by setting err to "0" for warning and "" for information.
    Both values are false and so don't trigger RaiseError etc.
    Thanks to Steffen Goeldner for the original idea.
  Added $h->{HandleSetErr} = sub { ... } to be called at the
    point that an error, warn, or info state is recorded.
    The code can alter the err, errstr, and state values
    (e.g., to promote an error to a warning, or the reverse).
  Added $h->{PrintWarn} attribute to enable printing of warnings
    recorded by the driver. Defaults to same value as $^W (perl -w).
  Added $h->{ErrCount} attribute, incremented whenever an error is
    recorded by the driver via set_err().
  Added $h->{Executed} attribute, set if do()/execute() called.
  Added \%attr parameter to foreign_key_info() method.
  Added ref count of inner handle to "DESTROY ignored for outer" msg.
  Added Win32 build config checks to DBI::DBD thanks to Andy Hassall.
  Added bind_col to Driver.xst so drivers can define their own.
  Added TYPE attribute to bind_col and specified the expected
    driver behaviour.

  Major update to signal handling docs thanks to Lincoln Baxter.
  Corrected dbiproxy usage doc thanks to Christian Hammers.
  Corrected type_info_all index hash docs thanks to Steffen Goeldner.
  Corrected type_info COLUMN_SIZE to chars not bytes thanks to Dean Arnold.
  Corrected get_info() docs to include details of DBI::Const::GetInfoType.
  Clarified that $sth->{PRECISION} is OCTET_LENGTH for char types.

=head2 Changes in DBI 1.40,    7th January 2004

  Fixed handling of CachedKids when DESTROYing threaded handles.
  Fixed sql_user_name() in DBI::DBD::Metadata (used by write_getinfo_pm)
    to use $dbh->{Username}. Driver authors please update your code.

  Changed connect_cached() when running under Apache::DBI
    to route calls to Apache::DBI::connect().

  Added CLONE() to DBD::Sponge and DBD::ExampleP.
  Added warning when starting a new thread about any loaded driver
    which does not have a CLONE() function.
  Added new prepare_cache($sql, \%attr, 3) option to manage Active handles.
  Added SCALE and NULLABLE support to DBD::Sponge.
  Added missing execute() in fetchall_hashref docs thanks to Iain Truskett.
  Added a CONTRIBUTING section to the docs with notes on creating patches.

=head2 Changes in DBI 1.39,    27th November 2003

  Fixed STORE to not clear error during nested DBI call, again/better,
    thanks to Tony Bowden for the report and helpful test case.
  Fixed DBI dispatch to not try to use AUTOLOAD for driver methods unless
    the method has been declared (as methods should be when using AUTOLOAD).
    This fixes a problem when the Attribute::Handlers module is loaded.
  Fixed cwd check code to use $Config{path_sep} thanks to Steve Hay.
  Fixed unqualified croak() calls thanks to Steffen Goeldner.
  Fixed DBD::ExampleP TYPE and PRECISION attributes thanks to Tom Lowery.
  Fixed tracing of methods that only get traced at high trace levels.

  The level 1 trace no longer includes nested method calls so it generally
    just shows the methods the application explicitly calls.
  Added line to trace log (level>=4) when err/errstr is cleared.
  Updated docs for InactiveDestroy and point out where and when the
    trace includes the process id.
  Update DBI::DBD docs thanks to Steffen Goeldner.
  Removed docs saying that the DBI->data_sources method could be
    passed a $dbh. The $dbh->data_sources method should be used instead.
  Added link to 'DBI recipes' thanks to Giuseppe Maxia:
    http://gmax.oltrelinux.com/dbirecipes.html (note that this
    is not an endorsement that the recipies are 'optimal')

  Note: There is a bug in perl 5.8.2 when configured with threads
  and debugging enabled (bug #24463) which causes a DBI test to fail.

=head2 Changes in DBI 1.38,    21th August 2003

  NOTE: The DBI now requires perl version 5.6.0 or later.
  (As per notice in DBI 1.33 released 27th February 2003)

  Fixed spurious t/03handles failure on 64bit perls reported by H.Merijn Brand.
  Fixed spurious t/15array failure on some perl versions thanks to Ed Avis.
  Fixed build using dmake on windows thanks to Steffen Goeldner.
  Fixed build on using some shells thanks to Gurusamy Sarathy.
  Fixed ParamValues to only be appended to ShowErrorStatement if not empty.
  Fixed $dbh->{Statement} not being writable by drivers in some cases.
  Fixed occasional undef warnings on connect failures thanks to Ed Avis.
  Fixed small memory leak when using $sth->{NAME..._hash}.
  Fixed 64bit warnings thanks to Marian Jancar.
  Fixed DBD::Proxy::db::DESTROY to not alter $@ thanks to Keith Chapman.
  Fixed Makefile.PL status from WriteMakefile() thanks to Leon Brocard.

  Changed "Can't set ...->{Foo}: unrecognised attribute" from an error to a
    warning when running with DBI::ProxyServer to simplify upgrades.
  Changed execute_array() to no longer require ArrayTupleStatus attribute.
  Changed DBI->available_drivers to not hide DBD::Sponge.
  Updated/moved placeholder docs to a better place thanks to Johan Vromans.
  Changed dbd_db_do4 api in Driver.xst to match dbd_st_execute (return int,
    not bool), relevant only to driver authors.
  Changed neat(), and thus trace(), so strings marked as utf8 are presented
    in double quotes instead of single quotes and are not sanitized.

  Added $dbh->data_sources method.
  Added $dbh->last_insert_id method.
  Added $sth->execute_for_fetch($fetch_tuple_sub, \@tuple_status) method.
  Added DBI->installed_versions thanks to Jeff Zucker.
  Added $DBI::Profile::ON_DESTROY_DUMP variable.
  Added docs for DBD::Sponge thanks to Mark Stosberg.

=head2 Changes in DBI 1.37,    15th May 2003

  Fixed "Can't get dbh->{Statement}: unrecognised attribute" error in test
    caused by change to perl internals in 5.8.0
  Fixed to build with latest development perl (5.8.1@19525).
  Fixed C code to use all ANSI declarations thanks to Steven Lembark.

=head2 Changes in DBI 1.36,    11th May 2003

  Fixed DBI->connect to carp instead of croak on 'old-style' usage.
  Fixed connect(,,, { RootClass => $foo }) to not croak if module not found.
  Fixed code generated by DBI::DBD::Metadata thanks to DARREN@cpan.org (#2270)
  Fixed DBI::PurePerl to not reset $@ during method dispatch.
  Fixed VMS build thanks to Michael Schwern.
  Fixed Proxy disconnect thanks to Steven Hirsch.
  Fixed error in DBI::DBD docs thanks to Andy Hassall.

  Changed t/40profile.t to not require Time::HiRes.
  Changed DBI::ProxyServer to load DBI only on first request, which
    helps threaded server mode, thanks to Bob Showalter.
  Changed execute_array() return value from row count to executed
    tuple count, and now the ArrayTupleStatus attribute is mandatory.
    NOTE: That is an API definition change that may affect your code.
  Changed CompatMode attribute to also disable attribute 'quick FETCH'.
  Changed attribute FETCH to be slightly faster thanks to Stas Bekman.

  Added workaround for perl bug #17575 tied hash nested FETCH
    thanks to Silvio Wanka.
  Added Username and Password attributes to connect(..., \%attr) and so
    also embedded in DSN like "dbi:Driver(Username=user,Password=pass):..."
    Username and Password can't contain ")", ",", or "=" characters.
    The predence is DSN first, then \%attr, then $user & $pass parameters,
    and finally the DBI_USER & DBI_PASS environment variables.
    The Username attribute is stored in the $dbh but the Password is not.
  Added ProxyServer HOWTO configure restrictions docs thanks to Jochen Wiedmann.
  Added MaxRows attribute to selectcol_arrayref prompted by Wojciech Pietron.
  Added dump_handle as a method not just a DBI:: utility function.
  Added on-demand by-row data feed into execute_array() using code ref,
    or statement handle. For example, to insert from a select:
    $insert_sth->execute_array( { ArrayTupleFetch => $select_sth, ... } )
  Added warning to trace log when $h->{foo}=... is ignored due to
    invalid prefix (e.g., not 'private_').

=head2 Changes in DBI 1.35,    7th March 2003

  Fixed memory leak in fetchrow_hashref introduced in DBI 1.33.
  Fixed various DBD::Proxy errors introduced in DBI 1.33.
  Fixed to ANSI C in dbd_dr_data_sources thanks to Jonathan Leffler.
  Fixed $h->can($method_name) to return correct code ref.
  Removed DBI::Format from distribution as it's now part of the
    separate DBI::Shell distribution by Tom Lowery.
  Updated DBI::DBD docs with a note about the CLONE method.
  Updated DBI::DBD docs thanks to Jonathan Leffler.
  Updated DBI::DBD::Metadata for perl 5.5.3 thanks to Jonathan Leffler.
  Added note to install_method docs about setup_driver() method.

=head2 Changes in DBI 1.34,    28th February 2003

  Fixed DBI::DBD docs to refer to DBI::DBD::Metadata thanks to Jonathan Leffler.
  Fixed dbi_time() compile using BorlandC on Windows thanks to Steffen Goeldner.
  Fixed profile tests to do enough work to measure on Windows.
  Fixed disconnect_all() to not be required by drivers.

  Added $okay = $h->can($method_name) to check if a method exists.
  Added DBD::*::*->install_method($method_name, \%attr) so driver private
    methods can be 'installed' into the DBI dispatcher and no longer
    need to be called using $h->func(..., $method_name).

  Enhanced $dbh->clone() and documentation.
  Enhanced docs to note that dbi_time(), and thus profiling, is limited
    to only millisecond (seconds/1000) resolution on Windows.
  Removed old DBI::Shell from distribution and added Tom Lowery's improved
    version to the Bundle::DBI file.
  Updated minimum version numbers for modules in Bundle::DBI.

=head2 Changes in DBI 1.33,    27th February 2003

  NOTE: Future versions of the DBI *will not* support perl 5.6.0 or earlier.
  : Perl 5.6.1 will be the minimum supported version.

  NOTE: The "old-style" connect: DBI->connect($database, $user, $pass, $driver);
  : has been deprecated for several years and will now generate a warning.
  : It will be removed in a later release. Please change any old connect() calls.

  Added $dbh2 = $dbh1->clone to make a new connection to the database
    that is identical to the original one. clone() can be called even after
    the original handle has been disconnected. See the docs for more details.

  Fixed merging of profile data to not sum DBIprof_FIRST_TIME values.
  Fixed unescaping of newlines in DBI::ProfileData thanks to Sam Tregar.
  Fixed Taint bug with fetchrow_hashref with help from Bradley Baetz.
  Fixed $dbh->{Active} for DBD::Proxy, reported by Bob Showalter.
  Fixed STORE to not clear error during nested DBI call,
    thanks to Tony Bowden for the report and helpful test case.
  Fixed DBI::PurePerl error clearing behaviour.
  Fixed dbi_time() and thus DBI::Profile on Windows thanks to Smejkal Petr.
  Fixed problem that meant ShowErrorStatement could show wrong statement,
   thanks to Ron Savage for the report and test case.
  Changed Apache::DBI hook to check for $ENV{MOD_PERL} instead of
    $ENV{GATEWAY_INTERFACE} thanks to Ask Bjoern Hansen.
  No longer tries to dup trace logfp when an interpreter is being cloned.
  Database handles no longer inherit shared $h->err/errstr/state storage
    from their drivers, so each $dbh has it's own $h->err etc. values
    and is no longer affected by calls made on other dbh's.
    Now when a dbh is destroyed it's err/errstr/state values are copied
    up to the driver so checking $DBI::errstr still works as expected.

  Build / portability fixes:
    Fixed t/40profile.t to not use Time::HiRes.
    Fixed t/06attrs.t to not be locale sensitive, reported by Christian Hammers.
    Fixed sgi compiler warnings, reported by Paul Blake.
    Fixed build using make -j4, reported by Jonathan Leffler.
    Fixed build and tests under VMS thanks to Craig A. Berry.

  Documentation changes:
    Documented $high_resolution_time = dbi_time() function.
    Documented that bind_col() can take an atribute hash.
    Clarified documentation for ParamValues attribute hash keys.
    Many good DBI documentation tweaks from Jonathan Leffler,
      including a major update to the DBI::DBD driver author guide.
    Clarified that execute() should itself call finish() if it's
      called on a statement handle that's still active.
    Clarified $sth->{ParamValues}. Driver authors please note.
    Removed "NEW" markers on some methods and attributes and
      added text to each giving the DBI version it was added in,
      if it was added after DBI 1.21 (Feb 2002).

  Changes of note for authors of all drivers:
    Added SQL_DATA_TYPE, SQL_DATETIME_SUB, NUM_PREC_RADIX, and
      INTERVAL_PRECISION fields to docs for type_info_all. There were
      already in type_info(), but type_info_all() didn't specify the
      index values.  Please check and update your type_info_all() code.
    Added DBI::DBD::Metadata module that auto-generates your drivers
      get_info and type_info_all data and code, thanks mainly to
      Jonathan Leffler and Steffen Goeldner. If you've not implemented
      get_info and type_info_all methods and your database has an ODBC
      driver available then this will do all the hard work for you!
    Drivers should no longer pass Err, Errstr, or State to _new_drh
      or _new_dbh functions.
    Please check that you support the slightly modified behaviour of
      $sth->{ParamValues}, e.g., always return hash with keys if possible.

  Changes of note for authors of compiled drivers:
    Added dbd_db_login6 & dbd_st_finish3 prototypes thanks to Jonathan Leffler.
    All dbd_*_*() functions implemented by drivers must have a
      corresponding #define dbd_*_* <driver_prefix>_*_* otherwise
      the driver may not work with a future release of the DBI.

  Changes of note for authors of drivers which use Driver.xst:
    Some new method hooks have been added are are enabled by
      defining corresponding macros:
          $drh->data_sources()      - dbd_dr_data_sources
          $dbh->do()                - dbd_db_do4
    The following methods won't be compiled into the driver unless
      the corresponding macro has been #defined:
          $drh->disconnect_all()    - dbd_discon_all


=head2 Changes in DBI 1.32,    1st December 2002

  Fixed to work with 5.005_03 thanks to Tatsuhiko Miyagawa (I've not tested it).
  Reenabled taint tests (accidentally left disabled) spotted by Bradley Baetz.
  Improved docs for FetchHashKeyName attribute thanks to Ian Barwick.
  Fixed core dump if fetchrow_hashref given bad argument (name of attribute
    with a value that wasn't an array reference), spotted by Ian Barwick.
  Fixed some compiler warnings thanks to David Wheeler.
  Updated Steven Hirsch's enhanced proxy work (seems I left out a bit).
  Made t/40profile.t tests more reliable, reported by Randy, who is part of
    the excellent CPAN testers team: http://testers.cpan.org/
    (Please visit, see the valuable work they do and, ideally, join in!)

=head2 Changes in DBI 1.31,    29th November 2002

  The fetchall_arrayref method, when called with a $maxrows parameter,
    no longer gives an error if called again after all rows have been
    fetched. This simplifies application logic when fetching in batches.
    Also added batch-fetch while() loop example to the docs.
  The proxy now supports non-lazy (synchronous) prepare, positioned
    updates (for selects containing 'for update'), PlRPC config set
    via attributes, and accurate propagation of errors, all thanks
    to Steven Hirsch (plus a minor fix from Sean McMurray and doc
    tweaks from Michael A Chase).
  The DBI_AUTOPROXY env var can now hold the full dsn of the proxy driver
    plus attributes, like "dbi:Proxy(proxy_foo=>1):host=...".
  Added TaintIn & TaintOut attributes to give finer control over
    tainting thanks to Bradley Baetz.
  The RootClass attribute no longer ignores failure to load a module,
    but also doesn't try to load a module if the class already exists,
    with thanks to James FitzGibbon.
  HandleError attribute works for connect failures thanks to David Wheeler.
  The connect() RaiseError/PrintError message now includes the username.
  Changed "last handle unknown or destroyed" warning to be a trace message.
  Removed undocumented $h->event() method.
  Further enhancements to DBD::PurePerl accuracy.
  The CursorName attribute now defaults to undef and not an error.

  DBI::Profile changes:
    New DBI::ProfileDumper, DBI::ProfileDumper::Apache, and
    DBI::ProfileData modules (to manage the storage and processing
    of profile data), plus dbiprof program for analyzing profile
    data - with many thanks to Sam Tregar.
    Added $DBI::err (etc) tied variable lookup time to profile.
    Added time for DESTROY method into parent handles profile (used to be ignored).

  Documentation changes:
    Documented $dbh = $sth->{Database} attribute.
    Documented $dbh->connected(...) post-connection call when subclassing.
    Updated some minor doc issues thanks to H.Merijn Brand.
    Updated Makefile.PL example in DBI::DBD thanks to KAWAI,Takanori.
    Fixed execute_array() example thanks to Peter van Hardenberg.

  Changes for driver authors, not required but strongly recommended:
    Change DBIS to DBIc_DBISTATE(imp_xxh)   [or imp_dbh, imp_sth etc]
    Change DBILOGFP to DBIc_LOGPIO(imp_xxh) [or imp_dbh, imp_sth etc]
    Any function from which all instances of DBIS and DBILOGFP are
    removed can also have dPERLINTERP removed (a good thing).
    All use of the DBIh_EVENT* macros should be removed.
    Major update to DBI::DBD docs thanks largely to Jonathan Leffler.
    Add these key values: 'Err' => \my $err, 'Errstr' => \my $errstr,
    to the hash passed to DBI::_new_dbh() in your driver source code.
    That will make each $dbh have it's own $h->err and $h->errstr
    values separate from other $dbh belonging to the same driver.
    If you have a ::db or ::st DESTROY methods that do nothing
    you can now remove them - which speeds up handle destruction.


=head2 Changes in DBI 1.30,    18th July 2002

  Fixed problems with selectrow_array, selectrow_arrayref, and
    selectall_arrayref introduced in DBI 1.29.
  Fixed FETCHing a handle attribute to not clear $DBI::err etc (broken in 1.29).
  Fixed core dump at trace level 9 or above.
  Fixed compilation with perl 5.6.1 + ithreads (i.e. Windows).
  Changed definition of behaviour of selectrow_array when called in a scalar
    context to match fetchrow_array.
  Corrected selectrow_arrayref docs which showed selectrow_array thanks to Paul DuBois.

=head2 Changes in DBI 1.29,    15th July 2002

  NOTE: This release changes the specified behaviour for the
  : fetchrow_array method when called in a scalar context:
  : The DBI spec used to say that it would return the FIRST field.
  : Which field it returns (i.e., the first or the last) is now undefined.
  : This does not affect statements that only select one column, which is
  : usually the case when fetchrow_array is called in a scalar context.
  : FYI, this change was triggered by discovering that the fetchrow_array
  : implementation in Driver.xst (used by most compiled drivers) 
  : didn't match the DBI specification. Rather than change the code
  : to match, and risk breaking existing applications, I've changed the
  : specification (that part was always of dubious value anyway).

  NOTE: Future versions of the DBI may not support for perl 5.5 much longer.
  : If you are still using perl 5.005_03 you should be making plans to
  : upgrade to at least perl 5.6.1, or 5.8.0. Perl 5.8.0 is due to be
  : released in the next week or so.  (Although it's a "point 0" release,
  : it is the most throughly tested release ever.)

  Added XS/C implementations of selectrow_array, selectrow_arrayref, and
    selectall_arrayref to Driver.xst. See DBI 1.26 Changes for more info.
  Removed support for the old (fatally flawed) "5005" threading model.
  Added support for new perl 5.8 iThreads thanks to Gerald Richter.
    (Threading support and safety should still be regarded as beta
    quality until further notice. But it's much better than it was.)
  Updated the "Threads and Thread Safety" section of the docs.
  The trace output can be sent to STDOUT instead of STDERR by using
    "STDOUT" as the name of the file, i.e., $h->trace(..., "STDOUT")
  Added pointer to perlreftut, perldsc, perllol, and perlboot manuals
    into the intro section of the docs, suggested by Brian McCain.
  Fixed DBI::Const::GetInfo::* pod docs thanks to Zack Weinberg.
  Some changes to how $dbh method calls are treated by DBI::Profile:
    Meta-data methods now clear $dbh->{Statement} on entry.
    Some $dbh methods are now profiled as if $dbh->{Statement} was empty
    (because thet're unlikely to actually relate to its contents).
  Updated dbiport.h to ppport.h from perl 5.8.0.
  Tested with perl 5.5.3 (vanilla, Solaris), 5.6.1 (vanilla, Solaris), and
    perl 5.8.0 (RC3@17527 with iThreads & Multiplicity on Solaris and FreeBSD).

=head2 Changes in DBI 1.28,    14th June 2002

  Added $sth->{ParamValues} to return a hash of the most recent
    values bound to placeholders via bind_param() or execute().
    Individual drivers need to be updated to support it.
  Enhanced ShowErrorStatement to include ParamValues if available:
    "DBD::foo::st execute failed: errstr [for statement ``...'' with params: 1='foo']"
  Further enhancements to DBD::PurePerl accuracy.

=head2 Changes in DBI 1.27,    13th June 2002

  Fixed missing column in C implementation of fetchall_arrayref()
    thanks to Philip Molter for the prompt reporting of the problem.

=head2 Changes in DBI 1.26,    13th June 2002

  Fixed t/40profile.t to work on Windows thanks to Smejkal Petr.
  Fixed $h->{Profile} to return undef, not error, if not set.
  Fixed DBI->available_drivers in scalar context thanks to Michael Schwern.

  Added C implementations of selectrow_arrayref() and fetchall_arrayref()
    in Driver.xst.  All compiled drivers using Driver.xst will now be
    faster making those calls. Most noticable with fetchall_arrayref for
    many rows or selectrow_arrayref with a fast query. For example, using
    DBD::mysql a selectrow_arrayref for a single row using a primary key
    is ~20% faster, and fetchall_arrayref for 20000 rows is twice as fast!
    Drivers just need to be recompiled and reinstalled to enable it.
    The fetchall_arrayref speed up only applies if $slice parameter is not used.
  Added $max_rows parameter to fetchall_arrayref() to optionally limit
    the number of rows returned. Can now fetch batches of rows.
  Added MaxRows attribute to selectall_arrayref()
    which then passes it to fetchall_arrayref().
  Changed selectrow_array to make use of selectrow_arrayref.
  Trace level 1 now shows first two parameters of all methods
    (used to only for that for some, like prepare,execute,do etc)
  Trace indicator for recursive calls (first char on trace lines)
    now starts at 1 not 2.

  Documented that $h->func() does not trigger RaiseError etc
    so applications must explicitly check for errors.
  DBI::Profile with DBI_PROFILE now shows percentage time inside DBI.
  HandleError docs updated to show that handler can edit error message.
  HandleError subroutine interface is now regarded as stable.

=head2 Changes in DBI 1.25,    5th June 2002

  Fixed build problem on Windows and some compiler warnings.
  Fixed $dbh->{Driver} and $sth->{Statement} for driver internals
    These are 'inner' handles as per behaviour prior to DBI 1.16.
  Further minor improvements to DBI::PurePerl accuracy.

=head2 Changes in DBI 1.24,    4th June 2002

  Fixed reference loop causing a handle/memory leak
    that was introduced in DBI 1.16.
  Fixed DBI::Format to work with 'filehandles' from IO::Scalar
    and similar modules thanks to report by Jeff Boes.
  Fixed $h->func for DBI::PurePerl thanks to Jeff Zucker.
  Fixed $dbh->{Name} for DBI::PurePerl thanks to Dean Arnold.

  Added DBI method call profiling and benchmarking.
    This is a major new addition to the DBI.
    See $h->{Profile} attribute and DBI::Profile module.
    For a quick trial, set the DBI_PROFILE environment variable and
    run your favourite DBI script. Try it with DBI_PROFILE set to 1,
    then try 2, 4, 8, 10, and -10. Have fun!

  Added execute_array() and bind_param_array() documentation
    with thanks to Dean Arnold.
  Added notes about the DBI having not yet been tested with iThreads
    (testing and patches for SvLOCK etc welcome).
  Removed undocumented Handlers attribute (replaced by HandleError).
  Tested with 5.5.3 and 5.8.0 RC1.

=head2 Changes in DBI 1.23,    25th May 2002

  Greatly improved DBI::PurePerl in performance and accuracy.
  Added more detail to DBI::PurePerl docs about what's not supported.
  Fixed undef warnings from t/15array.t and DBD::Sponge.

=head2 Changes in DBI 1.22,    22nd May 2002

  Added execute_array() and bind_param_array() with special thanks
    to Dean Arnold. Not yet documented. See t/15array.t for examples.
    All drivers now automatically support these methods.
  Added DBI::PurePerl, a transparent DBI emulation for pure-perl drivers
    with special thanks to Jeff Zucker. Perldoc DBI::PurePerl for details.
  Added DBI::Const::GetInfo* modules thanks to Steffen Goeldner.
  Added write_getinfo_pm utility to DBI::DBD thanks to Steffen Goeldner.
  Added $allow_active==2 mode for prepare_cached() thanks to Stephen Clouse.

  Updated DBI::Format to Revision 11.4 thanks to Tom Lowery.
  Use File::Spec in Makefile.PL (helps VMS etc) thanks to Craig Berry.
  Extend $h->{Warn} to commit/rollback ineffective warning thanks to Jeff Baker.
  Extended t/preparse.t and removed "use Devel::Peek" thanks to Scott Hildreth.
  Only copy Changes to blib/lib/Changes.pm once thanks to Jonathan Leffler.
  Updated internals for modern perls thanks to Jonathan Leffler and Jeff Urlwin.
  Tested with perl 5.7.3 (just using default perl config).

  Documentation changes:

  Added 'Catalog Methods' section to docs thanks to Steffen Goeldner.
  Updated README thanks to Michael Schwern.
  Clarified that driver may choose not to start new transaction until
    next use of $dbh after commit/rollback.
  Clarified docs for finish method.
  Clarified potentials problems with prepare_cached() thanks to Stephen Clouse.


=head2 Changes in DBI 1.21,    7th February 2002

  The minimum supported perl version is now 5.005_03.

  Fixed DBD::Proxy support for AutoCommit thanks to Jochen Wiedmann.
  Fixed DBI::ProxyServer bind_param(_inout) handing thanks to Oleg Mechtcheriakov.
  Fixed DBI::ProxyServer fetch loop thanks to nobull@mail.com.
  Fixed install_driver do-the-right-thing with $@ on error. It, and connect(),
    will leave $@ empty on success and holding the error message on error.
    Thanks to Jay Lawrence, Gavin Sherlock and others for the bug report.
  Fixed fetchrow_hashref to assign columns to the hash left-to-right
    so later fields with the same name overwrite earlier ones
    as per DBI < 1.15, thanks to Kay Roepke.

  Changed tables() to use quote_indentifier() if the driver returns a
    true value for $dbh->get_info(29) # SQL_IDENTIFIER_QUOTE_CHAR
  Changed ping() so it no longer triggers RaiseError/PrintError.
  Changed connect() to not call $class->install_driver unless needed.
  Changed DESTROY to catch fatal exceptions and append to $@.

  Added ISO SQL/CLI & ODBCv3 data type definitions thanks to Steffen Goeldner.
  Removed the definition of SQL_BIGINT data type constant as the value is
    inconsistent between standards (ODBC=-5, SQL/CLI=25).
  Added $dbh->column_info(...) thanks to Steffen Goeldner.
  Added $dbh->foreign_key_info(...) thanks to Steffen Goeldner.
  Added $dbh->quote_identifier(...) insipred by Simon Oliver.
  Added $dbh->set_err(...) for DBD authors and DBI subclasses
    (actually been there for a while, now expanded and documented).
  Added $h->{HandleError} = sub { ... } addition and/or alternative
    to RaiseError/PrintError. See the docs for more info.
  Added $h->{TraceLevel} = N attribute to set/get trace level of handle
    thus can set trace level via an (eg externally specified) DSN
    using the embedded attribute syntax:
      $dsn = 'dbi:DB2(PrintError=1,TraceLevel=2):dbname';
    Plus, you can also now do: local($h->{TraceLevel}) = N;
    (but that leaks a little memory in some versions of perl).
  Added some call tree information to trace output if trace level >= 3
    With thanks to Graham Barr for the stack walking code.
  Added experimental undocumented $dbh->preparse(), see t/preparse.t
    With thanks to Scott T. Hildreth for much of the work.
  Added Fowler/Noll/Vo hash type as an option to DBI::hash().

  Documentation changes:

  Added DBI::Changes so now you can "perldoc DBI::Changes", yeah!
  Added selectrow_arrayref & selectrow_hashref docs thanks to Doug Wilson.
  Added 'Standards Reference Information' section to docs to gather
    together all references to relevant on-line standards.
  Added link to poop.sourceforge.net into the docs thanks to Dave Rolsky.
  Added link to hyperlinked BNF for SQL92 thanks to Jeff Zucker.
  Added 'Subclassing the DBI' docs thanks to Stephen Clouse, and
    then changed some of them to reflect the new approach to subclassing.
  Added stronger wording to description of $h->{private_*} attributes.
  Added docs for DBI::hash.

  Driver API changes:

  Now a COPY of the DBI->connect() attributes is passed to the driver
    connect() method, so it can process and delete any elements it wants.
    Deleting elements reduces/avoids the explicit
      $dbh->{$_} = $attr->{$_} foreach keys %$attr;
    that DBI->connect does after the driver connect() method returns.


=head2 Changes in DBI 1.20,    24th August 2001

  WARNING: This release contains two changes that may affect your code.
  : Any code using selectall_hashref(), which was added in March 2001, WILL
  : need to be changed. Any code using fetchall_arrayref() with a non-empty
  : hash slice parameter may, in a few rare cases, need to be changed.
  : See the change list below for more information about the changes.
  : See the DBI documentation for a description of current behaviour.

  Fixed memory leak thanks to Toni Andjelkovic.
  Changed fetchall_arrayref({ foo=>1, ...}) specification again (sorry):
    The key names of the returned hashes is identical to the letter case of
    the names in the parameter hash, regardless of the L</FetchHashKeyName>
    attribute. The letter case is ignored for matching.
  Changed fetchall_arrayref([...]) array slice syntax specification to
    clarify that the numbers in the array slice are perl index numbers
    (which start at 0) and not column numbers (which start at 1).
  Added { Columns=>... } and { Slice =>... } attributes to selectall_arrayref()
    which is passed to fetchall_arrayref() so it can fetch hashes now.
  Added a { Columns => [...] } attribute to selectcol_arrayref() so that
    the list it returns can be built from more than one column per row.
    Why? Consider my %hash = @{$dbh->selectcol_arrayref($sql,{ Columns=>[1,2]})}
    to return id-value pairs which can be used directly to build a hash.
  Added $hash_ref = $sth->fetchall_hashref( $key_field )
    which returns a ref to a hash with, typically, one element per row.
    $key_field is the name of the field to get the key for each row from.
    The value of the hash for each row is a hash returned by fetchrow_hashref.
  Changed selectall_hashref to return a hash ref (from fetchall_hashref)
    and not an array of hashes as it has since DBI 1.15 (end March 2001).
    WARNING: THIS CHANGE WILL BREAK ANY CODE USING selectall_hashref()!
    Sorry, but I think this is an important regularization of the API.
    To get previous selectall_hashref() behaviour (an array of hash refs)
    change $ary_ref = $dbh->selectall_hashref( $statement, undef, @bind);
	to $ary_ref = $dbh->selectall_arrayref($statement, { Columns=>{} }, @bind);
  Added NAME_lc_hash, NAME_uc_hash, NAME_hash statement handle attributes.
    which return a ref to a hash of field_name => field_index (0..n-1) pairs.
  Fixed select_hash() example thanks to Doug Wilson.
  Removed (unbundled) DBD::ADO and DBD::Multiplex from the DBI distribution.
    The latest versions of those modules are available from CPAN sites.
  Added $dbh->begin_work. This method causes AutoCommit to be turned
    off just until the next commit() or rollback().
    Driver authors: if the DBIcf_BegunWork flag is set when your commit or
    rollback method is called then please turn AutoCommit on and clear the
    DBIcf_BegunWork flag. If you don't then the DBI will but it'll be much
    less efficient and won't handle error conditions very cleanly.
  Retested on perl 5.4.4, but the DBI won't support 5.4.x much longer.
  Added text to SUPPORT section of the docs:
    For direct DBI and DBD::Oracle support, enhancement, and related work
    I am available for consultancy on standard commercial terms.
  Added text to ACKNOWLEDGEMENTS section of the docs:
    Much of the DBI and DBD::Oracle was developed while I was Technical
    Director (CTO) of the Paul Ingram Group (www.ig.co.uk).  So I'd
    especially like to thank Paul for his generosity and vision in
    supporting this work for many years.

=head2 Changes in DBI 1.19,    20th July 2001

  Made fetchall_arrayref({ foo=>1, ...}) be more strict to the specification
    in relation to wanting hash slice keys to be lowercase names.
    WARNING: If you've used fetchall_arrayref({...}) with a hash slice
    that contains keys with uppercase letters then your code will break.
    (As far as I recall the spec has always said don't do that.)
  Fixed $sth->execute() to update $dbh->{Statement} to $sth->{Statement}.
  Added row number to trace output for fetch method calls.
  Trace level 1 no longer shows fetches with row>1 (to reduce output volume).
  Added $h->{FetchHashKeyName} = 'NAME_lc' or 'NAME_uc' to alter
    behaviour of fetchrow_hashref() method. See docs.
  Added type_info quote caching to quote() method thanks to Dean Kopesky.
    Makes using quote() with second data type param much much faster.
  Added type_into_all() caching to type_info(), spotted by Dean Kopesky.
  Added new API definition for table_info() and tables(),
    driver authors please note!
  Added primary_key_info() to DBI API thanks to Steffen Goeldner.
  Added primary_key() to DBI API as simpler interface to primary_key_info().
  Indent and other fixes for DBI::DBD doc thanks to H.Merijn Brand.
  Added prepare_cached() insert_hash() example thanks to Doug Wilson.
  Removed false docs for fetchall_hashref(), use fetchall_arrayref({}).

=head2 Changes in DBI 1.18,    4th June 2001

  Fixed that altering ShowErrorStatement also altered AutoCommit!
    Thanks to Jeff Boes for spotting that clanger.
  Fixed DBD::Proxy to handle commit() and rollback(). Long overdue, sorry.
  Fixed incompatibility with perl 5.004 (but no one's using that right? :)
  Fixed connect_cached and prepare_cached to not be affected by the order
    of elements in the attribute hash. Spotted by Mitch Helle-Morrissey.
  Fixed version number of DBI::Shell
    reported by Stuhlpfarrer Gerhard and others.
  Defined and documented table_info() attribute semantics (ODBC compatible)
    thanks to Olga Voronova, who also implemented then in DBD::Oracle.
  Updated Win32::DBIODBC (Win32::ODBC emulation) thanks to Roy Lee.

=head2 Changes in DBI 1.16,    30th May 2001

  Reimplemented fetchrow_hashref in C, now fetches about 25% faster!
  Changed behaviour if both PrintError and RaiseError are enabled
    to simply do both (in that order, obviously :)
  Slight reduction in DBI handle creation overhead.
  Fixed $dbh->{Driver} & $sth->{Database} to return 'outer' handles.
  Fixed execute param count check to honour RaiseError spotted by Belinda Giardie.
  Fixed build for perl5.6.1 with PERLIO thanks to H.Merijn Brand.
  Fixed client sql restrictions in ProxyServer.pm thanks to Jochen Wiedmann.
  Fixed batch mode command parsing in Shell thanks to Christian Lemburg.
  Fixed typo in selectcol_arrayref docs thanks to Jonathan Leffler.
  Fixed selectrow_hashref to be available to callers thanks to T.J.Mather.
  Fixed core dump if statement handle didn't define Statement attribute.
  Added bind_param_inout docs to DBI::DBD thanks to Jonathan Leffler.
  Added note to data_sources() method docs that some drivers may
    require a connected database handle to be supplied as an attribute.
  Trace of install_driver method now shows path of driver file loaded.
  Changed many '||' to 'or' in the docs thanks to H.Merijn Brand.
  Updated DBD::ADO again (improvements in error handling) from Tom Lowery.
  Updated Win32::DBIODBC (Win32::ODBC emulation) thanks to Roy Lee.
  Updated email and web addresses in DBI::FAQ thanks to Michael A Chase.

=head2 Changes in DBI 1.15,    28th March 2001

  Added selectrow_arrayref
  Added selectrow_hashref
  Added selectall_hashref thanks to Leon Brocard.
  Added DBI->connect(..., { dbi_connect_method => 'method' })
  Added $dbh->{Statement} aliased to most recent child $sth->{Statement}.
  Added $h->{ShowErrorStatement}=1 to cause the appending of the
    relevant Statement text to the RaiseError/PrintError text.
  Modified type_info to always return hash keys in uppercase and
    to not require uppercase 'DATA_TYPE' key from type_info_all.
    Thanks to Jennifer Tong and Rob Douglas.
  Added \%attr param to tables() and table_info() methods.
  Trace method uses warn() if it can't open the new file.
  Trace shows source line and filename during global destruction.
  Updated packages:
    Updated Win32::DBIODBC (Win32::ODBC emulation) thanks to Roy Lee.
    Updated DBD::ADO to much improved version 0.4 from Tom Lowery.
    Updated DBD::Sponge to include $sth->{PRECISION} thanks to Tom Lowery.
    Changed DBD::ExampleP to use lstat() instead of stat().
  Documentation:
    Documented $DBI::lasth (which has been there since day 1).
    Documented SQL_* names.
    Clarified and extended docs for $h->state thanks to Masaaki Hirose.
    Clarified fetchall_arrayref({}) docs (thanks to, er, someone!).
    Clarified type_info_all re lettercase and index values.
    Updated DBI::FAQ to 0.38 thanks to Alligator Descartes.
    Added cute bind_columns example thanks to H.Merijn Brand.
    Extended docs on \%attr arg to data_sources method.
  Makefile.PL
    Removed obscure potential 'rm -rf /' (thanks to Ulrich Pfeifer).
    Removed use of glob and find (thanks to Michael A. Chase).
  Proxy:
    Removed debug messages from DBD::Proxy AUTOLOAD thanks to Brian McCauley.
    Added fix for problem using table_info thanks to Tom Lowery.
    Added better determination of where to put the pid file, and...
    Added KNOWN ISSUES section to DBD::Proxy docs thanks to Jochen Wiedmann.
  Shell:
    Updated DBI::Format to include DBI::Format::String thanks to Tom Lowery.
    Added describe command thanks to Tom Lowery.
    Added columnseparator option thanks to Tom Lowery (I think).
    Added 'raw' format thanks to, er, someone, maybe Tom again.
  Known issues:
    Perl 5.005 and 5.006 both leak memory doing local($handle->{Foo}).
    Perl 5.004 doesn't. The leak is not a DBI or driver bug.

=head2 Changes in DBI 1.14,	14th June 2000

  NOTE: This version is the one the DBI book is based on.
  NOTE: This version requires at least Perl 5.004.
  Perl 5.6 ithreads changes with thanks to Doug MacEachern.
  Changed trace output to use PerlIO thanks to Paul Moore.
  Fixed bug in RaiseError/PrintError handling.
    (% chars in the error string could cause a core dump.)
  Fixed Win32 PerlEx IIS concurrency bugs thanks to Murray Nesbitt.
  Major documentation polishing thanks to Linda Mui at O'Reilly.
  Password parameter now shown as **** in trace output.
  Added two fields to type_info and type_info_all.
  Added $dsn to PrintError/RaiseError message from DBI->connect().
  Changed prepare_cached() croak to carp if sth still Active.
  Added prepare_cached() example to the docs.
  Added further DBD::ADO enhancements from Thomas Lowery.

=head2 Changes in DBI 1.13,	11th July 1999

  Fixed Win32 PerlEx IIS concurrency bugs thanks to Murray Nesbitt.
  Fixed problems with DBD::ExampleP long_list test mode.
  Added SQL_WCHAR SQL_WVARCHAR SQL_WLONGVARCHAR and SQL_BIT
    to list of known and exportable SQL types.
  Improved data fetch performance of DBD::ADO.
  Added GetTypeInfo to DBD::ADO thanks to Thomas Lowery.
  Actually documented connect_cached thanks to Michael Schwern.
  Fixed user/key/cipher bug in ProxyServer thanks to Joshua Pincus.

=head2 Changes in DBI 1.12,	29th June 1999

  Fixed significant DBD::ADO bug (fetch skipped first row).
  Fixed ProxyServer bug handling non-select statements.
  Fixed VMS problem with t/examp.t thanks to Craig Berry.
  Trace only shows calls to trace_msg and _set_fbav at high levels.
  Modified t/examp.t to workaround Cygwin buffering bug.

=head2 Changes in DBI 1.11,	17th June 1999

  Fixed bind_columns argument checking to allow a single arg.
  Fixed problems with internal default_user method.
  Fixed broken DBD::ADO.
  Made default $DBI::rows more robust for some obscure cases.

=head2 Changes in DBI 1.10,	14th June 1999

  Fixed trace_msg.al error when using Apache.
  Fixed dbd_st_finish enhancement in Driver.xst (internals).
  Enable drivers to define default username and password
    and temporarily disabled warning added in 1.09.
  Thread safety optimised for single thread case.

=head2 Changes in DBI 1.09,	9th June 1999

  Added optional minimum trace level parameter to trace_msg().
  Added warning in Makefile.PL that DBI will require 5.004 soon.
  Added $dbh->selectcol_arrayref($statement) method.
  Fixed fetchall_arrayref hash-slice mode undef NAME problem.
  Fixed problem with tainted parameter checking and t/examp.t.
  Fixed problem with thread safety code, including 64 bit machines.
  Thread safety now enabled by default for threaded perls.
  Enhanced code for MULTIPLICITY/PERL_OBJECT from ActiveState.
  Enhanced prepare_cached() method.
  Minor changes to trace levels (less internal info at level 2).
  Trace log now shows "!! ERROR..." before the "<- method" line.
  DBI->connect() now warn's if user / password is undefined and
    DBI_USER / DBI_PASS environment variables are not defined.
  The t/proxy.t test now ignores any /etc/dbiproxy.conf file.
  Added portability fixes for MacOS from Chris Nandor.
  Updated mailing list address from fugue.com to isc.org.

=head2 Changes in DBI 1.08,	12th May 1999

  Much improved DBD::ADO driver thanks to Phlip Plumlee and others.
  Connect now allows you to specify attribute settings within the DSN
    E.g., "dbi:Driver(RaiseError=>1,Taint=>1,AutoCommit=>0):dbname"
  The $h->{Taint} attribute now also enables taint checking of
    arguments to almost all DBI methods.
  Improved trace output in various ways.
  Fixed bug where $sth->{NAME_xx} was undef in some situations.
  Fixed code for MULTIPLICITY/PERL_OBJECT thanks to Alex Smishlajev.
  Fixed and documented DBI->connect_cached.
  Workaround for Cygwin32 build problem with help from Jong-Pork Park.
  bind_columns no longer needs undef or hash ref as first parameter.

=head2 Changes in DBI 1.07,	6th May 1999

  Trace output now shows contents of array refs returned by DBI.
  Changed names of some result columns from type_info, type_info_all,
    tables and table_info to match ODBC 3.5 / ISO/IEC standards.
  Many fixes for DBD::Proxy and ProxyServer.
  Fixed error reporting in install_driver.
  Major enhancement to DBI::W32ODBC from Patrick Hollins.
  Added $h->{Taint} to taint fetched data if tainting (perl -T).
  Added code for MULTIPLICITY/PERL_OBJECT contributed by ActiveState.
  Added $sth->more_results (undocumented for now).

=head2 Changes in DBI 1.06,	6th January 1999

  Fixed Win32 Makefile.PL problem in 1.04 and 1.05.
  Significant DBD::Proxy enhancements and fixes
    including support for bind_param_inout (Jochen and I)
  Added experimental DBI->connect_cached method.
  Added $sth->{NAME_uc} and $sth->{NAME_lc} attributes.
  Enhanced fetchrow_hashref to take an attribute name arg.

=head2 Changes in DBI 1.05,	4th January 1999

  Improved DBD::ADO connect (thanks to Phlip Plumlee).
  Improved thread safety (thanks to Jochen Wiedmann).
  [Quick release prompted by truncation of copies on CPAN]

=head2 Changes in DBI 1.04,	3rd January 1999

  Fixed error in Driver.xst. DBI build now tests Driver.xst.
  Removed unused variable compiler warnings in Driver.xst.
  DBI::DBD module now tested during DBI build.
  Further clarification in the DBI::DBD driver writers manual.
  Added optional name parameter to $sth->fetchrow_hashref.

=head2 Changes in DBI 1.03,	1st January 1999

  Now builds with Perl>=5.005_54 (PERL_POLLUTE in DBIXS.h)
  DBI trace trims path from "at yourfile.pl line nnn".
  Trace level 1 now shows statement passed to prepare.
  Assorted improvements to the DBI manual.
  Assorted improvements to the DBI::DBD driver writers manual.
  Fixed $dbh->quote prototype to include optional $data_type.
  Fixed $dbh->prepare_cached problems.
  $dbh->selectrow_array behaves better in scalar context.
  Added a (very) experimental DBD::ADO driver for Win32 ADO.
  Added experimental thread support (perl Makefile.PL -thread).
  Updated the DBI::FAQ - thanks to Alligator Descartes.
  The following changes were implemented and/or packaged
    by Jochen Wiedmann - thanks Jochen:
  Added a Bundle for CPAN installation of DBI, the DBI proxy
    server and prerequisites (lib/Bundle/DBI.pm).
  DBI->available_drivers uses File::Spec, if available.
    This makes it work on MacOS. (DBI.pm)
  Modified type_info to work with read-only values returned
    by type_info_all. (DBI.pm)
  Added handling of magic values in $sth->execute,
    $sth->bind_param and other methods (Driver.xst)
  Added Perl's CORE directory to the linkers path on Win32,
    required by recent versions of ActiveState Perl.
  Fixed DBD::Sponge to work with empty result sets.
  Complete rewrite of DBI::ProxyServer and DBD::Proxy.

=head2 Changes in DBI 1.02,	2nd September 1998

  Fixed DBI::Shell including @ARGV and /current.
  Added basic DBI::Shell test.
  Renamed DBI::Shell /display to /format.

=head2 Changes in DBI 1.01,	2nd September 1998

  Many enhancements to Shell (with many contributions from
  Jochen Wiedmann, Tom Lowery and Adam Marks).
  Assorted fixes to DBD::Proxy and DBI::ProxyServer.
  Tidied up trace messages - trace(2) much cleaner now.
  Added $dbh->{RowCacheSize} and $sth->{RowsInCache}.
  Added experimental DBI::Format (mainly for DBI::Shell).
  Fixed fetchall_arrayref($slice_hash).
  DBI->connect now honours PrintError=1 if connect fails.
  Assorted clarifications to the docs.

=head2 Changes in DBI 1.00,	14th August 1998

  The DBI is no longer 'alpha' software!
  Added $dbh->tables and $dbh->table_info.
  Documented \%attr arg to data_sources method.
  Added $sth->{TYPE}, $sth->{PRECISION} and $sth->{SCALE}.
  Added $sth->{Statement}.
  DBI::Shell now uses neat_list to print results
  It also escapes "'" chars and converts newlines to spaces.

=head2 Changes in DBI 0.95,	10th August 1998

  WARNING: THIS IS AN EXPERIMENTAL RELEASE!

  Fixed 0.94 slip so it will build on pre-5.005 again.
  Added DBI_AUTOPROXY environment variable.
  Array ref returned from fetch/fetchrow_arrayref now readonly.
  Improved connect error reporting by DBD::Proxy.
  All trace/debug messages from DBI now go to trace file.

=head2 Changes in DBI 0.94,	9th August 1998

  WARNING: THIS IS AN EXPERIMENTAL RELEASE!

  Added DBD::Shell and dbish interactive DBI shell. Try it!
  Any database attribs can be set via DBI->connect(,,, \%attr).
  Added _get_fbav and _set_fbav methods for Perl driver developers
    (see ExampleP driver for perl usage). Drivers which don't use
    one of these methods (either via XS or Perl) are not compliant.
  DBI trace now shows adds " at yourfile.pl line nnn"!
  PrintError and RaiseError now prepend driver and method name.
  The available_drivers method no longer returns NullP or Sponge.
  Added $dbh->{Name}.
  Added $dbh->quote($value, $data_type).
  Added more hints to install_driver failure message.
  Added DBD::Proxy and DBI::ProxyServer (from Jochen Wiedmann).
  Added $DBI::neat_maxlen to control truncation of trace output.
  Added $dbh->selectall_arrayref and $dbh->selectrow_array methods.
  Added $dbh->tables.
  Added $dbh->type_info and $dbh->type_info_all.
  Added $h->trace_msg($msg) to write to trace log.
  Added @bool = DBI::looks_like_number(@ary).
  Many assorted improvements to the DBI docs.

=head2 Changes in DBI 0.93,	13th February 1998

  Fixed DBI::DBD::dbd_postamble bug causing 'Driver.xsi not found' errors.
  Changes to handling of 'magic' values in neatsvpv (used by trace).
  execute (in Driver.xst) stops binding after first bind error.
  This release requires drivers to be rebuilt.

=head2 Changes in DBI 0.92,	3rd February 1998

  Fixed per-handle memory leak (with many thanks to Irving Reid).
  Added $dbh->prepare_cached() caching variant of $dbh->prepare.
  Added some attributes:
    $h->{Active}       is the handle 'Active' (vague concept) (boolean)
    $h->{Kids}         e.g. number of sth's associated with a dbh
    $h->{ActiveKids}   number of the above which are 'Active'
    $dbh->{CachedKids} ref to prepare_cached sth cache
  Added support for general-purpose 'private_' attributes.
  Added experimental support for subclassing the DBI: see t/subclass.t
  Added SQL_ALL_TYPES to exported :sql_types.
  Added dbd_dbi_dir() and dbd_dbi_arch_dir() to DBI::DBD module so that
  DBD Makefile.PLs can work with the DBI installed in non-standard locations.
  Fixed 'Undefined value' warning and &sv_no output from neatsvpv/trace.
  Fixed small 'once per interpreter' leak.
  Assorted minor documentation fixes.

=head2 Changes in DBI 0.91,	10th December 1997

  NOTE: This fix may break some existing scripts:
  DBI->connect("dbi:...",$user,$pass) was not setting AutoCommit and PrintError!
  DBI->connect(..., { ... }) no longer sets AutoCommit or PrintError twice.
  DBI->connect(..., { RaiseError=>1 }) now croaks if connect fails.
  Fixed $fh parameter of $sth->dump_results;
  Added default statement DESTROY method which carps.
  Added default driver DESTROY method to silence AUTOLOAD/__DIE__/CGI::Carp
  Added more SQL_* types to %EXPORT_TAGS and @EXPORT_OK.
  Assorted documentation updates (mainly clarifications).
  Added workaround for perl's 'sticky lvalue' bug.
  Added better warning for bind_col(umns) where fields==0.
  Fixed to build okay with 5.004_54 with or without USE_THREADS.
  Note that the DBI has not been tested for thread safety yet.

=head2 Changes in DBI 0.90,	6th September 1997

  Can once again be built with Perl 5.003.
  The DBI class can be subclassed more easily now.
  InactiveDestroy fixed for drivers using the *.xst template.
  Slightly faster handle creation.
  Changed prototype for dbd_*_*_attrib() to add extra param.
  Note: 0.90, 0.89 and possibly some other recent versions have
  a small memory leak. This will be fixed in the next release.

=head2 Changes in DBI 0.89,	25th July 1997

  Minor fix to neatsvpv (mainly used for debug trace) to workaround
  bug in perl where SvPV removes IOK flag from an SV.
  Minor updates to the docs.

=head2 Changes in DBI 0.88,	22nd July 1997

  Fixed build for perl5.003 and Win32 with Borland.
  Fixed documentation formatting.
  Fixed DBI_DSN ignored for old-style connect (with explicit driver).
  Fixed AutoCommit in DBD::ExampleP
  Fixed $h->trace.
  The DBI can now export SQL type values: use DBI ':sql_types';
  Modified Driver.xst and renamed DBDI.h to dbd_xsh.h

=head2 Changes in DBI 0.87,	18th July 1997

  Fixed minor type clashes.
  Added more docs about placeholders and bind values.

=head2 Changes in DBI 0.86,	16th July 1997

  Fixed failed connect causing 'unblessed ref' and other errors.
  Drivers must handle AutoCommit FETCH and STORE else DBI croaks.
  Added $h->{LongReadLen} and $h->{LongTruncOk} attributes for BLOBS.
  Added DBI_USER and DBI_PASS env vars. See connect docs for usage.
  Added DBI->trace() to set global trace level (like per-handle $h->trace).
  PERL_DBI_DEBUG env var renamed DBI_DEBUG (old name still works for now).
  Updated docs, including commit, rollback, AutoCommit and Transactions sections.
  Added bind_param method and execute(@bind_values) to docs.
  Fixed fetchall_arrayref.

  Since the DBIS structure has change the internal version numbers have also
  changed (DBIXS_VERSION == 9 and DBISTATE_VERSION == 9) so drivers will have
  to be recompiled. The test is also now more sensitive and the version
  mismatch error message now more clear about what to do. Old drivers are
  likely to core dump (this time) until recompiled for this DBI. In future
  DBI/DBD version mismatch will always produce a clear error message.

  Note that this DBI release contains and documents many new features
  that won't appear in drivers for some time. Driver writers might like
  to read perldoc DBI::DBD and comment on or apply the information given.

=head2 Changes in DBI 0.85,	25th June 1997

  NOTE: New-style connect now defaults to AutoCommit mode unless
  { AutoCommit => 0 } specified in connect attributes. See the docs.
  AutoCommit attribute now defined and tracked by DBI core.
  Drivers should use/honour this and not implement their own.
  Added pod doc changes from Andreas and Jonathan.
  New DBI_DSN env var default for connect method. See docs.
  Documented the func method.
  Fixed "Usage: DBD::_::common::DESTROY" error.
  Fixed bug which set some attributes true when there value was fetched.
  Added new internal DBIc_set() macro for drivers to use.

=head2 Changes in DBI 0.84,	20th June 1997

  Added $h->{PrintError} attribute which, if set true, causes all errors to
  trigger a warn().
  New-style DBI->connect call now automatically sets PrintError=1 unless
  { PrintError => 0 } specified in the connect attributes. See the docs.
  The old-style connect with a separate driver parameter is deprecated.
  Fixed fetchrow_hashref.
  Renamed $h->debug to $h->trace() and added a trace filename arg.
  Assorted other minor tidy-ups.

=head2 Changes in DBI 0.83,	11th June 1997

  Added driver specification syntax to DBI->connect data_source
  parameter: DBI->connect('dbi:driver:...', $user, $passwd);
  The DBI->data_sources method should return data_source
  names with the appropriate 'dbi:driver:' prefix.
  DBI->connect will warn if \%attr is true but not a hash ref.
  Added the new fetchrow methods:
    @row_ary  = $sth->fetchrow_array;
    $ary_ref  = $sth->fetchrow_arrayref;
    $hash_ref = $sth->fetchrow_hashref;
  The old fetch and fetchrow methods still work.
  Driver implementors should implement the new names for
  fetchrow_array and fetchrow_arrayref ASAP (use the xs ALIAS:
  directive to define aliases for fetch and fetchrow).
  Fixed occasional problems with t/examp.t test.
  Added automatic errstr reporting to the debug trace output.
  Added the DBI FAQ from Alligator Descartes in module form for
  easy reading via "perldoc DBI::FAQ". Needs reformatting.
  Unknown driver specific attribute names no longer croak.
  Fixed problem with internal neatsvpv macro.

=head2 Changes in DBI 0.82,	23rd May 1997

  Added $h->{RaiseError} attribute which, if set true, causes all errors to
  trigger a die(). This makes it much easier to implement robust applications
  in terms of higher level eval { ... } blocks and rollbacks.
  Added DBI->data_sources($driver) method for implementation by drivers.
  The quote method now returns the string NULL (without quotes) for undef.
  Added VMS support thanks to Dan Sugalski.
  Added a 'quick start guide' to the README.
  Added neatsvpv function pointer to DBIS structure to make it available for
  use by drivers. A macro defines neatsvpv(sv,len) as (DBIS->neatsvpv(sv,len)).
  Old XS macro SV_YES_NO changes to standard boolSV.
  Since the DBIS structure has change the internal version numbers have also
  changed (DBIXS_VERSION == 8 and DBISTATE_VERSION == 8) so drivers will have
  to be recompiled.

=head2 Changes in DBI 0.81,	7th May 1997

  Minor fix to let DBI build using less modern perls.
  Fixed a suprious typo warning.

=head2 Changes in DBI 0.80,	6th May 1997

  Builds with no changes on NT using perl5.003_99 (with thanks to Jeffrey Urlwin).
  Automatically supports Apache::DBI (with thanks to Edmund Mergl).
    DBI scripts no longer need to be modified to make use of Apache::DBI.
  Added a ping method and an experimental connect_test_perf method.
  Added a fetchhash and fetch_all methods.
  The func method no longer pre-clears err and errstr. 
  Added ChopBlanks attribute (currently defaults to off, that may change).
    Support for the attribute needs to be implemented by individual drivers.
  Reworked tests into standard t/*.t form.
  Added more pod text.  Fixed assorted bugs.
  

=head2 Changes in DBI 0.79,	7th Apr 1997

  Minor release. Tidied up pod text and added some more descriptions
  (especially disconnect). Minor changes to DBI.xs to remove compiler
  warnings.

=head2 Changes in DBI 0.78,	28th Mar 1997

  Greatly extended the pod documentation in DBI.pm, including the under
  used bind_columns method. Use 'perldoc DBI' to read after installing.
  Fixed $h->err. Fetching an attribute value no longer resets err.
  Added $h->{InactiveDestroy}, see documentation for details.
  Improved debugging of cached ('quick') attribute fetches.
  errstr will return err code value if there is no string value.
  Added DBI/W32ODBC to the distribution. This is a pure-perl experimental
  DBI emulation layer for Win32::ODBC. Note that it's unsupported, your
  mileage will vary, and bug reports without fixes will probably be ignored.

=head2 Changes in DBI 0.77,	21st Feb 1997

  Removed erroneous $h->errstate and $h->errmsg methods from DBI.pm.
  Added $h->err, $h->errstr and $h->state default methods in DBI.xs.
  Updated informal DBI API notes in DBI.pm. Updated README slightly.
  DBIXS.h now correctly installed into INST_ARCHAUTODIR.
  (DBD authors will need to edit their Makefile.PL's to use
  -I$(INSTALLSITEARCH)/auto/DBI -I$(INSTALLSITEARCH)/DBI)


=head2 Changes in DBI 0.76,	3rd Feb 1997

  Fixed a compiler type warnings (pedantic IRIX again).

=head2 Changes in DBI 0.75,	27th Jan 1997

  Fix problem introduced by a change in Perl5.003_XX.
  Updated README and DBI.pm docs.

=head2 Changes in DBI 0.74,	14th Jan 1997

  Dispatch now sets dbi_debug to the level of the current handle
  (this makes tracing/debugging individual handles much easier).
  The '>> DISPATCH' log line now only logged at debug >= 3 (was 2).
  The $csr->NUM_OF_FIELDS attribute can be set if not >0 already.
  You can log to a file using the env var PERL_DBI_DEBUG=/tmp/dbi.log.
  Added a type cast needed by IRIX.
  No longer sets perl_destruct_level unless debug set >= 4.
  Make compatible with PerlIO and sfio.

=head2 Changes in DBI 0.73,	10th Oct 1996

  Fixed some compiler type warnings (IRIX).
  Fixed DBI->internal->{DebugLog} = $filename.
  Made debug log file unbuffered.
  Added experimental bind_param_inout method to interface.
  Usage: $dbh->bind_param_inout($param, \$value, $maxlen [, \%attribs ])
  (only currently used by DBD::Oracle at this time.)

=head2 Changes in DBI 0.72,	23 Sep 1996

  Using an undefined value as a handle now gives a better
  error message (mainly useful for emulators like Oraperl).
  $dbh->do($sql, @params) now works for binding placeholders.

=head2 Changes in DBI 0.71,	10 July 1996

  Removed spurious abort() from invalid handle check.
  Added quote method to DBI interface and added test.

=head2 Changes in DBI 0.70,	16 June 1996

  Added extra invalid handle check (dbih_getcom)
  Fixed broken $dbh->quote method.
  Added check for old GCC in Makefile.PL

=head2 Changes in DBI 0.69

  Fixed small memory leak.
  Clarified the behaviour of DBI->connect.
  $dbh->do now returns '0E0' instead of 'OK'.
  Fixed "Can't read $DBI::errstr, lost last handle" problem.


=head2 Changes in DBI 0.68,	2 Mar 1996

  Changes to suit perl5.002 and site_lib directories.
  Detects old versions ahead of new in @INC.


=head2 Changes in DBI 0.67,	15 Feb 1996

  Trivial change to test suite to fix a problem shown up by the
  Perl5.002gamma release Test::Harness.


=head2 Changes in DBI 0.66,	29 Jan 1996

  Minor changes to bring the DBI into line with 5.002 mechanisms,
  specifically the xs/pm VERSION checking mechanism.
  No functionality changes. One no-last-handle bug fix (rare problem).
  Requires 5.002 (beta2 or later).


=head2 Changes in DBI 0.65,	23 Oct 1995

  Added $DBI::state to hold SQL CLI / ODBC SQLSTATE value.
  SQLSTATE "00000" (success) is returned as "" (false), all else is true.
  If a driver does not explicitly initialise it (via $h->{State} or
  DBIc_STATE(imp_xxh) then $DBI::state will automatically return "" if
  $DBI::err is false otherwise "S1000" (general error).
  As always, this is a new feature and liable to change.

  The is *no longer* a default error handler!
  You can add your own using push(@{$h->{Handlers}}, sub { ... })
  but be aware that this interface may change (or go away).

  The DBI now automatically clears $DBI::err, errstr and state before
  calling most DBI methods. Previously error conditions would persist.
  Added DBIh_CLEAR_ERROR(imp_xxh) macro.

  DBI now EXPORT_OK's some utility functions, neat($value),
  neat_list(@values) and dump_results($sth).

  Slightly enhanced t/min.t minimal test script in an effort to help
  narrow down the few stray core dumps that some porters still report.

  Renamed readblob to blob_read (old name still works but warns).
  Added default blob_copy_to_file method.

  Added $sth = $dbh->tables method. This returns an $sth for a query
  which has these columns: TABLE_CATALOGUE, TABLE_OWNER, TABLE_NAME,
  TABLE_TYPE, REMARKS in that order. The TABLE_CATALOGUE column
  should be ignored for now.


=head2 Changes in DBI 0.64,	23 Oct 1995

  Fixed 'disconnect invalidates 1 associated cursor(s)' problem.
  Drivers using DBIc_ACTIVE_on/off() macros should not need any changes
  other than to test for DBIc_ACTIVE_KIDS() instead of DBIc_KIDS().
  Fixed possible core dump in dbih_clearcom during global destruction.


=head2 Changes in DBI 0.63,	1 Sep 1995

  Minor update. Fixed uninitialised memory bug in method
  attribute handling and streamlined processing and debugging.
  Revised usage definitions for bind_* methods and readblob.


=head2 Changes in DBI 0.62,	26 Aug 1995

  Added method redirection method $h->func(..., $method_name).
  This is now the official way to call private driver methods
  that are not part of the DBI standard.  E.g.:
      @ary = $sth->func('ora_types');
  It can also be used to call existing methods. Has very low cost.

  $sth->bind_col columns now start from 1 (not 0) to match SQL.
  $sth->bind_columns now takes a leading attribute parameter (or undef),
  e.g., $sth->bind_columns($attribs, \$col1 [, \$col2 , ...]);

  Added handy DBD_ATTRIBS_CHECK macro to vet attribs in XS.
  Added handy DBD_ATTRIB_GET_SVP, DBD_ATTRIB_GET_BOOL and
  DBD_ATTRIB_GET_IV macros for handling attributes.

  Fixed STORE for NUM_OF_FIELDS and NUM_OF_PARAMS.
  Added FETCH for NUM_OF_FIELDS and NUM_OF_PARAMS.

  Dispatch no longer bothers to call _untie().
  Faster startup via install_method/_add_dispatch changes.


=head2 Changes in DBI 0.61,	22 Aug 1995

  Added $sth->bind_col($column, \$var [, \%attribs ]);

  This method enables perl variable to be directly and automatically
  updated when a row is fetched. It requires no driver support
  (if the driver has been written to use DBIS->get_fbav).
  Currently \%attribs is unused.

  Added $sth->bind_columns(\$var [, \$var , ...]);

  This method is a short-cut for bind_col which binds all the
  columns of a query in one go (with no attributes). It also
  requires no driver support.

  Added $sth->bind_param($parameter, $var [, \%attribs ]);

  This method enables attributes to be specified when values are
  bound to placeholders. It also enables binding to occur away
  from the execute method to improve execute efficiency.
  The DBI does not provide a default implementation of this.
  See the DBD::Oracle module for a detailed example.

  The DBI now provides default implementations of both fetch and
  fetchrow.  Each is written in terms of the other. A driver is
  expected to implement at least one of them.

  More macro and assorted structure changes in DBDXS.h. Sorry!
  The old dbihcom definitions have gone. All fields have macros.
  The imp_xxh_t type is now used within the DBI as well as drivers.
  Drivers must set DBIc_NUM_FIELDS(imp_sth) and DBIc_NUM_PARAMS(imp_sth).

  test.pl includes a trivial test of bind_param and bind_columns.


=head2 Changes in DBI 0.60,	17 Aug 1995

  This release has significant code changes but much less
  dramatic than the previous release. The new implementors data
  handling mechanism has matured significantly (don't be put off
  by all the struct typedefs in DBIXS.h, there's just to make it
  easier for drivers while keeping things type-safe).

  The DBI now includes two new methods:

  do		$dbh->do($statement)

  This method prepares, executes and finishes a statement. It is
  designed to be used for executing one-off non-select statements
  where there is no benefit in reusing a prepared statement handle.

  fetch		$array_ref = $sth->fetch;

  This method is the new 'lowest-level' row fetching method. The
  previous @row = $sth->fetchrow method now defaults to calling
  the fetch method and expanding the returned array reference.

  The DBI now provides fallback attribute FETCH and STORE functions
  which drivers should call if they don't recognise an attribute.

  THIS RELEASE IS A GOOD STARTING POINT FOR DRIVER DEVELOPERS!
  Study DBIXS.h from the DBI and Oracle.xs etc from DBD::Oracle.
  There will be further changes in the interface but nothing
  as dramatic as these last two releases! (I hope :-)


=head2 Changes in DBI 0.59	15 Aug 1995

  NOTE: THIS IS AN UNSTABLE RELEASE!

  Major reworking of internal data management!
  Performance improvements and memory leaks fixed.
  Added a new NullP (empty) driver and a -m flag
  to test.pl to help check for memory leaks.
  Study DBD::Oracle version 0.21 for more details.
  (Comparing parts of v0.21 with v0.20 may be useful.)


=head2 Changes in DBI 0.58	21 June 1995

  Added DBI->internal->{DebugLog} = $filename;
  Reworked internal logging.
  Added $VERSION.
  Made disconnect_all a compulsary method for drivers.


=head1 ANCIENT HISTORY

12th Oct 1994: First public release of the DBI module.
               (for Perl 5.000-beta-3h)

19th Sep 1994: DBperl project renamed to DBI.

29th Sep 1992: DBperl project started.

=cut
