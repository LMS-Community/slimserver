#============================================================= -*-Perl-*-
#
# Template::Plugin::Format
#
# DESCRIPTION
#
#   Simple Template Toolkit Plugin which creates formatting functions.
#
# AUTHOR
#   Andy Wardley   <abw@kfs.org>
#
# COPYRIGHT
#   Copyright (C) 1996-2000 Andy Wardley.  All Rights Reserved.
#   Copyright (C) 1998-2000 Canon Research Centre Europe Ltd.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#----------------------------------------------------------------------------
#
# $Id: Format.pm,v 2.67 2006/01/30 20:05:48 abw Exp $
#
#============================================================================

package Template::Plugin::Format;

require 5.004;

use strict;
use vars qw( @ISA $VERSION );
use base qw( Template::Plugin );
use Template::Plugin;

$VERSION = sprintf("%d.%02d", q$Revision: 2.67 $ =~ /(\d+)\.(\d+)/);


sub new {
    my ($class, $context, $format) = @_;;
    return defined $format
	? make_formatter($format)
	: \&make_formatter;
}


sub make_formatter {
    my $format = shift;
    $format = '%s' unless defined $format;
    return sub { 
	my @args = @_;
	push(@args, '') unless @args;
	return sprintf($format, @args); 
    }
}


1;

__END__


#------------------------------------------------------------------------
# IMPORTANT NOTE
#   This documentation is generated automatically from source
#   templates.  Any changes you make here may be lost.
# 
#   The 'docsrc' documentation source bundle is available for download
#   from http://www.template-toolkit.org/docs.html and contains all
#   the source templates, XML files, scripts, etc., from which the
#   documentation for the Template Toolkit is built.
#------------------------------------------------------------------------

=head1 NAME

Template::Plugin::Format - Plugin to create formatting functions

=head1 SYNOPSIS

    [% USE format %]
    [% commented = format('# %s') %]
    [% commented('The cat sat on the mat') %]
    
    [% USE bold = format('<b>%s</b>') %]
    [% bold('Hello') %]

=head1 DESCRIPTION

The format plugin constructs sub-routines which format text according to
a printf()-like format string.

=head1 AUTHOR

Andy Wardley E<lt>abw@wardley.orgE<gt>

L<http://wardley.org/|http://wardley.org/>




=head1 VERSION

2.67, distributed as part of the
Template Toolkit version 2.15, released on 26 May 2006.

=head1 COPYRIGHT

  Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.
  Copyright (C) 1998-2002 Canon Research Centre Europe Ltd.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin|Template::Plugin>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
