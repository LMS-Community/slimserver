package Win32::Lanman;

#
# Lanman.pm by Jens Helberg, jens.helberg@de.bosch.com
#
# some parts of this file are written by Gavin McNay, thanks to him
#
# all comments are welcome
#
# you can use this module under the GNU public licence
#
#
# version 1.0.10.0 from 01/10/2003
#
# not all functions are completely tested - use this at your own risk
#
# it's intended to work on winnt (version 4.0 with sp3 or later) or windows 2000. 
# it should work with windows xp, but it's not heavy tested. 
# it does not work with w95/98/me!
#

require Exporter;
require DynaLoader;

$VERSION = 1.100;
$Package = "Win32::Lanman";

die "The $Package module works only on Windows NT/Windows 2000" 
	unless Win32::IsWinNT();

@ISA= qw( Exporter DynaLoader );

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw(

	NET_INFO_DESCRIPTION
	NET_STATUS_DESCRIPTION
	SERVICE_CONTROL_DESCRIPTIONS
	SERVICE_STATE_DESCRIPTIONS
	SERVICE_CONTROLS
	SERVICE_START_TYPES
	SERVICE_ERROR_TYPES
	SC_FAILURE_ACTIONS
	SERVICE_ACCEPTED_CONTROLS
	SERVICE_ADAPTER
	SERVICE_RECOGNIZER_DRIVER
	SERVICE_TYPE_ALL
	SV_TYPES 
	SERVICE_STATES 
	SERVICE_TYPES 
	WTS_STATES 
	SidToString
	StringToSid
	GuidToString
	StringToGuid

	AF_OP_ACCOUNTS
	AF_OP_COMM
	AF_OP_PRINT
	AF_OP_SERVER

	ALLOCATE_RESPONSE     

	AuditCategoryAccountLogon
	AuditCategoryAccountManagement
	AuditCategoryDetailedTracking
	AuditCategoryDirectoryServiceAccess
	AuditCategoryLogon
	AuditCategoryObjectAccess
	AuditCategoryPolicyChange
	AuditCategoryPrivilegeUse
	AuditCategorySystem

	AUTH_REQ_ALLOW_ENC_TKT_IN_SKEY
	AUTH_REQ_ALLOW_FORWARDABLE
	AUTH_REQ_ALLOW_NOADDRESS
	AUTH_REQ_ALLOW_POSTDATE
	AUTH_REQ_ALLOW_PROXIABLE
	AUTH_REQ_ALLOW_RENEWABLE
	AUTH_REQ_ALLOW_VALIDATE
	AUTH_REQ_OK_AS_DELEGATE
	AUTH_REQ_PREAUTH_REQUIRED
	AUTH_REQ_VALIDATE_CLIENT

	Batch

	CONNECT_CURRENT_MEDIA
	CONNECT_DEFERRED
	CONNECT_INTERACTIVE
	CONNECT_LOCALDRIVE
	CONNECT_NEED_DRIVE
	CONNECT_PROMPT
	CONNECT_REDIRECT
	CONNECT_REFCOUNT
	CONNECT_RESERVED
	CONNECT_TEMPORARY
	CONNECT_UPDATE_PROFILE
	CONNECT_UPDATE_RECENT

	CONNDLG_CONN_POINT
	CONNDLG_HIDE_BOX
	CONNDLG_NOT_PERSIST
	CONNDLG_PERSIST
	CONNDLG_RO_PATH
	CONNDLG_USE_MRU
	CONNECT_UPDATE_PROFILE

	DACL_SECURITY_INFORMATION

	DEF_MAX_PWHIST

	DISC_NO_FORCE
	DISC_UPDATE_PROFILE

	DFS_ADD_VOLUME
	DFS_RESTORE_VOLUME
	DFS_STORAGE_STATE_ACTIVE
	DFS_STORAGE_STATE_OFFLINE
	DFS_STORAGE_STATE_ONLINE
	DFS_VOLUME_STATE_INCONSISTENT
	DFS_VOLUME_STATE_OK
	DFS_VOLUME_STATE_OFFLINE
	DFS_VOLUME_STATE_ONLINE

	EVENTLOG_BACKWARDS_READ
	EVENTLOG_FORWARDS_READ
	EVENTLOG_SEEK_READ
	EVENTLOG_SEQUENTIAL_READ

	EVENTLOG_ERROR_TYPE
	EVENTLOG_WARNING_TYPE
	EVENTLOG_INFORMATION_TYPE
	EVENTLOG_AUDIT_SUCCESS
	EVENTLOG_AUDIT_FAILURE

	FILTER_INTERDOMAIN_TRUST_ACCOUNT
	FILTER_NORMAL_ACCOUNT
	FILTER_SERVER_TRUST_ACCOUNT
	FILTER_TEMP_DUPLICATE_ACCOUNT
	FILTER_WORKSTATION_TRUST_ACCOUNT

	GROUP_SECURITY_INFORMATION

	IDASYNC
	IDTIMEOUT

	Interactive

	JOB_ADD_CURRENT_DATE
	JOB_EXEC_ERROR
	JOB_INPUT_FLAGS
	JOB_NONINTERACTIVE
	JOB_OUTPUT_FLAGS
	JOB_RUN_PERIODICALLY
	JOB_RUNS_TODAY

	KERB_CHECKSUM_CRC32
	KERB_CHECKSUM_DES_MAC
	KERB_CHECKSUM_DES_MAC_MD5
	KERB_CHECKSUM_HMAC_MD5
	KERB_CHECKSUM_KRB_DES_MAC
	KERB_CHECKSUM_LM
	KERB_CHECKSUM_MD25
	KERB_CHECKSUM_MD4
	KERB_CHECKSUM_MD5
	KERB_CHECKSUM_MD5_DES
	KERB_CHECKSUM_MD5_HMAC
	KERB_CHECKSUM_NONE
	KERB_CHECKSUM_RC4_MD5
	KERB_CHECKSUM_REAL_CRC32
	KERB_CHECKSUM_SHA1
	KERB_DECRYPT_FLAG_DEFAULT_KEY
	KERB_ETYPE_DES_CBC_CRC
	KERB_ETYPE_DES_CBC_MD4
	KERB_ETYPE_DES_CBC_MD5
	KERB_ETYPE_DES_CBC_MD5_NT
	KERB_ETYPE_DES_PLAIN
	KERB_ETYPE_DSA_SIGN
	KERB_ETYPE_NULL
	KERB_ETYPE_PKCS7_PUB
	KERB_ETYPE_RC4_HMAC_NT
	KERB_ETYPE_RC4_HMAC_NT_EXP
	KERB_ETYPE_RC4_HMAC_OLD
	KERB_ETYPE_RC4_HMAC_OLD_EXP
	KERB_ETYPE_RC4_LM
	KERB_ETYPE_RC4_MD4
	KERB_ETYPE_RC4_PLAIN
	KERB_ETYPE_RC4_PLAIN_EXP
	KERB_ETYPE_RC4_PLAIN_OLD
	KERB_ETYPE_RC4_PLAIN_OLD_EXP
	KERB_ETYPE_RC4_PLAIN2
	KERB_ETYPE_RC4_SHA
	KERB_ETYPE_RSA_PRIV
	KERB_ETYPE_RSA_PUB
	KERB_ETYPE_RSA_PUB_MD5
	KERB_ETYPE_RSA_PUB_SHA1
	KERB_RETRIEVE_TICKET_DONT_USE_CACHE
	KERB_RETRIEVE_TICKET_USE_CACHE_ONLY
	KERB_WRAP_NO_ENCRYPT
	KERBEROS_REVISION
	KERBEROS_VERSION

	KerbInteractiveLogon
	KerbSmartCardLogon

	KerbInteractiveProfile
	KerbSmartCardProfile

	LG_INCLUDE_INDIRECT

	LOGON_CACHED_ACCOUNT
	LOGON_EXTRA_SIDS
	LOGON_GRACE_LOGON
	LOGON_GUEST
	LOGON_NOENCRYPTION
	LOGON_PROFILE_PATH_RETURNED
	LOGON_RESOURCE_GROUPS
	LOGON_SERVER_TRUST_ACCOUNT
	LOGON_SUBAUTH_SESSION_KEY
	LOGON_USED_LM_PASSWORD

	LSA_MODE_INDIVIDUAL_ACCOUNTS
	LSA_MODE_LOG_FULL
	LSA_MODE_MANDATORY_ACCESS
	LSA_MODE_PASSWORD_PROTECTED

	MAJOR_VERSION_MASK

	MsV1_0InteractiveLogon
	MsV1_0Lm20Logon
	MsV1_0NetworkLogon
	MsV1_0SubAuthLogon

	MsV1_0InteractiveProfile
	MsV1_0Lm20LogonProfile
	MsV1_0SmartCardProfile

	MsV1_0EnumerateUsers
	MsV1_0CacheLogon
	MsV1_0CacheLookup
	MsV1_0ChangeCachedPassword
	MsV1_0ChangePassword
	MsV1_0DeriveCredential
	MsV1_0GenericPassthrough
	MsV1_0GetUserInfo
	MsV1_0Lm20ChallengeRequest
	MsV1_0Lm20GetChallengeResponse
	MsV1_0ReLogonUsers
	MsV1_0SubAuth

	MSV1_0_CHALLENGE_LENGTH
	MSV1_0_USER_SESSION_KEY_LENGTH
	MSV1_0_LANMAN_SESSION_KEY_LENGTH

	MSV1_0_ALLOW_SERVER_TRUST_ACCOUNT
	MSV1_0_ALLOW_WORKSTATION_TRUST_ACCOUNT
	MSV1_0_CLEARTEXT_PASSWORD_ALLOWED
	MSV1_0_DERIVECRED_TYPE_SHA1
	MSV1_0_DONT_TRY_GUEST_ACCOUNT
	MSV1_0_RETURN_PASSWORD_EXPIRY
	MSV1_0_RETURN_PROFILE_PATH
	MSV1_0_RETURN_USER_PARAMETERS
	MSV1_0_SUBAUTHENTICATION_DLL_EX
	MSV1_0_TRY_GUEST_ACCOUNT_ONLY
	MSV1_0_TRY_SPECIFIED_DOMAIN_ONLY
	MSV1_0_UPDATE_LOGON_STATISTICS

	MSV1_0_MNS_LOGON
	MSV1_0_SUBAUTHENTICATION_DLL
	MSV1_0_SUBAUTHENTICATION_DLL_SHIFT

	MSV1_0_SUBAUTHENTICATION_DLL_IIS
	MSV1_0_SUBAUTHENTICATION_DLL_RAS

	MSV1_0_SUBAUTHENTICATION_FLAGS

	MSV1_0_CRED_LM_PRESENT
	MSV1_0_CRED_NT_PRESENT
	MSV1_0_CRED_VERSION
	MSV1_0_OWF_PASSWORD_LENGTH

	MSV1_0_NTLM3_OWF_LENGTH
	MSV1_0_NTLM3_RESPONSE_LENGTH

	MSV1_0_MAX_AVL_SIZE
	MSV1_0_MAX_NTLM3_LIFE

	MSV1_0_NTLM3_INPUT_LENGTH

	MsvAvEOL
	MsvAvNbComputerName
	MsvAvNbDomainName
	MsvAvDnsDomainName
	MsvAvDnsServerName

	NegCallPackageMax
	NegEnumPackagePrefixes

	NEGOTIATE_MAX_PREFIX

	NETLOGON_CONTROL_BACKUP_CHANGE_LOG
	NETLOGON_CONTROL_BREAKPOINT
	NETLOGON_CONTROL_FIND_USER
	NETLOGON_CONTROL_PDC_REPLICATE
	NETLOGON_CONTROL_QUERY
	NETLOGON_CONTROL_REDISCOVER
	NETLOGON_CONTROL_REPLICATE
	NETLOGON_CONTROL_SET_DBFLAG
	NETLOGON_CONTROL_SYNCHRONIZE
	NETLOGON_CONTROL_TC_QUERY
	NETLOGON_CONTROL_TRANSPORT_NOTIFY
	NETLOGON_CONTROL_TRUNCATE_LOG
	NETLOGON_CONTROL_UNLOAD_NETLOGON_DLL
	NETLOGON_FULL_SYNC_REPLICATION
	NETLOGON_REDO_NEEDED
	NETLOGON_REPLICATION_IN_PROGRESS
	NETLOGON_REPLICATION_NEEDED

	NetSetupDnsMachine
	NetSetupDomain
	NetSetupDomainName
	NetSetupMachine
	NetSetupNonExistentDomain
	NetSetupUnjoined
	NetSetupUnknown
	NetSetupUnknownStatus
	NetSetupWorkgroup
	NetSetupWorkgroupName

	NETSETUP_ACCT_CREATE
	NETSETUP_ACCT_DELETE
	NETSETUP_DOMAIN_JOIN_IF_JOINED
	NETSETUP_INSTALL_INVOCATION
	NETSETUP_JOIN_DOMAIN
	NETSETUP_JOIN_UNSECURE
	NETSETUP_WIN9X_UPGRADE

	NETPROPERTY_PERSISTENT

	Network

	NO_PERMISSION_REQUIRED

	ONE_DAY

	OWNER_SECURITY_INFORMATION

	PERM_FILE_CREATE
	PERM_FILE_READ
	PERM_FILE_WRITE

	POLICY_AUDIT_EVENT_FAILURE
	POLICY_AUDIT_EVENT_NONE
	POLICY_AUDIT_EVENT_MASK
	POLICY_AUDIT_EVENT_NONE
	POLICY_AUDIT_EVENT_SUCCESS
	POLICY_AUDIT_EVENT_UNCHANGED

	POLICY_ALL_ACCESS
	POLICY_AUDIT_LOG_ADMIN
	POLICY_CREATE_ACCOUNT
	POLICY_CREATE_PRIVILEGE
	POLICY_CREATE_SECRET
	POLICY_EXECUTE
	POLICY_GET_PRIVATE_INFORMATION
	POLICY_LOOKUP_NAMES
	POLICY_NOTIFICATION
	POLICY_READ
	POLICY_SERVER_ADMIN
	POLICY_SET_AUDIT_REQUIREMENTS
	POLICY_SET_DEFAULT_QUOTA_LIMITS
	POLICY_TRUST_ADMIN
	POLICY_VIEW_AUDIT_INFORMATION
	POLICY_VIEW_LOCAL_INFORMATION
	POLICY_WRITE

	POLICY_QOS_ALLOW_LOCAL_ROOT_CERT_STORE
	POLICY_QOS_DHCP_SERVER_ALLOWED
	POLICY_QOS_INBOUND_CONFIDENTIALITY
	POLICY_QOS_INBOUND_INTEGRITY
	POLICY_QOS_OUTBOUND_CONFIDENTIALITY
	POLICY_QOS_OUTBOUND_INTEGRITY
	POLICY_QOS_RAS_SERVER_ALLOWED
	POLICY_QOS_SCHANNEL_REQUIRED

	PolicyAccountDomainInformation
	PolicyAuditEventsInformation
	PolicyAuditFullQueryInformation
	PolicyAuditFullSetInformation
	PolicyAuditLogInformation
	PolicyDefaultQuotaInformation
	PolicyDnsDomainInformation
	PolicyLsaServerRoleInformation
	PolicyModificationInformation
	PolicyPdAccountInformation
	PolicyPrimaryDomainInformation
	PolicyReplicaSourceInformation

	PolicyDomainEfsInformation
	PolicyDomainKerberosTicketInformation
	PolicyDomainQualityOfServiceInformation

	PolicyNotifyAccountDomainInformation
	PolicyNotifyAuditEventsInformation
	PolicyNotifyDnsDomainInformation
	PolicyNotifyDomainEfsInformation
	PolicyNotifyDomainKerberosTicketInformation
	PolicyNotifyMachineAccountPasswordInformation
	PolicyNotifyServerRoleInformation

	PolicyServerDisabled
	PolicyServerEnabled
	PolicyServerRoleBackup
	PolicyServerRolePrimary

	Proxy

	REMOTE_NAME_INFO_LEVEL

	REPL_EXTENT_FILE
	REPL_EXTENT_TREE
	REPL_INTEGRITY_TREE
	REPL_INTEGRITY_FILE
	REPL_ROLE_BOTH
	REPL_ROLE_EXPORT
	REPL_ROLE_IMPORT
	REPL_STATE_OK
	REPL_STATE_NO_MASTER
	REPL_STATE_NO_SYNC
	REPL_STATE_NEVER_REPLICATED
	REPL_UNLOCK_FORCE
	REPL_UNLOCK_NOFORCE

	RESOURCEUSAGE_ALL
	RESOURCE_CONNECTED
	RESOURCE_CONTEXT
	RESOURCE_GLOBALNET
	RESOURCE_REMEMBERED
	RESOURCETYPE_RESERVED
	RESOURCETYPE_UNKNOWN
	RESOURCETYPE_ANY
	RESOURCETYPE_DISK
	RESOURCETYPE_PRINT
	RESOURCEDISPLAYTYPE_DIRECTORY
	RESOURCEDISPLAYTYPE_DOMAIN
	RESOURCEDISPLAYTYPE_FILE
	RESOURCEDISPLAYTYPE_GENERIC
	RESOURCEDISPLAYTYPE_GROUP
	RESOURCEDISPLAYTYPE_NDSCONTAINER
	RESOURCEDISPLAYTYPE_NETWORK
	RESOURCEDISPLAYTYPE_ROOT
	RESOURCEDISPLAYTYPE_SERVER
	RESOURCEDISPLAYTYPE_SHARE
	RESOURCEDISPLAYTYPE_SHAREADMIN
	RESOURCEDISPLAYTYPE_TREE
	RESOURCEUSAGE_ALL
	RESOURCEUSAGE_CONNECTABLE
	RESOURCEUSAGE_CONTAINER
	RESOURCEUSAGE_ATTACHED
	RESOURCEUSAGE_NOLOCALDEVICE
	RESOURCEUSAGE_RESERVED
	RESOURCEUSAGE_SIBLING

	SACL_SECURITY_INFORMATION

	SE_GROUP_ENABLED_BY_DEFAULT
	SE_GROUP_MANDATORY
	SE_GROUP_OWNER

	SE_CREATE_TOKEN_NAME
	SE_ASSIGNPRIMARYTOKEN_NAME
	SE_LOCK_MEMORY_NAME
	SE_INCREASE_QUOTA_NAME
	SE_UNSOLICITED_INPUT_NAME
	SE_MACHINE_ACCOUNT_NAME
	SE_TCB_NAME
	SE_SECURITY_NAME
	SE_TAKE_OWNERSHIP_NAME
	SE_LOAD_DRIVER_NAME
	SE_SYSTEM_PROFILE_NAME
	SE_SYSTEMTIME_NAME
	SE_PROF_SINGLE_PROCESS_NAME
	SE_INC_BASE_PRIORITY_NAME
	SE_CREATE_PAGEFILE_NAME
	SE_CREATE_PERMANENT_NAME
	SE_BACKUP_NAME
	SE_RESTORE_NAME
	SE_SHUTDOWN_NAME
	SE_DEBUG_NAME
	SE_AUDIT_NAME
	SE_SYSTEM_ENVIRONMENT_NAME
	SE_CHANGE_NOTIFY_NAME
	SE_REMOTE_SHUTDOWN_NAME
	SE_INTERACTIVE_LOGON_NAME
	SE_DENY_INTERACTIVE_LOGON_NAME
	SE_NETWORK_LOGON_NAME
	SE_DENY_NETWORK_LOGON_NAME
	SE_BATCH_LOGON_NAME
	SE_DENY_BATCH_LOGON_NAME
	SE_SERVICE_LOGON_NAME
	SE_DENY_SERVICE_LOGON_NAME

	Service

	SC_ACTION_NONE
	SC_ACTION_REBOOT
	SC_ACTION_RESTART
	SC_ACTION_RUN_COMMAND

	SC_MANAGER_ALL_ACCESS
	SC_MANAGER_CONNECT
	SC_MANAGER_CREATE_SERVICE
	SC_MANAGER_ENUMERATE_SERVICE
	SC_MANAGER_LOCK
	SC_MANAGER_MODIFY_BOOT_CONFIG
	SC_MANAGER_QUERY_LOCK_STATUS

	SC_STATUS_PROCESS_INFO

	SERVICE_ACCEPT_STOP
	SERVICE_ACCEPT_PAUSE_CONTINUE
	SERVICE_ACCEPT_SHUTDOWN
	SERVICE_ACCEPT_PARAMCHANGE
	SERVICE_ACCEPT_NETBINDCHANGE
	SERVICE_ACCEPT_HARDWAREPROFILECHANGE
	SERVICE_ACCEPT_POWEREVENT

	SERVICE_FILE_SYSTEM_DRIVER
	SERVICE_INTERACTIVE_PROCESS
	SERVICE_KERNEL_DRIVER
	SERVICE_WIN32_OWN_PROCESS
	SERVICE_WIN32_SHARE_PROCESS

	SERVICE_AUTO_START
	SERVICE_BOOT_START
	SERVICE_DEMAND_START
	SERVICE_DISABLED
	SERVICE_SYSTEM_START

	SERVICE_ERROR_CRITICAL
	SERVICE_ERROR_IGNORE
	SERVICE_ERROR_NORMAL
	SERVICE_ERROR_SEVERE

	SERVICE_CONTINUE_PENDING
	SERVICE_PAUSE_PENDING
	SERVICE_PAUSED
	SERVICE_RUNNING
	SERVICE_START_PENDING
	SERVICE_STOPPED
	SERVICE_STOP_PENDING

	SERVICE_ALL_ACCESS
	SERVICE_CHANGE_CONFIG
	SERVICE_ENUMERATE_DEPENDENTS
	SERVICE_INTERROGATE
	SERVICE_PAUSE_CONTINUE
	SERVICE_QUERY_CONFIG
	SERVICE_QUERY_STATUS
	SERVICE_START
	SERVICE_STOP
	SERVICE_USER_DEFINED_CONTROL

	SERVICE_RUNS_IN_SYSTEM_PROCESS

	SERVICE_CONTROL_CONTINUE
	SERVICE_CONTROL_DEVICEEVENT
	SERVICE_CONTROL_HARDWAREPROFILECHANGE
	SERVICE_CONTROL_INTERROGATE
	SERVICE_CONTROL_NETBINDADD
	SERVICE_CONTROL_NETBINDDISABLE
	SERVICE_CONTROL_NETBINDENABLE
	SERVICE_CONTROL_NETBINDREMOVE
	SERVICE_CONTROL_PAUSE
	SERVICE_CONTROL_PARAMCHANGE
	SERVICE_CONTROL_POWEREVENT
	SERVICE_CONTROL_SHUTDOWN
	SERVICE_CONTROL_STOP

	SERVICE_CONFIG_FAILURE_ACTIONS

	SERVICE_NO_CHANGE
	SERVICE_ACTIVE
	SERVICE_DRIVER
	SERVICE_INACTIVE
	SERVICE_STATE_ALL
	SERVICE_WIN32

	STYPE_DEVICE
	STYPE_DISKTREE
	STYPE_IPC
	STYPE_PRINTQ

	SUPPORTS_ANY
	SUPPORTS_LOCAL
	SUPPORTS_REMOTE_ADMIN_PROTOCOL
	SUPPORTS_RPC
	SUPPORTS_SAM_PROTOCOL
	SUPPORTS_UNICODE

	SV_HIDDEN
	SV_MAX_CMD_LEN
	SV_MAX_SRV_HEUR_LEN
	SV_NODISC
	SV_PLATFORM_ID_OS2
	SV_PLATFORM_ID_NT
	SV_SHARESECURITY
	SV_TYPE_AFP
	SV_TYPE_ALL
	SV_TYPE_ALTERNATE_XPORT
	SV_TYPE_BACKUP_BROWSER
	SV_TYPE_CLUSTER_NT
	SV_TYPE_DCE
	SV_TYPE_DFS
	SV_TYPE_DIALIN_SERVER
	SV_TYPE_DOMAIN_BAKCTRL
	SV_TYPE_DOMAIN_CTRL
	SV_TYPE_DOMAIN_ENUM
	SV_TYPE_DOMAIN_MASTER
	SV_TYPE_DOMAIN_MEMBER
	SV_TYPE_LOCAL_LIST_ONLY
	SV_TYPE_MASTER_BROWSER
	SV_TYPE_NOVELL
	SV_TYPE_NT
	SV_TYPE_POTENTIAL_BROWSER
	SV_TYPE_PRINTQ_SERVER
	SV_TYPE_SERVER
	SV_TYPE_SERVER_MFPN
	SV_TYPE_SERVER_NT
	SV_TYPE_SERVER_OSF
	SV_TYPE_SERVER_UNIX
	SV_TYPE_SERVER_VMS
	SV_TYPE_SQLSERVER
	SV_TYPE_TERMINALSERVER
	SV_TYPE_TIME_SOURCE
	SV_TYPE_WFW
	SV_TYPE_WINDOWS
	SV_TYPE_WORKSTATION
	SV_TYPE_XENIX_SERVER

	SV_USERS_PER_LICENSE
	SV_USERSECURITY
	SV_VISIBLE

	SW_AUTOPROF_LOAD_MASK
	SW_AUTOPROF_SAVE_MASK

	TIMEQ_FOREVER

	TRUST_ATTRIBUTE_NON_TRANSITIVE
	TRUST_ATTRIBUTE_TREE_PARENT
	TRUST_ATTRIBUTE_TREE_ROOT
	TRUST_ATTRIBUTE_UPLEVEL_ONLY
	TRUST_ATTRIBUTES_USER
	TRUST_ATTRIBUTES_VALID

	TRUST_AUTH_TYPE_CLEAR
	TRUST_AUTH_TYPE_NONE
	TRUST_AUTH_TYPE_NT4OWF
	TRUST_AUTH_TYPE_VERSION

	TRUST_DIRECTION_BIDIRECTIONAL
	TRUST_DIRECTION_DISABLED
	TRUST_DIRECTION_INBOUND
	TRUST_DIRECTION_OUTBOUND

	TRUST_TYPE_DCE
	TRUST_TYPE_DOWNLEVEL
	TRUST_TYPE_MIT
	TRUST_TYPE_UPLEVEL

	TrustedControllersInformation
	TrustedDomainAuthInformation
	TrustedDomainFullInformation
	TrustedDomainInformationBasic
	TrustedDomainInformationEx
	TrustedDomainNameInformation
	TrustedPasswordInformation
	TrustedPosixOffsetInformation

	UAS_ROLE_STANDALONE
	UAS_ROLE_MEMBER
	UAS_ROLE_BACKUP
	UAS_ROLE_PRIMARY

	UF_ACCOUNT_TYPE_MASK
	UF_ACCOUNTDISABLE
	UF_DONT_EXPIRE_PASSWD
	UF_DONT_REQUIRE_PREAUTH
	UF_ENCRYPTED_TEXT_PASSWORD_ALLOWED
	UF_HOMEDIR_REQUIRED
	UF_INTERDOMAIN_TRUST_ACCOUNT
	UF_LOCKOUT
	UF_MACHINE_ACCOUNT_MASK
	UF_MNS_LOGON_ACCOUNT
	UF_NORMAL_ACCOUNT
	UF_NOT_DELEGATED
	UF_PASSWD_CANT_CHANGE
	UF_PASSWD_NOTREQD
	UF_SCRIPT
	UF_SERVER_TRUST_ACCOUNT
	UF_SETTABLE_BITS
	UF_SMARTCARD_REQUIRED
	UF_TEMP_DUPLICATE_ACCOUNT
	UF_TRUSTED_FOR_DELEGATION
	UF_USE_DES_KEY_ONLY
	UF_WORKSTATION_TRUST_ACCOUNT

	UNITS_PER_WEEK

	UNIVERSAL_NAME_INFO_LEVEL

	Unlock

	USE_FORCE
	USE_LOTS_OF_FORCE
	USE_NOFORCE

	USE_SPECIFIC_TRANSPORT

	USE_CHARDEV
	USE_CONN
	USE_DISCONN
	USE_DISKDEV
	USE_IPC
	USE_NETERR
	USE_OK
	USE_PAUSED
	USE_RECONN
	USE_SESSLOST
	USE_SPOOLDEV
	USE_WILDCARD

	USER_MAXSTORAGE_UNLIMITED

	USER_PRIV_ADMIN
	USER_PRIV_GUEST
	USER_PRIV_USER

	WNCON_DYNAMIC
	WNCON_FORNETCARD
	WNCON_NOTROUTED
	WNCON_SLOWLINK

	WNNC_CRED_MANAGER
	WNNC_NET_10NET
	WNNC_NET_3IN1
	WNNC_NET_9TILES
	WNNC_NET_APPLETALK
	WNNC_NET_AS400
	WNNC_NET_AVID
	WNNC_NET_BMC
	WNNC_NET_BWNFS
	WNNC_NET_CLEARCASE
	WNNC_NET_COGENT
	WNNC_NET_CSC
	WNNC_NET_DCE
	WNNC_NET_DECORB
	WNNC_NET_DISTINCT
	WNNC_NET_DOCUSPACE
	WNNC_NET_EXTENDNET
	WNNC_NET_FARALLON
	WNNC_NET_FJ_REDIR
	WNNC_NET_FTP_NFS
	WNNC_NET_FRONTIER
	WNNC_NET_HOB_NFS
	WNNC_NET_IBMAL
	WNNC_NET_INTERGRAPH
	WNNC_NET_LANMAN
	WNNC_NET_LANTASTIC
	WNNC_NET_LANSTEP
	WNNC_NET_LIFENET
	WNNC_NET_LOCUS
	WNNC_NET_MANGOSOFT
	WNNC_NET_MASFAX
	WNNC_NET_MSNET
	WNNC_NET_NETWARE
	WNNC_NET_OBJECT_DIRE
	WNNC_NET_PATHWORKS
	WNNC_NET_POWERLAN
	WNNC_NET_PROTSTOR
	WNNC_NET_RDR2SAMPLE
	WNNC_NET_SERNET
	WNNC_NET_SHIVA
	WNNC_NET_SUN_PC_NFS
	WNNC_NET_SYMFONET
	WNNC_NET_TWINS
	WNNC_NET_VINES

	WTS_CURRENT_SERVER
	WTS_CURRENT_SERVER_HANDLE
	WTS_CURRENT_SERVER_NAME
	WTS_CURRENT_SESSION

	WTS_EVENT_NONE
	WTS_EVENT_CREATE
	WTS_EVENT_DELETE
	WTS_EVENT_RENAME
	WTS_EVENT_CONNECT
	WTS_EVENT_DISCONNECT
	WTS_EVENT_LOGON
	WTS_EVENT_LOGOFF
	WTS_EVENT_STATECHANGE
	WTS_EVENT_LICENSE
	WTS_EVENT_ALL
	WTS_EVENT_FLUSH

	WTS_WSD_FASTREBOOT
	WTS_WSD_LOGOFF
	WTS_WSD_POWEROFF
	WTS_WSD_REBOOT
	WTS_WSD_SHUTDOWN

	WTSActive
	WTSConnected
	WTSConnectQuery
	WTSShadow
	WTSDisconnected
	WTSIdle
	WTSListen
	WTSReset
	WTSDown
	WTSInit

	WTSApplicationName
	WTSClientAddress
	WTSClientBuildNumber
	WTSClientDirectory
	WTSClientDisplay
	WTSClientHardwareId
	WTSClientName
	WTSClientProductId
	WTSConnectState
	WTSDomainName
	WTSInitialProgram
	WTSOEMId
	WTSSessionId
	WTSUserName
	WTSWinStationName
	WTSWorkingDirectory

	WTSUserConfigInitialProgram
	WTSUserConfigWorkingDirectory
	WTSUserConfigfInheritInitialProgram
	WTSUserConfigfAllowLogonTerminalServer
	WTSUserConfigTimeoutSettingsConnections
	WTSUserConfigTimeoutSettingsDisconnections
	WTSUserConfigTimeoutSettingsIdle
	WTSUserConfigfDeviceClientDrives
	WTSUserConfigfDeviceClientPrinters
	WTSUserConfigfDeviceClientDefaultPrinter
	WTSUserConfigBrokenTimeoutSettings
	WTSUserConfigReconnectSettings
	WTSUserConfigModemCallbackSettings
	WTSUserConfigModemCallbackPhoneNumber
	WTSUserConfigShadowingSettings
	WTSUserConfigTerminalServerProfilePath
	WTSUserConfigTerminalServerHomeDir
	WTSUserConfigTerminalServerHomeDirDrive
	WTSUserConfigfTerminalServerRemoteHomeDir

);

@EXPORT_OK = qw(
	DACL_SECURITY_INFORMATION
	GROUP_SECURITY_INFORMATION
	OWNER_SECURITY_INFORMATION
	SACL_SECURITY_INFORMATION
);

%EXPORT_TAGS = 
	( WIN32_MOD => [ @EXPORT_OK ],
	);

sub AUTOLOAD
{
		# This AUTOLOAD is used to 'autoload' constants from the constant()
		# XS function.	If a constant is not found then control is passed
		# to the AUTOLOAD in AutoLoader.

		local($constname);
		
		($constname = $AUTOLOAD) =~ s/.*:://;
		
		#reset $! to zero to reset any current errors.
		$!=0;
		
		$val = constant($constname, @_ ? $_[0] : 0);
		
		if ($! != 0)
		{
				if ($! =~ /Invalid/)
				{
						$AutoLoader::AUTOLOAD = $AUTOLOAD;
						goto &AutoLoader::AUTOLOAD;
				}
				else
				{
						my ($file,$line) = (caller)[1,2];
						die "Your vendor has not defined $Package macro $constname, used in $file at line $line.";
				}
		}
		
		eval "sub $AUTOLOAD { $val }";
		
		goto &$AUTOLOAD;
}

sub LogonControlQuery {Win32::Lanman::I_NetLogonControl2($_[0], &NETLOGON_CONTROL_QUERY, '', $_[1]);}
sub LogonControlReplicate {Win32::Lanman::I_NetLogonControl2($_[0], &NETLOGON_CONTROL_REPLICATE, '', $_[1]);}
sub LogonControlSynchronize {Win32::Lanman::I_NetLogonControl2($_[0], &NETLOGON_CONTROL_SYNCHRONIZE, '', $_[1]);}
sub LogonControlPdcReplicate {Win32::Lanman::I_NetLogonControl2($_[0], &NETLOGON_CONTROL_PDC_REPLICATE, '', $_[1]);}
sub LogonControlRediscover {Win32::Lanman::I_NetLogonControl2($_[0], &NETLOGON_CONTROL_REDISCOVER, $_[1], $_[2]);}
sub LogonControlTCQuery {Win32::Lanman::I_NetLogonControl2($_[0], &NETLOGON_CONTROL_TC_QUERY, $_[1], $_[2]);}
sub LogonControlTransportNotify {Win32::Lanman::I_NetLogonControl2($_[0], &NETLOGON_CONTROL_TRANSPORT_NOTIFY, '', $_[1]);}
sub LogonControlFindUser {Win32::Lanman::I_NetLogonControl2($_[0], &NETLOGON_CONTROL_FIND_USER, $_[1], $_[2]);}

sub LsaQueryAuditLogPolicy {Win32::Lanman::LsaQueryInformationPolicy($_[0], &PolicyAuditLogInformation, $_[1]);}
sub LsaQueryAuditEventsPolicy {Win32::Lanman::LsaQueryInformationPolicy($_[0], &PolicyAuditEventsInformation, $_[1]);}
sub LsaSetAuditEventsPolicy {Win32::Lanman::LsaSetInformationPolicy($_[0], &PolicyAuditEventsInformation, $_[1]);}
sub LsaQueryPrimaryDomainPolicy {Win32::Lanman::LsaQueryInformationPolicy($_[0], &PolicyPrimaryDomainInformation, $_[1]);}
sub LsaSetPrimaryDomainPolicy {Win32::Lanman::LsaSetInformationPolicy($_[0], &PolicyPrimaryDomainInformation, $_[1]);}
sub LsaQueryPdAccountPolicy {Win32::Lanman::LsaQueryInformationPolicy($_[0], &PolicyPdAccountInformation, $_[1]);}
sub LsaQueryAccountDomainPolicy {Win32::Lanman::LsaQueryInformationPolicy($_[0], &PolicyAccountDomainInformation, $_[1]);}
sub LsaSetAccountDomainPolicy {Win32::Lanman::LsaSetInformationPolicy($_[0], &PolicyAccountDomainInformation, $_[1]);}
sub LsaQueryServerRolePolicy {Win32::Lanman::LsaQueryInformationPolicy($_[0], &PolicyLsaServerRoleInformation, $_[1]);}
sub LsaSetServerRolePolicy {Win32::Lanman::LsaSetInformationPolicy($_[0], &PolicyLsaServerRoleInformation, $_[1]);}
sub LsaQueryReplicaSourcePolicy {Win32::Lanman::LsaQueryInformationPolicy($_[0], &PolicyLsaReplicaSourceInformation, $_[1]);}
sub LsaSetReplicaSourcePolicy {Win32::Lanman::LsaSetInformationPolicy($_[0], &PolicyLsaReplicaSourceInformation, $_[1]);}
sub LsaQueryDefaultQuotaPolicy {Win32::Lanman::LsaQueryInformationPolicy($_[0], &PolicyDefaultQuotaInformation, $_[1]);}
sub LsaSetDefaultQuotaPolicy {Win32::Lanman::LsaSetInformationPolicy($_[0], &PolicyDefaultQuotaInformation, $_[1]);}
sub LsaQueryAuditFullPolicy {Win32::Lanman::LsaQueryInformationPolicy($_[0], &PolicyAuditFullQueryInformation, $_[1]);}
sub LsaSetAuditFullPolicy {Win32::Lanman::LsaSetInformationPolicy($_[0], &PolicyAuditFullSetInformation, $_[1]);}
sub LsaQueryDnsDomainPolicy {Win32::Lanman::LsaQueryInformationPolicy($_[0], &PolicyDnsDomainInformation, $_[1]);}
sub LsaSetDnsDomainPolicy {Win32::Lanman::LsaSetInformationPolicy($_[0], &PolicyDnsDomainInformation, $_[1]);}

sub LsaQueryTrustedDomainNameInfo {Win32::Lanman::LsaQueryTrustedDomainInfo($_[0], $_[1], &TrustedDomainNameInformation, $_[2]);}
sub LsaQueryTrustedPosixOffsetInfo {Win32::Lanman::LsaQueryTrustedDomainInfo($_[0], $_[1], &TrustedPosixOffsetInformation, $_[2]);}
sub LsaQueryTrustedPasswordInfo {Win32::Lanman::LsaQueryTrustedDomainInfo($_[0], $_[1], &TrustedPasswordInformation, $_[2]);}

sub LsaSetTrustedDomainInfo {Win32::Lanman::LsaSetTrustedDomainInformation(@_);}
sub LsaSetTrustedDomainNameInfo {Win32::Lanman::LsaSetTrustedDomainInformation($_[0], $_[1], &TrustedDomainNameInformation, $_[2]);}
sub LsaSetTrustedPosixOffsetInfo {Win32::Lanman::LsaSetTrustedDomainInformation($_[0], $_[1], &TrustedPosixOffsetInformation, $_[2]);}
sub LsaSetTrustedPasswordInfo {Win32::Lanman::LsaSetTrustedDomainInformation($_[0], $_[1], &TrustedPasswordInformation, $_[2]);}

sub SE_CREATE_TOKEN_NAME {"SeCreateTokenPrivilege";}
sub SE_ASSIGNPRIMARYTOKEN_NAME {"SeAssignPrimaryTokenPrivilege";}
sub SE_LOCK_MEMORY_NAME {"SeLockMemoryPrivilege";}
sub SE_INCREASE_QUOTA_NAME {"SeIncreaseQuotaPrivilege";}
sub SE_UNSOLICITED_INPUT_NAME {"SeUnsolicitedInputPrivilege";}
sub SE_MACHINE_ACCOUNT_NAME {"SeMachineAccountPrivilege";}
sub SE_TCB_NAME {"SeTcbPrivilege";}
sub SE_SECURITY_NAME {"SeSecurityPrivilege";}
sub SE_TAKE_OWNERSHIP_NAME {"SeTakeOwnershipPrivilege";}
sub SE_LOAD_DRIVER_NAME {"SeLoadDriverPrivilege";}
sub SE_SYSTEM_PROFILE_NAME {"SeSystemProfilePrivilege";}
sub SE_SYSTEMTIME_NAME {"SeSystemtimePrivilege";}
sub SE_PROF_SINGLE_PROCESS_NAME {"SeProfileSingleProcessPrivilege";}
sub SE_INC_BASE_PRIORITY_NAME {"SeIncreaseBasePriorityPrivilege";}
sub SE_CREATE_PAGEFILE_NAME {"SeCreatePagefilePrivilege";}
sub SE_CREATE_PERMANENT_NAME {"SeCreatePermanentPrivilege";}
sub SE_BACKUP_NAME {"SeBackupPrivilege";}
sub SE_RESTORE_NAME {"SeRestorePrivilege";}
sub SE_SHUTDOWN_NAME {"SeShutdownPrivilege";}
sub SE_DEBUG_NAME {"SeDebugPrivilege";}
sub SE_AUDIT_NAME {"SeAuditPrivilege";}
sub SE_SYSTEM_ENVIRONMENT_NAME {"SeSystemEnvironmentPrivilege";}
sub SE_CHANGE_NOTIFY_NAME {"SeChangeNotifyPrivilege";}
sub SE_REMOTE_SHUTDOWN_NAME {"SeRemoteShutdownPrivilege";}
sub SE_INTERACTIVE_LOGON_NAME {"SeInteractiveLogonRight";}
sub SE_DENY_INTERACTIVE_LOGON_NAME {"SeDenyInteractiveLogonRight";}
sub SE_NETWORK_LOGON_NAME {"SeNetworkLogonRight";}
sub SE_DENY_NETWORK_LOGON_NAME {"SeDenyNetworkLogonRight";}
sub SE_BATCH_LOGON_NAME {"SeBatchLogonRight";}
sub SE_DENY_BATCH_LOGON_NAME {"SeDenyBatchLogonRight";}
sub SE_SERVICE_LOGON_NAME {"SeServiceLogonRight";}
sub SE_DENY_SERVICE_LOGON_NAME {"SeDenyServiceLogonRight";}

sub SAM_PASSWORD_CHANGE_NOTIFY_ROUTINE {"PasswordChangeNotify";}
sub SAM_INIT_NOTIFICATION_ROUTINE{"InitializeChangeNotify";}
sub SAM_PASSWORD_FILTER_ROUTINE{"PasswordFilter";}

sub MSV1_0_PACKAGE_NAME{"MICROSOFT_AUTHENTICATION_PACKAGE_V1_0";}
sub MSV1_0_SUBAUTHENTICATION_KEY{"SYSTEM\\CurrentControlSet\\Control\\Lsa\\MSV1_0";}
sub MSV1_0_SUBAUTHENTICATION_VALUE{"Auth";}

sub MICROSOFT_KERBEROS_NAME{"Kerberos";}

sub WTSUserConfigAll
{
	return (&Win32::Lanman::WTSUserConfigInitialProgram, &Win32::Lanman::WTSUserConfigWorkingDirectory,
		&Win32::Lanman::WTSUserConfigfInheritInitialProgram, &Win32::Lanman::WTSUserConfigfAllowLogonTerminalServer,
		&Win32::Lanman::WTSUserConfigTimeoutSettingsConnections, &Win32::Lanman::WTSUserConfigTimeoutSettingsDisconnections,
		&Win32::Lanman::WTSUserConfigTimeoutSettingsIdle, &Win32::Lanman::WTSUserConfigfDeviceClientDrives,
		&Win32::Lanman::WTSUserConfigfDeviceClientPrinters, &Win32::Lanman::WTSUserConfigfDeviceClientDefaultPrinter,
		&Win32::Lanman::WTSUserConfigBrokenTimeoutSettings, &Win32::Lanman::WTSUserConfigReconnectSettings,
		&Win32::Lanman::WTSUserConfigModemCallbackSettings, &Win32::Lanman::WTSUserConfigModemCallbackPhoneNumber,
		&Win32::Lanman::WTSUserConfigShadowingSettings, &Win32::Lanman::WTSUserConfigTerminalServerProfilePath,
		&Win32::Lanman::WTSUserConfigTerminalServerHomeDir, &Win32::Lanman::WTSUserConfigTerminalServerHomeDirDrive,
		&Win32::Lanman::WTSUserConfigfTerminalServerRemoteHomeDir);
}

sub WTSInfoClassAll
{
	return (&Win32::Lanman::WTSApplicationName, &Win32::Lanman::WTSClientAddress,
		&Win32::Lanman::WTSClientBuildNumber, &Win32::Lanman::WTSClientDirectory,
		&Win32::Lanman::WTSClientDisplay, &Win32::Lanman::WTSClientHardwareId,
		&Win32::Lanman::WTSClientName, &Win32::Lanman::WTSClientProductId,
		&Win32::Lanman::WTSConnectState, &Win32::Lanman::WTSDomainName,
		&Win32::Lanman::WTSInitialProgram, &Win32::Lanman::WTSOEMId,
		&Win32::Lanman::WTSSessionId, &Win32::Lanman::WTSUserName,
		&Win32::Lanman::WTSWinStationName, &Win32::Lanman::WTSWorkingDirectory);
}

sub SV_TYPES 
{
	return (afp_server				=>	&Win32::Lanman::SV_TYPE_AFP,
		all					=>	&Win32::Lanman::SV_TYPE_ALL,
		alternate_transports			=>	&Win32::Lanman::SV_TYPE_ALTERNATE_XPORT,
		backup_browser				=>	&Win32::Lanman::SV_TYPE_BACKUP_BROWSER,
		cluster_server				=>	&Win32::Lanman::SV_TYPE_CLUSTER_NT,
		dce_server				=>	&Win32::Lanman::SV_TYPE_DCE,
		dfs_server				=>	&Win32::Lanman::SV_TYPE_DFS,
		dialup_server				=>	&Win32::Lanman::SV_TYPE_DIALIN_SERVER,
		bdc					=>	&Win32::Lanman::SV_TYPE_DOMAIN_BAKCTRL,
		dc					=>	&Win32::Lanman::SV_TYPE_DOMAIN_CTRL,
		backup_domain_controller		=>	&Win32::Lanman::SV_TYPE_DOMAIN_BAKCTRL,
		domain_controller			=>	&Win32::Lanman::SV_TYPE_DOMAIN_CTRL,
		primary_domain				=>	&Win32::Lanman::SV_TYPE_DOMAIN_ENUM,
		primary_domain_controller		=>	&Win32::Lanman::SV_TYPE_DOMAIN_MASTER,
		pdc					=>	&Win32::Lanman::SV_TYPE_DOMAIN_MASTER,
		lanmanager_domain_member		=>	&Win32::Lanman::SV_TYPE_DOMAIN_MEMBER,
		local_browser				=>	&Win32::Lanman::SV_TYPE_LOCAL_LIST_ONLY,
		master_browser				=>	&Win32::Lanman::SV_TYPE_MASTER_BROWSER,
		novell					=>	&Win32::Lanman::SV_TYPE_NOVELL,
		nt_server				=>	&Win32::Lanman::SV_TYPE_NT,
		potential_browser			=>	&Win32::Lanman::SV_TYPE_POTENTIAL_BROWSER,
		print_server				=>	&Win32::Lanman::SV_TYPE_PRINTQ_SERVER,
		server					=>	&Win32::Lanman::SV_TYPE_SERVER,
		file_and_print_server_for_netware	=>	&Win32::Lanman::SV_TYPE_SERVER_MFPN,
		nt					=>	&Win32::Lanman::SV_TYPE_SERVER_NT,
		osf					=>	&Win32::Lanman::SV_TYPE_SERVER_OSF,
		unix					=>	&Win32::Lanman::SV_TYPE_SERVER_UNIX,
		vms					=>	&Win32::Lanman::SV_TYPE_SERVER_VMS,
		sql_server				=>	&Win32::Lanman::SV_TYPE_SQLSERVER,
		terminal_server				=>	&Win32::Lanman::SV_TYPE_TERMINALSERVER,
		time_server				=>	&Win32::Lanman::SV_TYPE_TIME_SOURCE,
		wfw					=>	&Win32::Lanman::SV_TYPE_WFW,
		windows_for_workgroups			=>	&Win32::Lanman::SV_TYPE_WFW,
		windows					=>	&Win32::Lanman::SV_TYPE_WINDOWS,
		workstation				=>	&Win32::Lanman::SV_TYPE_WORKSTATION,
		xenix_server				=>	&Win32::Lanman::SV_TYPE_XENIX_SERVER);	
}

sub SERVICE_STATES
{
	return (active_services		=>	&Win32::Lanman::SERVICE_ACTIVE,
		inactive_services	=>	&Win32::Lanman::SERVICE_INACTIVE, 
		all			=>	&Win32::Lanman::SERVICE_STATE_ALL);
}

sub WTS_STATES
{
	return (all		=>	&Win32::Lanman::WTS_EVENT_ALL,
		connect		=>	&Win32::Lanman::WTS_EVENT_CONNECT,
    	  	create		=>	&Win32::Lanman::WTS_EVENT_CREATE,
	    	delete		=>	&Win32::Lanman::WTS_EVENT_DELETE,
		disconnect	=>	&Win32::Lanman::WTS_EVENT_DISCONNECT,
		flush		=>	&Win32::Lanman::WTS_EVENT_FLUSH,
		license		=>	&Win32::Lanman::WTS_EVENT_LICENSE,
		logoff		=>	&Win32::Lanman::WTS_EVENT_LOGOFF,
		logon		=>	&Win32::Lanman::WTS_EVENT_LOGON,
		none		=>	&Win32::Lanman::WTS_EVENT_NONE,
		rename		=>	&Win32::Lanman::WTS_EVENT_RENAME,
		state_change	=>	&Win32::Lanman::WTS_EVENT_STATECHANGE);
}

sub SERVICE_FAILURE_ACTIONS
{
	return (none		=>	&Win32::Lanman::SC_ACTION_NONE,
		reboot	        => 	&Win32::Lanman::SC_ACTION_REBOOT,
		restart	        =>	&Win32::Lanman::SC_ACTION_RESTART,
		ren_command	=>      &Win32::Lanman::SC_ACTION_RUN_COMMAND);
}

sub SERVICE_STATE_DESCRIPTIONS 
{ 
  return (&Win32::Lanman::SERVICE_STOPPED      => 'The service is not running.', 
	  &Win32::Lanman::SERVICE_START_PENDING  => 'The service is starting.',
	  &Win32::Lanman::SERVICE_STOP_PENDING   => 'The service is stopping.',
	  &Win32::Lanman::SERVICE_RUNNING        => 'The service is running.',
	  &Win32::Lanman::SERVICE_CONTINUE_PENDING => 'The service continue is pending.',
	  &Win32::Lanman::SERVICE_PAUSE_PENDING  => 'The service pause is pending.',
	  &Win32::Lanman::SERVICE_PAUSED         => 'The service is paused.');
}

sub NET_STATUS_DESCRIPTION 
{
    return (&Win32::Lanman::USE_OK       => 'The connection is successful.', 
	    &Win32::Lanman::USE_PAUSED   => 'Paused by a local workstation.', 
	    &Win32::Lanman::USE_SESSLOST => 'Disconnected.',
	    &Win32::Lanman::USE_DISCONN  => 'An error occurred.', 
	    &Win32::Lanman::USE_NETERR   => 'A network error occurred.', 
	    &Win32::Lanman::USE_CONN     => 'The connection is being made.', 
	    &Win32::Lanman::USE_RECONN   => 'Reconnecting.');
}

sub NET_INFO_DESCRIPTION
{
    return (&Win32::Lanman::USE_NOFORCE => 'Fail the disconnection if open files exist on the connection.', 
	    &Win32::Lanman::USE_FORCE   => 'Fail the disconnection if open files exist on the connection.', 
	    &Win32::Lanman::USE_LOTS_OF_FORCE => 'Close any open files and delete the connection.',
	    # These first 3 are for use with NetUseDel and NetWkStaTransportDel
	    # Others are for use with the flags parameter in NetUseAdd , GetInfo and Enum
	    &Win32::Lanman::USE_WILDCARD => "Matches the type of the server's shared resources. " . 
	                                    "Wildcards can be used only with the NetUseAdd function, see MSDN for details",
	    &Win32::Lanman::USE_DISKDEV =>  'Disk device.',
	    &Win32::Lanman::USE_SPOOLDEV => 'Spooled printer.', 
	    &Win32::Lanman::USE_IPC => 'Interprocess communication (IPC).');
}

sub SERVICE_CONTROL_DESCRIPTIONS 
{ 
  return (&Win32::Lanman::SERVICE_ACCEPT_STOP                 => 'The service can be stopped. This flag allows the service to receive the SERVICE_CONTROL_STOP value.', 
	  &Win32::Lanman::SERVICE_ACCEPT_PAUSE_CONTINUE       => "The service can be paused and continued. This flag allows the service to receive the SERVICE_CONTROL_PAUSE and SERVICE_CONTROL_CONTINUE values.",
	  &Win32::Lanman::SERVICE_ACCEPT_SHUTDOWN             => "The service is notified when system shutdown occurs. This flag allows the service to receive the SERVICE_CONTROL_SHUTDOWN value. Note that ControlService cannot send this control code; only the system can send SERVICE_CONTROL_SHUTDOWN.",
	  &Win32::Lanman::SERVICE_ACCEPT_PARAMCHANGE          => "Windows 2000: The service can reread its startup parameters without being stopped and restarted. This flag allows the service to receive the SERVICE_CONTROL_PARAMCHANGE value.",
	  &Win32::Lanman::SERVICE_ACCEPT_NETBINDCHANGE        => "Windows 2000: The service is a network component that can accept changes in its binding without being stopped and restarted. This flag allows the service to receive the SERVICE_CONTROL_NETBINDADD, SERVICE_CONTROL_NETBINDREMOVE, SERVICE_CONTROL_NETBINDENABLE, and SERVICE_CONTROL_NETBINDDISABLE values.",
	  &Win32::Lanman::SERVICE_ACCEPT_HARDWAREPROFILECHANGE => "Windows 2000: The service is notified when the computer's hardware profile has changed. This enables the system to send a SERVICE_CONTROL_HARDWAREPROFILECHANGE value to the service. The service receives this value only if it has called the RegisterServiceCtrlHandlerEx function. The ControlService function cannot send this control code.",
	  &Win32::Lanman::SERVICE_ACCEPT_POWEREVENT            => "Windows 2000: The service is notified when the computer's power status has changed. This enables the system to send a SERVICE_CONTROL_POWEREVENT value to the service. The service receives this value only if it has called the RegisterServiceCtrlHandlerEx function. The ControlService function cannot send this control code.");
}

sub SC_FAILURE_ACTIONS
{
	return (none	   	=>     &Win32::Lanman::SC_ACTION_NONE,
		reboot		=>     &Win32::Lanman::SC_ACTION_REBOOT,
		restart	        =>     &Win32::Lanman::SC_ACTION_RESTART,
		run_command	=>     &Win32::Lanman::SC_ACTION_RUN_COMMAND);
}

sub SERVICE_ACCEPTED_CONTROLS
{
	return (stop			=>	&Win32::Lanman::SERVICE_ACCEPT_STOP,
		pause_continue		=>	&Win32::Lanman::SERVICE_ACCEPT_PAUSE_CONTINUE,
		shutdown		=>	&Win32::Lanman::SERVICE_ACCEPT_SHUTDOWN,
		paramchange		=>	&Win32::Lanman::SERVICE_ACCEPT_PARAMCHANGE,
		netbindchange		=>	&Win32::Lanman::SERVICE_ACCEPT_NETBINDCHANGE,
		hardwareprofilechange	=>	&Win32::Lanman::SERVICE_ACCEPT_HARDWAREPROFILECHANGE,
		powerevent		=>	&Win32::Lanman::SERVICE_ACCEPT_POWEREVENT);
}

sub SERVICE_START_TYPES
{
	return (auto		=>	&Win32::Lanman::SERVICE_AUTO_START,  
		boot		=>	&Win32::Lanman::SERVICE_BOOT_START,
		demand		=>	&Win32::Lanman::SERVICE_DEMAND_START,
		disabled	=>	&Win32::Lanman::SERVICE_DISABLED,
		system		=>	&Win32::Lanman::SERVICE_SYSTEM_START);
}

sub SERVICE_ERROR_TYPES
{
	return (critical		=>	&Win32::Lanman::SERVICE_ERROR_CRITICAL,  
		ignore		=>	&Win32::Lanman::SERVICE_ERROR_IGNORE,
		normal		=>	&Win32::Lanman::SERVICE_ERROR_NORMAL,
		severe		=>	&Win32::Lanman::SERVICE_ERROR_SEVERE);
}

sub SERVICE_CONTROLS
{
	return (continue		=>	&Win32::Lanman::SERVICE_CONTROL_CONTINUE,
		deviceevent		=>	&Win32::Lanman::SERVICE_CONTROL_DEVICEEVENT,
		hardwareprofilechange	=>	&Win32::Lanman::SERVICE_CONTROL_HARDWAREPROFILECHANGE,
		interrogate		=>	&Win32::Lanman::SERVICE_CONTROL_INTERROGATE,
		netbindadd		=>	&Win32::Lanman::SERVICE_CONTROL_NETBINDADD,
		netbinddisable		=>	&Win32::Lanman::SERVICE_CONTROL_NETBINDDISABLE,
		netbindenable		=>	&Win32::Lanman::SERVICE_CONTROL_NETBINDENABLE,
		netbindremove		=>	&Win32::Lanman::SERVICE_CONTROL_NETBINDREMOVE,
		pause			=>	&Win32::Lanman::SERVICE_CONTROL_PAUSE,
		paramchange		=>	&Win32::Lanman::SERVICE_CONTROL_PARAMCHANGE,
		powerevent		=>	&Win32::Lanman::SERVICE_CONTROL_POWEREVENT,
		shutdown		=>	&Win32::Lanman::SERVICE_CONTROL_SHUTDOWN,
		stop			=>	&Win32::Lanman::SERVICE_CONTROL_STOP);
}

sub SERVICE_TYPES
{
	return (win32			=>	&Win32::Lanman::SERVICE_WIN32,  
		driver			=>	&Win32::Lanman::SERVICE_DRIVER,
		adapter			=>	&Win32::Lanman::SERVICE_ADAPTER,
		recognizerdriver	=>	&Win32::Lanman::SERVICE_RECOGNIZER_DRIVER,
		filesystemdriver	=>	&Win32::Lanman::SERVICE_FILE_SYSTEM_DRIVER,
		interactive		=>	&Win32::Lanman::SERVICE_INTERACTIVE_PROCESS,
		kernel			=>	&Win32::Lanman::SERVICE_KERNEL_DRIVER,
		ownprocess		=>	&Win32::Lanman::SERVICE_WIN32_OWN_PROCESS,
		shareprocess		=>	&Win32::Lanman::SERVICE_WIN32_SHARE_PROCESS,
		all			=>	&Win32::Lanman::SERVICE_TYPE_ALL);
}

sub PRIVILEGE_NAMES {
        return (create_token	        =>	&Win32::Lanman::SE_CREATE_TOKEN_NAME,
		assignprimarytoken	=>	&Win32::Lanman::SE_ASSIGNPRIMARYTOKEN_NAME,
	        lock_memory      	=>	&Win32::Lanman::SE_LOCK_MEMORY_NAME,
	        increase_quota      	=>	&Win32::Lanman::SE_INCREASE_QUOTA_NAME,
	        unsolicited_input	=>	&Win32::Lanman::SE_UNSOLICITED_INPUT_NAME,
	        machine_account		=>	&Win32::Lanman::SE_MACHINE_ACCOUNT_NAME,
	        tcb			=>	&Win32::Lanman::SE_TCB_NAME,
	        security		=>	&Win32::Lanman::SE_SECURITY_NAME,
	        take_ownership		=>	&Win32::Lanman::SE_TAKE_OWNERSHIP_NAME,
	        load_driver		=>	&Win32::Lanman::SE_LOAD_DRIVER_NAME,
	        system_profile		=>	&Win32::Lanman::SE_SYSTEM_PROFILE_NAME,
	        systemtime		=>	&Win32::Lanman::SE_SYSTEMTIME_NAME,
	        prof_single_process	=>	&Win32::Lanman::SE_PROF_SINGLE_PROCESS_NAME,
	        inc_base_priority	=>	&Win32::Lanman::SE_INC_BASE_PRIORITY_NAME,
	        create_pagefile		=>	&Win32::Lanman::SE_CREATE_PAGEFILE_NAME,
	        create_permanent	=>	&Win32::Lanman::SE_CREATE_PERMANENT_NAME,
	        backup			=>	&Win32::Lanman::SE_BACKUP_NAME,
	        restore			=>	&Win32::Lanman::SE_RESTORE_NAME,
	        shutdown		=>	&Win32::Lanman::SE_SHUTDOWN_NAME,
	        debug			=>	&Win32::Lanman::SE_DEBUG_NAME,
	        audit			=>	&Win32::Lanman::SE_AUDIT_NAME,
	        system_environment	=>	&Win32::Lanman::SE_SYSTEM_ENVIRONMENT_NAME,
	        change_notify		=>	&Win32::Lanman::SE_CHANGE_NOTIFY_NAME,
	        remote_shutdown		=>	&Win32::Lanman::SE_REMOTE_SHUTDOWN_NAME,
	        interactive_logon	=>	&Win32::Lanman::SE_INTERACTIVE_LOGON_NAME,
	        deny_interactive_logon	=>	&Win32::Lanman::SE_DENY_INTERACTIVE_LOGON_NAME,
	        network_logon		=>	&Win32::Lanman::SE_NETWORK_LOGON_NAME,
	        deny_network_logon	=>	&Win32::Lanman::SE_DENY_NETWORK_LOGON_NAME,
	        batch_logon		=>	&Win32::Lanman::SE_BATCH_LOGON_NAME,
	        deny_batch_logon	=>	&Win32::Lanman::SE_DENY_BATCH_LOGON_NAME,
	        service_logon		=>	&Win32::Lanman::SE_SERVICE_LOGON_NAME,
        	deny_service_logon	=>	&Win32::Lanman::SE_DENY_SERVICE_LOGON_NAME);
}

sub SidToString
{
	return undef
		unless unpack("C", substr($_[0], 0, 1)) == 1;

	return undef
		unless length($_[0]) == 8 + 4 * unpack("C", substr($_[0], 1, 1));

	my $sid_str = "S-1-";

	$sid_str .= (unpack("C", substr($_[0], 7, 1)) + (unpack("C", substr($_[0], 6, 1)) << 8) +
		     (unpack("C", substr($_[0], 5, 1)) << 16) + (unpack("C",substr($_[0], 4, 1)) << 24));

	for $loop (0 .. unpack("C", substr($_[0], 1, 1)) - 1)
	{
		$sid_str .= "-" . unpack("I", substr($_[0], 4 * $loop + 8, 4));
	}

	return $sid_str;
}

sub StringToSid
{
	return undef
		unless uc(substr($_[0], 0, 4)) eq "S-1-";

	my ($auth_id, @sub_auth_id) = split(/-/, substr($_[0], 4));

	my $sid = pack("C4", 1, $#sub_auth_id + 1, 0, 0);
	
	$sid .= pack("C4", ($auth_id & 0xff000000) >> 24, ($auth_id &0x00ff0000) >> 16, 
			($auth_id & 0x0000ff00) >> 8, $auth_id &0x000000ff);

	for $loop (0 .. $#sub_auth_id)
	{
		$sid .= pack("I", $sub_auth_id[$loop]);
	}

	return $sid;
}

sub GuidToString
{
	return sprintf "%08X-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X", 
		unpack("I", $_[0]), 
		unpack("S", substr($_[0], 4, 2)), 
		unpack("S", substr($_[0], 6, 2)),
		unpack("C", substr($_[0], 8, 1)),
		unpack("C", substr($_[0], 9, 1)),
		unpack("C", substr($_[0], 10, 1)),
		unpack("C", substr($_[0], 11, 1)),
		unpack("C", substr($_[0], 12, 1)),
		unpack("C", substr($_[0], 13, 1)),
		unpack("C", substr($_[0], 14, 1)),
		unpack("C", substr($_[0], 15, 1)); 
}

sub StringToGuid
{
	return undef
		unless $_[0] =~ /([0-9,a-z]{8})-([0-9,a-z]{4})-([0-9,a-z]{4})-([0-9,a-z]{2})([0-9,a-z]{2})-([0-9,a-z]{2})([0-9,a-z]{2})([0-9,a-z]{2})([0-9,a-z]{2})([0-9,a-z]{2})([0-9,a-z]{2})/i;

	return pack("I", hex $1) . pack("S", hex $2) . pack("S", hex $3) . pack("C", hex $4) . pack("C", hex $5) .
	       pack("C", hex $6) . pack("C", hex $7) . pack("C", hex $8) . pack("C", hex $9) . pack("C", hex $10) . pack("C", hex $11);

	print "$1\n$2\n$3\n$4\n$5\n$6\n$7\n$8\n$9\n$10\n$11\n";
}

bootstrap $Package;

# Preloaded methods go here.

# Autoload methods go after __END__, and are processed by the autosplit program.

1;

__END__

=head1 NAME

Win32::Lanman - implements MS Lanmanager functions

=head1 SYNOPSIS

	use Win32::Lanman;

=head1 DESCRIPTION

This module implements the MS Lanmanager functions

=head1 CONSTANTS

Documentation for use and meaning of the Constants can be found at
L<"http://search.microsoft.com/us/dev/default.asp">

	SERVICE_CONTROL_DESCRIPTIONS
	SERVICE_STATE_DESCRIPTIONS
	SERVICE_CONTROLS
	SERVICE_START_TYPES
	SERVICE_ERROR_TYPES
	SERVICE_ACCEPTED_CONTROLS
	SERVICE_ADAPTER
	SERVICE_RECOGNIZER_DRIVER
	SERVICE_TYPE_ALL
	SERVICE_STATES 
	SERVICE_TYPES 

	AF_OP_ACCOUNTS
	AF_OP_COMM
	AF_OP_PRINT
	AF_OP_SERVER

	ALLOCATE_RESPONSE     

	AuditCategoryAccountLogon
	AuditCategoryAccountManagement
	AuditCategoryDetailedTracking
	AuditCategoryDirectoryServiceAccess
	AuditCategoryLogon
	AuditCategoryObjectAccess
	AuditCategoryPolicyChange
	AuditCategoryPrivilegeUse
	AuditCategorySystem

	AUTH_REQ_ALLOW_ENC_TKT_IN_SKEY
	AUTH_REQ_ALLOW_FORWARDABLE
	AUTH_REQ_ALLOW_NOADDRESS
	AUTH_REQ_ALLOW_POSTDATE
	AUTH_REQ_ALLOW_PROXIABLE
	AUTH_REQ_ALLOW_RENEWABLE
	AUTH_REQ_ALLOW_VALIDATE
	AUTH_REQ_OK_AS_DELEGATE
	AUTH_REQ_PREAUTH_REQUIRED
	AUTH_REQ_VALIDATE_CLIENT

	Batch

	CONNECT_CURRENT_MEDIA
	CONNECT_DEFERRED
	CONNECT_INTERACTIVE
	CONNECT_LOCALDRIVE
	CONNECT_NEED_DRIVE
	CONNECT_PROMPT
	CONNECT_REDIRECT
	CONNECT_REFCOUNT
	CONNECT_RESERVED
	CONNECT_TEMPORARY
	CONNECT_UPDATE_PROFILE
	CONNECT_UPDATE_RECENT

	CONNDLG_CONN_POINT
	CONNDLG_HIDE_BOX
	CONNDLG_NOT_PERSIST
	CONNDLG_PERSIST
	CONNDLG_RO_PATH
	CONNDLG_USE_MRU
	CONNECT_UPDATE_PROFILE

	DEF_MAX_PWHIST

	DACL_SECURITY_INFORMATION

	DISC_NO_FORCE
	DISC_UPDATE_PROFILE

	DFS_ADD_VOLUME
	DFS_RESTORE_VOLUME
	DFS_STORAGE_STATE_ACTIVE
	DFS_STORAGE_STATE_OFFLINE
	DFS_STORAGE_STATE_ONLINE
	DFS_VOLUME_STATE_INCONSISTENT
	DFS_VOLUME_STATE_OK
	DFS_VOLUME_STATE_OFFLINE
	DFS_VOLUME_STATE_ONLINE

	EVENTLOG_BACKWARDS_READ
	EVENTLOG_FORWARDS_READ
	EVENTLOG_SEEK_READ
	EVENTLOG_SEQUENTIAL_READ

	EVENTLOG_ERROR_TYPE
	EVENTLOG_WARNING_TYPE
	EVENTLOG_INFORMATION_TYPE
	EVENTLOG_AUDIT_SUCCESS
	EVENTLOG_AUDIT_FAILURE

	FILTER_INTERDOMAIN_TRUST_ACCOUNT
	FILTER_NORMAL_ACCOUNT
	FILTER_SERVER_TRUST_ACCOUNT
	FILTER_TEMP_DUPLICATE_ACCOUNT
	FILTER_WORKSTATION_TRUST_ACCOUNT

	GROUP_SECURITY_INFORMATION

	IDASYNC
	IDTIMEOUT

	Interactive

	JOB_ADD_CURRENT_DATE
	JOB_EXEC_ERROR
	JOB_INPUT_FLAGS
	JOB_NONINTERACTIVE
	JOB_OUTPUT_FLAGS
	JOB_RUN_PERIODICALLY
	JOB_RUNS_TODAY

	KERB_CHECKSUM_CRC32
	KERB_CHECKSUM_DES_MAC
	KERB_CHECKSUM_DES_MAC_MD5
	KERB_CHECKSUM_HMAC_MD5
	KERB_CHECKSUM_KRB_DES_MAC
	KERB_CHECKSUM_LM
	KERB_CHECKSUM_MD25
	KERB_CHECKSUM_MD4
	KERB_CHECKSUM_MD5
	KERB_CHECKSUM_MD5_DES
	KERB_CHECKSUM_MD5_HMAC
	KERB_CHECKSUM_NONE
	KERB_CHECKSUM_RC4_MD5
	KERB_CHECKSUM_REAL_CRC32
	KERB_CHECKSUM_SHA1
	KERB_DECRYPT_FLAG_DEFAULT_KEY
	KERB_ETYPE_DES_CBC_CRC
	KERB_ETYPE_DES_CBC_MD4
	KERB_ETYPE_DES_CBC_MD5
	KERB_ETYPE_DES_CBC_MD5_NT
	KERB_ETYPE_DES_PLAIN
	KERB_ETYPE_DSA_SIGN
	KERB_ETYPE_NULL
	KERB_ETYPE_PKCS7_PUB
	KERB_ETYPE_RC4_HMAC_NT
	KERB_ETYPE_RC4_HMAC_NT_EXP
	KERB_ETYPE_RC4_HMAC_OLD
	KERB_ETYPE_RC4_HMAC_OLD_EXP
	KERB_ETYPE_RC4_LM
	KERB_ETYPE_RC4_MD4
	KERB_ETYPE_RC4_PLAIN
	KERB_ETYPE_RC4_PLAIN_EXP
	KERB_ETYPE_RC4_PLAIN_OLD
	KERB_ETYPE_RC4_PLAIN_OLD_EXP
	KERB_ETYPE_RC4_PLAIN2
	KERB_ETYPE_RC4_SHA
	KERB_ETYPE_RSA_PRIV
	KERB_ETYPE_RSA_PUB
	KERB_ETYPE_RSA_PUB_MD5
	KERB_ETYPE_RSA_PUB_SHA1
	KERB_RETRIEVE_TICKET_DONT_USE_CACHE
	KERB_RETRIEVE_TICKET_USE_CACHE_ONLY
	KERB_WRAP_NO_ENCRYPT
	KERBEROS_REVISION
	KERBEROS_VERSION

	KerbInteractiveLogon
	KerbSmartCardLogon

	KerbInteractiveProfile
	KerbSmartCardProfile

	LG_INCLUDE_INDIRECT

	LOGON_CACHED_ACCOUNT
	LOGON_EXTRA_SIDS
	LOGON_GRACE_LOGON
	LOGON_GUEST
	LOGON_NOENCRYPTION
	LOGON_PROFILE_PATH_RETURNED
	LOGON_RESOURCE_GROUPS
	LOGON_SERVER_TRUST_ACCOUNT
	LOGON_SUBAUTH_SESSION_KEY
	LOGON_USED_LM_PASSWORD

	LSA_MODE_INDIVIDUAL_ACCOUNTS
	LSA_MODE_LOG_FULL
	LSA_MODE_MANDATORY_ACCESS
	LSA_MODE_PASSWORD_PROTECTED

	MAJOR_VERSION_MASK

	MsV1_0InteractiveLogon
	MsV1_0Lm20Logon
	MsV1_0NetworkLogon
	MsV1_0SubAuthLogon

	MsV1_0InteractiveProfile
	MsV1_0Lm20LogonProfile
	MsV1_0SmartCardProfile

	MsV1_0EnumerateUsers
	MsV1_0CacheLogon
	MsV1_0CacheLookup
	MsV1_0ChangeCachedPassword
	MsV1_0ChangePassword
	MsV1_0DeriveCredential
	MsV1_0GenericPassthrough
	MsV1_0GetUserInfo
	MsV1_0Lm20ChallengeRequest
	MsV1_0Lm20GetChallengeResponse
	MsV1_0ReLogonUsers
	MsV1_0SubAuth

	MSV1_0_CHALLENGE_LENGTH
	MSV1_0_USER_SESSION_KEY_LENGTH
	MSV1_0_LANMAN_SESSION_KEY_LENGTH

	MSV1_0_ALLOW_SERVER_TRUST_ACCOUNT
	MSV1_0_ALLOW_WORKSTATION_TRUST_ACCOUNT
	MSV1_0_CLEARTEXT_PASSWORD_ALLOWED
	MSV1_0_DERIVECRED_TYPE_SHA1
	MSV1_0_DONT_TRY_GUEST_ACCOUNT
	MSV1_0_RETURN_PASSWORD_EXPIRY
	MSV1_0_RETURN_PROFILE_PATH
	MSV1_0_RETURN_USER_PARAMETERS
	MSV1_0_SUBAUTHENTICATION_DLL_EX
	MSV1_0_TRY_GUEST_ACCOUNT_ONLY
	MSV1_0_TRY_SPECIFIED_DOMAIN_ONLY
	MSV1_0_UPDATE_LOGON_STATISTICS

	MSV1_0_MNS_LOGON
	MSV1_0_SUBAUTHENTICATION_DLL
	MSV1_0_SUBAUTHENTICATION_DLL_SHIFT

	MSV1_0_SUBAUTHENTICATION_DLL_IIS
	MSV1_0_SUBAUTHENTICATION_DLL_RAS

	MSV1_0_SUBAUTHENTICATION_FLAGS

	MSV1_0_CRED_LM_PRESENT
	MSV1_0_CRED_NT_PRESENT
	MSV1_0_CRED_VERSION
	MSV1_0_OWF_PASSWORD_LENGTH

	MSV1_0_NTLM3_OWF_LENGTH
	MSV1_0_NTLM3_RESPONSE_LENGTH

	MSV1_0_MAX_AVL_SIZE
	MSV1_0_MAX_NTLM3_LIFE

	MSV1_0_NTLM3_INPUT_LENGTH

	MsvAvEOL
	MsvAvNbComputerName
	MsvAvNbDomainName
	MsvAvDnsDomainName
	MsvAvDnsServerName

	NegCallPackageMax
	NegEnumPackagePrefixes

	NEGOTIATE_MAX_PREFIX

	NETLOGON_CONTROL_BACKUP_CHANGE_LOG
	NETLOGON_CONTROL_BREAKPOINT
	NETLOGON_CONTROL_FIND_USER
	NETLOGON_CONTROL_PDC_REPLICATE
	NETLOGON_CONTROL_QUERY
	NETLOGON_CONTROL_REDISCOVER
	NETLOGON_CONTROL_REPLICATE
	NETLOGON_CONTROL_SET_DBFLAG
	NETLOGON_CONTROL_SYNCHRONIZE
	NETLOGON_CONTROL_TC_QUERY
	NETLOGON_CONTROL_TRANSPORT_NOTIFY
	NETLOGON_CONTROL_TRUNCATE_LOG
	NETLOGON_CONTROL_UNLOAD_NETLOGON_DLL
	NETLOGON_FULL_SYNC_REPLICATION
	NETLOGON_REDO_NEEDED
	NETLOGON_REPLICATION_IN_PROGRESS
	NETLOGON_REPLICATION_NEEDED

	NetSetupDnsMachine
	NetSetupDomain
	NetSetupDomainName
	NetSetupMachine
	NetSetupNonExistentDomain
	NetSetupUnjoined
	NetSetupUnknown
	NetSetupUnknownStatus
	NetSetupWorkgroup
	NetSetupWorkgroupName

	NETSETUP_ACCT_CREATE
	NETSETUP_ACCT_DELETE
	NETSETUP_DOMAIN_JOIN_IF_JOINED
	NETSETUP_INSTALL_INVOCATION
	NETSETUP_JOIN_DOMAIN
	NETSETUP_JOIN_UNSECURE
	NETSETUP_WIN9X_UPGRADE

	NETPROPERTY_PERSISTENT

	Network

	NO_PERMISSION_REQUIRED

	ONE_DAY

	OWNER_SECURITY_INFORMATION

	PERM_FILE_CREATE
	PERM_FILE_READ
	PERM_FILE_WRITE

	POLICY_AUDIT_EVENT_FAILURE
	POLICY_AUDIT_EVENT_NONE
	POLICY_AUDIT_EVENT_MASK
	POLICY_AUDIT_EVENT_NONE
	POLICY_AUDIT_EVENT_SUCCESS
	POLICY_AUDIT_EVENT_UNCHANGED

	POLICY_ALL_ACCESS
	POLICY_AUDIT_LOG_ADMIN
	POLICY_CREATE_ACCOUNT
	POLICY_CREATE_PRIVILEGE
	POLICY_CREATE_SECRET
	POLICY_EXECUTE
	POLICY_GET_PRIVATE_INFORMATION
	POLICY_LOOKUP_NAMES
	POLICY_NOTIFICATION
	POLICY_READ
	POLICY_SERVER_ADMIN
	POLICY_SET_AUDIT_REQUIREMENTS
	POLICY_SET_DEFAULT_QUOTA_LIMITS
	POLICY_TRUST_ADMIN
	POLICY_VIEW_AUDIT_INFORMATION
	POLICY_VIEW_LOCAL_INFORMATION
	POLICY_WRITE

	POLICY_QOS_ALLOW_LOCAL_ROOT_CERT_STORE
	POLICY_QOS_DHCP_SERVER_ALLOWED
	POLICY_QOS_INBOUND_CONFIDENTIALITY
	POLICY_QOS_INBOUND_INTEGRITY
	POLICY_QOS_OUTBOUND_CONFIDENTIALITY
	POLICY_QOS_OUTBOUND_INTEGRITY
	POLICY_QOS_RAS_SERVER_ALLOWED
	POLICY_QOS_SCHANNEL_REQUIRED

	PolicyAccountDomainInformation
	PolicyAuditEventsInformation
	PolicyAuditFullQueryInformation
	PolicyAuditFullSetInformation
	PolicyAuditLogInformation
	PolicyDefaultQuotaInformation
	PolicyDnsDomainInformation
	PolicyLsaServerRoleInformation
	PolicyModificationInformation
	PolicyPdAccountInformation
	PolicyPrimaryDomainInformation
	PolicyReplicaSourceInformation

	PolicyDomainEfsInformation
	PolicyDomainKerberosTicketInformation
	PolicyDomainQualityOfServiceInformation

	PolicyNotifyAccountDomainInformation
	PolicyNotifyAuditEventsInformation
	PolicyNotifyDnsDomainInformation
	PolicyNotifyDomainEfsInformation
	PolicyNotifyDomainKerberosTicketInformation
	PolicyNotifyMachineAccountPasswordInformation
	PolicyNotifyServerRoleInformation

	PolicyServerDisabled
	PolicyServerEnabled
	PolicyServerRoleBackup
	PolicyServerRolePrimary

	Proxy

	REMOTE_NAME_INFO_LEVEL

	REPL_EXTENT_FILE
	REPL_EXTENT_TREE
	REPL_INTEGRITY_TREE
	REPL_INTEGRITY_FILE
	REPL_ROLE_BOTH
	REPL_ROLE_EXPORT
	REPL_ROLE_IMPORT
	REPL_STATE_OK
	REPL_STATE_NO_MASTER
	REPL_STATE_NO_SYNC
	REPL_STATE_NEVER_REPLICATED
	REPL_UNLOCK_FORCE
	REPL_UNLOCK_NOFORCE

	RESOURCEUSAGE_ALL
	RESOURCE_CONNECTED
	RESOURCE_CONTEXT
	RESOURCE_GLOBALNET
	RESOURCE_REMEMBERED
	RESOURCETYPE_RESERVED
	RESOURCETYPE_UNKNOWN
	RESOURCETYPE_ANY
	RESOURCETYPE_DISK
	RESOURCETYPE_PRINT
	RESOURCEDISPLAYTYPE_DIRECTORY
	RESOURCEDISPLAYTYPE_DOMAIN
	RESOURCEDISPLAYTYPE_FILE
	RESOURCEDISPLAYTYPE_GENERIC
	RESOURCEDISPLAYTYPE_GROUP
	RESOURCEDISPLAYTYPE_NDSCONTAINER
	RESOURCEDISPLAYTYPE_NETWORK
	RESOURCEDISPLAYTYPE_ROOT
	RESOURCEDISPLAYTYPE_SERVER
	RESOURCEDISPLAYTYPE_SHARE
	RESOURCEDISPLAYTYPE_SHAREADMIN
	RESOURCEDISPLAYTYPE_TREE
	RESOURCEUSAGE_ALL
	RESOURCEUSAGE_CONNECTABLE
	RESOURCEUSAGE_CONTAINER
	RESOURCEUSAGE_ATTACHED
	RESOURCEUSAGE_NOLOCALDEVICE
	RESOURCEUSAGE_RESERVED
	RESOURCEUSAGE_SIBLING

	SACL_SECURITY_INFORMATION

	SE_GROUP_ENABLED_BY_DEFAULT
	SE_GROUP_MANDATORY
	SE_GROUP_OWNER

	SE_CREATE_TOKEN_NAME
	SE_ASSIGNPRIMARYTOKEN_NAME
	SE_LOCK_MEMORY_NAME
	SE_INCREASE_QUOTA_NAME
	SE_UNSOLICITED_INPUT_NAME
	SE_MACHINE_ACCOUNT_NAME
	SE_TCB_NAME
	SE_SECURITY_NAME
	SE_TAKE_OWNERSHIP_NAME
	SE_LOAD_DRIVER_NAME
	SE_SYSTEM_PROFILE_NAME
	SE_SYSTEMTIME_NAME
	SE_PROF_SINGLE_PROCESS_NAME
	SE_INC_BASE_PRIORITY_NAME
	SE_CREATE_PAGEFILE_NAME
	SE_CREATE_PERMANENT_NAME
	SE_BACKUP_NAME
	SE_RESTORE_NAME
	SE_SHUTDOWN_NAME
	SE_DEBUG_NAME
	SE_AUDIT_NAME
	SE_SYSTEM_ENVIRONMENT_NAME
	SE_CHANGE_NOTIFY_NAME
	SE_REMOTE_SHUTDOWN_NAME
	SE_INTERACTIVE_LOGON_NAME
	SE_DENY_INTERACTIVE_LOGON_NAME
	SE_NETWORK_LOGON_NAME
	SE_DENY_NETWORK_LOGON_NAME
	SE_BATCH_LOGON_NAME
	SE_DENY_BATCH_LOGON_NAME
	SE_SERVICE_LOGON_NAME
	SE_DENY_SERVICE_LOGON_NAME

	Service

	SC_ACTION_NONE
	SC_ACTION_REBOOT
	SC_ACTION_RESTART
	SC_ACTION_RUN_COMMAND

	SC_MANAGER_ALL_ACCESS
	SC_MANAGER_CONNECT
	SC_MANAGER_CREATE_SERVICE
	SC_MANAGER_ENUMERATE_SERVICE
	SC_MANAGER_LOCK
	SC_MANAGER_MODIFY_BOOT_CONFIG
	SC_MANAGER_QUERY_LOCK_STATUS

	SC_STATUS_PROCESS_INFO

	SERVICE_ACCEPT_STOP
	SERVICE_ACCEPT_PAUSE_CONTINUE
	SERVICE_ACCEPT_SHUTDOWN
	SERVICE_ACCEPT_PARAMCHANGE
	SERVICE_ACCEPT_NETBINDCHANGE
	SERVICE_ACCEPT_HARDWAREPROFILECHANGE
	SERVICE_ACCEPT_POWEREVENT

	SERVICE_FILE_SYSTEM_DRIVER
	SERVICE_INTERACTIVE_PROCESS
	SERVICE_KERNEL_DRIVER
	SERVICE_WIN32_OWN_PROCESS
	SERVICE_WIN32_SHARE_PROCESS

	SERVICE_AUTO_START
	SERVICE_BOOT_START
	SERVICE_DEMAND_START
	SERVICE_DISABLED
	SERVICE_SYSTEM_START

	SERVICE_ERROR_CRITICAL
	SERVICE_ERROR_IGNORE
	SERVICE_ERROR_NORMAL
	SERVICE_ERROR_SEVERE

	SERVICE_CONTINUE_PENDING
	SERVICE_PAUSE_PENDING
	SERVICE_PAUSED
	SERVICE_RUNNING
	SERVICE_START_PENDING
	SERVICE_STOPPED
	SERVICE_STOP_PENDING

	SERVICE_ALL_ACCESS
	SERVICE_CHANGE_CONFIG
	SERVICE_ENUMERATE_DEPENDENTS
	SERVICE_INTERROGATE
	SERVICE_PAUSE_CONTINUE
	SERVICE_QUERY_CONFIG
	SERVICE_QUERY_STATUS
	SERVICE_START
	SERVICE_STOP
	SERVICE_USER_DEFINED_CONTROL

	SERVICE_RUNS_IN_SYSTEM_PROCESS

	SERVICE_CONTROL_CONTINUE
	SERVICE_CONTROL_DEVICEEVENT
	SERVICE_CONTROL_HARDWAREPROFILECHANGE
	SERVICE_CONTROL_INTERROGATE
	SERVICE_CONTROL_NETBINDADD
	SERVICE_CONTROL_NETBINDDISABLE
	SERVICE_CONTROL_NETBINDENABLE
	SERVICE_CONTROL_NETBINDREMOVE
	SERVICE_CONTROL_PAUSE
	SERVICE_CONTROL_PARAMCHANGE
	SERVICE_CONTROL_POWEREVENT
	SERVICE_CONTROL_SHUTDOWN
	SERVICE_CONTROL_STOP

	SERVICE_CONFIG_FAILURE_ACTIONS

	SERVICE_NO_CHANGE
	SERVICE_ACTIVE
	SERVICE_DRIVER
	SERVICE_INACTIVE
	SERVICE_STATE_ALL
	SERVICE_WIN32

	STYPE_DEVICE
	STYPE_DISKTREE
	STYPE_IPC
	STYPE_PRINTQ

	SUPPORTS_ANY
	SUPPORTS_LOCAL
	SUPPORTS_REMOTE_ADMIN_PROTOCOL
	SUPPORTS_RPC
	SUPPORTS_SAM_PROTOCOL
	SUPPORTS_UNICODE

	SV_HIDDEN
	SV_MAX_CMD_LEN
	SV_MAX_SRV_HEUR_LEN
	SV_NODISC
	SV_PLATFORM_ID_OS2
	SV_PLATFORM_ID_NT
	SV_SHARESECURITY
	SV_TYPE_AFP
	SV_TYPE_ALL
	SV_TYPE_ALTERNATE_XPORT
	SV_TYPE_BACKUP_BROWSER
	SV_TYPE_CLUSTER_NT
	SV_TYPE_DCE
	SV_TYPE_DFS
	SV_TYPE_DIALIN_SERVER
	SV_TYPE_DOMAIN_BAKCTRL
	SV_TYPE_DOMAIN_CTRL
	SV_TYPE_DOMAIN_ENUM
	SV_TYPE_DOMAIN_MASTER
	SV_TYPE_DOMAIN_MEMBER
	SV_TYPE_LOCAL_LIST_ONLY
	SV_TYPE_MASTER_BROWSER
	SV_TYPE_NOVELL
	SV_TYPE_NT
	SV_TYPE_POTENTIAL_BROWSER
	SV_TYPE_PRINTQ_SERVER
	SV_TYPE_SERVER
	SV_TYPE_SERVER_MFPN
	SV_TYPE_SERVER_NT
	SV_TYPE_SERVER_OSF
	SV_TYPE_SERVER_UNIX
	SV_TYPE_SERVER_VMS
	SV_TYPE_SQLSERVER
	SV_TYPE_TERMINALSERVER
	SV_TYPE_TIME_SOURCE
	SV_TYPE_WFW
	SV_TYPE_WINDOWS
	SV_TYPE_WORKSTATION
	SV_TYPE_XENIX_SERVER

	SV_USERS_PER_LICENSE
	SV_USERSECURITY
	SV_VISIBLE

	SW_AUTOPROF_LOAD_MASK
	SW_AUTOPROF_SAVE_MASK

	TIMEQ_FOREVER

	TRUST_ATTRIBUTE_NON_TRANSITIVE
	TRUST_ATTRIBUTE_TREE_PARENT
	TRUST_ATTRIBUTE_TREE_ROOT
	TRUST_ATTRIBUTE_UPLEVEL_ONLY
	TRUST_ATTRIBUTES_USER
	TRUST_ATTRIBUTES_VALID

	TRUST_AUTH_TYPE_CLEAR
	TRUST_AUTH_TYPE_NONE
	TRUST_AUTH_TYPE_NT4OWF
	TRUST_AUTH_TYPE_VERSION

	TRUST_DIRECTION_BIDIRECTIONAL
	TRUST_DIRECTION_DISABLED
	TRUST_DIRECTION_INBOUND
	TRUST_DIRECTION_OUTBOUND

	TRUST_TYPE_DCE
	TRUST_TYPE_DOWNLEVEL
	TRUST_TYPE_MIT
	TRUST_TYPE_UPLEVEL

	TrustedControllersInformation
	TrustedDomainAuthInformation
	TrustedDomainFullInformation
	TrustedDomainInformationBasic
	TrustedDomainInformationEx
	TrustedDomainNameInformation
	TrustedPasswordInformation
	TrustedPosixOffsetInformation

	UAS_ROLE_STANDALONE
	UAS_ROLE_MEMBER
	UAS_ROLE_BACKUP
	UAS_ROLE_PRIMARY

	UF_ACCOUNT_TYPE_MASK
	UF_ACCOUNTDISABLE
	UF_DONT_EXPIRE_PASSWD
	UF_DONT_REQUIRE_PREAUTH
	UF_ENCRYPTED_TEXT_PASSWORD_ALLOWED
	UF_HOMEDIR_REQUIRED
	UF_INTERDOMAIN_TRUST_ACCOUNT
	UF_LOCKOUT
	UF_MACHINE_ACCOUNT_MASK
	UF_MNS_LOGON_ACCOUNT
	UF_NORMAL_ACCOUNT
	UF_NOT_DELEGATED
	UF_PASSWD_CANT_CHANGE
	UF_PASSWD_NOTREQD
	UF_SCRIPT
	UF_SERVER_TRUST_ACCOUNT
	UF_SETTABLE_BITS
	UF_SMARTCARD_REQUIRED
	UF_TEMP_DUPLICATE_ACCOUNT
	UF_TRUSTED_FOR_DELEGATION
	UF_USE_DES_KEY_ONLY
	UF_WORKSTATION_TRUST_ACCOUNT

	UNITS_PER_WEEK

	UNIVERSAL_NAME_INFO_LEVEL

	Unlock

	USE_FORCE
	USE_LOTS_OF_FORCE
	USE_NOFORCE

	USE_SPECIFIC_TRANSPORT

	USE_CHARDEV
	USE_CONN
	USE_DISCONN
	USE_DISKDEV
	USE_IPC
	USE_NETERR
	USE_OK
	USE_PAUSED
	USE_RECONN
	USE_SESSLOST
	USE_SPOOLDEV
	USE_WILDCARD

	USER_MAXSTORAGE_UNLIMITED

	USER_PRIV_ADMIN
	USER_PRIV_GUEST
	USER_PRIV_USER

	WNCON_DYNAMIC
	WNCON_FORNETCARD
	WNCON_NOTROUTED
	WNCON_SLOWLINK

	WNNC_CRED_MANAGER
	WNNC_NET_10NET
	WNNC_NET_3IN1
	WNNC_NET_9TILES
	WNNC_NET_APPLETALK
	WNNC_NET_AS400
	WNNC_NET_AVID
	WNNC_NET_BMC
	WNNC_NET_BWNFS
	WNNC_NET_CLEARCASE
	WNNC_NET_COGENT
	WNNC_NET_CSC
	WNNC_NET_DCE
	WNNC_NET_DECORB
	WNNC_NET_DISTINCT
	WNNC_NET_DOCUSPACE
	WNNC_NET_EXTENDNET
	WNNC_NET_FARALLON
	WNNC_NET_FJ_REDIR
	WNNC_NET_FTP_NFS
	WNNC_NET_FRONTIER
	WNNC_NET_HOB_NFS
	WNNC_NET_IBMAL
	WNNC_NET_INTERGRAPH
	WNNC_NET_LANMAN
	WNNC_NET_LANTASTIC
	WNNC_NET_LANSTEP
	WNNC_NET_LIFENET
	WNNC_NET_LOCUS
	WNNC_NET_MANGOSOFT
	WNNC_NET_MASFAX
	WNNC_NET_MSNET
	WNNC_NET_NETWARE
	WNNC_NET_OBJECT_DIRE
	WNNC_NET_PATHWORKS
	WNNC_NET_POWERLAN
	WNNC_NET_PROTSTOR
	WNNC_NET_RDR2SAMPLE
	WNNC_NET_SERNET
	WNNC_NET_SHIVA
	WNNC_NET_SUN_PC_NFS
	WNNC_NET_SYMFONET
	WNNC_NET_TWINS
	WNNC_NET_VINES

	WTS_CURRENT_SERVER
	WTS_CURRENT_SERVER_HANDLE
	WTS_CURRENT_SERVER_NAME
	WTS_CURRENT_SESSION

	WTS_EVENT_NONE
	WTS_EVENT_CREATE
	WTS_EVENT_DELETE
	WTS_EVENT_RENAME
	WTS_EVENT_CONNECT
	WTS_EVENT_DISCONNECT
	WTS_EVENT_LOGON
	WTS_EVENT_LOGOFF
	WTS_EVENT_STATECHANGE
	WTS_EVENT_LICENSE
	WTS_EVENT_ALL
	WTS_EVENT_FLUSH

	WTS_WSD_FASTREBOOT
	WTS_WSD_LOGOFF
	WTS_WSD_POWEROFF
	WTS_WSD_REBOOT
	WTS_WSD_SHUTDOWN

	WTSActive
	WTSConnected
	WTSConnectQuery
	WTSShadow
	WTSDisconnected
	WTSIdle
	WTSListen
	WTSReset
	WTSDown
	WTSInit

	WTSApplicationName
	WTSClientAddress
	WTSClientBuildNumber
	WTSClientDirectory
	WTSClientDisplay
	WTSClientHardwareId
	WTSClientName
	WTSClientProductId
	WTSConnectState
	WTSDomainName
	WTSInitialProgram
	WTSOEMId
	WTSSessionId
	WTSUserName
	WTSWinStationName
	WTSWorkingDirectory

	WTSUserConfigInitialProgram
	WTSUserConfigWorkingDirectory
	WTSUserConfigfInheritInitialProgram
	WTSUserConfigfAllowLogonTerminalServer
	WTSUserConfigTimeoutSettingsConnections
	WTSUserConfigTimeoutSettingsDisconnections
	WTSUserConfigTimeoutSettingsIdle
	WTSUserConfigfDeviceClientDrives
	WTSUserConfigfDeviceClientPrinters
	WTSUserConfigfDeviceClientDefaultPrinter
	WTSUserConfigBrokenTimeoutSettings
	WTSUserConfigReconnectSettings
	WTSUserConfigModemCallbackSettings
	WTSUserConfigModemCallbackPhoneNumber
	WTSUserConfigShadowingSettings
	WTSUserConfigTerminalServerProfilePath
	WTSUserConfigTerminalServerHomeDir
	WTSUserConfigTerminalServerHomeDirDrive
	WTSUserConfigfTerminalServerRemoteHomeDir

=head2 Useful Hashes

The following hashes are useful, since they group several associated codes form the platform sdk together, 
or provide description for the constants. For each hash we describe its use and mention some functions 
it may be used with. This is work in progress and should be finished by the next release.

=over 4

=item Work In progress

=item %SV_TYPES

Descriptions of the various server types. Could be used with ....

=item %SERVICE_STATES

Could be used with

=item %SERVICE_TYPES

Could be used with ...

=item %WTS_STATES

=item %SERVICE_FAILURE_ACTIONS

Could be used with ....

=item %SERVICE_CONTROL_DESCRIPTIONS

English descriptions of the service_control constants. Could be used with ....

=item %SERVICE_STATE_DESCRIPTIONS

=item %SERVICE_CONTROLS

=item %SERVICE_START_TYPES

=item %SERVICE_ERROR_TYPES

=item %SC_FAILURE_ACTIONS

Used in ChangeServiceConfig2 and QueryServiceConfig2

=item %SERVICE_ACCEPTED_CONTROLS

=item %NET_INFO_DESCRIPTION

Used with NetUseDel, NetWkStaTransportDel, NetUseAdd , GetInfo and Enum with the flags parameter. 
English descriptions of the status flag (asg_type) of a NetUseAdd

=item %NET_STATUS_DESCRIPTION

English descriptions of the status flag of a NetUseEnum or NetUseGetInfo call

=item %PRIVILEGE_NAMES

A list of privileges which can be set or used when querying. These apply to the functions in the 
L<Policy and Privileges (LSA)> section.

=back

=head1 FUNCTIONS

C<I_NetLogonControl> ---
C<I_NetLogonControl2> ---
C<LogonControlQuery> ---
C<LogonControlReplicate> ---
C<LogonControlSynchronize> ---
C<LogonControlPdcReplicate> ---
C<LogonControlRediscover> ---
C<LogonControlTCQuery> ---
C<LogonControlTransportNotify> ---
C<LogonControlFindUser> ---
C<NetEnumerateTrustedDomains> ---
C<I_NetGetDCList>

C<LsaQueryInformationPolicy> ---
C<LsaSetInformationPolicy> ---
C<LsaQueryAuditLogPolicy> ---
C<LsaQueryAuditEventsPolicy> ---
C<LsaSetAuditEventsPolicy> ---
C<LsaQueryPrimaryDomainPolicy> ---
C<LsaSetPrimaryDomainPolicy> ---
C<LsaQueryPdAccountPolicy> ---
C<LsaQueryAccountDomainPolicy> ---
C<LsaSetAccountDomainPolicy> ---
C<LsaQueryServerRolePolicy> ---
C<LsaSetServerRolePolicy> ---
C<LsaQueryReplicaSourcePolicy> ---
C<LsaSetReplicaSourcePolicy> ---
C<LsaQueryDefaultQuotaPolicy> ---
C<LsaSetDefaultQuotaPolicy> ---
C<LsaQueryAuditFullPolicy> ---
C<LsaSetAuditFullPolicy> ---
C<LsaQueryDnsDomainPolicy> ---
C<LsaSetDnsDomainPolicy> ---
C<LsaQueryTrustedDomainInfo> ---
C<LsaSetTrustedDomainInformation> ---
C<LsaSetTrustedDomainInfo> ---
C<LsaQueryTrustedDomainNameInfo> ---
C<LsaSetTrustedDomainNameInfo> ---
C<LsaQueryTrustedPosixOffsetInfo> ---
C<LsaSetTrustedPosixOffsetInfo> ---
C<LsaQueryTrustedPasswordInfo> ---
C<LsaSetTrustedPasswordInfo> ---
C<LsaRetrievePrivateData> ---
C<LsaStorePrivateData> ---
C<LsaEnumerateTrustedDomains> ---
C<LsaLookupNames> ---
C<LsaLookupSids> ---
C<LsaEnumerateAccountsWithUserRight> ---
C<LsaEnumerateAccountRights> ---
C<LsaAddAccountRights> ---
C<LsaRemoveAccountRights>

C<GrantPrivilegeToAccount> ---
C<RevokePrivilegeFromAccount> ---
C<EnumAccountPrivileges> ---
C<EnumPrivilegeAccounts>

C<NetDfsAdd> ---
C<NetDfsEnum> ---
C<NetDfsGetInfo> ---
C<NetDfsRemove> ---
C<NetDfsSetInfo> ---
C<NetDfsMove> ---
C<NetDfsRename> ---
C<NetDfsAddFtRoot> ---
C<NetDfsRemoveFtRoot> ---
C<NetDfsRemoveFtRootForced> ---
C<NetDfsAddStdRoot> ---
C<NetDfsAddStdRootForced> ---
C<NetDfsRemoveStdRoot> ---
C<NetDfsManagerInitialize> ---
C<NetDfsGetClientInfo> ---
C<NetDfsSetClientInfo> ---
C<NetDfsGetDcAddress>

C<NetGetJoinableOUs> ---
C<NetGetJoinInformation> ---
C<NetJoinDomain> ---
C<NetRenameMachineInDomain> ---
C<NetUnjoinDomain> ---
C<NetValidateName> ---
C<NetRegisterDomainNameChangeNotification> ---
C<NetUnregisterDomainNameChangeNotification>

C<NetFileClose> ---
C<NetFileEnum> ---
C<NetFileGetInfo>

C<MultinetGetConnectionPerformance> ---
C<NetGetAnyDCName> ---
C<NetGetDCName> ---
C<NetGetDisplayInformationIndex> ---
C<NetQueryDisplayInformation>

C<NetGroupAdd> ---
C<NetGroupAddUser> ---
C<NetGroupDel> ---
C<NetGroupDelUser> ---
C<NetGroupEnum> ---
C<NetGroupGetInfo> ---
C<NetGroupGetUsers> ---
C<NetGroupSetInfo> ---
C<NetGroupSetUsers>

C<NetLocalGroupAdd> ---
C<NetLocalGroupAddMember> ---
C<NetLocalGroupAddMembers> ---
C<NetLocalGroupAddMembersBySid> ---
C<NetLocalGroupDel> ---
C<NetLocalGroupDelMember> ---
C<NetLocalGroupDelMembers> ---
C<NetLocalGroupDelMembersBySid> ---
C<NetLocalGroupEnum> ---
C<NetLocalGroupGetInfo> ---
C<NetLocalGroupGetMembers> ---
C<NetLocalGroupSetInfo> ---
C<NetLocalGroupSetMembers> ---
C<NetLocalGroupSetMembersBySid>

C<NetMessageBufferSend> ---
C<NetMessageNameAdd> ---
C<NetMessageNameDel> ---
C<NetMessageNameEnum> ---
C<NetMessageNameGetInfo>

C<NetRemoteTOD> ---
C<NetRemoteComputerSupports>

C<NetReplExportDirAdd> ---
C<NetReplExportDirDel> ---
C<NetReplExportDirEnum> ---
C<NetReplExportDirGetInfo> ---
C<NetReplExportDirLock> ---
C<NetReplExportDirSetInfo> ---
C<NetReplExportDirUnlock> ---
C<NetReplGetInfo> ---
C<NetReplImportDirAdd> ---
C<NetReplImportDirDel> ---
C<NetReplImportDirEnum> ---
C<NetReplImportDirGetInfo> ---
C<NetReplImportDirLock> ---
C<NetReplImportDirUnlock> ---
C<NetReplSetInfo>

C<NetScheduleJobAdd> ---
C<NetScheduleJobDel> ---
C<NetScheduleJobEnum> ---
C<NetScheduleJobGetInfo>

C<NetServerDiskEnum> ---
C<NetServerEnum> ---
C<NetServerGetInfo> ---
C<NetServerSetInfo> ---
C<NetServerTransportAdd> ---
C<NetServerTransportDel> ---
C<NetServerTransportEnum>

C<NetSessionDel> ---
C<NetSessionEnum> ---
C<NetSessionGetInfo>

C<NetStatisticsGet>

C<NetShareAdd> ---
C<NetShareCheck> ---
C<NetShareDel> ---
C<NetShareEnum> ---
C<NetShareGetInfo> ---
C<NetShareSetInfo> ---
C<NetConnectionEnum>

C<NetUserAdd> ---
C<NetUserChangePassword> ---
C<NetUserCheckPassword> ---
C<NetUserDel> ---
C<NetUserEnum> ---
C<NetUserGetGroups> ---
C<NetUserGetInfo> ---
C<NetUserGetLocalGroups> ---
C<NetUserSetGroups> ---
C<NetUserSetInfo> ---
C<NetUserSetProp> ---
C<NetUserModalsGet> ---
C<NetUserModalsSet>

C<NetWkstaGetInfo> ---
C<NetWkstaSetInfo> ---
C<NetWkstaTransportAdd> ---
C<NetWkstaTransportDel> ---
C<NetWkstaTransportEnum> ---
C<NetWkstaUserGetInfo> ---
C<NetWkstaUserSetInfo> ---
C<NetWkstaUserEnum>

C<WNetAddConnection> ---
C<WNetCancelConnection> ---
C<WNetEnumResource> ---
C<WNetConnectionDialog> ---
C<WNetDisconnectDialog> ---
C<WNetGetConnection> ---
C<WNetGetNetworkInformation> ---
C<WNetGetProviderName> ---
C<WNetGetResourceInformation> ---
C<WNetGetResourceParent> ---
C<WNetGetUniversalName> ---
C<WNetGetUser> ---
C<WNetUseConnection>

C<StartService> ---
C<StopService> ---
C<PauseService> ---
C<ContinueService> ---
C<InterrogateService> ---
C<ControlService> ---
C<CreateService> ---
C<DeleteService> ---
C<EnumServicesStatus> ---
C<EnumDependentServices> ---
C<ChangeServiceConfig> ---
C<GetServiceDisplayName> ---
C<GetServiceKeyName> ---
C<LockServiceDatabase> ---
C<UnlockServiceDatabase> ---
C<QueryServiceLockStatus> ---
C<QueryServiceConfig> ---
C<QueryServiceStatus> ---
C<QueryServiceObjectSecurity> ---
C<SetServiceObjectSecurity> ---
C<QueryServiceConfig2> ---
C<ChangeServiceConfig2> ---
C<QueryServiceStatusEx> ---
C<EnumServicesStatusEx>

C<ReadEventLog> ---
C<GetEventDescription> ---
C<BackupEventLog> ---
C<ClearEventLog> ---
C<ReportEvent> ---
C<GetNumberOfEventLogRecords> ---
C<GetOldestEventLogRecord>

C<WTSEnumerateServers> ---
C<WTSOpenServer> ---
C<WTSCloseServer> ---
C<WTSEnumerateSessions> ---
C<WTSEnumerateProcesses> ---
C<WTSTerminateProcess> ---
C<WTSQuerySessionInformation> ---
C<WTSQueryUserConfig> ---
C<WTSSetUserConfig> ---
C<WTSSendMessage> ---
C<WTSDisconnectSession> ---
C<WTSLogoffSession> ---
C<WTSShutdownSystem> ---
C<WTSWaitSystemEvent>

C<SidToString> ---
C<StringToSid> ---
C<GuidToString> ---
C<StringToGuid>

=head2 Windows 2000

This version of Win32::Lanman now supports/implements specific calls which are only available in Windows 2000. If you call one of these 
routines from NT4, the call will fail and GetLastError() returns the code 127 (procedure not found).

=head2 NOTE

All of the functions return false if they fail. You can call
Win32::Lanman::GetLastError() to get more error information.

Throughout $server is the name of the server you want the call to run against.
If set to '', this signifies the local machine.

In previous versions of this module, you were required to put two backslashes 
before the server name, as you would do at the cmd prompt, but from version 1.05 
all server names will be automatically prefaced by two backslashes if they are missing.

Note: Win32::Lanman defines some private error codes, which are not currently exported. 
You cannot call "net helpmsg" for a description of these. Instead you can find the 
meaning in the usererror.h file included as part of the distribution.

=head2 DFS

=over 4

Here we use the term <C storage> to mean a root share, (Dfs path) associated with a Dfs link. 
Throughout this section if you specify a server and share the function applies to the server 
and share within the dfs tree. If you leave them empty, the function runs relative to the dfsroot.

=item NetDfsAdd($entrypath, $server, $share, [, $comment[, $flags]])

Adds a new volume to the dfs root or adds another storage to a
existing dfs volume.

=item NetDfsEnum($server, \@dfs)

Enumerates all DFS-Entries on a DFS-Server.

=item NetDfsGetInfo($entrypath, $server, $share, \%dfs)

Gets information about a dfs volume. 
When you specify $server and $share you will get information 
of the volume and the specified storage.
If $server and $share are empty, retrieves information for all 
storages in the volume.

=item NetDfsRemove($entrypath, $server, $share)

Removes a volume or storage space from the dfs directory; when applied
to the latest storage in a volume, removes the volume from the dfs.

=item NetDfsSetInfo($entrypath, $server, $share, \%dfs)

Sets dfs volume information. Currently, you can only set the volume comment.

=item NetDfsRename($oldEntrypath, $newEntrypath)

Renames a dfs volume. Not supported in NT4.

=item NetDfsMove($oldEntrypath, $newEntrypath)

Moves a dfs volume. Not supported in NT4.

=item NetDfsAddFtRoot($server, $rootshare, $ftdfs [, $comment])

Creates the root of a new domain-based Distributed File System implementation. If the root 
already exists, the function adds the specified server and share to the root. This function 
requires Windows 2000.

=item NetDfsRemoveFtRoot($server, $rootshare, $ftdfs)

Removes the specified server and share from a domain-based Distributed File System root. If 
the share is the last associated with the Dfs root, the function also deletes the root. This 
function requires Windows 2000.

=item NetDfsRemoveFtRootForced($domain, $server, $rootshare, $ftdfs)

Removes the specified server and share from a domain-based Distributed File System root, 
even if the server is offline. If the share is the last associated with the Dfs root, the 
function also deletes the root. This function requires Windows 2000.

=item NetDfsAddStdRoot($server, $rootshare [, $comment])

Creates the root for a new stand-alone Distributed File System implementation. This function 
requires Windows 2000.

=item NetDfsAddStdRootForced($server, $rootshare, $store [, $comment])

Creates the root for a new stand-alone Distributed File System implementation in a cluster 
technology environment, allowing an offline share to host the Dfs root. This function 
requires Windows 2000. 

=item NetDfsRemoveStdRoot($server, $rootshare)

Removes the server and share at the root of a stand-alone Distributed File System implementation.
This function requires Windows 2000.

=item NetDfsManagerInitialize($server)

Reinitializes the Dfs service on the specified server. This function requires Windows 2000.

=item NetDfsGetClientInfo($entrypath, $server, $share, \%info)

Retrieves information about a Distributed File System link in the named Dfs root. This function 
requires Windows 2000.

=item NetDfsSetClientInfo($entrypath, $server, $share, \%info)

Associates information with a Distributed File System link in the named Dfs root. This function 
requires Windows 2000.

=item NetDfsGetDcAddress($server, \%info)

Retrieves information about a Distributed File System domain controller. This function requires 
Windows 2000.

=back

=head2 DFS EXAMPLES:

=over 4

=item NetDfsAdd($entrypath, $server, $share, [, $comment[, $flags]])

create new dfs volume in the dfs root

 if(!Win32::Lanman::NetDfsAdd("\\\\testdfsserver\\dfsrootdir\\dfsdir",
  "testserver1", "testshare1", "comment", &Win32::Lanman::DFS_ADD_VOLUME))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

add an additional storage space to an existing dfs volume

 if(!Win32::Lanman::NetDfsAdd("\\\\testdfsserver\\dfsrootdir\\dfsdir", "testserver2", "testshare2", "comment", &Win32::Lanman::DFS_RESTORE_VOLUME))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetDfsEnum($server, \@dfs)

Enumerates all directories in a dfs structure. @dfs contains all directories in the dfs root

 if(!Win32::Lanman::NetDfsEnum("\\\\testserver", \@dfs))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $dfspath (@dfs)
 {
	print "${$dfspath}{'entrypath'}\t${$dfspath}{'comment'}\t${$dfspath}{'state'}\n";

	if(exists(${$dfspath}{'storage'}))
	{
		$storage = ${$dfspath}{'storage'};

		for($count = 0; $count <= $#$storage; $count++)
		{
			print "\t${$$storage[$count]}{'servername'}";
			print "\t${$$storage[$count]}{'sharename'}";
			print "\t${$$storage[$count]}{'state'}\n";
		}
	}
 }

=item NetDfsGetInfo($entrypath, $server, $share, \%dfs)

gets information about volume \\testdfsserver\dfsrootdir\dfsdir and the
storage testserver2\testshare2

 if(!Win32::Lanman::NetDfsGetInfo("\\\\testdfsserver\\dfsrootdir\\dfsdir", "testserver2", "testshare2", \%dfs))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }


 print "$dfs{'entrypath'}\t$dfs{'comment'}\t$dfs{'state'}\n";
 if(exists($dfs{'storage'}))
 {
	$store = $dfs{'storage'};

	for($count = 0; $count <= $#$store; $count++)
	{
		print "\t${$$store[$count]}{'servername'}";
		print "\t${$$store[$count]}{'sharename'}";
		print "\t${$$store[$count]}{'state'}\n";
	}
 }

gets information about volume \\testdfsserver\dfsrootdir\dfsdir and all
storages in \\testdfsserver\dfsrootdir\dfsdir

 if(!Win32::Lanman::NetDfsGetInfo("\\\\testdfsserver\\dfsrootdir\\dfsdir", '', '', \%dfs))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "$dfs{'entrypath'}\t$dfs{'comment'}\t$dfs{'state'}\n";
 if(exists($dfs{'storage'}))
 {
	$store = $dfs{'storage'};

	for($count = 0; $count <= $#$store; $count++)
	{
		print "\t${$$store[$count]}{'server'}";
		print "\t${$$store[$count]}{'share'}";
		print "\t${$$store[$count]}{'state'}\n";
	}
 }

=item NetDfsRemove($entrypath, $server, $share)

removes the storage testserver2\testshare2 in volume
\\testdfsserver\\dfsrootdir\\dfsdir. If there is only one storage, the
volume will be removed too.

 if(!Win32::Lanman::NetDfsRemove("\\\\testdfsserver\\dfsrootdir\\dfsdir", "testserver2", "testshare2"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetDfsSetInfo($entrypath, $server, $share, \%dfs)

Sets dfs volume comment to "this is a volume name". There is no
difference, if you specify a storage or not.

 if(!Win32::Lanman::NetDfsSetInfo("\\\\testdfsserver\\dfsrootdir\\dfsdir", '', '', {'comment' => 'this is a volume name'}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetDfsAddFtRoot($server, $rootshare, $ftdfs [, $comment])

Creates the new dfs root testroot on the server \\testserver. It uses the share name testdfs and
sets the comment test comment.

 if(!Win32::Lanman::NetDfsSetInfo("\\\\testserver", "testdfs", "testroot", "test comment"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetDfsRemoveFtRoot($server, $rootshare, $ftdfs)

Removes the dfs share testdfs from the dfs root testdfs on the server \\testserver. If testdfs
is the last share in the dfs root, the function deletes the root testroot.

 if(!Win32::Lanman::NetDfsRemoveFtRoot("\\\\testserver", "testdfs", "testroot"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetDfsRemoveFtRootForced($domain, $server, $rootshare, $ftdfs)

Removes the dfs share testdfs from the dfs root testroot in the domain testdomain.com, even if the 
dfs server which hosts the share testdfs is offline. The function will be executed on the server 
\\testserver. If dfstest is the last share in the dfs root, the function deletes the root testroot.

 if(!Win32::Lanman::NetDfsRemoveFtRootForced("testdomain.com", "\\\\testserver", "testdfs", 
					     "testroot"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetDfsAddStdRoot($server, $rootshare [, $comment])

Creates the root testroot for a new stand-alone Distributed File System implementation on the
server \\testserver and sets the comment to test comment.

 if(!Win32::Lanman::NetDfsAddStdRoot("\\\\testserver", "testroot", "test comment"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetDfsAddStdRootForced($server, $rootshare, $store [, $comment])

Creates the root testroot for a new stand-alone Distributed File System implementation on the
server \\testserver and sets the comment to test comment, even if the share does not exist.

 if(!Win32::Lanman::NetDfsAddStdRootForced("\\\\testserver", "testroot", "c:\\testdir", 
					   "test comment"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetDfsRemoveStdRoot($server, $rootshare)

Removes the server/share \\testserver\\testdfs at the root of a stand-alone Distributed File System 
implementation.

 if(!Win32::Lanman::NetDfsRemoveStdRoot("\\\\testserver", "testdfs"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetDfsManagerInitialize($server)

Reinitializes the Dfs service on the server \\testserver. 

 if(!Win32::Lanman::NetDfsManagerInitialize("\\\\testserver"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetDfsGetClientInfo($entrypath, $server, $share, \%info)

Retrieves information about the \\testserver\testroot dfs root.

 if(!Win32::Lanman::NetDfsGetClientInfo("\\\\testserver\\testroot", "", "", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key(sort keys info)
 {
	if($key eq "storage")
	{
		foreach $count (0 .. $#{$info{$key}})
		{
			print "storage[$count]:\n";

			foreach $skey (sort keys %{${$info{$key}}[$count]})
			{
				print "\t$skey=${${$info{$key}}[$count]}{$skey}\n";
			}
		}		
	}
	else
	{
		print "$key=$info{$key}\n";
	}
 }

Retrieves information about the testdfs link in the \\testserver\testroot dfs root.

 if(!Win32::Lanman::NetDfsGetClientInfo("\\\\testserver\\testroot", "\\\\testserver", "testdfs", 
					\%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetDfsSetClientInfo($entrypath, $server, $share, \%info)

Set the timeout to 200 seconds for the testdfs link in the \\testserver\testroot dfs root.

 if(!Win32::Lanman::NetDfsSetClientInfo("\\\\testserver\\testroot", "\\\\testserver", "testdfs", 
					{ tomeout => 200 }))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetDfsGetDcAddress($server, \%info)

Retrieves information about a Distributed File System domain controller \\testserver.

 if(!Win32::Lanman::NetDfsGetDcAddress("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key(sort keys info)
 {
	print "$key=$info{$key}\n";
 }

=back

=head2 Directory Services

The following functions are related to The Active Directory.

=over 4

=item NetGetJoinableOUs($server, $domain, $account, $password, \@ous)

Retrieves a list of organizational units in which a computer account can be created. This function 
requires Windows 2000.

=item NetGetJoinInformation($server, \%info)

Retrieves the join status information for the specified server. This function requires Windows 2000.

=item NetJoinDomain($server, $domain, $account_ou, $account, $password, $options)

Joins a computer to a workgroup or domain. This function requires Windows 2000.

=item NetRenameMachineInDomain($server, $new_machine_name, $account, $password, $options)

Changes the name of a computer in a domain. This function requires Windows 2000.

=item NetUnjoinDomain($server, $account, $password, $options)

Unjoins a computer from a workgroup or a domain. This function requires Windows 2000.

=item NetValidateName($server, $name, $account, $password, $name_type)

Verifies the validity of a computer, workgroup or domain name. This function requires Windows 2000.

=item NetRegisterDomainNameChangeNotification($notification_handle)

Enables an application to receive a notification when the name of the current domain changes. 
When the domain name changes, the specified event object is set to the signaled state. This function 
requires Windows 2000.

=item NetUnregisterDomainNameChangeNotification($notification_handle)

Ends a domain name change notification started by the NetRegisterDomainNameChangeNotification 
function. This function requires Windows 2000.

=back

=head2 Directory Services EXAMPLES:

=over 4

=item NetGetJoinableOUs($server, $domain, $account, $password, \@ous)

Retrieves a list of organizational units in the domain testdomain.com in which a computer account can 
be created. The command is executed on the server \\testserver.

 if(!Win32::Lanman::NetGetJoinableOUs("\\\\testserver", "testdomain.com", "testaccount", "testpassword", \@ous))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $ou(@ous)
 {
	print "$ou\n";
 }

=item NetGetJoinInformation($server, \%info)

Retrieves the join status information for the server \\testserver.

 if(!Win32::Lanman::NetGetJoinInformation("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key (sort keys %info)
 {
	print "$key=$info{$key}\n";
 }

=item NetJoinDomain($server, $domain, $account_ou, $account, $password, $options)

Joins the computer \\testserver to the domain testdomain.com. The computer will be rejoined if it is 
already joined.

 if(!Win32::Lanman::NetJoinDomain("\\\\testserver", "testdomain.com", "testou", "testaccount", 
				  "testpassword", &NETSETUP_JOIN_DOMAIN | &NETSETUP_DOMAIN_JOIN_IF_JOINED))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetRenameMachineInDomain($server, $new_machine_name, $account, $password, $options)

Changes the name of a the computer testserver to testcomputer in the domain.

 if(!Win32::Lanman::NetRenameMachineInDomain("\\\\testserver", "testcomputer", "testaccount", 
					     "testpassword", &NETSETUP_ACCT_CREATE))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetUnjoinDomain($server, $account, $password, $options)

Unjoins the computer \\testserver from the domain.

 if(!Win32::Lanman::NetUnjoinDomain("\\\\testserver", "testaccount", "testpassword"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetValidateName($server, $name, $account, $password, $name_type)

Verifies the validity of domain name testdomain.

 if(!Win32::Lanman::NetValidateName("\\\\testserver", "testdomain", "testaccount", "testpassword",  
				    &NetSetupDomain))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetRegisterDomainNameChangeNotification($notification_handle)

Enables an application to receive a notification when the name of the current domain changes. 

 # you must have a valid handle
 # $handle = 

 if(!Win32::Lanman::NetRegisterDomainNameChangeNotification($handle))  
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 # wait til the handle is signaled
 # WaitForSingleObject($handle)

=item NetUnregisterDomainNameChangeNotification($notification_handle)

Ends a domain name change notification started by the NetRegisterDomainNameChangeNotification 
function.

 # you must have a valid handle
 # $handle = 

 if(!Win32::Lanman::NetUnregisterDomainNameChangeNotification($handle))  
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=back

=head2 File

=over 4

=item NetFileEnum($server, $basepath, $user, \@info)

Supplies information about some or all open files on a server.

=item NetFileGetInfo($server, $fileid, \%info)

Retrieves information about a particular open file (specified by $fileid) resource on $server.

=item NetFileClose($server, $fileid)

Closes a file on a server.

=back

=head2 File EXAMPLES:

=over 4

=item NetFileEnum($server, $basepath, $user, \@info)

Enumerates info about some or all open files on $server.

The following sample enumerates all information about all 
open files on server \\testserver.

 if(!Win32::Lanman::NetFileEnum("\\\\testserver", '', '', \@infos))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $info (@infos)
 {
	@keys = keys(%$info);

	foreach $key(@keys)
	{
		print "$key: ${$info}{$key}\n";
	}
	print "\n";
 }

The following code supplies information about all open files below c:\winnt opened by user
testuser on server \\testserver.

 if(!Win32::Lanman::NetFileEnum("\\\\testserver", "c:\\winnt", "testuser", \@infos))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $info (@infos)
 {
	@keys = keys(%$info);

	foreach $key(@keys)
	{
		print "$key: ${$info}{$key}\n";
	}
	print "\n";
 }

=item NetFileGetInfo($server, $fileid, \%info)

Retrieves information about a particular file being opened on $server,
fileid must be valid and obtained by NetFileEnum.

 $fileid = 125;
 if(!Win32::Lanman::NetFileGetInfo("\\\\testserver", $fileid, \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys(%info);

 foreach $key(@keys)
 {
	print "$key: $info{$key}\n";
 }

=item NetFileClose($server, $fileid)

As with NetFileGetInfo, fileid must be valid and obtained by NetFileEnum.
The following code closes the file with fileid 125 on server \\testserver. 

 $fileid = 125;
 if(!Win32::Lanman::NetFileClose("\\\\testserver", $fileid))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=back

=head2 Get

=over 4

=item MultinetGetConnectionPerformance(\%netresource, \%info)

Returns information about the expected performance of a connection used to access a
network resource.

=item NetGetAnyDCName($server, $domain, \$dcname)

Returns the name of a domain controller in a specified domain.
Does NOT work with Trusted Domains. You get the error code 1355 (domain doesn't exist).

In this case proceed as follows: get your pdc or a bdc and execute the NetGetAnyDCName call there.
 
 # your primary domain name
 $my_domain = "my_domain";
 # a trusted domain name
 $trust_domain = "trust_domain";
 
 # get the pdc on your local machine for $my_domain
 NetGetDCName('', $my_domain, \$pdc);
 # now get a dc in the trusted domain
 NetGetAnyDCName($pdc, $trusted_domain, \$dc);

=item NetGetDCName($server, $domain, \$pdcname)

Returns the name of the primary domain controller for domain $domain.

=item NetGetDisplayInformationIndex($server, $level, $prefix, \$index)

Gets the index of the first display information entry whose name begins with a specified
string or alphabetically follows the string.

=item NetQueryDisplayInformation($server, $level, $index, $entries, \@info)

Returns user, computer, or global group account information.
The number of entries to retrieve ($entries) must be supplied and must be a decimal digit

=back

=head2 Get EXAMPLES:

=over 4

=item MultinetGetConnectionPerformance(\%netresource, \%info)

Returns information about the expected performance of a connection
specified in %netresource used to access a network resource. You have to
specify a remote name (server and share) or a local name (redirected
device name)

 if(!Win32::Lanman::MultinetGetConnectionPerformance({'remotename' => "\\\\testserver\\ipc\$"}, \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys(%info);

 foreach $key(@keys)
 {
	print "$key: $info{$key}\n";
 }

 if(!Win32::Lanman::MultinetGetConnectionPerformance({'localname' => "f:"}, \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys(%info);

 foreach $key(@keys)
 {
	print "$key: $info{$key}\n";
 }

=item NetGetAnyDCName($server, $domain, \$dcname)

Returns the name of a domain controller in domain testdomain. The
command will be executed on server \\testserver.

 if(!Win32::Lanman::NetGetAnyDCName("\\\\testserver", "testdomain", \$dcname))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }
 print $dcname;

=item NetGetDCName($server, $domain, \$pdcname)

Returns the name of the primary domain controller in domain testdomain.
The command will be executed on server \\testserver.

 if(!Win32::Lanman::NetGetDCName("\\\\testserver", "testdomain", \$pdcname))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }
 print $pdcname;

=item NetGetDisplayInformationIndex($server, $level, $prefix, \$index)

Gets the index of the first display information entry whose name begins
with test or alphabetically follows test. The command will be executed
on server \\testserver. You can get an index for users accounts (pass
1), machine accounts (pass 2) or group accounts (pass 3).

 if(!Win32::Lanman::NetGetDisplayInformationIndex("\\\\testserver", 1, "test", \$index))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }
 print $index;

=item NetQueryDisplayInformation($server, $level, $index, $entries, \@info)

Returns user, computer, or global group account information. The command
will be excuted on server \\testserver. A maximum of 10 accounts will be
returned for each call. It starts at index 12 (every account has an
index starting at 0). You can get a starting index by call
NetGetDisplayInformationIndex. At first we get user accounts.

 $index = 12;
 while(Win32::Lanman::NetQueryDisplayInformation("\\\\testserver", 1, $index, 10, \@users))
 {
	foreach $user (@users)
	{
		print "${$user}{'name'}\t";
		print "${$user}{'comment'}\t";
		print "${$user}{'full_name'}\t";
		print "${$user}{'flags'}\t";
		print "${$user}{'user_id'}\t";
		print "${$user}{'next_index'}\n";
	}

	last
		if $#users == -1;

	$index = ${$users[$#users]}{'next_index'};
 }

Dito for machine accounts. Start at machines names beginning with test.
We get 20 accounts on each call.

 if(!Win32::Lanman::NetGetDisplayInformationIndex("\\\\testserver", 2, "test", \$index))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 while(Win32::Lanman::NetQueryDisplayInformation("\\\\testserver", 2, $index, 20, \@machines))
 {
	foreach $machine (@machines)
	{
		print "${$machine}{'name'}\t";
		print "${$machine}{'comment'}\t";
		print "${$machine}{'flags'}\t";
		print "${$machine}{'user_id'}\t";
		print "${$machine}{'next_index'}\n";
	}

	last
		if $#machines == -1;

	$index = ${$machines[$#machines]}{'next_index'};
 }

Dito for group accounts. Start at begin (index position 0). We get 5
accounts on each call.

 $index = 0;
 while(Win32::Lanman::NetQueryDisplayInformation("\\\\testserver", 3, $index, 5, \@groups))
 {
	foreach $group (@groups)
	{
		print "${$group}{'name'}\t";
		print "${$group}{'comment'}\t";
		print "${$group}{'group_id'}\t";
		print "${$group}{'attributes'}\t";
		print "${$group}{'next_index'}\n";
	}

	last
		if $#groups == -1;

	$index = ${$groups[$#groups]}{'next_index'};
 }

=back

=head2 Groups

=over 4

=item NetGroupAdd($server, $group[, $comment])

Creates a new global group $group on $server.
An optional $comment may be specified.

=item NetGroupAddUser($server, $group, $user)

Adds a user to a global group $group on $server.

=item NetGroupDel($server, $group)

Deletes the global group $group on $server.

=item NetGroupDelUser($server, $group, $user)

Deletes a user from a global group $group on server $server.

=item NetGroupEnum($server, \@groups)

Enumerates all global groups defined on server $server. If successfull, each
array element contains a hash with group name ('name'), comment
('comment'), group id ('group_id') and attributes ('attributes').

=item NetGroupGetInfo($server, $group, \%info)

Gets the name, comment, group id and attributes of a global group, storing the result in %info
($group should be equal to $info{'name'}).

=item NetGroupGetUsers($server, $group, \@users)

Gets the users in a global group.

=item NetGroupSetInfo($server, $group, \%info)

Sets the name and the comment of a global group.
Note if $group is set and not equal to $info{'name'}, the group will be renamed. 
If $info{name} is not set, only the comment will be set.

=item NetGroupSetUsers($server, $group, \@users)

Sets the members of a global group.
Note: This operation is destructive; previous users will be removed.

=back

=head2 Group EXAMPLES:

=over 4

=item NetGroupAdd($server, $group[, $comment])

Creates a new global group testgroup on server \\testserver.
\\testserver must be a domain controller.

 if(!Win32::Lanman::NetGroupAdd("\\\\testserver", "testgroup", "test group comment"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetGroupAddUser($server, $group, $user)

Adds a user testuser to the global group testgroup on \\testserver.

 if(!Win32::Lanman::NetGroupAddUser("\\\\testserver", "testgroup", "testuser"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetGroupDel($server, $group)

Deletes the global group testgroup on server \\testserver.

 if(!Win32::Lanman::NetLocalGroupDel("\\\\testserver", "testgroup"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetGroupDelUser($server, $group, $user)

Removes a user testuser from global group testgroup on server \\testserver

 if(!Win32::Lanman::NetLocalGroupDelMembers("\\\\testserver", "testgroup", "testuser"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetGroupEnum($server, \@groups)

Retrieves all global groups on server \\testserver

 if(!Win32::Lanman::NetGroupEnum("\\\\testserver", \@groups))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $group (@groups)
 {
	print "${$group}{'name'}\t${$group}{'comment'}\t${$group}{'group_id'}\t${$group}{'attributes'}\n";
 }

=item NetGroupGetInfo($server, $group, \%info)

Retrieves information about the global group testgroup on server \\testserver

 if(!Win32::Lanman::NetGroupGetInfo("\\\\testserver", "testgroup", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "$info{'name'}\t$info{'comment'}\t$info{'group_id'}\t$info{'attributes'}\n";

=item NetGroupGetUsers($server, $group, \@users)

Retrieves all user in global group testgroup on server \\testserver

 if(!Win32::Lanman::NetGroupGetUsers("\\\\testserver", "testgroup", \@users))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $user (@users)
 {
	#don't print these binary data
	#print "${$user}{'sid'}\n";
	print "${$user}{'name'}\t${$user}{'attributes'}\n";
 }

=item NetGroupSetInfo($server, $group, \%info)

Sets information for the global group testgroup on server \\testserver.
Only the group name and the comment can be set. Specifying a new name
renames the group.

 if(!Win32::Lanman::NetGroupSetInfo("\\\\testserver", "testgroup", {'name' => 'newtestgrp', 'comment' => 'comment for testgroup'}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetGroupSetUsers($server, $group, \@users)

Sets user user1, user2 and user3 as members of the global group
testgroup on server \\testserver. All previous group members will be
removed.

 if(!Win32::Lanman::NetGroupSetUsers("\\\\testserver", "testgroup", ['user1', 'user2', 'user3']))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=back

=head2 Local Groups

=over 4

=item NetLocalGroupAdd($server, $group[, $comment])

Creates a new local group $group on server $server. You can specify an
optional comment $comment.

=item NetLocalGroupAddMember($server, $group, $sid)

Adds users $sid to a local group on server $server.

=item NetLocalGroupAddMembers($server, $group, \@members)

Adds members (global groups or users) to a local group $group on
$server. You can specficy the users or global groups with or without
domain name.

=item NetLocalGroupAddMembersBySid($server, $group, \@members)

Adds members (global groups or users) to a local group $group on
$server. You must specficy the users or global groups by sid's.

=item NetLocalGroupDel($server, $group)

Deletes the local group $group on server $server.

=item NetLocalGroupDelMember($server, $group, $sid)

Removes users $sid from a local group $group on server $server.

=item NetLocalGroupDelMembers($server, $group, \@members)

Deletes members (global groups or users) of a local group $group on
server $server. You can specficy the users or global groups with or
without domain name.

=item NetLocalGroupDelMembersBySid($server, $group, \@members)

Deletes members (global groups or users) of a local group $group on
server $server. You must specficy the users or global groups by sid's.

=item NetLocalGroupEnum($server, \@groups)

Enumerates all local groups defined on server $server. If successfull, each
array element contains a hash with group name ('name') and comment
('comment').

=item NetLocalGroupGetInfo($server, $group, \%info)

Gets the name and the comment of a local group ($group should be returned equal to 
$info{'name'}).

=item NetLocalGroupGetMembers($server, $group, \@members)

Gets the members of a local group (users and global groups).

=item NetLocalGroupSetInfo($server, $group, \%info)

Sets the name and the comment of a local group ( if $group is not equal
to $info{'name'}, the group will be renamed).

=item NetLocalGroupSetMembers($server, $group, \@members)

Sets the members of a local group (previous members will be removed).
Members can be users and/or global groups.

=item NetLocalGroupSetMembersBySid($server, $group, \@members)

Sets the members of a local group (previous members will be removed).
You must specficy the users or global groups by sid's.

=back

=head2 Local Group EXAMPLES:

=over 4

=item NetLocalGroupAdd($server, $group[, $comment])

Creates a new local group testgroup on server \\testserver.

 if(!Win32::Lanman::NetLocalGroupAdd("\\\\testserver", "testgroup", "test group comment"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetLocalGroupAddMember($server, $group, $sid)

Adds testuser's $sid to the local group testgroup on server
\\testserver. You must retrieve the user sid with
Win32::LookupAccountName. $sid = ...

 if(!Win32::Lanman::NetLocalGroupAddMember("\\\\testserver", "testgroup", $sid))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetLocalGroupAddMembers($server, $group, \@members)

Adds global groups (glb_grp, domain\glb_grp) and/or users (user,
domain\user) to the local group testgroup on \\testserver.


 unless(Win32::Lanman::NetLocalGroupAddMembers("testserver", 
                                               "testgroup", 
                                               ['glb_grp', 'domain\glb_grp', 'user', 'domain\user'])
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetLocalGroupAddMembersBySid($server, $group, \@members)

Adds global groups (glb_grp, domain\glb_grp) and/or users (user,
domain\user) to the local group testgroup on \\testserver.

 unless(Win32::Lanman::LsaLookupNames("testserver", 
                                      ['glb_grp', 'domain\glb_grp', 'user', 'domain\user'], 
                                      \@sids))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @members = map { ${$_}{sid} } @sids;

 unless(Win32::Lanman::NetLocalGroupAddMembersBySid("testserver", "testgroup", \@members))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetLocalGroupDel($server, $group)

Deletes the local group testgroup on server \\testserver.

 unless(Win32::Lanman::NetLocalGroupDel("testserver", "testgroup"))
 {
	print 'Sorry, something went wrong; in ( Win32::Lanman::NetLocalGroupDel ) error: ';
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetLocalGroupDelMember($server, $group, $sid)

Removes testuser's $sid from the local group testgroup on server
\\testserver. You must retrieve the user sid with
Win32::LookupAccountName. $sid = ...

 if(!Win32::Lanman::NetLocalGroupDelMember("\\\\testserver", "testgroup", $sid))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetLocalGroupDelMembers($server, $group, \@members)

Removes groups (glb_grp, domain\glb_grp) and/or users (user,
domain\user) from the members of the local group testgroup on \\testserver.

 unless(Win32::Lanman::NetLocalGroupDelMembers("testserver", "testgroup", 
					    ['glb_grp', 'domain\glb_grp', 'user', 'domain\user'])
   )
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetLocalGroupDelMembersBySid($server, $group, \@members)

Removes groups (glb_grp, domain\glb_grp) and/or users (user,
domain\user) from the members of the local group testgroup on \\testserver.

 unless(Win32::Lanman::LsaLookupNames("testserver", 
                                      ['glb_grp', 'domain\glb_grp', 'user', 'domain\user'], 
                                      \@sids))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @members = map { ${$_}{sid} } @sids;

 unless(Win32::Lanman::NetLocalGroupDelMembersBySid("testserver", "testgroup", \@members))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetLocalGroupEnum($server, \@groups)

Retrieves all local groups on server \\testserver

 unless(Win32::Lanman::NetLocalGroupEnum("testserver", \@groups))
 {
	print 'Sorry, something went wrong in (Win32::Lanman::NetLocalGroupEnum) ; error: ';
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $group (@groups)
 {
	print "${$group}{'name'}\t${$group}{'comment'}\n";
 }

=item NetLocalGroupGetInfo($server, $group, \%info)

Retrieves information about the local group testgroup on server \\testserver

 if(!Win32::Lanman::NetLocalGroupGetInfo("\\\\testserver", "testgroup", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "$info{'name'}\t$info{'comment'}\n";

=item NetLocalGroupGetMembers($server, $group, \@members)

Retrieves all global groups and /or user in local group testgroup on server \\testserver

 if(!Win32::Lanman::NetLocalGroupGetMembers("\\\\testserver", "testgroup", \@members))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $member (@members)
 {
	#don't print these binary data
	#print "${$member}{'sid'}\n";
	print "${$member}{'domainandname'}\t${$member}{'sidusage'}\n";
 }

=item NetLocalGroupSetInfo($server, $group, \%info)

Sets information for the local group testgroup on server \\testserver.
Only the group name and the comment can be set. Since we specify a new name
the group is renamed.

 unless(Win32::Lanman::NetLocalGroupSetInfo("testserver", 
					    "testgroup", 
					    {'name' => 'newtestgrp', 
					     'comment' => 'comment for testgroup'}
					   )
       )
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetLocalGroupSetMembers($server, $group, \@members)

Sets users (user1 and testdomain\user1) and global groups
(testdomain\group1) as members of the local group testgroup on server
\\testserver. All previous group members will be removed.

 unless(Win32::Lanman::NetLocalGroupSetMembers("testserver", 
					       "testgroup", 
					       ['user1', 
						'testdomain\group1', 
						'testdomain\user1']
					      )
       )
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetLocalGroupSetMembersBySid($server, $group, \@members)

Sets users (user1 and testdomain\user1) and global groups
(testdomain\group1) as members of the local group testgroup on server
\\testserver. All previous group members will be removed.

 unless(Win32::Lanman::LsaLookupNames("testserver", 
                                      ['user1', 'testdomain\user1', 'testdomain\group1'], 
                                      \@sids))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @members = map { ${$_}{sid} } @sids;

 unless(Win32::Lanman::NetLocalGroupSetMembersBySid("testserver", "testgroup", \@members))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=back

=head2 Netlogon

=over 4

=item I_NetLogonControl($server, $function, \%info)

Queries, synchonizes or replicates the sam database between PDC and
$server. Avoid direct calls. Use the wrapper functions below.

=item I_NetLogonControl2($server, $function, $data, \%info)

Queries, synchonizes or replicates the sam database between PDC and
$server. Queries and resets secure channels. Notifies a new transport is
coming up. Finds user names. Avoid direct calls. Use the wrapper
functions below.

=item LogonControlQuery($server, \%info)

Queries the status of the sam database on $server.

=item LogonControlReplicate($server, \%info)

Replicates the changes of the sam database on $server.

=item LogonControlSynchronize($server, \%info)

Synchronizes the sam database between $server and a PDC.

=item LogonControlPdcReplicate($server, \%info)

Forces all BDC's to synchronize the sam database with the PDC $server.

=item LogonControlRediscover($server, $domain, \%info)

Resets the secure channel for a domain $domain on a server $server.

=item LogonControlTCQuery($server, $domain, \%info)

Queries the status of the secure channel for domain $domain on a server $server.

=item LogonControlTransportNotify($server, \%info)

Informs the server $server about the coming up of a new transport.

=item LogonControlFindUser($server, $user, \%info)

Finds a user $user in a trusted domain. The command will be executed on server $server.

=item NetEnumerateTrustedDomains($server, \@domains)

Enumerates all trusted domain names. The command will be executed on server $server.

=item I_NetGetDCList($server, $domain, \@controllers)

Enumerates all domain controllers in a domain. The command will be executed on server $server.

=back

=head2 Netlogon EXAMPLES:

=over 4

=item I_NetLogonControl($server, $function, \%info)

Queries the status of \\testserver. \\testserver must be a PDC or BDC.

 if(!Win32::Lanman::I_NetLogonControl("\\\\testserver", &NETLOGON_CONTROL_QUERY, \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

Replicates the sam changes of \\testserver with the PDC. \\testserver must be a BDC.

 if(!Win32::Lanman::I_NetLogonControl("\\\\testserver", &NETLOGON_CONTROL_REPLICATE, \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

Synchronizes the sam of \\testserver with the PDC. \\testserver must be a PDC or BDC.

 if(!Win32::Lanman::I_NetLogonControl("\\\\testserver", &NETLOGON_CONTROL_SYNCHRONIZE, \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

Forces to send a synchronize request to all BDC's. \\testserver must be a PDC.

 if(!Win32::Lanman::I_NetLogonControl("\\\\testserver", &NETLOGON_CONTROL_PDC_REPLICATE, \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

=item I_NetLogonControl2($server, $function, \%info)

Rediscovers a secure channel for domain testdomain on server \\testserver.

 if(!Win32::Lanman::I_NetLogonControl2("\\\\testserver", &NETLOGON_CONTROL_REDISCOVER, "testdomain", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

Queries the status of the secure channel for domain testdomain on server \\testserver.

 if(!Win32::Lanman::I_NetLogonControl2("\\\\testserver", &NETLOGON_CONTROL_TC_QUERY, "testdomain", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

Informs the server \\testserver about a new transport coming up.

 if(!Win32::Lanman::I_NetLogonControl2("\\\\testserver", &NETLOGON_CONTROL_TRANSPORT_NOTIFY, '', \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

Retrieves which trusted domain will log on user testuser. The command
will be excuted on server \\testserver.

 if(!Win32::Lanman::I_NetLogonControl2("\\\\testserver", &NETLOGON_CONTROL_FIND_USER, "testuser", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

=item LogonControlQuery($server, \%info)

Queries the status of \\testserver. \\testserver must be a PDC or BDC.

 if(!Win32::Lanman::LogonControlQuery("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

=item LogonControlReplicate($server, \%info)

Replicates the sam changes of \\testserver with the PDC. \\testserver must be a BDC.

 if(!Win32::Lanman::LogonControlReplicate("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

=item LogonControlSynchronize($server, \%info)

Synchronizes the sam of \\testserver with the PDC. \\testserver must be a PDC or BDC.

 if(!Win32::Lanman::LogonControlSynchronize("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

=item LogonControlPdcReplicate($server, \%info)

Forces a synchronize request to be sent to all BDC's. \\testserver must be a PDC.

 if(!Win32::Lanman::LogonControlPdcReplicate("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

=item LogonControlRediscover($server, $domain, \%info)

Rediscovers a secure channel for domain testdomain on server \\testserver.

 if(!Win32::Lanman::LogonControlRediscover("\\\\testserver", "testdomain", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

=item LogonControlTCQuery($server, $domain, \%info)

Queries the status of the secure channel for domain testdomain on server \\testserver.

 if(!Win32::Lanman::LogonControlTCQuery("\\\\testserver", "testdomain", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

=item LogonControlTransportNotify($server, \%info)

Informs the server \\testserver about the coming up of a new transport.

 if(!Win32::Lanman::LogonControlTransportNotify("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

=item LogonControlFindUser($server, $user, \%info)

Retrieves which trusted domain will log on user testuser. The command will be excuted
on server \\testserver.

 if(!Win32::Lanman::LogonControlFindUser("\\\\testserver", "testuser", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

=item NetEnumerateTrustedDomains($server, \@domains)

Enumerates all trusted domain names. The command will be executed on server \\testserver.

 if(!Win32::Lanman::NetEnumerateTrustedDomains("\\\\testserver", \@domains))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $domain (@domains)
 {
	print "$domain\n";
 }

=item I_NetGetDCList($server, $domain, \@controllers)

Enumerates all domain controllers in the domain testdomain. The command will be executed
on server \\testserver.

 if(!Win32::Lanman::I_NetGetDCList("\\\\testserver", "testdomain", \@servers))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $server (@servers)
 {
	print "$server\n";
 }

=back

=head2 Message Related Functions

=over 4

=item NetMessageBufferSend($server, $to, $from, $message)

Sends a message.

=item NetMessageNameAdd($server, $messagename)

Registers a message alias in the message name table.

=item NetMessageNameAdd($server, $messagename)

Deletes a message alias from the table of message aliases.

=item NetMessageNameEnum($server, \@info)

Lists the message aliases that will receive messages.

=item NetMessageNameGetInfo($server, $messagename, \$info)

Retrieves information about a message alias in the message name table.

=back

=head2 Message Related Functions EXAMPLES:

=over 4

=item NetMessageBufferSend($server, $to, $from, $message)

Sends the message "this is a message" from computer1 to user1. The command will be executed on
\\testserver.

 if(!Win32::Lanman::NetMessageBufferSend("\\\\testserver", "user1", "computer1", "this is a message"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetMessageNameAdd($server, $messagename)

Registers the message alias user1 in the message on server \\testserver.

 if(!Win32::Lanman::NetMessageNameAdd("\\\\testserver", "testuser1"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetMessageNameDel($server, $messagename)

Deletes the message alias user1 in the message on server \\testserver.

 if(!Win32::Lanman::NetMessageNameDel("\\\\testserver", "testuser1"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetMessageNameEnum($server, $messagename)

Lists the message aliases that will receive messages on server \\testserver.

 if(!Win32::Lanman::NetMessageNameEnum("\\\\testserver", \@info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach (@info)
 {
	print "$_\n";
 }

=item NetMessageNameGetInfo($server, $messagename, \$info)

Retrieves information about the message alias user1 in the message name
table on server \\testserver.

 if(!Win32::Lanman::NetMessageNameEnum("\\\\testserver", "user1", \$info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print $info;

=back

=head2 Policy and Privileges (LSA)

=over 4

=item LsaQueryInformationPolicy($server, $infotype, \%info)

Queries policy information. Don't call LsaQueryInformationPolicy directly. Use the 
LsaQueryXXXPolicy wrappers instead.

The following are equivalent, 
Win32::Lanman::LsaQueryInformationPolicy("", &PolicyAuditFullQueryInformation, \%info);
and
Win32::Lanman::LsaQueryAuditFullPolicy("", \%info);

Please use the second form , it is less prone to error.

=item LsaSetInformationPolicy($server, $infotype, \%info)

Sets policy information. Don't call LsaSetInformationPolicy directly. Use the 
LsaSetXXXPolicy wrappers instead (see below).

=item LsaQueryAuditLogPolicy($server, \%info)

Queries audit log policy information.

=item LsaQueryAuditEventsPolicy($server, \%info)

Queries audit event policy information (if auditing is enabled and which events will be
logged).

=item LsaSetAuditEventsPolicy($server, \%info)

Sets audit event policy information.

=item LsaQueryPrimaryDomainPolicy($server, \%info)

Queries primary domain policy information (domain name and domain sid).

=item LsaSetPrimaryDomainPolicy($server, \%info)

Sets primary domain policy information (domain name and domain sid).

=item LsaQueryPdAccountPolicy($server, \%info)

Queries the primary domain account used for authentication and lookup requests. It returns
always an empty string. This should be a bug in the call.

=item LsaQueryAccountDomainPolicy($server, \%info)

Queries account domain policy information (workstation name and sid).

=item LsaSetAccountDomainPolicy($server, \%info)

Sets account domain policy information (workstation name and sid).

=item LsaQueryServerRolePolicy($server, \%info)

Queries server role policy information (type of server: pdc, bdc).

=item LsaSetServerRolePolicy($server, \%info)

Sets server role policy information (type of server: pdc, bdc).

=item LsaQueryReplicaSourcePolicy($server, \%info)

Queries the replication source server (pdc) policy information.

=item LsaSetReplicaSourcePolicy($server, \%info)

Sets the replication source server (pdc) policy information.

=item LsaQueryDefaultQuotaPolicy($server, \%info)

Queries the default quota policy information.

=item LsaSetDefaultQuotaPolicy($server, \%info)

Sets the default quota policy information.

=item LsaQueryAuditFullPolicy($server, \%info)

Queries the audit full policy information (if a shutdown is raised, when the audit log
is full and if the log is full).

=item LsaQueryAuditFullPolicy($server, \%info)

Sets the audit full policy information (if a shutdown is raised, when the audit log
is full).

=item LsaQueryDnsDomainPolicy($server, \%info)

Queries the dns domain policy information. This call is only supported in nt 5 and it's
not tested!

=item LsaSetDnsDomainPolicy($server, \%info)

Sets the dns domain policy information. This call is only supported in nt 5 and it's
not tested!

=item LsaEnumerateTrustedDomains($server, \@domains)

Enumerates all trusted domains. If you execute this on a workstation or a member server,
you'll get your domain and the domain sid. If you execute this on a PDC or BDC, you'll
get a list of all trusted domains and their sid's.

=item LsaLookupNames($server, \@accounts, \@info)

Looks up for account names and returns the appropriate rid, domains, sid's and domain
sid's. Unlike to the LsaLookupNames api call, it returns success if at least one name
could be resolved. If an account couldn't be resolved, the use flag has the value 8
(SidTypeUnknown).

=item LsaLookupSids($server, \@sids, \@info)

Looks up for sid's and returns the appropriate names, domains, sid's and domain
sid's. Unlike to the LsaLookupsids api call, it returns success if at least one sid
could be resolved. If a sid couldn't be resolved, the use flag has the value 7
(SidTypeInvalid) or 8 (SidTypeUnknown).

=item LsaEnumerateAccountsWithUserRight($server, $privilege, \@sids)

Enumerates all sids granted a privilege. To convert sid's to account names use LsaLookupSids.
If the privilege is not granted to anybody, the error code is 259. This is not an error,
it's by design.

=item LsaEnumerateAccountRights($server, $sid, \@privileges)

Enumerates all privileges granted to a sid. To convert account names to sid's use
LsaLookupNames. If the sid has not granted any privileges, the error code is 2.
This is not an error, it's by design.

=item LsaAddAccountRights($server, $sid, \@privileges)

Grants privileges to a sid. To convert account names to sid's use LsaLookupNames. Be
really carefully with the sid. If the sid does not belong to a user, LsaAddAccountRights
creates a new user without a user name.

=item LsaRemoveAccountRights($server, $sid, \@privileges, [$all])

Removes privileges from a sid. To convert account names to sid's use LsaLookupNames.
If the optional parameter $all is not null, all privileges for $sid will be removed. In
this case, @privileges has no meaning. Note: there is a mistake in the documentation
from Microsoft (see the platform sdk). If you remove all privileges with the $all
parameter the account won't be deleted.

=item LsaQueryTrustedDomainInfo($server, $domainsid, $infotype, \%info)

Queries information about trusted domains. Don't call LsaQueryTrustedDomainInfo directly.
Use the wrappers LsaQueryTrustedXXXInfo instead.

=item LsaSetTrustedDomainInformation($server, $domainsid, $infotype, \%info)

Sets information about trusted domains. Don't call LsaSetTrustedDomainInformation
directly. Use the wrappers LsaSetTrustedXXXInfo instead.

=item LsaSetTrustedDomainInfo($server, $domainsid, $infotype, \%info)

Sets information about trusted domains. Don't call LsaSetTrustedDomainInfo directly. Use 
the wrappers LsaSetTrustedXXXInfo instead.

=item LsaQueryTrustedDomainNameInfo($server, $domainsid, \%info)

Queries the domain name info for a trusted domain.

=item LsaSetTrustedDomainNameInfo($server, $domainsid, \%info)

Sets the domain name info for a trusted domain. If the specified domain is not in the list 
of trusted domains, the function adds it.

=item LsaQueryTrustedPosixOffsetInfo($server, $domainsid, \%info)

Queries the posix rid used to create posix users or groups for a trusted domain.

=item LsaSetTrustedPosixOffsetInfo($server, $domainsid, \%info)

Sets the posix rid used to create posix users or groups for a trusted domain.

=item LsaQueryTrustedPasswordInfo($server, $domainsid, \%info)

Queries the passwords used by trust connections for a trusted domain.

=item LsaSetTrustedPasswordInfo($server, $domainsid, \%info)

Sets the passwords used by trust connections for a trusted domain.

=item LsaRetrievePrivateData($server, $key, \$data)

Retrieves private data that was stored by the LsaStorePrivateData.

=item LsaStorePrivateData($server, $key, \$data)

Stores or deletes private data under a specified registry key.

=item GrantPrivilegeToAccount($server, $privilege, \@accounts)

Grants a privilege to users and/or groups. Avoid using GrantPrivilegeToAccount. Use
LsaAddAccountRights instead.

=item RevokePrivilegeFromAccount($server, $privilege, \@accounts)

Revokes a privilege from users and/or groups. Avoid using RevokePrivilegeFromAccount. Use
LsaRemoveAccountRights instead.

=item EnumAccountPrivileges($server, $account, \@privileges)

Enumerates privileges held by an user or group. If the user has not granted any privileges,
the error code is 2. This is not an error, it's by design. Avoid using
EnumAccountPrivileges. Use LsaEnumerateAccountRights instead.

=item EnumPrivilegeAccounts($server, $privilege, \@accounts)

Enumerates all accounts (users and groups) granted a privilege. If the privilege is not granted
to anybody, the error code is 259. This is not a bug, it is by design. 

Avoid using EnumPrivilegeAccounts. Use LsaEnumerateAccountsWithUserRight instead.

=back

=head2 Policy and Privileges (LSA) EXAMPLES:

=over 4

=item LsaQueryInformationPolicy($server, $infotype, \%info)

Queries the audit log policies on server \\testserver. Don't call LsaQueryInformationPolicy
directly. Use the wrappers LsaQueryXXXPolicy instead (see examples below).

 if(!Win32::Lanman::LsaQueryInformationPolicy("\\\\testserver", &PolicyAuditLogInformation, \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key(sort keys %info)
 {
	print "$key=$info{$key}\n";
 }

=item LsaSetInformationPolicy($server, $infotype, \%info)

Sets the audit log policies on server \\testserver. Don't call LsaSetInformationPolicy
directly. Use the wrappers LsaSetXXXPolicy instead (see examples below).

 #events to audit
 $options[AuditCategorySystem] = &POLICY_AUDIT_EVENT_UNCHANGED;
 $options[AuditCategoryLogon] = &POLICY_AUDIT_EVENT_SUCCESS;
 $options[AuditCategoryObjectAccess] = &POLICY_AUDIT_EVENT_FAILURE;
 $options[AuditCategoryPrivilegeUse] = &POLICY_AUDIT_EVENT_NONE;
 $options[AuditCategoryDetailedTracking] = &POLICY_AUDIT_EVENT_SUCCESS | &POLICY_AUDIT_EVENT_FAILURE;
 $options[AuditCategoryPolicyChange] = &POLICY_AUDIT_EVENT_NONE;
 $options[AuditCategoryAccountManagement] = &POLICY_AUDIT_EVENT_NONE;
  # only valid in nt 5
 $options[AuditCategoryDirectoryServiceAccess] = &POLICY_AUDIT_EVENT_NONE;
 $options[AuditCategoryAccountLogon] = &POLICY_AUDIT_EVENT_NONE;

 %info = ('auditingmode' => 1, 			# turn on auditing
	 'eventauditingoptions' => \@options	# events to audit
	);

 if(!Win32::Lanman::LsaSetInformationPolicy("\\\\testserver", PolicyAuditEventsInformation, \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item LsaQueryAuditLogPolicy($server, \%info)

Queries the audit log policies on server \\testserver.

 if(!Win32::Lanman::LsaQueryAuditLogPolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key(sort keys %info)
 {
	print "$key=$info{$key}\n";
 }

=item LsaQueryAuditEventsPolicy($server, \%info)

Queries the audit event policies on server \\testserver.

 if(!Win32::Lanman::LsaQueryAuditEventsPolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "auditingmode=$info{auditingmode}\n";
 print "maximumauditeventcount=$info{maximumauditeventcount}\n";
 print "eventauditingoptions:\n";

 if($info{maximumauditeventcount} > 0)
 {
	$options = $info{eventauditingoptions};

	foreach $option (@$options)
	{
		print "\t$option\n";
	}
 }

=item LsaSetAuditEventsPolicy($server, \%info)

Sets audit event policy information on server \\testserver.

 #events to audit
 $options[AuditCategorySystem] = &POLICY_AUDIT_EVENT_UNCHANGED;
 $options[AuditCategoryLogon] = &POLICY_AUDIT_EVENT_SUCCESS;
 $options[AuditCategoryObjectAccess] = &POLICY_AUDIT_EVENT_FAILURE;
 $options[AuditCategoryPrivilegeUse] = &POLICY_AUDIT_EVENT_NONE;
 $options[AuditCategoryDetailedTracking] = &POLICY_AUDIT_EVENT_SUCCESS | &POLICY_AUDIT_EVENT_FAILURE;
 $options[AuditCategoryPolicyChange] = &POLICY_AUDIT_EVENT_NONE;
 $options[AuditCategoryAccountManagement] = &POLICY_AUDIT_EVENT_NONE;
  # only valid in nt 5
 $options[AuditCategoryDirectoryServiceAccess] = &POLICY_AUDIT_EVENT_NONE;
 $options[AuditCategoryAccountLogon] = &POLICY_AUDIT_EVENT_NONE;

 %info = ('auditingmode' => 1, 			# turn on auditing
	 'eventauditingoptions' => \@options	# events to audit
	);

 if(!Win32::Lanman::LsaSetAuditEventsPolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item LsaQueryPrimaryDomainPolicy($server, \%info)

Queries primary domain policy information on server \\testserver.

 if(!Win32::Lanman::LsaQueryPrimaryDomainPolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "name=$info{name}\n";
 print "sid=", unpack("H" . 2 * length($info{sid}), $info{sid}), "\n";

=item LsaSetPrimaryDomainPolicy($server, \%info)

Sets the primary domain policy information for server \\testserver2 to the same like
server \\testserver1.

 if(!Win32::Lanman::LsaQueryPrimaryDomainPolicy("\\\\testserver1", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "name=$info{name}\n";
 print "sid=", unpack("H" . 2 * length($info{sid}), $info{sid}), "\n";

 if(!Win32::Lanman::LsaSetPrimaryDomainPolicy("\\\\testserver2", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item LsaQueryPdAccountPolicy($server, \%info)

Queries the primary domain account used for authentication and lookup requests on
server \\testserver. It returns always an empty string. This should be a bug in the call.

 if(!Win32::Lanman::LsaQueryPdAccountPolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key(sort keys %info)
 {
	print "$key=$info{$key}\n";
 }

=item LsaQueryAccountDomainPolicy($server, \%info)

Queries account domain policy information on server \\testserver.

 if(!Win32::Lanman::LsaQueryAccountDomainPolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "domainname=$info{domainname}\n";
 print "domainsid=", unpack("H" . 2 * length($info{domainsid}), $info{domainsid}), "\n";

=item LsaSetAccountDomainPolicy($server, \%info)

Sets account domain policy information on server \\testserver.

 if(!Win32::Lanman::LsaQueryAccountDomainPolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "domainname=$info{domainname}\n";
 print "domainsid=", unpack("H" . 2 * length($info{domainsid}), $info{domainsid}), "\n";

$info{domainname} = 'testserver2';

 if(!Win32::Lanman::LsaSetAccountDomainPolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item LsaQueryServerRolePolicy($server, \%info)

Queries server role policy information on server \\testserver.

 if(!Win32::Lanman::LsaQueryServerRolePolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key(sort keys %info)
 {
	print "$key=$info{$key}\n";
 }

=item LsaSetServerRolePolicy($server, \%info)

Sets server role policy information to PolicyServerRoleBackup on server \\testserver.

%info = (serverrole => &PolicyServerRoleBackup);
 if(!Win32::Lanman::LsaQueryServerRolePolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item LsaQueryReplicaSourcePolicy($server, \%info)

Queries replication source server on server \\testserver.

 if(!Win32::Lanman::LsaQueryReplicaSourcePolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key(sort keys %info)
 {
	print "$key=$info{$key}\n";
 }

=item LsaSetReplicaSourcePolicy($server, \%info)

Sets replication source server to \\testserver2 on server \\testserver.

 $info{replicasource} = "\\\\testserver2";
 if(!Win32::Lanman::LsaSetReplicaSourcePolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item LsaQueryDefaultQuotaPolicy($server, \%info)

Queries the default quota policy information on server \\testserver.

 if(!Win32::Lanman::LsaQueryDefaultQuotaPolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key(sort keys %info)
 {
	print "$key=$info{$key}\n";
 }

=item LsaQueryDefaultQuotaPolicy($server, \%info)

Sets the default quota policy information on server \\testserver (doubles the
minimum working set size).

 if(!Win32::Lanman::LsaQueryDefaultQuotaPolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 $info{minimumworkingsetsize} *= 2;

 if(!Win32::Lanman::LsaSetDefaultQuotaPolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item LsaQueryAuditFullPolicy($server, \%info)

Queries the audit full policy information on server \\testserver.

 if(!Win32::Lanman::LsaQueryAuditFullPolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key(sort keys %info)
 {
	print "$key=$info{$key}\n";
 }

=item LsaSetAuditFullPolicy($server, \%info)

Sets the audit full policy information on server \\testserver. The server
will shut down, if the audit log is full.

 if(!Win32::Lanman::LsaSetAuditFullPolicy("\\\\testserver", {shutdownonfull => 1}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item LsaQueryDnsDomainPolicy($server, \%info)

Queries the dns domain policy information on server \\testserver. This call is only
supported in nt 5 and is currently untested!

 if(!Win32::Lanman::LsaQueryDnsDomainPolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "name=$info{name}\n";
 print "dnsdomainname=$info{dnsdomainname}\n";
 print "dnsforestname=$info{dnsforestname}\n";
 print "guid=", unpack("H" . 2 * length($info{guid}), $info{guid}), "\n";
 print "sid=", unpack("H" . 2 * length($info{sid}), $info{sid}), "\n";

=item LsaQueryDnsDomainPolicy($server, \%info)

Sets the dns domain policy information on server \\testserver. This call is only
supported in nt 5 and is currently untested!

 if(!Win32::Lanman::LsaQueryDnsDomainPolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 #$info{dnsdomainname} = ...
 #$info{dnsforestname} = ...

 if(!Win32::Lanman::LsaSetDnsDomainPolicy("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item LsaEnumerateTrustedDomains($server, \@domains)

Shows the domain name and sid of your workstation. If you call this on any domain controller,
you'll get a list of trusted domains (see the example below).

 if(!Win32::Lanman::LsaEnumerateTrustedDomains("", \@domains))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $domain(@domains)
 {
	print "name=${$domain}{name}\t";
	print "sid=" . unpack("H" . 2 * length(${$domain}{sid}), ${$domain}{sid}) . "\n";
 }


Enumerates all trusted domains of the domain testdomain.

 if(!Win32::Lanman::NetGetDCName("", "testdomain", \$pdcname))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::LsaEnumerateTrustedDomains($pdcname, \@domains))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $domain(@domains)
 {
	print "name=${$domain}{name}\t";
	print "sid=" . Win32::Lanman::SidToString(${$domain}{sid}) . "\n";
 }

Enumerate all Trusted domains for your workstation

 if(!Win32::Lanman::LsaEnumerateTrustedDomains("", \@domains))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	#print 
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach my $domain (@domains)
 {
	next
		unless Win32::Lanman::NetGetAnyDCName("", ${$domain}{name},\$prim_dom_dcname);

	print "name=${$domain}{name}, anydc=$prim_dom_dcname\n";

	next
		unless Win32::Lanman::LsaEnumerateTrustedDomains($prim_dom_dcname, \@trusts);

	foreach $trust(@trusts)
	{
		next
			unless Win32::Lanman::NetGetAnyDCName($prim_dom_dcname, ${$trust}{name}, \$dcname);

		print "$prim_dom_dcname Trusts name=${$trust}{name}, anydc=$dcname\n";
	}
 }

=item LsaLookupNames($server, \@accounts, \@info)

Looks up for account names in @account on server \\testserver and returns the appropriate
rid, domains, sid's and domain sid's.

 @accounts = ('user1', 'user2', 'group1', 'testdomain\\group2');

 if(!Win32::Lanman::LsaLookupNames("\\\\testserver", @accounts, \@infos))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $info (@infos)
 {
	print "name=", $accounts[$count++], "\n";

	@keys = sort keys %$info;

	foreach $key(@keys)
	{
		if($key eq "domainsid" || $key eq "sid")
		{
			print "$key=" . unpack("H" . 2 * length(${$info}{$key}), ${$info}{$key}) . "\n";
		}
		else
		{
			print "$key=${$info}{$key}\n";
		}
	}
 }

=item LsaLookupSids($server, \@sids, \@info)

Looks up for sid's in @sids on server \\testserver and returns the appropriate
account names, domains, sid's and domain sid's.

 @sids = (
	pack("C12", 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0),		#everyone
	pack("C12", 1, 1, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0),		#local
	pack("C12", 1, 1, 0, 0, 0, 0, 0, 5, 2, 0, 0, 0),		#network
	pack("C12", 1, 1, 0, 0, 0, 0, 0, 5, 3, 0, 0, 0),		#batch
	pack("C12", 1, 1, 0, 0, 0, 0, 0, 5, 6, 0, 0, 0),		#service
	pack("C12", 1, 1, 0, 0, 0, 0, 0, 5, 3, 0, 0, 0),		#batch
	pack("C16", 1, 2, 0, 0, 0, 0, 0, 5, 32, 0, 0, 0, 32, 2, 0 ,0),	#administrators
	pack("C16", 1, 2, 0, 0, 0, 0, 0, 5, 32, 0, 0, 0, 33, 2, 0 ,0),	#users
	pack("C16", 1, 2, 0, 0, 0, 0, 0, 5, 32, 0, 0, 0, 34, 2, 0 ,0)	#guests
 );

 if(!Win32::Lanman::LsaLookupSids("\\\\testserver", \@sids, \@infos))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }


 foreach $info (@infos)
 {
	print "sid=" . unpack("H" . 2 * length($sids[$count]), $sids[$count++]) . "\n";

	@keys = sort keys %$info;

	foreach $key(@keys)
	{
		if($key eq "domainsid")
		{
			print "$key=" . unpack("H" . 2 * length(${$info}{$key}), ${$info}{$key}) . "\n";
		}
		else
		{
			print "$key=${$info}{$key}\n";
		}
	}

 }

=item LsaEnumerateAccountsWithUserRight($server, $privilege, \@sids)

Enums all accounts granted the SeNetworkLogonRight privilege on server \\testserver.

 if(!Win32::Lanman::LsaEnumerateAccountsWithUserRight("\\\\testserver", &SE_NETWORK_LOGON_NAME, \@sids))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::LsaLookupSids("\\\\testserver", \@sids, \@infos))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $info (@infos)
 {
	@keys = sort keys %$info;

	foreach $key(@keys)
	{
		if($key eq "domainsid" || $key eq "sid")
		{
			print "$key=" . unpack("H" . 2 * length(${$info}{$key}), ${$info}{$key}) . "\n";
		}
		else
		{
			print "$key=${$info}{$key}\n";
		}
	}
 }

=item LsaEnumerateAccountRights($server, $sid, \@privileges)

Enumerates all privileges granted to the account testuser on server \\testserver.

 if(!Win32::Lanman::LsaLookupNames("\\\\testserver", ['testuser'], \@infos))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	#print
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::LsaEnumerateAccountRights("\\\\testserver", ${$infos[0]}{sid}, \@privileges))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	#print
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $priv(@privileges)
 {
	print "$priv\n";
 }

=item LsaAddAccountRights($server, $sid, \@privileges)

Grants privileges SeBackupPrivilege, SeRestorePrivilege, SeShutdownPrivilege and
SeDebugPrivilege to user testuser on server \\testserver.

 if(!Win32::Lanman::LsaLookupNames("\\\\testserver", ['testuser'], \@infos))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	#print
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::LsaAddAccountRights("\\\\testserver", ${$infos[0]}{sid},
				[&SE_BACKUP_NAME, &SE_RESTORE_NAME, &SE_SHUTDOWN_NAME, &SE_DEBUG_NAME]))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	#print
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item LsaRemoveAccountRights($server, $sid, \@privileges, [$all])

Removes the privileges SeBackupPrivilege, SeRestorePrivilege, SeShutdownPrivilege
and SeDebugPrivilege from the user testuser on server \\testserver.

 if(!Win32::Lanman::LsaLookupNames("\\\\testserver", ['testuser'], \@infos))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	#print
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::LsaRemoveAccountRights("\\\\testserver", ${$infos[0]}{sid},
				[&SE_BACKUP_NAME, &SE_RESTORE_NAME, &SE_SHUTDOWN_NAME, &SE_DEBUG_NAME]))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	#print
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Removes all privileges from the user testuser on server \\testserver.

 if(!Win32::Lanman::LsaLookupNames("\\\\testserver", ['testuser'], \@infos))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	#print
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::LsaRemoveAccountRights("\\\\testserver", ${$infos[0]}{sid}, [], 1))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	#print
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item LsaQueryTrustedDomainInfo($server, $domainsid, $infotype, \%info)

Queries the trusted domain passwords for domain testdomain on server \\testserver. Don't call
LsaQueryTrustedDomainInfo directly. Use the wrappers LsaQueryTrustedXXXInfo instead (see
examples below).

 if(!Win32::Lanman::LsaLookupNames("\\\\testserver", ['testdomain'], \@domain))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::LsaQueryTrustedDomainInfo("\\\\testserver", ${$domain[0]}{domainsid}, &TrustedPasswordInformation, \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "password=" . unpack("H" . 2 * length($info{password}), $info{password}) . "\n";
 print "oldpassword=" . unpack("H" . 2 * length($info{oldpassword}), $info{oldpassword}) . "\n";

=item LsaSetTrustedDomainInformation($server, $domainsid, $infotype, \%info)

Sets the trusted domain passwords for domain testdomain on server \\testserver to newpassword.
Don't call LsaSetTrustedDomainInformation directly. Use the wrappers LsaQueryTrustedXXXInfo 
instead (see examples below).

 if(!Win32::Lanman::LsaLookupNames("\\\\testserver", ['testdomain'], \@domain))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::LsaSetTrustedDomainInformation("\\\\testserver", ${$domain[0]}{domainsid}, 
                                                   &TrustedPasswordInformation, 
                                                   { password => 'newpassword'}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item LsaSetTrustedDomainInfo($server, $domainsid, $infotype, \%info)

Sets the trusted domain passwords for domain testdomain on server \\testserver to newpassword.
Don't call LsaSetTrustedDomainInfo directly. Use the wrappers LsaQueryTrustedXXXInfo instead 
(see examples below).

 if(!Win32::Lanman::LsaLookupNames("\\\\testserver", ['testdomain'], \@domain))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::LsaSetTrustedDomainInfo("\\\\testserver", ${$domain[0]}{domainsid}, 
                                            &TrustedPasswordInformation, 
                                            { password => 'newpassword'}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item LsaQueryTrustedDomainNameInfo($server, $domainsid, \%info)

Queries the domain name info for domain testdomain on server \\testserver.

 if(!Win32::Lanman::LsaLookupNames("\\\\testserver", ['testdomain'], \@domain))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::LsaQueryTrustedDomainNameInfo("\\\\testserver", ${$domain[0]}{domainsid}, \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key(sort keys %info)
 {
	print "$key=$info{$key}\n";
 }

=item LsaSetTrustedDomainNameInfo($server, $domainsid, \%info)

Sets the trusted domain name for testdomain on the domain \\testserver belongs to. If testdomain isn't 
already a member of the trusted domain list, the function adds it. Keep in mind, this function is not
tested completely.

 if(!Win32::Lanman::LsaLookupNames("\\\\testserver", ['testdomain'], \@domain))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::LsaSetTrustedDomainNameInfo("\\\\testserver", ${$domain[0]}{domainsid}, {name => 'testdomain'}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item LsaQueryTrustedPosixOffsetInfo($server, $domainsid, \%info)

Queries the posix rid used to create posix users or groups for domain testdomain
on server \\testserver.

 if(!Win32::Lanman::LsaLookupNames("\\\\testserver", ['testdomain'], \@domain))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::LsaQueryTrustedPosixOffsetInfo("\\\\testserver", ${$domain[0]}{domainsid}, \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key(sort keys %info)
 {
	print "$key=$info{$key}\n";
 }

=item LsaSetTrustedPosixOffsetInfo($server, $domainsid, \%info)

Sets the posix rid used to create posix users or groups for domain testdomain
on server \\testserver to the value 123456. You should use this function only, 
if you really know what you're doing! Keep in mind, this function is not tested 
completely.

 if(!Win32::Lanman::LsaLookupNames("\\\\testserver", ['testdomain'], \@domain))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::LsaSetTrustedPosixOffsetInfo("\\\\testserver", ${$domain[0]}{domainsid}, 
                                                 {offset => 123456}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item LsaQueryTrustedPasswordInfo($server, $domainsid, \%info)

Queries the trusted domain passwords for domain testdomain on server \\testserver.

 if(!Win32::Lanman::LsaLookupNames("\\\\testserver", ['testdomain'], \@domain))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::LsaQueryTrustedPasswordInfo("\\\\testserver", ${$domain[0]}{domainsid}, \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "password=" . unpack("H" . 2 * length($info{password}), $info{password}) . "\n";
 print "oldpassword=" . unpack("H" . 2 * length($info{oldpassword}), $info{oldpassword}) . "\n";

=item LsaSetTrustedPasswordInfo($server, $domainsid, \%info)

Sets the trusted domain passwords for domain testdomain on server \\testserver to newpassword.
You should use this function only, if you really know what you're doing! Keep in mind, this 
function is not tested completely.

 if(!Win32::Lanman::LsaLookupNames("\\\\testserver", ['testdomain'], \@domain))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::LsaSetTrustedPasswordInfo("\\\\testserver", ${$domain[0]}{domainsid}, 
                                              { password => 'newpassword'}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item LsaRetrievePrivateData($server, $key, \$data)

Retrieves private data (here the encrypted machine password - $MACHINE.ACC) that was stored by the 
LsaStorePrivateData function on server \\testserver. For further information about global, local and
machine objects, see also the LsaRetrievePrivateData function in the MSDN (topic private data object).

 if(!Win32::Lanman::LsaRetrievePrivateData("\\\\testserver", "\$MACHINE.ACC", \$data))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print $data;

=item LsaStorePrivateData($server, $key, \$data)

Stores private data (here the encrypted machine password - $MACHINE.ACC) on server \\testserver.
For further information about global, local and machine objects, see also the LsaStorePrivateData
function in the MSDN (topic private data object). You should use this function only, if you really 
know what you're doing! Keep in mind, this function is not tested completely.

 if(!Win32::Lanman::LsaStorePrivateData("\\\\testserver", "\$MACHINE.ACC", 'new_machine_pwd'))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item GrantPrivilegeToAccount($server, $privilege, \@accounts)

Grants the SeShutdownPrivilege to users testuser1, testuser1 and group testgroup on
server \\testserver.

 if(!Win32::Lanman::GrantPrivilegeToAccount("\\\\testserver", &SE_SHUTDOWN_NAME,
					   ["testuser1", "testuser2", "testgroup"]))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item RevokePrivilegeFromAccount($server, $privilege, \@accounts)

Revokes the SeServiceLogonRight from users testuser1, testuser1 and group testgroup on
server \\testserver.

 if(!Win32::Lanman::RevokePrivilegeToAccount("\\\\testserver", &SE_SERVICE_LOGON_NAME,
					    ["testuser1", "testuser2", "testgroup"]))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item EnumAccountPrivileges($server, $account, \@privileges)

Enums all privileges held by an user testuser on server \\testserver.

 if(!Win32::Lanman::EnumAccountPrivileges("\\\\testserver", "testuser", \@privileges))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach (@privileges)
 {
	print "$_\n";
 }

=item EnumPrivilegeAccounts($server, $privilege, \@accounts)

Enums all accounts granted the privilege SE_INTERACTIVE_LOGON_NAME on server \\testserver.

 if(!Win32::Lanman::EnumAccountPrivileges("\\\\testserver", &SE_INTERACTIVE_LOGON_NAME, \@accounts))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach (@accounts)
 {
	print "$_\n";
 }

=back

=head2 File System Replicator

=over 4

=item NetReplExportDirAdd($server, \%info)

Registers an existing directory in the export path to be replicated.

=item NetReplExportDirDel($server, $directory)

Removes registration of a replicated directory.

=item NetReplExportDirEnum($server, \@directories)

Lists the replicated directories in the export path.

=item NetReplExportDirGetInfo($server, $directory, \%info)

Retrieves the control information of a replicated directory.

=item NetReplExportDirLock($server, $directory)

Locks a replicated directory.

=item NetReplExportDirSetInfo($server, $directory, \%info)

Modifies the control information of a replicated directory.

=item NetReplExportDirUnlock($server, $directory, [$forceUnlock])

Unlocks a replicated directory.

=item NetReplGetInfo($server, \%info)

Retrieves configuration information for the Replicator service.

=item NetReplImportDirAdd($server, $directory)

Registers an existing directory in the import path to be replicated.

=item NetReplImportDirDel($server, $directory)

Removes registration of a replicated directory.

=item NetReplImportDirEnum($server, \@directories)

Lists the replicated directories in the import path.

=item NetReplImportDirGetInfo($server, $directory, \%info)

Retrieves the control information of a replicated directory.

=item NetReplImportDirLock($server, $directory)

Locks a replicated directory.

=item NetReplImportDirUnlock($server, $directory, [$forceUnlock])

Unlocks a replicated directory.

=item NetReplSetInfo($server, \%info)

Modifies the Replicator service configuration information.

=back

=head2 File System Replicator EXAMPLES:

=over 4

=item NetReplExportDirAdd($server, \%info)

Registers an existing directory testexportdir in the export path of server \\testserver to be replicated.

 if(!Win32::Lanman::NetReplExportDirAdd("\\\\testserver",
				       {'dirname' => "testexportdir",
					'integrity' => &REPL_INTEGRITY_FILE,
					'extent' => &REPL_EXTENT_TREE}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetReplExportDirDel($server, $directory)

Removes registration of replicated directory testexportdir on server \\testserver.

 if(!Win32::Lanman::NetReplExportDirDel("\\\\testserver", "testexportdir"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetReplExportDirEnum($server, \@directories)

Lists the replicated directories in the export path on server \\testserver.

 if(!Win32::Lanman::NetReplExportDirEnum("\\\\testserver", \@directories))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $directory (@directories)
 {
	@keys = sort keys %$directory;

	foreach $key (@keys)
	{
		print "$key=${$directory}{$key}\n";
	}
 }

=item NetReplExportDirGetInfo($server, $directory, \%info)

Retrieves the control information of the replicated directory testexportdir on server \\testserver.

 if(!Win32::Lanman::NetReplExportDirGetInfo("\\\\testserver", "testexportdir", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key (@keys)
 {
	print "$key=$info{$key}\n";
 }

=item NetReplExportDirLock($server, $directory)

Adds a lock to the replicated directory testexportdir on server \\testserver.

 if(!Win32::Lanman::NetReplExportDirLock("\\\\testserver", "testexportdir"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetReplExportDirSetInfo($server, $directory, \%info)

Modifies the control information of the replicated directory testexportdir on server \\testserver.

 if(!Win32::Lanman::NetReplExportDirSetInfo("\\\\testserver", "testexportdir",
					   {'dirname' => "testexportdir",
					    'integrity' => &REPL_INTEGRITY_FILE,
					    'extent' => &REPL_EXTENT_FILE}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetReplExportDirUnlock($server, $directory, [$forceUnlock])

Decrements the lock counter by one for the replicated directory testexportdir on server \\testserver.

 if(!Win32::Lanman::NetReplExportDirUnlock("\\\\testserver", "testexportdir"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Sets the lock counter to zero for the replicated directory testexportdir on server \\testserver.

 if(!Win32::Lanman::NetReplExportDirUnlock("\\\\testserver", "testexportdir", REPL_UNLOCK_FORCE))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetReplGetInfo($server, \%info)

Retrieves configuration information for the Replicator service on server \\testserver.

 if(!Win32::Lanman::NetReplGetInfo("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key (@keys)
 {
	print "$key=$info{$key}\n";
 }

=item NetReplImportDirAdd($server, $directory)

Registers an existing directory testimportdir in the import path of server \\testserver to be replicated.

 if(!Win32::Lanman::NetReplImportDirAdd("\\\\terstserver", "testimportdir"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetReplImportDirDel($server, $directory)

Removes registration of replicated directory testimportdir on server \\testserver.

 if(!Win32::Lanman::NetReplImportDirDel("\\\\testserver", "testimportdir"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetReplImportDirEnum($server, \@directories)

Lists the replicated directories in the import path on server \\testserver.

 if(!Win32::Lanman::NetReplImportDirEnum("\\\\testserver", \@directories))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $directory (@directories)
 {
	@keys = keys %$directory;

	foreach $key (@keys)
	{
		print "$key=${$directory}{$key}\n";
	}
 }

=item NetReplImportDirGetInfo($server, $directory, \%info)

Retrieves the control information of the replicated directory testimportdir on server \\testserver.

 if(!Win32::Lanman::NetReplImportDirGetInfo("\\\\testserver", "testimportdir", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key (@keys)
 {
	print "$key=$info{$key}\n";
 }

=item NetReplImportDirLock($server, $directory)

Adds a lock to the replicated directory testimportdir on server \\testserver.

 if(!Win32::Lanman::NetReplImportDirLock("\\\\testserver", "testimportdir"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetReplImportDirUnlock($server, $directory, [$forceUnlock])

Decrements the lock counter by one for the replicated directory testimportdir on server \\testserver.

 if(!Win32::Lanman::NetReplImportDirUnlock("\\\\testserver", "testimportdir"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Sets the lock counter to zero for the replicated directory testimportdir on server \\testserver.

 if(!Win32::Lanman::NetReplImportDirUnlock("\\\\testserver", "testimportdir", REPL_UNLOCK_FORCE))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetReplSetInfo($server, \%info)

Modifies the Replicator service configuration information on server \\testserver.

 if(!Win32::Lanman::NetReplSetInfo("\\\\testserver",
				  {role => REPL_ROLE_BOTH,
				   exportpath => "c:\\winnt\\system32\\repl\\export",
				   exportlist => 'testexpdomain',
				   importpath => "c:\\winnt\\system32\\repl\\import",
				   importlist => 'testimpdomain',
				   logonusername => '',
				   interval => 10,
				   pulse => 2,
				   guardtime => 5,
				   random => 120}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=back

=head2 Schedule

=over 4

=item NetScheduleJobAdd($server, \%info)

Submits a job to run at a specified future time and date.

=item NetScheduleJobDel($server, $minjobid, $maxjobid)

Deletes a range of jobs queued to run at a computer.

=item NetScheduleJobEnum($server, \@info)

Lists the jobs queued on a specified computer.

=item NetScheduleJobGetInfo($server, \@info)

Retrieves information about a particular job queued on a specified computer.

=back

=head2 Schedule EXAMPLES:

=over 4

=item NetScheduleJobAdd($server, \%info)

Submits a job to run at at 12 o'clock noon on server \\testserver.

 if(!Win32::Lanman::NetScheduleJobAdd("\\\\testserver",
				     {jobtime => 12 * 3600 * 1000,
				      daysofmonth => 0, daysofmonth => 0,
				      daysofweek => 0,
				      flags => 0,
				      command => "winfile.exe"}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print $info{jobid};

=item NetScheduleJobDel($server, $minjobid, $maxjobid)

Deletes all jobs between job id's 5 to 10 on server \\testserver.

 if(!Win32::Lanman::NetScheduleJobDel("\\\\testserver", 5, 10))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetScheduleJobEnum($server, \@info)

Lists the job properties of all jobs queued on server \\testserver.

 if(!Win32::Lanman::NetScheduleJobEnum("\\\\testserver", \@jobs))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $job (@jobs)
 {
	@keys = keys %$job;

	foreach $key (@keys)
	{
		print "$key=${$job}{$key}\n";
	}
 }

=item NetScheduleJobGetInfo($server, \@info)

Retrieves information about job 5 queued on server \\testserver.

 if(!Win32::Lanman::NetScheduleJobGetInfo("\\\\testserver", 5, \%job))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %job;

 foreach $key (@keys)
 {
	print "$key=$job{$key}\n";
 }

=back

=head2 Server

=over 4

=item NetServerDiskEnum($server, \@info)

Retrieves a list of disk drives on a server.

=item NetServerEnum($server, $domain, $type, \@info)

Lists all servers of the specified type that are visible in the specified domain. 

$type can be any of the constants SV_TYPE_*. e.g. SV_TYPE_SQLSERVER , SV_TYPE_TERMINALSERVER , SV_TYPE_NT . 

These can also be combined using |. To get all SQL servers or terminal servers user $type = SV_TYPE_SQLSERVER | SV_TYPE_TERMINALSERVER

=item NetServerGetInfo($server, \%info, [$fullinfo])

Retrieves information about the specified server.

=item NetServerSetInfo($server, \%info, [$fullinfo])

Sets a server’s operating parameters.

=item NetServerTransportAdd($server, \%info)

Binds the server to the transport.

=item NetServerTransportDel($server, \%info)

Unbinds (or disconnects) the transport protocol from the server.

=item NetServerTransportEnum($server, \@info)

Supplies information about transports that are managed by the server.

=back

=head2 Server EXAMPLES:

=over 4

=item NetServerDiskEnum($server, \@info)

Retrieves a list of disk drives on server \\testserver.

 if(!Win32::Lanman::NetServerDiskEnum("\\\\testserver", \@disks))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $disk (@disks)
 {
	print "$disk\n";
 }

=item NetServerEnum($server, $domain, $type, \@info)

Lists all servers of the type SV_TYPE_NT that are visible in the domain testdomain. The command will
be executed on \\\\testserver.

 if(!Win32::Lanman::NetServerEnum("\\\\testserver", "testdomain", SV_TYPE_NT, \@info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $server (@info)
 {
	@keys = keys %$server;

	foreach $key(@keys)
	{
		print "$key=${$server}{$key}\n";
	}
 }

=item NetServerGetInfo($server, \%info, [$fullinfo])

Retrieves basic and extended information about the server \\testserver.

 if(!Win32::Lanman::NetServerGetInfo("\\\\testserver", \%info, 1))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

Retrieves only basic information about the server \\testserver.

 if(!Win32::Lanman::NetServerGetInfo("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

=item NetServerSetInfo($server, \%info, [$fullinfo])

Changes the server’s operating parameters userpath to c:\users and hidden to true
on server \\testserver.

 if(!Win32::Lanman::NetServerGetInfo("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

$info{'hidden'} = 1;
$info{'userpath'} = "c:\\users";

 if(!Win32::Lanman::NetServerSetInfo("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetServerTransportAdd($server, \%info)

Binds the server to the transport on server \\testserver.

 if(!Win32::Lanman::NetServerTransportAdd("\\\\testserver",
					 {'domain' => 'testdomain',
					  'networkaddress' => '000000000000',
					  'numberofvcs' => 0,
					  'transportaddress' => 'TESTSERVER',
					  'transportaddresslength' => length('TESTSERVER'),
					  'transportname' => "\\Device\\NetBT_NdisWan7"
					 }))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetServerTransportDel($server, \%info)

Unbinds (or disconnects) the transport protocol on server \\testserver.

 if(!Win32::Lanman::NetServerTransportDel("\\\\testserver",
					 {'domain' => 'testdomain',
					  'networkaddress' => '000000000000',
					  'numberofvcs' => 0,
					  'transportaddress' => 'TESTSERVER',
					  'transportaddresslength' => length('TESTSERVER'),
					  'transportname' => "\\Device\\NetBT_NdisWan7"
					 }))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetServerTransportEnum($server, \@info)

Supplies information about transports that are managed by the server \\testserver.

 if(!Win32::Lanman::NetServerTransportEnum("\\\\testserver", \@info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $server (@info)
 {
	@keys = keys %$server;

	foreach $key(@keys)
	{
		print "$key=#${$server}{$key}#\n";
	}
 }

=back

=head2 Session

=over 4

=item NetSessionDel($server, $client, $user)

Ends a session between a server and a workstation.

=item NetSessionEnum($server, $client, $user, \@info)

Provides information about all current sessions.

=item NetSessionGetInfo($server, $client, $user, \%info)

Retrieves information about a session established .

=back

=head2 Session EXAMPLES:

=over 4

=item NetSessionDel($server, $client, $user)

Ends all session on server \\testserver.

 if(!Win32::Lanman::NetSessionDel("\\\\testserver", '', ''))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Ends the session on server \\testserver to client \\testclient for user testuser.

 if(!Win32::Lanman::NetSessionDel("\\\\testserver", "\\\\testclient", "testuser"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetSessionEnum($server, $client, $user, \@info)

Provides information about all current sessions on server \\testserver.

 if(!Win32::Lanman::NetSessionEnum("\\\\testserver", "", "", \@sessions))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $session (@sessions)
 {
	@keys = keys %$session;

	foreach $key(@keys)
	{
		print "$key=#${$session}{$key}#\n";
	}
 }

Provides information about the current sessions for client \\testclient and user testuser
on server \\testserver.

 if(!Win32::Lanman::NetSessionEnum("\\\\testserver", "\\\\testclient", "testuser", \@sessions))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $session (@sessions)
 {
	@keys = keys %$session;

	foreach $key (@keys)
	{
		print "$key=#${$session}{$key}#\n";
	}
 }

=item NetSessionGetInfo($server, $client, $user, \%info)

Retrieves information about a session on server \\\\testserver for client \\testclient.

 if(!Win32::Lanman::NetSessionGetInfo("\\\\testserver", "\\\\testclient", "", \%session))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %session;

 foreach $key (@keys)
 {
	print "$key=$session{$key}\n";
 }

=back

=head2 Share

In the following section on shares. Information about a share is stored in a hash (%shareinfo).
The following are valid keys: netname, type, remark, permissions, max_uses, current_uses, path,
passwd and security_descriptor (which is has a binary value)

=over 4

=item NetShareAdd($server, \%shareinfo)

Adds a new share on $server.

=item NetShareCheck($server, $path, \$type)

Checks whether or not a $server is sharing a device.

=item NetShareDel($server, $share)

Deletes a share from $server.

=item NetShareEnum($server, \@shares)

Enumerates all shares on $server.

=item NetShareGetInfo($server, $share, \%info)

Gets information about $share on $server, the results are stored in %info

=item NetShareSetInfo($server, $share, \%info)

Sets information about $share on $server as specified in %info.

=item NetConnectionEnum($server, $share_or_computer, \%connections)

Gets all connections made to a shared resource on the server $server or all 
connections established from a particular computer. If $share_or_computer
has two backslashes befor the name it is interpreted as a computer name,
otherwise as a share name.

=back

=head2 Share EXAMPLES:

=over 4

=item NetShareAdd($server, \%shareinfo)

Adds a new share on server \\testdfsserver. If you want to set security, you have to build a
security descriptor.

 $secdesc = ...
 if(!Win32::Lanman::NetShareAdd("\\\\testdfsserver",
			       {'netname' => 'testshare', 			# share name
				type => Win32::Lanman::STYPE_DISKTREE,		# share type
				remark => 'remark for testshare',		# remark
				permissions => 0,				# only used for share level security
				max_uses => 5,					# number of users can connect
				current_uses => 0,				# unused
				path => 'c:\test',				# physical share path
				passwd => 'password',				# password
				security_descriptor => $secdesc}))		# sec. descriptor if you need security
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetShareCheck($server, $path, \$type)

Checks if c:\test on server \\testserver is sharing a device.

 if(!Win32::Lanman::NetShareCheck("\\\\testserver", "c:\\test", \$type))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print $type;

=item NetShareDel($server, $path)

Deletes share testshare on server \\testserver

 if(!Win32::Lanman::NetShareDel("\\\\testserver", "testshare"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetShareEnum($server, \@shares)

Enums all shares on server \\testserver

 if(!Win32::Lanman::NetShareEnum("\\\\testserver", \@shares))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $share (@shares)
 {
	print "${$share}{'netname'}\n";
	print "${$share}{'type'}\n";
	print "${$share}{'remark'}\n";
	print "${$share}{'permissions'}\n";
	print "${$share}{'max_uses'}\n";
	print "${$share}{'current_uses'}\n";
	print "${$share}{'path'}\n";
	print "${$share}{'passwd'}\n";
	#don't print these binary data
	#print "${$share}{'security_descriptor'}\n";
 }

=item NetShareGetInfo($server, $share, \%info)

Gets information on share testshare on server \\testserver

 if(!Win32::Lanman::NetShareGetInfo("\\\\testserver", "testshare", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "$info{'netname'}\n";
 print "$info{'type'}\n";
 print "$info{'remark'}\n";
 print "$info{'permissions'}\n";
 print "$info{'max_uses'}\n";
 print "$info{'current_uses'}\n";
 print "$info{'path'}\n";
 print "$info{'passwd'}\n";
 #don't print these binary data
 #print "$info{'security_descriptor'}\n";

=item NetShareSetInfo($server, $share, \%info)

Sets information on share testshare on server \\testserver

 unless(Win32::Lanman::NetShareSetInfo("\\\\testserver", "testshare", 
				    {'remark' => 'new remark', 'max_uses' => 5}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetConnectionEnum($server, $share_or_computer, \%connections)

Gets all connections made to the share testshare on server \\testserver.

 if(!Win32::Lanman::NetConnectionEnum("\\\\testserver", "testshare", \%conns))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $conn(@conns)
 {
	foreach $key(sort keys %$conn)
	{
		print "$key=${$conn}{$key}\n";
	}
 }

Gets all connections made from computer testcomputer to the server testserver.

 if(!Win32::Lanman::NetConnectionEnum("\\\\testserver", "\\\\testcomputer", \%conns))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $conn(@conns)
 {
	foreach $key(sort keys %$conn)
	{
		print "$key=${$conn}{$key}\n";
	}
 }

=back

=head2 Statistics

=over 4

=item NetStatisticsGet($server, $service, \%info)

Retrieves operating statistics for a service.

=back

=head2 Statistics EXAMPLES:

=over 4

Retrieves operating statistics for the service server on server \\testserver.

 if(!Win32::Lanman::NetStatisticsGet("\\\\testserver", "SERVER", \%statistics))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %statistics;

 foreach $key (@keys)
 {
	print "$key=$statistics{$key}\n";
 }


Retrieves operating statistics for the service workstation on server \\testserver.

 if(!Win32::Lanman::NetStatisticsGet("\\\\testserver", "WORKSTATION", \%statistics))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %statistics;

 foreach $key (@keys)
 {
	print "$key=$statistics{$key}\n";
 }

=back

=head2 Workstation

=over 4

=item NetWkstaGetInfo($server, \@info, $fullinfo)

Returns information about the configuration elements for a workstation.

=item NetWkstaSetInfo($server, \%info)

Configures a workstation.

=item NetWkstaTransportAdd($server, \%info)

Binds (or connects) the redirector to the transport.

=item NetWkstaTransportDel($server, $transport, $force)

Unbinds the transport protocol from the redirector.

=item NetWkstaTransportEnum($server, \@info)

Supplies information about transport protocols that are managed by the redirector.

=item NetWkstaUserGetInfo(\@info)

Returns information about the currently logged-on user. This function must be called
in the context of the logged-on user.

=item NetWkstaUserSetInfo(\@info)

Returns information about the currently logged-on user. This function must be called
in the context of the logged-on user.

=item NetWkstaUserEnum($server, \@info)

Lists information about all users currently logged on to the workstation.

=back

=head2 Workstation EXAMPLES:

=over 4

=item NetWkstaGetInfo($server, \@info, $fullinfo)

Returns information about the configuration elements for \\testserver.

 if(!Win32::Lanman::NetWkstaGetInfo("\\\\testserver", \%info, 1))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key (@keys)
 {
	print "$key=$info{$key}\n";
 }

=item NetWkstaSetInfo("\\\\testserver", \%info)

Configures \\testserver.

 if(!Win32::Lanman::NetWkstaSetInfo($server, {'char_wait' => 3600,
				 'collection_time' => 250,
				 'maximum_collection_count' => 16,
				 'keep_conn' => 600,
				 'sess_timeout' => 45,
				 'siz_char_buf' => 512}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetWkstaTransportAdd($server, \%info)

Binds (or connects) the redirector to the transport on server \\testserver.

 if(!Win32::Lanman::NetWkstaTransportAdd("\\testserver"
					{'number_of_vcs' => 0,
					 'transport_address' => '000000000000',
					 'transport_name' => "\\Device\\NetBT_NdisWan7",
					 'quality_of_service' => 0xffff}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetWkstaTransportDel($server, $transport, $force)

Unbinds the transport protocol from the redirector on server \\testserver.

 if(!Win32::Lanman::NetWkstaTransportDel("\\\\testserver", "\\Device\\NetBT_NdisWan7", USE_FORCE))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetWkstaTransportEnum($server, \@info)

Supplies information about transport protocols that are managed by the redirector on server \\testserver.

 if(!Win32::Lanman::NetWkstaTransportEnum("\\\\testserver", \@info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $transport (@info)
 {
	@keys = keys %$transport;

	foreach $key (@keys)
	{
		print "$key=#${$transport}{$key}#\n";
	}
 }

=item NetWkstaUserGetInfo(\@info)

Returns information about the currently logged-on user. This function must be called
in the context of the logged-on user.

 if(!Win32::Lanman::NetWkstaUserGetInfo(\%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key (@keys)
 {
	print "$key=$info{$key}\n";
 }

=item NetWkstaUserSetInfo(\@info)

Returns information about the currently logged-on user. This function must be called
in the context of the logged-on user.

 if(!Win32::Lanman::NetWkstaUserSetInfo({'username' => 'testuser',
					'logon_domain' => 'testdomain',
					'oth_domains' => 'test_oth_domain',
					'logon_server' => 'logonserver'}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetWkstaUserEnum($server, \@info)

Lists information about all users currently logged on \\testserver.

 if(!Win32::Lanman::NetWkstaUserEnum("\\\\testserver", \@info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $user (@info)
 {
	@keys = keys %$user;

	foreach $key (@keys)
	{
		print "$key=#${$user}{$key}#\n";
	}
 }

=back

=head2 Time and Misc

=over 4

=item NetRemoteTOD($server, \%info)

Returns the time of day information from a specified server.

=item NetRemoteComputerSupports($server, $options, \$supported)

Retrieves the optional features the remote server supports.

=back

=head2 Time and Misc EXAMPLES:

=over 4

=item NetRemoteTOD($server, \%info)

Returns the time of day information from server \\testserver.

 if(!Win32::Lanman::NetRemoteTOD("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys %info;

 foreach $key(@keys)
 {
	print "$key=$info{$key}\n";
 }

=item NetRemoteComputerSupports($server, $options, \$supported)

Retrieves which of the options in $options are supported on server \\testserver.

 if(!Win32::Lanman::NetRemoteComputerSupports("\\\\testserver", 
					      &SUPPORTS_REMOTE_ADMIN_PROTOCOL | 
					      &SUPPORTS_RPC | &SUPPORTS_SAM_PROTOCOL | 
					      &SUPPORTS_UNICODE, \$supported))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "RAP is", ($supported & &SUPPORTS_REMOTE_ADMIN_PROTOCOL) ? "" : " not", " supported\n";
 print "RPC is", ($supported & &SUPPORTS_RPC) ? "" : " not", " supported\n";
 print "SAM is", ($supported & &SUPPORTS_SAM_PROTOCOL) ? "" : " not", " supported\n";
 print "UNICODE is", ($supported & &SUPPORTS_UNICODE) ? "" : " not", " supported\n";

=back

=head2 Use

=over 4

=item NetUseAdd(\%info)

Establishes a connection to a shared resource.

=item NetUseDel($usename, [$forcedel])

Deletes a connection to a shared resource.

=item NetUseEnum(\@info)

Enumerates all connections to shared resources.

=item NetUseGetInfo($usename, \%info)

Gets information about a connection to a shared resource.

=back

=head2 Use EXAMPLES:

=over 4

=item NetUseAdd(\%info)

Establishes a connection to a ipc$ on server \\testserver. The connection will be established
in context of user testdomain\testuser.

 if(!Win32::Lanman::NetUseAdd({remote => "\\\\testserver\\ipc\$",
			      password => "testpass",
			      username => "testuser",
			      domain => "testdomain",
			      asg_type => &USE_IPC}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

connects drive h: to \\testserver\testshare.

 if(!Win32::Lanman::NetUseAdd({remote => "\\\\testserver\\testshare",
			      local => "h:",
			      asg_type => &USE_DISKDEV}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

connects port lpt3: to \\testserver\testprint.

 if(!Win32::Lanman::NetUseAdd({remote => "\\\\testserver\\testprint",
			      local => "lpt3:",
			      asg_type => &USE_SPOOLDEV}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetUseDel($usename, [$forcedel])

Deletes a connection to \\testserver\testshare. If there are open files, the connection won't
be closed.

 if(!Win32::Lanman::NetUseDel("\\\\testserver\\testshare"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Deletes the connection to drive h:. If there are open files, the connection will be closed.

 if(!Win32::Lanman::NetUseDel("h:", &USE_FORCE))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetUseEnum(\@info)

Enumerates all connections to shared resources.

 if(!Win32::Lanman::NetUseEnum(\@uses))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $use (@uses)
 {
	foreach (sort keys %$use)
	{
		print "$_=${$use}{$_}\n";
	}
 }

=item NetUseGetInfo($usename, \%info)

Gets information about the to \\testserver\testshare.

 if(!Win32::Lanman::NetUseGetInfo('\\\\testserver\\testshare', \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach (sort keys %info)
 {
	print "$_=$info{$_}\n";
 }

=back

=head2 User

In this section, you cannot specify a domain name for the server parameter. 
Instead to affect domain accounts, obtain the PDC, using NetGetDCName, and 
then make the calls against this server.

=over 4

=item NetUserAdd($server, \%user)

Creates a new user $user on server $server.

=item NetUserChangePassword($location, $user, $oldpassword, $newpassword)

Changes the password for user $location\$user from $oldpassword to $newpassword. 
$oldpassword must be supplied, otherwise you will get error 86 (wrong password).

To Change the password for a domain account run the command on the PDC (not a BDC!).
 
To change a user's password without knowing the old password use NetUserSetInfo or NetUserSetProp.
To do this you need to have admin rights to perform the task.
$location should be either a domainname (clear text) or a servername ('\\server') 
for local machine accounts. 

Note in this function should you desire to create a local machine account you B<must>
use the "\\\\my_machine" format for $location; the module does B<not> insert the '\\' 
for you for this function!

=item NetUserCheckPassword($domain, $user, $password)

Checks if a user password is valid or not. This function is implemented by the Win32
LogonUser function and tries to log on the user over the network. If the user account 
has been disabled, locked out or expired or the user has not been granted the 
SeNetworkLogonRight (access this computer from the network) privilege, the function 
fails even you have specified the correct password. With Windows 2000 your script needs 
the SeTcbPrivilege (act as part of the operating system) privilege.

=item NetUserDel($server, $user)

Deletes user $user on server $server.

=item NetUserEnum($domain, $filter, \@user)

Enumerates all user in a domain or on a server.

=item NetUserGetGroups($server, $user, \@groups)

Enumerates all global groups on server $server to which user $user belongs.

=item NetUserGetInfo($server, $user, \%info)

Retrieves information about user $user on server $server.

=item NetUserGetLocalGroups($server, $user, $flags, \@groups)

Enumerates all local (and global if you specify LG_INCLUDE_INDIRECT in $flags) groups
on server $server to which user $user belongs.

=item NetUserSetGroups($server, $user, \@groups)

Sets global group memberships for user $user on server $server.

=item NetUserSetInfo($server, $user, \%info)

Sets the parameters of user $user on server $server. You cannot specify a domain name, it must be a server.

=item NetUserSetProp($server, $user, \%info)

Sets on or more parameters of user $user on server $server. You cannot specify a domain name, it must be a server.

=item NetUserModalsGet($server, \%info)

Retrieves global information for all users and global groups in the security
database on server $server.

=item NetUserModalsSet($server, \%info)

Sets global information for all users and global groups in the security
database on server $server. This call is not tested!!!

=item StringToSid

Converts a standard text format for a sid into the binary packed format used by NT internally

=item SidToString

Converts a sid in binary format to the standard text format ( e.g. S-1-3-3479834-3464-7664)

=back

=head2 User EXAMPLES:

=over 4

=item NetUserAdd($server, \@shares)

Creates a new user testuser on server \\testserver.

 if(!Win32::Lanman::NetUserAdd("\\\\testserver", {'name' => 'testuser',
						 'password' => 'testpassword',
						 'home_dir' => '\\\\testserver\\testshare',
						 'comment' => 'test users comment',
						 'flags' => UF_ACCOUNTDISABLE | UF_PASSWD_CANT_CHANGE | UF_TEMP_DUPLICATE_ACCOUNT,
						 'script_path' => '\\\\testserver\\testshare\\logon_script.bat',
						 'full_name' => 'test users full name',
						 'usr_comment' => 'test users usr comment',
						 'parms' => 'test users parameters',
						 'workstations' => 'comp0001,comp0002,comp0003,comp0004,comp0005,comp0006,comp0007,comp0008',
						 'profile' => '\\\\testserver\\testshare\\profile_dir',
						 'home_dir_drive' => 'Y:',
						 'acct_expires' => time() + 3600 * 24,
						 'country_code' => 49,
						 'code_page' => 850,
						 'logon_hours' => pack("b168", "000000001111111100000000" x 7),
						 'password_expired' => 1}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetUserChangePassword($domain, $user, $oldpassword, $newpassword)

Changes user testuser's password in the domain testdomain.

 if(!Win32::Lanman::NetUserChangePassword("testdomain", 'testuser', 'old_password', 'new_password'))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Changes user testuser's password on the server \\testserver.

 if(!Win32::Lanman::NetUserChangePassword("\\\\testserver", 'testuser', 'old_password', 'new_password'))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetUserCheckPassword($domain, $user, $password)

Checks if user testuser's password testpass in the domain testdomain is valid or not.

 if(!Win32::Lanman::NetUserCheckPassword("testdomain", 'testuser', 'testpass'))
 {
	print "Password testpass for user testuser in domain testdomain isn't valid; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }
 
 print "Password testpass for user testuser in domain testdomain is valid.";

Checks if user testuser's password testpass on the server \\testserver is valid or not.

 if(!Win32::Lanman::NetUserCheckPassword("\\\\testserver", 'testuser', 'testpass'))
 {
	print "Password testpass for user testuser on server \\\\testserver isn't valid; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }
 
 print "Password testpass for user testuser on server \\\\testserver is valid.";

=item NetUserDel($server, $user)

Deletes user testuser on server \\testserver.

 if(!Win32::Lanman::NetUserDel("\\\\testserver", 'testuser'))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetUserEnum($domain, $filter, \@user)

Enums all user in domain testdomain. All account types will be enumerated.

 if(!Win32::Lanman::NetUserEnum("testdomain", 0, \@users))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $user (@users)
 {
	$hours = unpack("b168", ${$user}{'logon_hours'});

	print "${$user}{'name'}\n";
	print "${$user}{'comment'}\n";
	print "${$user}{'usr_comment'}\n";
	print "${$user}{'full_name'}\n";
	print "${$user}{'password_age'}\n";
	print "${$user}{'priv'}\n";
	print "${$user}{'home_dir'}\n";
	print "${$user}{'flags'}\n";
	print "${$user}{'script_path'}\n";
	print "${$user}{'auth_flags'}\n";
	print "${$user}{'parms'}\n";
	print "${$user}{'workstations'}\n";
	print "${$user}{'last_logon'}\n";
	print "${$user}{'last_logoff'}\n";
	print "${$user}{'acct_expires'}\n";
	print "${$user}{'max_storage'}\n";
	print "${$user}{'units_per_week'}\n";
	print "$hours\n";
	print "${$user}{'bad_pw_count'}\n";
	print "${$user}{'num_logons'}\n";
	print "${$user}{'logon_server'}\n";
	print "${$user}{'country_code'}\n";
	print "${$user}{'code_page'}\n";
	print "${$user}{'user_id'}\n";
	print "${$user}{'primary_group_id'}\n";
	print "${$user}{'profile'}\n";
	print "${$user}{'home_dir_drive'}\n";
	print "${$user}{'password_expired'}\n";
 }

Enums all user on server \\testserver. Only normal accounts will be enumerated.

 if(!Win32::Lanman::NetUserEnum("\\\\testserver", &FILTER_NORMAL_ACCOUNT, \@users))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $user (@users)
 {
	$hours = unpack("b168", ${$user}{'logon_hours'});

	print "${$user}{'name'}\n";
	print "${$user}{'comment'}\n";
	print "${$user}{'usr_comment'}\n";
	print "${$user}{'full_name'}\n";
	print "${$user}{'password_age'}\n";
	print "${$user}{'priv'}\n";
	print "${$user}{'home_dir'}\n";
	print "${$user}{'flags'}\n";
	print "${$user}{'script_path'}\n";
	print "${$user}{'auth_flags'}\n";
	print "${$user}{'parms'}\n";
	print "${$user}{'workstations'}\n";
	print "${$user}{'last_logon'}\n";
	print "${$user}{'last_logoff'}\n";
	print "${$user}{'acct_expires'}\n";
	print "${$user}{'max_storage'}\n";
	print "${$user}{'units_per_week'}\n";
	print "$hours\n";
	print "${$user}{'bad_pw_count'}\n";
	print "${$user}{'num_logons'}\n";
	print "${$user}{'logon_server'}\n";
	print "${$user}{'country_code'}\n";
	print "${$user}{'code_page'}\n";
	print "${$user}{'user_id'}\n";
	print "${$user}{'primary_group_id'}\n";
	print "${$user}{'profile'}\n";
	print "${$user}{'home_dir_drive'}\n";
	print "${$user}{'password_expired'}\n";
 }

=item NetUserGetGroups($server, $user, \@groups)

Enums all global groups on server \\testserver to which user testuser belongs.

 if(!Win32::Lanman::NetUserGetGroups("testserver", "testuser", \@groups))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $group (@groups)
 {
	print "${$group}{'name'}\n";
 }

=item NetUserGetInfo($server, $user, \%info)

Retrieves information about user testuser on server \\testserver.

 if(!Win32::Lanman::NetUserGetInfo("testserver", "testuser", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 $hours = unpack("b168", $user{'logon_hours'});

 print "$info{'name'}\n";
 print "$info{'comment'}\n";
 print "$info{'usr_comment'}\n";
 print "$info{'full_name'}\n";
 print "$info{'password_age'}\n";
 print "$info{'priv'}\n";
 print "$info{'home_dir'}\n";
 print "$info{'flags'}\n";
 print "$info{'script_path'}\n";
 print "$info{'auth_flags'}\n";
 print "$info{'parms'}\n";
 print "$info{'workstations'}\n";
 print "$info{'last_logon'}\n";
 print "$info{'last_logoff'}\n";
 print "$info{'acct_expires'}\n";
 print "$info{'max_storage'}\n";
 print "$info{'units_per_week'}\n";
 print "$hours\n";
 print "$info{'bad_pw_count'}\n";
 print "$info{'num_logons'}\n";
 print "$info{'logon_server'}\n";
 print "$info{'country_code'}\n";
 print "$info{'code_page'}\n";
 print "$info{'user_id'}\n";
 print "$info{'primary_group_id'}\n";
 print "$info{'profile'}\n";
 print "$info{'home_dir_drive'}\n";
 print "$info{'password_expired'}\n";

=item NetUserGetLocalGroups($server, $user, $flags, \@groups)

Enums all local and global groups on server \\testserver to which user testuser belongs.

 if(!Win32::Lanman::NetUserGetLocalGroups("\\\\testserver", "testuser", &LG_INCLUDE_INDIRECT, \@groups))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $group (@groups)
 {
	print "${$group}{'name'}\n";
 }

=item NetUserSetGroups($server, $user, \@groups)

Sets global group memberships (domain users, testgroup1 and testgroup2)
for user testuser on server \\testserver.

 if(!Win32::Lanman::NetUserSetGroups("\\\\testserver", "testuser", ['domain users', 'testgroup1', 'testgroup2']))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetUserSetInfo($server, $user, \%info)

Sets the parameters of user testuser on server \\testserver. It's recommended that you first call NetUserGetInfo
to retrieve the current user parameters. Than you'd change the desired parameters and call NetUserSetInfo to
write the changed values back to the SAM. If you only want to change a few parameters, you'd use NetUSerSetProp.

 if(!Win32::Lanman::NetUserSetInfo("\\\\testserver", "testuser",
				  {'name' => 'testuser',
				   'password' => 'testpassword',
				   'home_dir' => '\\\\testserver\\testshare',
				   'comment' => 'test users comment',
				   'flags' => UF_ACCOUNTDISABLE | UF_PASSWD_CANT_CHANGE | UF_TEMP_DUPLICATE_ACCOUNT,
				   'script_path' => '\\\\testserver\\testshare\\logon_script.bat',
				   'full_name' => 'test users full name',
				   'usr_comment' => 'test users usr comment',
				   'parms' => 'test users parameters',
				   'workstations' => 'comp0001,comp0002,comp0003,comp0004,comp0005,comp0006,comp0007,comp0008',
				   'profile' => '\\\\testserver\\testshare\\profile_dir',
				   'home_dir_drive' => 'Y:',
				   'acct_expires' => time() + 3600 * 24,
				   'country_code' => 49,
				   'code_page' => 850,
				   'logon_hours' => pack("b168", "000000001111111100000000" x 7),
				   'password_expired' => 1}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }


=item NetUserSetProp($server, $user, \%info)

Sets or or more the parameters of user testuser on server \\testserver. There's no need to call NetUserGetInfo first.
You may specify the following parameters: name, password, home_dir, comment, flags, script_path, full_name, 
usr_comment, workstations, acct_expires, logon_hours, country_code, code_page, primary_group_id, profile and 
home_dir_drive. Because of the implementation, the call is not atomic. If a parameter couldn't be set, the call fails.

 if(!Win32::Lanman::NetUserSetProp("\\\\testserver", "testuser",
				  {'name' => 'testuser',
				   'password' => 'testpassword',
				   'home_dir' => '\\\\testserver\\testshare',
				   'comment' => 'test users comment',
				   'flags' => UF_ACCOUNTDISABLE | UF_PASSWD_CANT_CHANGE | UF_TEMP_DUPLICATE_ACCOUNT,
				   'script_path' => '\\\\testserver\\testshare\\logon_script.bat',
				   'full_name' => 'test users full name',
				   'usr_comment' => 'test users usr comment',
				   'workstations' => 'comp0001,comp0002,comp0003,comp0004,comp0005,comp0006,comp0007,comp0008',
				   'acct_expires' => time() + 3600 * 24,
				   'logon_hours' => pack("b168", "000000001111111100000000" x 7),
				   'country_code' => 49,
				   'code_page' => 850,
				   'primary_group_id' => 513, # domain users
				   'profile' => '\\\\testserver\\testshare\\profile_dir',
				   'home_dir_drive' => 'Y:'}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item NetUserModalsGet($server, \%info)

Retrieves global information (account policies) for all users and global groups in the security
database on server \\testserver.

 if(!Win32::Lanman::NetUserModalsGet("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 @keys = keys(%info);

 foreach $key(@keys)
 {
	print "$key: $info{$key}\n";
 }

=item NetUserModalsSet($server, \%info)

Sets global information (account policies) for all users and global groups in the security
database on server \\testserver. Be really carefully in calling this. As a rule, first call
NetUserModalsGet and then set the fields you want to modify. As last call NetUserModalsSet.
You cannot change the domain id and the domain name.

 if(!Win32::Lanman::NetUserModalsGet("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Set minimum password age to 14 days, maximum password age to 2 months,
minimum password length to 8 character

 $info{'min_passwd_age'} = 14 * 3600 * 24;
 $info{'max_passwd_age'} = 60 * 3600 * 24;
 $info{'min_passwd_len'} = 8;

 if(!Win32::Lanman::NetUserModalsSet("\\\\testserver", \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=back

=head2 Windows Networking

The Windows Networking functions offer a similar functionality like the NetUseXXX functions and 
some more.

=over 4

=item WNetAddConnection(\%useinfo)

Connects a local device to a network resource. The function is implemented by the 
WNetAddConnection2 or the WNetAddConnection3 call.

=item WNetCancelConnection($conn [, $flags [, $forcecancel] ])

Cancels an existing network connection. The function is implemented by the 
WNetCancelConnection2 call.

=item WNetEnumResource($scope, $type, $usage, \%startinfo, \@resinfo)

Enumerates network resources.

=item WNetConnectionDialog([ \%info ])

Shows a browsing dialog box for connecting to network resources.

=item WNetDisconnectDialog([ \%info ])

Shows a browsing dialog box for disconnecting from network resources. The function
is implemented by the WNetDisconnectDialog or the WNetDisconnectDialog1 call.

=item WNetGetConnection($local, \$remote)

Retrieves the name of the network resource associated with a local device.

=item WNetGetNetworkInformation($provider, \%info)

Retrieves information about a network provider.

=item WNetGetProviderName($type, \$provider)

Obtains the provider name for a specific type of network.

=item WNetGetResourceInformation(\%resource, \%info)

Obtains information about a network resource.

=item WNetGetResourceParent(\%resource, \%parent)

Retrieves the parent of a network resource.

=item WNetGetUniversalName($localname, \%info)

Takes a drive based path for a network resource and returns information that contains 
a more universal form of the name.

=item WNetGetUser($resource, \$user)

Retrieves the current default user name, or the user name used to establish a 
network connection. 

=item WNetUseConnection(\%resource [, \%useinfo ])

Makes a connection to a network resource.

=back

=head2 Windows Networking EXAMPLES:

=over 4

=item WNetAddConnection(\%useinfo)

Connects the local device z: to the share testshare on server \\testserver.

 $info{type} = &RESOURCETYPE_DISK;
 $info{localname} = "z:";
 $info{remotename} = "\\\\testserver\\testshare";

 if(!Win32::Lanman::WNetAddConnection(\%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Connects the local device x: to the share testshare on server \\testserver. The connection
will be established with credentials from user testuser in the domain testdomain and 
the password testpass. The connection will be remembered if the user logs on again.

 $info{type} = &RESOURCETYPE_DISK;
 $info{localname} = "x:";
 $info{remotename} = "\\\\testserver\\testshare";
 $info{username} = "testdomain\\testuser";
 $info{password} = "testpass";
 $info{flags} = &CONNECT_UPDATE_PROFILE;

You may also specify a network provider name.

 $info{provider} = "Microsoft Windows Network";

 if(!Win32::Lanman::WNetAddConnection(\%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Connects the local device lpt1: to the printer testprinter on server \\testserver.

 $info{type} = &RESOURCETYPE_PRINT;
 $info{localname} = "lpt1:";
 $info{remotename} = "\\\\testserver\\testprinter";

 if(!Win32::Lanman::WNetAddConnection(\%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Connects to ipc$ on server \\testserver. The connection will be established with 
credentials from user testuser in the domain testdomain and the password testpass.

 $info{type} = &RESOURCETYPE_ANY;
 $info{remotename} = "\\\\testserver\\testprinter";
 $info{password} = "testpass";
 $info{flags} = &CONNECT_UPDATE_PROFILE;

 if(!Win32::Lanman::WNetAddConnection(\%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item WNetCancelConnection($conn [, $flags [, $forcecancel] ])

Cancels the connection to drive z:. If there are open files to drive z: the connection
won't be canceled. The connection to z: will be remembered if the user logs on again.

 if(!Win32::Lanman::WNetCancelConnection("z:"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Cancels the connection to drive z:. The connection will be canceled even if there are 
still open files. The connection to z: won't be remembered furthermore.

 if(!Win32::Lanman::WNetCancelConnection("z:", &CONNECT_UPDATE_PROFILE, 1))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Cancels the connection to \\testserver\testshare. 

 if(!Win32::Lanman::WNetCancelConnection("\\\\testserver\\testshare"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Cancels the connection to printer port lpt1:. 

 if(!Win32::Lanman::WNetCancelConnection("lpt1:"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item WNetEnumResource($scope, $type, $usage, \%startinfo, \@resinfo)

Enumerates global resources in your network.

 if(!Win32::Lanman::WNetEnumResource(&RESOURCE_GLOBALNET, &RESOURCETYPE_ANY, 0, 0, \@info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $item (@info)
 {
	foreach $key (sort keys %$item)
	{
		print "$key=${$item}{$key}\n";
	}

	print "#" x 80;
 }

Enumerates all resources in your network beginning at the top level. Be careful if 
you run this code in a bigger network. It may take a long time.

 sub EnumNetRes
 {
	my @info;
	my $level = $_[0];

	return 0
		unless Win32::Lanman::WNetEnumResource(&RESOURCE_GLOBALNET, &RESOURCETYPE_ANY, 0, $_[1], \@info);

	foreach my $item (@info)
	{
		print " " x (2 * $level), "provider=#${$item}{provider}#\n";
		print " " x (2 * $level), "localname=${$item}{localname}\n";
		print " " x (2 * $level), "remotename=${$item}{remotename}\n";
		print " " x (2 * $level), "comment=${$item}{comment}\n";
		print " " x (2 * $level), sprintf "scope=0x%x\n", ${$item}{scope};
		print " " x (2 * $level), sprintf "type=0x%x\n", ${$item}{type};
		print " " x (2 * $level), sprintf "usage=0x%x\n", ${$item}{usage};

		print "#" x 80;

		EnumNetRes($level + 1, $item);
	}
 }

 EnumNetRes();

=item WNetConnectionDialog([ \%info ])

Shows a browsing dialog box for connecting to network resources.

 print Win32::Lanman::WNetConnectionDialog() ? 
		"Connection established" : "Dialog canceled";

Shows a browsing dialog box and specifies some flags.

 print Win32::Lanman::WNetConnectionDialog({flags => &CONNDLG_NOT_PERSIST | &CONNDLG_HIDE_BOX}) 
		"Connection established" : "Dialog canceled";

Shows a browsing dialog box and specifies the server \\testserver and share testshare
to connect.

 print Win32::Lanman::WNetConnectionDialog({flags => &CONNDLG_NOT_PERSIST | &CONNDLG_HIDE_BOX,
					    remotename => "\\\\testserver\\testshare"}) 
		"Connection established" : "Dialog canceled";

=item WNetDisconnectDialog([ \%info ])

Shows a browsing dialog box for disconnecting to network resources.

 print Win32::Lanman::WNetDisconnectDialog() ?
		"Connection removed" : "Dialog canceled";

Disconnects drive z: from the network resource. The disconnect is not forced and the 
connection to z: won't be remembered furthermore.

 if(!Win32::Lanman::WNetDisconnectDialog({localname => "z:", 
					  flags => &DISC_NO_FORCE | &DISC_UPDATE_PROFILE}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "Connection removed";

=item WNetGetConnection($local, \$remote)

Retrieves the name of the network resource associated with drive z:.

 if(!Win32::Lanman::WNetGetConnection("z:", \$remote)) 
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "z:=$remote";

Retrieves the name of the network resource associated with printer lpt1:.

 if(!Win32::Lanman::WNetGetConnection("lpt1:", \$remote)) 
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "lpt1:=$remote";

=item WNetGetNetworkInformation($provider, \%info)

Retrieves information about the Microsoft Windows Network provider.

 if(!Win32::Lanman::WNetGetNetworkInformation("Microsoft Windows Network", \%info)) 
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key(sort keys %info)
 {
	print "$key=$info{$key}\n";
 }

=item WNetGetProviderName($type, \$provider)

Obtains the provider name for the  WNNC_NET_LANMAN network (Microsoft Windows Network). 

 if(!Win32::Lanman::WNetGetProviderName(&WNNC_NET_LANMAN, \$provider)) 
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print $provider;

=item WNetGetResourceInformation(\%resource, \%info)

Obtains information about the file \\testserver\testshare\testdir\testfile.txt. The 
file must be exist. You may specify a network provider name, but it's optional.

 if(!Win32::Lanman::WNetGetResourceInformation({remotename => "\\\\testserver\\testshare\\testdir\\testfile.txt",
						provider => "Microsoft Windows Network"},
					       \%info)) 
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key(sort keys %info)
 {
	print "$key=$info{$key}\n";
 }

=item WNetGetResourceParent(\%resource, \%parent)

Retrieves the parent of the network resource \\testserver\testshare.

 if(!Win32::Lanman::WNetGetResourceParent({remotename => "\\\\testserver\\testshare",
					   provider => "Microsoft Windows Network"},
					  \%info)) 
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key(sort keys %info)
 {
	print "$key=$info{$key}\n";
 }

=item WNetGetUniversalName($localname, \%info)

Retrieves the universal form of the file name z:\testdir\testfile.txt.

 if(!Win32::Lanman::WNetGetUniversalName("z:\\testdir\\testfile.txt", \%info)) 
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key(sort keys %info)
 {
	print "$key=$info{$key}\n";
 }

=item WNetGetUser($resource, \$user)

Retrieves the user name used to establish a connection to drive z:. 

 if(!Win32::Lanman::WNetGetUser("z:", \$user)) 
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print $user;

=item WNetUseConnection(\%resource [, \%useinfo ])

Connects drive z: to \\testserver\testshare. If the current user has no access to the
network resource, the system brings up a dialog to supply user credentials.

 if(!Win32::Lanman::WNetUseConnection({localname => "z:", remotename => "\\\\testserver\\testshare",
				      flags => &CONNECT_INTERACTIVE | &CONNECT_PROMPT,
				      type => &RESOURCETYPE_DISK}))

 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Connects drive lpt1: to \\testserver\testprinter.

 if(!Win32::Lanman::WNetUseConnection({localname => "lpt1:", remotename => "\\\\testserver\\testprinter",
				      type => &RESOURCETYPE_PRINT}))

 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=back

=head2 Services

=over 4

Throughout these functions, which are used to manage services, you can specify the 
default service database by replacing $servicedb with the empty string (or "ServicesActive").

Currently NT supports only the default database.
If you specify an invalid database name, you'll get an error 1065 (database doesn't exist).

=item StartService($server, $servicedb, $service)

Starts the service $service on server $server. Specify an empty string to use the default
service database in $servicedb.

=item StopService($server, $servicedb, $service, \%status)

Stops the service $service on server $server. The service status will be returned in
%status. Specify an empty string to use the default service database in $servicedb.

=item PauseService($server, $servicedb, $service, \%status)

Pauses the service $service on server $server. The service status will be returned in
%status. Specify an empty string to use the default service database in $servicedb.

=item ContinueService($server, $servicedb, $service, \%status)

Continues the service $service on server $server. The service status will be returned in
%status. Specify an empty string to use the default service database in $servicedb.

=item InterrogateService($server, $servicedb, $service, \%status)

Interrogates the service $service on server $server. The service status will be returned in
%status. Specify an empty string to use the default service database in $servicedb.

=item ControlService($server, $servicedb, $service, $contol, \%status)

Sends a control message to the service $service on server $server. The service status will
be returned in %status. Specify an empty string to use the default service database in
$servicedb. $control can be one of the following commands: SERVICE_CONTROL_CONTINUE,
SERVICE_CONTROL_INTERROGATE, SERVICE_CONTROL_PAUSE, SERVICE_CONTROL_STOP or a server
specific control code between 128 and 255. Do not specify SERVICE_CONTROL_SHUTDOWN. To stop,
continue, pause or interrogate a service, you can use the app. calls or ControlService. But
you can send service specific controls between 128 and 255 to initiate a conversation with
the service or something else. The most services ignore this messages.

=item CreateService($server, $servicedb, \%param)

Creates a service on server $server. Specify an empty string for the default service database
in $servicedb. Valid keys for %param are:

 name    : service name
 display : service display name in control panel applet
 type    : service type
	SERVICE_WIN32_OWN_PROCESS   - the service file contains only one service
	SERVICE_WIN32_SHARE_PROCESS - the service file contains more services
	SERVICE_KERNEL_DRIVER       - the service is a kernal driver
	SERVICE_FILE_SYSTEM_DRIVER  - the service is a file system driver
	SERVICE_INTERACTIVE_PROCESS - the service can interact with the desktop,
	   must be or'ed with SERVICE_WIN32_OWN_PROCESS or
	   SERVICE_WIN32_SHARE_PROCESS;
	   if your service has to interact with the desktop, it has to
	   run with the localsystem account
 start   : when to start the service
	SERVICE_BOOT_START	 - starts at boot time (device drivers)
	SERVICE_SYSTEM_START - will be started by the IoInitSystem function
	                       (device drivers)
	SERVICE_AUTO_START	 - will be started by the service control manager
	SERVICE_DEMAND_START - will be started by calling StartService
	SERVICE_DISABLED	 - can't be started
 control	:
	SERVICE_ERROR_IGNORE	- errors will be logged, startup will be continued
	SERVICE_ERROR_NORMAL	- errors will be logged, startup will be continued,
	                          message box will pop up
	SERVICE_ERROR_SEVERE	- errors will be logged, startup will be continued
	                          if the last known good configuration is started,
	                          otherwise the system is restarted with the last
	                          known good configuration
	SERVICE_ERROR_CRITICAL	- errors will be logged, startup failes if the last
	                          known good configuration is started, otherwise
	                          the system is restarted with the last known
	                          good configuration
 filename: path to the executable which runs for the service
 group	: the load ordering group of which the service is a member
 tagid	: unique identifier for the service in the load order group;
          only valid for device drivers
 dependencies array : the service will not start until all services or
      load ordering groups in the dependencies array are started

account        : account name for the service to log on as; Should be
specified as one of
 
'domain\username'  for domain accounts
 
or '.\usr' or 'username' for machine accounts
 
or 'LocalSystem'

LocalSystem is not a real account, but instead species that the service
will run with "the system account".
 
Note if type includes SERVICE_INTERACTIVE_PROCESS then account must => 'LocalSystem'.
 
The account chosen requires the logon as service privilege. 

password: password for account; 
	if  account =>LocalSystem, then password => ''

=item DeleteService($server, $servicedb, $service)

Deletes the service $service on server $server. Specify an empty string to use the default
service database in $servicedb. If you delete a running service, the service will be marked
as deleted, but doesn't stop the service! To stop it, call StopService.

=item EnumServicesStatus($server, $servicedb, $type, $state, \@services)

Enums the status of all services on server $server. Specify an empty string to use the default
service database in $servicedb. Valid types are:

 SERVICE_WIN32  - win32 services
 SERVICE_DRIVER - kernel driver

Valid states are:

 SERVICE_ACTIVE		- active services
 SERVICE_INACTIVE	- inactive services
 SERVICE_STATE_ALL	- both of them

=item EnumDependentServices($server, $servicedb, $service, $state, \@services)

Enums all services dependent from service in $service on server $server. Specify an empty
string to use the default service database in $servicedb.

=item ChangeServiceConfig($server, $servicedb, $service, \%param)

Changes the service configuration to the values specified in %param for service $service on
server $server. Specify an empty string to use the default service database in $servicedb. For
a description of %param, see CreateService.

=item GetServiceDisplayName($server, $servicedb, $service, \$display)

Obtains the service display name of service $service on server $server. Specify an empty string
to use the default service database in $servicedb.

=item GetServiceKeyName($server, $servicedb, $display, \$service)

Obtains the service name from the service display name $display on server $server. Specify an empty
string to use the default service database in $servicedb.

=item LockServiceDatabase($server, $servicedb, \$lock)

Locks the service control manager database on server $server. Only one process can lock the database
at a given time. LockServiceDatabase prevents the service control manager from starting services.
You have to call UnlockServiceDatabase to unlock the database. Specify an empty string to use the
default service database in $servicedb.

=item UnlockServiceDatabase($server, $servicedb, $lock)

Unlocks the service control manager database on server $server by releasing the lock $lock. Specify an
empty string to use the default service database in $servicedb.

=item QueryServiceLockStatus($server, $servicedb, \%lock)

Retrieves the lock status of the service control manager database on server $server. Specify an empty
string to use the default service database in $servicedb.

=item QueryServiceConfig($server, $servicedb, $service, \%config)

Retrieves the configuration parameters of the service $service on server $server. Specify an empty
string to use the default service database in $servicedb.

=item QueryServiceStatus($server, $servicedb, $service, \%status)

Retrieves the current status of the service $service on server $server. Specify an empty string to use
the default service database in $servicedb.

=item QueryServiceObjectSecurity($server, $servicedb, $service, $securityinformation, \$securitydescriptor)

Retrieves a security descriptor associated with the service $service on server $server. $securityinformation
specifies the requested security information. Valid security informations are OWNER_SECURITY_INFORMATION,
GROUP_SECURITY_INFORMATION, DACL_SECURITY_INFORMATION and SACL_SECURITY_INFORMATION. To get
SACL_SECURITY_INFORMATION, the calling process needs the SeSecurityPrivilege privilege enabled. Specify an
empty string to use the default service database in $servicedb.

=item SetServiceObjectSecurity($server, $servicedb, $service, $securityinformation, $securitydescriptor)

Sets a security descriptor of the service $service on server $server. $securityinformation specifies the
security information to set. Valid security informations are OWNER_SECURITY_INFORMATION,
GROUP_SECURITY_INFORMATION, DACL_SECURITY_INFORMATION and SACL_SECURITY_INFORMATION. $securitydescriptor
must be a valid security descriptor. 

Note: Be careful when using this call, since if you revoke access to everyone, then nobody will be able to
 control the service. Also if you can grant the SERVICE_START and SERVICE_STOP rights to the
everyone group, any people can start and stop your service (as default only administrators and power user
can do this). Specify an empty string to use the default service database in $servicedb.

=item QueryServiceConfig2($server, $servicedb, $service, \%config)

Retrieves the optional configuration parameters of the service $service from the $servicedb database. This function requires Windows 2000.

=item ChangeServiceConfig2($server, $servicedb, $service, \%config)

Changes the optional configuration parameters of the service $service from the $servicedb database. This function requires Windows 2000.

=item QueryServiceStatusEx($server, $servicedb, $service, \%status)

Retrieves the current status of the specified service. This function requires Windows 2000.

=item EnumServicesStatusEx($server, $servicedb, $type, $state, \@services [, $group])

Enumerates services in the specified service control manager database. Filtering is done on type, state and group. The group parameter is optional.
If you omit the group parameter, the function returns all services filtered only on type and state.
 This function requires Windows 2000.

=back

=head2 Services EXAMPLES:

=over 4

=item StartService($server, $servicedb, $service)

Starts the schedule service on server \\testserver.

 if(!Win32::Lanman::StartService("testserver", '', "schedule"))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item StopService($server, $servicedb, $service, \%status)

Stops the schedule service on server \\testserver and prints the status flags.

 if(!Win32::Lanman::StopService("testserver", '', "schedule", \%status))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

for $keyeach (sort keys %status)
 {
	print "$key = $status{$key}\n";
 }

=item PauseService($server, $servicedb, $service, \%status)

Pauses the schedule service on server \\testserver and prints the status flags.

 if(!Win32::Lanman::PauseService("\\\\testserver", '', "schedule", \%status))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 for $keyeach (sort keys %status)
 {
	print "$key = $status{$key}\n";
 }

=item ContinueService($server, $servicedb, $service, \%status)

Continues the schedule service on server \\testserver and prints the status flags.

 if(!Win32::Lanman::ContinueService("\\\\testserver", '', "schedule", \%status))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 for $keyeach (sort keys %status)
 {
	print "$key = $status{$key}\n";
 }

=item InterrogateService($server, $servicedb, $service, \%status)

Interrogates the schedule service on server \\testserver and prints the status flags.

 if(!Win32::Lanman::InterrogateService("\\\\testserver", '', "schedule", \%status))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key (sort keys %status)
 {
	print "$key = $status{$key}\n";
 }

=item ControlService($server, $servicedb, $service, $contol, \%status)

Stops the schedule service on server \\testserver and prints the status flags.

 if(!Win32::Lanman::ControlService("\\\\testserver", '', "schedule", &SERVICE_CONTROL_STOP, \%status))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key (sort keys %status)
 {
	print "$key = $status{$key}\n";
 }

Sends the value 130 to the service myservice on server \\testserver and prints the status flags.

 if(!Win32::Lanman::ControlService("\\\\testserver", '', "myservice", 130, \%status))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key (sort keys %status)
 {
	print "$key = $status{$key}\n";
 }

=item CreateService($server, $servicedb, \%param)

Creates the service myservice on server \\testserver. The display name is 'my first service'.
The service logs on with the testdomain\testuser account. We have to grant the logon as service
right. The service doesn't have dependencies. It will belong to the load ordering group
'myservices'

 if(!Win32::Lanman::GrantPrivilegeToAccount("\\\\testserver", "SeServiceLogonRight",
					   ['testdomain\\testuser']) ||
   !Win32::Lanman::CreateService("\\\\testserver", '', { name => 'myservice'
							 display => 'my first service',
							 type => &SERVICE_WIN32_OWN_PROCESS,
							 start => &SERVICE_AUTO_START,
							 control => &SERVICE_ERROR_NORMAL,
							 filename => "C:\\WINNT\\system32\\myservice.exe",
							 group => 'myservices',
						 	 account => 'testdomain\\testuser',
							 password => 'testpass'}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }


Creates the next service myservice2 on server \\testserver. The display
name is 'my next service'. The service logs on with the LocalSystem
account (this is because account and password are missing, so LocalSystem is the
default). The service has no dependencies or load ordering
group. The service can have more than one service in the same file and
it can interact with the desktop.

 if(!Win32::Lanman::CreateService("\\\\testserver", '', { name => 'myservice2'
							 display => 'my next service',
							 type => &SERVICE_WIN32_SHARE_PROCESS |
								 &SERVICE_INTERACTIVE_PROCESS,
							 start => &SERVICE_DEMAND_START,
							 control => &SERVICE_ERROR_IGNORE,
							 filename => "C:\\WINNT\\system32\\mysrv_x.exe"}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Creates the 3rd service myservice3 on server \\testserver. The display
name is 'my 3rd service'. The service logs on with the LocalSystem
account. The service doesn't have dependencies or a load ordering group.
The service may have more than one service in the same file.

 if(!Win32::Lanman::CreateService("\\\\testserver", '', { name => 'myservice3'
							 display => 'my 3rd service',
							 type => &SERVICE_WIN32_SHARE_PROCESS,
							 start => &SERVICE_DEMAND_START,
							 control => &SERVICE_ERROR_IGNORE,
							 filename => "C:\\WINNT\\system32\\mysrv_x.exe",
							 account => 'LocalSystem',
							 password = ''}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }


Creates the 4th service myservice3 on server \\testserver. The display
name is 'my 4th service'. The service logs on with the LocalSystem
account. The service has dependencies (two services and one load
ordering group). The service can interact with the desktop.

 if(!Win32::Lanman::CreateService("\\\\testserver", '',
   { name => 'myservice4',
	 display => 'my 4th service',
	 type => &SERVICE_WIN32_OWN_PROCESS | &SERVICE_INTERACTIVE_PROCESS,
	 start => &SERVICE_DEMAND_START,
	 control => &SERVICE_ERROR_IGNORE,
	 filename => "C:\\WINNT\\system32\\mysrv4.exe",
	 dependencies => ['myservice2', 'myservice2', 'myservices']
   }))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item DeleteService($server, $servicedb, $service)

Deletes the service 'myservice' on server \\testserver.

 if(!Win32::Lanman::DeleteService("\\\\testserver", '', 'myservice'))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item EnumServicesStatus($server, $servicedb, $type, $state, \@services)

Enums the status of all normal services on server \\testserver.

 if(!Win32::Lanman::EnumServicesStatus("\\\\testserver", "",
  &SERVICE_WIN32, &SERVICE_STATE_ALL, \@services))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $service (@services)
 {
	print "${$service}{name}\n";

	foreach $key (sort keys %$service)
	{
		print "\t$key = ${$service}{$key}\n"
			if $key ne 'name';
	}
 }

Enums the status of all active kernel drivers on server \\testserver.

 if(!Win32::Lanman::EnumServicesStatus("\\\\testserver", "",
  &SERVICE_DRIVER, &SERVICE_ACTIVE, \@services))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $service (@services)
 {
	print "${$service}{name}\n";

	foreach $key (sort keys %$service)
	{
		print "\t$key = ${$service}{$key}\n"
			if $key ne 'name';
	}
 }

=item EnumDependentServices($server, $servicedb, $service, $state, \@services)

Enums the name and status of all services depend on service
LanmanWorkstation on server \\testserver.

 if(!Win32::Lanman::EnumDependentServices("\\\\testserver", "", 'LanmanWorkstation', &SERVICE_STATE_ALL, \@services))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $service (@services)
 {
	print "${$service}{name}\n";

	foreach $key (sort keys %$service)
	{
		print "\t$key = ${$service}{$key}\n"
			if $key ne 'name';
	}
 }

=item ChangeServiceConfig($server, $servicedb, $service, \%param)

Changes the service configuration for service myservice on server \\testserver. You have to
specify only the properties you want to change. All the others remain their values. In this
example, we only change the display and account information. Don't forget to grant the
logon as service right to testdomain\testuser. See also CreateService examples.

 if(!Win32::Lanman::ChangeServiceConfig("\\\\testserver", '', { name => 'myservice'
							       display => 'a new display name',
						 	       account => 'testdomain\\testuser',
							       password => 'testpass'}))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item GetServiceDisplayName($server, $servicedb, $service, \$display)

Obtains the service display name of service myservice on server \\testserver.

 if(!Win32::Lanman::GetServiceDisplayName("\\\\testserver", "", 'myservice', \$display))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print $display;

=item GetServiceKeyName($server, $servicedb, $display, \$service)

Obtains the service name from the service display name 'my newest service' on server \\testserver.

 if(!Win32::Lanman::GetServiceKeyName("\\\\testserver", "", 'my newest service', \$service))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print $service;

=item LockServiceDatabase($server, $servicedb, \$lock)

Locks the service control manager database on server \\testserver. If locked, do any stuff and the
unlock the database.

 if(!Win32::Lanman::LockServiceDatabase("\\\\testserver", "", \$lock))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 # do any stuff here...

 if(!Win32::Lanman::UnlockServiceDatabase("\\\\testserver", "", $lock))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item UnlockServiceDatabase($server, $servicedb, $lock)

Unlocks the service control manager database on server \\testserver. See the example above.

=item QueryServiceLockStatus($server, $servicedb, \%lock)

Retrieves the lock status of the service control manager database on server \\testserver.

 if(!Win32::Lanman::QueryServiceLockStatus("\\\\testserver", "", \%lock))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 for $key (sort keys %lock)
 {
	print "$key = $lock{$key}\n";
 }

=item QueryServiceConfig($server, $servicedb, $service, \%config)

Retrieves the configuration parameters of the service myservice on server \\testserver.

 if(!Win32::Lanman::QueryServiceConfig("\\\\testserver", '', 'myservice', \%config))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 for $key (sort keys %config)
 {
	if($key eq "dependencies")
	{
		$dependencies = $config{$key};
		print "\t$key = ", $#$dependencies + 1, "\n";

		foreach $dependency (@$dependencies)
		{
			print "\t\t$dependency\n";
		}
	}
	else
	{
		print "\t$key = $config{$key}\n";
	}
 }

=item QueryServiceStatus($server, $servicedb, $service, \%status)

Retrieves the current status of the service myservice on server \\testserver.

 if(!Win32::Lanman::QueryServiceStatus("\\\\testserver", "", 'myservice', \%status))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

for $key (sort keys %status)
 {
	print "$key = $status{$key}\n";
 }

=item QueryServiceObjectSecurity($server, $servicedb, $service, $securityinformation, \$securitydescriptor)

Retrieves a security descriptor associated with the service $service on server $server.
OWNER_SECURITY_INFORMATION, GROUP_SECURITY_INFORMATION, DACL_SECURITY_INFORMATION and
SACL_SECURITY_INFORMATION will be retrieved.

 $securityinformation = &OWNER_SECURITY_INFORMATION | &GROUP_SECURITY_INFORMATION
                      | &DACL_SECURITY_INFORMATION | &SACL_SECURITY_INFORMATION;

 if(!Win32::Lanman::QueryServiceObjectSecurity("\\\\testserver", "",
      'myservice', $securityinformation, \$securitydescriptor))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 #Do not print these binary data.
 #print $securitydescriptor;

=item SetServiceObjectSecurity($server, $servicedb, $service, $securityinformation, $securitydescriptor)

Sets a security descriptor of the service myservice on server
\\testserver. Only DACL_SECURITY_INFORMATION will be set. You have to build
a valid security descriptor in $securitydescriptor.

 #build a valid security descriptor
 #$securitydescriptor = ...

 if(!Win32::Lanman::SetServiceObjectSecurity("\\\\testserver", "", 'myservice', &DACL_SECURITY_INFORMATION,
					    $securitydescriptor))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item QueryServiceConfig2($server, $servicedb, $service, \%config)

Retrieves the optional configuration parameters of the service testserv on the server \\testserver.

 if(!Win32::Lanman::QueryServiceConfig2("\\\\testserver", "", 'testserv', \%config))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key (sort keys %config)
 {
	print "$key = $config{$key}\n";
 }

=item ChangeServiceConfig2($server, $servicedb, $service, \%config)

Changes the optional configuration parameters of the service testserv on server \\testserver.
Unfortunately, you cannot configure the actions parameters. I don't know why, but the call
fails as soon as the actions parameter is specified.

 $config{description} = 'This is a service description';
 $config{command} = 'c:\\winnt\\system32\\notepad.exe';
 $config{rebootmsg} = 'This is a reboot message';
 $config{resetperiod} = 100;
 #@actions = ({type => &SC_ACTION_NONE, delay => 1000}, 
 #	     {type => &SC_ACTION_REBOOT, delay => 2000},
 #	     {type => &SC_ACTION_RESTART, delay => 3000},
 #	     {type => &SC_ACTION_RUN_COMMAND, delay => 4000});
 #$config{actions} = \@actions;

 if(!Win32::Lanman::ChangeServiceConfig2("\\\\testserver", "", 'testserv', \%config))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item QueryServiceStatusEx($server, $servicedb, $service, \%status)

Retrieves the current status of the service testserv on the server \\testserver.

 if(!Win32::Lanman::QueryServiceStatusEx("\\\\testserver", "", 'testserv', \%status))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key (sort keys %status)
 {
	print "\t$key = $status{$key}\n";
 }

=item EnumServicesStatusEx($server, $servicedb, $type, $state, \@services [, $group])

Enumerates all services belonging to the group testgroup on the server \\testserver. 

 if(!Win32::Lanman::EnumServicesStatusEx("\\\\testserver", "", &SERVICE_WIN32 | &SERVICE_DRIVER,
					 &SERVICE_STATE_ALL, \%services, 'testgroup'))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $service (@services)
 {
        foreach $key (sort keys %$service)
        {
                print "\t$key = ${$service}{$key}\n";
        }
 }

=back

=head2 Eventlog

=over 4

Throughout this section $source will represent the event log source, which can only be 
"application" or "system" or "security".

=item ReadEventLog($server, $source, $first, $last, \@events)

Reads events in the range from $first to $last from the event log $source on server $server in the order $first to $last. So y
ou can read forward ,when $first <= $last, or backward , by having $first > $last. Sequential reads as with
NT EventViewer's Next and Previous buttons, are not supported.
This is because after each call the event log is closed.

To get all events  set $first to 1 and $last to -1 (or 0xffffffff if you prefer).

=item GetEventDescription($server, \%event)

Retrieves the description of the event %event on server $server. %event must be retrieved
by a ReadEventLog call.

=item ClearEventLog($server, $source [, $filename])

Clears the eventlog $source on server $server and makes an optionally backup to file
$filename before clearing. 
ClearEventLog will fail with error 183 (couldn't create existing file). 
In this case, the eventlog will not be cleared.

=item BackupEventLog($server, $source, $filename)

Makes a backup from the eventlog $source on server $server to file $filename. 
As with ClearEventLog, BackupEventLog fails if filename exists.

=item ReportEvent($server, $source, $type, $category, $id, $sid, \@strings, $data)

Writes an event to the event log $source on server $server.

=item GetNumberOfEventLogRecords($server, $source, \$numrecords)

Retrieves the number of records in the event log $source on server $server.

=item GetOldestEventLogRecord($server, $source, \$oldestrecord)

Retrieves the oldest record number in the event log $source on server $server.

=back

=head2 Eventlog EXAMPLES:

=over 4

=item ReadEventLog($server, $source, $first, $last, \@events)

Reads all events from the system event log in the range from the first to the last event
on server \\testserver.

 if(!Win32::Lanman::ReadEventLog("testserver", 'system', 0, 0xffffffff, \@events))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Reads all events from the security event log in reverse order on server \\testserver.

 if(!Win32::Lanman::ReadEventLog("\\\\testserver", 'security', 0xffffffff, 0, \@events))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

Retrieves the first and the last record number in the application log on server
\\testserver. Then it reads all these events and prints out the event properties.

 if(!Win32::Lanman::GetOldestEventLogRecord("testserver", 'application', \$first))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::GetNumberOfEventLogRecords("testserver", 'application', \$last))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 $last += $first - 1;

 if(!Win32::Lanman::ReadEventLog("testserver", 'application', $first, $last, \@events))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $event(@events)
 {
	#get the event description for the event
	${$event}{'eventdescription'} = "*** Error get event description ***"
		if !Win32::Lanman::GetEventDescription("\\\\testserver", $event);

	${$event}{'eventdescription'} = join('', split(/\r/, ${$event}{'eventdescription'}));
	${$event}{'eventdescription'} = join('', split(/\n/, ${$event}{'eventdescription'}));

	print '#' x 80;

	@keys = sort keys %$event;

	foreach $key(@keys)
	{
		if($key eq 'strings')
		{
			$strings = ${$event}{$key};

			print "strings\n";

			foreach $string(@$strings)
			{
				print "\t$string\n";
			}
		}
		elsif($key eq 'eventid')
		{
			#this is the event id you'll see in event viewer; the highest 16 bit are discarded
			print "$key=" . (${$event}{$key} & 0xffff) . "\n";

			#this is the real event id
			#print "$key=" . (${$event}{$key}) . "\n";

		}
		elsif($key eq 'timegenerated' || $key eq 'timewritten')
		{
			print "$key=" . localtime(${$event}{$key}) . "\n";

		}
		elsif($key eq 'usersid' || $key eq 'data')
		{
			print "$key=" . unpack("H" . 2 * length(${$event}{$key}), ${$event}{$key}) . "\n";

		}
		else
		{
			print "$key=${$event}{$key}\n";
		}
	}
 }

=item GetEventDescription($server, \%event)

Retrieves all records in the system log on server \\testserver. Then it reads
all these events and prints out the event descriptions.

 if(!Win32::Lanman::ReadEventLog("\\\\testserver", 'system', 0, -1, \@events))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $event(@events)
 {
	#get the event description for the event
	${$event}{'eventdescription'} = "*** Error get event description ***"
		if !Win32::Lanman::GetEventDescription("\\\\testserver", $event);

	print ${$event}{'eventdescription'};
 }

=item BackupEventLog($server, $source, $filename)

Makes a backup from the application eventlog on server \\testserver to the
file application.evt.

 if(!Win32::Lanman::BackupEventLog("\\\\testserver", 'application', 'application.evt'))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item ClearEventLog($server, $source [, $filename])

Makes a backup from the application eventlog on server \\testserver to the
file application.evt. Thereafter the application event log will be cleared.

 if(!Win32::Lanman::ClearEventLog("\\\\testserver", 'application', 'application.evt'))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }


Clears the system eventlog on server \\testserver without backing up the events.

 if(!Win32::Lanman::ClearEventLog("\\\\testserver", 'system'))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item ReportEvent($server, $source, $type, $category, $id, $sid, \@strings, $data)

Reports an event to the event log on server \\testserver.

 #build administrators sid
 $sid = pack("C16", 1, 2, 0, 0, 0, 0, 0, 5, 32, 0, 0, 0, 32, 2, 0 , 0);

 unless(Win32::Lanman::ReportEvent("\\\\testserver", 'Print', &EVENTLOG_ERROR_TYPE, 100, 256, $sid, 
 								['string1', 'string2', 'string3'], 'Here is my data ...')
 		) {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item GetNumberOfEventLogRecords($server, $source, \$numrecords)

Retrieves the number of records in the event log system on server \\testserver.

 if(!Win32::Lanman::GetNumberOfEventLogRecords("\\\\testserver", 'system', \$numrecords))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "$numrecords\n";

=item GetOldestEventLogRecord($server, $source, \$oldestrecord)

Retrieves the oldest record number in the event log system on server \\testserver.

 if(!Win32::Lanman::GetOldestEventLogRecord("\\\\testserver", 'system', \$oldestrecord))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print "$oldestrecord\n";

=back

=head2 Windows Terminal Server (WTS)

=over 4

=item Note:

The WTS dll (wtsapi32.dll) is not an integral part of Windows NT. The Lanman module tries
to loads the dll dynamically when your script starts. The dll is not statically linked. If the dll
is present and can be loaded, then you can call the WTS functions. But if the dll cannot
be loaded, every WTS call fails. GetLastError() returns 126 (ERROR_MOD_NOT_FOUND). 
Wtsapi32.dll needs three additional dlls: utildll.dll, regapi.dll and winsta.dll. Copy
each of these dlls into your system32 directory.
 
=item WTSEnumerateServers($domain, \@sessions)

Enumerates all WTS server in domain.

=item WTSOpenServer($server, \$handle)

Opens an handle on a WTS server. 

This call is not really necessary and only implemented for completeness and for those keenly 
interested in performance. 
With the WTS api you have to open a server handle, then call your
WTS function and close the handle with WTSCloseServer at the end. The module opens the
handle every time you call a WTS function, makes the job and closes the handle at the end.
The advantage: you don't need to deal with handles, the downside: the  overhead
in opening and closing a handle at each call.

=item WTSCloseServer($handle)

Closes an handle on a WTS server. This call is not really necessary and only implemented
for completeness. See also the remarks at WTSOpenServer.

=item WTSEnumerateSessions($server, \@sessions)

Enumerates sessions on a WTS server.

=item WTSEnumerateProcesses($server, \@processes)

Enumerates processes on a WTS server.

=item WTSTerminateProcess($server, $processid [, $exitcode])

Terminates a process on a WTS server.

=item WTSQuerySessionInformation($server, $sessionid, \@infoclass, \%info)

Returns information about the specified session on a WTS server. You need to
specify which information you are interested in. To get all information 
available, use WTSInfoClassAll() as @infoclass parameter.

=item WTSQueryUserConfig($server, $user, \@infoclass, \%config)

Returns the WTS user properties. Call this on your domains primary domain controller.
You need to specify which information you are interested in. To get all information 
available, use WTSUserConfigAll() as @infoclass parameter.

=item WTSSetUserConfig($server, $user, \%config)

Sets the WTS user properties. Call this on your primary domain controller.
The function sets all information contained in the %config hash.

=item WTSSendMessage($server, $sessionid, $title, $message[, $style [, $timeout [, \$response]]])

Displays a message box on the client desktop of a WTS session.

=item WTSDisconnectSession($server, $sessionid [, $wait])

Disconnects the logged on user from the specified WTS session without 
closing the session.

=item WTSLogoffSession($server, $sessionid [, $wait])

Logs off the specified WTS session.

=item WTSShutdownSystem($server[, $flag])

Shuts down the specified WTS server. Avoid this call. I believe it doesn't behave
as expected. It ignores the $server parameter and shuts down the 
local machine. Is this a bug or a feature? I don't know.

=item WTSWaitSystemEvent($server[, $flag])

Waits for a WTS event before returning to the caller.

=back

=head2 Windows Terminal Server (WTS) EXAMPLES:

=over 4

=item WTSEnumerateServers($domain, \@sessions)

Enumerates all WTS server in domain testdomain.

 if(!Win32::Lanman::WTSEnumerateServers("testdomain", \@servers))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $server(@servers)
 {
	print "${$server}{name}\n";
 }

=item WTSOpenServer($server, \$handle)

Opens and closes a WTS handle on server \\testserver. These calls are not really 
necessary. See the description above.

 if(!Win32::Lanman::WTSOpenServer("\\\\testserver", \$handle))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 # use the handle
 # ...

 if(!Win32::Lanman::WTSCloseServer($handle))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item WTSCloseServer($handle)

Opens and closes a WTS handle on server \\testserver. These calls are not really 
necessary. See the description above.

 if(!Win32::Lanman::WTSOpenServer("\\\\testserver", \$handle))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 # use the handle
 # ...

 if(!Win32::Lanman::WTSCloseServer($handle))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item WTSEnumerateSessions($server, \@sessions)

Enumerates all sessions on the WTS server \\testserver.

 if(!Win32::Lanman::WTSEnumerateSessions("\\\\testserver", \@sessions))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $session (@sessions)
 {
	foreach $key (keys %$session)
	{
		print "$key=${$session}{$key}\n";
	}
 }

=item WTSEnumerateProcesses($server, \@processes)

Enumerates all processes on the WTS server \\testserver.

 if(!Win32::Lanman::WTSEnumerateProcesses("\\\\testserver", \@processes))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $process (@processes)
 {
	foreach $key (keys %$process)
	{
		if($key eq "sid")
		{
			print "$key=", unpack("H" . 2 * length(${$process}{$key}), ${$process}{$key}), "\n";
		}
		else
		{
			print "$key=${$process}{$key}\n";
		}
	}
 }

=item WTSTerminateProcess($server, $processid [, $exitcode])

Terminates all processes which belongs to disconnected sessions on the WTS server 
\\testserver (these have windowstation parameter of the empty string). All processes terminate with
the exit value 3 (if you omit the exitcode, the processes terminate with exit code 0). 
You'll get some access denied errors (error 5) because you cannot terminate system 
processes like csrss or winlogon. 

 if(!Win32::Lanman::WTSEnumerateSessions("\\\\testserver", \@sessions))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 if(!Win32::Lanman::WTSEnumerateProcesses("\\\\testserver", \@processes))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $session (@sessions)
 {
	next
		if ${$session}{winstationname} ne "";

	foreach $process (@processes)
	{
		next
			unless ${$process}{sessionid} == ${$session}{id};

		print "${$process}{name} (${$process}{processid}) will be terminated\n";

		if(!Win32::Lanman::WTSTerminateProcess("\\\\testserver", ${$process}{processid}, 3))
		{
			print "Oops, cannot terminate process ${$process}{processid}; error: ";
			# get the error code
			print Win32::Lanman::GetLastError();
			print "\n";
		}
	}
 }

=item WTSQuerySessionInformation($server, $sessionid, \@infoclass, \%info)

Returns all information available for the session id 0 (session 0 is the WTS 
console) on server \\testserver.

 if(!Win32::Lanman::WTSQuerySessionInformation("\\\\testserver", 0, [WTSInfoClassAll()], \%info))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key (sort keys %info)
 {
	print "$key=$info{$key}\n";
 } 

=item WTSQueryUserConfig($server, $user, \@infoclass, \%config)

Returns all WTS specific user properties for user testuser from server 
\\testserver. \\testserver should be your primary domain controller.

 if(!Win32::Lanman::WTSQueryUserConfig("\\\\testserver", "testuser", [WTSUserConfigAll()], \%user))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 foreach $key (sort keys %user)
 {
	print "$key=$user{$key}\n";
 } 

=item WTSSetUserConfig($server, $user, \%config)

Set WTS specific user properties for user testuser from server \\testserver. 
\\testserver should be your primary domain controller. In this sample the WTS
profile path will be set to \\testserver\testpath\profile and the working
directory to c:\work\testuser.

 $user{terminalserverprofilepath} = "\\\\testserver\\testpath\\profile";
 $user{workingdirectory} = "c:\\work\\testuser";

 if(!Win32::Lanman::WTSSetUserConfig("\\\\testserver", "testuser", \%user))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item WTSSendMessage($server, $sessionid, $title, $message[, $style [, $timeout [, \$response]]])

Displays a message box with the text "a message to the console" and the caption 
"hi console user" on the console desktop (session id 0) on the WTS \\testserver. 
The message box disappears after 15 seconds or if the user presses the Ok button. 
You can specify a style or 0 for the default (simply an Ok button). The available 
style values you'll find in the MessageBox description in the platform sdk. If you 
pass a response value, the call returns which button the user pressed or if the 
timeout elapsed. If you omit the timeout value or the timeout is null, the function 
returns immediately. Otherwise it returns if the user pressed a button on the 
message box or if the timeout elapsed.

 if(!Win32::Lanman::WTSSendMessage("\\\\testserver", 0, "a message to the console", "hi console user",
				   0, 15, \$response))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

 print $response;

=item WTSDisconnectSession($server, $sessionid [, $wait])

Disconnects the user logged on the desktop window station (session id 0) on
server \\testserver. The session is closed only. The user won't be logged off. 
The calling process waits til the connection is closed ($wait == 1).

 if(!Win32::Lanman::WTSDisconnectSession("\\\\testserver", 0, 1))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item WTSLogoffSession($server, $sessionid [, $wait])

Logs off the user logged on the desktop window station (session id 0) on
server \\testserver. The calling process waits until the user is logged
off ($wait == 1).

 if(!Win32::Lanman::WTSDisconnectSession("\\\\testserver", 0, 1))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=item WTSShutdownSystem($server[, $flag])

Avoid using this call. It's buggy. See the notes above.

=item WTSWaitSystemEvent($server[, $flag])

Waits for the WTS event WTS_EVENT_LOGON (a user logs on) on server \\testserver
and returns as soon as the event occurs. You'll find the available events in
the constants section above (WTS_EVENT_*). You can specify more than
one event type by or'ing them. The $event returns which event occured.

 if(!Win32::Lanman::WTSWaitSystemEvent("\\\\testserver", &WTS_EVENT_LOGON | &WTS_EVENT_LOGOFF, \$event))
 {
	print "Sorry, something went wrong; error: ";
	# get the error code
	print Win32::Lanman::GetLastError();
	exit 1;
 }

=back

=head1 AUTHOR

Jens Helberg <jens.helberg@de.bosch.com>

You can use this module under GNU public licence.

=cut

