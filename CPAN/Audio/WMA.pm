package Audio::WMA;

use strict;
use vars qw($VERSION);

$VERSION = '0.3';

my %guidMapping   = _knownGUIDs();
my %reversedGUIDs = reverse %guidMapping;

my @ValTypeTemplates = ("", "", "V", "V", "", "v");

my $DEBUG	  = 0;

sub new {
	my $class = shift;
	my $file  = shift;

	my $self  = {};

	open(FILE, $file) or do {
		warn "[$file] does not exist or cannot be read: $!";
		return undef;
	};

	binmode FILE;

	bless $self, $class;

	$self->{'filename'}   = $file;
	$self->{'fileHandle'} = \*FILE;
	$self->{'offset'}     = 0;
	$self->{'size'}	      = -s $file;

	$self->_parseWMAHeader();

	delete $self->{'headerData'};

	close  $self->{'fileHandle'};
	delete $self->{'fileHandle'};

	close  FILE;

	return $self;
}

sub setDebug {
	my $self = shift;

	$DEBUG = shift || 0;
}

sub info {
	my $self = shift;
	my $key = shift;

	return $self->{'INFO'} unless $key;
	return $self->{'INFO'}{lc $key};
}

sub comment {
	my $self = shift;
	my $key = shift;

	return $self->{'COMMENTS'} unless $key;
	return $self->{'COMMENTS'}{uc $key};
}

sub _readAndIncrementOffset {
	my $self  = shift;
	my $size  = shift;

	my $value = substr($self->{'headerData'}, $self->{'offset'}, $size);

	$self->{'offset'} += $size;

	return $value;
}

sub _denull {
        my $string = shift;
        $string =~ s/\0//g;
        return $string;
}

sub _parseWMAHeader {
	my $self = shift;

	my $fh		  = $self->{'fileHandle'};

	read($fh, my $headerObjectData, 30) or return -1;

	my $objectId	  = substr($headerObjectData, 0, 16);
	my $objectSize    = unpack('V', substr($headerObjectData, 16, 8) );
	my $headerObjects = unpack('V', substr($headerObjectData, 24, 4));
	my $reserved1     = vec(substr($headerObjectData, 28, 1), 0, 4);
	my $reserved2     = vec(substr($headerObjectData, 29, 1), 0, 4);

	# some sanity checks
	return -1 if ($objectSize > $self->{'size'});
	
	if ($DEBUG) {
		printf("ObjectId: [%s]\n", _byteStringToGUID($objectId));
		print  "objectSize: [$objectSize]\n";
		print  "headerObjects [$headerObjects]\n";
		print  "reserved1 [$reserved1]\n";
		print  "reserved2 [$reserved2]\n";
	}

	read($fh, $self->{'headerData'}, ($objectSize - 30));

	for (my $headerCounter = 0; $headerCounter < $headerObjects; $headerCounter++) {

		my $nextObjectGUID     = $self->_readAndIncrementOffset(16);
		my $nextObjectGUIDText = _byteStringToGUID($nextObjectGUID);
		my $nextObjectSize     = _parse64BitString($self->_readAndIncrementOffset(8));

		my $nextObjectGUIDName = $reversedGUIDs{$nextObjectGUIDText};

		# some sanity checks
		return -1 if (!defined($nextObjectGUIDName));
		return -1 if (!defined $nextObjectSize || $nextObjectSize > $self->{'size'});

		if ($DEBUG) {
			print "nextObjectGUID: [" . $nextObjectGUIDText . "]\n";
			print "nextObjectName: [" . $nextObjectGUIDName . "]\n";
			print "nextObjectSize: [" . $nextObjectSize . "]\n";
		}
        
        	if (defined($nextObjectGUIDName)) {

			# start the different header types parsing              
			if ($nextObjectGUIDName eq 'GETID3_ASF_File_Properties_Object') {
	
				$self->_parseASFFilePropertiesObject();
				next;
			}
	
			if ($nextObjectGUIDName eq 'GETID3_ASF_Content_Description_Object') {
	
				$self->_parseASFContentDescriptionObject();
				next;
			}

			if ($nextObjectGUIDName eq 'GETID3_ASF_Content_Encryption_Object') {

				$self->_parseASFContentEncryptionObject();
				next;
			}
	
			if ($nextObjectGUIDName eq 'GETID3_ASF_Extended_Content_Description_Object') {
	
				$self->_parseASFExtendedContentDescriptionObject();
				next;
			}
		}

		# set our next object size
		$self->{'offset'} += ($nextObjectSize - 16 - 8);
	}

	# pull these out and make them more normalized
	while (my ($k,$v) = each %{$self->{'EXT'}->{'content'}}) {

		my $name = $v->{'name'};

		# this gets both WM/Title and isVBR
		next unless $name =~ s#^(?:WM/|is)##i;

		$self->{'COMMENTS'}->{uc $name} = $v->{'value'} || 0;
	}

	delete $self->{'EXT'};
}

# We can't do anything about DRM'd files.
sub _parseASFContentEncryptionObject {
	my $self = shift;

	$self->{'INFO'}->{'drm'} = 1;
}

sub _parseASFFilePropertiesObject {
	my $self = shift;

	my %info = ();

	$info{'fileid'}			= $self->_readAndIncrementOffset(16);
	$info{'fileid_guid'}		= _byteStringToGUID($info{'fileid'});

	$info{'filesize'}		= _parse64BitString($self->_readAndIncrementOffset(8));

	$info{'creation_date'}		= unpack('V', $self->_readAndIncrementOffset(8));
	$info{'creation_date_unix'}	= _fileTimeToUnixTime($info{'creation_date'});

	$info{'data_packets'}		= unpack('V', $self->_readAndIncrementOffset(8));

	$info{'play_duration'}		= _parse64BitString($self->_readAndIncrementOffset(8));
	$info{'send_duration'}		= _parse64BitString($self->_readAndIncrementOffset(8));
	$info{'preroll'}		= unpack('V', $self->_readAndIncrementOffset(8));
	$info{'playtime_seconds'}	= ($info{'play_duration'} / 10000000)-($info{'preroll'} / 1000);

	$info{'flags_raw'}		= unpack('V', $self->_readAndIncrementOffset(4));

	$info{'flags'}->{'broadcast'}	= ($info{'flags_raw'} & 0x0001) ? 1 : 0;
	$info{'flags'}->{'seekable'}	= ($info{'flags_raw'} & 0x0002) ? 1 : 0;

	$info{'min_packet_size'}	= unpack('V', $self->_readAndIncrementOffset(4));
	$info{'max_packet_size'}	= unpack('V', $self->_readAndIncrementOffset(4));
	$info{'max_bitrate'}		= unpack('V', $self->_readAndIncrementOffset(4));

	$info{'bitrate'}		= int($info{'max_bitrate'} / 1000);

	$self->{'INFO'}			= \%info;
}

sub _parseASFContentDescriptionObject {
	my $self = shift;

	my %desc = ();
	my @keys = qw(TITLE AUTHOR COPYRIGHT DESCRIPTION RATING);

	# populate the lengths of each key
	for my $key (@keys) {
		$desc{"_${key}length"}	= unpack('v', $self->_readAndIncrementOffset(2));
	}

	# now pull the data based on length
	for my $key (@keys) {

		my $lengthKey		= "_${key}length";
		$desc{$key}		= _denull( $self->_readAndIncrementOffset($desc{$lengthKey}) );

		delete $desc{$lengthKey};
	}

	$self->{'COMMENTS'}		= \%desc;
}

sub _parseASFExtendedContentDescriptionObject {
	my $self = shift;

	my %ext  = ();

	$ext{'content_count'} = unpack('v', $self->_readAndIncrementOffset(2));

	for (my $id = 0; $id < $ext{'content_count'}; $id++) {

		$ext{'content'}->{$id}->{'base_offset'}  = $self->{'offset'} + 30;
		$ext{'content'}->{$id}->{'name_length'}  = unpack('v', $self->_readAndIncrementOffset(2));

		$ext{'content'}->{$id}->{'name'}         = _denull( $self->_readAndIncrementOffset(
				$ext{'content'}->{$id}->{'name_length'}
		) );

		$ext{'content'}->{$id}->{'value_type'}   = unpack('v', $self->_readAndIncrementOffset(2));
		$ext{'content'}->{$id}->{'value_length'} = unpack('v', $self->_readAndIncrementOffset(2));

		# Value types from ASF spec:
		# 0 = unicode string
		# 1 = BYTE array
		# 2 = BOOL (32 bit)
		# 3 = DWORD (32 bit)
		# 4 = QWORD (64 bit)
		# 5 = WORD (16 bit)
		my $value = $self->_readAndIncrementOffset( $ext{'content'}->{$id}->{'value_length'} );

		if ($ext{'content'}->{$id}->{'value_type'} <= 1) {

			$ext{'content'}->{$id}->{'value'} = _denull($value);

		} elsif($ext{'content'}->{$id}->{'value_type'} == 4) {

			# Looks like "Q" isn't supported w/ unpack on win32
			$ext{'content'}->{$id}->{'value'} = _parse64BitString($value);

		} else {

			# Value types 0, 1, 3 handled separately
			$ext{'content'}->{$id}->{'value'} = unpack(
				$ValTypeTemplates[ $ext{'content'}->{$id}->{'value_type'} ], $value
			);
		}

		if ($DEBUG) {
			print "Ext Cont Desc: $id";
			print " name  = " . $ext{'content'}->{$id}->{'name'};
			print " value = " . $ext{'content'}->{$id}->{'value'};
			print " type  = " . $ext{'content'}->{$id}->{'value_type'};
			print " value_length = " . $ext{'content'}->{$id}->{'value_length'};
			print "\n";
		}
	}

	$self->{'EXT'} = \%ext;
}

sub _parse64BitString {
	my ($low,$high) = unpack('VV', shift);

	return $high * 2 ** 32 + $low;
}

sub _knownGUIDs {

	my %guidMapping = (

		'GETID3_ASF_Extended_Stream_Properties_Object'		=> '14E6A5CB-C672-4332-8399-A96952065B5A',
		'GETID3_ASF_Padding_Object'				=> '1806D474-CADF-4509-A4BA-9AABCB96AAE8',
		'GETID3_ASF_Payload_Ext_Syst_Pixel_Aspect_Ratio'	=> '1B1EE554-F9EA-4BC8-821A-376B74E4C4B8',
		'GETID3_ASF_Script_Command_Object'			=> '1EFB1A30-0B62-11D0-A39B-00A0C90348F6',
		'GETID3_ASF_No_Error_Correction'			=> '20FB5700-5B55-11CF-A8FD-00805F5C442B',
		'GETID3_ASF_Content_Branding_Object'			=> '2211B3FA-BD23-11D2-B4B7-00A0C955FC6E',
		'GETID3_ASF_Content_Encryption_Object'			=> '2211B3FB-BD23-11D2-B4B7-00A0C955FC6E',
		'GETID3_ASF_Digital_Signature_Object'			=> '2211B3FC-BD23-11D2-B4B7-00A0C955FC6E',
		'GETID3_ASF_Extended_Content_Encryption_Object'		=> '298AE614-2622-4C17-B935-DAE07EE9289C',
		'GETID3_ASF_Simple_Index_Object'			=> '33000890-E5B1-11CF-89F4-00A0C90349CB',
		'GETID3_ASF_Degradable_JPEG_Media'			=> '35907DE0-E415-11CF-A917-00805F5C442B',
		'GETID3_ASF_Payload_Extension_System_Timecode'		=> '399595EC-8667-4E2D-8FDB-98814CE76C1E',
		'GETID3_ASF_Binary_Media'				=> '3AFB65E2-47EF-40F2-AC2C-70A90D71D343',
		'GETID3_ASF_Timecode_Index_Object'			=> '3CB73FD0-0C4A-4803-953D-EDF7B6228F0C',
		'GETID3_ASF_Metadata_Library_Object'			=> '44231C94-9498-49D1-A141-1D134E457054',
		'GETID3_ASF_Reserved_3'					=> '4B1ACBE3-100B-11D0-A39B-00A0C90348F6',
		'GETID3_ASF_Reserved_4'					=> '4CFEDB20-75F6-11CF-9C0F-00A0C90349CB',
		'GETID3_ASF_Command_Media'				=> '59DACFC0-59E6-11D0-A3AC-00A0C90348F6',
		'GETID3_ASF_Header_Extension_Object'			=> '5FBF03B5-A92E-11CF-8EE3-00C00C205365',
		'GETID3_ASF_Media_Object_Index_Parameters_Obj'		=> '6B203BAD-3F11-4E84-ACA8-D7613DE2CFA7',
		'GETID3_ASF_Header_Object'				=> '75B22630-668E-11CF-A6D9-00AA0062CE6C',
		'GETID3_ASF_Content_Description_Object'			=> '75B22633-668E-11CF-A6D9-00AA0062CE6C',
		'GETID3_ASF_Error_Correction_Object'			=> '75B22635-668E-11CF-A6D9-00AA0062CE6C',
		'GETID3_ASF_Data_Object'				=> '75B22636-668E-11CF-A6D9-00AA0062CE6C',
		'GETID3_ASF_Web_Stream_Media_Subtype'			=> '776257D4-C627-41CB-8F81-7AC7FF1C40CC',
		'GETID3_ASF_Stream_Bitrate_Properties_Object'		=> '7BF875CE-468D-11D1-8D82-006097C9A2B2',
		'GETID3_ASF_Language_List_Object'			=> '7C4346A9-EFE0-4BFC-B229-393EDE415C85',
		'GETID3_ASF_Codec_List_Object'				=> '86D15240-311D-11D0-A3A4-00A0C90348F6',
		'GETID3_ASF_Reserved_2'					=> '86D15241-311D-11D0-A3A4-00A0C90348F6',
		'GETID3_ASF_File_Properties_Object'			=> '8CABDCA1-A947-11CF-8EE4-00C00C205365',
		'GETID3_ASF_File_Transfer_Media'			=> '91BD222C-F21C-497A-8B6D-5AA86BFC0185',
		'GETID3_ASF_Advanced_Mutual_Exclusion_Object'		=> 'A08649CF-4775-4670-8A16-6E35357566CD',
		'GETID3_ASF_Bandwidth_Sharing_Object'			=> 'A69609E6-517B-11D2-B6AF-00C04FD908E9',
		'GETID3_ASF_Reserved_1'					=> 'ABD3D211-A9BA-11cf-8EE6-00C00C205365',
		'GETID3_ASF_Bandwidth_Sharing_Exclusive'		=> 'AF6060AA-5197-11D2-B6AF-00C04FD908E9',
		'GETID3_ASF_Bandwidth_Sharing_Partial'			=> 'AF6060AB-5197-11D2-B6AF-00C04FD908E9',
		'GETID3_ASF_JFIF_Media'					=> 'B61BE100-5B4E-11CF-A8FD-00805F5C442B',
		'GETID3_ASF_Stream_Properties_Object'			=> 'B7DC0791-A9B7-11CF-8EE6-00C00C205365',
		'GETID3_ASF_Video_Media'				=> 'BC19EFC0-5B4D-11CF-A8FD-00805F5C442B',
		'GETID3_ASF_Audio_Spread'				=> 'BFC3CD50-618F-11CF-8BB2-00AA00B4E220',
		'GETID3_ASF_Metadata_Object'				=> 'C5F8CBEA-5BAF-4877-8467-AA8C44FA4CCA',
		'GETID3_ASF_Payload_Ext_Syst_Sample_Duration'		=> 'C6BD9450-867F-4907-83A3-C77921B733AD',
		'GETID3_ASF_Group_Mutual_Exclusion_Object'		=> 'D1465A40-5A79-4338-B71B-E36B8FD6C249',
		'GETID3_ASF_Extended_Content_Description_Object'	=> 'D2D0A440-E307-11D2-97F0-00A0C95EA850',
		'GETID3_ASF_Stream_Prioritization_Object'		=> 'D4FED15B-88D3-454F-81F0-ED5C45999E24',
		'GETID3_ASF_Payload_Ext_System_Content_Type'		=> 'D590DC20-07BC-436C-9CF7-F3BBFBF1A4DC',
		'GETID3_ASF_Index_Object'				=> 'D6E229D3-35DA-11D1-9034-00A0C90349BE',
		'GETID3_ASF_Bitrate_Mutual_Exclusion_Object'		=> 'D6E229DC-35DA-11D1-9034-00A0C90349BE',
		'GETID3_ASF_Index_Parameters_Object'			=> 'D6E229DF-35DA-11D1-9034-00A0C90349BE',
		'GETID3_ASF_Mutex_Language'				=> 'D6E22A00-35DA-11D1-9034-00A0C90349BE',
		'GETID3_ASF_Mutex_Bitrate'				=> 'D6E22A01-35DA-11D1-9034-00A0C90349BE',
		'GETID3_ASF_Mutex_Unknown'				=> 'D6E22A02-35DA-11D1-9034-00A0C90349BE',
		'GETID3_ASF_Web_Stream_Format'				=> 'DA1E6B13-8359-4050-B398-388E965BF00C',
		'GETID3_ASF_Payload_Ext_System_File_Name'		=> 'E165EC0E-19ED-45D7-B4A7-25CBD1E28E9B',
		'GETID3_ASF_Marker_Object'				=> 'F487CD01-A951-11CF-8EE6-00C00C205365',
		'GETID3_ASF_Timecode_Index_Parameters_Object'		=> 'F55E496D-9797-4B5D-8C8B-604DFE9BFB24',
		'GETID3_ASF_Audio_Media'				=> 'F8699E40-5B4D-11CF-A8FD-00805F5C442B',
		'GETID3_ASF_Media_Object_Index_Object'			=> 'FEB103F8-12AD-4C64-840F-2A1D2F7AD48C',
		'GETID3_ASF_Alt_Extended_Content_Encryption_Obj'	=> 'FF889EF1-ADEE-40DA-9E71-98704BB928CE',
	);

	return %guidMapping;
}

sub _guidToByteString {
	my $guidString  = shift;

	# Microsoft defines these 16-byte (128-bit) GUIDs as:
	# first 4 bytes are in little-endian order
	# next 2 bytes are appended in little-endian order
	# next 2 bytes are appended in little-endian order
	# next 2 bytes are appended in big-endian order
	# next 6 bytes are appended in big-endian order

	# AaBbCcDd-EeFf-GgHh-IiJj-KkLlMmNnOoPp is stored as this 16-byte string:
	# $Dd $Cc $Bb $Aa $Ff $Ee $Hh $Gg $Ii $Jj $Kk $Ll $Mm $Nn $Oo $Pp

	my $hexByteCharString;

	$hexByteCharString  = chr(hex(substr($guidString,  6, 2)));
	$hexByteCharString .= chr(hex(substr($guidString,  4, 2)));
	$hexByteCharString .= chr(hex(substr($guidString,  2, 2)));
	$hexByteCharString .= chr(hex(substr($guidString,  0, 2)));

	$hexByteCharString .= chr(hex(substr($guidString, 11, 2)));
	$hexByteCharString .= chr(hex(substr($guidString,  9, 2)));

	$hexByteCharString .= chr(hex(substr($guidString, 16, 2)));
	$hexByteCharString .= chr(hex(substr($guidString, 14, 2)));

	$hexByteCharString .= chr(hex(substr($guidString, 19, 2)));
	$hexByteCharString .= chr(hex(substr($guidString, 21, 2)));

	$hexByteCharString .= chr(hex(substr($guidString, 24, 2)));
	$hexByteCharString .= chr(hex(substr($guidString, 26, 2)));
	$hexByteCharString .= chr(hex(substr($guidString, 28, 2)));
	$hexByteCharString .= chr(hex(substr($guidString, 30, 2)));
	$hexByteCharString .= chr(hex(substr($guidString, 32, 2)));
	$hexByteCharString .= chr(hex(substr($guidString, 34, 2)));

	return $hexByteCharString;
}

sub _byteStringToGUID {
	my @byteString	= split //, shift;

	my $guidString;

	# this reverses _guidToByteString.
	$guidString  = sprintf("%02X", ord($byteString[3]));
	$guidString .= sprintf("%02X", ord($byteString[2]));
	$guidString .= sprintf("%02X", ord($byteString[1]));
	$guidString .= sprintf("%02X", ord($byteString[0]));
	$guidString .= '-';
	$guidString .= sprintf("%02X", ord($byteString[5]));
	$guidString .= sprintf("%02X", ord($byteString[4]));
	$guidString .= '-';
	$guidString .= sprintf("%02X", ord($byteString[7]));
	$guidString .= sprintf("%02X", ord($byteString[6]));
	$guidString .= '-';
	$guidString .= sprintf("%02X", ord($byteString[8]));
	$guidString .= sprintf("%02X", ord($byteString[9]));
	$guidString .= '-';
	$guidString .= sprintf("%02X", ord($byteString[10]));
	$guidString .= sprintf("%02X", ord($byteString[11]));
	$guidString .= sprintf("%02X", ord($byteString[12]));
	$guidString .= sprintf("%02X", ord($byteString[13]));
	$guidString .= sprintf("%02X", ord($byteString[14]));
	$guidString .= sprintf("%02X", ord($byteString[15]));

	return uc($guidString);
}

sub _fileTimeToUnixTime {
	my $filetime	= shift;
	my $round	= shift || 1;

	# filetime is a 64-bit unsigned integer representing
	# the number of 100-nanosecond intervals since January 1, 1601
	# UNIX timestamp is number of seconds since January 1, 1970
	# 116444736000000000 = 10000000 * 60 * 60 * 24 * 365 * 369 + 89 leap days
	if ($round) {
		return int(($filetime - 116444736000000000) / 10000000);
	}

	return ($filetime - 116444736000000000) / 10000000;
}

1;

__END__

=head1 NAME

Audio::WMA - Perl extension for reading WMA/ASF Metadata

=head1 SYNOPSIS

	use Audio::WMA;

	my $wma  = Audio::WMA->new($file);

	my $info = $wma->info();

=head1 DESCRIPTION

This module implements access to metadata contained in WMA files.

=head1 SEE ALSO

Audio::FLAC, L<http://getid3.sf.net/>

=head1 AUTHOR

Dan Sully, E<lt>Dan@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Dan Sully

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
