package DBD::SQLite::GetInfo;

use 5.006;
use strict;
use warnings;

use DBD::SQLite;

# SQL_DRIVER_VER should be formatted as dd.dd.dddd
my $dbdversion = $DBD::SQLite::VERSION;
$dbdversion .= '_00' if $dbdversion =~ /^\d+\.\d+$/;
my $sql_driver_ver = sprintf("%02d.%02d.%04d", split(/[\._]/, $dbdversion));

# Full list of keys and their return types: DBI::Const::GetInfo::ODBC

# Most of the key definitions can be gleaned from:
#
# https://docs.microsoft.com/en-us/sql/odbc/reference/syntax/sqlgetinfo-function

our %info = (
     20 => 'N',                           # SQL_ACCESSIBLE_PROCEDURES  - No stored procedures to access
     19 => 'Y',                           # SQL_ACCESSIBLE_TABLES      - SELECT access to all tables in table_info
      0 => 0,                             # SQL_ACTIVE_CONNECTIONS     - No maximum connection limit
    116 => 0,                             # SQL_ACTIVE_ENVIRONMENTS    - No "active environment" limit
      1 => 0,                             # SQL_ACTIVE_STATEMENTS      - No concurrent activity limit
    169 => 127,                           # SQL_AGGREGATE_FUNCTIONS    - Supports all SQL-92 aggregrate functions
    117 => 0,                             # SQL_ALTER_DOMAIN           - No ALTER DOMAIN support
     86 => 1,                             # SQL_ALTER_TABLE            - Only supports ADD COLUMN and table rename (not listed in enum) in ALTER TABLE statements
  10021 => 0,                             # SQL_ASYNC_MODE             - No asynchronous support (in vanilla SQLite)
    120 => 0,                             # SQL_BATCH_ROW_COUNT        - No special row counting access
    121 => 0,                             # SQL_BATCH_SUPPORT          - No batches
     82 => 0,                             # SQL_BOOKMARK_PERSISTENCE   - No bookmark support
    114 => 1,                             # SQL_CATALOG_LOCATION       - Database comes first in identifiers
  10003 => 'Y',                           # SQL_CATALOG_NAME           - Supports database names
     41 => '.',                           # SQL_CATALOG_NAME_SEPARATOR - Separated by dot
     42 => 'database',                    # SQL_CATALOG_TERM           - SQLite calls catalogs databases
     92 => 1+4+8,                         # SQL_CATALOG_USAGE          - Supported in calls to DML & table/index definiton (no procedures or permissions)
  10004 => 'UTF-8',                       # SQL_COLLATION_SEQ          - SQLite 3 uses UTF-8 by default
     87 => 'Y',                           # SQL_COLUMN_ALIAS           - Supports column aliases
     22 => 0,                             # SQL_CONCAT_NULL_BEHAVIOR   - 'a'||NULL = NULL

# SQLite has no CONVERT function, only CAST.  However, it converts to every "affinity" it supports.
#
# The only SQL_CVT_* types it doesn't support are date/time types, as it has no concept of
# date/time values once inserted.  These are only convertable to text-like types.  GUIDs are in
# the same boat, having no real means of switching to a numeric format.
#
# text/binary types = 31723265
# numeric types     = 28926
# date/time types   = 1802240
# total             = 33554431

     48 => 1,                             # SQL_CONVERT_FUNCTIONS      - CAST only

     53 => 31723265+28926,                # SQL_CONVERT_BIGINT
     54 => 31723265+28926,                # SQL_CONVERT_BINARY
     55 => 31723265+28926,                # SQL_CONVERT_BIT
     56 => 33554431,                      # SQL_CONVERT_CHAR
     57 => 31723265+1802240,              # SQL_CONVERT_DATE
     58 => 31723265+28926,                # SQL_CONVERT_DECIMAL
     59 => 31723265+28926,                # SQL_CONVERT_DOUBLE
     60 => 31723265+28926,                # SQL_CONVERT_FLOAT
    173 => 31723265,                      # SQL_CONVERT_GUID
     61 => 31723265+28926,                # SQL_CONVERT_INTEGER
    123 => 31723265+1802240,              # SQL_CONVERT_INTERVAL_DAY_TIME
    124 => 31723265+1802240,              # SQL_CONVERT_INTERVAL_YEAR_MONTH
     71 => 31723265+28926,                # SQL_CONVERT_LONGVARBINARY
     62 => 31723265+28926,                # SQL_CONVERT_LONGVARCHAR
     63 => 31723265+28926,                # SQL_CONVERT_NUMERIC
     64 => 31723265+28926,                # SQL_CONVERT_REAL
     65 => 31723265+28926,                # SQL_CONVERT_SMALLINT
     66 => 31723265+1802240,              # SQL_CONVERT_TIME
     67 => 31723265+1802240,              # SQL_CONVERT_TIMESTAMP
     68 => 31723265+28926,                # SQL_CONVERT_TINYINT
     69 => 33554431,                      # SQL_CONVERT_VARBINARY
     70 => 33554431,                      # SQL_CONVERT_VARCHAR
    122 => 33554431,                      # SQL_CONVERT_WCHAR
    125 => 33554431,                      # SQL_CONVERT_WLONGVARCHAR
    126 => 33554431,                      # SQL_CONVERT_WVARCHAR

     74 => 1,                             # SQL_CORRELATION_NAME         - Table aliases are supported, but must be named differently
    127 => 0,                             # SQL_CREATE_ASSERTION         - No CREATE ASSERTION support
    128 => 0,                             # SQL_CREATE_CHARACTER_SET     - No CREATE CHARACTER SET support
    129 => 0,                             # SQL_CREATE_COLLATION         - No CREATE COLLATION support
    130 => 0,                             # SQL_CREATE_DOMAIN            - No CREATE DOMAIN support
    131 => 0,                             # SQL_CREATE_SCHEMA            - No CREATE SCHEMA support
    132 => 16383-2-8-4096,                # SQL_CREATE_TABLE             - Most of the functionality of CREATE TABLE support
    133 => 0,                             # SQL_CREATE_TRANSLATION       - No CREATE TRANSLATION support
    134 => 1,                             # SQL_CREATE_VIEW              - CREATE VIEW, no WITH CHECK OPTION support

     23 => 2,                             # SQL_CURSOR_COMMIT_BEHAVIOR   - Cursors are preserved
     24 => 2,                             # SQL_CURSOR_ROLLBACK_BEHAVIOR - Cursors are preserved
  10001 => 0,                             # SQL_CURSOR_SENSITIVITY       - Cursors have a concept of snapshots, though this depends on the transaction type

      2 => \&sql_data_source_name,        # SQL_DATA_SOURCE_NAME         - The DSN
     25 => \&sql_data_source_read_only,   # SQL_DATA_SOURCE_READ_ONLY    - Might have a SQLITE_OPEN_READONLY flag
     16 => \&sql_database_name,           # SQL_DATABASE_NAME            - Self-explanatory
    119 => 0,                             # SQL_DATETIME_LITERALS        - No support for SQL-92's super weird date/time literal format (ie: {d '2999-12-12'})
     17 => 'SQLite',                      # SQL_DBMS_NAME                - You are here
     18 => \&sql_dbms_ver,                # SQL_DBMS_VER                 - This driver version
    170 => 1+2,                           # SQL_DDL_INDEX                - Supports CREATE/DROP INDEX
     26 => 8,                             # SQL_DEFAULT_TXN_ISOLATION    - Default is SERIALIZABLE (See "PRAGMA read_uncommitted")
  10002 => 'N',                           # SQL_DESCRIBE_PARAMETER       - No DESCRIBE INPUT support

# XXX: MySQL/Oracle fills in HDBC and HENV, but information on what should actually go there is
# hard to acquire.

#   171 => undef,                         # SQL_DM_VER                   - Not a Driver Manager
#     3 => undef,                         # SQL_DRIVER_HDBC              - Not a Driver Manager
#   135 => undef,                         # SQL_DRIVER_HDESC             - Not a Driver Manager
#     4 => undef,                         # SQL_DRIVER_HENV              - Not a Driver Manager
#    76 => undef,                         # SQL_DRIVER_HLIB              - Not a Driver Manager
#     5 => undef,                         # SQL_DRIVER_HSTMT             - Not a Driver Manager
      6 => 'libsqlite3odbc.so',           # SQL_DRIVER_NAME              - SQLite3 ODBC driver (if installed)
     77 => '03.00',                       # SQL_DRIVER_ODBC_VER          - Same as sqlite3odbc.c
      7 => $sql_driver_ver,               # SQL_DRIVER_VER               - Self-explanatory

    136 => 0,                             # SQL_DROP_ASSERTION           - No DROP ASSERTION support
    137 => 0,                             # SQL_DROP_CHARACTER_SET       - No DROP CHARACTER SET support
    138 => 0,                             # SQL_DROP_COLLATION           - No DROP COLLATION support
    139 => 0,                             # SQL_DROP_DOMAIN              - No DROP DOMAIN support
    140 => 0,                             # SQL_DROP_SCHEMA              - No DROP SCHEMA support
    141 => 1,                             # SQL_DROP_TABLE               - DROP TABLE support, no RESTRICT/CASCADE
    142 => 0,                             # SQL_DROP_TRANSLATION         - No DROP TRANSLATION support
    143 => 1,                             # SQL_DROP_VIEW                - DROP VIEW support, no RESTRICT/CASCADE

# NOTE: This is based purely on what sqlite3odbc supports.
#
# Static CA1: NEXT, ABSOLUTE, RELATIVE, BOOKMARK, LOCK_NO_CHANGE, POSITION, UPDATE, DELETE, REFRESH,
# BULK_ADD, BULK_UPDATE_BY_BOOKMARK, BULK_DELETE_BY_BOOKMARK = 466511
#
# Forward-only CA1: NEXT, BOOKMARK
#
# CA2: READ_ONLY_CONCURRENCY, LOCK_CONCURRENCY

    144 => 0,                             # SQL_DYNAMIC_CURSOR_ATTRIBUTES1 - No dynamic cursor support
    145 => 0,                             # SQL_DYNAMIC_CURSOR_ATTRIBUTES2 - No dynamic cursor support
    146 => 1+8,                           # SQL_FORWARD_ONLY_CURSOR_ATTRIBUTES1
    147 => 1+2,                           # SQL_FORWARD_ONLY_CURSOR_ATTRIBUTES2
    150 => 0,                             # SQL_KEYSET_CURSOR_ATTRIBUTES1 - No keyset cursor support
    151 => 0,                             # SQL_KEYSET_CURSOR_ATTRIBUTES2 - No keyset cursor support
    167 => 466511,                        # SQL_STATIC_CURSOR_ATTRIBUTES1
    168 => 1+2,                           # SQL_STATIC_CURSOR_ATTRIBUTES2

     27 => 'Y',                           # SQL_EXPRESSIONS_IN_ORDERBY     - ORDER BY allows expressions
      8 => 63,                            # SQL_FETCH_DIRECTION            - Cursors support next, first, last, prior, absolute, relative
     84 => 2,                             # SQL_FILE_USAGE                 - Single-tier driver, treats files as databases
     81 => 1+2+8,                         # SQL_GETDATA_EXTENSIONS         - Same as sqlite3odbc.c
     88 => 3,                             # SQL_GROUP_BY                   - SELECT columns are independent of GROUP BY columns
     28 => 4,                             # SQL_IDENTIFIER_CASE            - Not case-sensitive, stored in mixed case
     29 => '"',                           # SQL_IDENTIFIER_QUOTE_CHAR      - Uses " for identifiers, though supports [] and ` as well
    148 => 0,                             # SQL_INDEX_KEYWORDS             - No support for ASC/DESC/ALL for CREATE INDEX
    149 => 0,                             # SQL_INFO_SCHEMA_VIEWS          - No support for INFORMATION_SCHEMA
    172 => 1+2,                           # SQL_INSERT_STATEMENT           - INSERT...VALUES & INSERT...SELECT
     73 => 'N',                           # SQL_INTEGRITY                  - No support for "Integrity Enhancement Facility"
     89 => \&sql_keywords,                # SQL_KEYWORDS                   - List of non-ODBC keywords
    113 => 'Y',                           # SQL_LIKE_ESCAPE_CLAUSE         - Supports LIKE...ESCAPE
     78 => 1,                             # SQL_LOCK_TYPES                 - Only NO_CHANGE

  10022 => 0,                             # SQL_MAX_ASYNC_CONCURRENT_STATEMENTS - No async mode
    112 => 1_000_000,                     # SQL_MAX_BINARY_LITERAL_LEN     - SQLITE_MAX_SQL_LENGTH
     34 => 1_000_000,                     # SQL_MAX_CATALOG_NAME_LEN       - SQLITE_MAX_SQL_LENGTH
    108 => 1_000_000,                     # SQL_MAX_CHAR_LITERAL_LEN       - SQLITE_MAX_SQL_LENGTH
     97 => 2000,                          # SQL_MAX_COLUMNS_IN_GROUP_BY    - SQLITE_MAX_COLUMN
     98 => 2000,                          # SQL_MAX_COLUMNS_IN_INDEX       - SQLITE_MAX_COLUMN
     99 => 2000,                          # SQL_MAX_COLUMNS_IN_ORDER_BY    - SQLITE_MAX_COLUMN
    100 => 2000,                          # SQL_MAX_COLUMNS_IN_SELECT      - SQLITE_MAX_COLUMN
    101 => 2000,                          # SQL_MAX_COLUMNS_IN_TABLE       - SQLITE_MAX_COLUMN
     30 => 1_000_000,                     # SQL_MAX_COLUMN_NAME_LEN        - SQLITE_MAX_SQL_LENGTH
      1 => 1021,                          # SQL_MAX_CONCURRENT_ACTIVITIES  - Typical filehandle limits
     31 => 1_000_000,                     # SQL_MAX_CURSOR_NAME_LEN        - SQLITE_MAX_SQL_LENGTH
      0 => 1021,                          # SQL_MAX_DRIVER_CONNECTIONS     - Typical filehandle limits
  10005 => 1_000_000,                     # SQL_MAX_IDENTIFIER_LEN         - SQLITE_MAX_SQL_LENGTH
    102 => 2147483646*65536,              # SQL_MAX_INDEX_SIZE             - Tied to DB size, which is theortically 140TB
     32 => 1_000_000,                     # SQL_MAX_OWNER_NAME_LEN         - SQLITE_MAX_SQL_LENGTH
     33 => 1_000_000,                     # SQL_MAX_PROCEDURE_NAME_LEN     - SQLITE_MAX_SQL_LENGTH
     34 => 1_000_000,                     # SQL_MAX_QUALIFIER_NAME_LEN     - SQLITE_MAX_SQL_LENGTH
    104 => 1_000_000,                     # SQL_MAX_ROW_SIZE               - SQLITE_MAX_SQL_LENGTH (since INSERT has to be used)
    103 => 'Y',                           # SQL_MAX_ROW_SIZE_INCLUDES_LONG
     32 => 1_000_000,                     # SQL_MAX_SCHEMA_NAME_LEN        - SQLITE_MAX_SQL_LENGTH
    105 => 1_000_000,                     # SQL_MAX_STATEMENT_LEN          - SQLITE_MAX_SQL_LENGTH
    106 => 64,                            # SQL_MAX_TABLES_IN_SELECT       - 64 tables, because of the bitmap in the query optimizer
     35 => 1_000_000,                     # SQL_MAX_TABLE_NAME_LEN         - SQLITE_MAX_SQL_LENGTH
    107 => 0,                             # SQL_MAX_USER_NAME_LEN          - No user support

     37 => 'Y',                           # SQL_MULTIPLE_ACTIVE_TXN        - Supports mulitple txns, though not nested
     36 => 'N',                           # SQL_MULT_RESULT_SETS           - No batches
    111 => 'N',                           # SQL_NEED_LONG_DATA_LEN         - Doesn't care about LONG
     75 => 1,                             # SQL_NON_NULLABLE_COLUMNS       - Supports NOT NULL
     85 => 1,                             # SQL_NULL_COLLATION             - NULLs first on ASC (low end)
     49 => 4194304+1,                     # SQL_NUMERIC_FUNCTIONS          - Just ABS & ROUND (has RANDOM, but not RAND)

      9 => 1,                             # SQL_ODBC_API_CONFORMANCE       - Same as sqlite3odbc.c
    152 => 1,                             # SQL_ODBC_INTERFACE_CONFORMANCE - Same as sqlite3odbc.c
     12 => 0,                             # SQL_ODBC_SAG_CLI_CONFORMANCE   - Same as sqlite3odbc.c
     15 => 0,                             # SQL_ODBC_SQL_CONFORMANCE       - Same as sqlite3odbc.c
     10 => '03.00',                       # SQL_ODBC_VER                   - Same as sqlite3odbc.c

    115 => 1+8+16+32+64,                  # SQL_OJ_CAPABILITIES            - Supports all OUTER JOINs except RIGHT & FULL
     90 => 'N',                           # SQL_ORDER_BY_COLUMNS_IN_SELECT - ORDER BY columns don't have to be in the SELECT list
     38 => 'Y',                           # SQL_OUTER_JOINS                - Supports OUTER JOINs
    153 => 2,                             # SQL_PARAM_ARRAY_ROW_COUNTS     - Only has row counts for executed statements
    154 => 3,                             # SQL_PARAM_ARRAY_SELECTS        - No support for arrays of parameters
     80 => 0,                             # SQL_POSITIONED_STATEMENTS      - No support for positioned statements (WHERE CURRENT OF or SELECT FOR UPDATE)
     79 => 31,                            # SQL_POS_OPERATIONS             - Supports all SQLSetPos operations
     21 => 'N',                           # SQL_PROCEDURES                 - No procedures
     40 => '',                            # SQL_PROCEDURE_TERM             - No procedures
     93 => 4,                             # SQL_QUOTED_IDENTIFIER_CASE     - Even quoted identifiers are case-insensitive
     11 => 'N',                           # SQL_ROW_UPDATES                - No fancy cursor update support
     39 => '',                            # SQL_SCHEMA_TERM                - No schemas
     91 => 0,                             # SQL_SCHEMA_USAGE               - No schemas
     43 => 2,                             # SQL_SCROLL_CONCURRENCY         - Updates/deletes on cursors lock the database
     44 => 1+16,                          # SQL_SCROLL_OPTIONS             - Only supports static & forward-only cursors
     14 => '\\',                          # SQL_SEARCH_PATTERN_ESCAPE      - Default escape character for LIKE is \
     13 => \&sql_server_name,             # SQL_SERVER_NAME                - Just $dbh->{Name}
     94 => '',                            # SQL_SPECIAL_CHARACTERS         - Other drivers tend to stick to the ASCII/Latin-1 range, and SQLite uses all of
                                          #                                  the lower 7-bit punctuation for other things

    155 => 7,                             # SQL_SQL92_DATETIME_FUNCTIONS        - Supports CURRENT_(DATE|TIME|TIMESTAMP)
    156 => 1+2+4+8,                       # SQL_SQL92_FOREIGN_KEY_DELETE_RULE   - Support all ON DELETE options
    157 => 1+2+4+8,                       # SQL_SQL92_FOREIGN_KEY_UPDATE_RULE   - Support all ON UPDATE options
    158 => 0,                             # SQL_SQL92_GRANT                     - No users; no support for GRANT
    159 => 0,                             # SQL_SQL92_NUMERIC_VALUE_FUNCTIONS   - No support for any of the listed functions
    160 => 1+2+4+512+1024+2048+4096+8192, # SQL_SQL92_PREDICATES                - Supports the important comparison operators
    161 => 2+16+64+128,                   # SQL_SQL92_RELATIONAL_JOIN_OPERATORS - Supports the important ones except RIGHT/FULL OUTER JOINs
    162 => 0,                             # SQL_SQL92_REVOKE                    - No users; no support for REVOKE
    163 => 1+2+8,                         # SQL_SQL92_ROW_VALUE_CONSTRUCTOR     - Supports most row value constructors
    164 => 2+4,                           # SQL_SQL92_STRING_FUNCTIONS          - Just UPPER & LOWER (has SUBSTR, but not SUBSTRING and SQL-92's weird TRIM syntax)
    165 => 1+2+4+8,                       # SQL_SQL92_VALUE_EXPRESSIONS         - Supports all SQL-92 value expressions

    118 => 1,                             # SQL_SQL_CONFORMANCE              - SQL-92 Entry level
     83 => 0,                             # SQL_STATIC_SENSITIVITY           - Cursors would lock the DB, so only old data is visible
     50 => 8+16+256+1024+16384+131072,    # SQL_STRING_FUNCTIONS             - LTRIM, LENGTH, REPLACE, RTRIM, CHAR, SOUNDEX
     95 => 1+2+4+8+16,                    # SQL_SUBQUERIES                   - Supports all of the subquery types
     51 => 4,                             # SQL_SYSTEM_FUNCTIONS             - Only IFNULL
     45 => 'table',                       # SQL_TABLE_TERM                   - Tables are called tables
    109 => 0,                             # SQL_TIMEDATE_ADD_INTERVALS       - No support for INTERVAL
    110 => 0,                             # SQL_TIMEDATE_DIFF_INTERVALS      - No support for INTERVAL
     52 => 0x20000+0x40000+0x80000,       # SQL_TIMEDATE_FUNCTIONS           - Only supports CURRENT_(DATE|TIME|TIMESTAMP)
     46 => 2,                             # SQL_TXN_CAPABLE                  - Full transaction support for both DML & DDL
     72 => 1+8,                           # SQL_TXN_ISOLATION_OPTION         - Supports read uncommitted and serializable
     96 => 1+2,                           # SQL_UNION                        - Supports UNION and UNION ALL
     47 => '',                            # SQL_USER_NAME                    - No users

    166 => 1,                             # SQL_STANDARD_CLI_CONFORMANCE     - X/Open CLI Version 1.0
  10000 => 1992,                          # SQL_XOPEN_CLI_YEAR               - Year for V1.0
);

sub sql_dbms_ver {
    my $dbh = shift;
    return $dbh->FETCH('sqlite_version');
}

sub sql_data_source_name {
    my $dbh = shift;
    return "dbi:SQLite:".$dbh->{Name};
}

sub sql_data_source_read_only {
    my $dbh = shift;
    my $flags = $dbh->FETCH('sqlite_open_flags') || 0;
    return $dbh->{ReadOnly} || ($flags & DBD::SQLite::OPEN_READONLY()) ? 'Y' : 'N';
}

sub sql_database_name {
    my $dbh = shift;
    my $databases = $dbh->selectall_hashref('PRAGMA database_list', 'seq');
    return $databases->{0}{name};
}

sub sql_keywords {
    # SQLite keywords minus ODBC keywords
    return join ',', (qw<
        ABORT     AFTER   ANALYZE ATTACH AUTOINCREMENT BEFORE  CONFLICT DATABASE  DETACH  EACH    EXCLUSIVE
        EXPLAIN   FAIL    GLOB    IF     IGNORE        INDEXED INSTEAD  ISNULL    LIMIT   NOTNULL OFFSET
        PLAN      PRAGMA  QUERY   RAISE  RECURSIVE     REGEXP  REINDEX  RELEASE   RENAME  REPLACE ROW
        SAVEPOINT TEMP    TRIGGER VACUUM VIRTUAL       WITHOUT
    >);
}

sub sql_server_name {
    my $dbh = shift;
    return $dbh->{Name};
}

1;

__END__
