# $Id: ANSI.pm 8696 2007-01-24 23:12:38Z timbo $
#
# Copyright (c) 2002  Tim Bunce  Ireland
#
# Constant data describing ANSI CLI info types and return values for the
# SQLGetInfo() method of ODBC.
#
# You may distribute under the terms of either the GNU General Public
# License or the Artistic License, as specified in the Perl README file.

package DBI::Const::GetInfo::ANSI;

=head1 NAME

DBI::Const::GetInfo::ANSI - ISO/IEC SQL/CLI Constants for GetInfo

=head1 SYNOPSIS

  The API for this module is private and subject to change.

=head1 DESCRIPTION

Information requested by GetInfo().

See: A.1 C header file SQLCLI.H, Page 316, 317.

The API for this module is private and subject to change.

=head1 REFERENCES

  ISO/IEC FCD 9075-3:200x Information technology - Database Languages -
  SQL - Part 3: Call-Level Interface (SQL/CLI)

  SC32 N00744 = WG3:VIE-005 = H2-2002-007

  Date: 2002-01-15

=cut

my
$VERSION = sprintf("2.%06d", q$Revision: 8696 $ =~ /(\d+)/o);


%InfoTypes =
(
  SQL_ALTER_TABLE                     =>      86
, SQL_CATALOG_NAME                    =>   10003
, SQL_COLLATING_SEQUENCE              =>   10004
, SQL_CURSOR_COMMIT_BEHAVIOR          =>      23
, SQL_CURSOR_SENSITIVITY              =>   10001
, SQL_DATA_SOURCE_NAME                =>       2
, SQL_DATA_SOURCE_READ_ONLY           =>      25
, SQL_DBMS_NAME                       =>      17
, SQL_DBMS_VERSION                    =>      18
, SQL_DEFAULT_TRANSACTION_ISOLATION   =>      26
, SQL_DESCRIBE_PARAMETER              =>   10002
, SQL_FETCH_DIRECTION                 =>       8
, SQL_GETDATA_EXTENSIONS              =>      81
, SQL_IDENTIFIER_CASE                 =>      28
, SQL_INTEGRITY                       =>      73
, SQL_MAXIMUM_CATALOG_NAME_LENGTH     =>      34
, SQL_MAXIMUM_COLUMNS_IN_GROUP_BY     =>      97
, SQL_MAXIMUM_COLUMNS_IN_ORDER_BY     =>      99
, SQL_MAXIMUM_COLUMNS_IN_SELECT       =>     100
, SQL_MAXIMUM_COLUMNS_IN_TABLE        =>     101
, SQL_MAXIMUM_COLUMN_NAME_LENGTH      =>      30
, SQL_MAXIMUM_CONCURRENT_ACTIVITIES   =>       1
, SQL_MAXIMUM_CURSOR_NAME_LENGTH      =>      31
, SQL_MAXIMUM_DRIVER_CONNECTIONS      =>       0
, SQL_MAXIMUM_IDENTIFIER_LENGTH       =>   10005
, SQL_MAXIMUM_SCHEMA_NAME_LENGTH      =>      32
, SQL_MAXIMUM_STMT_OCTETS             =>   20000
, SQL_MAXIMUM_STMT_OCTETS_DATA        =>   20001
, SQL_MAXIMUM_STMT_OCTETS_SCHEMA      =>   20002
, SQL_MAXIMUM_TABLES_IN_SELECT        =>     106
, SQL_MAXIMUM_TABLE_NAME_LENGTH       =>      35
, SQL_MAXIMUM_USER_NAME_LENGTH        =>     107
, SQL_NULL_COLLATION                  =>      85
, SQL_ORDER_BY_COLUMNS_IN_SELECT      =>      90
, SQL_OUTER_JOIN_CAPABILITIES         =>     115
, SQL_SCROLL_CONCURRENCY              =>      43
, SQL_SEARCH_PATTERN_ESCAPE           =>      14
, SQL_SERVER_NAME                     =>      13
, SQL_SPECIAL_CHARACTERS              =>      94
, SQL_TRANSACTION_CAPABLE             =>      46
, SQL_TRANSACTION_ISOLATION_OPTION    =>      72
, SQL_USER_NAME                       =>      47
);

=head2 %ReturnTypes

See: Codes and data types for implementation information (Table 28), Page 85, 86.

Mapped to ODBC datatype names.

=cut

%ReturnTypes =                                                 #          maxlen
(
  SQL_ALTER_TABLE                     => 'SQLUINTEGER bitmask' # INTEGER
, SQL_CATALOG_NAME                    => 'SQLCHAR'             # CHARACTER   (1)
, SQL_COLLATING_SEQUENCE              => 'SQLCHAR'             # CHARACTER (254)
, SQL_CURSOR_COMMIT_BEHAVIOR          => 'SQLUSMALLINT'        # SMALLINT
, SQL_CURSOR_SENSITIVITY              => 'SQLUINTEGER'         # INTEGER
, SQL_DATA_SOURCE_NAME                => 'SQLCHAR'             # CHARACTER (128)
, SQL_DATA_SOURCE_READ_ONLY           => 'SQLCHAR'             # CHARACTER   (1)
, SQL_DBMS_NAME                       => 'SQLCHAR'             # CHARACTER (254)
, SQL_DBMS_VERSION                    => 'SQLCHAR'             # CHARACTER (254)
, SQL_DEFAULT_TRANSACTION_ISOLATION   => 'SQLUINTEGER'         # INTEGER
, SQL_DESCRIBE_PARAMETER              => 'SQLCHAR'             # CHARACTER   (1)
, SQL_FETCH_DIRECTION                 => 'SQLUINTEGER bitmask' # INTEGER
, SQL_GETDATA_EXTENSIONS              => 'SQLUINTEGER bitmask' # INTEGER
, SQL_IDENTIFIER_CASE                 => 'SQLUSMALLINT'        # SMALLINT
, SQL_INTEGRITY                       => 'SQLCHAR'             # CHARACTER   (1)
, SQL_MAXIMUM_CATALOG_NAME_LENGTH     => 'SQLUSMALLINT'        # SMALLINT
, SQL_MAXIMUM_COLUMNS_IN_GROUP_BY     => 'SQLUSMALLINT'        # SMALLINT
, SQL_MAXIMUM_COLUMNS_IN_ORDER_BY     => 'SQLUSMALLINT'        # SMALLINT
, SQL_MAXIMUM_COLUMNS_IN_SELECT       => 'SQLUSMALLINT'        # SMALLINT
, SQL_MAXIMUM_COLUMNS_IN_TABLE        => 'SQLUSMALLINT'        # SMALLINT
, SQL_MAXIMUM_COLUMN_NAME_LENGTH      => 'SQLUSMALLINT'        # SMALLINT
, SQL_MAXIMUM_CONCURRENT_ACTIVITIES   => 'SQLUSMALLINT'        # SMALLINT
, SQL_MAXIMUM_CURSOR_NAME_LENGTH      => 'SQLUSMALLINT'        # SMALLINT
, SQL_MAXIMUM_DRIVER_CONNECTIONS      => 'SQLUSMALLINT'        # SMALLINT
, SQL_MAXIMUM_IDENTIFIER_LENGTH       => 'SQLUSMALLINT'        # SMALLINT
, SQL_MAXIMUM_SCHEMA_NAME_LENGTH      => 'SQLUSMALLINT'        # SMALLINT
, SQL_MAXIMUM_STMT_OCTETS             => 'SQLUSMALLINT'        # SMALLINT
, SQL_MAXIMUM_STMT_OCTETS_DATA        => 'SQLUSMALLINT'        # SMALLINT
, SQL_MAXIMUM_STMT_OCTETS_SCHEMA      => 'SQLUSMALLINT'        # SMALLINT
, SQL_MAXIMUM_TABLES_IN_SELECT        => 'SQLUSMALLINT'        # SMALLINT
, SQL_MAXIMUM_TABLE_NAME_LENGTH       => 'SQLUSMALLINT'        # SMALLINT
, SQL_MAXIMUM_USER_NAME_LENGTH        => 'SQLUSMALLINT'        # SMALLINT
, SQL_NULL_COLLATION                  => 'SQLUSMALLINT'        # SMALLINT
, SQL_ORDER_BY_COLUMNS_IN_SELECT      => 'SQLCHAR'             # CHARACTER   (1)
, SQL_OUTER_JOIN_CAPABILITIES         => 'SQLUINTEGER bitmask' # INTEGER
, SQL_SCROLL_CONCURRENCY              => 'SQLUINTEGER bitmask' # INTEGER
, SQL_SEARCH_PATTERN_ESCAPE           => 'SQLCHAR'             # CHARACTER   (1)
, SQL_SERVER_NAME                     => 'SQLCHAR'             # CHARACTER (128)
, SQL_SPECIAL_CHARACTERS              => 'SQLCHAR'             # CHARACTER (254)
, SQL_TRANSACTION_CAPABLE             => 'SQLUSMALLINT'        # SMALLINT
, SQL_TRANSACTION_ISOLATION_OPTION    => 'SQLUINTEGER bitmask' # INTEGER
, SQL_USER_NAME                       => 'SQLCHAR'             # CHARACTER (128)
);

=head2 %ReturnValues

See: A.1 C header file SQLCLI.H, Page 317, 318.

=cut

$ReturnValues{SQL_ALTER_TABLE} =
{
  SQL_AT_ADD_COLUMN                         => 0x00000001
, SQL_AT_DROP_COLUMN                        => 0x00000002
, SQL_AT_ALTER_COLUMN                       => 0x00000004
, SQL_AT_ADD_CONSTRAINT                     => 0x00000008
, SQL_AT_DROP_CONSTRAINT                    => 0x00000010
};
$ReturnValues{SQL_CURSOR_COMMIT_BEHAVIOR} =
{
  SQL_CB_DELETE                             => 0
, SQL_CB_CLOSE                              => 1
, SQL_CB_PRESERVE                           => 2
};
$ReturnValues{SQL_FETCH_DIRECTION} =
{
  SQL_FD_FETCH_NEXT                         => 0x00000001
, SQL_FD_FETCH_FIRST                        => 0x00000002
, SQL_FD_FETCH_LAST                         => 0x00000004
, SQL_FD_FETCH_PRIOR                        => 0x00000008
, SQL_FD_FETCH_ABSOLUTE                     => 0x00000010
, SQL_FD_FETCH_RELATIVE                     => 0x00000020
};
$ReturnValues{SQL_GETDATA_EXTENSIONS} =
{
  SQL_GD_ANY_COLUMN                         => 0x00000001
, SQL_GD_ANY_ORDER                          => 0x00000002
};
$ReturnValues{SQL_IDENTIFIER_CASE} =
{
  SQL_IC_UPPER                              => 1
, SQL_IC_LOWER                              => 2
, SQL_IC_SENSITIVE                          => 3
, SQL_IC_MIXED                              => 4
};
$ReturnValues{SQL_NULL_COLLATION} =
{
  SQL_NC_HIGH                               => 1
, SQL_NC_LOW                                => 2
};
$ReturnValues{SQL_OUTER_JOIN_CAPABILITIES} =
{
  SQL_OUTER_JOIN_LEFT                       => 0x00000001
, SQL_OUTER_JOIN_RIGHT                      => 0x00000002
, SQL_OUTER_JOIN_FULL                       => 0x00000004
, SQL_OUTER_JOIN_NESTED                     => 0x00000008
, SQL_OUTER_JOIN_NOT_ORDERED                => 0x00000010
, SQL_OUTER_JOIN_INNER                      => 0x00000020
, SQL_OUTER_JOIN_ALL_COMPARISON_OPS         => 0x00000040
};
$ReturnValues{SQL_SCROLL_CONCURRENCY} =
{
  SQL_SCCO_READ_ONLY                        => 0x00000001
, SQL_SCCO_LOCK                             => 0x00000002
, SQL_SCCO_OPT_ROWVER                       => 0x00000004
, SQL_SCCO_OPT_VALUES                       => 0x00000008
};
$ReturnValues{SQL_TRANSACTION_ACCESS_MODE} =
{
  SQL_TRANSACTION_READ_ONLY                 => 0x00000001
, SQL_TRANSACTION_READ_WRITE                => 0x00000002
};
$ReturnValues{SQL_TRANSACTION_CAPABLE} =
{
  SQL_TC_NONE                               => 0
, SQL_TC_DML                                => 1
, SQL_TC_ALL                                => 2
, SQL_TC_DDL_COMMIT                         => 3
, SQL_TC_DDL_IGNORE                         => 4
};
$ReturnValues{SQL_TRANSACTION_ISOLATION} =
{
  SQL_TRANSACTION_READ_UNCOMMITTED          => 0x00000001
, SQL_TRANSACTION_READ_COMMITTED            => 0x00000002
, SQL_TRANSACTION_REPEATABLE_READ           => 0x00000004
, SQL_TRANSACTION_SERIALIZABLE              => 0x00000008
};

1;

=head1 TODO

Corrections, e.g.:

  SQL_TRANSACTION_ISOLATION_OPTION vs. SQL_TRANSACTION_ISOLATION

=cut
