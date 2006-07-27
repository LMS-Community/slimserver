package JSON::Syck;
use strict;
use Exporter;
use YAML::Syck ();

$JSON::Syck::VERSION = '0.14';

*Load = \&YAML::Syck::LoadJSON;
*Dump = \&YAML::Syck::DumpJSON;

$JSON::Syck::ImplicitTyping  = 1;
$JSON::Syck::Headless        = 1;
$JSON::Syck::ImplicitUnicode = 0;
$JSON::Syck::SingleQuote     = 0;

1;

__END__

=head1 NAME

JSON::Syck - JSON is YAML

=head1 SYNOPSIS

  use JSON::Syck;

  my $data = JSON::Syck::Load($json);
  my $json = JSON::Syck::Dump($data);

=head1 DESCRIPTION

JSON::Syck is a syck implementatoin of JSON parsing and
generation. Because JSON is YAML
(L<http://redhanded.hobix.com/inspect/yamlIsJson.html>), using syck
gives you the fastest and most memory efficient parser and dumper for
JSON data representation.

=head1 DIFFERENCE WITH JSON

You might want to know the difference between I<JSON> and
I<JSON::Syck>.

Since JSON is a pure-perl module and JSON::Syck is based on libsyck,
JSON::Syck is supposed to be very fast and memory efficient. See
chansen's benchmark table at
L<http://idisk.mac.com/christian.hansen/Public/perl/serialize.pl>

JSON.pm comes with dozens of ways to do the same thing and lots of
options, while JSON::Syck doesn't. There's only C<Load> and C<Dump>.

Oh, and JSON::Syck doesn't use camelCase method names :-)

=head1 REFERENCES

=head2 SCALAR REFERNECE

For now, when you pass a scalar reference to JSON::Syck, it
derefernces to get the actual scalar value. It means when you pass
self-referencing reference, JSON::Syck goes into infinite loop. Don't
do it.

If you want to serialize self refernecing stuff, you should use
YAML which supports it.

=head2 SUBROUTINE REFERENCE

When you pass subroutine reference, JSON::Syck dumps it as null.

=head1 UNICODE FLAGS

By default this module doesn't touch any of Unicode flags, and assumes
UTF-8 bytes to be passed and emit as an interface. However, when you
set C<$JSON::Syck::ImplicitUnicode> to 1, this module properly decodes
UTF-8 binaries and sets Unicode flag everywhere, as in:

  JSON (UTF-8 bytes)     => Perl (Unicode flagged)
  JSON (Unicode flagged) => Perl (Unicode flagged)
  Perl (UTF-8 bytes)     => JSON (Unicode flagged)
  Perl (Unicode flagged) => JSON (Unicode flagged)

=head1 QUOTING

According to the JSON specification, all JSON strings are to be double-quoted.
However, when embedding JavaScript in HTML attributes, it may be more
convenient to use single quotes.

Set C<$JSON::Syck::SingleQuote> to 1 will make both C<Dump> and C<Load> expect
single-quoted string literals.

=head1 AUTHORS

Audrey Tang E<lt>cpan@audreyt.orgE<gt>

Tatsuhiko Miyagawa E<lt>miyagawa@gmail.comE<gt>

This module is originally forked from Audrey Tang's excellent
YAML::Syck module and 99.9% of the XS code is written by Audrey.

The F<libsyck> code bundled with this module is written by I<why the
lucky stiff>, under a BSD-style license.  See the F<COPYING> file for
details.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
