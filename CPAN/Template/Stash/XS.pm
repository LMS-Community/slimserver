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

Template::Stash::XS - Experimetal high-speed stash written in XS

=head1 SYNOPSIS

    use Template;
    use Template::Stash::XS;

    my $stash = Template::Stash::XS->new(\%vars);
    my $tt2   = Template->new({ STASH => $stash });

=head1 DESCRIPTION

This module loads the XS version of Template::Stash::XS. It should 
behave very much like the old one, but run about twice as fast. 
See the synopsis above for usage information.

Only a few methods (such as get and set) have been implemented in XS. 
The others are inherited from Template::Stash.

=head1 NOTE

To always use the XS version of Stash, modify the Template/Config.pm 
module near line 45:

 $STASH    = 'Template::Stash::XS';

If you make this change, then there is no need to explicitly create 
an instance of Template::Stash::XS as seen in the SYNOPSIS above. Just
use Template as normal.

Alternatively, in your code add this line before creating a Template
object:

 $Template::Config::STASH = 'Template::Stash::XS';

To use the original, pure-perl version restore this line in 
Template/Config.pm:

 $STASH    = 'Template::Stash';

Or in your code:

 $Template::Config::STASH = 'Template::Stash';

You can elect to have this performed once for you at installation
time by answering 'y' or 'n' to the question that asks if you want
to make the XS Stash the default.

=head1 BUGS

Please report bugs to the Template Toolkit mailing list
templates@template-toolkit.org

As of version 2.05 of the Template Toolkit, use of the XS Stash is
known to have 2 potentially troublesome side effects.  The first
problem is that accesses to tied hashes (e.g. Apache::Session) may not
work as expected.  This should be fixed in an imminent release.  If
you are using tied hashes then it is suggested that you use the
regular Stash by default, or write a thin wrapper around your tied
hashes to enable the XS Stash to access items via regular method
calls.

The second potential problem is that enabling the XS Stash causes all
the Template Toolkit modules to be installed in an architecture
dependant library, e.g. in

    /usr/lib/perl5/site_perl/5.6.0/i386-linux/Template

instead of 

    /usr/lib/perl5/site_perl/5.6.0/Template

At the time of writing, we're not sure why this is happening but it's
likely that this is either a bug or intentional feature in the Perl
ExtUtils::MakeMaker module.  As far as I know, Perl always checks the
architecture dependant directories before the architecture independant
ones.  Therefore, a newer version of the Template Toolkit installed
with the XS Stash enabled should be used by Perl in preference to any
existing version using the regular stash.  However, if you install a 
future version of the Template Toolkit with the XS Stash disabled, you
may find that Perl continues to use the older version with XS Stash 
enabled in preference.

=head1 AUTHORS

Andy Wardley E<lt>abw@tt2.orgE<gt>

Doug Steinwand E<lt>dsteinwand@citysearch.comE<gt>

=head1 VERSION

Template Toolkit version 2.13, released on 30 January 2004.



=head1 COPYRIGHT

  Copyright (C) 1996-2004 Andy Wardley.  All Rights Reserved.
  Copyright (C) 1998-2002 Canon Research Centre Europe Ltd.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.



=head1 SEE ALSO

L<Template::Stash|Template::Stash>

