package SQL::Statement::GetInfo;

use SQL::Statement();
use vars qw(%info);


my @Keywords = qw(
  INTEGERVAL STRING REALVAL IDENT NULLVAL PARAM OPERATOR IS AND OR ERROR
  INSERT UPDATE SELECT DELETE DROP CREATE ALL DISTINCT WHERE ORDER ASC
  DESC FROM INTO BY VALUES SET NOT TABLE CHAR VARCHAR REAL INTEGER
  PRIMARY KEY BLOB TEXT
);
sub sql_keywords {
    return join ',', @Keywords;
}

%info = (
     20 => "N"                             # SQL_ACCESSIBLE_PROCEDURES
,    19 => "Y"                             # SQL_ACCESSIBLE_TABLES
#     0 => undef                           # SQL_ACTIVE_CONNECTIONS
#   116 => undef                           # SQL_ACTIVE_ENVIRONMENTS
#     1 => undef                           # SQL_ACTIVE_STATEMENTS
,    169 => 0x0000007F                     # SQL_AGGREGATE_FUNCTIONS
#                                             SQL_AF_AVG      + 1
#                                             SQL_AF_COUNT    + 2
#                                             SQL_AF_MAX      + 4
#                                             SQL_AF_MIN      + 8
#                                             SQL_AF_SUM      + 10
#                                             SQL_AF_DISTINCT + 20
#                                             SQL_AF_ALL      + 40
,    117 => 0                              # SQL_ALTER_DOMAIN -
,     86 => 0                              # SQL_ALTER_TABLE  -
# 10021 => undef                           # SQL_ASYNC_MODE
#   120 => undef                           # SQL_BATCH_ROW_COUNT
#   121 => undef                           # SQL_BATCH_SUPPORT
#    82 => undef                           # SQL_BOOKMARK_PERSISTENCE
,    114 => 1                              # SQL_CATALOG_LOCATION
,  10003 => "N"                            # SQL_CATALOG_NAME
,     41 => '.'                            # SQL_CATALOG_NAME_SEPARATOR
,     42 => ""                             # SQL_CATALOG_TERM
,     92 => 0                              # SQL_CATALOG_USAGE
#
# 10004 => undef                           # SQL_COLLATING_SEQUENCE
,  10004 => "ISO-8859-1"                   # SQL_COLLATION_SEQ
,     87 => "N"                            # SQL_COLUMN_ALIAS
,     22 => 0                              # SQL_CONCAT_NULL_BEHAVIOR
#
# CONVERT FUNCTION NOT CURRENTLY SUPPORTED
#
,     53 => 0                              # SQL_CONVERT_BIGINT
,     54 => 0                              # SQL_CONVERT_BINARY
,     55 => 0                              # SQL_CONVERT_BIT
,     56 => 0                              # SQL_CONVERT_CHAR
,     57 => 0                              # SQL_CONVERT_DATE
,     58 => 0                              # SQL_CONVERT_DECIMAL
,     59 => 0                              # SQL_CONVERT_DOUBLE
,     60 => 0                              # SQL_CONVERT_FLOAT
,     48 => 0                              # SQL_CONVERT_FUNCTIONS
,    173 => 0                              # SQL_CONVERT_GUID
,     61 => 0                              # SQL_CONVERT_INTEGER
,    123 => 0                              # SQL_CONVERT_INTERVAL_DAY_TIME
,    124 => 0                              # SQL_CONVERT_INTERVAL_YEAR_MONTH
,     71 => 0                              # SQL_CONVERT_LONGVARBINARY
,     62 => 0                              # SQL_CONVERT_LONGVARCHAR
,     63 => 0                              # SQL_CONVERT_NUMERIC
,     64 => 0                              # SQL_CONVERT_REAL
,     65 => 0                              # SQL_CONVERT_SMALLINT
,     66 => 0                              # SQL_CONVERT_TIME
,     67 => 0                              # SQL_CONVERT_TIMESTAMP
,     68 => 0                              # SQL_CONVERT_TINYINT
,     69 => 0                              # SQL_CONVERT_VARBINARY
,     70 => 0                              # SQL_CONVERT_VARCHAR
,    122 => 0                              # SQL_CONVERT_WCHAR
,    125 => 0                              # SQL_CONVERT_WLONGVARCHAR
,    126 => 0                              # SQL_CONVERT_WVARCHAR
#
,     74 => 2                              # SQL_CORRELATION_NAME
,    127 => 0                              # SQL_CREATE_ASSERTION
,    128 => 0                              # SQL_CREATE_CHARACTER_SET
,    129 => 0                              # SQL_CREATE_COLLATION
,    130 => 0                              # SQL_CREATE_DOMAIN
,    131 => 0                              # SQL_CREATE_SCHEMA
,    132 => 1                              # SQL_CREATE_TABLE
,    133 => 0                              # SQL_CREATE_TRANSLATION
,    134 => 0                              # SQL_CREATE_VIEW
#
# CURSORS NOT CURRENTLY SUPPORTED
#
#     23 => undef,                         # SQL_CURSOR_COMMIT_BEHAVIOR
#     24 => undef,                         # SQL_CURSOR_ROLLBACK_BEHAVIOR
#  10001 => undef,                         # SQL_CURSOR_SENSITIVITY
#
#,      2 => \&sql_data_source_name         # SQL_DATA_SOURCE_NAME
,     25 => "N"                            # SQL_DATA_SOURCE_READ_ONLY
,    119 => 0                              # SQL_DATETIME_LITERALS
#,     17 => \&sql_driver_name              # SQL_DBMS_NAME
#,     18 => \&sql_driver_ver               # SQL_DBMS_VER
#    18 => undef                           # SQL_DBMS_VERSION
#   170 => undef,                          # SQL_DDL_INDEX
#    26 => undef,                          # SQL_DEFAULT_TRANSACTION_ISOLATION
#    26 => undef                           # SQL_DEFAULT_TXN_ISOLATION
,  10002 => "N"                            # SQL_DESCRIBE_PARAMETER
#   171 => undef                           # SQL_DM_VER
#     3 => undef                           # SQL_DRIVER_HDBC
#   135 => undef                           # SQL_DRIVER_HDESC
#     4 => undef                           # SQL_DRIVER_HENV
#    76 => undef                           # SQL_DRIVER_HLIB
#     5 => undef                           # SQL_DRIVER_HSTMT
#,      6 => \&sql_driver_name              # SQL_DRIVER_NAME
#    77 => undef                           # SQL_DRIVER_ODBC_VER
#,      7 => \&sql_driver_ver               # SQL_DRIVER_VER
,    136 => 0                              # SQL_DROP_ASSERTION
,    137 => 0                              # SQL_DROP_CHARACTER_SET
,    138 => 0                              # SQL_DROP_COLLATION
,    139 => 0                              # SQL_DROP_DOMAIN
,    140 => 0                              # SQL_DROP_SCHEMA
,    141 => 1                              # SQL_DROP_TABLE
,    142 => 0                              # SQL_DROP_TRANSLATION
,    143 => 0                              # SQL_DROP_VIEW
#   144 => undef                           # SQL_DYNAMIC_CURSOR_ATTRIBUTES1
#   145 => undef                           # SQL_DYNAMIC_CURSOR_ATTRIBUTES2
#    27 => undef                           # SQL_EXPRESSIONS_IN_ORDERBY
#     8 => undef                           # SQL_FETCH_DIRECTION
,     84 => 1                              # SQL_FILE_USAGE
#   146 => undef                           # SQL_FORWARD_ONLY_CURSOR_ATTRIBUTES1
#   147 => undef                           # SQL_FORWARD_ONLY_CURSOR_ATTRIBUTES2
#    81 => undef                           # SQL_GETDATA_EXTENSIONS
#    88 => undef                           # SQL_GROUP_BY
,     28 => 4                              # SQL_IDENTIFIER_CASE
,     29 => q(")                           # SQL_IDENTIFIER_QUOTE_CHAR
#   148 => undef                           # SQL_INDEX_KEYWORDS
#   149 => undef                           # SQL_INFO_SCHEMA_VIEWS
,    172 => 1                              # SQL_INSERT_STATEMENT
#    73 => undef                           # SQL_INTEGRITY
#   150 => undef                           # SQL_KEYSET_CURSOR_ATTRIBUTES1
#   151 => undef                           # SQL_KEYSET_CURSOR_ATTRIBUTES2
,     89 => \&sql_keywords                 # SQL_KEYWORDS
,    113 => "N"                            # SQL_LIKE_ESCAPE_CLAUSE
#    78 => undef                           # SQL_LOCK_TYPES
#    34 => undef                           # SQL_MAXIMUM_CATALOG_NAME_LENGTH
#    97 => undef                           # SQL_MAXIMUM_COLUMNS_IN_GROUP_BY
#    98 => undef                           # SQL_MAXIMUM_COLUMNS_IN_INDEX
#    99 => undef                           # SQL_MAXIMUM_COLUMNS_IN_ORDER_BY
#   100 => undef                           # SQL_MAXIMUM_COLUMNS_IN_SELECT
#   101 => undef                           # SQL_MAXIMUM_COLUMNS_IN_TABLE
#    30 => undef                           # SQL_MAXIMUM_COLUMN_NAME_LENGTH
#     1 => undef                           # SQL_MAXIMUM_CONCURRENT_ACTIVITIES
#    31 => undef                           # SQL_MAXIMUM_CURSOR_NAME_LENGTH
#     0 => undef                           # SQL_MAXIMUM_DRIVER_CONNECTIONS
# 10005 => undef                           # SQL_MAXIMUM_IDENTIFIER_LENGTH
#   102 => undef                           # SQL_MAXIMUM_INDEX_SIZE
#   104 => undef                           # SQL_MAXIMUM_ROW_SIZE
#    32 => undef                           # SQL_MAXIMUM_SCHEMA_NAME_LENGTH
#   105 => undef                           # SQL_MAXIMUM_STATEMENT_LENGTH
# 20000 => undef                           # SQL_MAXIMUM_STMT_OCTETS
# 20001 => undef                           # SQL_MAXIMUM_STMT_OCTETS_DATA
# 20002 => undef                           # SQL_MAXIMUM_STMT_OCTETS_SCHEMA
#   106 => undef                           # SQL_MAXIMUM_TABLES_IN_SELECT
#    35 => undef                           # SQL_MAXIMUM_TABLE_NAME_LENGTH
#   107 => undef                           # SQL_MAXIMUM_USER_NAME_LENGTH
# 10022 => undef                           # SQL_MAX_ASYNC_CONCURRENT_STATEMENTS
#   112 => undef                           # SQL_MAX_BINARY_LITERAL_LEN
#    34 => undef                           # SQL_MAX_CATALOG_NAME_LEN
#   108 => undef                           # SQL_MAX_CHAR_LITERAL_LEN
#    97 => undef                           # SQL_MAX_COLUMNS_IN_GROUP_BY
#    98 => undef                           # SQL_MAX_COLUMNS_IN_INDEX
#    99 => undef                           # SQL_MAX_COLUMNS_IN_ORDER_BY
#   100 => undef                           # SQL_MAX_COLUMNS_IN_SELECT
#   101 => undef                           # SQL_MAX_COLUMNS_IN_TABLE
#    30 => undef                           # SQL_MAX_COLUMN_NAME_LEN
#     1 => undef                           # SQL_MAX_CONCURRENT_ACTIVITIES
#    31 => undef                           # SQL_MAX_CURSOR_NAME_LEN
#     0 => undef                           # SQL_MAX_DRIVER_CONNECTIONS
# 10005 => undef                           # SQL_MAX_IDENTIFIER_LEN
#   102 => undef                           # SQL_MAX_INDEX_SIZE
#    32 => undef                           # SQL_MAX_OWNER_NAME_LEN
#    33 => undef                           # SQL_MAX_PROCEDURE_NAME_LEN
#    34 => undef                           # SQL_MAX_QUALIFIER_NAME_LEN
#   104 => undef                           # SQL_MAX_ROW_SIZE
#   103 => undef                           # SQL_MAX_ROW_SIZE_INCLUDES_LONG
#    32 => undef                           # SQL_MAX_SCHEMA_NAME_LEN
#   105 => undef                           # SQL_MAX_STATEMENT_LEN
#   106 => undef                           # SQL_MAX_TABLES_IN_SELECT
#    35 => undef                           # SQL_MAX_TABLE_NAME_LEN
#   107 => undef                           # SQL_MAX_USER_NAME_LEN
#    37 => undef                           # SQL_MULTIPLE_ACTIVE_TXN
#    36 => undef                           # SQL_MULT_RESULT_SETS
,   111 => "N"                             # SQL_NEED_LONG_DATA_LEN
,    75 => 1                               # SQL_NON_NULLABLE_COLUMNS
,     85 => 1                              # SQL_NULL_COLLATION
,     49 => 0                              # SQL_NUMERIC_FUNCTIONS
#     9 => undef                           # SQL_ODBC_API_CONFORMANCE
#   152 => undef                           # SQL_ODBC_INTERFACE_CONFORMANCE
#    12 => undef                           # SQL_ODBC_SAG_CLI_CONFORMANCE
#    15 => undef                           # SQL_ODBC_SQL_CONFORMANCE
#    73 => undef                           # SQL_ODBC_SQL_OPT_IEF
#    10 => undef                           # SQL_ODBC_VER
,    115 => 0x00000037                     # SQL_OJ_CAPABILITIES
#           1   SQL_OJ_LEFT                +  left joins SUPPORTED
#           2   SQL_OJ_RIGHT               +  right joins SUPPORTED
#           4   SQL_OJ_FULL                +  full joins SUPPORTED
#               SQL_OJ_NESTED              -  nested joins not supported
#          10   SQL_OJ_NOT_ORDERED         +  on clause col order not required
#          20   SQL_OJ_INNER               +  inner joins SUPPORTED
#               SQL_OJ_ALL_COMPARISON_OPS  -  on clause comp op must be =
,     90 => "N"                            # SQL_ORDER_BY_COLUMNS_IN_SELECT
#    38 => undef                           # SQL_OUTER_JOINS
#   115 => undef                           # SQL_OUTER_JOIN_CAPABILITIES
#    39 => undef                           # SQL_OWNER_TERM
#    91 => undef                           # SQL_OWNER_USAGE
#   153 => undef                           # SQL_PARAM_ARRAY_ROW_COUNTS
#   154 => undef                           # SQL_PARAM_ARRAY_SELECTS
#    80 => undef                           # SQL_POSITIONED_STATEMENTS
#    79 => undef                           # SQL_POS_OPERATIONS
,     21 => "N"                            # SQL_PROCEDURES
#    40 => undef                           # SQL_PROCEDURE_TERM
#   114 => undef                           # SQL_QUALIFIER_LOCATION
#    41 => undef                           # SQL_QUALIFIER_NAME_SEPARATOR
#    42 => undef                           # SQL_QUALIFIER_TERM
#    92 => undef                           # SQL_QUALIFIER_USAGE
,     93 => 3                              # SQL_QUOTED_IDENTIFIER_CASE
,     11 => "N"                            # SQL_ROW_UPDATES
,     39 => "schema"                        # SQL_SCHEMA_TERM
#    91 => undef                           # SQL_SCHEMA_USAGE
#    43 => undef                           # SQL_SCROLL_CONCURRENCY
#    44 => undef                           # SQL_SCROLL_OPTIONS
#    14 => undef                           # SQL_SEARCH_PATTERN_ESCAPE
#    13 => undef                           # SQL_SERVER_NAME
#    94 => undef                           # SQL_SPECIAL_CHARACTERS
#   155 => undef                           # SQL_SQL92_DATETIME_FUNCTIONS
#   156 => undef                           # SQL_SQL92_FOREIGN_KEY_DELETE_RULE
#   157 => undef                           # SQL_SQL92_FOREIGN_KEY_UPDATE_RULE
#   158 => undef                           # SQL_SQL92_GRANT
#   159 => undef                           # SQL_SQL92_NUMERIC_VALUE_FUNCTIONS
,    160 => 0x00003E06                     # SQL_SQL92_PREDICATES
#                               SQL_SP_EXISTS                    -      -
#                               SQL_SP_ISNOTNULL                 +      +   2
#                               SQL_SP_ISNULL                    +      +   4
#                               SQL_SP_MATCH_FULL                -      -
#                               SQL_SP_MATCH_PARTIAL             -      -
#                               SQL_SP_MATCH_UNIQUE_FULL         -      -
#                               SQL_SP_MATCH_UNIQUE_PARTIAL      -      -
#                               SQL_SP_OVERLAPS                  -      -
#                               SQL_SP_UNIQUE                    -      -
#                               SQL_SP_LIKE                      +      +  200
#                               SQL_SP_IN                        -      +  400
#                               SQL_SP_BETWEEN                   -      +  800
#                               SQL_SP_COMPARISON                +      + 1000
#                               SQL_SP_QUANTIFIED_COMPARISON     +      + 2000
,    161 => 0x000001D8                     # SQL_SQL92_RELATIONAL_JOIN_OPERATORS
#         SQL_SRJO_CORRESPONDING_CLAUSE  -   corresponding clause not supported
#         SQL_SRJO_CROSS_JOIN            -   cross join not supported
#         SQL_SRJO_EXCEPT_JOIN           -   except join not supported
#     8   SQL_SRJO_FULL_OUTER_JOIN       +   full join SUPPORTED
#    10   SQL_SRJO_INNER_JOIN            +   inner join SUPPORTED
#         SQL_SRJO_INTERSECT_JOIN        -   intersect join not supported
#    40   SQL_SRJO_LEFT_OUTER_JOIN       +   left join SUPPORTED
#    80   SQL_SRJO_NATURAL_JOIN          +   natural join SUPPORTED
#   100   SQL_SRJO_RIGHT_OUTER_JOIN      +   right join SUPPORTED
#         SQL_SRJO_UNION_JOIN            -   union join not supported
#   162 => undef                           # SQL_SQL92_REVOKE
,    163 => 3                              # SQL_SQL92_ROW_VALUE_CONSTRUCTOR
#                                                    SQL_SRVC_VALUE_EXPRESSION
#                                                    SQL_SRVC_NULL 
#                                                    SQL_SRVC_DEFAULT 
#                                                    SQL_SRVC_ROW_SUBQUERY
,   164 => 0x000000EE                      # SQL_SQL92_STRING_FUNCTIONS
#  SQL_SSF_CONVERT         -    /* convert() string function not supported */
#  SQL_SSF_LOWER        2  +    /* lower() string function SUPPORTED */
#  SQL_SSF_UPPER        4  +    /* upper() string function SUPPORTED */
#  SQL_SSF_SUBSTRING    8  +    /* substring() string function SUPPORTED */
#  SQL_SSF_TRANSLATE       -    /* translate() string function not supported */
#  SQL_SSF_TRIM_BOTH   32  +    /* trim() both string function SUPPORTED */
#  SQL_SSF_TRIM_LEADING 64 +    /* trim() leading string function SUPPORTED */
#  SQL_SSF_TRIM_TRAILING128+    /* trim() trailing string function SUPPORTED */
#   165 => undef                           # SQL_SQL92_VALUE_EXPRESSIONS
#   118 => undef                           # SQL_SQL_CONFORMANCE
#   166 => undef                           # SQL_STANDARD_CLI_CONFORMANCE
#   167 => undef                           # SQL_STATIC_CURSOR_ATTRIBUTES1
#   168 => undef                           # SQL_STATIC_CURSOR_ATTRIBUTES2
#    83 => undef                           # SQL_STATIC_SENSITIVITY
,    50 => 0x00001C49                      # SQL_STRING_FUNCTIONS
#      SQL_FN_STR_CONCAT                         => 0x00000001 +
#      SQL_FN_STR_INSERT                         => 0x00000002
#      SQL_FN_STR_LEFT                           => 0x00000004
#      SQL_FN_STR_LTRIM                          => 0x00000008 +
#      SQL_FN_STR_LENGTH                         => 0x00000010
#      SQL_FN_STR_LOCATE                         => 0x00000020
#      SQL_FN_STR_LCASE                          => 0x00000040 +
#      SQL_FN_STR_REPEAT                         => 0x00000080
#      SQL_FN_STR_REPLACE                        => 0x00000100
#      SQL_FN_STR_RIGHT                          => 0x00000200
#      SQL_FN_STR_RTRIM                          => 0x00000400 +
#      SQL_FN_STR_SUBSTRING                      => 0x00000800 +
#      SQL_FN_STR_UCASE                          => 0x00001000 +
#      SQL_FN_STR_ASCII                          => 0x00002000
#      SQL_FN_STR_CHAR                           => 0x00004000
#      SQL_FN_STR_DIFFERENCE                     => 0x00008000
#      SQL_FN_STR_LOCATE_2                       => 0x00010000
#      SQL_FN_STR_SOUNDEX                        => 0x00020000
#      SQL_FN_STR_SPACE                          => 0x00040000
#      SQL_FN_STR_BIT_LENGTH                     => 0x00080000
#      SQL_FN_STR_CHAR_LENGTH                    => 0x00100000
#      SQL_FN_STR_CHARACTER_LENGTH               => 0x00200000
#      SQL_FN_STR_OCTET_LENGTH                   => 0x00400000
#      SQL_FN_STR_POSITION                       => 0x00800000
#    95 => undef                           # SQL_SUBQUERIES
#    51 => undef                           # SQL_SYSTEM_FUNCTIONS
,     45 => "table"                        # SQL_TABLE_TERM
#   109 => undef                           # SQL_TIMEDATE_ADD_INTERVALS
#   110 => undef                           # SQL_TIMEDATE_DIFF_INTERVALS
#    52 => undef                           # SQL_TIMEDATE_FUNCTIONS
#    46 => undef                           # SQL_TRANSACTION_CAPABLE
#    72 => undef                           # SQL_TRANSACTION_ISOLATION_OPTION
#    46 => undef                           # SQL_TXN_CAPABLE
#    72 => undef                           # SQL_TXN_ISOLATION_OPTION
#    96 => undef                           # SQL_UNION
#    96 => undef                           # SQL_UNION_STATEMENT
#,    47 => \&sql_user_name                 # SQL_USER_NAME
# 10000 => undef                           # SQL_XOPEN_CLI_YEAR
);


1;

__END__

NO LONGER NEEDED

sub sql_driver_name {
    shift->{"Driver"}->{"Name"};
}

sub sql_driver_ver {
    my $dbh = shift;
    my $ver = shift;
    my $drv = 'DBD::'.$dbh->{"Driver"}->{"Name"};
#    $ver = "$drv"."::VERSION";
#    $ver = ${$ver};
    my $fmt = '%02d.%02d.%1d%1d%1d%1d';   # ODBC version string: ##.##.#####
    $ver = sprintf $fmt, split (/\./, $ver);
    return $ver . '; ss-'. $SQL::Statement::VERSION;
}

sub sql_data_source_name {
    my $dbh = shift;
    return 'dbi:'.$dbh->{"Driver"}->{"Name"}.':'.$dbh->{"Name"};
}
sub sql_user_name {
    my $dbh = shift;
    return $dbh->{"CURRENT_USER"};
}


