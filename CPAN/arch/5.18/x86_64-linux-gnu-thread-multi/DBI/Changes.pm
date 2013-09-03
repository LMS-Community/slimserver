=head1 NAME

DBI::Changes - List of significant changes to the DBI

=encoding ISO8859-1

=cut

=head2 Changes in DBI 1.628 - 22nd July 2013

    Fixed missing fields on partial insert via DBI::DBD::SqlEngine
        engines (DBD::CSV, DBD::DBM etc.) [H.Merijn Brand, Jens Rehsack]
    Fixed stack corruption on callbacks RT#85562 RT#84974 [Aaron Schweiger]
    Fixed DBI::SQL::Nano_::Statement handling of "0" [Jens Rehsack]
    Fixed exit op precedence in test RT#87029 [Reni Urban]

    Added support for finding tables in multiple directories
        via new DBD::File f_dir_search attribute [H.Merijn Brand]
    Enable compiling by C++ RT#84285 [Kurt Jaeger]

    Typo fixes in pod and comment [David Steinbrunner]
    Change DBI's docs to refer to git not svn [H.Merijn Brand]
    Clarify bind_col TYPE attribute is sticky [Martin J. Evans]
    Fixed reference to $sth in selectall_arrayref docs RT#84873
    Spelling fixes [Ville Skyttä]
    Changed $VERSIONs to hardcoded strings [H.Merijn Brand]

=head2 Changes in DBI 1.627 - 16th May 2013

    Fixed VERSION regression in DBI::SQL::Nano [Tim Bunce]

=head2 Changes in DBI 1.626 - 15th May 2013

    Fixed pod text/link was reversed in a few cases RT#85168
        [H.Merijn Brand]

    Handle aliasing of STORE'd attributes in DBI::DBD::SqlEngine
        [Jens Rehsack]

    Updated repository URI to git [Jens Rehsack]

    Fixed skip() count arg in t/48dbi_dbd_sqlengine.t [Tim Bunce]

=head2 Changes in DBI 1.625 (svn r15595) 28th March 2013

  Fixed heap-use-after-free during global destruction RT#75614
    thanks to Reini Urban.
  Fixed ignoring RootClass attribute during connect() by
    DBI::DBD::SqlEngine reported in RT#84260 by Michael Schout

=head2 Changes in DBI 1.624 (svn r15576) 22nd March 2013

  Fixed Gofer for hash randomization in perl 5.17.10+ RT#84146

  Clarify docs for can() re RT#83207

=head2 Changes in DBI 1.623 (svn r15547) 2nd Jan 2013

  Fixed RT#64330 - ping wipes out errstr (Martin J. Evans).
  Fixed RT#75868 - DBD::Proxy shouldn't call connected() on the server.
  Fixed RT#80474 - segfault in DESTROY with threads.
  Fixed RT#81516 - Test failures due to hash randomisation in perl 5.17.6
    thanks to Jens Rehsack and H.Merijn Brand and feedback on IRC
  Fixed RT#81724 - Handle copy-on-write scalars (sprout)
  Fixed unused variable / self-assignment compiler warnings.
  Fixed default table_info in DBI::DBD::SqlEngine which passed NAMES
    attribute instead of NAME to DBD::Sponge RT72343 (Martin J. Evans)

  Corrected a spelling error thanks to Chris Sanders.
  Corrected typo in DBI->installed_versions docs RT#78825
    thanks to Jan Dubois.

  Refactored table meta information management from DBD::File into
    DBI::DBD::SqlEngine (H.Merijn Brand, Jens Rehsack)
  Prevent undefined f_dir being used in opendir (H.Merijn Brand)

  Added logic to force destruction of children before parents
    during global destruction. See RT#75614.
  Added DBD::File Plugin-Support for table names and data sources
    (Jens Rehsack, #dbi Team)
  Added new tests to 08keeperr for RT#64330
    thanks to Kenichi Ishigaki.
  Added extra internal handle type check, RT#79952
    thanks to Reini Urban.
  Added cubrid_ registered prefix for DBD::cubrid, RT#78453

  Removed internal _not_impl method (Martin J. Evans).

  NOTE: The "old-style" DBD::DBM attributes 'dbm_ext' and 'dbm_lockfile'
    have been deprecated for several years and their use will now generate
    a warning.

=head2 Changes in DBI 1.622 (svn r15327) 6th June 2012

  Fixed lack of =encoding in non-ASCII pod docs. RT#77588

  Corrected typo in DBI::ProfileDumper thanks to Finn Hakansson.

=head2 Changes in DBI 1.621 (svn r15315) 21st May 2012

  Fixed segmentation fault when a thread is created from
    within another thread RT#77137, thanks to Dave Mitchell.
  Updated previous Changes to credit Booking.com for sponsoring
    Dave Mitchell's recent DBI optimization work.

=head2 Changes in DBI 1.620 (svn r15300) 25th April 2012

  Modified column renaming in fetchall_arrayref, added in 1.619,
    to work on column index numbers not names (an incompatible change).
  Reworked the fetchall_arrayref documentation.
  Hash slices in fetchall_arrayref now detect invalid column names.

=head2 Changes in DBI 1.619 (svn r15294) 23rd April 2012

  Fixed the connected method to stop showing the password in
    trace file (Martin J. Evans).
  Fixed _install_method to set CvFILE correctly
    thanks to sprout RT#76296
  Fixed SqlEngine "list_tables" thanks to David McMath
    and Norbert Gruener. RT#67223 RT#69260

  Optimized DBI method dispatch thanks to Dave Mitchell.
  Optimized driver access to DBI internal state thanks to Dave Mitchell.
  Optimized driver access to handle data thanks to Dave Mitchell.
    Dave's work on these optimizations was sponsored by Booking.com.
  Optimized fetchall_arrayref with hash slice thanks
    to Dagfinn Ilmari Mannsåker. RT#76520
  Allow renaming columns in fetchall_arrayref hash slices
    thanks to Dagfinn Ilmari Mannsåker. RT#76572
  Reserved snmp_ and tree_ for DBD::SNMP and DBD::TreeData

=head2 Changes in DBI 1.618 (svn r15170) 25rd February 2012

  Fixed compiler warnings in Driver_xst.h (Martin J. Evans)
  Fixed compiler warning in DBI.xs (H.Merijn Brand)
  Fixed Gofer tests failing on Windows RT74975 (Manoj Kumar)
  Fixed my_ctx compile errors on Windows (Dave Mitchell)

  Significantly optimized method dispatch via cache (Dave Mitchell)
  Significantly optimized DBI internals for threads (Dave Mitchell)
    Dave's work on these optimizations was sponsored by Booking.com.
  Xsub to xsub calling optimization now enabled for threaded perls.
  Corrected typo in example in docs (David Precious)
  Added note that calling clone() without an arg may warn in future.
  Minor changes to the install_method() docs in DBI::DBD.
  Updated dbipport.h from Devel::PPPort 3.20

=head2 Changes in DBI 1.617 (svn r15107) 30th January 2012

  NOTE: The officially supported minimum perl version will change
  from perl 5.8.1 (2003) to perl 5.8.3 (2004) in a future release.
  (The last change, from perl 5.6 to 5.8.1, was announced
  in July 2008 and implemented in DBI 1.611 in April 2010.)

  Fixed ParamTypes example in the pod (Martin J. Evans)
  Fixed the definition of ArrayTupleStatus and remove confusion over
    rows affected in list context of execute_array (Martin J. Evans)
  Fixed sql_type_cast example and typo in errors (Martin J. Evans)
  Fixed Gofer error handling for keeperr methods like ping (Tim Bunce)
  Fixed $dbh->clone({}) RT73250 (Tim Bunce)
  Fixed is_nested_call logic error RT73118 (Reini Urban)

  Enhanced performance for threaded perls (Dave Mitchell, Tim Bunce)
    Dave's work on this optimization was sponsored by Booking.com.
  Enhanced and standardized driver trace level mechanism (Tim Bunce)
  Removed old code that was an inneffective attempt to detect
    people doing DBI->{Attrib}.
  Clear ParamValues on bind_param param count error RT66127 (Tim Bunce)
  Changed DBI::ProxyServer to require DBI at compile-time RT62672 (Tim Bunce)

  Added pod for default_user to DBI::DBD (Martin J. Evans)
  Added CON, ENC and DBD trace flags and extended 09trace.t (Martin J. Evans)
  Added TXN trace flags and applied CON and TXN to relevant methods (Tim Bunce)
  Added some more fetchall_arrayref(..., $maxrows) tests (Tim Bunce)
  Clarified docs for fetchall_arrayref called on an inactive handle.
  Clarified docs for clone method (Tim Bunce)
  Added note to DBI::Profile about async queries (Marcel Grünauer).
  Reserved spatialite_ as a driver prefix for DBD::Spatialite
  Reserved mo_ as a driver prefix for DBD::MO
  Updated link to the SQL Reunion 95 docs, RT69577 (Ash Daminato)
  Changed links for DBI recipes. RT73286 (Martin J. Evans)

=head2 Changes in DBI 1.616 (svn r14616) 30th December 2010

  Fixed spurious dbi_profile lines written to the log when
    profiling is enabled and a trace flag, like SQL, is used.
  Fixed to recognize SQL::Statement errors even if instantiated
    with RaiseError=0 (Jens Rehsack)
  Fixed RT#61513 by catching attribute assignment to tied table access
    interface (Jens Rehsack)
  Fixing some misbehavior of DBD::File when running within the Gofer
    server.
  Fixed compiler warnings RT#62640

  Optimized connect() to remove redundant FETCH of \%attrib values.
  Improved initialization phases in DBI::DBD::SqlEngine (Jens Rehsack)

  Added DBD::Gofer::Transport::corostream. An experimental proof-of-concept
    transport that enables asynchronous database calls with few code changes.
    It enables asynchronous use of DBI frameworks like DBIx::Class.

  Added additional notes on DBDs which avoid creating a statement in
    the do() method and the effects on error handlers (Martin J. Evans)
  Adding new attribute "sql_dialect" to DBI::DBD::SqlEngine to allow
    users control used SQL dialect (ANSI, CSV or AnyData), defaults to
    CSV (Jens Rehsack)
  Add documentation for DBI::DBD::SqlEngine attributes (Jens Rehsack)
  Documented dbd_st_execute return (Martin J. Evans)
  Fixed typo in InactiveDestroy thanks to Emmanuel Rodriguez.

=head2 Changes in DBI 1.615 (svn r14438) 21st September 2010

  Fixed t/51dbm_file for file/directory names with whitespaces in them
    RT#61445 (Jens Rehsack)
  Fixed compiler warnings from ignored hv_store result (Martin J. Evans)
  Fixed portability to VMS (Craig A. Berry)

=head2 Changes in DBI 1.614 (svn r14408) 17th September 2010

  Fixed bind_param () in DBI::DBD::SqlEngine (rt#61281)
  Fixed internals to not refer to old perl symbols that
    will no longer be visible in perl >5.13.3 (Andreas Koenig)
    Many compiled drivers are likely to need updating.
  Fixed issue in DBD::File when absolute filename is used as table name
    (Jens Rehsack)
  Croak manually when file after tie doesn't exists in DBD::DBM
    when it have to exists (Jens Rehsack)
  Fixed issue in DBD::File when users set individual file name for tables
    via f_meta compatibility interface - reported by H.Merijn Brand while
    working on RT#61168 (Jens Rehsack)

  Changed 50dbm_simple to simplify and fix problems (Martin J. Evans)
  Changed 50dbm_simple to skip aggregation tests when not using
    SQL::Statement (Jens Rehsack)
  Minor speed improvements in DBD::File (Jens Rehsack)

  Added $h->{AutoInactiveDestroy} as simpler safer form of
    $h->{InactiveDestroy} (David E. Wheeler)
  Added ability for parallel testing "prove -j4 ..." (Jens Rehsack)
  Added tests for delete in DBM (H.Merijn Brand)
  Added test for absolute filename as table to 51dbm_file (Jens Rehsack)
  Added two initialization phases to DBI::DBD::SqlEngine (Jens Rehsack)
  Added improved developers documentation for DBI::DBD::SqlEngine
    (Jens Rehsack)
  Added guides how to write DBI drivers using DBI::DBD::SqlEngine
    or DBD::File (Jens Rehsack)
  Added register_compat_map() and table_meta_attr_changed() to
    DBD::File::Table to support clean fix of RT#61168 (Jens Rehsack)

=head2 Changes in DBI 1.613 (svn r14271) 22nd July 2010

  Fixed Win32 prerequisite module from PathTools to File::Spec.

  Changed attribute headings and fixed references in DBI pod (Martin J. Evans)
  Corrected typos in DBI::FAQ and DBI::ProxyServer (Ansgar Burchardt)

=head2 Changes in DBI 1.612 (svn r14254) 16th July 2010

NOTE: This is a minor release for the DBI core but a major release for
DBD::File and drivers that depend on it, like DBD::DBM and DBD::CSV.

This is also the first release where the bulk of the development work
has been done by other people. I'd like to thank (in no particular order)
Jens Rehsack, Martin J. Evans, and H.Merijn Brand for all their contributions.

  Fixed DBD::File's {ChopBlank} handling (it stripped \s instead of space
    only as documented in DBI) (H.Merijn Brand)
  Fixed DBD::DBM breakage with SQL::Statement (Jens Rehsack, fixes RT#56561)
  Fixed DBD::File file handle leak (Jens Rehsack)
  Fixed problems in 50dbm.t when running tests with multiple
    dbms (Martin J. Evans)
  Fixed DBD::DBM bugs found during tests (Jens Rehsack)
  Fixed DBD::File doesn't find files without extensions under some
    circumstances (Jens Rehsack, H.Merijn Brand, fixes RT#59038)

  Changed Makefile.PL to modernize with CONFLICTS, recommended dependencies
    and resources (Jens Rehsack)
  Changed DBI::ProfileDumper to rename any existing profile file by
    appending .prev, instead of overwriting it.
  Changed DBI::ProfileDumper::Apache to work in more configurations
    including vhosts using PerlOptions +Parent.
  Add driver_prefix method to DBI (Jens Rehsack)

  Added more tests to 50dbm_simple.t to prove optimizations in
    DBI::SQL::Nano and SQL::Statement (Jens Rehsack)
  Updated tests to cover optional installed SQL::Statement (Jens Rehsack)
  Synchronize API between SQL::Statement and DBI::SQL::Nano (Jens Rehsack)
  Merged some optimizations from SQL::Statement into DBI::SQL::Nano
    (Jens Rehsack)
  Added basic test for DBD::File (H.Merijn Brand, Jens Rehsack)
  Extract dealing with Perl SQL engines from DBD::File into
    DBI::DBD::SqlEngine for better subclassing of 3rd party non-db DBDs
    (Jens Rehsack)

  Updated and clarified documentation for finish method (Tim Bunce).
  Changes to DBD::File for better English and hopefully better
    explanation (Martin J. Evans)
  Update documentation of DBD::DBM to cover current implementation,
    tried to explain some things better and changes most examples to
    preferred style of Merijn and myself (Jens Rehsack)
  Added developer documentation (including a roadmap of future plans)
    for DBD::File

=head2 Changes in DBI 1.611 (svn r13935) 29th April 2010

  NOTE: minimum perl version is now 5.8.1 (as announced in DBI 1.607)

  Fixed selectcol_arrayref MaxRows attribute to count rows not values
    thanks to Vernon Lyon.
  Fixed DBI->trace(0, *STDERR); (H.Merijn Brand)
    which tried to open a file named "*main::STDERR" in perl-5.10.x
  Fixes in DBD::DBM for use under threads (Jens Rehsack)

  Changed "Issuing rollback() due to DESTROY without explicit disconnect"
    warning to not be issued if ReadOnly set for that dbh.

  Added f_lock and f_encoding support to DBD::File (H.Merijn Brand)
  Added ChildCallbacks => { ... } to Callbacks as a way to
    specify Callbacks for child handles.
    With tests added by David E. Wheeler.
  Added DBI::sql_type_cast($value, $type, $flags) to cast a string value
    to an SQL type. e.g. SQL_INTEGER effectively does $value += 0;
    Has other options plus an internal interface for drivers.

  Documentation changes:
  Small fixes in the documentation of DBD::DBM (H.Merijn Brand)
  Documented specification of type casting behaviour for bind_col()
    based on DBI::sql_type_cast() and two new bind_col attributes
    StrictlyTyped and DiscardString. Thanks to Martin Evans.
  Document fetchrow_hashref() behaviour for functions,
    aliases and duplicate names (H.Merijn Brand)
  Updated DBI::Profile and DBD::File docs to fix pod nits
    thanks to Frank Wiegand.
  Corrected typos in Gopher documentation reported by Jan Krynicky.
  Documented the Callbacks attribute thanks to David E. Wheeler.
  Corrected the Timeout examples as per rt 50621 (Martin J. Evans).
  Removed some internal broken links in the pod (Martin J. Evans)
  Added Note to column_info for drivers which do not
    support it (Martin J. Evans)
  Updated dbipport.h to Devel::PPPort 3.19 (H.Merijn Brand)

=head2 Changes in DBI 1.609 (svn r12816) 8th June 2009

  Fixes to DBD::File (H.Merijn Brand)
    added f_schema attribute
    table names case sensitive when quoted, insensitive when unquoted
    workaround a bug in SQL::Statement (temporary fix) related
      to the "You passed x parameters where y required" error

  Added ImplementorClass and Name info to the "Issuing rollback() due to
    DESTROY without explicit disconnect" warning to identify the handle.
    Applies to compiled drivers when they are recompiled.
  Added DBI->visit_handles($coderef) method.
  Added $h->visit_child_handles($coderef) method.
  Added docs for column_info()'s COLUMN_DEF value.
  Clarified docs on stickyness of data type via bind_param().
  Clarified docs on stickyness of data type via bind_col().

=head2 Changes in DBI 1.608 (svn r12742) 5th May 2009

  Fixes to DBD::File (H.Merijn Brand)
    bind_param () now honors the attribute argument
    added f_ext attribute
    File::Spec is always required. (CORE since 5.00405)
    Fail and set errstr on parameter count mismatch in execute ()
  Fixed two small memory leaks when running in mod_perl
    one in DBI->connect and one in DBI::Gofer::Execute.
    Both due to "local $ENV{...};" leaking memory.
  Fixed DBD_ATTRIB_DELETE macro for driver authors
    and updated DBI::DBD docs thanks to Martin J. Evans.
  Fixed 64bit issues in trace messages thanks to Charles Jardine.
  Fixed FETCH_many() method to work with drivers that incorrectly return
    an empty list from $h->FETCH. Affected gofer.

  Added 'sqlite_' as registered prefix for DBD::SQLite.
  Corrected many typos in DBI docs thanks to Martin J. Evans.
  Improved DBI::DBD docs thanks to H.Merijn Brand.

=head2 Changes in DBI 1.607 (svn r11571) 22nd July 2008

  NOTE: Perl 5.8.1 is now the minimum supported version.
  If you need support for earlier versions send me a patch.

  Fixed missing import of carp in DBI::Gofer::Execute.

  Added note to docs about effect of execute(@empty_array).
  Clarified docs for ReadOnly thanks to Martin Evans.

=head2 Changes in DBI 1.605 (svn r11434) 16th June 2008

  Fixed broken DBIS macro with threads on big-endian machines
    with 64bit ints but 32bit pointers. Ticket #32309.
  Fixed the selectall_arrayref, selectrow_arrayref, and selectrow_array
    methods that get embedded into compiled drivers to use the
    inner sth handle when passed a $sth instead of an sql string.
    Drivers will need to be recompiled to pick up this change.
  Fixed leak in neat() for some kinds of values thanks to Rudolf Lippan.
  Fixed DBI::PurePerl neat() to behave more like XS neat().

  Increased default $DBI::neat_maxlen from 400 to 1000.
  Increased timeout on tests to accommodate very slow systems.
  Changed behaviour of trace levels 1..4 to show less information
    at lower levels.
  Changed the format of the key used for $h->{CachedKids}
    (which is undocumented so you shouldn't depend on it anyway)
  Changed gofer error handling to avoid duplicate error text in errstr.
  Clarified docs re ":N" style placeholders.
  Improved gofer retry-on-error logic and refactored to aid subclassing.
  Improved gofer trace output in assorted ways.

  Removed the beeps "\a" from Makefile.PL warnings.
  Removed check for PlRPC-modules from Makefile.PL

  Added sorting of ParamValues reported by ShowErrorStatement
    thanks to to Rudolf Lippan.
  Added cache miss trace message to DBD::Gofer transport class.
  Added $drh->dbixs_revision method.
  Added explicit LICENSE specification (perl) to META.yaml

=head2 Changes in DBI 1.604 (svn rev 10994) 24th March 2008

  Fixed fetchall_arrayref with $max_rows argument broken in 1.603,
    thanks to Greg Sabino Mullane.
  Fixed a few harmless compiler warnings on cygwin.

=head2 Changes in DBI 1.603

  Fixed pure-perl fetchall_arrayref with $max_rows argument
    to not error when fetching after all rows already fetched.
    (Was fixed for compiled drivers back in DBI 1.31.)
    Thanks to Mark Overmeer.
  Fixed C sprintf formats and casts, fixing compiler warnings.

  Changed dbi_profile() to accept a hash of profiles and apply to all.
  Changed gofer stream transport to improve error reporting.
  Changed gofer test timeout to avoid spurious failures on slow systems.

  Added options to t/85gofer.t so it's more useful for manual testing.

=head2 Changes in DBI 1.602 (svn rev 10706)  8th February 2008

  Fixed potential coredump if stack reallocated while calling back
    into perl from XS code. Thanks to John Gardiner Myers.
  Fixed DBI::Util::CacheMemory->new to not clear the cache.
  Fixed avg in DBI::Profile as_text() thanks to Abe Ingersoll.
  Fixed DBD::DBM bug in push_names thanks to J M Davitt.
  Fixed take_imp_data for some platforms thanks to Jeffrey Klein.
  Fixed docs tie'ing CacheKids (ie LRU cache) thanks to Peter John Edwards.

  Expanded DBI::DBD docs for driver authors thanks to Martin Evans.
  Enhanced t/80proxy.t test script.
  Enhanced t/85gofer.t test script thanks to Stig.
  Enhanced t/10examp.t test script thanks to David Cantrell.
  Documented $DBI::stderr as the default value of err for internal errors.

  Gofer changes:
    track_recent now also keeps track of N most recent errors.
    The connect method is now also counted in stats.

=head2 Changes in DBI 1.601 (svn rev 10103),  21st October 2007

  Fixed t/05thrclone.t to work with Test::More >= 0.71
    thanks to Jerry D. Hedden and Michael G Schwern.
  Fixed DBI for VMS thanks to Peter (Stig) Edwards.

  Added client-side caching to DBD::Gofer. Can use any cache with
    get($k)/set($k,$v) methods, including all the Cache and Cache::Cache
    distribution modules plus Cache::Memcached, Cache::FastMmap etc.
    Works for all transports. Overridable per handle.

  Added DBI::Util::CacheMemory for use with DBD::Gofer caching.
    It's a very fast and small strict subset of Cache::Memory.

=head2 Changes in DBI 1.59 (svn rev 9874),  23rd August 2007

  Fixed DBI::ProfileData to unescape headers lines read from data file.
  Fixed DBI::ProfileData to not clobber $_, thanks to Alexey Tourbin.
  Fixed DBI::SQL::Nano to not clobber $_, thanks to Alexey Tourbin.
  Fixed DBI::PurePerl to return undef for ChildHandles if weaken not available.
  Fixed DBD::Proxy disconnect error thanks to Philip Dye.
  Fixed DBD::Gofer::Transport::Base bug (typo) in timeout code.
  Fixed DBD::Proxy rows method thanks to Philip Dye.
  Fixed dbiprof compile errors, thanks to Alexey Tourbin.
  Fixed t/03handle.t to skip some tests if ChildHandles not available.

  Added check_response_sub to DBI::Gofer::Execute

=head2 Changes in DBI 1.58 (svn rev 9678),  25th June 2007

  Fixed code triggering fatal error in bleadperl, thanks to Steve Hay.
  Fixed compiler warning thanks to Jerry D. Hedden.
  Fixed t/40profile.t to use int(dbi_time()) for systems like Cygwin where
    time() seems to be rounded not truncated from the high resolution time.
  Removed dump_results() test from t/80proxy.t.

=head2 Changes in DBI 1.57 (svn rev 9639),  13th June 2007

  Note: this release includes a change to the DBI::hash() function which will
  now produce different values than before *if* your perl was built with 64-bit
  'int' type (i.e. "perl -V:intsize" says intsize='8').  It's relatively rare
  for perl to be configured that way, even on 64-bit systems.

  Fixed XS versions of select*_*() methods to call execute()
    fetch() etc., with inner handle instead of outer.
  Fixed execute_for_fetch() to not cache errstr values
    thanks to Bart Degryse.
  Fixed unused var compiler warning thanks to JDHEDDEN.
  Fixed t/86gofer_fail tests to be less likely to fail falsely.

  Changed DBI::hash to return 'I32' type instead of 'int' so results are
    portable/consistent regardless of size of the int type.
  Corrected timeout example in docs thanks to Egmont Koblinger.
  Changed t/01basic.t to warn instead of failing when it detects
    a problem with Math::BigInt (some recent versions had problems).

  Added support for !Time and !Time~N to DBI::Profile Path. See docs.
  Added extra trace info to connect_cached thanks to Walery Studennikov.
  Added non-random (deterministic) mode to DBI_GOFER_RANDOM mechanism.
  Added DBIXS_REVISION macro that drivers can use.
  Added more docs for private_attribute_info() method.

  DBI::Profile changes:
    dbi_profile() now returns ref to relevant leaf node.
    Don't profile DESTROY during global destruction.
    Added as_node_path_list() and as_text() methods.
  DBI::ProfileDumper changes:
    Don't write file if there's no profile data.
    Uses full natural precision when saving data (was using %.6f)
    Optimized flush_to_disk().
    Locks the data file while writing.
    Enabled filename to be a code ref for dynamic names.
  DBI::ProfileDumper::Apache changes:
    Added Quiet=>1 to avoid write to STDERR in flush_to_disk().
    Added Dir=>... to specify a writable destination directory.
    Enabled DBI_PROFILE_APACHE_LOG_DIR for mod_perl 1 as well as 2.
    Added parent pid to default data file name.
  DBI::ProfileData changes:
    Added DeleteFiles option to rename & delete files once read.
    Locks the data files while reading.
    Added ability to sort by Path elements.
  dbiprof changes:
    Added --dumpnodes and --delete options.
  Added/updated docs for both DBI::ProfileDumper && ::Apache.

=head2 Changes in DBI 1.56 (svn rev 9660),  18th June 2007

  Fixed printf arg warnings thanks to JDHEDDEN.
  Fixed returning driver-private sth attributes via gofer.

  Changed pod docs docs to use =head3 instead of =item
    so now in html you get links to individual methods etc.
  Changed default gofer retry_limit from 2 to 0.
  Changed tests to workaround Math::BigInt broken versions.
  Changed dbi_profile_merge() to dbi_profile_merge_nodes()
    old name still works as an alias for the new one.
  Removed old DBI internal sanity check that's no longer valid
    causing "panic: DESTROY (dbih_clearcom)" when tracing enabled

  Added DBI_GOFER_RANDOM env var that can be use to trigger random
    failures and delays when executing gofer requests. Designed to help
    test automatic retry on failures and timeout handling.
  Added lots more docs to all the DBD::Gofer and DBI::Gofer classes.

=head2 Changes in DBI 1.55 (svn rev 9504),  4th May 2007

  Fixed set_err() so HandleSetErr hook is executed reliably, if set.
  Fixed accuracy of profiling when perl configured to use long doubles.
  Fixed 42prof_data.t on fast systems with poor timers thanks to Malcolm Nooning.
  Fixed potential corruption in selectall_arrayref and selectrow_arrayref
    for compiled drivers, thanks to Rob Davies.
    Rebuild your compiled drivers after installing DBI.

  Changed some handle creation code from perl to C code,
    to reduce handle creation cost by ~20%.
  Changed internal implementation of the CachedKids attribute
    so it's a normal handle attribute (and initially undef).
  Changed connect_cached and prepare_cached to avoid a FETCH method call,
    and thereby reduced cost by ~5% and ~30% respectively.
  Changed _set_fbav to not croak when given a wrongly sized array,
    it now warns and adjusts the row buffer to match.
  Changed some internals to improve performance with threaded perls.
  Changed DBD::NullP to be slightly more useful for testing.
  Changed File::Spec prerequisite to not require a minimum version.
  Changed tests to work with other DBMs thanks to ZMAN.
  Changed ex/perl_dbi_nulls_test.pl to be more descriptive.

  Added more functionality to the (undocumented) Callback mechanism.
    Callbacks can now elect to provide a value to be returned, in which case
    the method won't be called. A callback for "*" is applied to all methods
    that don't have their own callback.
  Added $h->{ReadOnly} attribute.
  Added support for DBI Profile Path to contain refs to scalars
    which will be de-ref'd for each profile sample.
  Added dbilogstrip utility to edit DBI logs for diff'ing (gets installed)
  Added details for SQLite 3.3 to NULL handling docs thanks to Alex Teslik.
  Added take_imp_data() to DBI::PurePerl.

  Gofer related changes:
    Fixed gofer pipeone & stream transports to avoid risk of hanging.
    Improved error handling and tracing significantly.
    Added way to generate random 1-in-N failures for methods.
    Added automatic retry-on-error mechanism to gofer transport base class.
    Added tests to show automatic retry mechanism works a treat!
    Added go_retry_hook callback hook so apps can fine-tune retry behaviour.
    Added header to request and response packets for sanity checking
      and to enable version skew between client and server.
    Added forced_single_resultset, max_cached_sth_per_dbh and max_cached_dbh_per_drh
      to gofer executor config.
    Driver-private methods installed with install_method are now proxied.
    No longer does a round-trip to the server for methods it knows
      have not been overridden by the remote driver.
    Most significant aspects of gofer behaviour are controlled by policy mechanism.
    Added policy-controlled caching of results for some methods, such as schema metadata.
    The connect_cached and prepare_cached methods cache on client and server.
    The bind_param_array and execute_array methods are now supported.
    Worked around a DBD::Sybase bind_param bug (which is fixed in DBD::Sybase 1.07)
    Added goferperf.pl utility (doesn't get installed).
    Many other assorted Gofer related bug fixes, enhancements and docs.
    The http and mod_perl transports have been remove to their own distribution.
    Client and server will need upgrading together for this release.

=head2 Changes in DBI 1.54 (svn rev 9157),  23rd February 2007

  NOTE: This release includes the 'next big thing': DBD::Gofer.
  Take a look!

  WARNING: This version has some subtle changes in DBI internals.
  It's possible, though doubtful, that some may affect your code.
  I recommend some extra testing before using this release.
  Or perhaps I'm just being over cautious...

  Fixed type_info when called for multiple dbh thanks to Cosimo Streppone.
  Fixed compile warnings in bleadperl on freebsd-6.1-release
    and solaris 10g thanks to Philip M. Gollucci.
  Fixed to compile for perl built with -DNO_MATHOMS thanks to Jerry D. Hedden.
  Fixed to work for bleadperl (r29544) thanks to Nicholas Clark.
    Users of Perl >= 5.9.5 will require DBI >= 1.54.
  Fixed rare error when profiling access to $DBI::err etc tied variables.
  Fixed DBI::ProfileDumper to not be affected by changes to $/ and $,
    thanks to Michael Schwern.

  Changed t/40profile.t to skip tests for perl < 5.8.0.
  Changed setting trace file to no longer write "Trace file set" to new file.
  Changed 'handle cleared whilst still active' warning for dbh
    to only be given for dbh that have active sth or are not AutoCommit.
  Changed take_imp_data to call finish on all Active child sth.
  Changed DBI::PurePerl trace() method to be more consistent.
  Changed set_err method to effectively not append to errstr if the new errstr
    is the same as the current one.
  Changed handle factory methods, like connect, prepare, and table_info,
    to copy any error/warn/info state of the handle being returned
    up into the handle the method was called on.
  Changed row buffer handling to not alter NUM_OF_FIELDS if it's
    inconsistent with number of elements in row buffer array.
  Updated DBI::DBD docs re handling multiple result sets.
  Updated DBI::DBD docs for driver authors thanks to Ammon Riley
    and Dean Arnold.
  Updated column_info docs to note that if a table doesn't exist
    you get an sth for an empty result set and not an error.

  Added new DBD::Gofer 'stateless proxy' driver and framework,
    and the DBI test suite is now also executed via DBD::Gofer,
    and DBD::Gofer+DBI::PurePerl, in addition to DBI::PurePerl.
  Added ability for trace() to support filehandle argument,
    including tracing into a string, thanks to Dean Arnold.
  Added ability for drivers to implement func() method
    so proxy drivers can proxy the func method itself.
  Added SQL_BIGINT type code (resolved to the ODBC/JDBC value (-5))
  Added $h->private_attribute_info method.

=head2 Changes in DBI 1.53 (svn rev 7995),   31st October 2006

  Fixed checks for weaken to work with early 5.8.x versions
  Fixed DBD::Proxy handling of some methods, including commit and rollback.
  Fixed t/40profile.t to be more insensitive to long double precision.
  Fixed t/40profile.t to be insensitive to small negative shifts in time
    thanks to Jamie McCarthy.
  Fixed t/40profile.t to skip tests for perl < 5.8.0.
  Fixed to work with current 'bleadperl' (~5.9.5) thanks to Steve Peters.
    Users of Perl >= 5.9.5 will require DBI >= 1.53.
  Fixed to be more robust against drivers not handling multiple result
    sets properly, thanks to Gisle Aas.

  Added array context support to execute_array and execute_for_fetch
    methods which returns executed tuples and rows affected.
  Added Tie::Cache::LRU example to docs thanks to Brandon Black.

=head2 Changes in DBI 1.52 (svn rev 6840),   30th July 2006

  Fixed memory leak (per handle) thanks to Nicholas Clark and Ephraim Dan.
  Fixed memory leak (16 bytes per sth) thanks to Doru Theodor Petrescu.
  Fixed execute_for_fetch/execute_array to RaiseError thanks to Martin J. Evans.
  Fixed for perl 5.9.4. Users of Perl >= 5.9.4 will require DBI >= 1.52.

  Updated DBD::File to 0.35 to match the latest release on CPAN.

  Added $dbh->statistics_info specification thanks to Brandon Black.

  Many changes and additions to profiling:
    Profile Path can now uses sane strings instead of obscure numbers,
    can refer to attributes, assorted magical values, and even code refs!
    Parsing of non-numeric DBI_PROFILE env var values has changed.
    Changed DBI::Profile docs extensively - many new features.
    See DBI::Profile docs for more information.

=head2 Changes in DBI 1.51 (svn rev 6475),   6th June 2006

  Fixed $dbh->clone method 'signature' thanks to Jeffrey Klein.
  Fixed default ping() method to return false if !$dbh->{Active}.
  Fixed t/40profile.t to be insensitive to long double precision.
  Fixed for perl 5.8.0's more limited weaken() function.
  Fixed DBD::Proxy to not alter $@ in disconnect or AUTOLOADd methods.
  Fixed bind_columns() to use return set_err(...) instead of die()
    to report incorrect number of parameters, thanks to Ben Thul.
  Fixed bind_col() to ignore undef as bind location, thanks to David Wheeler.
  Fixed for perl 5.9.x for non-threaded builds thanks to Nicholas Clark.
    Users of Perl >= 5.9.x will require DBI >= 1.51.
  Fixed fetching of rows as hash refs to preserve utf8 on field names
    from $sth->{NAME} thanks to Alexey Gaidukov.
  Fixed build on Win32 (dbd_postamble) thanks to David Golden.

  Improved performance for thread-enabled perls thanks to Gisle Aas.
  Drivers can now use PERL_NO_GET_CONTEXT thanks to Gisle Aas.
    Driver authors please read the notes in the DBI::DBD docs.
  Changed DBI::Profile format to always include a percentage,
    if not exiting then uses time between the first and last DBI call.
  Changed DBI::ProfileData to be more forgiving of systems with
    unstable clocks (where time may go backwards occasionally).
  Clarified the 'Subclassing the DBI' docs.
  Assorted minor changes to docs from comments on annocpan.org.
  Changed Makefile.PL to avoid incompatible options for old gcc.

  Added 'fetch array of hash refs' example to selectall_arrayref
    docs thanks to Tom Schindl.
  Added docs for $sth->{ParamArrays} thanks to Martin J. Evans.
  Added reference to $DBI::neat_maxlen in TRACING section of docs.
  Added ability for DBI::Profile Path to include attributes
    and a summary of where the code was called from.

=head2 Changes in DBI 1.50 (svn rev 2307),   13 December 2005

  Fixed Makefile.PL options for gcc bug introduced in 1.49.
  Fixed handle magic order to keep DBD::Oracle happy.
  Fixed selectrow_array to return empty list on error.

  Changed dbi_profile_merge() to be able to recurse and merge
    sub-trees of profile data.

  Added documentation for dbi_profile_merge(), including how to
    measure the time spent inside the DBI for an http request.

=head2 Changes in DBI 1.49 (svn rev 2287),   29th November 2005

  Fixed assorted attribute handling bugs in DBD::Proxy.
  Fixed croak() in DBD::NullP thanks to Sergey Skvortsov.
  Fixed handling of take_imp_data() and dbi_imp_data attribute.
  Fixed bugs in DBD::DBM thanks to Jeff Zucker.
  Fixed bug in DBI::ProfileDumper thanks to Sam Tregar.
  Fixed ping in DBD::Proxy thanks to George Campbell.
  Fixed dangling ref in $sth after parent $dbh destroyed
    with thanks to il@rol.ru for the bug report #13151
  Fixed prerequisites to include Storable thanks to Michael Schwern.
  Fixed take_imp_data to be more practical.

  Change to require perl 5.6.1 (as advertised in 2003) not 5.6.0.
  Changed internals to be more strictly coded thanks to Andy Lester.
  Changed warning about multiple copies of Driver.xst found in @INC
    to ignore duplicated directories thanks to Ed Avis.
  Changed Driver.xst to enable drivers to define an dbd_st_prepare_sv
    function where the statement parameter is an SV. That enables
    compiled drivers to support SQL strings that are UTF-8.
  Changed "use DBI" to only set $DBI::connect_via if not already set.
  Changed docs to clarify pre-method clearing of err values.

  Added ability for DBI::ProfileData to edit profile path on loading.
    This enables aggregation of different SQL statements into the same
    profile node - very handy when not using placeholders or when working
    multiple separate tables for the same thing (ie logtable_2005_11_28)
  Added $sth->{ParamTypes} specification thanks to Dean Arnold.
  Added $h->{Callbacks} attribute to enable code hooks to be invoked
    when certain methods are called. For example:
    $dbh->{Callbacks}->{prepare} = sub { ... };
    With thanks to David Wheeler for the kick start.
  Added $h->{ChildHandles} (using weakrefs) thanks to Sam Tregar
    I've recoded it in C so there's no significant performance impact.
  Added $h->{Type} docs (returns 'dr', 'db', or 'st')
  Adding trace message in DESTROY if InactiveDestroy enabled.
  Added %drhs = DBI->installed_drivers();

  Ported DBI::ProfileDumper::Apache to mod_perl2 RC5+
    thanks to Philip M. Golluci

=head2 Changes in DBI 1.48 (svn rev 928),    14th March 2005

  Fixed DBI::DBD::Metadata generation of type_info_all thanks to Steffen Goeldner
    (driver authors who have used it should rerun it).

  Updated docs for NULL Value placeholders thanks to Brian Campbell.

  Added multi-keyfield nested hash fetching to fetchall_hashref()
    thanks to Zhuang (John) Li for polishing up my draft.
  Added registered driver prefixes: amzn_ for DBD::Amazon and yaswi_ for DBD::Yaswi.


=head2 Changes in DBI 1.47 (svn rev 854),    2nd February 2005

  Fixed DBI::ProxyServer to not create pid files by default.
    References: Ubuntu Security Notice USN-70-1, CAN-2005-0077
    Thanks to Javier Fernández-Sanguino Peña from the
    Debian Security Audit Project, and Jonathan Leffler.
  Fixed some tests to work with older Test::More versions.
  Fixed setting $DBI::err/errstr in DBI::PurePerl.
  Fixed potential undef warning from connect_cached().
  Fixed $DBI::lasth handling for DESTROY so lasth points to
    parent even if DESTROY called other methods.
  Fixed DBD::Proxy method calls to not alter $@.
  Fixed DBD::File problem with encoding pragma thanks to Erik Rijkers.

  Changed error handling so undef errstr doesn't cause warning.
  Changed DBI::DBD docs to use =head3/=head4 pod thanks to
    Jonathan Leffler. This may generate warnings for perl 5.6.
  Changed DBI::PurePerl to set autoflush on trace filehandle.
  Changed DBD::Proxy to treat Username as a local attribute
    so recent DBI version can be used with old DBI::ProxyServer.
  Changed driver handle caching in DBD::File.
  Added $GetInfoType{SQL_DATABASE_NAME} thanks to Steffen Goeldner.

  Updated docs to recommend some common DSN string attributes.
  Updated connect_cached() docs with issues and suggestions.
  Updated docs for NULL Value placeholders thanks to Brian Campbell.
  Updated docs for primary_key_info and primary_keys.
  Updated docs to clarify that the default fetchrow_hashref behaviour,
    of returning a ref to a new hash for each row, will not change.
  Updated err/errstr/state docs for DBD authors thanks to Steffen Goeldner.
  Updated handle/attribute docs for DBD authors thanks to Steffen Goeldner.
  Corrected and updated LongReadLen docs thanks to Bart Lateur.
  Added DBD::JDBC as a registered driver.

=head2 Changes in DBI 1.46 (svn rev 584),    16th November 2004

  Fixed parsing bugs in DBI::SQL::Nano thanks to Jeff Zucker.
  Fixed a couple of bad links in docs thanks to Graham Barr.
  Fixed test.pl Win32 undef warning thanks to H.Merijn Brand & David Repko.
  Fixed minor issues in DBI::DBD::Metadata thanks to Steffen Goeldner.
  Fixed DBI::PurePerl neat() to use double quotes for utf8.

  Changed execute_array() definition, and default implementation,
    to not consider scalar values for execute tuple count. See docs.
  Changed DBD::File to enable ShowErrorStatement by default,
    which affects DBD::File subclasses such as DBD::CSV and DBD::DBM.
  Changed use DBI qw(:utils) tag to include $neat_maxlen.
  Updated Roadmap and ToDo.

  Added data_string_diff() data_string_desc() and data_diff()
    utility functions to help diagnose Unicode issues.
    All can be imported via the use DBI qw(:utils) tag.

=head2 Changes in DBI 1.45 (svn rev 480),    6th October 2004

  Fixed DBI::DBD code for drivers broken in 1.44.
  Fixed "Free to wrong pool"/"Attempt to free unreferenced scalar" in FETCH.

=head2 Changes in DBI 1.44 (svn rev 478),    5th October 2004

  Fixed build issues on VMS thanks to Jakob Snoer.
  Fixed DBD::File finish() method to return 1 thanks to Jan Dubois.
  Fixed rare core dump during global destruction thanks to Mark Jason Dominus.
  Fixed risk of utf8 flag persisting from one row to the next.

  Changed bind_param_array() so it doesn't require all bind arrays
    to have the same number of elements.
  Changed bind_param_array() to error if placeholder number <= 0.
  Changed execute_array() definition, and default implementation,
    to effectively NULL-pad shorter bind arrays.
  Changed execute_array() to return "0E0" for 0 as per the docs.
  Changed execute_for_fetch() definition, and default implementation,
    to return "0E0" for 0 like execute() and execute_array().
  Changed Test::More prerequisite to Test::Simple (which is also the name
    of the distribution both are packaged in) to work around ppm behaviour.

  Corrected docs to say that get/set of unknown attribute generates
    a warning and is no longer fatal. Thanks to Vadim.
  Corrected fetchall_arrayref() docs example thanks to Drew Broadley.

  Added $h1->swap_inner_handle($h2) sponsored by BizRate.com


=head2 Changes in DBI 1.43 (svn rev 377),    2nd July 2004

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
  Changed DBI::Profile header to include the date and time.

  Added DBI->parse_dsn($dsn) method.
  Added warning if build directory path contains white space.
  Added docs for parse_trace_flags() and parse_trace_flag().
  Removed "may change" warnings from the docs for table_info(),
    primary_key_info(), and foreign_key_info() methods.

=head2 Changes in DBI 1.42 (svn rev 222),    12th March 2004

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

=head2 Changes in DBI 1.41 (svn rev 130),    22nd February 2004

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
    Documented that bind_col() can take an attribute hash.
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
  : it is the most thoroughly tested release ever.)

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
    faster making those calls. Most noticeable with fetchall_arrayref for
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
  Made disconnect_all a compulsory method for drivers.


=head1 ANCIENT HISTORY

12th Oct 1994: First public release of the DBI module.
               (for Perl 5.000-beta-3h)

19th Sep 1994: DBperl project renamed to DBI.

29th Sep 1992: DBperl project started.

=cut
