#//////////////////////////////////////////////////////////////////////////////
#//
#//  AdminMisc.pm
#//  Win32::AdminMisc Perl extension package file
#//
#//  This extension provides miscellaneous administrative functions.
#//
#//  Copyright (c) 1996-2002 Dave Roth <rothd@roth.net>
#//  Courtesy of Roth Consulting
#//  http://www.roth.net/
#//
#//  This file may be copied or modified only under the terms of either 
#//  the Artistic License or the GNU General Public License, which may 
#//  be found in the Perl 5.0 source kit.
#//
#//  2003.07.14  :Date
#//  20030714    :Version
#//////////////////////////////////////////////////////////////////////////////

package Win32::AdminMisc;

require Exporter;
require DynaLoader;
use vars qw( $PACKAGE $VERSION );

$PACKAGE = "Win32::AdminMisc";
$VERSION = 20030714;

die "The $PACKAGE module works only on Windows NT/2000/XP/2003" if (!Win32::IsWinNT() );

@ISA= qw( Exporter DynaLoader );
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw(
    LOGON32_LOGON_INTERACTIVE
    LOGON32_LOGON_BATCH
    LOGON32_LOGON_SERVICE
    LOGON32_LOGON_NETWORK

    FILTER_TEMP_DUPLICATE_ACCOUNT
    FILTER_NORMAL_ACCOUNT
    FILTER_INTERDOMAIN_TRUST_ACCOUNT
    FILTER_WORKSTATION_TRUST_ACCOUNT
    FILTER_SERVER_TRUST_ACCOUNT

    UF_TEMP_DUPLICATE_ACCOUNT
    UF_NORMAL_ACCOUNT
    UF_INTERDOMAIN_TRUST_ACCOUNT
    UF_WORKSTATION_TRUST_ACCOUNT
    UF_SERVER_TRUST_ACCOUNT
    UF_MACHINE_ACCOUNT_MASK
    UF_ACCOUNT_TYPE_MASK
    UF_DONT_EXPIRE_PASSWD
    UF_SETTABLE_BITS
    UF_SCRIPT
    UF_ACCOUNTDISABLE
    UF_HOMEDIR_REQUIRED
    UF_LOCKOUT
    UF_PASSWD_NOTREQD
    UF_PASSWD_CANT_CHANGE

    USE_FORCE
    USE_LOTS_OF_FORCE
    USE_NOFORCE

    USER_PRIV_MASK
    USER_PRIV_GUEST
    USER_PRIV_USER
    USER_PRIV_ADMIN

    DRIVE_REMOVABLE
    DRIVE_FIXED
    DRIVE_REMOTE
    DRIVE_CDROM
    DRIVE_RAMDISK

    EWX_LOGOFF
    EWX_FORCE
    EWX_POWEROFF
    EWX_REBOOT
    EWX_SHUTDOWN

    STARTF_USESHOWWINDOW
    STARTF_USEPOSITION
    STARTF_USESIZE
    STARTF_USECOUNTCHARS
    STARTF_USEFILLATTRIBUTE
    STARTF_FORCEONFEEDBACK
    STARTF_FORCEOFFFEEDBACK
    STARTF_USESTDHANDLES

    CREATE_DEFAULT_ERROR_MODE
    CREATE_NEW_CONSOLE
    CREATE_NEW_PROCESS_GROUP
    CREATE_SEPARATE_WOW_VDM
    CREATE_SUSPENDED
    CREATE_UNICODE_ENVIRONMENT
    DEBUG_PROCESS
    DEBUG_ONLY_THIS_PROCESS
    DETACHED_PROCESS;

    HIGH_PRIORITY_CLASS
    IDLE_PRIORITY_CLASS
    NORMAL_PRIORITY_CLASS
    REALTIME_PRIORITY_CLASS

    SW_HIDE
    SW_MAXIMIZE
    SW_MINIMIZE
    SW_RESTORE
    SW_SHOW
    SW_SHOWDEFAULT
    SW_SHOWMAXIMIZED
    SW_SHOWMINIMIZED
    SW_SHOWMINNOACTIVE
    SW_SHOWNA
    SW_SHOWNOACTIVATE
    SW_SHOWNORMAL

    STD_INPUT_HANDLE
    STD_OUTPUT_HANDLE
    STD_ERROR_HANDLE

    FOREGROUND_RED
    FOREGROUND_BLUE
    FOREGROUND_GREEN
    FOREGROUND_INTENSITY
    BACKGROUND_RED
    BACKGROUND_BLUE
    BACKGROUND_GREEN
    BACKGROUND_INTENSITY

    MONDAY
    TUESDAY
    WEDNESDAY
    THURSDAY
    FRIDAY
    SATURDAY
    SUNDAY
    JOB_ADD_CURRENT_DATE
    JOB_RUN_PERIODICALLY
    JOB_EXEC_ERROR
    JOB_RUNS_TODAY
    JOB_NONINTERACTIVE

    ENV_SYSTEM
    ENV_USER

    GROUP_TYPE_ALL
    GROUP_TYPE_LOCAL
    GROUP_TYPE_GLOBAL

    FS_CASE_IS_PRESERVED 
    FS_CASE_SENSITIVE 
    FS_UNICODE_STORED_ON_DISK 
    FS_PERSISTENT_ACLS 
    FS_FILE_COMPRESSION 
    FS_VOL_IS_COMPRESSED

    AF_OP_PRINT
    AF_OP_COMM
    AF_OP_SERVER
    AF_OP_ACCOUNTS

);

# Preloaded methods go here.

sub AUTOLOAD 
{
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.  If a constant is not found then control is passed
    # to the AUTOLOAD in AutoLoader.

    my( $Constant ) = $AUTOLOAD;
    my( $Result, $Value );
    $Constant =~ s/.*:://;

    $Result = GetConstantValue( $Constant, $Value );

    if( 0 == $Result )
    {
        # The extension could not resolve the constant...
        $AutoLoader::AUTOLOAD = $AUTOLOAD;
	    goto &AutoLoader::AUTOLOAD;
        return;
    }
    elsif( 1 == $Result )
    {
        # $Result == 1 if the constant is valid but not defined
        # that is, the extension knows that the constant exists but for
        # some wild reason it was not compiled with it.
        $pack = 0; 
        ($pack,$file,$line) = caller;
        print "Your vendor has not defined $PACKAGE macro $constname, used in $file at line $line.";
    }
    elsif( 2 == $Result )
    {
        # If $Result == 2 then we have a string value
        $Value = "'$Value'";
    }
        # If $Result == 3 then we have a numeric value

    eval "sub $AUTOLOAD { return( $Value ); }";
    goto &$AUTOLOAD;
}

bootstrap $PACKAGE;
return( 1 );

# Autoload methods go after __END__, and are processed by the autosplit program.

__END__


=head1 NAME

Win32::AdminMisc - Miscellanous administrative functions.

=head1 SYNOPSIS

	use Win32::AdminMisc;

=head1 DESCRIPTION

This module provides functionality for general Win32 administration. This module
compliments the other Win32 modules such as Win32::NetAdmin.

=head1 FUNCTIONS

=head2 NOTES

All of the functions return C<FALSE (0)> if they fail, unless otherwise noted.
server is optional for all the calls below. (if not given the local machine is assumed.)

=head2 S<LogonAsUser()>
C<LogonAsUser($Domain, $User, $Password)>

Logs the running process on as $User in $Domain. This requires that the user
account the script runs under have the "C<act as part of the operating system>"
privilege.


=head2 S<UserCreate()>
C<UserCreate(server, userName, password, passwordAge, privilege, homeDir, comment, flags, scriptPath)>

B<NOTHING HERE YET>


=head2 S<GetProcessInfo()>
C<GetProcessInfo( )>

Returns a hash with information pertaining to the running process information:
	

    OEMID             =>  The OEM ID of the microprocessor
    ProcessorNum      =>  Number of microprocessors
    ProcessorType     =>  Type of microprocessor
    ProcessorLevel    =>  Level of microprocessor
    ProcessorRevision =>  Revision of microprocessor
    PageSize          =>  Page size


Returns C<a hash> if successful and C<nothing> is unsuccessful.


=head2 S<GetMemoryInfo()>
C<GetMemoryInfo( )>

Returns a hash with information pertaining to the local computer's memory:


    Load		=>	The current memory load
    RAMTotal	=>	Total amount of physical RAM
    RAMAvail	=>	Available amount of physical RAM
    VirtTotal	=>	Total amount of virtual memory
    VirtAvail	=>	Available amount of virtual memory
    PageTotal	=>	Total amount of paging memory
    PageAvail	=>	Available amount of paging memory


Returns C<a hash> if successful and C<nothing> is unsuccessful.


=head2 S<GetDriveSpace()>
C<GetDriveSpace($Drive)>

Returns an array with drive space information where for $Drive where $Drive
is in the format of C<"C:\">. The array returned is in the form:


	($TotalSize, $TotalFree)


Returns C<an array> if successful and C<nothing> if unsuccessful.


=head2 S<GetDriveGeometry()>
C<GetDriveGeometry($Drive)>

Returns an array of drive geometry information for $Drive where $Drive is in
the format of C<"C:\">.  The returned array contains the following information
in order:


	Sectors per cluster
	Bytes per sector
	Number of free clusters
	Number of total clusters


Returns C<an array> if successful and C<nothing> if unsuccessful.

=head2 S<GetEnvVar()>
C<GetEnvVar( $VarName | \%VarList [, $Type ] )>

Returns either the value of the specified environment variable or the number of
variables if a hash reference is passed.

If a hash reference is passed in then it is populated with the name and value of each 
environment variable.  The return value is a numeric value representing the number of
variables.

An optional second value, C<$Type>, can be included to specify what environment
variable set to examine.  Possible values are:

    ENV_SYSTEM.......The set of system environment variables
    ENV_USER.........The current set of user environment variables

B<Note:>  By default ENV_SYSTEM is assumed.

B<Example:>

    use Win32;
    use Win32::AdminMisc;
    if( $Var = Win32::AdminMisc::GetEnvVar( "windir" ) )
    {
        $WinDir = Win32::ExpandEnvironmentStrings( $Var );
    }

    if( $Var = Win32::AdminMisc::GetEnvVar( "include", ENV_USER ) )
    {
        $IncludePath = Win32::ExpandEnvironmentStrings( $Var );
    }

    if( Win32::AdminMisc::GetEnvVar( \%List, ENV_SYSTEM ) )
    {
        foreach $Var ( keys( %List ) )
        {
            print "$Key = " . Win32::ExpandEnvironmentStrings( $List{$Key} );
        }
    }

Returns C<a string> or C<a numeric value> if successful and C<undef> if unsuccessful.


=head2 S<UserCheckPassword()>
C<UserCheckPassword($Domain, $User, $Password)>

This will verify whether or not $Password is the correct password for
$User on the domain $Domain ($Domain could be a server instead of a domain).

If $Domain is C<Null> ('') then the $User is assumed to be in the current
domain.

If $User is C<Null> ('') then the account to be changed is assumed to be the
account which the perl script is executing under.

Returns C<0> if password is incorrect and C<1> if password is correct.


=head2 S<UserChangePassword()>
C<UserChangePassword($Domain, $User, $OldPassword, $NewPassword)>

This will change the password for the user $User in domain $Domain ($Domain
could be a server instead of a domain) from $OldPassword to $NewPassword.

If $Domain is C<Null> ('') then the $User is assumed to be in the current
domain.

If $User is C<Null> ('') then the account to be changed is assumed to be the
account which the perl script is executing under.


Returns C<0> if password was I<NOT> changed and C<1> if password was changed.


=head2 S<GetLogonName()>
C<GetLogonName( )>

This will return the name of the user this account is logged on as. This is
I<NOT> necessarily the same as the account the perl script is running under.
An account can log on as another user (known as "impersonating" another
account; I<see LogonAsUser()>).

Returns C<the name that the current account is logged in as>.


=head2 S<LogonAsUser()>
C<LogonAsUser($Domain, $User, $Password [, $LogonType])>

This will log the current account on under a different account. The account
to log on under will be in the domain $Domain, user $User with the password
$Password.

If $Domain is C<Null> ('') then the $User is assumed to be in the current
domain.

$LogonType is by default (if not specified) C<LOGON32_LOGON_INTERACTIVE> but
can be any valid logon type:

    LOGON32_LOGON_BATCH
    LOGON32_LOGON_INTERACTIVE
    LOGON32_LOGON_SERVICE
    LOGON32_LOGON_NETWORK


Returns C<0> if unsuccessful and C<1> if successful.


=head2 S<LogoffAsUser()>
C<LogoffAsUser( [ 1 | 0 ])>

This will log the current account out from an "impersonated" account if
the current account is indeed impersonating another account.
If a non C<0> parameter is passed then the the logoff is forced, that is,
you can force the impersonation to end even if LogonAsUser() was not called.

This always returns a C<1>.


=head2 S<CreateProcessAsUser()>
C<CreateProcessAsUser($CommandString [, $DefaultDirectory])>

This creates a new process $CommandString starting in the $DefaultDirectory
(optional). The new process will be running under the account of the
currently impersonated user (L<LogonAsUser()>).

Returns C<-1> if failure otherwise the return is the C<OS createprocess result>.


=head2 S<UserSetAttributes()>
C<UserSetAttributes($Server, $UserName, $UserFullName, $Password, $PasswordAge,
$Privilege, $HomeDir, $Comment, $Flags, $ScriptPath)>

This performs the same function as the original UserSetAttributes()
with the addition that it adds the ability to set the user's Full Name
($UserFullName).

Returns C<0> if unsuccessful and C<1> if successful.


=head2 S<UserGetAttributes()>
C<UserGetAttributes($Server, $UserName, $UserFullName, $Password, $PasswordAge,
$Privilege, $HomeDir, $Comment, $Flags, $ScriptPath)>

This performs the same function as the original UserGetAttributes()
with the addition that it adds the ability to get the user's Full Name
($UserFullName).

Returns C<0> if unsuccessful and C<1> if successful.


=head2 S<GetHostAddress()>
=head2 S<gethostbynames()>
=head2 S<GetHostName()>
=head2 S<gethostbyaddr()>
C<GetHostxxxxx( $DSN_Name | $IP_Address )>

These four functions are the same but go by different names for the sake
of sanity. You can freely mix and match any of these.
Providing either an IP address or a DNS name it will return the opposite
of what you provided or return a C<0> if it fails.

Returns C<0> if unsuccessful and the C<IP address> or C<DNS name> if successful.


=head2 S<DNSCache()>
C<DNSCache( [ 1 | 0 ] )>

Sets the local DNS cache on (C<1>) or off (C<0>). If nothing is specified it
only returns the current state of the DNS cache.

Returns C<0> if the local DNS cache is not active and C<1> if the local DNS
cache is active.


=head2 S<DNSCacheSize()>
C<DNSCacheSize( [$Size] )>

Sets the local DNS cache size to $Size elements (or name/ip associations).
If nothing is specified then it only returns the current size of the cache.

B<NOTE:> If a number is specified then the cache will be reset and every
         thing in it will be lost.

B<NOTE:> The size could be anything. Don't make it too large for memory and
         speed sake.

The default size is 600.

Returns the Current size of the DNS cache.


=item DNSCacheCount()

Returns the current number of cached elements. This can not exceed the
value of DNSCacheSize.

    Returns: Current number of cached elements.


=item UserGetMiscAttributes(C<$Domain, $User, \%Attributes>)

This will return a hash of attributes and values. The attributes are the
attributes associated with the NT User account C<$User> in the domain C<$Domain>.
If <$Domain> is empty then the current domain is assumed.

    Returns: 0 if unsuccessful
             1 if successful
	

=item UserSetMiscAttributes(C<$Domain, $User, $Attrib, $Value [, $Attrib2, $Value2]...>)

This will set a particular attribute C<$Attrib> to be C<$Value> for the NT
user account C<$User> in domain $Domain. If C<$Domain> is empty then the current
domain is assumed.

    Returns: 0 if unsuccessful
             1 if successful

=item GetDrives([C<$Type>])

This will return an array of drive roots. If no parameters are passed
then the list will be all drives (cdroms, floppy, fixed, net, etc.).
If you specify C<$Type> the list will only contain drive roots that are
of the specified type.

    The types are:
         DRIVE_FIXED
         DRIVE_REMOVABLE
         DRIVE_REMOTE
         DRIVE_CDROM
         DRIVE_RAMDISK

    Returns: nothing if unsuccessful
             array if successful

=item GetDriveType(<$Drive>)

This will return an integer relating to a drive type of the root $Drive.
Drives need to be specified as a root such as C<"c:\"> or C<"a:\"> (notice
the need to specify the root directory).

    The types are:
         DRIVE_FIXED
         DRIVE_REMOVABLE
         DRIVE_REMOTE
         DRIVE_CDROM
         DRIVE_RAMDISK

If an error occurs a 0 will be returned and if the type could not be
determined (maybe a a disk is not in the drive) then a 1 will return,
otherwise type drive type will return.

    Returns:
        0 if unsuccessful
        1 if unable to determine
        drive type if successful

=item GetDriveSpace(C<$Drive>)
	This will return an array consisting of the total drive capacity and the
	available space on the drive.
	Drives need to be specified as a root such as "c:\" or "a:\" (notice
	the need to specify the root directory not just the drive letter).
    NOTE: The values returned may not be accurate if you are running on a
    Windows 95 OSR 1 machine due to a bug in the OS. This was fixed with OSR 2.
    If an UNC is used instead of $Drive then it must end with a backslash as
    in:
        \\server\share\

    Returns:
        array ($Total, $Free) if successful
        nothing if unsuccessful

=item GetDriveGeometry(C<$Drive>)

This will return an array consisting of drive information in the following
order:

    Sectors per Cluster
    Bytes per Sector
    Number of free clusters
    Total number of clusters

If an UNC is used instead of C<$Drive> then it must end with a backslash as
in:

    \\server\share\

    Returns:
        array if successful
        nothing if unsuccessful


GetProcessorInfo()
	This will return a hash of processor related information. Returned
	values are:
		OEMID................OEM identifier
		NumOfProcessors......Number of microprocessors installed
		ProcessorType........Type of microprocessor
		ProcessorLevel.......Level of microprocessor (eg. 4=486,
							 5=Pentium [586], 6=Pentium Pro)
		ProcessorRevision....Revision of microprocessor
		PageSize.............Paged memory size (how much memory is paged
							 to disk at one time)
	Returns: nothing if unsuccessful
			 hash if successful

GetMemoryInfo()
	This will return a hash of memory related information.	Returned
	values are:
		Load.................Current load on memory (in percentages)



	Returns: nothing if unsuccessful
			 hash if successful

GetWinVersion()
	This will return a hash of windows versions. Returned values are:
		Major................Major version.
		Minor................Minor version.
							 (Windows version = Major.Minor as
							 in 3.51)
		Build................Build number
		Platform.............Platform of OS (Win32s, Win_95 or Win_NT)
		CSD..................Service Pack number (if any)
	Returns: nothing is unsuccessful
			 hash if successful



WriteINI($File, $Section, $Key, $Value)
    This will write the value $Value to the key $Key in the section $Section
    of the INI file $File.
    If $Value is empty then the key $Key is removed.
    If $Key is empty then all keys are removed from the section $Section.
    If $Section is empty then all sections are removed from the INI file $File.

    returns:
        1 if successful
        undef if unsuccessful


ReadINI($File, $Section, $Key)
    This will return either a scalar containing the value of $Key from the
    $Section section of the INI file $File.
    If $Key is empty then an array is returned containing all of the keys of
    the section $Section.
    If $Section is empty then an array is returned containing all of the
    sections in the INI file $File.

    Returns:
        array if $Section or $Key are empty and the function is successful
        scalar if successful
        nothing if unsuccessful


=head2 S<ExitWindows()>
C<ExitWindows($Flag)>

This will start the exit windows process. $Flag can be one of the following:


    EWX_LOGOFF......Log the user off. Applications will be told to quite so
                    you may be prompted to save files.
    EWX_POWEROFF....Force the system to shutdown and power off. The system
                    must support poweroff. (NT: calling process must have
                    the SE_SHUTDOWN_NAME privilege)
    EWX_REBOOT......Shut down the system and reboot the computer. (NT:
                    calling process must have the SE_SHUTDOWN_NAME
                    privilege)
    EWX_SHUTDOWN....Shut down the system but don't reboot. (NT: calling
                    process must have the SE_SHUTDOWN_NAME privilege)


The following flag can be logically ORed with one of the above flags:

    EWX_FORCE.......Log the user off. Applications will be forced to exit
                    without saving. This is a hostile way to force a
                    log off.

Returns C<non zero value> if successful and C<0> if unsuccessful.


=head2 S<GetIdInfo()>
C<GetIdInfo( )>

This will return an array with the following information (in order):

    Process ID (PID)............The process ID (PID).
    Thread ID (TID).............The Thread ID (TID).
    Priority Class for PID......The priority of the process.
                                    **Currently Broken**
    Thread Priority.............The priority of the thread.
                                    **Currently Broken**
    Command Line................The command line used to start the process.

Returns C<array> if successful.


=head2 S<GetDC()>
C<GetDC()>

This will return a Domain Controler of the domain $Domain. If $Domain is empty
then use default domain is assumed. $Domain can be either an NT domain or an
NT computer.

Example:

    GetDC("ENGINEERING");
    GetDC("\\\\Server1");
    GetDC("//Server1");


Returns C<name of a DC for the sepecified domain> if successful C<undef> if
unsuccessful.


=head2 S<GetPDC()>
C<GetPDC($Domain)>

This will return the Primary Domain Controler of the domain $Domain. If $Domain
is empty then use default domain is assumed. $Domain can be either an NT domain
or an NT computer.

Example:

    GetPDC("ENGINEERING");
    GetPDC("\\\\Server1");
    GetPDC("//Server1");


Returns C<name of the PDC for the sepecified domain> if successful and C<undef>
if unsuccessful.


=head2 S<GetStdHandle()>
C<GetStdHandle($Handle)>

This will return the win32 handle to the standard handle specified in $Handle.

Possible options for $Handle are:


        STD_INPUT_HANDLE
        STD_OUTPUT_HANDLE
        STD_ERROR_HANDLE

Returns C<Win32 handle> if successful and C<undef> if unsuccessful


=head2 S<SetPassword()>
C<SetPassword($Server, $User, $Password)>

This will set the user $User password to $Password. This assumes that the
calling process has administrative rights on the target server/domain.

Limitations on accounts may restrict the setting of passwords, for example,
setting a password to empty ('') may be restricted if blank passwords are
not allowed in the domain.

Returns 1 if successful and 0 if not successful.


===== The following has been updated =====

=head2 S<CreateProcessAsUser()>
C<CreateProcessAsUser($CommandString [, $DefaultDirectory] [, %Config])>

This will create a process that will be running under the account that you are
impersonating with LogonAsUser().


        $CommandString......The full command line of the processes to run.
        $DefaultDirectory...The default directory that the process runs in.
        %Config.............A hash of values that specify a configuration
                            the process is to run with.

The %Config hash can consist of any of the following:


        Title...............The title of the processes window.
        Desktop.............A virtual desktop. Leave this blank if you are not
                            familiar with it. The default is "winsta0\default".
        X...................The X coordinate of the upper left corner of the
                            processes window.
        Y...................The Y corrdinate of the upper left corner of the
                            processes window.
        XSize...............The width of the processes window (in pixels).
        YSize...............The height of the processes window (in pixels).
        XBuffer.............Number of chars the X buffer should be. This
                            applies only to console applications.
        YBuffer.............Number of chars to Y buffer should be. This applies
                            only to console applications.
        Fill................The color to fill the window. This applies only to
                            console applications.
                            Possible values can be logically ORed together:
                                BACKGROUND_RED
                                BACKGROUND_BLUE
                                BACKGROUND_GREEN
                                BACKGROUND_INTENSITY
                                FOREGROUND_RED
                                FOREGROUND_GREEN
                                FOREGROUND_BLUE
                                FOREGROUND_INTENSITY
		Priority............The priority to run the process under. It can 
							use one of the following:
								HIGH_PRIORITY_CLASS
								IDLE_PRIORITY_CLASS
								NORMAL_PRIORITY_CLASS
								REALTIME_PRIORITY_CLASS
		Flags...............Flags specifying process startup options. Some of
							these can be logically ORed together:
									CREATE_DEFAULT_ERROR_MODE
									CREATE_NEW_CONSOLE
									CREATE_NEW_PROCESS_GROUP
									CREATE_SEPARATE_WOW_VDM
									CREATE_SUSPENDED
									CREATE_UNICODE_ENVIRONMENT
									DEBUG_PROCESS
									DEBUG_ONLY_THIS_PROCESS
									DETACHED_PROCESS;
        ShowWindow..........State of the processes window during startup.
                            Possible values:
                                SW_HIDE
                                SW_MAXIMIZE
                                SW_MINIMIZE
                                SW_RESTORE
                                SW_SHOW
                                SW_SHOWDEFAULT
                                SW_SHOWMAXIMIZED
                                SW_SHOWMINIMIZED
                                SW_SHOWMINNOACTIVE
                                SW_SHOWNA
                                SW_SHOWNOACTIVATE
                                SW_SHOWNORMAL
        StdInput
        StdOutput
        StdError............Specifies which handle to use for standard IN, OUT
                            and ERROR. If one of these is specified *ALL MUST*
                            be specified.
                            You can use GetStdHandle() to retrieve the handle
                            for the current standard handle.
        Inherit.............Specifies to inherit file handles.
        Directory...........Specifies a default directory. This is the same
                            attribute as the $DefaultDirectory.

This function requires the calling process to have the following rights
assigned:


        Privilege          Display Name
        ---------------    -----------------------------------
        SeTcbPrivilege     Act as part of the operating system
        SeAssignPrimary    Replace a process level token
        SeIncreaseQuota    Increase quotas


Returns the C<process id (PID)> if successful and C<unde>f if unsuccessful.



=back

=cut










