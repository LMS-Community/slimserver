#============================================================= -*-Perl-*-
# 
# Template::Stash::XS
# 
# DESCRIPTION
#
#   Perl bootstrap for XS module. Inherits methods from 
#   Template::Stash when not implemented in the XS module.
#
#========================================================================

package Template::Stash::XS;

use Template;
use Template::Stash;

BEGIN {
  require DynaLoader;
  @Template::Stash::XS::ISA = qw( DynaLoader Template::Stash );

  eval {
    bootstrap Template::Stash::XS $Template::VERSION;
  };
  if ($@) {
    die "Couldn't load Template::Stash::XS $Template::VERSION:\n\n$@\n";
  }
}


sub DESTROY {
  # no op
  1;
}


# catch missing method calls here so perl doesn't barf 
# trying to load *.al files 
sub AUTOLOAD {
  my ($self, @args) = @_;
  my @c             = caller(0);
  my $auto	    = $AUTOLOAD;

  $auto =~ s/.*:://;
  $self =~ s/=.*//;

  die "Can't locate object method \"$auto\"" .
      " via package \"$self\" at $c[1] line $c[2]\n";
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

Template::Stash::XS - High-speed variable stash written in C

=head1 SYNOPSIS

    use Template;
    use Template::Stash::XS;

    my $stash = Template::Stash::XS->new(\%vars);
    my $tt2   = Template->new({ STASH => $stash });

=head1 DESCRIPTION

The Template:Stash::XS module is an implementation of the
Template::Stash written in C.  The "XS" in the name refers to Perl's
XS extension system for interfacing Perl to C code.  It works just
like the regular Perl implementation of Template::Stash but runs about
twice as fast.

The easiest way to use the XS stash is to configure the Template
Toolkit to use it by default.  You can do this at installation time
(when you run C<perl Makefile.PL>) by answering 'y' to the questions:

    Do you want to build the XS Stash module?      y
    Do you want to use the XS Stash by default?    y

See the F<INSTALL> file distributed with the Template Toolkit for further
details on installation.

If you don't elect to use the XS stash by default then you should use
the C<STASH> configuration item when you create a new Template object.
This should reference an XS stash object that you have created
manually.

    use Template;
    use Template::Stash::XS;

    my $stash = Template::Stash::XS->new(\%vars);
    my $tt2   = Template->new({ STASH => $stash });

Alternately, you can set the C<$Template::Config::STASH> package
variable like so:

    use Template;
    use Template::Config;

    $Template::Config::STASH = 'Template::Stash::XS';

    my $tt2 = Template->new();

The XS stash will then be automatically used.  

If you want to use the XS stash by default and don't want to
re-install the Template Toolkit, then you can manually modify the
C<Template/Config.pm> module near line 42 to read:

    $STASH = 'Template::Stash::XS';

=head1 BUGS

Please report bugs to the Template Toolkit mailing list
templates@template-toolkit.org

=head1 AUTHORS

Andy Wardley E<lt>abw@tt2.orgE<gt>

Doug Steinwand E<lt>dsteinwand@citysearch.comE<gt>

=head1 VERSION

Template Toolkit version 2.15, released on 26 May 2006.



=head1 COPYRIGHT

  Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.
  Copyright (C) 1998-2002 Canon Research Centre Europe Ltd.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.



=head1 SEE ALSO

L<Template::Stash|Template::Stash>

