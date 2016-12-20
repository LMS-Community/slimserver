package Net::Ifconfig::Wrapper;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS @EXPORT_FAIL);

$VERSION = 0.14;

#$^W++;

require Exporter;

@ISA = qw(Exporter);
# Items to export into caller's namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw();

%EXPORT_TAGS = ('Ifconfig' => [qw(Ifconfig)]);

foreach (keys(%EXPORT_TAGS))
        { push(@{$EXPORT_TAGS{'all'}}, @{$EXPORT_TAGS{$_}}); };

$EXPORT_TAGS{'all'}
	and @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

my $DEBUG = 0;

use POSIX;
my ($OsName, $OsVers) = (POSIX::uname())[0,2];

my $Win32_FormatMessage   = undef;
my %Win32API = ();
my %ToLoad = ('iphlpapi' => {'GetAdaptersInfo' => [['P','P'],             'N'],
                             #'GetIpAddrTable'  => [['P','P','I'],         'N'],
                             'AddIPAddress'    => [['N','N','N','P','P'], 'N'],
                             'DeleteIPAddress' => [['N'],                 'N'],
                            },
             );

my $Win32_ERROR_BUFFER_OVERFLOW     = undef;
my $Win32_ERROR_INSUFFICIENT_BUFFER = undef;
my $Win32_NO_ERROR                  = undef;

my $ETHERNET = 'ff:ff:ff:ff:ff:ff';

(($^O eq 'openbsd') &&
 (`/usr/sbin/arp -a 2>&1` =~ m/(?:\A|\n).+\s+at\s+([a-f\d]{1,2}(?:\:[a-f\d]{1,2}){5})\s+static\s*(?:\n|\Z)/i))
	and $ETHERNET = $1;

if (($^O eq 'MSWin32') || ($^O eq 'cygwin'))
	{
	eval 'use Win32::API;
	      use Win32::WinError;
	      
	      Win32::IsWinNT()
	      	or die "Only WinNT (from Win2K) is supported";

	      $Win32_FormatMessage = sub { return Win32::FormatMessage(@_); };
	      $Win32_ERROR_BUFFER_OVERFLOW     = ERROR_BUFFER_OVERFLOW;
	      $Win32_ERROR_INSUFFICIENT_BUFFER = ERROR_INSUFFICIENT_BUFFER;
	      $Win32_NO_ERROR                  = NO_ERROR;

	      foreach my $DLib (keys(%ToLoad))
	      	{
	      	foreach my $Func (keys(%{$ToLoad{$DLib}}))
	      		{
	      		$Win32API{$DLib}{$Func} = Win32::API->new($DLib, $Func, $ToLoad{$DLib}{$Func}->[0], $ToLoad{$DLib}{$Func}->[1])
	      			or die "Cannot import function \'$Func\' from \'$DLib\' DLL: $^E";
	      		};
	      	};
	     ';
	     
	$@ and die $@;
	};

my $MAXLOGIC = 65535;

my %Hex2Mask  = ('00000000' => '0.0.0.0',         '80000000' => '128.0.0.0',
                 'c0000000' => '192.0.0.0',       'e0000000' => '224.0.0.0',
                 'f0000000' => '240.0.0.0',       'f8000000' => '248.0.0.0',
                 'fc000000' => '252.0.0.0',       'fe000000' => '254.0.0.0',
                 'ff000000' => '255.0.0.0',       'ff800000' => '255.128.0.0',
                 'ffc00000' => '255.192.0.0',     'ffe00000' => '255.224.0.0',
                 'fff00000' => '255.240.0.0',     'fff80000' => '255.248.0.0',
                 'fffc0000' => '255.252.0.0',     'fffe0000' => '255.254.0.0',
                 'ffff0000' => '255.255.0.0',     'ffff8000' => '255.255.128.0',
                 'ffffc000' => '255.255.192.0',   'ffffe000' => '255.255.224.0',
                 'fffff000' => '255.255.240.0',   'fffff800' => '255.255.248.0',
                 'fffffc00' => '255.255.252.0',   'fffffe00' => '255.255.254.0',
                 'ffffff00' => '255.255.255.0',   'ffffff80' => '255.255.255.128',
                 'ffffffc0' => '255.255.255.192', 'ffffffe0' => '255.255.255.224',
                 'fffffff0' => '255.255.255.240', 'fffffff8' => '255.255.255.248',
                 'fffffffc' => '255.255.255.252', 'fffffffe' => '255.255.255.254',
                 'ffffffff' => '255.255.255.255',
                );

my $Inet2Logic = undef;
my $Logic2Inet = undef;

my $Name2Index = undef;

my %Ifconfig = ();

my $RunCmd = sub($$)
	{
	my ($CName, $Iface, $Logic, $Addr, $Mask) = @_;

	my $Cmd = (defined($Ifconfig{$CName}{$^O}{$OsName}{$OsVers}{'ifconfig'}) ?
	           $Ifconfig{$CName}{$^O}{$OsName}{$OsVers}{'ifconfig'}          :
	           $Ifconfig{$CName}{$^O}{'ifconfig'}).' 2>&1';

	#print "\n=== RunCmd ===\n\$CName: $CName, \$Iface: $Iface, \$Logic: $Logic, \$Addr: $Addr, \$Mask: $Mask\n";

	$Cmd =~ s{%Iface%}{$Iface}gsex;
	$Cmd =~ s{%Logic%}{$Logic}gsex;
	$Cmd =~ s{%Addr%}{$Addr}gsex;
	$Cmd =~ s{%Mask%}{$Mask}gsex;
	
	my $saveLang = $ENV{'LANG'} || '';
	$ENV{'LANG'} = 'C';
	my @Output   = `$Cmd`;
	$ENV{'LANG'} = $saveLang;

	$@ = "Command '$Cmd', exit code '".(defined($?) ? $? : '!UNDEFINED!')."'".join("\t", @Output);
        
        $? ? return : return \@Output;
	};

my $SolarisList = sub($$$$)
{
    $Inet2Logic = undef;
    $Logic2Inet = undef;
    
    my $Output = &{$RunCmd}('list', '', '', '', '')
	or return;
    
    $Inet2Logic = {};
    $Logic2Inet = {};

    my $Iface = undef;
    my $Logic = undef;
    my $LogUp = undef;
    my $Info  = {};
    foreach (@{$Output})
    {
	if (
	    ($_ =~ m/\A([a-z]+\d+)(?:\:(\d+))?\:\s+flags=[^\<]+\<(?:\w+\,)*(up)?(?:\,\w+)*\>.*\n?\Z/io)
	    ||
	    ($_ =~ m/\A([a-z]+\d+)(?:\:(\d+))?\:\s+flags=[^\<]+\<(?:\w+(?:\,\w+)*)*\>.*\n?\Z/io)
	    )
	{
	    $Iface = $1;
	    $Logic = defined($2) ? $2 : '';
	    $LogUp = 1 && $3;
	    #$Info->{$Iface}{'status'} = ($Info->{$Iface}{'status'} || $LogUp) ? 1 : 0;
	    $Info->{$Iface}{'status'} = $Info->{$Iface}{'status'} || $LogUp;
	}
	elsif (!$Iface)
	{
	    next;
			}
		elsif (
             ($_ =~ m/\A\s+inet\s+(\d{1,3}(?:\.\d{1,3}){3})\s+netmask\s+(?:0x)?([a-f\d]{8})(?:\s.*)?\n?\Z/io)
             ||
             0
            )
			{
			$LogUp
				and $Info->{$Iface}{'inet'}{$1} = $Hex2Mask{$2};
			$Inet2Logic->{$Iface}{$1} = $Logic;
			$Logic2Inet->{$Iface}{$Logic} = $1;
			}
		elsif (($_ =~ m/\A\s+media\:?\s+(ethernet.*)\s*\n?\Z/io) && !$Info->{$Iface}{'ether'})
			{
			$Info->{$Iface}{'ether'} = $ETHERNET;
			if (!$Info->{$Iface}{'media'})
				{$Info->{$Iface}{'media'} = $1; };
			}
		elsif (($_ =~ m/\A\s+supported\s+media\:?\s+(.*)\s*\n?\Z/io) && !$Info->{$Iface}{'media'})
			{
			$Info->{$Iface}{'media'} = $1;
			}
		elsif ($_ =~ m/\A\s+ether\s+([a-f\d]{1,2}(?:\:[a-f\d]{1,2}){5})(?:\s.*)?\n?\Z/io)
			{
			$Info->{$Iface}{'ether'} = $1;
			};
		};

	return $Info;
	};

my $LinuxList = sub($$$$)
	{
	  # warn " DDD start sub LinuxList...\n";
        $Inet2Logic = undef;
        $Logic2Inet = undef;

        my $Output = &{$RunCmd}('list', '', '', '', '')
        	or return;

        $Inet2Logic = {};
        $Logic2Inet = {};

        my $Iface = undef;
        my $Logic = undef;
        my $Info  = {};
	foreach (@{$Output})
	{
	  $DEBUG && warn " DDD looking at line of Output=$_";
	    if (
           ($_ =~ m/\A([a-z0-9]+)(?:\:(\d+))?\s+link\s+encap\:(?:ethernet\s+hwaddr\s+([a-f\d]{1,2}(?:\:[a-f\d]{1,2}){5}))?.*\n?\Z/io)
           ||
           # German locale de_DE.UTF-8
           ($_ =~ m/\A([a-z0-9]+)(?:\:(\d+))?\s+Link\s+encap\:(?:Ethernet\s+Hardware\s+Adresse\s+([a-f\d]{1,2}(?:\:[a-f\d]{1,2}){5}))?.*\n?\Z/io)
          )
	    {
		$Iface = $1;
		$Logic = defined($2) ? $2 : '';
		defined($3)
		    and $Info->{$Iface}{'ether'} = $3;
		$Info->{$Iface}{'status'} = 0;
	    }
	    elsif (
		($_ =~ m/\A([a-z0-9]+)\:\s+flags=\d+<(\w+(?:,\w+)*)*>.*\n?\Z/io)
		)
	    {
		$Iface = $1;
		my $sFlags = $2;
		$DEBUG && warn " DDD   matched 'flags' line, Iface=$Iface, sFlags=$sFlags\n";
		$Info->{$Iface}{'status'} = 1 if ($sFlags =~ m/\bUP\b/);
	    }
	    elsif (!$Iface)
	    {
		next;
	    }
	    elsif (
              ($_ =~ m/\A\s+inet\s+addr\:(\d{1,3}(?:\.\d{1,3}){3})\s+(?:.*\s)?mask\:(\d{1,3}(?:\.\d{1,3}){3}).*\n?\Z/io)
              ||
              ($_ =~ m/\A\s+inet\s+(\d{1,3}(?:\.\d{1,3}){3})\s+netmask\s+(\d{1,3}(?:\.\d{1,3}){3})(?:\s.*)?\n?\Z/io)
              ||
              # German locale de_DE.UTF-8
              ($_ =~ m/\A\s+inet\s+Adresse\:(\d{1,3}(?:\.\d{1,3}){3})\s+(?:.*\s)?Maske\:(\d{1,3}(?:\.\d{1,3}){3}).*\n?\Z/io)
             )
			{
			    my $sIP = $1;
			    my $sNetmask = $2;
			    $DEBUG && warn " DDD   matched 'netmask' line, sIP=$sIP, sNetmask=$sNetmask\n";
			$Info->{$Iface}{'inet'}{$sIP} = $sNetmask;
			$Inet2Logic->{$Iface}{$sIP} = $Logic;
			$Logic2Inet->{$Iface}{$Logic} = $sIP;
			}
		elsif ($_ =~ m/\A\s+ether\s+([a-f0-9]{1,2}(?:\:[a-f0-9]{1,2}){5})(?:\s|\n|\Z)/io)
			{
			$Info->{$Iface}{'ether'} = $1;
			}
		elsif ($_ =~ m/\A\s+up(?:\s+[^\s]+)*\s*\n?\Z/io)
			{
			  $DEBUG && warn " DDD   matched 'up' line\n";
			  $Info->{$Iface}{'status'} = 1;
			};
		};

	return $Info;
	};


my $st_IP_ADDR_STRING =
	['Next'      => 'L',   #struct _IP_ADDR_STRING*
	 'IpAddress' => 'a16', #IP_ADDRESS_STRING
	 'IpMask'    => 'a16', #IP_MASK_STRING
	 'Context'   => 'L'    #DWORD
	];

my $MAX_ADAPTER_NAME_LENGTH        = 256;
my $MAX_ADAPTER_DESCRIPTION_LENGTH = 128;
my $MAX_ADAPTER_ADDRESS_LENGTH     =   8;

my $st_IP_ADAPTER_INFO =
	['Next'                => 'L',                                     #struct _IP_ADAPTER_INFO*
	 'ComboIndex'          => 'L',                                     #DWORD
	 'AdapterName'         => 'a'.($MAX_ADAPTER_NAME_LENGTH+4),        #char[MAX_ADAPTER_NAME_LENGTH + 4]
	 'Description'         => 'a'.($MAX_ADAPTER_DESCRIPTION_LENGTH+4), #char[MAX_ADAPTER_DESCRIPTION_LENGTH + 4]
	 'AddressLength'       => 'L',                                     #UINT
	 'Address'             => 'a'.$MAX_ADAPTER_ADDRESS_LENGTH,         #BYTE[MAX_ADAPTER_ADDRESS_LENGTH]
	 'Index'               => 'L',                                     #DWORD
	 'Type'                => 'L',                                     #UINT
	 'DhcpEnabled'         => 'L',                                     #UINT
	 'CurrentIpAddress'    => 'L',                                     #PIP_ADDR_STRING
	 'IpAddressList'       => $st_IP_ADDR_STRING,                      #IP_ADDR_STRING
	 'GatewayList'         => $st_IP_ADDR_STRING,                      #IP_ADDR_STRING 
	 'DhcpServer'          => $st_IP_ADDR_STRING,                      #IP_ADDR_STRING
	 'HaveWins'            => 'L',                                     #BOOL
	 'PrimaryWinsServer'   => $st_IP_ADDR_STRING,                      #IP_ADDR_STRING
	 'SecondaryWinsServer' => $st_IP_ADDR_STRING,                      #IP_ADDR_STRING
	 'LeaseObtained'       => 'L',                                     #time_t
	 'LeaseExpires'        => 'L',                                     #time_t
	];

#my $st_MIB_IPADDRROW =
#	['dwAddr'       => 'L', #DWORD              
#	 'dwIndex'      => 'L', #DWORD              
#	 'dwMask'       => 'L', #DWORD              
#	 'dwBCastAddr'  => 'L', #DWORD              
#	 'dwReasmSize'  => 'L', #DWORD              
#	 'unused1'      => 'S', #unsigned short     
#	 'unused2'      => 'S', #unsigned short     
#	];

my %UnpackStrCache = ();
my $UnpackStr = undef;
$UnpackStr = sub($$)
	{
	my ($Struct, $Repeat) = @_;
	$Repeat or $Repeat = 1;

	my $StructUpStr = '';

	if (!defined($UnpackStrCache{$Struct}))
		{
		for (my $RI = 1; defined($Struct->[$RI]); $RI += 2)
			{
			$StructUpStr .= ref($Struct->[$RI]) ?
			                   &{$UnpackStr}($Struct->[$RI], 1) :
			                   $Struct->[$RI];
			};
		$UnpackStrCache{$Struct} = $StructUpStr;
		}
	else
		{ $StructUpStr = $UnpackStrCache{$Struct}; };

	my $UpStr = '';
	for (; $Repeat > 0; $Repeat--)
		{ $UpStr .= $StructUpStr; };

	return $UpStr;
	};


my $ShiftStruct = undef;
$ShiftStruct = sub($$)
	{
	my ($Array, $Struct) = @_;

	my $Result = {};
	#tie(%{$Result}, 'Tie::IxHash');

	for (my $RI = 0; defined($Struct->[$RI]); $RI += 2)
		{
		$Result->{$Struct->[$RI]} = ref($Struct->[$RI+1]) ?
		                             &{$ShiftStruct}($Array, $Struct->[$RI+1]) :
		                             shift(@{$Array});
		};
	return $Result;
	};

my $UnpackStruct = sub($$)
	{
	my ($pBuff, $Struct) = @_;

	my $UpStr = &{$UnpackStr}($Struct);

	my @Array = unpack($UpStr, ${$pBuff});

	substr(${$pBuff}, 0, length(pack($UpStr)), '');

	return &{$ShiftStruct}(\@Array, $Struct);
	};


my $if_hwaddr = sub($$)
	{
	my($len, $addr) = @_;
	return join(':', map {sprintf '%02x', $_ } unpack('C' x $len, $addr));
	};

sub if_ipaddr
	{
	my ($addr) = @_;
	return join(".", unpack("C4", pack("L", $addr)));
	};

my $Win32List = sub($$$$)
	{
        $Inet2Logic = undef;
        $Logic2Inet = undef;
        $Name2Index = undef;

	my $Buff = '';
	my $BuffLen = pack('L', 0);

	my $Res = $Win32API{'iphlpapi'}{'GetAdaptersInfo'}->Call(0, $BuffLen);

	while ($Res == $Win32_ERROR_BUFFER_OVERFLOW)
		{
		$Buff = "\0" x unpack("L", $BuffLen);
		$Res = $Win32API{'iphlpapi'}{'GetAdaptersInfo'}->Call($Buff, $BuffLen);
		};

	if ($Res != $Win32_NO_ERROR)
		{
		$! = $Res;
		$@ = "Error running 'GetAdaptersInfo' function: ".&{$Win32_FormatMessage}($Res);
		return;
		};

	my $Info = {};

        $Inet2Logic = {};
        $Logic2Inet = {};
        $Name2Index = {};

	while (1)
		{
		my $ADAPTER_INFO = &{$UnpackStruct}(\$Buff, $st_IP_ADAPTER_INFO);

		foreach my $Field ('AdapterName', 'Description')
			{ $ADAPTER_INFO->{$Field} =~ s/\x00+\Z//o; };

		foreach my $AddrField ('IpAddressList', 'GatewayList', 'DhcpServer', 'PrimaryWinsServer', 'SecondaryWinsServer')
			{
			foreach my $Field ('IpAddress', 'IpMask')
				{ $ADAPTER_INFO->{$AddrField}{$Field} =~ s/\x00+\Z//o; };
			};


	        $ADAPTER_INFO->{'Address'} = &{$if_hwaddr}($ADAPTER_INFO->{'AddressLength'}, $ADAPTER_INFO->{'Address'});

		foreach my $IpList ('IpAddressList', 'GatewayList')
			{
			my $ADDR_STRING = $ADAPTER_INFO->{$IpList};
			$ADAPTER_INFO->{$IpList} = [$ADDR_STRING,];
			while ($ADDR_STRING->{'Next'})
				{
				$ADDR_STRING = &{$UnpackStruct}(\$Buff, $st_IP_ADDR_STRING);
				foreach my $Field ('IpAddress', 'IpMask')
					{ $ADDR_STRING->{$Field} =~ s/\x00+\Z//o; };
				push(@{$ADAPTER_INFO->{$IpList}}, $ADDR_STRING);
				};
			};

		my $Iface = $ADAPTER_INFO->{'AdapterName'};

	        $Info->{$Iface}{'descr'}  = $ADAPTER_INFO->{'Description'};
	        $Info->{$Iface}{'ether'}  = $ADAPTER_INFO->{'Address'};
		$Info->{$Iface}{'status'} = 1;
	        
	        foreach my $Addr (@{$ADAPTER_INFO->{'IpAddressList'}})
	        	{
	        	($Addr->{'IpAddress'} eq '0.0.0.0')
	        		and next;
	        	$Info->{$Iface}{'inet'}{$Addr->{'IpAddress'}} = $Addr->{'IpMask'};
			$Inet2Logic->{$Iface}{$Addr->{'IpAddress'}} = $Addr->{'Context'};
			$Logic2Inet->{$Iface}{$Addr->{'Context'}} = $Addr->{'IpAddress'};
	        	};

	        $Name2Index->{$Iface} = $ADAPTER_INFO->{'Index'};

		$ADAPTER_INFO->{'Next'}
			or last;
		};


	#$Buff = '';
	#$BuffLen = pack('L', 0);
	#$Res = $Win32API{'iphlpapi'}{'GetIpAddrTable'}->Call($Buff, $BuffLen, 0);
	#
	#while ($Res == ERROR_INSUFFICIENT_BUFFER)
	#	{
	#	$Buff = "\0" x unpack("L", $BuffLen);
	#	$Res = $Win32API{'iphlpapi'}{'GetIpAddrTable'}->Call($Buff, $BuffLen, 0);
	#	};
	#
	#if ($Res != $Win32_NO_ERROR)
	#	{
	#	$! = $Res;
	#	$@ = "Error running 'GetIpAddrTable' function: ".&{$Win32_FormatMessage}($Res);
	#	return;
	#	};
	#
	#my $IpAddrTable = &{$UnpackStruct}(\$Buff, ['Len' => 'L']);
	#my %Info1 = ();
	#for (; $IpAddrTable->{'Len'} > 0; $IpAddrTable->{'Len'}--)
	#	{
	#	my $IPADDRROW = &{$UnpackStruct}(\$Buff, $st_MIB_IPADDRROW);
	#	$Info->{$IPADDRROW->{'dwIndex'}}
	#		and next;
	#        $Info1{$IPADDRROW->{'dwIndex'}}{'inet'}{if_ipaddr($IPADDRROW->{'dwAddr'})} = if_ipaddr($IPADDRROW->{'dwMask'});
	#	};
	#
	#foreach my $Iface (keys(%Info1))
	#	{ $Info->{$Iface} = $Info1{$Iface}; };

	return wantarray ? %{$Info} : $Info;
	};



$Ifconfig{'list'} = {'solaris' => {'ifconfig' => 'LC_ALL=C /sbin/ifconfig -a',
                                   'function' => $SolarisList},
                     'openbsd' => {'ifconfig' => 'LC_ALL=C /sbin/ifconfig -A',
                                   'function' => $SolarisList},
                     'linux'   => {'ifconfig' => 'LC_ALL=C /sbin/ifconfig -a',
                                   'function' => $LinuxList},
                     'MSWin32' => {'ifconfig' => '',
                                   'function' => $Win32List,},
                    };

$Ifconfig{'list'}{'freebsd'} = $Ifconfig{'list'}{'solaris'};
$Ifconfig{'list'}{'darwin'}  = $Ifconfig{'list'}{'solaris'};
$Ifconfig{'list'}{'cygwin'}  = $Ifconfig{'list'}{'MSWin32'};


my $UpDown = sub($$$$)
	{
	my ($CName, $Iface, $Addr, $Mask) = @_;

	if (!(defined($Iface) && defined($Addr) && defined($Mask)))
		{
		$@ = "Command '$CName': interface, inet address and netmask have to be defined";
		return;
		};

        my $Output = &{$RunCmd}($CName, $Iface, '', $Addr, $Mask);

        $Inet2Logic = undef;
        $Logic2Inet = undef;

	$Output ? return $Output : return;        
	};

my $UpDownNewLog = sub($$$$)
	{
	my ($CName, $Iface, $Addr, $Mask) = @_;

	if (!(defined($Iface) && defined($Addr) && defined($Mask)))
		{
		$@ = "Command '$CName': interface, inet address and netmask have to be defined";
		return;
		};

	defined($Inet2Logic)
		or (defined($Ifconfig{'list'}{$^O}{$OsName}{$OsVers}{'function'}) ?
	            &{$Ifconfig{'list'}{$^O}{$OsName}{$OsVers}{'function'}}()     :
	            &{$Ifconfig{'list'}{$^O}{'function'}}())
		or return;

	my $Logic = $Inet2Logic->{$Iface}{$Addr};

	my $RunIndex = 1;
	for(; !defined($Logic); $RunIndex++)
		{
		if ($RunIndex > $MAXLOGIC)
			{
			$@ = "Command '$CName': maximum number of logic interfaces ($MAXLOGIC) on interface '$Iface' exceeded";
			return;
			};
		defined($Logic2Inet->{$Iface}{$RunIndex})
			or $Logic = $RunIndex;
		};
        
        my $Output = &{$RunCmd}($CName, $Iface, $Logic, $Addr, $Mask);

        $Inet2Logic = undef;
        $Logic2Inet = undef;

	$Output ? return $Output : return;        
	};

my $UpDownReqLog = sub($$$$)
	{
	my ($CName, $Iface, $Addr, $Mask) = @_;

	if (!(defined($Iface) && defined($Addr) && defined($Mask)))
		{
		$@ = "Command '$CName': interface, inet address and netmask have to be defined";
		return;
		};

	defined($Inet2Logic)
		or (defined($Ifconfig{'list'}{$^O}{$OsName}{$OsVers}{'function'}) ?
	            &{$Ifconfig{'list'}{$^O}{$OsName}{$OsVers}{'function'}}()     :
	            &{$Ifconfig{'list'}{$^O}{'function'}}())
		or return;

	my $Logic = $Inet2Logic->{$Iface}{$Addr};

	if (!defined($Logic))
		{
		$@ = "Command '$CName': can not get logic interface for interface '$Iface', inet address '$Addr'";
		return;
		};
        
        my $Output = &{$RunCmd}($CName, $Iface, $Logic, $Addr, $Mask);

        $Inet2Logic = undef;
        $Logic2Inet = undef;

	$Output ? return $Output : return;        
	};

#my $Win32UpDown = sub($$)
#	{
#	my ($Iface, $State) = @_;
#
#
#	};
#
#my $Win32Inet = sub($$$$)
#	{
#	my ($CName, $Iface, $Addr, $Mask) = @_;
#
#
#	if (!(defined($Iface) && defined($Addr) && defined($Mask)))
#		{
#		$@ = "Command '$CName': interface, inet address and netmask have to be defined";
#		return;
#		};
#
#	$Win32Up($Iface)
#		or return;
#
#	$Win32AddIP($Iface, $Addr, $Mask)
#		or return;
#        my $Output = &{$RunCmd}('inet', '$Iface', '', '$Addr', '$Mask');
#
#        $Inet2Logic = undef;
#        $Logic2Inet = undef;
#
#	$Output ? return $Output : return;        
#	};


my $PackIP = sub($)
	{
	my @Bytes = split('\.', $_[0]);
	return unpack("L", pack('C4', @Bytes));
	};

my $Win32AddAlias = sub($$$$)
	{
	my ($CName, $Iface, $Addr, $Mask) = @_;

	if (!(defined($Iface) && defined($Addr) && defined($Mask)))
		{
		$@ = "Command '$CName': interface, inet address and netmask have to be defined";
		return;
		};

	defined($Inet2Logic)
		or (defined($Ifconfig{'list'}{$^O}{$OsName}{$OsVers}{'function'}) ?
	            &{$Ifconfig{'list'}{$^O}{$OsName}{$OsVers}{'function'}}()     :
	            &{$Ifconfig{'list'}{$^O}{'function'}}())
		or return;

	my $NTEContext  = pack('L', 0);
	my $NTEInstance = pack('L', 0);

	my $Index = $Name2Index->{$Iface};

	if (!defined($Index))
		{
		$@ = "Command '$CName': can not get interface index for interface '$Iface'";
		return;
		};
        
	my $Res = $Win32API{'iphlpapi'}{'AddIPAddress'}->Call(&{$PackIP}($Addr), &{$PackIP}($Mask), $Index, $NTEContext, $NTEInstance);

	if ($Res != $Win32_NO_ERROR)
		{
		$! = $Res;
		$@ = &{$Win32_FormatMessage}($Res)
			or $@ = 'Unknown error :(';
		return;
		};

        $Inet2Logic = undef;
        $Logic2Inet = undef;
	
	return ['Command completed successfully'];
	};

my $Win32RemAlias = sub($$$$)
	{
	my ($CName, $Iface, $Addr, $Mask) = @_;

	if (!(defined($Iface) && defined($Addr) && defined($Mask)))
		{
		$@ = "Command '$CName': interface, inet address and netmask have to be defined";
		return;
		};

	defined($Inet2Logic)
		or (defined($Ifconfig{'list'}{$^O}{$OsName}{$OsVers}{'function'}) ?
	            &{$Ifconfig{'list'}{$^O}{$OsName}{$OsVers}{'function'}}()     :
	            &{$Ifconfig{'list'}{$^O}{'function'}}())
		or return;

	my $Logic = $Inet2Logic->{$Iface}{$Addr};

	if (!defined($Logic))
		{
		$@ = "Command '$CName': can not get logic interface for interface '$Iface', inet address '$Addr'";
		return;
		};
        
	my $Res = $Win32API{'iphlpapi'}{'DeleteIPAddress'}->Call($Logic);

	if ($Res != $Win32_NO_ERROR)
		{
		$! = $Res;
		$@ = &{$Win32_FormatMessage}($Res);
		return;
		};

        $Inet2Logic = undef;
        $Logic2Inet = undef;
	
	return ['Command completed successfully'];
	};


$Ifconfig{'inet'} = {'solaris' => {'ifconfig' => '/sbin/ifconfig %Iface% inet %Addr% netmask %Mask% up',
                                   'function' => $UpDown},
#                     'MSWin32' => {'ifconfig' => '',
#                                   'function' => $Win32Inet,},
                    };
$Ifconfig{'inet'}{'freebsd'} = $Ifconfig{'inet'}{'solaris'};
$Ifconfig{'inet'}{'openbsd'} = $Ifconfig{'inet'}{'solaris'};
$Ifconfig{'inet'}{'linux'}   = $Ifconfig{'inet'}{'solaris'};
$Ifconfig{'inet'}{'darwin'}  = $Ifconfig{'inet'}{'solaris'};
               
$Ifconfig{'up'} = $Ifconfig{'inet'};

$Ifconfig{'down'}{'solaris'} = {'ifconfig' => '/sbin/ifconfig %Iface% down',
                                  'function' => $UpDown,
                                 };
$Ifconfig{'down'}{'freebsd'} = $Ifconfig{'down'}{'solaris'};
$Ifconfig{'down'}{'openbsd'} = $Ifconfig{'down'}{'solaris'};
$Ifconfig{'down'}{'linux'}   = $Ifconfig{'down'}{'solaris'};
$Ifconfig{'down'}{'darwin'}  = $Ifconfig{'down'}{'solaris'};

$Ifconfig{'+alias'} = {'freebsd' => {'ifconfig' => '/sbin/ifconfig %Iface%         inet %Addr% netmask %Mask% alias',
                                     'function' => $UpDown},
                       'solaris' => {'ifconfig' => '/sbin/ifconfig %Iface%:%Logic% inet %Addr% netmask %Mask% up',
                                     'function' => $UpDownNewLog},
                       'MSWin32' => {'ifconfig' => '',
                                     'function' => $Win32AddAlias,},
                      };
$Ifconfig{'+alias'}{'openbsd'} = $Ifconfig{'+alias'}{'freebsd'};
$Ifconfig{'+alias'}{'linux'}   = $Ifconfig{'+alias'}{'solaris'};
$Ifconfig{'+alias'}{'darwin'}  = $Ifconfig{'+alias'}{'freebsd'};

$Ifconfig{'+alias'}{'solaris'}{'SunOS'}{'5.8'}{'ifconfig'}  = '/sbin/ifconfig %Iface%:%Logic% plumb; /sbin/ifconfig %Iface%:%Logic% inet %Addr% netmask %Mask% up';
$Ifconfig{'+alias'}{'solaris'}{'SunOS'}{'5.9'}{'ifconfig'}  = $Ifconfig{'+alias'}{'solaris'}{'SunOS'}{'5.8'}{'ifconfig'};
$Ifconfig{'+alias'}{'solaris'}{'SunOS'}{'5.10'}{'ifconfig'} = $Ifconfig{'+alias'}{'solaris'}{'SunOS'}{'5.8'}{'ifconfig'};

$Ifconfig{'alias'} = $Ifconfig{'+alias'};


$Ifconfig{'-alias'} = {'freebsd' => {'ifconfig' => '/sbin/ifconfig %Iface% inet %Addr% -alias',
                                     'function' => $UpDown},
                       'solaris' => {'ifconfig' => '/sbin/ifconfig %Iface%:%Logic% down',
                                     'function' => $UpDownReqLog},
                       'MSWin32' => {'ifconfig' => '',
                                     'function' => $Win32RemAlias,},
                      };
$Ifconfig{'-alias'}{'openbsd'} = $Ifconfig{'-alias'}{'freebsd'};
$Ifconfig{'-alias'}{'linux'}   = $Ifconfig{'-alias'}{'solaris'};
$Ifconfig{'-alias'}{'darwin'} = $Ifconfig{'-alias'}{'freebsd'};

$Ifconfig{'-alias'}{'solaris'}{'SunOS'}{'5.9'}{'ifconfig'} = '/sbin/ifconfig %Iface%:%Logic% unplumb';

sub Ifconfig
	{
	my ($CName, $Iface, $Addr, $Mask) = @_;
	if (!($CName && $Ifconfig{$CName} && $Ifconfig{$CName}{$^O}))
		{
		$@ = "Command '$CName' is not defined for system '$^O'";
		return;
		};
	
	defined($Inet2Logic)
		or (defined($Ifconfig{'list'}{$^O}{$OsName}{$OsVers}{'function'}) ?
	            &{$Ifconfig{'list'}{$^O}{$OsName}{$OsVers}{'function'}}()     :
	            &{$Ifconfig{'list'}{$^O}{'function'}}())
		or return;

	my $Output = (defined($Ifconfig{$CName}{$^O}{$OsName}{$OsVers}{'function'}) ?
	              &{$Ifconfig{$CName}{$^O}{$OsName}{$OsVers}{'function'}}($CName, $Iface, $Addr, $Mask) :
	              &{$Ifconfig{$CName}{$^O}{'function'}}($CName, $Iface, $Addr, $Mask));

	$Output ? return $Output : return;        
	};

1;

__END__

=head1 NAME

Net::Ifconfig::Wrapper - provides a unified way to configure network interfaces
on FreeBSD, OpenBSD, Solaris, Linux, OS X, and WinNT (from Win2K).

=head1 SYNOPSIS

  use Net::Ifconfig::Wrapper;
  my $rhInfo = Net::Ifconfig::Wrapper::Ifconfig('list');

=head1 DESCRIPTION

This module provides a unified way to configure the network interfaces
on FreeBSD, OpenBSD, Solaris, Linux, OS X, and WinNT (from Win2K) systems.

I<B<Only C<inet> (IPv4) and C<ether> (MAC) addresses are supported at this time>>

On Unix, this module calls the system C<ifconfig> command to gather the information.
On Windows, the functions from IpHlpAPI.DLL are called.

For all supported Unixes, C<Net::Ifconfig::Wrapper> expects the C<ifconfig>
command to be C</sbin/ifconfig>.

See the top-level README file for a list of tested OSes.

I<On the MSWin32 family, only Windows NT is supported.  
In the Windows NT family, only Windows 2000 or later is supported.>

=head1 The Net::Ifconfig::Wrapper methods

=over 4

=item C<Ifconfig(I<Command>, I<Interface>, I<Address>, I<Netmask>);>

The one and only method of the C<Net::Ifconfig::Wrapper> module.  Does all the jobs.
The particular action is described by the C<$Command> parameter.

C<$Command> could be:

=over 8

=item 'list'

C<Ifconfig('list', '', '', '')> will return a reference to a hash
containing information about interfaces.

The structure of this hash is the following:

  {IfaceName => {'status' => 0|1          # The status of the interface. 0 means down, 1 means up
                 'ether'  => MACaddr,     # The ethernet address of the interface if available
                 'descr'  => Description, # The description of the interface if available
                 'inet'   => {IPaddr1 => NetMask, # The IP address and his netmask, both are in AAA.BBB.CCC.DDD notation
                              IPaddr2 => NetMask,
                              ...
                             },
  ...
  };


I<Interface>, I<Address>, I<Netmask> parameters are ignored.

The following shows what program is called for each OS:

=over 12

=item FreeBSD

C</sbin/ifconfig -a>

=item Solaris

C</sbin/ifconfig -a>

=item OpenBSD

C</sbin/ifconfig -A>

=item Linux

C</sbin/ifconfig -a>

=item OS X

C</sbin/ifconfig -a>

=item MSWin32

C<GetAdaptersInfo> function from C<IpHlpAPI.DLL>

=back

Known Limitations:

OpenBSD: C</sbin/ifconfig -A> command is not returning information about MAC addresses
so we are trying to get it from C<'/usr/sbin/arp -a'> command (first I<C<'static'>> entry).
If no one present the I<C<'ff:ff:ff:ff:ff'>> address is returned.

MSWin32: C<GetAdaptersInfo> function is not returning information about the interface
which has address C<127.0.0.1> bound to it,
so we have no way to return it.

Not a limitation, but a small problem: in MSWin32, interface names are not human-readable,
they look like C<{843C2077-30EC-4C56-A401-658BB1E42BC7}> (on Win2K at least).

=item 'inet'

This function is used to set IPv4 address on interface.  It is called as

  Ifconfig('inet', $IfaceName, $Addr, $Mask);

I<C<$IfaceName>> is an interface name as displayed by C<'list'> command

I<C<$Addr>> is an IPv4 address in the C<AAA.AAA.AAA.AAA> notation

I<C<$Mask>> is an IPv4 subnet mask in the C<MMM.MMM.MMM.MMM> notation

In order to accomplish this, the following actual C<ifconfig> programs are called:

=over 12

=item FreeBSD

C</sbin/ifconfig %Iface% inet %Addr% netmask  %Mask% up>

=item Solaris

C</sbin/ifconfig %Iface% inet %Addr% netmask %Mask% up>

=item OpenBSD

C</sbin/ifconfig %Iface% inet %Addr% netmask  %Mask% up>

=item Linux

C</sbin/ifconfig %Iface% inet %Addr% netmask  %Mask% up>

=item OS X

C</sbin/ifconfig %Iface% inet %Addr% netmask  %Mask% up>

=item MSWin32:

nothing :(

=back

Known Limitations:

MSWin32: I did not find a reliable way to recognize the "main" address on the Win32
network interface, so I have disabled this functionality.  If you know how, please let me know.

=item 'up'

Just a synonym for C<'inet'>

=item 'down'

This function is used to bring specified interface down.  It is called as

  Ifconfig('inet', $IfaceName, '', '');

I<C<$IfaceName>> is an interface name as displayed by C<'list'> command

Last two arguments are ignored.

In order to accomplish this, the following programs are called:

=over 12

=item FreeBSD

C</sbin/ifconfig %Iface% down>

=item Solaris

C</sbin/ifconfig %Iface% down>

=item OpenBSD

C</sbin/ifconfig %Iface% down>

=item Linux

C</sbin/ifconfig %Iface% down>

=item OS X

C</sbin/ifconfig %Iface% down>

=item MSWin32

Sorry, this function is not possible.

=back

Known Limitations:

MSWin32: I did not find the way to implement the C<'up'> command so I did not implement C<'down'>.

=item '+alias'

This function is used to set IPv4 alias address on interface. It have to be called as

  Ifconfig('+alias', $IfaceName, $Addr, $Mask);

I<C<$IfaceName>> is an interface name as displayed by C<'list'> command

I<C<$Addr>> is an IPv4 address in the C<AAA.AAA.AAA.AAA> notation

I<C<$Mask>> is an IPv4 subnet mask in the C<MMM.MMM.MMM.MMM> notation

In order to accomplish this, the following C<ifconfig> programs are called:

=over 12

=item FreeBSD

C</sbin/ifconfig %Iface%         inet %Addr% netmask  %Mask% alias>

=item Solaris

C</sbin/ifconfig %Iface%:%Logic% inet %Addr% netmask %Mask% up>

=item OpenBSD

C</sbin/ifconfig %Iface%         inet %Addr% netmask  %Mask% alias>

=item Linux

C</sbin/ifconfig %Iface%:%Logic% inet %Addr% netmask  %Mask% up>

=item OS X

C</sbin/ifconfig %Iface%         inet %Addr% netmask  %Mask% alias>

=item MSWin32

C<AddIPAddress> function from C<IpHlpAPI.DLL>

=back

I<First available logic interface is taken automatically for Solaris and Linux>

=item 'alias'

Just a synonim for C<'+alias'>

=item '-alias'

This function is used to remove IPv4 alias address from interface. It have to be called as

  Ifconfig('-alias', $IfaceName, $Addr, '');

I<C<$IfaceName>> is an interface name as displayed by C<'list'> command.

I<C<$Addr>> is an IPv4 address in the C<AAA.AAA.AAA.AAA> notation.

Last argument is ignored if present.

In order to accomplish this, the following C<ifconfig> programs are called:

=over 12

=item FreeBSD

C</sbin/ifconfig %Iface% inet %Addr% -alias>

=item Solaris

C</sbin/ifconfig %Iface%:%Logic% down>

=item OpenBSD

C</sbin/ifconfig %Iface% inet %Addr% -alias>

=item Linux

C</sbin/ifconfig %Iface%:%Logic% down>

=item OS X

C</sbin/ifconfig %Iface% inet %Addr% -alias>

=item MSWin32

C<DeleteIPAddress> function from C<IpHlpAPI.DLL>

=back

I<Appropriate logic interface is obtained automatically for Solaris and Linux>

=back

On success, the C<Ifconfig(...)> function returns the defined value.
Actually, it is a reference to the array containing the output
of the actual I<C<ifconfig>> program called.

In case of error, C<Ifconfig(...)> returns C<'undef'> value,
and the C<$@> variable contains the error message.

=back

=head2 EXPORT

None by default.

=head1 AUTHOR

Daniel Podolsky, E<lt>tpaba@cpan.orgE<gt>
As of 2015-11, maintained by Martin Thurn E<lt>mthurn@cpan.orgE<gt>

=head1 SEE ALSO

L<ifconfig>(8), I<Internet Protocol Helper> in I<Platform SDK>.

=cut
