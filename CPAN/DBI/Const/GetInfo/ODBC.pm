# $Id: ODBC.pm 8696 2007-01-24 23:12:38Z timbo $
#
# Copyright (c) 2002  Tim Bunce  Ireland
#
# Constant data describing Microsoft ODBC info types and return values
# for the SQLGetInfo() method of ODBC.
#
# You may distribute under the terms of either the GNU General Public
# License or the Artistic License, as specified in the Perl README file.

package DBI::Const::GetInfo::ODBC;

=head1 NAME

DBI::Const::GetInfo::ODBC - ODBC Constants for GetInfo

=head1 SYNOPSIS

 The API for this module is private and subject to change.

=head1 DESCRIPTION

Information requested by GetInfo().

The API for this module is private and subject to change.   

=head1 REFERENCES

  MDAC SDK 2.6
  ODBC version number (0x0351)

  sql.h
  sqlext.h

=cut

my
$VERSION = sprintf("2.%06d", q$Revision: 8696 $ =~ /(\d+)/o);


%InfoTypes =
(
  SQL_ACCESSIBLE_PROCEDURES           =>    20
, SQL_ACCESSIBLE_TABLES               =>    19
, SQL_ACTIVE_CONNECTIONS              =>     0
, SQL_ACTIVE_ENVIRONMENTS             =>   116
, SQL_ACTIVE_STATEMENTS               =>     1
, SQL_AGGREGATE_FUNCTIONS             =>   169
, SQL_ALTER_DOMAIN                    =>   117
, SQL_ALTER_TABLE                     =>    86
, SQL_ASYNC_MODE                      => 10021
, SQL_BATCH_ROW_COUNT                 =>   120
, SQL_BATCH_SUPPORT                   =>   121
, SQL_BOOKMARK_PERSISTENCE            =>    82
, SQL_CATALOG_LOCATION                =>   114  # SQL_QUALIFIER_LOCATION
, SQL_CATALOG_NAME                    => 10003
, SQL_CATALOG_NAME_SEPARATOR          =>    41  # SQL_QUALIFIER_NAME_SEPARATOR
, SQL_CATALOG_TERM                    =>    42  # SQL_QUALIFIER_TERM
, SQL_CATALOG_USAGE                   =>    92  # SQL_QUALIFIER_USAGE
, SQL_COLLATION_SEQ                   => 10004
, SQL_COLUMN_ALIAS                    =>    87
, SQL_CONCAT_NULL_BEHAVIOR            =>    22
, SQL_CONVERT_BIGINT                  =>    53
, SQL_CONVERT_BINARY                  =>    54
, SQL_CONVERT_BIT                     =>    55
, SQL_CONVERT_CHAR                    =>    56
, SQL_CONVERT_DATE                    =>    57
, SQL_CONVERT_DECIMAL                 =>    58
, SQL_CONVERT_DOUBLE                  =>    59
, SQL_CONVERT_FLOAT                   =>    60
, SQL_CONVERT_FUNCTIONS               =>    48
, SQL_CONVERT_GUID                    =>   173
, SQL_CONVERT_INTEGER                 =>    61
, SQL_CONVERT_INTERVAL_DAY_TIME       =>   123
, SQL_CONVERT_INTERVAL_YEAR_MONTH     =>   124
, SQL_CONVERT_LONGVARBINARY           =>    71
, SQL_CONVERT_LONGVARCHAR             =>    62
, SQL_CONVERT_NUMERIC                 =>    63
, SQL_CONVERT_REAL                    =>    64
, SQL_CONVERT_SMALLINT                =>    65
, SQL_CONVERT_TIME                    =>    66
, SQL_CONVERT_TIMESTAMP               =>    67
, SQL_CONVERT_TINYINT                 =>    68
, SQL_CONVERT_VARBINARY               =>    69
, SQL_CONVERT_VARCHAR                 =>    70
, SQL_CONVERT_WCHAR                   =>   122
, SQL_CONVERT_WLONGVARCHAR            =>   125
, SQL_CONVERT_WVARCHAR                =>   126
, SQL_CORRELATION_NAME                =>    74
, SQL_CREATE_ASSERTION                =>   127
, SQL_CREATE_CHARACTER_SET            =>   128
, SQL_CREATE_COLLATION                =>   129
, SQL_CREATE_DOMAIN                   =>   130
, SQL_CREATE_SCHEMA                   =>   131
, SQL_CREATE_TABLE                    =>   132
, SQL_CREATE_TRANSLATION              =>   133
, SQL_CREATE_VIEW                     =>   134
, SQL_CURSOR_COMMIT_BEHAVIOR          =>    23
, SQL_CURSOR_ROLLBACK_BEHAVIOR        =>    24
, SQL_CURSOR_SENSITIVITY              => 10001
, SQL_DATA_SOURCE_NAME                =>     2
, SQL_DATA_SOURCE_READ_ONLY           =>    25
, SQL_DATABASE_NAME                   =>    16 
, SQL_DATETIME_LITERALS               =>   119
, SQL_DBMS_NAME                       =>    17
, SQL_DBMS_VER                        =>    18
, SQL_DDL_INDEX                       =>   170
, SQL_DEFAULT_TXN_ISOLATION           =>    26
, SQL_DESCRIBE_PARAMETER              => 10002
, SQL_DM_VER                          =>   171
, SQL_DRIVER_HDBC                     =>     3
, SQL_DRIVER_HDESC                    =>   135
, SQL_DRIVER_HENV                     =>     4
, SQL_DRIVER_HLIB                     =>    76
, SQL_DRIVER_HSTMT                    =>     5
, SQL_DRIVER_NAME                     =>     6
, SQL_DRIVER_ODBC_VER                 =>    77
, SQL_DRIVER_VER                      =>     7
, SQL_DROP_ASSERTION                  =>   136
, SQL_DROP_CHARACTER_SET              =>   137
, SQL_DROP_COLLATION                  =>   138
, SQL_DROP_DOMAIN                     =>   139
, SQL_DROP_SCHEMA                     =>   140
, SQL_DROP_TABLE                      =>   141
, SQL_DROP_TRANSLATION                =>   142
, SQL_DROP_VIEW                       =>   143
, SQL_DYNAMIC_CURSOR_ATTRIBUTES1      =>   144
, SQL_DYNAMIC_CURSOR_ATTRIBUTES2      =>   145
, SQL_EXPRESSIONS_IN_ORDERBY          =>    27
, SQL_FETCH_DIRECTION                 =>     8
, SQL_FILE_USAGE                      =>    84
, SQL_FORWARD_ONLY_CURSOR_ATTRIBUTES1 =>   146
, SQL_FORWARD_ONLY_CURSOR_ATTRIBUTES2 =>   147
, SQL_GETDATA_EXTENSIONS              =>    81
, SQL_GROUP_BY                        =>    88
, SQL_IDENTIFIER_CASE                 =>    28
, SQL_IDENTIFIER_QUOTE_CHAR           =>    29
, SQL_INDEX_KEYWORDS                  =>   148
# SQL_INFO_DRIVER_START               =>  1000
# SQL_INFO_FIRST                      =>     0
# SQL_INFO_LAST                       =>   114  # SQL_QUALIFIER_LOCATION
, SQL_INFO_SCHEMA_VIEWS               =>   149
, SQL_INSERT_STATEMENT                =>   172
, SQL_INTEGRITY                       =>    73
, SQL_KEYSET_CURSOR_ATTRIBUTES1       =>   150
, SQL_KEYSET_CURSOR_ATTRIBUTES2       =>   151
, SQL_KEYWORDS                        =>    89
, SQL_LIKE_ESCAPE_CLAUSE              =>   113
, SQL_LOCK_TYPES                      =>    78
, SQL_MAXIMUM_CATALOG_NAME_LENGTH     =>    34  # SQL_MAX_CATALOG_NAME_LEN
, SQL_MAXIMUM_COLUMNS_IN_GROUP_BY     =>    97  # SQL_MAX_COLUMNS_IN_GROUP_BY
, SQL_MAXIMUM_COLUMNS_IN_INDEX        =>    98  # SQL_MAX_COLUMNS_IN_INDEX
, SQL_MAXIMUM_COLUMNS_IN_ORDER_BY     =>    99  # SQL_MAX_COLUMNS_IN_ORDER_BY
, SQL_MAXIMUM_COLUMNS_IN_SELECT       =>   100  # SQL_MAX_COLUMNS_IN_SELECT
, SQL_MAXIMUM_COLUMN_NAME_LENGTH      =>    30  # SQL_MAX_COLUMN_NAME_LEN
, SQL_MAXIMUM_CONCURRENT_ACTIVITIES   =>     1  # SQL_MAX_CONCURRENT_ACTIVITIES
, SQL_MAXIMUM_CURSOR_NAME_LENGTH      =>    31  # SQL_MAX_CURSOR_NAME_LEN
, SQL_MAXIMUM_DRIVER_CONNECTIONS      =>     0  # SQL_MAX_DRIVER_CONNECTIONS
, SQL_MAXIMUM_IDENTIFIER_LENGTH       => 10005  # SQL_MAX_IDENTIFIER_LEN
, SQL_MAXIMUM_INDEX_SIZE              =>   102  # SQL_MAX_INDEX_SIZE
, SQL_MAXIMUM_ROW_SIZE                =>   104  # SQL_MAX_ROW_SIZE
, SQL_MAXIMUM_SCHEMA_NAME_LENGTH      =>    32  # SQL_MAX_SCHEMA_NAME_LEN
, SQL_MAXIMUM_STATEMENT_LENGTH        =>   105  # SQL_MAX_STATEMENT_LEN
, SQL_MAXIMUM_TABLES_IN_SELECT        =>   106  # SQL_MAX_TABLES_IN_SELECT
, SQL_MAXIMUM_USER_NAME_LENGTH        =>   107  # SQL_MAX_USER_NAME_LEN
, SQL_MAX_ASYNC_CONCURRENT_STATEMENTS => 10022
, SQL_MAX_BINARY_LITERAL_LEN          =>   112
, SQL_MAX_CATALOG_NAME_LEN            =>    34
, SQL_MAX_CHAR_LITERAL_LEN            =>   108
, SQL_MAX_COLUMNS_IN_GROUP_BY         =>    97
, SQL_MAX_COLUMNS_IN_INDEX            =>    98
, SQL_MAX_COLUMNS_IN_ORDER_BY         =>    99
, SQL_MAX_COLUMNS_IN_SELECT           =>   100
, SQL_MAX_COLUMNS_IN_TABLE            =>   101
, SQL_MAX_COLUMN_NAME_LEN             =>    30
, SQL_MAX_CONCURRENT_ACTIVITIES       =>     1
, SQL_MAX_CURSOR_NAME_LEN             =>    31
, SQL_MAX_DRIVER_CONNECTIONS          =>     0
, SQL_MAX_IDENTIFIER_LEN              => 10005
, SQL_MAX_INDEX_SIZE                  =>   102
, SQL_MAX_OWNER_NAME_LEN              =>    32
, SQL_MAX_PROCEDURE_NAME_LEN          =>    33
, SQL_MAX_QUALIFIER_NAME_LEN          =>    34
, SQL_MAX_ROW_SIZE                    =>   104
, SQL_MAX_ROW_SIZE_INCLUDES_LONG      =>   103
, SQL_MAX_SCHEMA_NAME_LEN             =>    32
, SQL_MAX_STATEMENT_LEN               =>   105
, SQL_MAX_TABLES_IN_SELECT            =>   106
, SQL_MAX_TABLE_NAME_LEN              =>    35
, SQL_MAX_USER_NAME_LEN               =>   107
, SQL_MULTIPLE_ACTIVE_TXN             =>    37
, SQL_MULT_RESULT_SETS                =>    36
, SQL_NEED_LONG_DATA_LEN              =>   111
, SQL_NON_NULLABLE_COLUMNS            =>    75
, SQL_NULL_COLLATION                  =>    85
, SQL_NUMERIC_FUNCTIONS               =>    49
, SQL_ODBC_API_CONFORMANCE            =>     9
, SQL_ODBC_INTERFACE_CONFORMANCE      =>   152
, SQL_ODBC_SAG_CLI_CONFORMANCE        =>    12
, SQL_ODBC_SQL_CONFORMANCE            =>    15
, SQL_ODBC_SQL_OPT_IEF                =>    73
, SQL_ODBC_VER                        =>    10
, SQL_OJ_CAPABILITIES                 =>   115
, SQL_ORDER_BY_COLUMNS_IN_SELECT      =>    90
, SQL_OUTER_JOINS                     =>    38
, SQL_OUTER_JOIN_CAPABILITIES         =>   115  # SQL_OJ_CAPABILITIES
, SQL_OWNER_TERM                      =>    39
, SQL_OWNER_USAGE                     =>    91
, SQL_PARAM_ARRAY_ROW_COUNTS          =>   153
, SQL_PARAM_ARRAY_SELECTS             =>   154
, SQL_POSITIONED_STATEMENTS           =>    80
, SQL_POS_OPERATIONS                  =>    79
, SQL_PROCEDURES                      =>    21
, SQL_PROCEDURE_TERM                  =>    40
, SQL_QUALIFIER_LOCATION              =>   114
, SQL_QUALIFIER_NAME_SEPARATOR        =>    41
, SQL_QUALIFIER_TERM                  =>    42
, SQL_QUALIFIER_USAGE                 =>    92
, SQL_QUOTED_IDENTIFIER_CASE          =>    93
, SQL_ROW_UPDATES                     =>    11
, SQL_SCHEMA_TERM                     =>    39  # SQL_OWNER_TERM
, SQL_SCHEMA_USAGE                    =>    91  # SQL_OWNER_USAGE
, SQL_SCROLL_CONCURRENCY              =>    43
, SQL_SCROLL_OPTIONS                  =>    44
, SQL_SEARCH_PATTERN_ESCAPE           =>    14
, SQL_SERVER_NAME                     =>    13
, SQL_SPECIAL_CHARACTERS              =>    94
, SQL_SQL92_DATETIME_FUNCTIONS        =>   155
, SQL_SQL92_FOREIGN_KEY_DELETE_RULE   =>   156
, SQL_SQL92_FOREIGN_KEY_UPDATE_RULE   =>   157
, SQL_SQL92_GRANT                     =>   158
, SQL_SQL92_NUMERIC_VALUE_FUNCTIONS   =>   159
, SQL_SQL92_PREDICATES                =>   160
, SQL_SQL92_RELATIONAL_JOIN_OPERATORS =>   161
, SQL_SQL92_REVOKE                    =>   162
, SQL_SQL92_ROW_VALUE_CONSTRUCTOR     =>   163
, SQL_SQL92_STRING_FUNCTIONS          =>   164
, SQL_SQL92_VALUE_EXPRESSIONS         =>   165
, SQL_SQL_CONFORMANCE                 =>   118
, SQL_STANDARD_CLI_CONFORMANCE        =>   166
, SQL_STATIC_CURSOR_ATTRIBUTES1       =>   167
, SQL_STATIC_CURSOR_ATTRIBUTES2       =>   168
, SQL_STATIC_SENSITIVITY              =>    83
, SQL_STRING_FUNCTIONS                =>    50
, SQL_SUBQUERIES                      =>    95
, SQL_SYSTEM_FUNCTIONS                =>    51
, SQL_TABLE_TERM                      =>    45
, SQL_TIMEDATE_ADD_INTERVALS          =>   109
, SQL_TIMEDATE_DIFF_INTERVALS         =>   110
, SQL_TIMEDATE_FUNCTIONS              =>    52
, SQL_TRANSACTION_CAPABLE             =>    46  # SQL_TXN_CAPABLE
, SQL_TRANSACTION_ISOLATION_OPTION    =>    72  # SQL_TXN_ISOLATION_OPTION
, SQL_TXN_CAPABLE                     =>    46
, SQL_TXN_ISOLATION_OPTION            =>    72
, SQL_UNION                           =>    96
, SQL_UNION_STATEMENT                 =>    96  # SQL_UNION
, SQL_USER_NAME                       =>    47
, SQL_XOPEN_CLI_YEAR                  => 10000
);

=head2 %ReturnTypes

See: mk:@MSITStore:X:\dm\cli\mdac\sdk26\Docs\odbc.chm::/htm/odbcsqlgetinfo.htm

  =>     : alias
  => !!! : edited

=cut

%ReturnTypes =
(
  SQL_ACCESSIBLE_PROCEDURES           => 'SQLCHAR'             #    20
, SQL_ACCESSIBLE_TABLES               => 'SQLCHAR'             #    19
, SQL_ACTIVE_CONNECTIONS              => 'SQLUSMALLINT'        #     0  =>
, SQL_ACTIVE_ENVIRONMENTS             => 'SQLUSMALLINT'        #   116
, SQL_ACTIVE_STATEMENTS               => 'SQLUSMALLINT'        #     1  =>
, SQL_AGGREGATE_FUNCTIONS             => 'SQLUINTEGER bitmask' #   169
, SQL_ALTER_DOMAIN                    => 'SQLUINTEGER bitmask' #   117
, SQL_ALTER_TABLE                     => 'SQLUINTEGER bitmask' #    86
, SQL_ASYNC_MODE                      => 'SQLUINTEGER'         # 10021
, SQL_BATCH_ROW_COUNT                 => 'SQLUINTEGER bitmask' #   120
, SQL_BATCH_SUPPORT                   => 'SQLUINTEGER bitmask' #   121
, SQL_BOOKMARK_PERSISTENCE            => 'SQLUINTEGER bitmask' #    82
, SQL_CATALOG_LOCATION                => 'SQLUSMALLINT'        #   114
, SQL_CATALOG_NAME                    => 'SQLCHAR'             # 10003
, SQL_CATALOG_NAME_SEPARATOR          => 'SQLCHAR'             #    41
, SQL_CATALOG_TERM                    => 'SQLCHAR'             #    42
, SQL_CATALOG_USAGE                   => 'SQLUINTEGER bitmask' #    92
, SQL_COLLATION_SEQ                   => 'SQLCHAR'             # 10004
, SQL_COLUMN_ALIAS                    => 'SQLCHAR'             #    87
, SQL_CONCAT_NULL_BEHAVIOR            => 'SQLUSMALLINT'        #    22
, SQL_CONVERT_BIGINT                  => 'SQLUINTEGER bitmask' #    53
, SQL_CONVERT_BINARY                  => 'SQLUINTEGER bitmask' #    54
, SQL_CONVERT_BIT                     => 'SQLUINTEGER bitmask' #    55
, SQL_CONVERT_CHAR                    => 'SQLUINTEGER bitmask' #    56
, SQL_CONVERT_DATE                    => 'SQLUINTEGER bitmask' #    57
, SQL_CONVERT_DECIMAL                 => 'SQLUINTEGER bitmask' #    58
, SQL_CONVERT_DOUBLE                  => 'SQLUINTEGER bitmask' #    59
, SQL_CONVERT_FLOAT                   => 'SQLUINTEGER bitmask' #    60
, SQL_CONVERT_FUNCTIONS               => 'SQLUINTEGER bitmask' #    48
, SQL_CONVERT_GUID                    => 'SQLUINTEGER bitmask' #   173
, SQL_CONVERT_INTEGER                 => 'SQLUINTEGER bitmask' #    61
, SQL_CONVERT_INTERVAL_DAY_TIME       => 'SQLUINTEGER bitmask' #   123
, SQL_CONVERT_INTERVAL_YEAR_MONTH     => 'SQLUINTEGER bitmask' #   124
, SQL_CONVERT_LONGVARBINARY           => 'SQLUINTEGER bitmask' #    71
, SQL_CONVERT_LONGVARCHAR             => 'SQLUINTEGER bitmask' #    62
, SQL_CONVERT_NUMERIC                 => 'SQLUINTEGER bitmask' #    63
, SQL_CONVERT_REAL                    => 'SQLUINTEGER bitmask' #    64
, SQL_CONVERT_SMALLINT                => 'SQLUINTEGER bitmask' #    65
, SQL_CONVERT_TIME                    => 'SQLUINTEGER bitmask' #    66
, SQL_CONVERT_TIMESTAMP               => 'SQLUINTEGER bitmask' #    67
, SQL_CONVERT_TINYINT                 => 'SQLUINTEGER bitmask' #    68
, SQL_CONVERT_VARBINARY               => 'SQLUINTEGER bitmask' #    69
, SQL_CONVERT_VARCHAR                 => 'SQLUINTEGER bitmask' #    70
, SQL_CONVERT_WCHAR                   => 'SQLUINTEGER bitmask' #   122  => !!!
, SQL_CONVERT_WLONGVARCHAR            => 'SQLUINTEGER bitmask' #   125  => !!!
, SQL_CONVERT_WVARCHAR                => 'SQLUINTEGER bitmask' #   126  => !!!
, SQL_CORRELATION_NAME                => 'SQLUSMALLINT'        #    74
, SQL_CREATE_ASSERTION                => 'SQLUINTEGER bitmask' #   127
, SQL_CREATE_CHARACTER_SET            => 'SQLUINTEGER bitmask' #   128
, SQL_CREATE_COLLATION                => 'SQLUINTEGER bitmask' #   129
, SQL_CREATE_DOMAIN                   => 'SQLUINTEGER bitmask' #   130
, SQL_CREATE_SCHEMA                   => 'SQLUINTEGER bitmask' #   131
, SQL_CREATE_TABLE                    => 'SQLUINTEGER bitmask' #   132
, SQL_CREATE_TRANSLATION              => 'SQLUINTEGER bitmask' #   133
, SQL_CREATE_VIEW                     => 'SQLUINTEGER bitmask' #   134
, SQL_CURSOR_COMMIT_BEHAVIOR          => 'SQLUSMALLINT'        #    23
, SQL_CURSOR_ROLLBACK_BEHAVIOR        => 'SQLUSMALLINT'        #    24
, SQL_CURSOR_SENSITIVITY              => 'SQLUINTEGER'         # 10001
, SQL_DATA_SOURCE_NAME                => 'SQLCHAR'             #     2
, SQL_DATA_SOURCE_READ_ONLY           => 'SQLCHAR'             #    25
, SQL_DATABASE_NAME                   => 'SQLCHAR'             #    16 
, SQL_DATETIME_LITERALS               => 'SQLUINTEGER bitmask' #   119
, SQL_DBMS_NAME                       => 'SQLCHAR'             #    17
, SQL_DBMS_VER                        => 'SQLCHAR'             #    18
, SQL_DDL_INDEX                       => 'SQLUINTEGER bitmask' #   170
, SQL_DEFAULT_TXN_ISOLATION           => 'SQLUINTEGER'         #    26
, SQL_DESCRIBE_PARAMETER              => 'SQLCHAR'             # 10002
, SQL_DM_VER                          => 'SQLCHAR'             #   171
, SQL_DRIVER_HDBC                     => 'SQLUINTEGER'         #     3
, SQL_DRIVER_HDESC                    => 'SQLUINTEGER'         #   135
, SQL_DRIVER_HENV                     => 'SQLUINTEGER'         #     4
, SQL_DRIVER_HLIB                     => 'SQLUINTEGER'         #    76
, SQL_DRIVER_HSTMT                    => 'SQLUINTEGER'         #     5
, SQL_DRIVER_NAME                     => 'SQLCHAR'             #     6
, SQL_DRIVER_ODBC_VER                 => 'SQLCHAR'             #    77
, SQL_DRIVER_VER                      => 'SQLCHAR'             #     7
, SQL_DROP_ASSERTION                  => 'SQLUINTEGER bitmask' #   136
, SQL_DROP_CHARACTER_SET              => 'SQLUINTEGER bitmask' #   137
, SQL_DROP_COLLATION                  => 'SQLUINTEGER bitmask' #   138
, SQL_DROP_DOMAIN                     => 'SQLUINTEGER bitmask' #   139
, SQL_DROP_SCHEMA                     => 'SQLUINTEGER bitmask' #   140
, SQL_DROP_TABLE                      => 'SQLUINTEGER bitmask' #   141
, SQL_DROP_TRANSLATION                => 'SQLUINTEGER bitmask' #   142
, SQL_DROP_VIEW                       => 'SQLUINTEGER bitmask' #   143
, SQL_DYNAMIC_CURSOR_ATTRIBUTES1      => 'SQLUINTEGER bitmask' #   144
, SQL_DYNAMIC_CURSOR_ATTRIBUTES2      => 'SQLUINTEGER bitmask' #   145
, SQL_EXPRESSIONS_IN_ORDERBY          => 'SQLCHAR'             #    27
, SQL_FETCH_DIRECTION                 => 'SQLUINTEGER bitmask' #     8  => !!!
, SQL_FILE_USAGE                      => 'SQLUSMALLINT'        #    84
, SQL_FORWARD_ONLY_CURSOR_ATTRIBUTES1 => 'SQLUINTEGER bitmask' #   146
, SQL_FORWARD_ONLY_CURSOR_ATTRIBUTES2 => 'SQLUINTEGER bitmask' #   147
, SQL_GETDATA_EXTENSIONS              => 'SQLUINTEGER bitmask' #    81
, SQL_GROUP_BY                        => 'SQLUSMALLINT'        #    88
, SQL_IDENTIFIER_CASE                 => 'SQLUSMALLINT'        #    28
, SQL_IDENTIFIER_QUOTE_CHAR           => 'SQLCHAR'             #    29
, SQL_INDEX_KEYWORDS                  => 'SQLUINTEGER bitmask' #   148
# SQL_INFO_DRIVER_START               => ''                    #  1000  =>
# SQL_INFO_FIRST                      => 'SQLUSMALLINT'        #     0  =>
# SQL_INFO_LAST                       => 'SQLUSMALLINT'        #   114  =>
, SQL_INFO_SCHEMA_VIEWS               => 'SQLUINTEGER bitmask' #   149
, SQL_INSERT_STATEMENT                => 'SQLUINTEGER bitmask' #   172
, SQL_INTEGRITY                       => 'SQLCHAR'             #    73
, SQL_KEYSET_CURSOR_ATTRIBUTES1       => 'SQLUINTEGER bitmask' #   150
, SQL_KEYSET_CURSOR_ATTRIBUTES2       => 'SQLUINTEGER bitmask' #   151
, SQL_KEYWORDS                        => 'SQLCHAR'             #    89
, SQL_LIKE_ESCAPE_CLAUSE              => 'SQLCHAR'             #   113
, SQL_LOCK_TYPES                      => 'SQLUINTEGER bitmask' #    78  => !!!
, SQL_MAXIMUM_CATALOG_NAME_LENGTH     => 'SQLUSMALLINT'        #    34  =>
, SQL_MAXIMUM_COLUMNS_IN_GROUP_BY     => 'SQLUSMALLINT'        #    97  =>
, SQL_MAXIMUM_COLUMNS_IN_INDEX        => 'SQLUSMALLINT'        #    98  =>
, SQL_MAXIMUM_COLUMNS_IN_ORDER_BY     => 'SQLUSMALLINT'        #    99  =>
, SQL_MAXIMUM_COLUMNS_IN_SELECT       => 'SQLUSMALLINT'        #   100  =>
, SQL_MAXIMUM_COLUMN_NAME_LENGTH      => 'SQLUSMALLINT'        #    30  =>
, SQL_MAXIMUM_CONCURRENT_ACTIVITIES   => 'SQLUSMALLINT'        #     1  =>
, SQL_MAXIMUM_CURSOR_NAME_LENGTH      => 'SQLUSMALLINT'        #    31  =>
, SQL_MAXIMUM_DRIVER_CONNECTIONS      => 'SQLUSMALLINT'        #     0  =>
, SQL_MAXIMUM_IDENTIFIER_LENGTH       => 'SQLUSMALLINT'        # 10005  =>
, SQL_MAXIMUM_INDEX_SIZE              => 'SQLUINTEGER'         #   102  =>
, SQL_MAXIMUM_ROW_SIZE                => 'SQLUINTEGER'         #   104  =>
, SQL_MAXIMUM_SCHEMA_NAME_LENGTH      => 'SQLUSMALLINT'        #    32  =>
, SQL_MAXIMUM_STATEMENT_LENGTH        => 'SQLUINTEGER'         #   105  =>
, SQL_MAXIMUM_TABLES_IN_SELECT        => 'SQLUSMALLINT'        #   106  =>
, SQL_MAXIMUM_USER_NAME_LENGTH        => 'SQLUSMALLINT'        #   107  =>
, SQL_MAX_ASYNC_CONCURRENT_STATEMENTS => 'SQLUINTEGER'         # 10022
, SQL_MAX_BINARY_LITERAL_LEN          => 'SQLUINTEGER'         #   112
, SQL_MAX_CATALOG_NAME_LEN            => 'SQLUSMALLINT'        #    34
, SQL_MAX_CHAR_LITERAL_LEN            => 'SQLUINTEGER'         #   108
, SQL_MAX_COLUMNS_IN_GROUP_BY         => 'SQLUSMALLINT'        #    97
, SQL_MAX_COLUMNS_IN_INDEX            => 'SQLUSMALLINT'        #    98
, SQL_MAX_COLUMNS_IN_ORDER_BY         => 'SQLUSMALLINT'        #    99
, SQL_MAX_COLUMNS_IN_SELECT           => 'SQLUSMALLINT'        #   100
, SQL_MAX_COLUMNS_IN_TABLE            => 'SQLUSMALLINT'        #   101
, SQL_MAX_COLUMN_NAME_LEN             => 'SQLUSMALLINT'        #    30
, SQL_MAX_CONCURRENT_ACTIVITIES       => 'SQLUSMALLINT'        #     1
, SQL_MAX_CURSOR_NAME_LEN             => 'SQLUSMALLINT'        #    31
, SQL_MAX_DRIVER_CONNECTIONS          => 'SQLUSMALLINT'        #     0
, SQL_MAX_IDENTIFIER_LEN              => 'SQLUSMALLINT'        # 10005
, SQL_MAX_INDEX_SIZE                  => 'SQLUINTEGER'         #   102
, SQL_MAX_OWNER_NAME_LEN              => 'SQLUSMALLINT'        #    32  =>
, SQL_MAX_PROCEDURE_NAME_LEN          => 'SQLUSMALLINT'        #    33
, SQL_MAX_QUALIFIER_NAME_LEN          => 'SQLUSMALLINT'        #    34  =>
, SQL_MAX_ROW_SIZE                    => 'SQLUINTEGER'         #   104
, SQL_MAX_ROW_SIZE_INCLUDES_LONG      => 'SQLCHAR'             #   103
, SQL_MAX_SCHEMA_NAME_LEN             => 'SQLUSMALLINT'        #    32
, SQL_MAX_STATEMENT_LEN               => 'SQLUINTEGER'         #   105
, SQL_MAX_TABLES_IN_SELECT            => 'SQLUSMALLINT'        #   106
, SQL_MAX_TABLE_NAME_LEN              => 'SQLUSMALLINT'        #    35
, SQL_MAX_USER_NAME_LEN               => 'SQLUSMALLINT'        #   107
, SQL_MULTIPLE_ACTIVE_TXN             => 'SQLCHAR'             #    37
, SQL_MULT_RESULT_SETS                => 'SQLCHAR'             #    36
, SQL_NEED_LONG_DATA_LEN              => 'SQLCHAR'             #   111
, SQL_NON_NULLABLE_COLUMNS            => 'SQLUSMALLINT'        #    75
, SQL_NULL_COLLATION                  => 'SQLUSMALLINT'        #    85
, SQL_NUMERIC_FUNCTIONS               => 'SQLUINTEGER bitmask' #    49
, SQL_ODBC_API_CONFORMANCE            => 'SQLUSMALLINT'        #     9  => !!!
, SQL_ODBC_INTERFACE_CONFORMANCE      => 'SQLUINTEGER'         #   152
, SQL_ODBC_SAG_CLI_CONFORMANCE        => 'SQLUSMALLINT'        #    12  => !!!
, SQL_ODBC_SQL_CONFORMANCE            => 'SQLUSMALLINT'        #    15  => !!!
, SQL_ODBC_SQL_OPT_IEF                => 'SQLCHAR'             #    73  =>
, SQL_ODBC_VER                        => 'SQLCHAR'             #    10
, SQL_OJ_CAPABILITIES                 => 'SQLUINTEGER bitmask' #   115
, SQL_ORDER_BY_COLUMNS_IN_SELECT      => 'SQLCHAR'             #    90
, SQL_OUTER_JOINS                     => 'SQLCHAR'             #    38  => !!!
, SQL_OUTER_JOIN_CAPABILITIES         => 'SQLUINTEGER bitmask' #   115  =>
, SQL_OWNER_TERM                      => 'SQLCHAR'             #    39  =>
, SQL_OWNER_USAGE                     => 'SQLUINTEGER bitmask' #    91  =>
, SQL_PARAM_ARRAY_ROW_COUNTS          => 'SQLUINTEGER'         #   153
, SQL_PARAM_ARRAY_SELECTS             => 'SQLUINTEGER'         #   154
, SQL_POSITIONED_STATEMENTS           => 'SQLUINTEGER bitmask' #    80  => !!!
, SQL_POS_OPERATIONS                  => 'SQLINTEGER bitmask'  #    79
, SQL_PROCEDURES                      => 'SQLCHAR'             #    21
, SQL_PROCEDURE_TERM                  => 'SQLCHAR'             #    40
, SQL_QUALIFIER_LOCATION              => 'SQLUSMALLINT'        #   114  =>
, SQL_QUALIFIER_NAME_SEPARATOR        => 'SQLCHAR'             #    41  =>
, SQL_QUALIFIER_TERM                  => 'SQLCHAR'             #    42  =>
, SQL_QUALIFIER_USAGE                 => 'SQLUINTEGER bitmask' #    92  =>
, SQL_QUOTED_IDENTIFIER_CASE          => 'SQLUSMALLINT'        #    93
, SQL_ROW_UPDATES                     => 'SQLCHAR'             #    11
, SQL_SCHEMA_TERM                     => 'SQLCHAR'             #    39
, SQL_SCHEMA_USAGE                    => 'SQLUINTEGER bitmask' #    91
, SQL_SCROLL_CONCURRENCY              => 'SQLUINTEGER bitmask' #    43  => !!!
, SQL_SCROLL_OPTIONS                  => 'SQLUINTEGER bitmask' #    44
, SQL_SEARCH_PATTERN_ESCAPE           => 'SQLCHAR'             #    14
, SQL_SERVER_NAME                     => 'SQLCHAR'             #    13
, SQL_SPECIAL_CHARACTERS              => 'SQLCHAR'             #    94
, SQL_SQL92_DATETIME_FUNCTIONS        => 'SQLUINTEGER bitmask' #   155
, SQL_SQL92_FOREIGN_KEY_DELETE_RULE   => 'SQLUINTEGER bitmask' #   156
, SQL_SQL92_FOREIGN_KEY_UPDATE_RULE   => 'SQLUINTEGER bitmask' #   157
, SQL_SQL92_GRANT                     => 'SQLUINTEGER bitmask' #   158
, SQL_SQL92_NUMERIC_VALUE_FUNCTIONS   => 'SQLUINTEGER bitmask' #   159
, SQL_SQL92_PREDICATES                => 'SQLUINTEGER bitmask' #   160
, SQL_SQL92_RELATIONAL_JOIN_OPERATORS => 'SQLUINTEGER bitmask' #   161
, SQL_SQL92_REVOKE                    => 'SQLUINTEGER bitmask' #   162
, SQL_SQL92_ROW_VALUE_CONSTRUCTOR     => 'SQLUINTEGER bitmask' #   163
, SQL_SQL92_STRING_FUNCTIONS          => 'SQLUINTEGER bitmask' #   164
, SQL_SQL92_VALUE_EXPRESSIONS         => 'SQLUINTEGER bitmask' #   165
, SQL_SQL_CONFORMANCE                 => 'SQLUINTEGER'         #   118
, SQL_STANDARD_CLI_CONFORMANCE        => 'SQLUINTEGER bitmask' #   166
, SQL_STATIC_CURSOR_ATTRIBUTES1       => 'SQLUINTEGER bitmask' #   167
, SQL_STATIC_CURSOR_ATTRIBUTES2       => 'SQLUINTEGER bitmask' #   168
, SQL_STATIC_SENSITIVITY              => 'SQLUINTEGER bitmask' #    83  => !!!
, SQL_STRING_FUNCTIONS                => 'SQLUINTEGER bitmask' #    50
, SQL_SUBQUERIES                      => 'SQLUINTEGER bitmask' #    95
, SQL_SYSTEM_FUNCTIONS                => 'SQLUINTEGER bitmask' #    51
, SQL_TABLE_TERM                      => 'SQLCHAR'             #    45
, SQL_TIMEDATE_ADD_INTERVALS          => 'SQLUINTEGER bitmask' #   109
, SQL_TIMEDATE_DIFF_INTERVALS         => 'SQLUINTEGER bitmask' #   110
, SQL_TIMEDATE_FUNCTIONS              => 'SQLUINTEGER bitmask' #    52
, SQL_TRANSACTION_CAPABLE             => 'SQLUSMALLINT'        #    46  =>
, SQL_TRANSACTION_ISOLATION_OPTION    => 'SQLUINTEGER bitmask' #    72  =>
, SQL_TXN_CAPABLE                     => 'SQLUSMALLINT'        #    46
, SQL_TXN_ISOLATION_OPTION            => 'SQLUINTEGER bitmask' #    72
, SQL_UNION                           => 'SQLUINTEGER bitmask' #    96
, SQL_UNION_STATEMENT                 => 'SQLUINTEGER bitmask' #    96  =>
, SQL_USER_NAME                       => 'SQLCHAR'             #    47
, SQL_XOPEN_CLI_YEAR                  => 'SQLCHAR'             # 10000
);

=head2 %ReturnValues

See: sql.h, sqlext.h
Edited:
  SQL_TXN_ISOLATION_OPTION

=cut

$ReturnValues{SQL_AGGREGATE_FUNCTIONS} =
{
  SQL_AF_AVG                                => 0x00000001
, SQL_AF_COUNT                              => 0x00000002
, SQL_AF_MAX                                => 0x00000004
, SQL_AF_MIN                                => 0x00000008
, SQL_AF_SUM                                => 0x00000010
, SQL_AF_DISTINCT                           => 0x00000020
, SQL_AF_ALL                                => 0x00000040
};
$ReturnValues{SQL_ALTER_DOMAIN} =
{
  SQL_AD_CONSTRAINT_NAME_DEFINITION         => 0x00000001
, SQL_AD_ADD_DOMAIN_CONSTRAINT              => 0x00000002
, SQL_AD_DROP_DOMAIN_CONSTRAINT             => 0x00000004
, SQL_AD_ADD_DOMAIN_DEFAULT                 => 0x00000008
, SQL_AD_DROP_DOMAIN_DEFAULT                => 0x00000010
, SQL_AD_ADD_CONSTRAINT_INITIALLY_DEFERRED  => 0x00000020
, SQL_AD_ADD_CONSTRAINT_INITIALLY_IMMEDIATE => 0x00000040
, SQL_AD_ADD_CONSTRAINT_DEFERRABLE          => 0x00000080
, SQL_AD_ADD_CONSTRAINT_NON_DEFERRABLE      => 0x00000100
};
$ReturnValues{SQL_ALTER_TABLE} =
{
  SQL_AT_ADD_COLUMN                         => 0x00000001
, SQL_AT_DROP_COLUMN                        => 0x00000002
, SQL_AT_ADD_CONSTRAINT                     => 0x00000008
, SQL_AT_ADD_COLUMN_SINGLE                  => 0x00000020
, SQL_AT_ADD_COLUMN_DEFAULT                 => 0x00000040
, SQL_AT_ADD_COLUMN_COLLATION               => 0x00000080
, SQL_AT_SET_COLUMN_DEFAULT                 => 0x00000100
, SQL_AT_DROP_COLUMN_DEFAULT                => 0x00000200
, SQL_AT_DROP_COLUMN_CASCADE                => 0x00000400
, SQL_AT_DROP_COLUMN_RESTRICT               => 0x00000800
, SQL_AT_ADD_TABLE_CONSTRAINT               => 0x00001000
, SQL_AT_DROP_TABLE_CONSTRAINT_CASCADE      => 0x00002000
, SQL_AT_DROP_TABLE_CONSTRAINT_RESTRICT     => 0x00004000
, SQL_AT_CONSTRAINT_NAME_DEFINITION         => 0x00008000
, SQL_AT_CONSTRAINT_INITIALLY_DEFERRED      => 0x00010000
, SQL_AT_CONSTRAINT_INITIALLY_IMMEDIATE     => 0x00020000
, SQL_AT_CONSTRAINT_DEFERRABLE              => 0x00040000
, SQL_AT_CONSTRAINT_NON_DEFERRABLE          => 0x00080000
};
$ReturnValues{SQL_ASYNC_MODE} =
{
  SQL_AM_NONE                               => 0
, SQL_AM_CONNECTION                         => 1
, SQL_AM_STATEMENT                          => 2
, SQL_AM_NONE                               => 0
, SQL_AM_CONNECTION                         => 1
, SQL_AM_STATEMENT                          => 2
};
$ReturnValues{SQL_ATTR_MAX_ROWS} =
{
  SQL_CA2_MAX_ROWS_SELECT                   => 0x00000080
, SQL_CA2_MAX_ROWS_INSERT                   => 0x00000100
, SQL_CA2_MAX_ROWS_DELETE                   => 0x00000200
, SQL_CA2_MAX_ROWS_UPDATE                   => 0x00000400
, SQL_CA2_MAX_ROWS_CATALOG                  => 0x00000800
# SQL_CA2_MAX_ROWS_AFFECTS_ALL              =>
};
$ReturnValues{SQL_ATTR_SCROLL_CONCURRENCY} =
{
  SQL_CA2_READ_ONLY_CONCURRENCY             => 0x00000001
, SQL_CA2_LOCK_CONCURRENCY                  => 0x00000002
, SQL_CA2_OPT_ROWVER_CONCURRENCY            => 0x00000004
, SQL_CA2_OPT_VALUES_CONCURRENCY            => 0x00000008
, SQL_CA2_SENSITIVITY_ADDITIONS             => 0x00000010
, SQL_CA2_SENSITIVITY_DELETIONS             => 0x00000020
, SQL_CA2_SENSITIVITY_UPDATES               => 0x00000040
};
$ReturnValues{SQL_BATCH_ROW_COUNT} =
{
  SQL_BRC_PROCEDURES                        => 0x0000001
, SQL_BRC_EXPLICIT                          => 0x0000002
, SQL_BRC_ROLLED_UP                         => 0x0000004
};
$ReturnValues{SQL_BATCH_SUPPORT} =
{
  SQL_BS_SELECT_EXPLICIT                    => 0x00000001
, SQL_BS_ROW_COUNT_EXPLICIT                 => 0x00000002
, SQL_BS_SELECT_PROC                        => 0x00000004
, SQL_BS_ROW_COUNT_PROC                     => 0x00000008
};
$ReturnValues{SQL_BOOKMARK_PERSISTENCE} =
{
  SQL_BP_CLOSE                              => 0x00000001
, SQL_BP_DELETE                             => 0x00000002
, SQL_BP_DROP                               => 0x00000004
, SQL_BP_TRANSACTION                        => 0x00000008
, SQL_BP_UPDATE                             => 0x00000010
, SQL_BP_OTHER_HSTMT                        => 0x00000020
, SQL_BP_SCROLL                             => 0x00000040
};
$ReturnValues{SQL_CATALOG_LOCATION} =
{
  SQL_CL_START                              => 0x0001  # SQL_QL_START
, SQL_CL_END                                => 0x0002  # SQL_QL_END
};
$ReturnValues{SQL_CATALOG_USAGE} =
{
  SQL_CU_DML_STATEMENTS                     => 0x00000001  # SQL_QU_DML_STATEMENTS
, SQL_CU_PROCEDURE_INVOCATION               => 0x00000002  # SQL_QU_PROCEDURE_INVOCATION
, SQL_CU_TABLE_DEFINITION                   => 0x00000004  # SQL_QU_TABLE_DEFINITION
, SQL_CU_INDEX_DEFINITION                   => 0x00000008  # SQL_QU_INDEX_DEFINITION
, SQL_CU_PRIVILEGE_DEFINITION               => 0x00000010  # SQL_QU_PRIVILEGE_DEFINITION
};
$ReturnValues{SQL_CONCAT_NULL_BEHAVIOR} =
{
  SQL_CB_NULL                               => 0x0000
, SQL_CB_NON_NULL                           => 0x0001
};
$ReturnValues{SQL_CONVERT_} =
{
  SQL_CVT_CHAR                              => 0x00000001
, SQL_CVT_NUMERIC                           => 0x00000002
, SQL_CVT_DECIMAL                           => 0x00000004
, SQL_CVT_INTEGER                           => 0x00000008
, SQL_CVT_SMALLINT                          => 0x00000010
, SQL_CVT_FLOAT                             => 0x00000020
, SQL_CVT_REAL                              => 0x00000040
, SQL_CVT_DOUBLE                            => 0x00000080
, SQL_CVT_VARCHAR                           => 0x00000100
, SQL_CVT_LONGVARCHAR                       => 0x00000200
, SQL_CVT_BINARY                            => 0x00000400
, SQL_CVT_VARBINARY                         => 0x00000800
, SQL_CVT_BIT                               => 0x00001000
, SQL_CVT_TINYINT                           => 0x00002000
, SQL_CVT_BIGINT                            => 0x00004000
, SQL_CVT_DATE                              => 0x00008000
, SQL_CVT_TIME                              => 0x00010000
, SQL_CVT_TIMESTAMP                         => 0x00020000
, SQL_CVT_LONGVARBINARY                     => 0x00040000
, SQL_CVT_INTERVAL_YEAR_MONTH               => 0x00080000
, SQL_CVT_INTERVAL_DAY_TIME                 => 0x00100000
, SQL_CVT_WCHAR                             => 0x00200000
, SQL_CVT_WLONGVARCHAR                      => 0x00400000
, SQL_CVT_WVARCHAR                          => 0x00800000
, SQL_CVT_GUID                              => 0x01000000
};
$ReturnValues{SQL_CONVERT_BIGINT             } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_BINARY             } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_BIT                } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_CHAR               } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_DATE               } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_DECIMAL            } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_DOUBLE             } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_FLOAT              } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_GUID               } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_INTEGER            } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_INTERVAL_DAY_TIME  } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_INTERVAL_YEAR_MONTH} = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_LONGVARBINARY      } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_LONGVARCHAR        } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_NUMERIC            } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_REAL               } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_SMALLINT           } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_TIME               } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_TIMESTAMP          } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_TINYINT            } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_VARBINARY          } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_VARCHAR            } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_WCHAR              } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_WLONGVARCHAR       } = $ReturnValues{SQL_CONVERT_};
$ReturnValues{SQL_CONVERT_WVARCHAR           } = $ReturnValues{SQL_CONVERT_};

$ReturnValues{SQL_CONVERT_FUNCTIONS} =
{
  SQL_FN_CVT_CONVERT                        => 0x00000001
, SQL_FN_CVT_CAST                           => 0x00000002
};
$ReturnValues{SQL_CORRELATION_NAME} =
{
  SQL_CN_NONE                               => 0x0000
, SQL_CN_DIFFERENT                          => 0x0001
, SQL_CN_ANY                                => 0x0002
};
$ReturnValues{SQL_CREATE_ASSERTION} =
{
  SQL_CA_CREATE_ASSERTION                   => 0x00000001
, SQL_CA_CONSTRAINT_INITIALLY_DEFERRED      => 0x00000010
, SQL_CA_CONSTRAINT_INITIALLY_IMMEDIATE     => 0x00000020
, SQL_CA_CONSTRAINT_DEFERRABLE              => 0x00000040
, SQL_CA_CONSTRAINT_NON_DEFERRABLE          => 0x00000080
};
$ReturnValues{SQL_CREATE_CHARACTER_SET} =
{
  SQL_CCS_CREATE_CHARACTER_SET              => 0x00000001
, SQL_CCS_COLLATE_CLAUSE                    => 0x00000002
, SQL_CCS_LIMITED_COLLATION                 => 0x00000004
};
$ReturnValues{SQL_CREATE_COLLATION} =
{
  SQL_CCOL_CREATE_COLLATION                 => 0x00000001
};
$ReturnValues{SQL_CREATE_DOMAIN} =
{
  SQL_CDO_CREATE_DOMAIN                     => 0x00000001
, SQL_CDO_DEFAULT                           => 0x00000002
, SQL_CDO_CONSTRAINT                        => 0x00000004
, SQL_CDO_COLLATION                         => 0x00000008
, SQL_CDO_CONSTRAINT_NAME_DEFINITION        => 0x00000010
, SQL_CDO_CONSTRAINT_INITIALLY_DEFERRED     => 0x00000020
, SQL_CDO_CONSTRAINT_INITIALLY_IMMEDIATE    => 0x00000040
, SQL_CDO_CONSTRAINT_DEFERRABLE             => 0x00000080
, SQL_CDO_CONSTRAINT_NON_DEFERRABLE         => 0x00000100
};
$ReturnValues{SQL_CREATE_SCHEMA} =
{
  SQL_CS_CREATE_SCHEMA                      => 0x00000001
, SQL_CS_AUTHORIZATION                      => 0x00000002
, SQL_CS_DEFAULT_CHARACTER_SET              => 0x00000004
};
$ReturnValues{SQL_CREATE_TABLE} =
{
  SQL_CT_CREATE_TABLE                       => 0x00000001
, SQL_CT_COMMIT_PRESERVE                    => 0x00000002
, SQL_CT_COMMIT_DELETE                      => 0x00000004
, SQL_CT_GLOBAL_TEMPORARY                   => 0x00000008
, SQL_CT_LOCAL_TEMPORARY                    => 0x00000010
, SQL_CT_CONSTRAINT_INITIALLY_DEFERRED      => 0x00000020
, SQL_CT_CONSTRAINT_INITIALLY_IMMEDIATE     => 0x00000040
, SQL_CT_CONSTRAINT_DEFERRABLE              => 0x00000080
, SQL_CT_CONSTRAINT_NON_DEFERRABLE          => 0x00000100
, SQL_CT_COLUMN_CONSTRAINT                  => 0x00000200
, SQL_CT_COLUMN_DEFAULT                     => 0x00000400
, SQL_CT_COLUMN_COLLATION                   => 0x00000800
, SQL_CT_TABLE_CONSTRAINT                   => 0x00001000
, SQL_CT_CONSTRAINT_NAME_DEFINITION         => 0x00002000
};
$ReturnValues{SQL_CREATE_TRANSLATION} =
{
  SQL_CTR_CREATE_TRANSLATION                => 0x00000001
};
$ReturnValues{SQL_CREATE_VIEW} =
{
  SQL_CV_CREATE_VIEW                        => 0x00000001
, SQL_CV_CHECK_OPTION                       => 0x00000002
, SQL_CV_CASCADED                           => 0x00000004
, SQL_CV_LOCAL                              => 0x00000008
};
$ReturnValues{SQL_CURSOR_COMMIT_BEHAVIOR} =
{
  SQL_CB_DELETE                             => 0
, SQL_CB_CLOSE                              => 1
, SQL_CB_PRESERVE                           => 2
};
$ReturnValues{SQL_CURSOR_ROLLBACK_BEHAVIOR} = $ReturnValues{SQL_CURSOR_COMMIT_BEHAVIOR};

$ReturnValues{SQL_CURSOR_SENSITIVITY} =
{
  SQL_UNSPECIFIED                           => 0
, SQL_INSENSITIVE                           => 1
, SQL_SENSITIVE                             => 2
};
$ReturnValues{SQL_DATETIME_LITERALS} =
{
  SQL_DL_SQL92_DATE                         => 0x00000001
, SQL_DL_SQL92_TIME                         => 0x00000002
, SQL_DL_SQL92_TIMESTAMP                    => 0x00000004
, SQL_DL_SQL92_INTERVAL_YEAR                => 0x00000008
, SQL_DL_SQL92_INTERVAL_MONTH               => 0x00000010
, SQL_DL_SQL92_INTERVAL_DAY                 => 0x00000020
, SQL_DL_SQL92_INTERVAL_HOUR                => 0x00000040
, SQL_DL_SQL92_INTERVAL_MINUTE              => 0x00000080
, SQL_DL_SQL92_INTERVAL_SECOND              => 0x00000100
, SQL_DL_SQL92_INTERVAL_YEAR_TO_MONTH       => 0x00000200
, SQL_DL_SQL92_INTERVAL_DAY_TO_HOUR         => 0x00000400
, SQL_DL_SQL92_INTERVAL_DAY_TO_MINUTE       => 0x00000800
, SQL_DL_SQL92_INTERVAL_DAY_TO_SECOND       => 0x00001000
, SQL_DL_SQL92_INTERVAL_HOUR_TO_MINUTE      => 0x00002000
, SQL_DL_SQL92_INTERVAL_HOUR_TO_SECOND      => 0x00004000
, SQL_DL_SQL92_INTERVAL_MINUTE_TO_SECOND    => 0x00008000
};
$ReturnValues{SQL_DDL_INDEX} =
{
  SQL_DI_CREATE_INDEX                       => 0x00000001
, SQL_DI_DROP_INDEX                         => 0x00000002
};
$ReturnValues{SQL_DIAG_CURSOR_ROW_COUNT} =
{
  SQL_CA2_CRC_EXACT                         => 0x00001000
, SQL_CA2_CRC_APPROXIMATE                   => 0x00002000
, SQL_CA2_SIMULATE_NON_UNIQUE               => 0x00004000
, SQL_CA2_SIMULATE_TRY_UNIQUE               => 0x00008000
, SQL_CA2_SIMULATE_UNIQUE                   => 0x00010000
};
$ReturnValues{SQL_DROP_ASSERTION} =
{
  SQL_DA_DROP_ASSERTION                     => 0x00000001
};
$ReturnValues{SQL_DROP_CHARACTER_SET} =
{
  SQL_DCS_DROP_CHARACTER_SET                => 0x00000001
};
$ReturnValues{SQL_DROP_COLLATION} =
{
  SQL_DC_DROP_COLLATION                     => 0x00000001
};
$ReturnValues{SQL_DROP_DOMAIN} =
{
  SQL_DD_DROP_DOMAIN                        => 0x00000001
, SQL_DD_RESTRICT                           => 0x00000002
, SQL_DD_CASCADE                            => 0x00000004
};
$ReturnValues{SQL_DROP_SCHEMA} =
{
  SQL_DS_DROP_SCHEMA                        => 0x00000001
, SQL_DS_RESTRICT                           => 0x00000002
, SQL_DS_CASCADE                            => 0x00000004
};
$ReturnValues{SQL_DROP_TABLE} =
{
  SQL_DT_DROP_TABLE                         => 0x00000001
, SQL_DT_RESTRICT                           => 0x00000002
, SQL_DT_CASCADE                            => 0x00000004
};
$ReturnValues{SQL_DROP_TRANSLATION} =
{
  SQL_DTR_DROP_TRANSLATION                  => 0x00000001
};
$ReturnValues{SQL_DROP_VIEW} =
{
  SQL_DV_DROP_VIEW                          => 0x00000001
, SQL_DV_RESTRICT                           => 0x00000002
, SQL_DV_CASCADE                            => 0x00000004
};
$ReturnValues{SQL_CURSOR_ATTRIBUTES1} =
{
  SQL_CA1_NEXT                              => 0x00000001
, SQL_CA1_ABSOLUTE                          => 0x00000002
, SQL_CA1_RELATIVE                          => 0x00000004
, SQL_CA1_BOOKMARK                          => 0x00000008
, SQL_CA1_LOCK_NO_CHANGE                    => 0x00000040
, SQL_CA1_LOCK_EXCLUSIVE                    => 0x00000080
, SQL_CA1_LOCK_UNLOCK                       => 0x00000100
, SQL_CA1_POS_POSITION                      => 0x00000200
, SQL_CA1_POS_UPDATE                        => 0x00000400
, SQL_CA1_POS_DELETE                        => 0x00000800
, SQL_CA1_POS_REFRESH                       => 0x00001000
, SQL_CA1_POSITIONED_UPDATE                 => 0x00002000
, SQL_CA1_POSITIONED_DELETE                 => 0x00004000
, SQL_CA1_SELECT_FOR_UPDATE                 => 0x00008000
, SQL_CA1_BULK_ADD                          => 0x00010000
, SQL_CA1_BULK_UPDATE_BY_BOOKMARK           => 0x00020000
, SQL_CA1_BULK_DELETE_BY_BOOKMARK           => 0x00040000
, SQL_CA1_BULK_FETCH_BY_BOOKMARK            => 0x00080000
};
$ReturnValues{     SQL_DYNAMIC_CURSOR_ATTRIBUTES1} = $ReturnValues{SQL_CURSOR_ATTRIBUTES1};
$ReturnValues{SQL_FORWARD_ONLY_CURSOR_ATTRIBUTES1} = $ReturnValues{SQL_CURSOR_ATTRIBUTES1};
$ReturnValues{      SQL_KEYSET_CURSOR_ATTRIBUTES1} = $ReturnValues{SQL_CURSOR_ATTRIBUTES1};
$ReturnValues{      SQL_STATIC_CURSOR_ATTRIBUTES1} = $ReturnValues{SQL_CURSOR_ATTRIBUTES1};

$ReturnValues{SQL_CURSOR_ATTRIBUTES2} =
{
  SQL_CA2_READ_ONLY_CONCURRENCY             => 0x00000001
, SQL_CA2_LOCK_CONCURRENCY                  => 0x00000002
, SQL_CA2_OPT_ROWVER_CONCURRENCY            => 0x00000004
, SQL_CA2_OPT_VALUES_CONCURRENCY            => 0x00000008
, SQL_CA2_SENSITIVITY_ADDITIONS             => 0x00000010
, SQL_CA2_SENSITIVITY_DELETIONS             => 0x00000020
, SQL_CA2_SENSITIVITY_UPDATES               => 0x00000040
, SQL_CA2_MAX_ROWS_SELECT                   => 0x00000080
, SQL_CA2_MAX_ROWS_INSERT                   => 0x00000100
, SQL_CA2_MAX_ROWS_DELETE                   => 0x00000200
, SQL_CA2_MAX_ROWS_UPDATE                   => 0x00000400
, SQL_CA2_MAX_ROWS_CATALOG                  => 0x00000800
, SQL_CA2_CRC_EXACT                         => 0x00001000
, SQL_CA2_CRC_APPROXIMATE                   => 0x00002000
, SQL_CA2_SIMULATE_NON_UNIQUE               => 0x00004000
, SQL_CA2_SIMULATE_TRY_UNIQUE               => 0x00008000
, SQL_CA2_SIMULATE_UNIQUE                   => 0x00010000
};
$ReturnValues{     SQL_DYNAMIC_CURSOR_ATTRIBUTES2} = $ReturnValues{SQL_CURSOR_ATTRIBUTES2};
$ReturnValues{SQL_FORWARD_ONLY_CURSOR_ATTRIBUTES2} = $ReturnValues{SQL_CURSOR_ATTRIBUTES2};
$ReturnValues{      SQL_KEYSET_CURSOR_ATTRIBUTES2} = $ReturnValues{SQL_CURSOR_ATTRIBUTES2};
$ReturnValues{      SQL_STATIC_CURSOR_ATTRIBUTES2} = $ReturnValues{SQL_CURSOR_ATTRIBUTES2};

$ReturnValues{SQL_FETCH_DIRECTION} =
{
  SQL_FD_FETCH_NEXT                         => 0x00000001
, SQL_FD_FETCH_FIRST                        => 0x00000002
, SQL_FD_FETCH_LAST                         => 0x00000004
, SQL_FD_FETCH_PRIOR                        => 0x00000008
, SQL_FD_FETCH_ABSOLUTE                     => 0x00000010
, SQL_FD_FETCH_RELATIVE                     => 0x00000020
, SQL_FD_FETCH_RESUME                       => 0x00000040
, SQL_FD_FETCH_BOOKMARK                     => 0x00000080
};
$ReturnValues{SQL_FILE_USAGE} =
{
  SQL_FILE_NOT_SUPPORTED                    => 0x0000
, SQL_FILE_TABLE                            => 0x0001
, SQL_FILE_QUALIFIER                        => 0x0002
, SQL_FILE_CATALOG                          => 0x0002  # SQL_FILE_QUALIFIER
};
$ReturnValues{SQL_GETDATA_EXTENSIONS} =
{
  SQL_GD_ANY_COLUMN                         => 0x00000001
, SQL_GD_ANY_ORDER                          => 0x00000002
, SQL_GD_BLOCK                              => 0x00000004
, SQL_GD_BOUND                              => 0x00000008
};
$ReturnValues{SQL_GROUP_BY} =
{
  SQL_GB_NOT_SUPPORTED                      => 0x0000
, SQL_GB_GROUP_BY_EQUALS_SELECT             => 0x0001
, SQL_GB_GROUP_BY_CONTAINS_SELECT           => 0x0002
, SQL_GB_NO_RELATION                        => 0x0003
, SQL_GB_COLLATE                            => 0x0004
};
$ReturnValues{SQL_IDENTIFIER_CASE} =
{
  SQL_IC_UPPER                              => 1
, SQL_IC_LOWER                              => 2
, SQL_IC_SENSITIVE                          => 3
, SQL_IC_MIXED                              => 4
};
$ReturnValues{SQL_INDEX_KEYWORDS} =
{
  SQL_IK_NONE                               => 0x00000000
, SQL_IK_ASC                                => 0x00000001
, SQL_IK_DESC                               => 0x00000002
# SQL_IK_ALL                                =>
};
$ReturnValues{SQL_INFO_SCHEMA_VIEWS} =
{
  SQL_ISV_ASSERTIONS                        => 0x00000001
, SQL_ISV_CHARACTER_SETS                    => 0x00000002
, SQL_ISV_CHECK_CONSTRAINTS                 => 0x00000004
, SQL_ISV_COLLATIONS                        => 0x00000008
, SQL_ISV_COLUMN_DOMAIN_USAGE               => 0x00000010
, SQL_ISV_COLUMN_PRIVILEGES                 => 0x00000020
, SQL_ISV_COLUMNS                           => 0x00000040
, SQL_ISV_CONSTRAINT_COLUMN_USAGE           => 0x00000080
, SQL_ISV_CONSTRAINT_TABLE_USAGE            => 0x00000100
, SQL_ISV_DOMAIN_CONSTRAINTS                => 0x00000200
, SQL_ISV_DOMAINS                           => 0x00000400
, SQL_ISV_KEY_COLUMN_USAGE                  => 0x00000800
, SQL_ISV_REFERENTIAL_CONSTRAINTS           => 0x00001000
, SQL_ISV_SCHEMATA                          => 0x00002000
, SQL_ISV_SQL_LANGUAGES                     => 0x00004000
, SQL_ISV_TABLE_CONSTRAINTS                 => 0x00008000
, SQL_ISV_TABLE_PRIVILEGES                  => 0x00010000
, SQL_ISV_TABLES                            => 0x00020000
, SQL_ISV_TRANSLATIONS                      => 0x00040000
, SQL_ISV_USAGE_PRIVILEGES                  => 0x00080000
, SQL_ISV_VIEW_COLUMN_USAGE                 => 0x00100000
, SQL_ISV_VIEW_TABLE_USAGE                  => 0x00200000
, SQL_ISV_VIEWS                             => 0x00400000
};
$ReturnValues{SQL_INSERT_STATEMENT} =
{
  SQL_IS_INSERT_LITERALS                    => 0x00000001
, SQL_IS_INSERT_SEARCHED                    => 0x00000002
, SQL_IS_SELECT_INTO                        => 0x00000004
};
$ReturnValues{SQL_LOCK_TYPES} =
{
  SQL_LCK_NO_CHANGE                         => 0x00000001
, SQL_LCK_EXCLUSIVE                         => 0x00000002
, SQL_LCK_UNLOCK                            => 0x00000004
};
$ReturnValues{SQL_NON_NULLABLE_COLUMNS} =
{
  SQL_NNC_NULL                              => 0x0000
, SQL_NNC_NON_NULL                          => 0x0001
};
$ReturnValues{SQL_NULL_COLLATION} =
{
  SQL_NC_HIGH                               => 0
, SQL_NC_LOW                                => 1
, SQL_NC_START                              => 0x0002
, SQL_NC_END                                => 0x0004
};
$ReturnValues{SQL_NUMERIC_FUNCTIONS} =
{
  SQL_FN_NUM_ABS                            => 0x00000001
, SQL_FN_NUM_ACOS                           => 0x00000002
, SQL_FN_NUM_ASIN                           => 0x00000004
, SQL_FN_NUM_ATAN                           => 0x00000008
, SQL_FN_NUM_ATAN2                          => 0x00000010
, SQL_FN_NUM_CEILING                        => 0x00000020
, SQL_FN_NUM_COS                            => 0x00000040
, SQL_FN_NUM_COT                            => 0x00000080
, SQL_FN_NUM_EXP                            => 0x00000100
, SQL_FN_NUM_FLOOR                          => 0x00000200
, SQL_FN_NUM_LOG                            => 0x00000400
, SQL_FN_NUM_MOD                            => 0x00000800
, SQL_FN_NUM_SIGN                           => 0x00001000
, SQL_FN_NUM_SIN                            => 0x00002000
, SQL_FN_NUM_SQRT                           => 0x00004000
, SQL_FN_NUM_TAN                            => 0x00008000
, SQL_FN_NUM_PI                             => 0x00010000
, SQL_FN_NUM_RAND                           => 0x00020000
, SQL_FN_NUM_DEGREES                        => 0x00040000
, SQL_FN_NUM_LOG10                          => 0x00080000
, SQL_FN_NUM_POWER                          => 0x00100000
, SQL_FN_NUM_RADIANS                        => 0x00200000
, SQL_FN_NUM_ROUND                          => 0x00400000
, SQL_FN_NUM_TRUNCATE                       => 0x00800000
};
$ReturnValues{SQL_ODBC_API_CONFORMANCE} =
{
  SQL_OAC_NONE                              => 0x0000
, SQL_OAC_LEVEL1                            => 0x0001
, SQL_OAC_LEVEL2                            => 0x0002
};
$ReturnValues{SQL_ODBC_INTERFACE_CONFORMANCE} =
{
  SQL_OIC_CORE                              => 1
, SQL_OIC_LEVEL1                            => 2
, SQL_OIC_LEVEL2                            => 3
};
$ReturnValues{SQL_ODBC_SAG_CLI_CONFORMANCE} =
{
  SQL_OSCC_NOT_COMPLIANT                    => 0x0000
, SQL_OSCC_COMPLIANT                        => 0x0001
};
$ReturnValues{SQL_ODBC_SQL_CONFORMANCE} =
{
  SQL_OSC_MINIMUM                           => 0x0000
, SQL_OSC_CORE                              => 0x0001
, SQL_OSC_EXTENDED                          => 0x0002
};
$ReturnValues{SQL_OJ_CAPABILITIES} =
{
  SQL_OJ_LEFT                               => 0x00000001
, SQL_OJ_RIGHT                              => 0x00000002
, SQL_OJ_FULL                               => 0x00000004
, SQL_OJ_NESTED                             => 0x00000008
, SQL_OJ_NOT_ORDERED                        => 0x00000010
, SQL_OJ_INNER                              => 0x00000020
, SQL_OJ_ALL_COMPARISON_OPS                 => 0x00000040
};
$ReturnValues{SQL_OWNER_USAGE} =
{
  SQL_OU_DML_STATEMENTS                     => 0x00000001
, SQL_OU_PROCEDURE_INVOCATION               => 0x00000002
, SQL_OU_TABLE_DEFINITION                   => 0x00000004
, SQL_OU_INDEX_DEFINITION                   => 0x00000008
, SQL_OU_PRIVILEGE_DEFINITION               => 0x00000010
};
$ReturnValues{SQL_PARAM_ARRAY_ROW_COUNTS} =
{
  SQL_PARC_BATCH                            => 1
, SQL_PARC_NO_BATCH                         => 2
};
$ReturnValues{SQL_PARAM_ARRAY_SELECTS} =
{
  SQL_PAS_BATCH                             => 1
, SQL_PAS_NO_BATCH                          => 2
, SQL_PAS_NO_SELECT                         => 3
};
$ReturnValues{SQL_POSITIONED_STATEMENTS} =
{
  SQL_PS_POSITIONED_DELETE                  => 0x00000001
, SQL_PS_POSITIONED_UPDATE                  => 0x00000002
, SQL_PS_SELECT_FOR_UPDATE                  => 0x00000004
};
$ReturnValues{SQL_POS_OPERATIONS} =
{
  SQL_POS_POSITION                          => 0x00000001
, SQL_POS_REFRESH                           => 0x00000002
, SQL_POS_UPDATE                            => 0x00000004
, SQL_POS_DELETE                            => 0x00000008
, SQL_POS_ADD                               => 0x00000010
};
$ReturnValues{SQL_QUALIFIER_LOCATION} =
{
  SQL_QL_START                              => 0x0001
, SQL_QL_END                                => 0x0002
};
$ReturnValues{SQL_QUALIFIER_USAGE} =
{
  SQL_QU_DML_STATEMENTS                     => 0x00000001
, SQL_QU_PROCEDURE_INVOCATION               => 0x00000002
, SQL_QU_TABLE_DEFINITION                   => 0x00000004
, SQL_QU_INDEX_DEFINITION                   => 0x00000008
, SQL_QU_PRIVILEGE_DEFINITION               => 0x00000010
};
$ReturnValues{SQL_QUOTED_IDENTIFIER_CASE}   = $ReturnValues{SQL_IDENTIFIER_CASE};

$ReturnValues{SQL_SCHEMA_USAGE} =
{
  SQL_SU_DML_STATEMENTS                     => 0x00000001  # SQL_OU_DML_STATEMENTS
, SQL_SU_PROCEDURE_INVOCATION               => 0x00000002  # SQL_OU_PROCEDURE_INVOCATION
, SQL_SU_TABLE_DEFINITION                   => 0x00000004  # SQL_OU_TABLE_DEFINITION
, SQL_SU_INDEX_DEFINITION                   => 0x00000008  # SQL_OU_INDEX_DEFINITION
, SQL_SU_PRIVILEGE_DEFINITION               => 0x00000010  # SQL_OU_PRIVILEGE_DEFINITION
};
$ReturnValues{SQL_SCROLL_CONCURRENCY} =
{
  SQL_SCCO_READ_ONLY                        => 0x00000001
, SQL_SCCO_LOCK                             => 0x00000002
, SQL_SCCO_OPT_ROWVER                       => 0x00000004
, SQL_SCCO_OPT_VALUES                       => 0x00000008
};
$ReturnValues{SQL_SCROLL_OPTIONS} =
{
  SQL_SO_FORWARD_ONLY                       => 0x00000001
, SQL_SO_KEYSET_DRIVEN                      => 0x00000002
, SQL_SO_DYNAMIC                            => 0x00000004
, SQL_SO_MIXED                              => 0x00000008
, SQL_SO_STATIC                             => 0x00000010
};
$ReturnValues{SQL_SQL92_DATETIME_FUNCTIONS} =
{
  SQL_SDF_CURRENT_DATE                      => 0x00000001
, SQL_SDF_CURRENT_TIME                      => 0x00000002
, SQL_SDF_CURRENT_TIMESTAMP                 => 0x00000004
};
$ReturnValues{SQL_SQL92_FOREIGN_KEY_DELETE_RULE} =
{
  SQL_SFKD_CASCADE                          => 0x00000001
, SQL_SFKD_NO_ACTION                        => 0x00000002
, SQL_SFKD_SET_DEFAULT                      => 0x00000004
, SQL_SFKD_SET_NULL                         => 0x00000008
};
$ReturnValues{SQL_SQL92_FOREIGN_KEY_UPDATE_RULE} =
{
  SQL_SFKU_CASCADE                          => 0x00000001
, SQL_SFKU_NO_ACTION                        => 0x00000002
, SQL_SFKU_SET_DEFAULT                      => 0x00000004
, SQL_SFKU_SET_NULL                         => 0x00000008
};
$ReturnValues{SQL_SQL92_GRANT} =
{
  SQL_SG_USAGE_ON_DOMAIN                    => 0x00000001
, SQL_SG_USAGE_ON_CHARACTER_SET             => 0x00000002
, SQL_SG_USAGE_ON_COLLATION                 => 0x00000004
, SQL_SG_USAGE_ON_TRANSLATION               => 0x00000008
, SQL_SG_WITH_GRANT_OPTION                  => 0x00000010
, SQL_SG_DELETE_TABLE                       => 0x00000020
, SQL_SG_INSERT_TABLE                       => 0x00000040
, SQL_SG_INSERT_COLUMN                      => 0x00000080
, SQL_SG_REFERENCES_TABLE                   => 0x00000100
, SQL_SG_REFERENCES_COLUMN                  => 0x00000200
, SQL_SG_SELECT_TABLE                       => 0x00000400
, SQL_SG_UPDATE_TABLE                       => 0x00000800
, SQL_SG_UPDATE_COLUMN                      => 0x00001000
};
$ReturnValues{SQL_SQL92_NUMERIC_VALUE_FUNCTIONS} =
{
  SQL_SNVF_BIT_LENGTH                       => 0x00000001
, SQL_SNVF_CHAR_LENGTH                      => 0x00000002
, SQL_SNVF_CHARACTER_LENGTH                 => 0x00000004
, SQL_SNVF_EXTRACT                          => 0x00000008
, SQL_SNVF_OCTET_LENGTH                     => 0x00000010
, SQL_SNVF_POSITION                         => 0x00000020
};
$ReturnValues{SQL_SQL92_PREDICATES} =
{
  SQL_SP_EXISTS                             => 0x00000001
, SQL_SP_ISNOTNULL                          => 0x00000002
, SQL_SP_ISNULL                             => 0x00000004
, SQL_SP_MATCH_FULL                         => 0x00000008
, SQL_SP_MATCH_PARTIAL                      => 0x00000010
, SQL_SP_MATCH_UNIQUE_FULL                  => 0x00000020
, SQL_SP_MATCH_UNIQUE_PARTIAL               => 0x00000040
, SQL_SP_OVERLAPS                           => 0x00000080
, SQL_SP_UNIQUE                             => 0x00000100
, SQL_SP_LIKE                               => 0x00000200
, SQL_SP_IN                                 => 0x00000400
, SQL_SP_BETWEEN                            => 0x00000800
, SQL_SP_COMPARISON                         => 0x00001000
, SQL_SP_QUANTIFIED_COMPARISON              => 0x00002000
};
$ReturnValues{SQL_SQL92_RELATIONAL_JOIN_OPERATORS} =
{
  SQL_SRJO_CORRESPONDING_CLAUSE             => 0x00000001
, SQL_SRJO_CROSS_JOIN                       => 0x00000002
, SQL_SRJO_EXCEPT_JOIN                      => 0x00000004
, SQL_SRJO_FULL_OUTER_JOIN                  => 0x00000008
, SQL_SRJO_INNER_JOIN                       => 0x00000010
, SQL_SRJO_INTERSECT_JOIN                   => 0x00000020
, SQL_SRJO_LEFT_OUTER_JOIN                  => 0x00000040
, SQL_SRJO_NATURAL_JOIN                     => 0x00000080
, SQL_SRJO_RIGHT_OUTER_JOIN                 => 0x00000100
, SQL_SRJO_UNION_JOIN                       => 0x00000200
};
$ReturnValues{SQL_SQL92_REVOKE} =
{
  SQL_SR_USAGE_ON_DOMAIN                    => 0x00000001
, SQL_SR_USAGE_ON_CHARACTER_SET             => 0x00000002
, SQL_SR_USAGE_ON_COLLATION                 => 0x00000004
, SQL_SR_USAGE_ON_TRANSLATION               => 0x00000008
, SQL_SR_GRANT_OPTION_FOR                   => 0x00000010
, SQL_SR_CASCADE                            => 0x00000020
, SQL_SR_RESTRICT                           => 0x00000040
, SQL_SR_DELETE_TABLE                       => 0x00000080
, SQL_SR_INSERT_TABLE                       => 0x00000100
, SQL_SR_INSERT_COLUMN                      => 0x00000200
, SQL_SR_REFERENCES_TABLE                   => 0x00000400
, SQL_SR_REFERENCES_COLUMN                  => 0x00000800
, SQL_SR_SELECT_TABLE                       => 0x00001000
, SQL_SR_UPDATE_TABLE                       => 0x00002000
, SQL_SR_UPDATE_COLUMN                      => 0x00004000
};
$ReturnValues{SQL_SQL92_ROW_VALUE_CONSTRUCTOR} =
{
  SQL_SRVC_VALUE_EXPRESSION                 => 0x00000001
, SQL_SRVC_NULL                             => 0x00000002
, SQL_SRVC_DEFAULT                          => 0x00000004
, SQL_SRVC_ROW_SUBQUERY                     => 0x00000008
};
$ReturnValues{SQL_SQL92_STRING_FUNCTIONS} =
{
  SQL_SSF_CONVERT                           => 0x00000001
, SQL_SSF_LOWER                             => 0x00000002
, SQL_SSF_UPPER                             => 0x00000004
, SQL_SSF_SUBSTRING                         => 0x00000008
, SQL_SSF_TRANSLATE                         => 0x00000010
, SQL_SSF_TRIM_BOTH                         => 0x00000020
, SQL_SSF_TRIM_LEADING                      => 0x00000040
, SQL_SSF_TRIM_TRAILING                     => 0x00000080
};
$ReturnValues{SQL_SQL92_VALUE_EXPRESSIONS} =
{
  SQL_SVE_CASE                              => 0x00000001
, SQL_SVE_CAST                              => 0x00000002
, SQL_SVE_COALESCE                          => 0x00000004
, SQL_SVE_NULLIF                            => 0x00000008
};
$ReturnValues{SQL_SQL_CONFORMANCE} =
{
  SQL_SC_SQL92_ENTRY                        => 0x00000001
, SQL_SC_FIPS127_2_TRANSITIONAL             => 0x00000002
, SQL_SC_SQL92_INTERMEDIATE                 => 0x00000004
, SQL_SC_SQL92_FULL                         => 0x00000008
};
$ReturnValues{SQL_STANDARD_CLI_CONFORMANCE} =
{
  SQL_SCC_XOPEN_CLI_VERSION1                => 0x00000001
, SQL_SCC_ISO92_CLI                         => 0x00000002
};
$ReturnValues{SQL_STATIC_SENSITIVITY} =
{
  SQL_SS_ADDITIONS                          => 0x00000001
, SQL_SS_DELETIONS                          => 0x00000002
, SQL_SS_UPDATES                            => 0x00000004
};
$ReturnValues{SQL_STRING_FUNCTIONS} =
{
  SQL_FN_STR_CONCAT                         => 0x00000001
, SQL_FN_STR_INSERT                         => 0x00000002
, SQL_FN_STR_LEFT                           => 0x00000004
, SQL_FN_STR_LTRIM                          => 0x00000008
, SQL_FN_STR_LENGTH                         => 0x00000010
, SQL_FN_STR_LOCATE                         => 0x00000020
, SQL_FN_STR_LCASE                          => 0x00000040
, SQL_FN_STR_REPEAT                         => 0x00000080
, SQL_FN_STR_REPLACE                        => 0x00000100
, SQL_FN_STR_RIGHT                          => 0x00000200
, SQL_FN_STR_RTRIM                          => 0x00000400
, SQL_FN_STR_SUBSTRING                      => 0x00000800
, SQL_FN_STR_UCASE                          => 0x00001000
, SQL_FN_STR_ASCII                          => 0x00002000
, SQL_FN_STR_CHAR                           => 0x00004000
, SQL_FN_STR_DIFFERENCE                     => 0x00008000
, SQL_FN_STR_LOCATE_2                       => 0x00010000
, SQL_FN_STR_SOUNDEX                        => 0x00020000
, SQL_FN_STR_SPACE                          => 0x00040000
, SQL_FN_STR_BIT_LENGTH                     => 0x00080000
, SQL_FN_STR_CHAR_LENGTH                    => 0x00100000
, SQL_FN_STR_CHARACTER_LENGTH               => 0x00200000
, SQL_FN_STR_OCTET_LENGTH                   => 0x00400000
, SQL_FN_STR_POSITION                       => 0x00800000
};
$ReturnValues{SQL_SUBQUERIES} =
{
  SQL_SQ_COMPARISON                         => 0x00000001
, SQL_SQ_EXISTS                             => 0x00000002
, SQL_SQ_IN                                 => 0x00000004
, SQL_SQ_QUANTIFIED                         => 0x00000008
, SQL_SQ_CORRELATED_SUBQUERIES              => 0x00000010
};
$ReturnValues{SQL_SYSTEM_FUNCTIONS} =
{
  SQL_FN_SYS_USERNAME                       => 0x00000001
, SQL_FN_SYS_DBNAME                         => 0x00000002
, SQL_FN_SYS_IFNULL                         => 0x00000004
};
$ReturnValues{SQL_TIMEDATE_ADD_INTERVALS} =
{
  SQL_FN_TSI_FRAC_SECOND                    => 0x00000001
, SQL_FN_TSI_SECOND                         => 0x00000002
, SQL_FN_TSI_MINUTE                         => 0x00000004
, SQL_FN_TSI_HOUR                           => 0x00000008
, SQL_FN_TSI_DAY                            => 0x00000010
, SQL_FN_TSI_WEEK                           => 0x00000020
, SQL_FN_TSI_MONTH                          => 0x00000040
, SQL_FN_TSI_QUARTER                        => 0x00000080
, SQL_FN_TSI_YEAR                           => 0x00000100
};
$ReturnValues{SQL_TIMEDATE_FUNCTIONS} =
{
  SQL_FN_TD_NOW                             => 0x00000001
, SQL_FN_TD_CURDATE                         => 0x00000002
, SQL_FN_TD_DAYOFMONTH                      => 0x00000004
, SQL_FN_TD_DAYOFWEEK                       => 0x00000008
, SQL_FN_TD_DAYOFYEAR                       => 0x00000010
, SQL_FN_TD_MONTH                           => 0x00000020
, SQL_FN_TD_QUARTER                         => 0x00000040
, SQL_FN_TD_WEEK                            => 0x00000080
, SQL_FN_TD_YEAR                            => 0x00000100
, SQL_FN_TD_CURTIME                         => 0x00000200
, SQL_FN_TD_HOUR                            => 0x00000400
, SQL_FN_TD_MINUTE                          => 0x00000800
, SQL_FN_TD_SECOND                          => 0x00001000
, SQL_FN_TD_TIMESTAMPADD                    => 0x00002000
, SQL_FN_TD_TIMESTAMPDIFF                   => 0x00004000
, SQL_FN_TD_DAYNAME                         => 0x00008000
, SQL_FN_TD_MONTHNAME                       => 0x00010000
, SQL_FN_TD_CURRENT_DATE                    => 0x00020000
, SQL_FN_TD_CURRENT_TIME                    => 0x00040000
, SQL_FN_TD_CURRENT_TIMESTAMP               => 0x00080000
, SQL_FN_TD_EXTRACT                         => 0x00100000
};
$ReturnValues{SQL_TXN_CAPABLE} =
{
  SQL_TC_NONE                               => 0
, SQL_TC_DML                                => 1
, SQL_TC_ALL                                => 2
, SQL_TC_DDL_COMMIT                         => 3
, SQL_TC_DDL_IGNORE                         => 4
};
$ReturnValues{SQL_TRANSACTION_ISOLATION_OPTION} =
{
  SQL_TRANSACTION_READ_UNCOMMITTED          => 0x00000001  # SQL_TXN_READ_UNCOMMITTED
, SQL_TRANSACTION_READ_COMMITTED            => 0x00000002  # SQL_TXN_READ_COMMITTED
, SQL_TRANSACTION_REPEATABLE_READ           => 0x00000004  # SQL_TXN_REPEATABLE_READ
, SQL_TRANSACTION_SERIALIZABLE              => 0x00000008  # SQL_TXN_SERIALIZABLE
};
$ReturnValues{SQL_DEFAULT_TRANSACTION_ISOLATION} = $ReturnValues{SQL_TRANSACTION_ISOLATION_OPTION};

$ReturnValues{SQL_TXN_ISOLATION_OPTION} =
{
  SQL_TXN_READ_UNCOMMITTED                  => 0x00000001
, SQL_TXN_READ_COMMITTED                    => 0x00000002
, SQL_TXN_REPEATABLE_READ                   => 0x00000004
, SQL_TXN_SERIALIZABLE                      => 0x00000008
};
$ReturnValues{SQL_DEFAULT_TXN_ISOLATION} = $ReturnValues{SQL_TXN_ISOLATION_OPTION};

$ReturnValues{SQL_TXN_VERSIONING} =
{
  SQL_TXN_VERSIONING                        => 0x00000010
};
$ReturnValues{SQL_UNION} =
{
  SQL_U_UNION                               => 0x00000001
, SQL_U_UNION_ALL                           => 0x00000002
};
$ReturnValues{SQL_UNION_STATEMENT} =
{
  SQL_US_UNION                              => 0x00000001  # SQL_U_UNION
, SQL_US_UNION_ALL                          => 0x00000002  # SQL_U_UNION_ALL
};

1;

=head1 TODO

  Corrections?
  SQL_NULL_COLLATION: ODBC vs ANSI
  Unique values for $ReturnValues{...}?, e.g. SQL_FILE_USAGE

=cut
