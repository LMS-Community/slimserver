package Audio::WMA;

use strict;
use vars qw($VERSION);

# WMA stores tags in UTF-16LE by default.
my $utf8 = 0;

# Minimum requirements
if ($] > 5.007) {
	require Encode;
}

$VERSION = '0.6';

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

sub setConvertTagsToUTF8 {   
	my $class = shift;
	my $val   = shift;

	$utf8 = $val if (($val == 0) || ($val == 1));

	return $utf8;
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

sub tags {
	my $self = shift;
	my $key = shift;

	return $self->{'TAGS'} unless $key;
	return $self->{'TAGS'}{uc $key};
}

sub _readAndIncrementOffset {
	my $self  = shift;
	my $size  = shift;

	my $value = substr($self->{'headerData'}, $self->{'offset'}, $size);

	$self->{'offset'} += $size;

	return $value;
}

sub _readAndIncrementInlineOffset {
	my $self  = shift;
	my $size  = shift;

	my $value = substr($self->{'inlineData'}, $self->{'inlineOffset'}, $size);

	$self->{'inlineOffset'} += $size;

	return $value;
}

sub _UTF16ToUTF8 {
	my $data = shift;

	if ($utf8) {

		# This also turns on the utf8 flag - perldoc Encode
		$data = Encode::decode('UTF-16LE', $data);

	} elsif ($] > 5.007) {

		# otherwise try and turn it into ISO-8859-1 if we have Encode
		$data = Encode::encode('latin1', $data);
	}

	return _denull($data);
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
		print  "\tobjectSize: [$objectSize]\n";
		print  "\theaderObjects [$headerObjects]\n";
		print  "\treserved1 [$reserved1]\n";
		print  "\treserved2 [$reserved2]\n\n";
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
			print "\n";
		}
        
        	if (defined($nextObjectGUIDName)) {

			# start the different header types parsing              
			if ($nextObjectGUIDName eq 'ASF_File_Properties_Object') {
	
				$self->_parseASFFilePropertiesObject();
				next;
			}
	
			if ($nextObjectGUIDName eq 'ASF_Content_Description_Object') {
	
				$self->_parseASFContentDescriptionObject();
				next;
			}

			if ($nextObjectGUIDName eq 'ASF_Content_Encryption_Object' ||
			    $nextObjectGUIDName eq 'ASF_Extended_Content_Encryption_Object') {

				$self->_parseASFContentEncryptionObject();
				next;
			}
	
			if ($nextObjectGUIDName eq 'ASF_Extended_Content_Description_Object') {
	
				$self->_parseASFExtendedContentDescriptionObject();
				next;
			}

			if ($nextObjectGUIDName eq 'ASF_Stream_Properties_Object') {

				$self->_parseASFStreamPropertiesObject();
				next;
			}

			if ($nextObjectGUIDName eq 'ASF_Header_Extension_Object') {

				$self->_parseASFHeaderExtensionObject();
				next;
			}
		}

		# set our next object size
		$self->{'offset'} += ($nextObjectSize - 16 - 8);
	}

	# Now work on the subtypes.
	for my $stream (@{$self->{'STREAM'}}) {

		if ($reversedGUIDs{ $stream->{'stream_type_guid'} } eq 'ASF_Audio_Media') {

			my $audio = $self->_parseASFAudioMediaObject($stream);

			for my $item (qw(bits_per_sample channels sample_rate)) {

				$self->{'INFO'}->{$item} = $audio->{$item};
			}
		}
	}

	# pull these out and make them more normalized
	for my $ext (@{$self->{'EXT'}}) {

		while (my ($k,$v) = each %{$ext->{'content'}}) {

			# this gets both WM/Title and isVBR
			next unless $v->{'name'} =~ s#^(?:WM/|is)##i || $v->{'name'} =~ /^Author/;

			my $name = uc($v->{'name'});

			# Append onto an existing item, semicolon separated.
			if (exists $self->{'TAGS'}->{$name}) {

				$self->{'TAGS'}->{$name} .= sprintf('; %s', ($v->{'value'} || 0));

			} else {

				$self->{'TAGS'}->{$name} = $v->{'value'} || 0;
			}
		}
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

		my $lengthKey  = "_${key}length";
		$desc{$key} = _UTF16ToUTF8($self->_readAndIncrementOffset($desc{$lengthKey}));

		delete $desc{$lengthKey};
	}

	$self->{'TAGS'}	= \%desc;
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
			printf "\tname  = %s\n", $ext{'content'}->{$id}->{'name'};
			printf "\tvalue = %s\n", $ext{'content'}->{$id}->{'value'};
			printf "\ttype  = %s\n", $ext{'content'}->{$id}->{'value_type'};
			printf "\tvalue_length = %s\n", $ext{'content'}->{$id}->{'value_length'};
			print "\n";
		}
	}

	push @{$self->{'EXT'}}, \%ext;
}

sub _parseASFStreamPropertiesObject {
	my $self = shift;

	my %ext  = ();
	my %stream  = ();
	my $streamNumber;

	# Stream Properties Object: (mandatory, one per media stream)
	# Field Name                   Field Type   Size (bits)
	# Object ID                    GUID         128             GUID for stream properties object - ASF_Stream_Properties_Object
	# Object Size                  QWORD        64              size of stream properties object, including 78 bytes of 
	# 							    Stream Properties Object header
	# Stream Type                  GUID         128             ASF_Audio_Media, ASF_Video_Media or ASF_Command_Media
	# Error Correction Type        GUID         128             ASF_Audio_Spread for audio-only streams, 
	# 							     ASF_No_Error_Correction for other stream types
	# Time Offset                  QWORD        64              100-nanosecond units. typically zero. added to all 
	# 							    timestamps of samples in the stream
	# Type-Specific Data Length    DWORD        32              number of bytes for Type-Specific Data field
	# Error Correction Data Length DWORD        32              number of bytes for Error Correction Data field
	# Flags                        WORD         16              
	# * Stream Number              bits         7 (0x007F)      number of this stream.  1 <= valid <= 127
	# * Reserved                   bits         8 (0x7F80)      reserved - set to zero
	# * Encrypted Content Flag     bits         1 (0x8000)      stream contents encrypted if set
	# Reserved                     DWORD        32              reserved - set to zero
	# Type-Specific Data           BYTESTREAM   variable        type-specific format data, depending on value of Stream Type
	# Error Correction Data        BYTESTREAM   variable        error-correction-specific format data, depending on 
	# 							    value of Error Correct Type
	#
	# There is one ASF_Stream_Properties_Object for each stream (audio, video) but the
	# stream number isn't known until halfway through decoding the structure, hence it
	# it is decoded to a temporary variable and then stuck in the appropriate index later

	$stream{'stream_type'}	      = $self->_readAndIncrementOffset(16);
	$stream{'stream_type_guid'}   = _byteStringToGUID($stream{'stream_type'});
	$stream{'error_correct_type'} = $self->_readAndIncrementOffset(16);
	$stream{'error_correct_guid'} = _byteStringToGUID($stream{'error_correct_type'});

	$stream{'time_offset'}        = unpack('v', $self->_readAndIncrementOffset(8));
	$stream{'type_data_length'}   = unpack('v', $self->_readAndIncrementOffset(4));
	$stream{'error_data_length'}  = unpack('v', $self->_readAndIncrementOffset(4));
	$stream{'flags_raw'}          = unpack('v', $self->_readAndIncrementOffset(2));
	$streamNumber                 = $stream{'flags_raw'} & 0x007F;
	$stream{'flags'}{'encrypted'} = ($stream{'flags_raw'} & 0x8000);

	# Skip the DWORD
	$self->_readAndIncrementOffset(4);

	$stream{'type_specific_data'} = $self->_readAndIncrementOffset($stream{'type_data_length'});
	$stream{'error_correct_data'} = $self->_readAndIncrementOffset($stream{'error_data_length'});

	push @{$self->{'STREAM'}}, \%stream;
}

sub _parseASFAudioMediaObject {
	my $self   = shift;
	my $stream = shift;

	# Field Name                   Field Type   Size (bits)
	# Codec ID / Format Tag        WORD         16              unique ID of audio codec - defined as wFormatTag 
	# 							      field of WAVEFORMATEX structure
	#
	# Number of Channels           WORD         16              number of channels of audio - defined as nChannels 
	# 							    field of WAVEFORMATEX structure
	#
	# Samples Per Second           DWORD        32              in Hertz - defined as nSamplesPerSec field 
	# 							    of WAVEFORMATEX structure
	#
	# Average number of Bytes/sec  DWORD        32              bytes/sec of audio stream  - defined as 
	# 							    nAvgBytesPerSec field of WAVEFORMATEX structure
	#
	# Block Alignment              WORD         16              block size in bytes of audio codec - defined 
	# 							    as nBlockAlign field of WAVEFORMATEX structure
	#
	# Bits per sample              WORD         16              bits per sample of mono data. set to zero for 
	# 							    variable bitrate codecs. defined as wBitsPerSample 
	# 							    field of WAVEFORMATEX structure
	#
	# Codec Specific Data Size     WORD         16              size in bytes of Codec Specific Data buffer - 
	# 							    defined as cbSize field of WAVEFORMATEX structure
	#
	# Codec Specific Data          BYTESTREAM   variable        array of codec-specific data bytes

	$stream->{'audio'} = $self->_parseWavFormat(substr($stream->{'type_specific_data'}, 0, 16));

	return $stream->{'audio'};
}

sub _parseWavFormat {
	my $self = shift;
	my $data = shift;

	my %wav  = ();

	#$wav{'codec'}          = RIFFwFormatTagLookup(unpack('v', substr($data,  0, 2));
	$wav{'channels'}        = unpack('v', substr($data,  2, 2));
	$wav{'sample_rate'}     = unpack('v', substr($data,  4, 4));
	$wav{'bitrate'}         = unpack('v', substr($data,  8, 4)) * 8;
	$wav{'bits_per_sample'} = unpack('v', substr($data, 14, 2));

	return \%wav;
}

sub _parseASFHeaderExtensionObject {
	my $self = shift;

	my %ext = ();

	$ext{'reserved_1'}          = _byteStringToGUID($self->_readAndIncrementOffset(16));
	$ext{'reserved_2'}	    = unpack('v', $self->_readAndIncrementOffset(2));

	$ext{'extension_data_size'} = unpack('V', $self->_readAndIncrementOffset(4));
	$ext{'extension_data'}      = $self->_readAndIncrementOffset($ext{'extension_data_size'});

	# Set these so we can use a convience method.
	$self->{'inlineData'}       = $ext{'extension_data'};
	$self->{'inlineOffset'}     = 0;

	if ($DEBUG) {
		print "Working on an ASF_Header_Extension_Object:\n\n";
	}

	while ($self->{'inlineOffset'} < $ext{'extension_data_size'}) {

		my $nextObjectGUID = _byteStringToGUID($self->_readAndIncrementInlineOffset(16)) || last;
		my $nextObjectName = $reversedGUIDs{$nextObjectGUID} || 'ASF_Unknown_Object';
		my $nextObjectSize = unpack('v', $self->_readAndIncrementInlineOffset(8));

		if ($DEBUG) {
			print "\tnextObjectGUID: [$nextObjectGUID]\n";
			print "\tnextObjectName: [$nextObjectName]\n";
			print "\tnextObjectSize: [$nextObjectSize]\n";
			print "\n";
		}
        
		# We only handle this object type for now.
        	if (defined $nextObjectName && $nextObjectName eq 'ASF_Metadata_Library_Object') {

			my $content_count = unpack('v', $self->_readAndIncrementInlineOffset(2));

			# Language List Index	WORD    16
			# Stream Number   	WORD    16
			# Name Length     	WORD    16
			# Data Type       	WORD    16
			# Data Length     	DWORD   32
			# Name    		WCHAR   varies
			# Data    		See below       varies
			for (my $id = 0; $id < $content_count; $id++) {

				my $language_list = unpack('v', $self->_readAndIncrementInlineOffset(2));
				my $stream_number = unpack('v', $self->_readAndIncrementInlineOffset(2));
				my $name_length   = unpack('v', $self->_readAndIncrementInlineOffset(2));
				my $data_type     = unpack('v', $self->_readAndIncrementInlineOffset(2));
				my $data_length   = unpack('V', $self->_readAndIncrementInlineOffset(4));
				my $name          = _denull($self->_readAndIncrementInlineOffset($name_length));

                                # 0x0000 Unicode string. The data consists of a sequence of Unicode characters.
                                #
                                # 0x0001 BYTE array. The type of the data is implementation-specific.
                                #
                                # 0x0002 BOOL. The data is 2 bytes long and should be interpreted as a
                                #        16-bit unsigned integer. Only 0x0000 or 0x0001 are permitted values.
                                #
                                # 0x0003 DWORD. The data is 4 bytes long - 32-bit unsigned integer.
                                #
                                # 0x0004 QWORD. The data is 8 bytes long - 64-bit unsigned integer.
                                #
                                # 0x0005 WORD. The data is 2 bytes long - 16-bit unsigned integer.
                                #
                                # 0x0006 GUID. The data is 16 bytes long - 128-bit GUID.
				my $value;

				if ($data_type == 6) {

					$value = _byteStringToGUID($self->_readAndIncrementInlineOffset($data_length));

				} elsif ($data_type == 0) {

					$value = _UTF16ToUTF8($self->_readAndIncrementInlineOffset($data_length));
				}

				$ext{'content'}->{$id}->{'name'}  = $name;
				$ext{'content'}->{$id}->{'value'} = $value;

				if ($DEBUG) {
					print "\tASF_Metadata_Library_Object: $id\n";
					print "\t\tname  = $name\n";
					print "\t\tvalue = $value\n";
					print "\t\ttype  = $data_type\n";
					print "\t\tdata_length = $data_length\n";
					print "\n";
				}
			}
		}

		$self->{'inlineOffset'} += ($nextObjectSize - 16 - 8);
	}

	delete $ext{'extension_data'};
	delete $self->{'inlineData'};
	delete $self->{'inlineOffset'};

	push @{$self->{'EXT'}}, \%ext;
}

sub _parse64BitString {
	my ($low,$high) = unpack('VV', shift);

	return $high * 2 ** 32 + $low;
}

sub _knownGUIDs {

	my %guidMapping = (

		'ASF_Extended_Stream_Properties_Object'		=> '14E6A5CB-C672-4332-8399-A96952065B5A',
		'ASF_Padding_Object'				=> '1806D474-CADF-4509-A4BA-9AABCB96AAE8',
		'ASF_Payload_Ext_Syst_Pixel_Aspect_Ratio'	=> '1B1EE554-F9EA-4BC8-821A-376B74E4C4B8',
		'ASF_Script_Command_Object'			=> '1EFB1A30-0B62-11D0-A39B-00A0C90348F6',
		'ASF_No_Error_Correction'			=> '20FB5700-5B55-11CF-A8FD-00805F5C442B',
		'ASF_Content_Branding_Object'			=> '2211B3FA-BD23-11D2-B4B7-00A0C955FC6E',
		'ASF_Content_Encryption_Object'			=> '2211B3FB-BD23-11D2-B4B7-00A0C955FC6E',
		'ASF_Digital_Signature_Object'			=> '2211B3FC-BD23-11D2-B4B7-00A0C955FC6E',
		'ASF_Extended_Content_Encryption_Object'	=> '298AE614-2622-4C17-B935-DAE07EE9289C',
		'ASF_Simple_Index_Object'			=> '33000890-E5B1-11CF-89F4-00A0C90349CB',
		'ASF_Degradable_JPEG_Media'			=> '35907DE0-E415-11CF-A917-00805F5C442B',
		'ASF_Payload_Extension_System_Timecode'		=> '399595EC-8667-4E2D-8FDB-98814CE76C1E',
		'ASF_Binary_Media'				=> '3AFB65E2-47EF-40F2-AC2C-70A90D71D343',
		'ASF_Timecode_Index_Object'			=> '3CB73FD0-0C4A-4803-953D-EDF7B6228F0C',
		'ASF_Metadata_Library_Object'			=> '44231C94-9498-49D1-A141-1D134E457054',
		'ASF_Reserved_3'				=> '4B1ACBE3-100B-11D0-A39B-00A0C90348F6',
		'ASF_Reserved_4'				=> '4CFEDB20-75F6-11CF-9C0F-00A0C90349CB',
		'ASF_Command_Media'				=> '59DACFC0-59E6-11D0-A3AC-00A0C90348F6',
		'ASF_Header_Extension_Object'			=> '5FBF03B5-A92E-11CF-8EE3-00C00C205365',
		'ASF_Media_Object_Index_Parameters_Obj'		=> '6B203BAD-3F11-4E84-ACA8-D7613DE2CFA7',
		'ASF_Header_Object'				=> '75B22630-668E-11CF-A6D9-00AA0062CE6C',
		'ASF_Content_Description_Object'		=> '75B22633-668E-11CF-A6D9-00AA0062CE6C',
		'ASF_Error_Correction_Object'			=> '75B22635-668E-11CF-A6D9-00AA0062CE6C',
		'ASF_Data_Object'				=> '75B22636-668E-11CF-A6D9-00AA0062CE6C',
		'ASF_Web_Stream_Media_Subtype'			=> '776257D4-C627-41CB-8F81-7AC7FF1C40CC',
		'ASF_Stream_Bitrate_Properties_Object'		=> '7BF875CE-468D-11D1-8D82-006097C9A2B2',
		'ASF_Language_List_Object'			=> '7C4346A9-EFE0-4BFC-B229-393EDE415C85',
		'ASF_Codec_List_Object'				=> '86D15240-311D-11D0-A3A4-00A0C90348F6',
		'ASF_Reserved_2'				=> '86D15241-311D-11D0-A3A4-00A0C90348F6',
		'ASF_File_Properties_Object'			=> '8CABDCA1-A947-11CF-8EE4-00C00C205365',
		'ASF_File_Transfer_Media'			=> '91BD222C-F21C-497A-8B6D-5AA86BFC0185',
		'ASF_Advanced_Mutual_Exclusion_Object'		=> 'A08649CF-4775-4670-8A16-6E35357566CD',
		'ASF_Bandwidth_Sharing_Object'			=> 'A69609E6-517B-11D2-B6AF-00C04FD908E9',
		'ASF_Reserved_1'				=> 'ABD3D211-A9BA-11cf-8EE6-00C00C205365',
		'ASF_Bandwidth_Sharing_Exclusive'		=> 'AF6060AA-5197-11D2-B6AF-00C04FD908E9',
		'ASF_Bandwidth_Sharing_Partial'			=> 'AF6060AB-5197-11D2-B6AF-00C04FD908E9',
		'ASF_JFIF_Media'				=> 'B61BE100-5B4E-11CF-A8FD-00805F5C442B',
		'ASF_Stream_Properties_Object'			=> 'B7DC0791-A9B7-11CF-8EE6-00C00C205365',
		'ASF_Video_Media'				=> 'BC19EFC0-5B4D-11CF-A8FD-00805F5C442B',
		'ASF_Audio_Spread'				=> 'BFC3CD50-618F-11CF-8BB2-00AA00B4E220',
		'ASF_Metadata_Object'				=> 'C5F8CBEA-5BAF-4877-8467-AA8C44FA4CCA',
		'ASF_Payload_Ext_Syst_Sample_Duration'		=> 'C6BD9450-867F-4907-83A3-C77921B733AD',
		'ASF_Group_Mutual_Exclusion_Object'		=> 'D1465A40-5A79-4338-B71B-E36B8FD6C249',
		'ASF_Extended_Content_Description_Object'	=> 'D2D0A440-E307-11D2-97F0-00A0C95EA850',
		'ASF_Stream_Prioritization_Object'		=> 'D4FED15B-88D3-454F-81F0-ED5C45999E24',
		'ASF_Payload_Ext_System_Content_Type'		=> 'D590DC20-07BC-436C-9CF7-F3BBFBF1A4DC',
		'ASF_Index_Object'				=> 'D6E229D3-35DA-11D1-9034-00A0C90349BE',
		'ASF_Bitrate_Mutual_Exclusion_Object'		=> 'D6E229DC-35DA-11D1-9034-00A0C90349BE',
		'ASF_Index_Parameters_Object'			=> 'D6E229DF-35DA-11D1-9034-00A0C90349BE',
		'ASF_Mutex_Language'				=> 'D6E22A00-35DA-11D1-9034-00A0C90349BE',
		'ASF_Mutex_Bitrate'				=> 'D6E22A01-35DA-11D1-9034-00A0C90349BE',
		'ASF_Mutex_Unknown'				=> 'D6E22A02-35DA-11D1-9034-00A0C90349BE',
		'ASF_Web_Stream_Format'				=> 'DA1E6B13-8359-4050-B398-388E965BF00C',
		'ASF_Payload_Ext_System_File_Name'		=> 'E165EC0E-19ED-45D7-B4A7-25CBD1E28E9B',
		'ASF_Marker_Object'				=> 'F487CD01-A951-11CF-8EE6-00C00C205365',
		'ASF_Timecode_Index_Parameters_Object'		=> 'F55E496D-9797-4B5D-8C8B-604DFE9BFB24',
		'ASF_Audio_Media'				=> 'F8699E40-5B4D-11CF-A8FD-00805F5C442B',
		'ASF_Media_Object_Index_Object'			=> 'FEB103F8-12AD-4C64-840F-2A1D2F7AD48C',
		'ASF_Alt_Extended_Content_Encryption_Obj'	=> 'FF889EF1-ADEE-40DA-9E71-98704BB928CE',
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

	foreach (keys %$info) {
                print "$_: $info->{$_}\n";
        }

	my $tags = $wma->tags();

        foreach (keys %$tags) {
                print "$_: $tags->{$_}\n";
        }

=head1 DESCRIPTION

This module implements access to metadata contained in WMA files.

=head1 SEE ALSO

Audio::FLAC::Header, L<http://getid3.sf.net/>

=head1 AUTHOR

Dan Sully, E<lt>Dan@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003-2004 by Dan Sully

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
