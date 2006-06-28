package Audio::WMA;

use strict;
use vars qw($VERSION);

# WMA stores tags in UTF-16LE by default.
my $utf8 = 0;

# Minimum requirements
if ($] > 5.007) {
	require Encode;
}

$VERSION = '0.9';

my %guidMapping   = _knownGUIDs();
my %reversedGUIDs = reverse %guidMapping;

my $DEBUG	  = 0;

my $WORD          = 2;
my $DWORD         = 4;
my $QWORD         = 8;
my $GUID          = 16;

sub new {
	my $class = shift;
	my $file  = shift;

	my $self  = {};

	bless $self, $class;

	if (ref $file) {
		binmode $file;
		$self->{'fileHandle'} = $file;
	}
	else {
		open(FILE, $file) or do {
			warn "[$file] does not exist or cannot be read: $!";
			return undef;
		};

		binmode FILE;

		$self->{'filename'}   = $file;
		$self->{'fileHandle'} = \*FILE;
		$self->{'size'}	      = -s $file;
	}

	$self->{'offset'}     = 0;

	$self->_parseWMAHeader();

	delete $self->{'headerData'};

	unless (ref $file) {
		close  $self->{'fileHandle'};
		delete $self->{'fileHandle'};

		close  FILE;
	}

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

sub stream {
	my $self = shift;
	my $index = shift;

	return undef unless $self->{'STREAM'};
	return $self->{'STREAM'} unless defined($index);
	return $self->{'STREAM'}->[$index];
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

	if ($utf8 && $] > 5.007) {

		# This also turns on the utf8 flag - perldoc Encode
		$data = eval { Encode::decode('UTF-16LE', $data) } || $data;

	} elsif ($] > 5.007) {

		# otherwise try and turn it into ISO-8859-1 if we have Encode
		$data = eval { Encode::encode('latin1', $data) } || $data;
	}

	return _denull($data);
}

sub _denull {
        my $string = shift;
        $string =~ s/\0//g if defined $string;
        return $string;
}

sub _parseWMAHeader {
	my $self = shift;

	my $fh		  = $self->{'fileHandle'};

	read($fh, my $headerObjectData, 30) or return -1;

	my $objectId	  = substr($headerObjectData, 0, $GUID);
	my $objectSize    = unpack('V', substr($headerObjectData, 16, $QWORD) );
	my $headerObjects = unpack('V', substr($headerObjectData, 24, $DWORD));
	my $reserved1     = vec(substr($headerObjectData, 28, 1), 0, $DWORD);
	my $reserved2     = vec(substr($headerObjectData, 29, 1), 0, $DWORD);

	if ($DEBUG) {
		printf("ObjectId: [%s]\n", _byteStringToGUID($objectId));
		print  "\tobjectSize: [$objectSize]\n";
		print  "\theaderObjects [$headerObjects]\n";
		print  "\treserved1 [$reserved1]\n";
		print  "\treserved2 [$reserved2]\n\n";
	}

	# some sanity checks
	return -1 if ($self->{'size'} && $objectSize > $self->{'size'});
	return -1 if ($objectSize < 30);

	read($fh, $self->{'headerData'}, ($objectSize - 30));

	for (my $headerCounter = 0; $headerCounter < $headerObjects; $headerCounter++) {

		my $nextObjectGUID     = $self->_readAndIncrementOffset($GUID);
		my $nextObjectGUIDText = _byteStringToGUID($nextObjectGUID);
		my $nextObjectSize     = _parse64BitString($self->_readAndIncrementOffset($QWORD));

		my $nextObjectGUIDName = $reversedGUIDs{$nextObjectGUIDText};

		# some sanity checks
		return -1 if (!defined($nextObjectGUIDName));
		return -1 if (!defined $nextObjectSize || ($self->{'size'} && $nextObjectSize > $self->{'size'}));

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

				$self->_parseASFStreamPropertiesObject(0);
				next;
			}

			if ($nextObjectGUIDName eq 'ASF_Header_Extension_Object') {

				$self->_parseASFHeaderExtensionObject();
				next;
			}
		}

		# set our next object size
		$self->{'offset'} += ($nextObjectSize - $GUID - $QWORD);
	}

	# Now work on the subtypes.
	for my $stream (@{$self->{'STREAM'}}) {

		if ($reversedGUIDs{ $stream->{'stream_type_guid'} } eq 'ASF_Audio_Media') {

			my $audio = $self->_parseASFAudioMediaObject($stream);

			while (my ($key, $value) = each %$audio) {

				$self->{'INFO'}->{$key} = $value;
			}
		}
	}

	# pull these out and normalize them.
	my @arrayOk = qw(ALBUMARTIST GENRE COMPOSER AUTHOR);

	for my $ext (@{$self->{'EXT'}}) {

		while (my ($k,$v) = each %{$ext->{'content'}}) {

			# this gets both WM/Title and isVBR
			next unless $v->{'name'} =~ s#^(?:WM/|is)##i || $v->{'name'} =~ /^Author/;

			my $name  = uc($v->{'name'});
			my $value = $v->{'value'} || 0;

			# Append onto an existing item, as an array ref
			if (exists $self->{'TAGS'}->{$name} && grep { /^$name$/ } @arrayOk) {

				if (ref($self->{'TAGS'}->{$name}) eq 'ARRAY') {

					push @{$self->{'TAGS'}->{$name}}, $value;

				} else {

					my $oldValue = delete $self->{'TAGS'}->{$name};

					@{$self->{'TAGS'}->{$name}} = ($oldValue, $value);
				}

			} else {

				$self->{'TAGS'}->{$name} = $value;
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

	$info{'fileid_guid'}		= _byteStringToGUID($self->_readAndIncrementOffset($GUID));

	$info{'filesize'}		= _parse64BitString($self->_readAndIncrementOffset($QWORD));

	$info{'creation_date'}		= unpack('V', $self->_readAndIncrementOffset($QWORD));
	$info{'creation_date_unix'}	= _fileTimeToUnixTime($info{'creation_date'});

	$info{'data_packets'}		= unpack('V', $self->_readAndIncrementOffset($QWORD));

	$info{'play_duration'}		= _parse64BitString($self->_readAndIncrementOffset($QWORD));
	$info{'send_duration'}		= _parse64BitString($self->_readAndIncrementOffset($QWORD));
	$info{'preroll'}		= unpack('V', $self->_readAndIncrementOffset($QWORD));
	$info{'playtime_seconds'}	= ($info{'play_duration'} / 10000000)-($info{'preroll'} / 1000);

	$info{'flags_raw'}		= unpack('V', $self->_readAndIncrementOffset(4));

	$info{'flags'}->{'broadcast'}	= ($info{'flags_raw'} & 0x0001) ? 1 : 0;
	$info{'flags'}->{'seekable'}	= ($info{'flags_raw'} & 0x0002) ? 1 : 0;

	$info{'min_packet_size'}	= unpack('V', $self->_readAndIncrementOffset($DWORD));
	$info{'max_packet_size'}	= unpack('V', $self->_readAndIncrementOffset($DWORD));
	$info{'max_bitrate'}		= unpack('V', $self->_readAndIncrementOffset($DWORD));

	$info{'bitrate'}		= $info{'max_bitrate'};

	$self->{'INFO'}			= \%info;
}

sub _parseASFContentDescriptionObject {
	my $self = shift;

	my %desc = ();
	my @keys = qw(TITLE AUTHOR COPYRIGHT DESCRIPTION RATING);

	# populate the lengths of each key
	for my $key (@keys) {
		$desc{"_${key}length"}	= unpack('v', $self->_readAndIncrementOffset($WORD));
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

	my $content_count = unpack('v', $self->_readAndIncrementOffset($WORD));

	for (my $id = 0; $id < $content_count; $id++) {

		my $name_length  = unpack('v', $self->_readAndIncrementOffset($WORD));
		my $name         = _denull( $self->_readAndIncrementOffset($name_length) );
		my $data_type    = unpack('v', $self->_readAndIncrementOffset($WORD));
		my $data_length  = unpack('v', $self->_readAndIncrementOffset($WORD));
		my $value        = $self->_bytesToValue($data_type, $self->_readAndIncrementOffset($data_length));

		if ($DEBUG && $name ne 'WM/Picture') {
			print "Ext Cont Desc: $id";
			print "\tname   = $name\n";
			print "\tvalue  = $value\n";
			print "\ttype   = $data_type\n";
			print "\tlength = $data_length\n";
			print "\n";
		}

		# Parse out the WM/Picture structure into something we can use.
		#
		# typedef struct _WMPicture {
		#  LPWSTR  pwszMIMEType;
		#  BYTE  bPictureType;
		#  LPWSTR  pwszDescription;
		#  DWORD  dwDataLen;
		#  BYTE*  pbData;
		# };

		if ($name eq 'WM/Picture') {

			my $image_type_id = unpack('v', substr($value, 0, 1));
			my $image_size    = unpack('v', substr($value, 1, $DWORD));
			my $image_mime    = '';
			my $image_desc    = '';
			my $image_data    = '';
			my $offset        = 5;
			my $byte_pair     = '';

			do {
				$byte_pair = substr($value, $offset, 2);
				$offset   += 2;
				$image_mime .= $byte_pair;

			} while ($byte_pair ne "\x00\x00");

			do {
				$byte_pair = substr($value, $offset, 2);
				$offset   += 2;
				$image_desc .= $byte_pair;

			} while ($byte_pair ne "\x00\x00");

			$image_mime = _UTF16ToUTF8($image_mime);
			$image_desc = _UTF16ToUTF8($image_desc);
			$image_data = substr($value, $offset, $image_size);

			$value = {
				'TYPE' => $image_mime,
				'DATA' => $image_data,
			};

			if ($DEBUG) {
				print "Ext Cont Desc: $id";
				print "\tname          = $name\n";
				print "\timage_type_id = $image_type_id\n";
				print "\timage_size    = $image_size\n";
				print "\timage_mime    = $image_mime\n";
				print "\timage_desc    = $image_desc\n";
				print "\n";
			}
                }

		$ext{'content'}->{$id} = {
			'name'        => $name,
			'value'       => $value,
		};
	}

	push @{$self->{'EXT'}}, \%ext;
}

sub _parseASFStreamPropertiesObject {
	my $self  = shift;
	my $inline = shift;

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
	my $method = $inline ? '_readAndIncrementInlineOffset' : '_readAndIncrementOffset';

	$stream{'stream_type'}	      = $self->$method($GUID);
	$stream{'stream_type_guid'}   = _byteStringToGUID($stream{'stream_type'});
	$stream{'error_correct_type'} = $self->$method($GUID);
	$stream{'error_correct_guid'} = _byteStringToGUID($stream{'error_correct_type'});

	$stream{'time_offset'}        = unpack('v', $self->$method($QWORD));
	$stream{'type_data_length'}   = unpack('v', $self->$method($DWORD));
	$stream{'error_data_length'}  = unpack('v', $self->$method($DWORD));
	$stream{'flags_raw'}          = unpack('v', $self->$method($WORD));
	$streamNumber                 = $stream{'flags_raw'} & 0x007F;
	$stream{'flags'}{'encrypted'} = ($stream{'flags_raw'} & 0x8000);

	# Skip the DWORD
	$self->$method($DWORD);

	$stream{'type_specific_data'} = $self->$method($stream{'type_data_length'});
	$stream{'error_correct_data'} = $self->$method($stream{'error_data_length'});

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

	$stream->{'audio'} = $self->_parseWavFormat(substr($stream->{'type_specific_data'}, 0, $GUID));

	return $stream->{'audio'};
}

sub _parseWavFormat {
	my $self = shift;
	my $data = shift;

	my $wFormatTag = unpack('v', substr($data,  0, 2));

	my %wav  = (
		'codec'           => _RIFFwFormatTagLookup($wFormatTag),
		'channels'        => unpack('v', substr($data,  2, $WORD)),
		'sample_rate'     => unpack('v', substr($data,  4, $DWORD)),
		'bitrate'         => unpack('v', substr($data,  8, $DWORD)) * 8,
		'bits_per_sample' => unpack('v', substr($data, 14, $WORD)),
	);

	if ($wFormatTag == 0x0001 || $wFormatTag == 0x0163) {

		$wav{'lossless'} = 1;
	}

	return \%wav;
}

sub _parseASFExtendedStreamPropertiesObject {
	my $self = shift;
	my $size = shift;

	my $offset = $self->{'inlineOffset'};

	my %ext = (
		startTime             => $self->_bytesToValue(4, $self->_readAndIncrementInlineOffset($QWORD)),
		endTime               => $self->_bytesToValue(4, $self->_readAndIncrementInlineOffset($QWORD)),
		dataBitrate           => $self->_bytesToValue(3, $self->_readAndIncrementInlineOffset($DWORD)),
		bufferSize            => $self->_bytesToValue(3, $self->_readAndIncrementInlineOffset($DWORD)),
		bufferFullness        => $self->_bytesToValue(3, $self->_readAndIncrementInlineOffset($DWORD)),
		altDataBitrate        => $self->_bytesToValue(3, $self->_readAndIncrementInlineOffset($DWORD)),
		altBufferSize         => $self->_bytesToValue(3, $self->_readAndIncrementInlineOffset($DWORD)),
		altBufferFullness     => $self->_bytesToValue(3, $self->_readAndIncrementInlineOffset($DWORD)),
		maxObjectSize         => $self->_bytesToValue(3, $self->_readAndIncrementInlineOffset($DWORD)),
		flags                 => $self->_bytesToValue(3, $self->_readAndIncrementInlineOffset($DWORD)),
		streamNumber          => $self->_bytesToValue(5, $self->_readAndIncrementInlineOffset($WORD)),
		streamLanguageID      => $self->_bytesToValue(5, $self->_readAndIncrementInlineOffset($WORD)),
		averageTimePerFrame   => $self->_bytesToValue(4, $self->_readAndIncrementInlineOffset($QWORD)),
		streamNameCount       => $self->_bytesToValue(5, $self->_readAndIncrementInlineOffset($WORD)),
		payloadExtensionCount => $self->_bytesToValue(5, $self->_readAndIncrementInlineOffset($WORD)),
	);

	for (my $s = 0; $s < $ext{'streamNameCount'}; $s++) {

		my $language = unpack('v', $self->_readAndIncrementInlineOffset($WORD));
		my $length   = unpack('v', $self->_readAndIncrementInlineOffset($WORD));

		$self->_readAndIncrementInlineOffset($length);
		$self->{'inlineOffset'} += 4;
	}

	for (my $p = 0; $p < $ext{'payloadExtensionCount'}; $p++) {

		$self->_readAndIncrementInlineOffset(18);
		my $length = unpack('V', $self->_readAndIncrementInlineOffset($DWORD));

		$self->_readAndIncrementInlineOffset($length);
		$self->{'inlineOffset'} += 22;
	}

	if (($self->{'inlineOffset'} - $offset) < $size) {

		my $nextObjectGUID = _byteStringToGUID($self->_readAndIncrementInlineOffset($GUID));
		my $nextObjectName = $reversedGUIDs{$nextObjectGUID} || 'ASF_Unknown_Object';
		my $nextObjectSize = unpack('v', $self->_readAndIncrementInlineOffset($QWORD));

		if ($DEBUG) {
			print "extendedStreamPropertiesObject nextObjectGUID: [" . $nextObjectGUID . "]\n";
			print "extendedStreamPropertiesObject nextObjectName: [" . $nextObjectName . "]\n";
			print "extendedStreamPropertiesObject nextObjectSize: [" . $nextObjectSize . "]\n";
			print "\n";
		}

		if (defined $nextObjectName && $nextObjectName eq 'ASF_Stream_Properties_Object') {
			$self->_parseASFStreamPropertiesObject(1);
		}
	}
}

sub _parseASFHeaderExtensionObject {
	my $self = shift;

	my %ext = ();

	$ext{'reserved_1'}          = _byteStringToGUID($self->_readAndIncrementOffset($GUID));
	$ext{'reserved_2'}	    = unpack('v', $self->_readAndIncrementOffset($WORD));

	$ext{'extension_data_size'} = unpack('V', $self->_readAndIncrementOffset($DWORD));
	$ext{'extension_data'}      = $self->_readAndIncrementOffset($ext{'extension_data_size'});

	# Set these so we can use a convience method.
	$self->{'inlineData'}       = $ext{'extension_data'};
	$self->{'inlineOffset'}     = 0;

	if ($DEBUG) {
		print "Working on an ASF_Header_Extension_Object:\n\n";
	}

	while ($self->{'inlineOffset'} < $ext{'extension_data_size'}) {

		my $nextObjectGUID = _byteStringToGUID($self->_readAndIncrementInlineOffset($GUID)) || last;
		my $nextObjectName = $reversedGUIDs{$nextObjectGUID} || 'ASF_Unknown_Object';
		my $nextObjectSize = unpack('v', $self->_readAndIncrementInlineOffset($QWORD));

		# some sanity checks
		next if $nextObjectSize == 0 || $nextObjectSize > $ext{'extension_data_size'};
		next unless defined $nextObjectName;

		if ($DEBUG) {
			print "\textensionObject nextObjectGUID: [$nextObjectGUID]\n";
			print "\textensionObject nextObjectName: [$nextObjectName]\n";
			print "\textensionObject nextObjectSize: [$nextObjectSize]\n";
			print "\n";
		}

		# We only handle this object type for now.
        	if ($nextObjectName eq 'ASF_Metadata_Library_Object' ||
        	    $nextObjectName eq 'ASF_Metadata_Object') {

			my $content_count = unpack('v', $self->_readAndIncrementInlineOffset($WORD));

			if ($DEBUG) {
				print "\tContent Count: [$content_count]\n";
			}

			# Language List Index	WORD    16
			# Stream Number   	WORD    16
			# Name Length     	WORD    16
			# Data Type       	WORD    16
			# Data Length     	DWORD   32
			# Name    		WCHAR   varies
			# Data    		See below       varies
			for (my $id = 0; $id < $content_count; $id++) {

				my $language_list = unpack('v', $self->_readAndIncrementInlineOffset($WORD));
				my $stream_number = unpack('v', $self->_readAndIncrementInlineOffset($WORD));
				my $name_length   = unpack('v', $self->_readAndIncrementInlineOffset($WORD));
				my $data_type     = unpack('v', $self->_readAndIncrementInlineOffset($WORD));
				my $data_length   = unpack('V', $self->_readAndIncrementInlineOffset($DWORD));
				my $name          = _denull($self->_readAndIncrementInlineOffset($name_length));
				my $value         = $self->_bytesToValue($data_type, $self->_readAndIncrementInlineOffset($data_length));

				$ext{'content'}->{$id}->{'name'}  = $name;
				$ext{'content'}->{$id}->{'value'} = $value;

				if ($DEBUG) {
					print "\t$nextObjectName: $id\n";
					print "\t\tname   = $name\n";
					print "\t\tvalue  = $value\n";
					print "\t\ttype   = $data_type\n";
					print "\t\tlength = $data_length\n";
					print "\n";
				}
			}

		} elsif ($nextObjectName eq 'ASF_Extended_Stream_Properties_Object') {

			$self->_parseASFExtendedStreamPropertiesObject($nextObjectSize - $GUID - $QWORD);

		} else {

			# Only increment the offset if we couldn't parse the object.
			$self->{'inlineOffset'} += ($nextObjectSize - $GUID - $QWORD);
		}
	}

	delete $ext{'extension_data'};
	delete $self->{'inlineData'};
	delete $self->{'inlineOffset'};

	push @{$self->{'EXT'}}, \%ext;
}

sub _bytesToValue {
	my ($self, $data_type, $value) = @_;

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

	if ($data_type == 0) {

		$value = _UTF16ToUTF8($value);

	} elsif ($data_type == 1) {

		# Leave byte arrays as is.

	} elsif ($data_type == 2 || $data_type == 5) {

		$value = unpack('v', $value);

	} elsif ($data_type == 3) {

		$value = unpack('V', $value);

	} elsif ($data_type == 4) {

		$value = _parse64BitString($value);

	} elsif ($data_type == 6) {

		$value = _byteStringToGUID($value);
	}

	return $value;
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
		'ASF_Index_Placeholder_Object'			=> 'D9AADE20-7C17-4F9C-BC28-8555DD98E2A2',
		'ASF_Compatibility_Object'			=> '26F18B5D-4584-47EC-9F5F-0E651F0452C9',
	);

	return %guidMapping;
}

sub _RIFFwFormatTagLookup {
	my $wFormatTag = shift;

	my %formatTags = (
		0x0000 => 'Microsoft Unknown Wave Format',
		0x0001 => 'Pulse Code Modulation (PCM)',
		0x0002 => 'Microsoft ADPCM',
		0x0003 => 'IEEE Float',
		0x0004 => 'Compaq Computer VSELP',
		0x0005 => 'IBM CVSD',
		0x0006 => 'Microsoft A-Law',
		0x0007 => 'Microsoft mu-Law',
		0x0008 => 'Microsoft DTS',
		0x0010 => 'OKI ADPCM',
		0x0011 => 'Intel DVI/IMA ADPCM',
		0x0012 => 'Videologic MediaSpace ADPCM',
		0x0013 => 'Sierra Semiconductor ADPCM',
		0x0014 => 'Antex Electronics G.723 ADPCM',
		0x0015 => 'DSP Solutions DigiSTD',
		0x0016 => 'DSP Solutions DigiFIX',
		0x0017 => 'Dialogic OKI ADPCM',
		0x0018 => 'MediaVision ADPCM',
		0x0019 => 'Hewlett-Packard CU',
		0x0020 => 'Yamaha ADPCM',
		0x0021 => 'Speech Compression Sonarc',
		0x0022 => 'DSP Group TrueSpeech',
		0x0023 => 'Echo Speech EchoSC1',
		0x0024 => 'Audiofile AF36',
		0x0025 => 'Audio Processing Technology APTX',
		0x0026 => 'AudioFile AF10',
		0x0027 => 'Prosody 1612',
		0x0028 => 'LRC',
		0x0030 => 'Dolby AC2',
		0x0031 => 'Microsoft GSM 6.10',
		0x0032 => 'MSNAudio',
		0x0033 => 'Antex Electronics ADPCME',
		0x0034 => 'Control Resources VQLPC',
		0x0035 => 'DSP Solutions DigiREAL',
		0x0036 => 'DSP Solutions DigiADPCM',
		0x0037 => 'Control Resources CR10',
		0x0038 => 'Natural MicroSystems VBXADPCM',
		0x0039 => 'Crystal Semiconductor IMA ADPCM',
		0x003A => 'EchoSC3',
		0x003B => 'Rockwell ADPCM',
		0x003C => 'Rockwell Digit LK',
		0x003D => 'Xebec',
		0x0040 => 'Antex Electronics G.721 ADPCM',
		0x0041 => 'G.728 CELP',
		0x0042 => 'MSG723',
		0x0050 => 'MPEG Layer-2 or Layer-1',
		0x0052 => 'RT24',
		0x0053 => 'PAC',
		0x0055 => 'MPEG Layer-3',
		0x0059 => 'Lucent G.723',
		0x0060 => 'Cirrus',
		0x0061 => 'ESPCM',
		0x0062 => 'Voxware',
		0x0063 => 'Canopus Atrac',
		0x0064 => 'G.726 ADPCM',
		0x0065 => 'G.722 ADPCM',
		0x0066 => 'DSAT',
		0x0067 => 'DSAT Display',
		0x0069 => 'Voxware Byte Aligned',
		0x0070 => 'Voxware AC8',
		0x0071 => 'Voxware AC10',
		0x0072 => 'Voxware AC16',
		0x0073 => 'Voxware AC20',
		0x0074 => 'Voxware MetaVoice',
		0x0075 => 'Voxware MetaSound',
		0x0076 => 'Voxware RT29HW',
		0x0077 => 'Voxware VR12',
		0x0078 => 'Voxware VR18',
		0x0079 => 'Voxware TQ40',
		0x0080 => 'Softsound',
		0x0081 => 'Voxware TQ60',
		0x0082 => 'MSRT24',
		0x0083 => 'G.729A',
		0x0084 => 'MVI MV12',
		0x0085 => 'DF G.726',
		0x0086 => 'DF GSM610',
		0x0088 => 'ISIAudio',
		0x0089 => 'Onlive',
		0x0091 => 'SBC24',
		0x0092 => 'Dolby AC3 SPDIF',
		0x0093 => 'MediaSonic G.723',
		0x0094 => 'Aculab PLC    Prosody 8kbps',
		0x0097 => 'ZyXEL ADPCM',
		0x0098 => 'Philips LPCBB',
		0x0099 => 'Packed',
		0x00FF => 'AAC',
		0x0100 => 'Rhetorex ADPCM',
		0x0101 => 'IBM mu-law',
		0x0102 => 'IBM A-law',
		0x0103 => 'IBM AVC Adaptive Differential Pulse Code Modulation (ADPCM)',
		0x0111 => 'Vivo G.723',
		0x0112 => 'Vivo Siren',
		0x0123 => 'Digital G.723',
		0x0125 => 'Sanyo LD ADPCM',
		0x0130 => 'Sipro Lab Telecom ACELP NET',
		0x0131 => 'Sipro Lab Telecom ACELP 4800',
		0x0132 => 'Sipro Lab Telecom ACELP 8V3',
		0x0133 => 'Sipro Lab Telecom G.729',
		0x0134 => 'Sipro Lab Telecom G.729A',
		0x0135 => 'Sipro Lab Telecom Kelvin',
		0x0140 => 'Windows Media Video V8',
		0x0150 => 'Qualcomm PureVoice',
		0x0151 => 'Qualcomm HalfRate',
		0x0155 => 'Ring Zero Systems TUB GSM',
		0x0160 => 'Microsoft Audio 1',
		0x0161 => 'Windows Media Audio V7 / V8 / V9',
		0x0162 => 'Windows Media Audio Professional V9',
		0x0163 => 'Windows Media Audio Lossless V9',
		0x0200 => 'Creative Labs ADPCM',
		0x0202 => 'Creative Labs Fastspeech8',
		0x0203 => 'Creative Labs Fastspeech10',
		0x0210 => 'UHER Informatic GmbH ADPCM',
		0x0220 => 'Quarterdeck',
		0x0230 => 'I-link Worldwide VC',
		0x0240 => 'Aureal RAW Sport',
		0x0250 => 'Interactive Products HSX',
		0x0251 => 'Interactive Products RPELP',
		0x0260 => 'Consistent Software CS2',
		0x0270 => 'Sony SCX',
		0x0300 => 'Fujitsu FM Towns Snd',
		0x0400 => 'BTV Digital',
		0x0401 => 'Intel Music Coder',
		0x0450 => 'QDesign Music',
		0x0680 => 'VME VMPCM',
		0x0681 => 'AT&T Labs TPC',
		0x08AE => 'ClearJump LiteWave',
		0x1000 => 'Olivetti GSM',
		0x1001 => 'Olivetti ADPCM',
		0x1002 => 'Olivetti CELP',
		0x1003 => 'Olivetti SBC',
		0x1004 => 'Olivetti OPR',
		0x1100 => 'Lernout & Hauspie Codec (0x1100)',
		0x1101 => 'Lernout & Hauspie CELP Codec (0x1101)',
		0x1102 => 'Lernout & Hauspie SBC Codec (0x1102)',
		0x1103 => 'Lernout & Hauspie SBC Codec (0x1103)',
		0x1104 => 'Lernout & Hauspie SBC Codec (0x1104)',
		0x1400 => 'Norris',
		0x1401 => 'AT&T ISIAudio',
		0x1500 => 'Soundspace Music Compression',
		0x181C => 'VoxWare RT24 Speech',
		0x1FC4 => 'NCT Soft ALF2CD (www.nctsoft.com)',
		0x2000 => 'Dolby AC3',
		0x2001 => 'Dolby DTS',
		0x2002 => 'WAVE_FORMAT_14_4',
		0x2003 => 'WAVE_FORMAT_28_8',
		0x2004 => 'WAVE_FORMAT_COOK',
		0x2005 => 'WAVE_FORMAT_DNET',
		0x674F => 'Ogg Vorbis 1',
		0x6750 => 'Ogg Vorbis 2',
		0x6751 => 'Ogg Vorbis 3',
		0x676F => 'Ogg Vorbis 1+',
		0x6770 => 'Ogg Vorbis 2+',
		0x6771 => 'Ogg Vorbis 3+',
		0x7A21 => 'GSM-AMR (CBR, no SID)',
		0x7A22 => 'GSM-AMR (VBR, including SID)',
		0xFFFE => 'WAVE_FORMAT_EXTENSIBLE',
		0xFFFF => 'WAVE_FORMAT_DEVELOPMENT',
	);

	return $formatTags{$wFormatTag};
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

Copyright 2003-2006 by Dan Sully & Slim Devices, Inc.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
