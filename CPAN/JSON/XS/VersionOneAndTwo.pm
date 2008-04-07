package JSON::XS::VersionOneAndTwo;
use strict;
no strict 'refs';
use warnings;
use JSON::XS;
our $VERSION = '0.31';

sub import {
    my ( $exporter, @imports ) = @_;
    my ( $caller, $file, $line ) = caller;
    my $json_xs_version = $JSON::XS::VERSION;
    if ( $json_xs_version < 2.01 ) {
        *{ $caller . '::encode_json' } = \&JSON::XS::to_json;
        *{ $caller . '::to_json' }     = \&JSON::XS::to_json;
        *{ $caller . '::decode_json' } = \&JSON::XS::from_json;
        *{ $caller . '::from_json' }   = \&JSON::XS::from_json;
    } else {
        *{ $caller . '::encode_json' } = \&JSON::XS::encode_json;
        *{ $caller . '::to_json' }     = \&JSON::XS::encode_json;
        *{ $caller . '::decode_json' } = \&JSON::XS::decode_json;
        *{ $caller . '::from_json' }   = \&JSON::XS::decode_json;
    }
}

1;

__END__

=head1 NAME

JSON::XS::VersionOneAndTwo - Support versions 1 and 2 of JSON::XS

=head1 SYNOPSIS

  use JSON::XS::VersionOneAndTwo;
  my $data = { 'three' => [ 1, 2, 3 ] };

  # use JSON::XS version 1.X style
  my $json1 = to_json($data);
  my $data1 = from_json($json1);
  
  # or use JSON::XS version 2.X style
  my $json2 = encode_json($data);
  my $data2 = decode_json($json2);

=head1 DESCRIPTION

L<JSON::XS> is by far the best JSON module on the CPAN. However, it changed
its API at version 2.01. If you have to maintain code which may be 
run on systems with either version one or two then this is a bit
of a pain. This module takes the pain away without sacrificing performance.

=head1 AUTHOR

Leon Brocard <acme@astray.com>.

=head1 COPYRIGHT

Copyright (C) 2008, Leon Brocard

This module is free software; you can redistribute it or modify it
under the same terms as Perl itself.
