package SOAP::Lite::Deserializer::XMLSchemaSOAP1_2;
use SOAP::Lite::Deserializer::XMLSchemaSOAP1_1;

sub anyTypeValue { 'anyType' }

sub as_boolean; *as_boolean = \&SOAP::Lite::Deserializer::XMLSchemaSOAP1_1::as_boolean;
sub as_base64 { shift; require MIME::Base64; MIME::Base64::decode_base64(shift) }

BEGIN {
    no strict 'refs';
    for my $method (qw(
        anyType
        string float double decimal dateTime timePeriod gMonth gYearMonth gYear
        century gMonthDay gDay duration recurringDuration anyURI
        language integer nonPositiveInteger negativeInteger long int short byte
        nonNegativeInteger unsignedLong unsignedInt unsignedShort unsignedByte
        positiveInteger date time dateTime
    )) {
        my $name = 'as_' . $method; 
        *$name = sub { $_[1] }; 
    }
}

1;