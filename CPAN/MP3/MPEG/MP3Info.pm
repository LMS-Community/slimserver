package MPEG::MP3Info;  # old name

use strict;
use vars qw[@ISA $VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS];

use MP3::Info ':all';
@ISA			= 'MP3::Info';
$VERSION		= '0.90';
@EXPORT			= @MP3::Info::EXPORT;
@EXPORT_OK		= @MP3::Info::EXPORT_OK;
%EXPORT_TAGS		= %MP3::Info::EXPORT_TAGS;

=pod

=head1 NAME

MPEG::MP3Info - Manipulate / fetch info from MP3 audio files

=head1 SYNOPSIS

	use MP3::Info;

=head1 DESCRIPTION

This is just a wrapper around MP3::Info now.

=head1 AUTHOR AND COPYRIGHT

Chris Nandor E<lt>pudge@pobox.comE<gt>, http://pudge.net/

Copyright (c) 1998-2001 Chris Nandor.  All rights reserved.  This program is
free software; you can redistribute it and/or modify it under the terms
of the Artistic License, distributed with Perl.


=head1 SEE ALSO

MP3::Info


=head1 VERSION

v0.90, Sunday, January 14, 2001

=cut
