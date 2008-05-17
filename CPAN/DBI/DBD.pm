package DBI::DBD;
# vim:ts=8:sw=4

use vars qw($VERSION);	# set $VERSION early so we don't confuse PAUSE/CPAN etc

# don't use Revision here because that's not in svn:keywords so that the
# examples that use it below won't be messed up
$VERSION = sprintf("12.%06d", q$Id: DBD.pm 10405 2007-12-11 10:00:19Z mjevans $ =~ /(\d+)/o);


# $Id: DBD.pm 10405 2007-12-11 10:00:19Z mjevans $
#
# Copyright (c) 1997-2006 Jonathan Leffler, Jochen Wiedmann, Steffen
# Goeldner and Tim Bunce
#
# You may distribute under the terms of either the GNU General Public
# License or the Artistic License, as specified in the Perl README file.

=head1 NAME

DBI::DBD - Perl DBI Database Driver Writer's Guide

=head1 SYNOPSIS

  perldoc DBI::DBD

=head2 Version and volatility

This document is I<still> a minimal draft which is in need of further work.

The changes will occur both because the B<DBI> specification is changing
and hence the requirements on B<DBD> drivers change, and because feedback
from people reading this document will suggest improvements to it.

Please read the B<DBI> documentation first and fully, including the B<DBI> FAQ.
Then reread the B<DBI> specification again as you're reading this. It'll help.

This document is a patchwork of contributions from various authors.
More contributions (preferably as patches) are very welcome.

=head1 DESCRIPTION

This document is primarily intended to help people writing new
database drivers for the Perl Database Interface (Perl DBI).
It may also help others interested in discovering why the internals of
a B<DBD> driver are written the way they are.

This is a guide.  Few (if any) of the statements in it are completely
authoritative under all possible circumstances.  This means you will
need to use judgement in applying the guidelines in this document.
If in I<any> doubt at all, please do contact the I<dbi-dev> mailing list
(details given below) where Tim Bunce and other driver authors can help.

=head1 CREATING A NEW DRIVER

The first rule for creating a new database driver for the Perl DBI is
very simple: B<DON'T!>

There is usually a driver already available for the database you want
to use, almost regardless of which database you choose. Very often, the
database will provide an ODBC driver interface, so you can often use
B<DBD::ODBC> to access the database. This is typically less convenient
on a Unix box than on a Microsoft Windows box, but there are numerous
options for ODBC driver managers on Unix too, and very often the ODBC
driver is provided by the database supplier.

Before deciding that you need to write a driver, do your homework to
ensure that you are not wasting your energies.

[As of December 2002, the consensus is that if you need an ODBC driver
manager on Unix, then the unixODBC driver (available from
L<http://www.unixodbc.org/>) is the way to go.]

The second rule for creating a new database driver for the Perl DBI is
also very simple: B<Don't -- get someone else to do it for you!>

Nevertheless, there are occasions when it is necessary to write a new
driver, often to use a proprietary language or API to access the
database more swiftly, or more comprehensively, than an ODBC driver can.
Then you should read this document very carefully, but with a suitably
sceptical eye.

If there is something in here that does not make any sense, question it.
You might be right that the information is bogus, but don't come to that
conclusion too quickly.

=head2 URLs and mailing lists

The primary web-site for locating B<DBI> software and information is

  http://dbi.perl.org/

There are two main and one auxilliary mailing lists for people working
with B<DBI>.  The primary lists are I<dbi-users@perl.org> for general users
of B<DBI> and B<DBD> drivers, and I<dbi-dev@perl.org> mainly for B<DBD> driver
writers (don't join the I<dbi-dev> list unless you have a good reason).
The auxilliary list is I<dbi-announce@perl.org> for announcing new
releases of B<DBI> or B<DBD> drivers.

You can join these lists by accessing the web-site L<http://dbi.perl.org/>.
The lists are closed so you cannot send email to any of the lists
unless you join the list first.

You should also consider monitoring the I<comp.lang.perl.*> newsgroups,
especially I<comp.lang.perl.modules>.

=head2 The Cheetah book

The definitive book on Perl DBI is the Cheetah book, so called because
of the picture on the cover. Its proper title is 'I<Programming the
Perl DBI: Database programming with Perl>' by Alligator Descartes
and Tim Bunce, published by O'Reilly Associates, February 2000, ISBN
1-56592-699-4. Buy it now if you have not already done so, and read it.

=head2 Locating drivers

Before writing a new driver, it is in your interests to find out
whether there already is a driver for your database.  If there is such
a driver, it would be much easier to make use of it than to write your
own!

The primary web-site for locating Perl software is
L<http://search.cpan.org/>.  You should look under the various
modules listings for the software you are after. For example:

  http://search.cpan.org/modlist/Database_Interfaces

Follow the B<DBD::> and B<DBIx::> links at the top to see those subsets.

See the B<DBI> docs for information on B<DBI> web sites and mailing lists.

=head2 Registering a new driver

Before going through any official registration process, you will need
to establish that there is no driver already in the works. You'll do
that by asking the B<DBI> mailing lists whether there is such a driver
available, or whether anybody is working on one.

When you get the go ahead, you will need to establish the name of the
driver and a prefix for the driver. Typically, the name is based on the
name of the database software it uses, and the prefix is a contraction
of that. Hence, B<DBD::Oracle> has the name I<Oracle> and the prefix
'I<ora_>'. The prefix must be lowercase and contain no underscores other
than the one at the end.

This information will be recorded in the B<DBI> module. Apart from
documentation purposes, registration is a prerequisite for
L<installing private methods|DBI/install_method>.

If you are writing a driver which will not be distributed on CPAN, then
you should choose a prefix beginning with 'I<x_>', to avoid potential
prefix collisions with drivers registered in the future. Thus, if you
wrote a non-CPAN distributed driver called B<DBD::CustomDB>, the prefix
might be 'I<x_cdb_>'.

This document assumes you are writing a driver called B<DBD::Driver>, and
that the prefix 'I<drv_>' is assigned to the driver.

=head2 Two styles of database driver

There are two distinct styles of database driver that can be written to
work with the Perl DBI.

Your driver can be written in pure Perl, requiring no C compiler.
When feasible, this is the best solution, but most databases are not
written in such a way that this can be done. Some examples of pure
Perl drivers are B<DBD::File> and B<DBD::CSV>.

Alternatively, and most commonly, your driver will need to use some C
code to gain access to the database. This will be classified as a C/XS
driver.

=head2 What code will you write?

There are a number of files that need to be written for either a pure
Perl driver or a C/XS driver. There are no extra files needed only by
a pure Perl driver, but there are several extra files needed only by a
C/XS driver.

=head3 Files common to pure Perl and C/XS drivers

Assuming that your driver is called B<DBD::Driver>, these files are:

=over 4

=item * F<Makefile.PL>

=item * F<META.yml>

=item * F<README>

=item * F<MANIFEST>

=item * F<Driver.pm>

=item * F<lib/Bundle/DBD/Driver.pm>

=item * F<lib/DBD/Driver/Summary.pm>

=item * F<t/*.t>

=back

The first four files are mandatory. F<Makefile.PL> is used to control
how the driver is built and installed. The F<README> file tells people
who download the file about how to build the module and any prerequisite
software that must be installed. The F<MANIFEST> file is used by the
standard Perl module distribution mechanism. It lists all the source
files that need to be distributed with your module. F<Driver.pm> is what
is loaded by the B<DBI> code; it contains the methods peculiar to your
driver.

Although the F<META.yml> file is not B<required> you are advised to
create one. Of particular importance are the I<build_requires> and
I<configure_requires> attributes which newer CPAN modules understand.
You use these to tell the CPAN module (and CPANPLUS) that your build
and configure mechanisms require DBI. The best reference for META.yml
(at the time of writing) is
L<http://module-build.sourceforge.net/META-spec-v1.2.html>. You can find
a reasonable example of a F<META.yml> in DBD::ODBC.

The F<lib/Bundle/DBD/Driver.pm> file allows you to specify other Perl
modules on which yours depends in a format that allows someone to type a
simple command and ensure that all the pre-requisites are in place as
well as building your driver.

The F<lib/DBD/Driver/Summary.pm> file contains (an updated version of) the
information that was included - or that would have been included - in
the appendices of the Cheetah book as a summary of the abilities of your
driver and the associated database.

The files in the F<t> subdirectory are unit tests for your driver.
You should write your tests as stringently as possible, while taking
into account the diversity of installations that you can encounter:

=over 4

=item *

Your tests should not casually modify operational databases.

=item *

You should never damage existing tables in a database.

=item *

You should code your tests to use a constrained name space within the
database. For example, the tables (and all other named objects) that are
created could all begin with 'I<dbd_drv_>'.

=item *

At the end of a test run, there should be no testing objects left behind
in the database.

=item *

If you create any databases, you should remove them.

=item *

If your database supports temporary tables that are automatically
removed at the end of a session, then exploit them as often as possible.

=item *

Try to make your tests independent of each other. If you have a
test F<t/t11dowhat.t> that depends upon the successful running
of F<t/t10thingamy.t>, people cannot run the single test case
F<t/t11dowhat.t>. Further, running F<t/t11dowhat.t> twice in a row is
likely to fail (at least, if F<t/t11dowhat.t> modifies the database at
all) because the database at the start of the second run is not what you
saw at the start of the first run.

=item *

Document in your F<README> file what you do, and what privileges people
need to do it.

=item *

You can, and probably should, sequence your tests by including a test
number before an abbreviated version of the test name; the tests are run
in the order in which the names are expanded by shell-style globbing.

=item *

It is in your interests to ensure that your tests work as widely
as possible.

=back

Many drivers also install sub-modules B<DBD::Driver::SubModule>
for any of a variety of different reasons, such as to support
the metadata methods (see the discussion of L</METADATA METHODS>
below). Such sub-modules are conventionally stored in the directory
F<lib/DBD/Driver>. The module itself would usually be in a file
F<SubModule.pm>. All such sub-modules should themselves be version
stamped (see the discussions far below).

=head3 Extra files needed by C/XS drivers

The software for a C/XS driver will typically contain at least four
extra files that are not relevant to a pure Perl driver.

=over 4

=item * F<Driver.xs>

=item * F<Driver.h>

=item * F<dbdimp.h>

=item * F<dbdimp.c>

=back

The F<Driver.xs> file is used to generate C code that Perl can call to gain
access to the C functions you write that will, in turn, call down onto
your database software.

The F<Driver.h> header is a stylized header that ensures you can access the
necessary Perl and B<DBI> macros, types, and function declarations.

The F<dbdimp.h> is used to specify which functions have been implemented by
your driver.

The F<dbdimp.c> file is where you write the C code that does the real work
of translating between Perl-ish data types and what the database expects
to use and return.

There are some (mainly small, but very important) differences between
the contents of F<Makefile.PL> and F<Driver.pm> for pure Perl and C/XS
drivers, so those files are described both in the section on creating a
pure Perl driver and in the section on creating a C/XS driver.

Obviously, you can add extra source code files to the list.

=head2 Requirements on a driver and driver writer

To be remotely useful, your driver must be implemented in a format that
allows it to be distributed via CPAN, the Comprehensive Perl Archive
Network (L<http://www.cpan.org/> and L<http://search.cpan.org>).
Of course, it is easier if you do not have to meet this criterion, but
you will not be able to ask for much help if you do not do so, and
no-one is likely to want to install your module if they have to learn a
new installation mechanism.

=head1 CREATING A PURE PERL DRIVER

Writing a pure Perl driver is surprisingly simple. However, there are
some problems you should be aware of. The best option is of course
picking up an existing driver and carefully modifying one method
after the other.

Also look carefully at B<DBD::AnyData> and B<DBD::Template>.

As an example we take a look at the B<DBD::File> driver, a driver for
accessing plain files as tables, which is part of the B<DBD::CSV> package.

The minimal set of files we have to implement are F<Makefile.PL>,
F<README>, F<MANIFEST> and F<Driver.pm>.

=head2 Pure Perl version of Makefile.PL

You typically start with writing F<Makefile.PL>, a Makefile
generator. The contents of this file are described in detail in
the L<ExtUtils::MakeMaker> man pages. It is definitely a good idea
if you start reading them. At least you should know about the
variables I<CONFIGURE>, I<DEFINED>, I<PM>, I<DIR>, I<EXE_FILES>,
I<INC>, I<LIBS>, I<LINKTYPE>, I<NAME>, I<OPTIMIZE>, I<PL_FILES>,
I<VERSION>, I<VERSION_FROM>, I<clean>, I<depend>, I<realclean> from
the L<ExtUtils::MakeMaker> man page: these are used in almost any
F<Makefile.PL>.

Additionally read the section on I<Overriding MakeMaker Methods> and the
descriptions of the I<distcheck>, I<disttest> and I<dist> targets: They
will definitely be useful for you.

Of special importance for B<DBI> drivers is the I<postamble> method from
the L<ExtUtils::MM_Unix> man page.

For Emacs users, I recommend the I<libscan> method, which removes
Emacs backup files (file names which end with a tilde '~') from lists of
files.

Now an example, I use the word C<Driver> wherever you should insert
your driver's name:

  # -*- perl -*-

  use ExtUtils::MakeMaker;

  WriteMakefile(
      dbd_edit_mm_attribs( {
          'NAME'         => 'DBD::Driver',
          'VERSION_FROM' => 'Driver.pm',
          'INC'          => '',
          'dist'         => { 'SUFFIX'   => '.gz',
                              'COMPRESS' => 'gzip -9f' },
          'realclean'    => { FILES => '*.xsi' },
          'PREREQ_PM'    => '1.03',
          'CONFIGURE'    => sub {
              eval {require DBI::DBD;};
              if ($@) {
                  warn $@;
                  exit 0;
              }
              my $dbi_arch_dir = dbd_dbi_arch_dir();
              if (exists($opts{INC})) {
                  return {INC => "$opts{INC} -I$dbi_arch_dir"};
              } else {
                  return {INC => "-I$dbi_arch_dir"};
              }
          }
      },
      { create_pp_tests => 1})
  );

  package MY;
  sub postamble { return main::dbd_postamble(@_); }
  sub libscan {
      my ($self, $path) = @_;
      ($path =~ m/\~$/) ? undef : $path;
  }

Note the calls to C<dbd_edit_mm_attribs()> and C<dbd_postamble()>.

The second hash reference in the call to C<dbd_edit_mm_attribs()>
(containing C<create_pp_tests()>) is optional; you should not use it
unless your driver is a pure Perl driver (that is, it does not use C and
XS code). Therefore, the call to C<dbd_edit_mm_attribs()> is not
relevant for C/XS drivers and may be omitted; simply use the (single)
hash reference containing NAME etc as the only argument to C<WriteMakefile()>.

Note that the C<dbd_edit_mm_attribs()> code will fail if you do not have a
F<t> sub-directory containing at least one test case.

I<PREREQ_PM> tells MakeMaker that DBI (version 1.03 in this case) is
required for this module. This will issue a warning that DBI 1.03 is
missing if someone attempts to install your DBD without DBI 1.03. See
I<CONFIGURE> below for why this does not work reliably in stopping cpan
testers failing your module if DBI is not installed.

I<CONFIGURE> is a subroutine called by MakeMaker during
C<WriteMakefile>.  By putting the C<require DBI::DBD> in this section
we can attempt to load DBI::DBD but if it is missing we exit with
success. As we exit successfully without creating a Makefile when
DBI::DBD is missing cpan testers will not report a failure. This may
seem at odds with I<PREREQ_PM> but I<PREREQ_PM> does not cause
C<WriteMakefile> to fail (unless you also specify PREREQ_FATAL which
is strongly discouraged by MakeMaker) so C<WriteMakefile> would
continue to call C<dbd_dbi_arch_dir> and fail.

All drivers must use C<dbd_postamble()> or risk running into problems.

Note the specification of I<VERSION_FROM>; the named file
(F<Driver.pm>) will be scanned for the first line that looks like an
assignment to I<$VERSION>, and the subsequent text will be used to
determine the version number.  Note the commentary in
L<ExtUtils::MakeMaker> on the subject of correctly formatted version
numbers.

If your driver depends upon external software (it usually will), you
will need to add code to ensure that your environment is workable
before the call to C<WriteMakefile()>. If you need to check for the
existance of an external library and perhaps modify I<INC> to include
the paths to where the external library header files are located and
you cannot find the library or header files make sure you output a
message saying they cannot be found but C<exit 0> (success) B<before>
calling C<WriteMakefile> or CPAN testers will fail your module if the
external library is not found.

A full-fledged I<Makefile.PL> can be quite large (for example, the
files for B<DBD::Oracle> and B<DBD::Informix> are both over 1000 lines
long, and the Informix one uses - and creates - auxilliary modules
too).

See also L<ExtUtils::MakeMaker> and L<ExtUtils::MM_Unix>. Consider using
L<CPAN::MakeMaker> in place of I<ExtUtils::MakeMaker>.

=head2 README

The L<README> file should describe what the driver is for, the
pre-requisites for the build process, the actual build process, how to
report errors, and who to report them to.

Users will find ways of breaking the driver build and test process
which you would never even have dreamed to be possible in your worst
nightmares. Therefore, you need to write this document defensively,
precisely and concisely.

As always, use the F<README> from one of the established drivers as a basis
for your own; the version in B<DBD::Informix> is worth a look as it has
been quite successful in heading off problems.

=over 4

=item *

Note that users will have versions of Perl and B<DBI> that are both older
and newer than you expected, but this will seldom cause much trouble.
When it does, it will be because you are using features of B<DBI> that are
not supported in the version they are using.

=item *

Note that users will have versions of the database software that are
both older and newer than you expected. You will save yourself time in
the long run if you can identify the range of versions which have been
tested and warn about versions which are not known to be OK.

=item *

Note that many people trying to install your driver will not be experts
in the database software.

=item *

Note that many people trying to install your driver will not be experts
in C or Perl.

=back

=head2 MANIFEST

The F<MANIFEST> will be used by the Makefile's dist target to build the
distribution tar file that is uploaded to CPAN. It should list every
file that you want to include in your distribution, one per line.

=head2 lib/Bundle/DBD/Driver.pm

The CPAN module provides an extremely powerful bundle mechanism that
allows you to specify pre-requisites for your driver.

The primary pre-requisite is B<Bundle::DBI>; you may want or need to add
some more. With the bundle set up correctly, the user can type:

        perl -MCPAN -e 'install Bundle::DBD::Driver'

and Perl will download, compile, test and install all the Perl modules
needed to build your driver.

The prerequisite modules are listed in the C<CONTENTS> section, with the
official name of the module followed by a dash and an informal name or
description.

=over 4

=item *

Listing B<Bundle::DBI> as the main pre-requisite simplifies life.

=item *

Don't forget to list your driver.

=item *

Note that unless the DBMS is itself a Perl module, you cannot list it as
a pre-requisite in this file.

=item *

You should keep the version of the bundle the same as the version of
your driver.

=item *

You should add configuration management, copyright, and licencing
information at the top.

=back

A suitable skeleton for this file is shown below.

  package Bundle::DBD::Driver;

  $VERSION = '0.01';

  1;

  __END__

  =head1 NAME

  Bundle::DBD::Driver - A bundle to install all DBD::Driver related modules

  =head1 SYNOPSIS

  C<perl -MCPAN -e 'install Bundle::DBD::Driver'>

  =head1 CONTENTS

  Bundle::DBI  - Bundle for DBI by TIMB (Tim Bunce)

  DBD::Driver  - DBD::Driver by YOU (Your Name)

  =head1 DESCRIPTION

  This bundle includes all the modules used by the Perl Database
  Interface (DBI) driver for Driver (DBD::Driver), assuming the
  use of DBI version 1.13 or later, created by Tim Bunce.

  If you've not previously used the CPAN module to install any
  bundles, you will be interrogated during its setup phase.
  But when you've done it once, it remembers what you told it.
  You could start by running:

    C<perl -MCPAN -e 'install Bundle::CPAN'>

  =head1 SEE ALSO

  Bundle::DBI

  =head1 AUTHOR

  Your Name E<lt>F<you@yourdomain.com>E<gt>

  =head1 THANKS

  This bundle was created by ripping off Bundle::libnet created by
  Graham Barr E<lt>F<gbarr@ti.com>E<gt>, and radically simplified
  with some information from Jochen Wiedmann E<lt>F<joe@ispsoft.de>E<gt>.
  The template was then included in the DBI::DBD documentation by
  Jonathan Leffler E<lt>F<jleffler@informix.com>E<gt>.

  =cut

=head2 lib/DBD/Driver/Summary.pm

There is no substitute for taking the summary file from a driver that
was documented in the Perl book (such as B<DBD::Oracle> or B<DBD::Informix> or
B<DBD::ODBC>, to name but three), and adapting it to describe the
facilities available via B<DBD::Driver> when accessing the Driver database.

=head2 Pure Perl version of Driver.pm

The F<Driver.pm> file defines the Perl module B<DBD::Driver> for your driver.
It will define a package B<DBD::Driver> along with some version information,
some variable definitions, and a function C<driver()> which will have a more
or less standard structure.

It will also define three sub-packages of B<DBD::Driver>:

=over 4

=item DBD::Driver::dr

with methods C<connect()>, C<data_sources()> and C<disconnect_all()>;

=item DBD::Driver::db

with methods such as C<prepare()>;

=item DBD::Driver::st

with methods such as C<execute()> and C<fetch()>.

=back

The F<Driver.pm> file will also contain the documentation specific to
B<DBD::Driver> in the format used by perldoc.

In a pure Perl driver, the F<Driver.pm> file is the core of the
implementation. You will need to provide all the key methods needed by B<DBI>.

Now let's take a closer look at an excerpt of F<File.pm> as an example.
We ignore things that are common to any module (even non-DBI modules)
or really specific to the B<DBD::File> package.

=head3 The DBD::Driver package

=head4 The header

  package DBD::File;

  use strict;
  use vars qw($VERSION $drh);

  $VERSION = "1.23.00"  # Version number of DBD::File

This is where the version number of your driver is specified, and is
where F<Makefile.PL> looks for this information. Please ensure that any
other modules added with your driver are also version stamped so that
CPAN does not get confused.

It is recommended that you use a two-part (1.23) or three-part (1.23.45)
version number. Also consider the CPAN system, which gets confused and
considers version 1.10 to precede version 1.9, so that using a raw CVS,
RCS or SCCS version number is probably not appropriate (despite being
very common).

For Subversion you could use:

  $VERSION = sprintf("12.%06d", q$Revision: 12345 $ =~ /(\d+)/o);

(use lots of leading zeros on the second portion so if you move the code to a
shared repository like svn.perl.org the much larger revision numbers won't
cause a problem, at least not for a few years).  For RCS or CVS you can use:

  $VERSION = sprintf "%d.%02d", '$Revision: 11.21 $ ' =~ /(\d+)\.(\d+)/;

which pads out the fractional part with leading zeros so all is well
(so long as you don't go past x.99)

  $drh = undef;         # holds driver handle once initialized

This is where the driver handle will be stored, once created.
Note that you may assume there is only one handle for your driver.

=head4 The driver constructor

The C<driver()> method is the driver handle constructor. Note that
the C<driver()> method is in the B<DBD::Driver> package, not in
one of the sub-packages B<DBD::Driver::dr>, B<DBD::Driver::db>, or
B<DBD::Driver::db>.

  sub driver
  {
      return $drh if $drh;      # already created - return same one
      my ($class, $attr) = @_;

      $class .= "::dr";

      DBD::Driver::db->install_method('drv_example_dbh_method');
      DBD::Driver::st->install_method('drv_example_sth_method');

      # not a 'my' since we use it above to prevent multiple drivers
      $drh = DBI::_new_drh($class, {
              'Name'        => 'File',
              'Version'     => $VERSION,
              'Attribution' => 'DBD::File by Jochen Wiedmann',
          })
          or return undef;

      return $drh;
  }

This is a reasonable example of how B<DBI> implements its handles. There
are three kinds: B<driver handles> (typically stored in I<$drh>; from
now on called I<drh> or I<$drh>), B<database handles> (from now on
called I<dbh> or I<$dbh>) and B<statement handles> (from now on called
I<sth> or I<$sth>).

The prototype of C<DBI::_new_drh()> is

  $drh = DBI::_new_drh($class, $public_attrs, $private_attrs);

with the following arguments:

=over 4

=item I<$class>

is typically the class for your driver, (for example, "DBD::File::dr"),
passed as the first argument to the C<driver()> method.

=item I<$public_attrs>

is a hash ref to attributes like I<Name>, I<Version>, and I<Attribution>.
These are processed and used by B<DBI>. You had better not make any
assumptions about them nor should you add private attributes here.

=item I<$private_attrs>

This is another (optional) hash ref with your private attributes.
B<DBI> will store them and otherwise leave them alone.

=back

The C<DBI::_new_drh()> method and the C<driver()> method both return C<undef>
for failure (in which case you must look at I<$DBI::err> and I<$DBI::errstr>
for the failure information, because you have no driver handle to use).


=head4 Using install_method() to expose driver-private methods

    DBD::Foo::db->install_method($method_name, \%attr);

Installs the driver-private method named by $method_name into the
DBI method dispatcher so it can be called directly, avoiding the
need to use the func() method.

It is called as a static method on the driver class to which the
method belongs. The method name must begin with the corresponding
registered driver-private prefix. For example, for DBD::Oracle
$method_name must being with 'C<ora_>', and for DBD::AnyData it
must begin with 'C<ad_>'.

The attributes can be used to provide fine control over how the DBI
dispatcher handles the dispatching of the method. However, at this
point, it's undocumented and very liable to change. (Volunteers to
polish up and document the interface are very welcome to get in
touch via dbi-dev@perl.org)

Methods installed using install_method default to the standard error
handling behaviour for DBI methods: clearing err and errstr before
calling the method, and checking for errors to trigger RaiseError 
etc. on return. This differs from the default behaviour of func(). 

Note for driver authors: The DBD::Foo::xx->install_method call won't
work until the class-hierarchy has been setup. Normally the DBI
looks after that just after the driver is loaded. This means
install_method() can't be called at the time the driver is loaded
unless the class-hierarchy is set up first. The way to do that is
to call the setup_driver() method:

    DBI->setup_driver('DBD::Foo');

before using install_method().


=head4 The CLONE special subroutine

Also needed here, in the B<DBD::Driver> package, is a C<CLONE()> method
that will be called by perl when an intrepreter is cloned. All your
C<CLONE()> method needs to do, currently, is clear the cached I<$drh> so
the new interpreter won't start using the cached I<$drh> from the old
interpreter:

  sub CLONE {
    undef $drh;
  }

See L<http://search.cpan.org/dist/perl/pod/perlmod.pod#Making_your_module_threadsafe>
for details.

=head3 The DBD::Driver::dr package

The next lines of code look as follows:

  package DBD::Driver::dr; # ====== DRIVER ======

  $DBD::Driver::dr::imp_data_size = 0;

Note that no I<@ISA> is needed here, or for the other B<DBD::Driver::*>
classes, because the B<DBI> takes care of that for you when the driver is
loaded.

 *FIX ME* Explain what the imp_data_size is, so that implementors aren't
 practicing cargo-cult programming.

=head4 The database handle constructor

The database handle constructor is the driver's (hence the changed
namespace) C<connect()> method:

  sub connect
  {
      my ($drh, $dr_dsn, $user, $auth, $attr) = @_;

      # Some database specific verifications, default settings
      # and the like can go here. This should only include
      # syntax checks or similar stuff where it's legal to
      # 'die' in case of errors.
      # For example, many database packages requires specific
      # environment variables to be set; this could be where you
      # validate that they are set, or default them if they are not set.

      my $driver_prefix = "drv_"; # the assigned prefix for this driver

      # Process attributes from the DSN; we assume ODBC syntax
      # here, that is, the DSN looks like var1=val1;...;varN=valN
      foreach my $var ( split /;/, $dr_dsn ) {
          my ($attr_name, $attr_value) = split '=', $var, 2;
	  return $drh->set_err($DBI::stderr, "Can't parse DSN part '$var'")
              unless defined $attr_value;

          # add driver prefix to attribute name if it doesn't have it already
          $attr_name = $driver_prefix.$attr_name
              unless $attr_name =~ /^$driver_prefix/o;

	  # Store attribute into %$attr, replacing any existing value.
          # The DBI will STORE() these into $dbh after we've connected
	  $attr->{$attr_name} = $attr_value;
      }

      # Get the attributes we'll use to connect.
      # We use delete here because these no need to STORE them
      my $db = delete $attr->{drv_database} || delete $attr->{drv_db}
          or return $drh->set_err($DBI::stderr, "No database name given in DSN '$dr_dsn'");
      my $host = delete $attr->{drv_host} || 'localhost';
      my $port = delete $attr->{drv_port} || 123456;

      # Assume you can attach to your database via drv_connect:
      my $connection = drv_connect($db, $host, $port, $user, $auth)
          or return $drh->set_err($DBI::stderr, "Can't connect to $dr_dsn: ...");

      # create a 'blank' dbh (call superclass constructor)
      my ($outer, $dbh) = DBI::_new_dbh($drh, { Name => $dr_dsn });

      $dbh->STORE('Active', 1 );
      $dbh->{drv_connection} = $connection;

      return $outer;
  }

This is mostly the same as in the I<driver handle constructor> above.
The arguments are described in L<DBI>.

The constructor C<DBI::_new_dbh()> is called, returning a database handle.
The constructor's prototype is:

  ($outer, $inner) = DBI::_new_dbh($drh, $public_attr, $private_attr);

with similar arguments to those in the I<driver handle constructor>,
except that the I<$class> is replaced by I<$drh>. The I<Name> attribute
is a standard B<DBI> attribute (see L<DBI/Database Handle Attributes>).

In scalar context, only the outer handle is returned.

Note the use of the C<STORE()> method for setting the I<dbh> attributes.
That's because within the driver code, the handle object you have is
the 'inner' handle of a tied hash, not the outer handle that the
users of your driver have.

Because you have the inner handle, tie magic doesn't get invoked
when you get or set values in the hash. This is often very handy for
speed when you want to get or set simple non-special driver-specific
attributes.

However, some attribute values, such as those handled by the B<DBI> like
I<PrintError>, don't actually exist in the hash and must be read via
C<$h-E<gt>FETCH($attrib)> and set via C<$h-E<gt>STORE($attrib, $value)>.
If in any doubt, use these methods.

=head4 The data_sources() method

The C<data_sources()> method must populate and return a list of valid data
sources, prefixed with the "I<dbi:Driver>" incantation that allows them to
be used in the first argument of the C<DBI-E<gt>connect()> method.
An example of this might be scanning the F<$HOME/.odbcini> file on Unix
for ODBC data sources (DSNs).

As a trivial example, consider a fixed list of data sources:

  sub data_sources
  {
      my($drh, $attr) = @_;
      my(@list) = ();
      # You need more sophisticated code than this to set @list...
      push @list, "dbi:Driver:abc";
      push @list, "dbi:Driver:def";
      push @list, "dbi:Driver:ghi";
      # End of code to set @list
      return @list;
  }

=head4 The disconnect_all() method

If you need to release any resources when the driver is unloaded, you
can provide a disconnect_all method.

=head4 Other driver handle methods

If you need any other driver handle methods, they can follow here.

=head4 Error handling

It is quite likely that something fails in the connect method.
With B<DBD::File> for example, you might catch an error when setting the
current directory to something not existent by using the
(driver-specific) I<f_dir> attribute.

To report an error, you use the C<set_err()> method:

  $h->set_err($err, $errmsg, $state);

This will ensure that the error is recorded correctly and that
I<RaiseError> and I<PrintError> etc are handled correctly.

Typically you'll always use the method instance, aka your method's first
argument.

As C<set_err()> always returns C<undef> your error handling code can
usually be simplified to something like this:

  return $h->set_err($err, $errmsg, $state) if ...;

=head3 The DBD::Driver::db package

  package DBD::Driver::db; # ====== DATABASE ======

  $DBD::Driver::db::imp_data_size = 0;

=head4 The statement handle constructor

There's nothing much new in the statement handle constructor, which
is the C<prepare()> method:

  sub prepare
  {
      my ($dbh, $statement, @attribs) = @_;

      # create a 'blank' sth
      my ($outer, $sth) = DBI::_new_sth($dbh, { Statement => $statement });

      $sth->STORE('NUM_OF_PARAMS', ($statement =~ tr/?//));

      $sth->{drv_params} = [];

      return $outer;
  }

This is still the same -- check the arguments and call the super class
constructor C<DBI::_new_sth()>. Again, in scalar context, only the outer
handle is returned. The I<Statement> attribute should be cached as
shown.

Note the prefix I<drv_> in the attribute names: it is required that
all your private attributes use a lowercase prefix unique to your driver.
As mentioned earlier in this document, the B<DBI> contains a registry of
known driver prefixes and may one day warn about unknown attributes
that don't have a registered prefix.

Note that we parse the statement here in order to set the attribute
I<NUM_OF_PARAMS>. The technique illustrated is not very reliable; it can
be confused by question marks appearing in quoted strings, delimited
identifiers or in SQL comments that are part of the SQL statement. We
could set I<NUM_OF_PARAMS> in the C<execute()> method instead because
the B<DBI> specification explicitly allows a driver to defer this, but then
the user could not call C<bind_param()>.

=head4 Transaction handling

Pure Perl drivers will rarely support transactions. Thus your C<commit()>
and C<rollback()> methods will typically be quite simple:

  sub commit
  {
      my ($dbh) = @_;
      if ($dbh->FETCH('Warn')) {
          warn("Commit ineffective while AutoCommit is on");
      }
      0;
  }

  sub rollback {
      my ($dbh) = @_;
      if ($dbh->FETCH('Warn')) {
          warn("Rollback ineffective while AutoCommit is on");
      }
      0;
  }

Or even simpler, just use the default methods provided by the B<DBI> that
do nothing except return C<undef>.

The B<DBI>'s default C<begin_work()> method can be used by inheritance.

=head4 The STORE() and FETCH() methods

These methods (that we have already used, see above) are called for
you, whenever the user does a:

  $dbh->{$attr} = $val;

or, respectively,

  $val = $dbh->{$attr};

See L<perltie> for details on tied hash refs to understand why these
methods are required.

The B<DBI> will handle most attributes for you, in particular attributes
like I<RaiseError> or I<PrintError>. All you have to do is handle your
driver's private attributes and any attributes, like I<AutoCommit> and
I<ChopBlanks>, that the B<DBI> can't handle for you.

A good example might look like this:

  sub STORE
  {
      my ($dbh, $attr, $val) = @_;
      if ($attr eq 'AutoCommit') {
          # AutoCommit is currently the only standard attribute we have
          # to consider.
          if (!$val) { die "Can't disable AutoCommit"; }
          return 1;
      }
      if ($attr =~ m/^drv_/) {
          # Handle only our private attributes here
          # Note that we could trigger arbitrary actions.
          # Ideally we should warn about unknown attributes.
          $dbh->{$attr} = $val; # Yes, we are allowed to do this,
          return 1;             # but only for our private attributes
      }
      # Else pass up to DBI to handle for us
      $dbh->SUPER::STORE($attr, $val);
  }

  sub FETCH
  {
      my ($dbh, $attr) = @_;
      if ($attr eq 'AutoCommit') { return 1; }
      if ($attr =~ m/^drv_/) {
          # Handle only our private attributes here
          # Note that we could trigger arbitrary actions.
          return $dbh->{$attr}; # Yes, we are allowed to do this,
                                # but only for our private attributes
      }
      # Else pass up to DBI to handle
      $dbh->SUPER::FETCH($attr);
  }

The B<DBI> will actually store and fetch driver-specific attributes (with all
lowercase names) without warning or error, so there's actually no need to
implement driver-specific any code in your C<FETCH()> and C<STORE()>
methods unless you need extra logic/checks, beyond getting or setting
the value.

Unless your driver documentation indicates otherwise, the return value of
the C<STORE()> method is unspecified and the caller shouldn't use that value.

=head4 Other database handle methods

As with the driver package, other database handle methods may follow here.
In particular you should consider a (possibly empty) C<disconnect()>
method and possibly a C<quote()> method if B<DBI>'s default isn't correct for
you. You may also need the C<type_info_all()> and C<get_info()> methods,
as described elsewhere in this document.

Where reasonable use C<$h-E<gt>SUPER::foo()> to call the B<DBI>'s method in
some or all cases and just wrap your custom behavior around that.

If you want to use private trace flags you'll probably want to be
able to set them by name. To do that you'll need to define a
C<parse_trace_flag()> method (note that's "parse_trace_flag", singular,
not "parse_trace_flags", plural).

  sub parse_trace_flag {
      my ($h, $name) = @_;
      return 0x01000000 if $name eq 'foo';
      return 0x02000000 if $name eq 'bar';
      return 0x04000000 if $name eq 'baz';
      return 0x08000000 if $name eq 'boo';
      return 0x10000000 if $name eq 'bop';
      return $h->SUPER::parse_trace_flag($name);
  }

All private flag names must be lowercase, and all private flags
must be in the top 8 of the 32 bits.

=head3 The DBD::Driver::st package

This package follows the same pattern the others do:

  package DBD::Driver::st;

  $DBD::Driver::st::imp_data_size = 0;

=head4 The execute() and bind_param() methods

This is perhaps the most difficult method because we have to consider
parameter bindings here. In addition to that, there are a number of
statement attributes which must be set for inherited B<DBI> methods to
function correctly (see L</Statement attributes> below).

We present a simplified implementation by using the I<drv_params>
attribute from above:

  sub bind_param
  {
      my ($sth, $pNum, $val, $attr) = @_;
      my $type = (ref $attr) ? $attr->{TYPE} : $attr;
      if ($type) {
          my $dbh = $sth->{Database};
          $val = $dbh->quote($sth, $type);
      }
      my $params = $sth->{drv_params};
      $params->[$pNum-1] = $val;
      1;
  }

  sub execute
  {
      my ($sth, @bind_values) = @_;

      # start of by finishing any previous execution if still active
      $sth->finish if $sth->FETCH('Active');

      my $params = (@bind_values) ?
          \@bind_values : $sth->{drv_params};
      my $numParam = $sth->FETCH('NUM_OF_PARAMS');
      return $sth->set_err($DBI::stderr, "Wrong number of parameters")
          if @$params != $numParam;
      my $statement = $sth->{'Statement'};
      for (my $i = 0;  $i < $numParam;  $i++) {
          $statement =~ s/?/$params->[$i]/; # XXX doesn't deal with quoting etc!
      }
      # Do anything ... we assume that an array ref of rows is
      # created and store it:
      $sth->{'drv_data'} = $data;
      $sth->{'drv_rows'} = @$data; # number of rows
      $sth->STORE('NUM_OF_FIELDS') = $numFields;
      $sth->{Active} = 1;
      @$data || '0E0';
  }

There are a number of things you should note here.

We initialize the I<NUM_OF_FIELDS> and I<Active> attributes here,
because they are essential for C<bind_columns()> to work.

We use attribute C<$sth-E<gt>{Statement}> which we created
within C<prepare()>. The attribute C<$sth-E<gt>{Database}>, which is
nothing else than the I<dbh>, was automatically created by B<DBI>.

Finally, note that (as specified in the B<DBI> specification) we return the
string C<'0E0'> instead of the number 0, so that the result tests true but
equal to zero.

  $sth->execute() or die $sth->errstr;

=head4 The execute_array(), execute_for_fetch() and bind_param_array() methods

In general, DBD's only need to implement C<execute_for_fetch()> and
C<bind_param_array>. DBI's default C<execute_array()> will invoke the
DBD's C<execute_for_fetch()> as needed.

The following sequence describes the interaction between
DBI C<execute_array> and a DBD's C<execute_for_fetch>:

=over

=item 1

App calls C<$sth-E<gt>execute_array(\%attrs, @array_of_arrays)>

=item 2

If C<@array_of_arrays> was specified, DBI processes C<@array_of_arrays> by calling
DBD's C<bind_param_array()>. Alternately, App may have directly called
C<bind_param_array()>

=item 3

DBD validates and binds each array

=item 4

DBI retrieves the validated param arrays from DBD's ParamArray attribute

=item 5

DBI calls DBD's C<execute_for_fetch($fetch_tuple_sub, \@tuple_status)>,
where C<&$fetch_tuple_sub> is a closure to iterate over the
returned ParamArray values, and C<\@tuple_status> is an array to receive
the disposition status of each tuple.

=item 6

DBD iteratively calls C<&$fetch_tuple_sub> to retrieve parameter tuples
to be added to its bulk database operation/request.

=item 7

when DBD reaches the limit of tuples it can handle in a single database
operation/request, or the C<&$fetch_tuple_sub> indicates no more
tuples by returning undef, the DBD executes the bulk operation, and
reports the disposition of each tuple in \@tuple_status.

=item 8

DBD repeats steps 6 and 7 until all tuples are processed.

=back

E.g., here's the essence of L<DBD::Oracle>'s execute_for_fetch:

       while (1) {
           my @tuple_batch;
           for (my $i = 0; $i < $batch_size; $i++) {
                push @tuple_batch, [ @{$fetch_tuple_sub->() || last} ];
           }
           last unless @tuple_batch;
           my $res = ora_execute_array($sth, \@tuple_batch,
              scalar(@tuple_batch), $tuple_batch_status);
           push @$tuple_status, @$tuple_batch_status;
       }

Note that DBI's default execute_array()/execute_for_fetch() implementation
requires the use of positional (i.e., '?') placeholders. Drivers
which B<require> named placeholders must either emulate positional
placeholders (e.g., see L<DBD::Oracle>), or must implement their own
execute_array()/execute_for_fetch() methods to properly sequence bound
parameter arrays.

=head4 Fetching data

Only one method needs to be written for fetching data, C<fetchrow_arrayref()>.
The other methods, C<fetchrow_array()>, C<fetchall_arrayref()>, etc, as well
as the database handle's C<select*> methods are part of B<DBI>, and call
C<fetchrow_arrayref()> as necessary.

  sub fetchrow_arrayref
  {
      my ($sth) = @_;
      my $data = $sth->{drv_data};
      my $row = shift @$data;
      if (!$row) {
          $sth->STORE(Active => 0); # mark as no longer active
          return undef;
      }
      if ($sth->FETCH('ChopBlanks')) {
          map { $_ =~ s/\s+$//; } @$row;
      }
      return $sth->_set_fbav($row);
  }
  *fetch = \&fetchrow_arrayref; # required alias for fetchrow_arrayref

Note the use of the method C<_set_fbav()> -- this is required so that
C<bind_col()> and C<bind_columns()> work.

If an error occurs which leaves the I<$sth> in a state where remaining rows
can't be fetched then I<Active> should be turned off before the method returns.

The C<rows()> method for this driver can be implemented like this:

  sub rows { shift->{drv_rows} }

because it knows in advance how many rows it has fetched.
Alternatively you could delete that method and so fallback
to the B<DBI>'s own method which does the right thing based
on the number of calls to C<_set_fbav()>.

=head4 The more_results method

If your driver doesn't support multiple result sets, then don't even implement this method.

Otherwise, this method needs to get the statement handle ready to fetch results
from the next result set, if there is one. Typically you'd start with:

    $sth->finish;

then you should delete all the attributes from the attribute cache that may no
longer be relevant for the new result set:

    delete $sth->{$_}
        for qw(NAME TYPE PRECISION SCALE ...);

for drivers written in C use:

    hv_delete((HV*)SvRV(sth), "NAME", 4, G_DISCARD);
    hv_delete((HV*)SvRV(sth), "NULLABLE", 8, G_DISCARD);
    hv_delete((HV*)SvRV(sth), "NUM_OF_FIELDS", 13, G_DISCARD);
    hv_delete((HV*)SvRV(sth), "PRECISION", 9, G_DISCARD);
    hv_delete((HV*)SvRV(sth), "SCALE", 5, G_DISCARD);
    hv_delete((HV*)SvRV(sth), "TYPE", 4, G_DISCARD);

Don't forget to also delete, or update, any driver-private attributes that may
not be correct for the next resultset.

The NUM_OF_FIELDS attribute is a special case. It should be set using STORE:

    $sth->STORE(NUM_OF_FIELDS => 0); /* for DBI <= 1.53 */
    $sth->STORE(NUM_OF_FIELDS => $new_value);

for drivers written in C use this incantation:

    /* Adjust NUM_OF_FIELDS - which also adjusts the row buffer size */
    DBIc_NUM_FIELDS(imp_sth) = 0; /* for DBI <= 1.53 */
    DBIc_STATE(imp_xxh)->set_attr_k(sth, sv_2mortal(newSVpvn("NUM_OF_FIELDS",13)), 0,
        sv_2mortal(newSViv(mysql_num_fields(imp_sth->result)))
    );

For DBI versions prior to 1.54 you'll also need to explicitly adjust the
number of elements in the row buffer array (C<DBIc_FIELDS_AV(imp_sth)>)
to match the new result set. Fill any new values with newSV(0) not &sv_undef.
Alternatively you could free DBIc_FIELDS_AV(imp_sth) and set it to null,
but that would mean bind_columns() woudn't work across result sets.


=head4 Statement attributes

The main difference between I<dbh> and I<sth> attributes is, that you
should implement a lot of attributes here that are required by
the B<DBI>, such as I<NAME>, I<NULLABLE>, I<TYPE>, etc. See
L<DBI/Statement Handle Attributes> for a complete list.

Pay attention to attributes which are marked as read only, such as
I<NUM_OF_PARAMS>. These attributes can only be set the first time
a statement is executed. If a statement is prepared, then executed
multiple times, warnings may be generated.

You can protect against these warnings, and prevent the recalculation
of attributes which might be expensive to calculate (such as the
I<NAME> and I<NAME_*> attributes):

    my $storedNumParams = $sth->FETCH('NUM_OF_PARAMS');
    if (!defined $storedNumParams or $storedNumFields < 0) {
        $sth->STORE('NUM_OF_PARAMS') = $numParams;

        # Set other useful attributes that only need to be set once
        # for a statement, like $sth->{NAME} and $sth->{TYPE}
    }

One particularly important attribute to set correctly (mentioned in
L<DBI/ATTRIBUTES COMMON TO ALL HANDLES> is I<Active>. Many B<DBI> methods,
including C<bind_columns()>, depend on this attribute.

Besides that the C<STORE()> and C<FETCH()> methods are mainly the same
as above for I<dbh>'s.

=head4 Other statement methods

A trivial C<finish()> method to discard stored data, reset any attributes
(such as I<Active>) and do C<$sth-E<gt>SUPER::finish()>.

If you've defined a C<parse_trace_flag()> method in B<::db> you'll also want
it in B<::st>, so just alias it in:

  *parse_trace_flag = \&DBD::foo:db::parse_trace_flag;

And perhaps some other methods that are not part of the B<DBI>
specification, in particular to make metadata available.
Remember that they must have names that begin with your drivers
registered prefix so they can be installed using C<install_method()>.

If C<DESTROY()> is called on a statement handle that's still active
(C<$sth-E<gt>{Active}> is true) then it should effectively call C<finish()>.

    sub DESTROY {
        my $sth = shift;
        $sth->finish if $sth->FETCH('Active');
    }

=head2 Tests

The test process should conform as closely as possibly to the Perl
standard test harness.

In particular, most (all) of the tests should be run in the F<t> sub-directory,
and should simply produce an C<ok> when run under C<make test>.
For details on how this is done, see the Camel book and the section in
Chapter 7, "The Standard Perl Library" on L<Test::Harness>.

The tests may need to adapt to the type of database which is being used
for testing, and to the privileges of the user testing the driver. For
example, the B<DBD::Informix> test code has to adapt in a number of
places to the type of database to which it is connected as different
Informix databases have different capabilities: some of the tests are
for databases without transaction logs; others are for databases with a
transaction log; some versions of the server have support for blobs, or
stored procedures, or user-defined data types, and others do not.

When a complete file of tests must be skipped, you can provide a reason
in a pseudo-comment:

    if ($no_transactions_available)
    {
        print "1..0 # Skip: No transactions available\n";
        exit 0;
    }

Consider downloading the B<DBD::Informix> code and look at the code in
F<DBD/Informix/TestHarness.pm> which is used throughout the
B<DBD::Informix> tests in the F<t> sub-directory.

=head1 CREATING A C/XS DRIVER

Please also see the section under L<CREATING A PURE PERL DRIVER>
regarding the creation of the F<Makefile.PL>.

Creating a new C/XS driver from scratch will always be a daunting task.
You can and should greatly simplify your task by taking a good
reference driver implementation and modifying that to match the
database product for which you are writing a driver.

The de facto reference driver has been the one for B<DBD::Oracle> written
by Tim Bunce, who is also the author of the B<DBI> package. The B<DBD::Oracle>
module is a good example of a driver implemented around a C-level API.

Nowadays it it seems better to base on B<DBD::ODBC>, another driver
maintained by Tim and Jeff Urlwin, because it offers a lot of metadata
and seems to become the guideline for the future development. (Also as
B<DBD::Oracle> digs deeper into the Oracle 8 OCI interface it'll get even
more hairy than it is now.)

The B<DBD::Informix> driver is one driver implemented using embedded SQL
instead of a function-based API.
B<DBD::Ingres> may also be worth a look.

=head2 C/XS version of Driver.pm

A lot of the code in the F<Driver.pm> file is very similar to the code for pure Perl modules
- see above.  However,
there are also some subtle (and not so subtle) differences, including:

=over 8

=item *

The variables I<$DBD::Driver::{dr|db|st}::imp_data_size> are not defined
here, but in the XS code, because they declare the size of certain
C structures.

=item *

Some methods are typically moved to the XS code, in particular
C<prepare()>, C<execute()>, C<disconnect()>, C<disconnect_all()> and the
C<STORE()> and C<FETCH()> methods.

=item *

Other methods are still part of F<Driver.pm>, but have callbacks to
the XS code.

=item *

If the driver-specific parts of the I<imp_drh_t> structure need to be
formally initialized (which does not seem to be a common requirement),
then you need to add a call to an appropriate XS function in the driver
method of C<DBD::Driver::driver()>, and you define the corresponding function
in F<Driver.xs>, and you define the C code in F<dbdimp.c> and the prototype in
F<dbdimp.h>.

For example, B<DBD::Informix> has such a requirement, and adds the
following call after the call to C<_new_drh()> in F<Informix.pm>:

  DBD::Informix::dr::driver_init($drh);

and the following code in F<Informix.xs>:

  # Initialize the DBD::Informix driver data structure
  void
  driver_init(drh)
      SV *drh
      CODE:
      ST(0) = dbd_ix_dr_driver_init(drh) ? &sv_yes : &sv_no;

and the code in F<dbdimp.h> declares:

  extern int dbd_ix_dr_driver_init(SV *drh);

and the code in F<dbdimp.ec> (equivalent to F<dbdimp.c>) defines:

  /* Formally initialize the DBD::Informix driver structure */
  int
  dbd_ix_dr_driver(SV *drh)
  {
      D_imp_drh(drh);
      imp_drh->n_connections = 0;       /* No active connections */
      imp_drh->current_connection = 0;  /* No current connection */
      imp_drh->multipleconnections = (ESQLC_VERSION >= 600) ? True : False;
      dbd_ix_link_newhead(&imp_drh->head);  /* Empty linked list of connections */
      return 1;
  }

B<DBD::Oracle> has a similar requirement but gets around it by checking
whether the private data part of the driver handle is all zeroed out,
rather than add extra functions.

=back

Now let's take a closer look at an excerpt from F<Oracle.pm> (revised
heavily to remove idiosyncrasies) as an example, ignoring things that
were already discussed for pure Perl drivers.

=head3 The connect method

The connect method is the database handle constructor.
You could write either of two versions of this method: either one which
takes connection attributes (new code) and one which ignores them (old
code only).

If you ignore the connection attributes, then you omit all mention of
the I<$auth> variable (which is a reference to a hash of attributes), and
the XS system manages the differences for you.

  sub connect
  {
      my ($drh, $dbname, $user, $auth, $attr) = @_;

      # Some database specific verifications, default settings
      # and the like following here. This should only include
      # syntax checks or similar stuff where it's legal to
      # 'die' in case of errors.

      my $dbh = DBI::_new_dbh($drh, {
              'Name'   => $dbname,
          })
          or return undef;

      # Call the driver-specific function _login in Driver.xs file which
      # calls the DBMS-specific function(s) to connect to the database,
      # and populate internal handle data.
      DBD::Driver::db::_login($dbh, $dbname, $user, $auth, $attr)
          or return undef;

      $dbh;
  }

This is mostly the same as in the pure Perl case, the exception being
the use of the private C<_login()> callback, which is the function that
will really connect to the database. It is implemented in F<Driver.xst>
(you should not implement it) and calls C<dbd_db_login6()> from
F<dbdimp.c>. See below for details.

 *FIX ME* Discuss removing attributes from hash reference as an optimization
 to skip later calls to $dbh->STORE made by DBI->connect.

 *FIX ME* Discuss removing attributes in Perl code.

 *FIX ME* Discuss removing attributes in C code.

=head3 The disconnect_all method

 *FIX ME* T.B.S

=head3 The data_sources method

If your C<data_sources()> method can be implemented in pure Perl, then do
so because it is easier than doing it in XS code (see the section above
for pure Perl drivers).

If your C<data_sources()> method must call onto compiled functions, then
you will need to define I<dbd_dr_data_sources> in your F<dbdimp.h> file, which
will trigger F<Driver.xst> (in B<DBI> v1.33 or greater) to generate the XS
code that calls your actual C function (see the discussion below for
details) and you do not code anything in F<Driver.pm> to handle it.

=head3 The prepare method

The prepare method is the statement handle constructor, and most of it
is not new. Like the C<connect()> method, it now has a C callback:

  package DBD::Driver::db; # ====== DATABASE ======
  use strict;

  sub prepare
  {
      my ($dbh, $statement, $attribs) = @_;

      # create a 'blank' sth
      my $sth = DBI::_new_sth($dbh, {
          'Statement' => $statement,
          })
          or return undef;

      # Call the driver-specific function _prepare in Driver.xs file
      # which calls the DBMS-specific function(s) to prepare a statement
      # and populate internal handle data.
      DBD::Driver::st::_prepare($sth, $statement, $attribs)
          or return undef;
      $sth;
  }

=head3 The execute method

 *FIX ME* T.B.S

=head3 The fetchrow_arrayref method

 *FIX ME* T.B.S

=head3 Other methods?

 *FIX ME* T.B.S

=head2 Driver.xs

F<Driver.xs> should look something like this:

  #include "Driver.h"

  DBISTATE_DECLARE;

  INCLUDE: Driver.xsi

  MODULE = DBD::Driver    PACKAGE = DBD::Driver::dr

  /* Non-standard drh XS methods following here, if any.       */
  /* If none (the usual case), omit the MODULE line above too. */

  MODULE = DBD::Driver    PACKAGE = DBD::Driver::db

  /* Non-standard dbh XS methods following here, if any.       */
  /* Currently this includes things like _list_tables from     */
  /* DBD::mSQL and DBD::mysql.                                 */

  MODULE = DBD::Driver    PACKAGE = DBD::Driver::st

  /* Non-standard sth XS methods following here, if any.       */
  /* In particular this includes things like _list_fields from */
  /* DBD::mSQL and DBD::mysql for accessing metadata.          */

Note especially the include of F<Driver.xsi> here: B<DBI> inserts stub
functions for almost all private methods here which will typically do
much work for you.

Wherever you really have to implement something, it will call a private
function in F<dbdimp.c>, and this is what you have to implement.

You need to set up an extra routine if your driver needs to export
constants of its own, analogous to the SQL types available when you say:

  use DBI qw(:sql_types);

 *FIX ME* T.B.S

=head2 Driver.h

F<Driver.h> is very simple and the operational contents should look like this:

  #ifndef DRIVER_H_INCLUDED
  #define DRIVER_H_INCLUDED

  #define NEED_DBIXS_VERSION 93    /* 93 for DBI versions 1.00 to 1.51+ */
  #define PERL_NO_GET_CONTEXT      /* if used require DBI 1.51+ */

  #include <DBIXS.h>      /* installed by the DBI module  */

  #include "dbdimp.h"

  #include "dbivport.h"   /* see below                    */

  #include <dbd_xsh.h>    /* installed by the DBI module  */

  #endif /* DRIVER_H_INCLUDED */

The F<DBIXS.h> header defines most of the interesting information that
the writer of a driver needs.

The file F<dbd_xsh.h> header provides prototype declarations for the
C functions that you might decide to implement. Note that you should
normally only define one of C<dbd_db_login()> and C<dbd_db_login6()>
unless you are intent on supporting really old versions of B<DBI>
(prior to B<DBI> 1.06) as well as modern versions. The only standard,
B<DBI>-mandated functions that you need write are those specified in the
F<dbd_xsh.h> header. You might also add extra driver-specific functions
in F<Driver.xs>.

The F<dbivport.h> file should be I<copied> from the latest B<DBI> release
into your distribution each time you modify your driver. Its job is to
allow you to enhance your code to work with the latest B<DBI> API while
still allowing your driver to be compiled and used with older versions
of the B<DBI> (for example, when the C<DBIh_SET_ERR_CHAR()> macro was added
to B<DBI> 1.41, an emulation of it was added to F<dbivport.h>). This makes
users happy and your life easier. Always read the notes in F<dbivport.h>
to check for any limitations in the emulation that you should be aware
of.

With B<DBI> v1.51 or better I recommend that the driver defines
I<PERL_NO_GET_CONTEXT> before F<DBIXS.h> is included. This can significantly
improve efficiency when running under a thread enabled perl. (Remember that
the standard perl in most Linux distributions is built with threads enabled.
So is ActiveState perl for Windows, and perl built for Apache mod_perl2.)
If you do this there are some things to keep in mind:

=over 4

=item *

If I<PERL_NO_GET_CONTEXT> is defined, then every function that calls the Perl
API will need to start out with a C<dTHX;> declaration.

=item *

You'll know which functions need this, because the C compiler will
complain that the undeclared identifier C<my_perl> is used if I<and only if>
the perl you are using to develop and test your driver has threads enabled.

=item *

If you don't remember to test with a thread-enabled perl before making
a release it's likely that you'll get failure reports from users who are.

=item *

For driver private functions it is possible to gain even more
efficiency by replacing C<dTHX;> with C<pTHX_> prepended to the
parameter list and then C<aTHX_> prepended to the argument list where
the function is called.

=back

See L<perlguts/How multiple interpreters and concurrency are supported> for
additional information about I<PERL_NO_GET_CONTEXT>.

=head2 Implementation header dbdimp.h

This header file has two jobs:

First it defines data structures for your private part of the handles.

Second it defines macros that rename the generic names like
C<dbd_db_login()> to database specific names like C<ora_db_login()>. This
avoids name clashes and enables use of different drivers when you work
with a statically linked perl.

It also will have the important task of disabling XS methods that you
don't want to implement.

Finally, the macros will also be used to select alternate
implementations of some functions. For example, the C<dbd_db_login()>
function is not passed the attribute hash.

Since B<DBI> v1.06, if a C<dbd_db_login6()> macro is defined (for a function
with 6 arguments), it will be used instead with the attribute hash
passed as the sixth argument.

People used to just pick Oracle's F<dbdimp.c> and use the same names,
structures and types. I strongly recommend against that. At first glance
this saves time, but your implementation will be less readable. It was
just hell when I had to separate B<DBI> specific parts, Oracle specific
parts, mSQL specific parts and mysql specific parts in B<DBD::mysql>'s
I<dbdimp.h> and I<dbdimp.c>. (B<DBD::mysql> was a port of B<DBD::mSQL>
which was based on B<DBD::Oracle>.) [Seconded, based on the experience
taking B<DBD::Informix> apart, even though the version inherited in 1996
was only based on B<DBD::Oracle>.]

This part of the driver is I<your exclusive part>. Rewrite it from
scratch, so it will be clean and short: in other words, a better piece
of code. (Of course keep an eye on other people's work.)

  struct imp_drh_st {
      dbih_drc_t com;           /* MUST be first element in structure   */
      /* Insert your driver handle attributes here */
  };

  struct imp_dbh_st {
      dbih_dbc_t com;           /* MUST be first element in structure   */
      /* Insert your database handle attributes here */
  };

  struct imp_sth_st {
      dbih_stc_t com;           /* MUST be first element in structure   */
      /* Insert your statement handle attributes here */
  };

  /*  Rename functions for avoiding name clashes; prototypes are  */
  /*  in dbd_xst.h                                                */
  #define dbd_init         drv_dr_init
  #define dbd_db_login6    drv_db_login
  #define dbd_db_do        drv_db_do
  ... many more here ...

These structures implement your private part of the handles.

You I<have> to use the name C<imp_dbh_{dr|db|st}> and the first field
I<must> be of type I<dbih_drc_t|_dbc_t|_stc_t> and I<must> be called
C<com>.

You should never access these fields directly, except by using the
I<DBIc_xxx()> macros below.

=head2 Implementation source dbdimp.c

Conventionally, F<dbdimp.c> is the main implementation file (but
B<DBD::Informix> calls the file F<dbdimp.ec>). This section includes a
short note on each function that is used in the F<Driver.xsi> template
and thus I<has> to be implemented.

Of course, you will probably also need to implement other support
functions, which should usually be file static if they are placed in
F<dbdimp.c>. If they are placed in other files, you need to list those
files in F<Makefile.PL> (and F<MANIFEST>) to handle them correctly.

It is wise to adhere to a namespace convention for your functions to
avoid conflicts. For example, for a driver with prefix I<drv_>, you
might call externally visible functions I<dbd_drv_xxxx>. You should also
avoid non-constant global variables as much as possible to improve the
support for threading.

Since Perl requires support for function prototypes (ANSI or ISO or
Standard C), you should write your code using function prototypes too.

It is possible to use either the unmapped names such as C<dbd_init()> or
the mapped names such as C<dbd_ix_dr_init()> in the F<dbdimp.c> file.
B<DBD::Informix> uses the mapped names which makes it easier to identify
where to look for linkage problems at runtime (which will report errors
using the mapped names).

Most other drivers, and in particular B<DBD::Oracle>, use the unmapped
names in the source code which makes it a little easier to compare code
between drivers and eases discussions on the I<dbi-dev> mailing list.
The majority of the code fragments here will use the unmapped names.

Ultimately, you should provide implementations for most fo the functions
listed in the F<dbd_xsh.h> header. The exceptions are optional functions
(such as C<dbd_st_rows()>) and those functions with alternative
signatures, such as C<dbd_db_login6()> and I<dbd_db_login()>. Then you
should only implement one of the alternatives, and generally the newer
one of the alternatives.

=head3 The dbd_init method

  #include "Driver.h"

  DBISTATE_DECLARE;

  void dbd_init(dbistate_t* dbistate)
  {
      DBISTATE_INIT;  /*  Initialize the DBI macros  */
  }

The C<dbd_init()> function will be called when your driver is first
loaded; the bootstrap command in C<DBD::Driver::dr::driver()> triggers this,
and the call is generated in the I<BOOT> section of F<Driver.xst>.
These statements are needed to allow your driver to use the B<DBI> macros.
They will include your private header file F<dbdimp.h> in turn.
Note that I<DBISTATE_INIT> requires the name of the argument to C<dbd_init()>
to be called C<dbistate()>.

=head3 The dbd_drv_error method

You need a function to record errors so B<DBI> can access them properly.
You can call it whatever you like, but we'll call it C<dbd_drv_error()>
here.

The argument list depends on your database software; different systems
provide different ways to get at error information.

  static void dbd_drv_error(SV *h, int rc, const char *what)
  {

Note that I<h> is a generic handle, may it be a driver handle, a
database or a statement handle.

      D_imp_xxh(h);

This macro will declare and initialize a variable I<imp_xxh> with
a pointer to your private handle pointer. You may cast this to
to I<imp_drh_t>, I<imp_dbh_t> or I<imp_sth_t>.

To record the error correctly, equivalent to the C<set_err()> method,
use one of the C<DBIh_SET_ERR_CHAR(...)> or C<DBIh_SET_ERR_SV(...)> macros,
which were added in B<DBI> 1.41:

  DBIh_SET_ERR_SV(h, imp_xxh, err, errstr, state, method);
  DBIh_SET_ERR_CHAR(h, imp_xxh, err_c, err_i, errstr, state, method);

For C<DBIh_SET_ERR_SV> the I<err>, I<errstr>, I<state>, and I<method>
parameters are C<SV*>.

For C<DBIh_SET_ERR_CHAR> the I<err_c>, I<errstr>, I<state>, I<method>
parameters are C<char*>.

The I<err_i> parameter is an C<IV> that's used instead of I<err_c> if
I<err_c> is C<Null>.

The I<method> parameter can be ignored.

The C<DBIh_SET_ERR_CHAR> macro is usually the simplest to use when you
just have an integer error code and an error message string:

  DBIh_SET_ERR_CHAR(h, imp_xxh, Nullch, rc, what, Nullch, Nullch);

As you can see, any parameters that aren't relevant to you can be C<Null>.

To make drivers compatible with B<DBI> < 1.41 you should be using F<dbivport.h>
as described in L</Driver.h> above.

The (obsolete) macros such as C<DBIh_EVENT2> should be removed from drivers.

The names C<dbis> and C<DBIS>, which were used in previous versions of
this document, should be replaced with the C<DBIc_STATE(imp_xxh)> macro.

The name C<DBILOGFP>, which was also used in previous versions of this
document, should be replaced by C<DBIc_LOGPIO(imp_xxh)>.

Your code should not call the C C<E<lt>stdio.hE<gt>> I/O functions; you
should use C<PerlIO_printf()> as shown:

      if (DBIc_TRACE_LEVEL(imp_xxh) >= 2)
          PerlIO_printf(DBIc_LOGPIO(imp_xxh), "foobar %s: %s\n",
              foo, neatsvpv(errstr,0));

That's the first time we see how tracing works within a B<DBI> driver. Make
use of this as often as you can, but don't output anything at a trace
level less than 3. Levels 1 and 2 are reserved for the B<DBI>.

You can define up to 8 private trace flags using the top 8 bits
of C<DBIc_TRACE_FLAGS(imp)>, that is: C<0xFF000000>. See the
C<parse_trace_flag()> method elsewhere in this document.

=head3 The dbd_dr_data_sources method

This method is optional; the support for it was added in B<DBI> v1.33.

As noted in the discussion of F<Driver.pm>, if the data sources
can be determined by pure Perl code, do it that way. If, as in
B<DBD::Informix>, the information is obtained by a C function call, then
you need to define a function that matches the prototype:

  extern AV *dbd_dr_data_sources(SV *drh, imp_drh_t *imp_drh, SV *attrs);

An outline implementation for B<DBD::Informix> follows, assuming that the
C<sqgetdbs()> function call shown will return up to 100 databases names,
with the pointers to each name in the array dbsname and the name strings
themselves being stores in dbsarea.

  AV *dbd_dr_data_sources(SV *drh, imp_drh_t *imp_drh, SV *attr)
  {
      int ndbs;
      int i;
      char *dbsname[100];
      char  dbsarea[10000];
      AV *av = Nullav;

      if (sqgetdbs(&ndbs, dbsname, 100, dbsarea, sizeof(dbsarea)) == 0)
      {
          av = NewAV();
          av_extend(av, (I32)ndbs);
          sv_2mortal((SV *)av);
          for (i = 0; i < ndbs; i++)
            av_store(av, i, newSVpvf("dbi:Informix:%s", dbsname[i]));
      }
      return(av);
  }

The actual B<DBD::Informix> implementation has a number of extra lines of
code, logs function entry and exit, reports the error from C<sqgetdbs()>,
and uses C<#define>'d constants for the array sizes.

=head3 The dbd_db_login6 method

  int dbd_db_login6(SV* dbh, imp_dbh_t* imp_dbh, char* dbname,
                   char* user, char* auth, SV *attr);

This function will really connect to the database. The argument I<dbh>
is the database handle. I<imp_dbh> is the pointer to the handles private
data, as is I<imp_xxx> in C<dbd_drv_error()> above. The arguments
I<dbname>, I<user>, I<auth> and I<attr> correspond to the arguments of
the driver handle's C<connect()> method.

You will quite often use database specific attributes here, that are
specified in the DSN. I recommend you parse the DSN (using Perl) within
the C<connect()> method and pass the segments of the DSN via the
attributes parameter through C<_login()> to C<dbd_db_login6()>.

Here's how you fetch them; as an example we use I<hostname> attribute,
which can be up to 12 characters long excluding null terminator:

  SV** svp;
  STRLEN len;
  char* hostname;

  if ( (svp = DBD_ATTRIB_GET_SVP(attr, "drv_hostname", 12)) && SvTRUE(*svp)) {
      hostname = SvPV(*svp, len);
      DBD__ATTRIB_DELETE(attr, "drv_hostname", 12); /* avoid later STORE */
  } else {
      hostname = "localhost";
  }

Note that you can also obtain standard attributes such as I<AutoCommit> and
I<ChopBlanks> from the attributes parameter, using C<DBD_ATTRIB_GET_IV> for
integer attributes.

If, for example, your database does not support transactions but
I<AutoCommit> is set off (requesting transaction support), then you can
emulate a 'failure to connect'.

Now you should really connect to the database. In general, if the
connection fails, it is best to ensure that all allocated resources are
released so that the handle does not need to be destroyed separately. If
you are successful (and possibly even if you fail but you have allocated
some resources), you should use the following macros:

  DBIc_IMPSET_on(imp_dbh);

This indicates that the driver (implementor) has allocated resources in
the I<imp_dbh> structure and that the implementors private C<dbd_db_destroy()>
function should be called when the handle is destroyed.

  DBIc_ACTIVE_on(imp_dbh);

This indicates that the handle has an active connection to the server
and that the C<dbd_db_disconnect()> function should be called before the
handle is destroyed.

Note that if you do need to fail, you should report errors via the I<drh>
or I<imp_drh> rather than via I<dbh> or I<imp_dbh> because I<imp_dbh> will be
destroyed by the failure, so errors recorded in that handle will not be
visible to B<DBI>, and hence not the user either.

Note too, that the function is passed I<dbh> and I<imp_dbh>, and there
is a macro C<D_imp_drh_from_dbh> which can recover the I<imp_drh> from
the I<imp_dbh>. However, there is no B<DBI> macro to provide you with the
I<drh> given either the I<imp_dbh> or the I<dbh> or the I<imp_drh> (and
there's no way to recover the I<dbh> given just the I<imp_dbh>).

This suggests that, despite the above notes about C<dbd_drv_error()>
taking an C<SV *>, it may be better to have two error routines, one
taking I<imp_dbh> and one taking I<imp_drh> instead. With care, you can
factor most of the formatting code out so that these are small routines
calling a common error formatter. See the code in B<DBD::Informix>
1.05.00 for more information.

The C<dbd_db_login6()> function should return I<TRUE> for success,
I<FALSE> otherwise.

Drivers implemented long ago may define the five-argument function
C<dbd_db_login()> instead of C<dbd_db_login6()>. The missing argument is
the attributes. There are ways to work around the missing attributes,
but they are ungainly; it is much better to use the 6-argument form.

=head3 The dbd_db_commit and dbd_db_rollback methods

  int dbd_db_commit(SV *dbh, imp_dbh_t *imp_dbh);
  int dbd_db_rollback(SV* dbh, imp_dbh_t* imp_dbh);

These are used for commit and rollback. They should return I<TRUE> for
success, I<FALSE> for error.

The arguments I<dbh> and I<imp_dbh> are the same as for C<dbd_db_login6()>
above; I will omit describing them in what follows, as they appear
always.

These functions should return I<TRUE> for success, I<FALSE> otherwise.

=head3 The dbd_db_disconnect method

This is your private part of the C<disconnect()> method. Any I<dbh> with
the I<ACTIVE> flag on must be disconnected. (Note that you have to set
it in C<dbd_db_connect()> above.)

  int dbd_db_disconnect(SV* dbh, imp_dbh_t* imp_dbh);

The database handle will return I<TRUE> for success, I<FALSE> otherwise.
In any case it should do a:

  DBIc_ACTIVE_off(imp_dbh);

before returning so B<DBI> knows that C<dbd_db_disconnect()> was executed.

Note that there's nothing to stop a I<dbh> being I<disconnected> while
it still have active children. If your database API reacts badly to
trying to use an I<sth> in this situation then you'll need to add code
like this to all I<sth> methods:

  if (!DBIc_ACTIVE(DBIc_PARENT_COM(imp_sth)))
    return 0;

Alternatively, you can add code to your driver to keep explicit track of
the statement handles that exist for each database handle and arrange
to destroy those handles before disconnecting from the database. There
is code to do this in B<DBD::Informix>. Similar comments apply to the
driver handle keeping track of all the database handles.

Note that the code which destroys the subordinate handles should only
release the associated database resources and mark the handles inactive;
it does not attempt to free the actual handle structures.

This function should return I<TRUE> for success, I<FALSE> otherwise, but
it is not clear what anything can do about a failure.

=head3 The dbd_db_discon_all method

  int dbd_discon_all (SV *drh, imp_drh_t *imp_drh);

This function may be called at shutdown time. It should make
best-efforts to disconnect all database handles - if possible. Some
databases don't support that, in which case you can do nothing
but return 'success'.

This function should return I<TRUE> for success, I<FALSE> otherwise, but
it is not clear what anything can do about a failure.

=head3 The dbd_db_destroy method

This is your private part of the database handle destructor. Any I<dbh> with
the I<IMPSET> flag on must be destroyed, so that you can safely free
resources. (Note that you have to set it in C<dbd_db_connect()> above.)

  void dbd_db_destroy(SV* dbh, imp_dbh_t* imp_dbh)
  {
      DBIc_IMPSET_off(imp_dbh);
  }

The B<DBI> F<Driver.xst> code will have called C<dbd_db_disconnect()> for you,
if the handle is still 'active', before calling C<dbd_db_destroy()>.

Before returning the function must switch I<IMPSET> to off, so B<DBI> knows
that the destructor was called.

A B<DBI> handle doesn't keep references to its children. But children
do keep references to their parents. So a database handle won't be
C<DESTROY>'d until all its children have been C<DESTROY>'d.

=head3 The dbd_db_STORE_attrib method

This function handles

  $dbh->{$key} = $value;

Its prototype is:

  int dbd_db_STORE_attrib(SV* dbh, imp_dbh_t* imp_dbh, SV* keysv,
                          SV* valuesv);

You do not handle all attributes; on the contrary, you should not handle
B<DBI> attributes here: leave this to B<DBI>. (There are two exceptions,
I<AutoCommit> and I<ChopBlanks>, which you should care about.)

The return value is I<TRUE> if you have handled the attribute or I<FALSE>
otherwise. If you are handling an attribute and something fails, you
should call C<dbd_drv_error()>, so B<DBI> can raise exceptions, if desired.
If C<dbd_drv_error()> returns, however, you have a problem: the user will
never know about the error, because he typically will not check
C<$dbh-E<gt>errstr()>.

I cannot recommend a general way of going on, if C<dbd_drv_error()> returns,
but there are examples where even the B<DBI> specification expects that
you C<croak()>. (See the I<AutoCommit> method in L<DBI>.)

If you have to store attributes, you should either use your private
data structure I<imp_xxx>, the handle hash (via C<(HV*)SvRV(dbh)>), or use
the private I<imp_data>.

The first is best for internal C values like integers or pointers and
where speed is important within the driver. The handle hash is best for
values the user may want to get/set via driver-specific attributes.
The private I<imp_data> is an additional C<SV> attached to the handle. You
could think of it as an unnamed handle attribute. It's not normally used.

=head3 The dbd_db_FETCH_attrib method

This is the counterpart of C<dbd_db_STORE_attrib()>, needed for:

  $value = $dbh->{$key};

Its prototype is:

  SV* dbd_db_FETCH_attrib(SV* dbh, imp_dbh_t* imp_dbh, SV* keysv);

Unlike all previous methods this returns an C<SV> with the value. Note
that you should normally execute C<sv_2mortal()>, if you return a nonconstant
value. (Constant values are C<&sv_undef>, C<&sv_no> and C<&sv_yes>.)

Note, that B<DBI> implements a caching algorithm for attribute values.
If you think, that an attribute may be fetched, you store it in the
I<dbh> itself:

  if (cacheit) /* cache value for later DBI 'quick' fetch? */
      hv_store((HV*)SvRV(dbh), key, kl, cachesv, 0);

=head3 The dbd_st_prepare method

This is the private part of the C<prepare()> method. Note that you
B<must not> really execute the statement here. You may, however,
preparse and validate the statement, or do similar things.

  int dbd_st_prepare(SV* sth, imp_sth_t* imp_sth, char* statement,
                     SV* attribs);

A typical, simple, possibility is to do nothing and rely on the perl
C<prepare()> code that set the I<Statement> attribute on the handle. This
attribute can then be used by C<dbd_st_execute()>.

If the driver supports placeholders then the I<NUM_OF_PARAMS> attribute
must be set correctly by C<dbd_st_prepare()>:

  DBIc_NUM_PARAMS(imp_sth) = ...

If you can, you should also setup attributes like I<NUM_OF_FIELDS>, I<NAME>,
etc. here, but B<DBI> doesn't require that - they can be deferred until
execute() is called. However, if you do, document it.

In any case you should set the I<IMPSET> flag, as you did in
C<dbd_db_connect()> above:

  DBIc_IMPSET_on(imp_sth);

=head3 The dbd_st_execute method

This is where a statement will really be executed.

  int dbd_st_execute(SV* sth, imp_sth_t* imp_sth);

Note that you must be aware a statement may be executed repeatedly.
Also, you should not expect that C<finish()> will be called between two
executions, so you might need code, like the following, near the start
of the function:

  if (DBIc_ACTIVE(imp_sth))
      dbd_st_finish(h, imp_sth);

If your driver supports the binding of parameters (it should!), but the
database doesn't, you must do it here. This can be done as follows:

  SV *svp;
  char* statement = DBD_ATTRIB_GET_PV(h, "Statement", 9, svp, "");
  int numParam = DBIc_NUM_PARAMS(imp_sth);
  int i;

  for (i = 0; i < numParam; i++)
  {
      char* value = dbd_db_get_param(sth, imp_sth, i);
      /* It is your drivers task to implement dbd_db_get_param,    */
      /* it must be setup as a counterpart of dbd_bind_ph.         */
      /* Look for '?' and replace it with 'value'.  Difficult      */
      /* task, note that you may have question marks inside        */
      /* quotes and comments the like ...  :-(                     */
      /* See DBD::mysql for an example. (Don't look too deep into  */
      /* the example, you will notice where I was lazy ...)        */
  }

The next thing is to really execute the statement.

Note that you must set the attributes I<NUM_OF_FIELDS>, I<NAME>, etc
when the statement is successfully executed if the driver has not
already done so: they may be used even before a potential C<fetchrow()>.
In particular you have to tell B<DBI> the number of fields that the
statement has, because it will be used by B<DBI> internally. Thus the
function will typically ends with:

  if (isSelectStatement) {
      DBIc_NUM_FIELDS(imp_sth) = numFields;
      DBIc_ACTIVE_on(imp_sth);
  }

It is important that the I<ACTIVE> flag only be set for C<SELECT>
statements (or any other statements that can return many
values from the database using a cursor-like mechanism). See
C<dbd_db_connect()> above for more explanations.

There plans for a preparse function to be provided by B<DBI>, but this has
not reached fruition yet.
Meantime, if you want to know how ugly it can get, try looking at the
C<dbd_ix_preparse()> in B<DBD::Informix> F<dbdimp.ec> and the related
functions in F<iustoken.c> and F<sqltoken.c>.

=head3 The dbd_st_fetch method

This function fetches a row of data. The row is stored in in an array,
of C<SV>'s that B<DBI> prepares for you. This has two advantages: it is fast
(you even reuse the C<SV>'s, so they don't have to be created after the
first C<fetchrow()>), and it guarantees that B<DBI> handles C<bind_cols()> for
you.

What you do is the following:

  AV* av;
  int numFields = DBIc_NUM_FIELDS(imp_sth); /* Correct, if NUM_FIELDS
      is constant for this statement. There are drivers where this is
      not the case! */
  int chopBlanks = DBIc_is(imp_sth, DBIcf_ChopBlanks);
  int i;

  if (!fetch_new_row_of_data(...)) {
      ... /* check for error or end-of-data */
      DBIc_ACTIVE_off(imp_sth); /* turn off Active flag automatically */
      return Nullav;
  }
  /* get the fbav (field buffer array value) for this row       */
  /* it is very important to only call this after you know      */
  /* that you have a row of data to return.                     */
  av = DBIc_DBISTATE(imp_sth)->get_fbav(imp_sth);
  for (i = 0; i < numFields; i++) {
      SV* sv = fetch_a_field(..., i);
      if (chopBlanks && SvOK(sv) && type_is_blank_padded(field_type[i])) {
          /*  Remove white space from end (only) of sv  */
      }
      sv_setsv(AvARRAY(av)[i], sv); /* Note: (re)use! */
  }
  return av;

There's no need to use a C<fetch_a_field()> function returning an C<SV*>.
It's more common to use your database API functions to fetch the
data as character strings and use code like this:

  sv_setpvn(AvARRAY(av)[i], char_ptr, char_count);

C<NULL> values must be returned as C<undef>. You can use code like this:

  SvOK_off(AvARRAY(av)[i]);

The function returns the C<AV> prepared by B<DBI> for success or C<Nullav>
otherwise.

 *FIX ME* Discuss what happens when there's no more data to fetch.
 Are errors permitted if another fetch occurs after the first fetch
 that reports no more data. (Permitted, not required.)

If an error occurs which leaves the I<$sth> in a state where remaining
rows can't be fetched then I<Active> should be turned off before the
method returns.

=head3 The dbd_st_finish3 method

The C<$sth-E<gt>finish()> method can be called if the user wishes to
indicate that no more rows will be fetched even if the database has more
rows to offer, and the B<DBI> code can call the function when handles are
being destroyed. See the B<DBI> specification for more background details.

In both circumstances, the B<DBI> code ends up calling the
C<dbd_st_finish3()> method (if you provide a mapping for
C<dbd_st_finish3()> in F<dbdimp.h>), or C<dbd_st_finish()> otherwise.
The difference is that C<dbd_st_finish3()> takes a third argument which
is an C<int> with the value 1 if it is being called from a C<destroy()>
method and 0 otherwise.

Note that B<DBI> v1.32 and earlier test on C<dbd_db_finish3()> to call
C<dbd_st_finish3()>; if you provide C<dbd_st_finish3()>, either define
C<dbd_db_finish3()> too, or insist on B<DBI> v1.33 or later.

All it I<needs> to do is turn off the I<Active> flag for the I<sth>.
It will only be called by F<Driver.xst> code, if the driver has set I<ACTIVE>
to on for the I<sth>.

Outline example:

  int dbd_st_finish3(SV* sth, imp_sth_t* imp_sth, int from_destroy) {
      if (DBIc_ACTIVE(imp_sth))
      {
          /* close cursor or equivalent action */
          DBIc_ACTIVE_off(imp_sth);
      }
      return 1;
  }

The from_destroy parameter is true if C<dbd_st_finish3()> is being called
from C<DESTROY()> - and so the statement is about to be destroyed.
For many drivers there's no point in doing anything more than turing of
the I<Active> flag in this case.

The function returns I<TRUE> for success, I<FALSE> otherwise, but there isn't
a lot anyone can do to recover if there is an error.

=head3 The dbd_st_destroy method

This function is the private part of the statement handle destructor.

  void dbd_st_destroy(SV* sth, imp_sth_t* imp_sth) {
      ... /* any clean-up that's needed */
      DBIc_IMPSET_off(imp_sth); /* let DBI know we've done it   */
  }

The B<DBI> F<Driver.xst> code will call C<dbd_st_finish()> for you, if the
I<sth> has the I<ACTIVE> flag set, before calling C<dbd_st_destroy()>.

=head3 The dbd_st_STORE_attrib and dbd_st_FETCH_attrib methods

These functions correspond to C<dbd_db_STORE()> and C<dbd_db_FETCH()> attrib
above, except that they are for statement handles.
See above.

  int dbd_st_STORE_attrib(SV* sth, imp_sth_t* imp_sth, SV* keysv,
                          SV* valuesv);
  SV* dbd_st_FETCH_attrib(SV* sth, imp_sth_t* imp_sth, SV* keysv);

=head3 The dbd_bind_ph method

This function is internally used by the C<bind_param()> method, the
C<bind_param_inout()> method and by the B<DBI> F<Driver.xst> code if
C<execute()> is called with any bind parameters.

  int dbd_bind_ph (SV *sth, imp_sth_t *imp_sth, SV *param,
                   SV *value, IV sql_type, SV *attribs,
                   int is_inout, IV maxlen);

The I<param> argument holds an C<IV> with the parameter number (1, 2, ...).
The I<value> argument is the parameter value and I<sql_type> is its type.

If your driver does not support C<bind_param_inout()> then you should
ignore I<maxlen> and croak if I<is_inout> is I<TRUE>.

If your driver I<does> support C<bind_param_inout()> then you should
note that I<value> is the C<SV> I<after> dereferencing the reference
passed to C<bind_param_inout()>.

In drivers of simple databases the function will, for example, store
the value in a parameter array and use it later in C<dbd_st_execute()>.
See the B<DBD::mysql> driver for an example.

=head3 Implementing bind_param_inout support

To provide support for parameters bound by reference rather than by
value, the driver must do a number of things.  First, and most
importantly, it must note the references and stash them in its own
driver structure.  Secondly, when a value is bound to a column, the
driver must discard any previous reference bound to the column.  On
each execute, the driver must evaluate the references and internally
bind the values resulting from the references.  This is only applicable
if the user writes:

  $sth->execute;

If the user writes:

  $sth->execute(@values);

then B<DBI> automatically calls the binding code for each element of
I<@values>.  These calls are indistinguishable from explicit user calls to
C<bind_param()>.

=head2 C/XS version of Makefile.PL

The F<Makefile.PL> file for a C/XS driver is similar to the code needed
for a pure Perl driver, but there are a number of extra bits of
information needed by the build system.

For example, the attributes list passed to C<WriteMakefile()> needs
to specify the object files that need to be compiled and built into
the shared object (DLL). This is often, but not necessarily, just
F<dbdimp.o> (unless that should be F<dbdimp.obj> because you're building
on MS Windows).

Note that you can reliably determine the extension of the object files
from the I<$Config{obj_ext}> values, and there are many other useful pieces
of configuration information lurking in that hash.
You get access to it with:

    use Config;

=head2 Methods which do not need to be written

The B<DBI> code implements the majority of the methods which are accessed
using the notation C<DBI-E<gt>function()>, the only exceptions being
C<DBI-E<gt>connect()> and C<DBI-E<gt>data_sources()> which require
support from the driver.

The B<DBI> code implements the following documented driver, database and
statement functions which do not need to be written by the B<DBD> driver
writer.

=over 4

=item $dbh->do()

The default implementation of this function prepares, executes and
destroys the statement.  This can be replaced if there is a better
way to implement this, such as C<EXECUTE IMMEDIATE> which can
sometimes be used if there are no parameters.

=item $h->errstr()

=item $h->err()

=item $h->state()

=item $h->trace()

The B<DBD> driver does not need to worry about these routines at all.

=item $h->{ChopBlanks}

This attribute needs to be honored during C<fetch()> operations, but does
not need to be handled by the attribute handling code.

=item $h->{RaiseError}

The B<DBD> driver does not need to worry about this attribute at all.

=item $h->{PrintError}

The B<DBD> driver does not need to worry about this attribute at all.

=item $sth->bind_col()

Assuming the driver uses the C<DBIc_DBISTATE(imp_xxh)-E<gt>get_fbav()>
function (C drivers, see below), or the C<$sth-E<gt>_set_fbav($data)>
method (Perl drivers) the driver does not need to do anything about this
routine.

=item $sth->bind_columns()

Regardless of whether the driver uses
C<DBIc_DBISTATE(imp_xxh)-E<gt>get_fbav()>, the driver does not need
to do anything about this routine as it simply iteratively calls
C<$sth-E<gt>bind_col()>.

=back

The B<DBI> code implements a default implementation of the following
functions which do not need to be written by the B<DBD> driver writer
unless the default implementation is incorrect for the Driver.

=over 4

=item $dbh->quote()

This should only be written if the database does not accept the ANSI
SQL standard for quoting strings, with the string enclosed in single
quotes and any embedded single quotes replaced by two consecutive
single quotes.

For the two argument form of quote, you need to implement the
C<type_info()> method to provide the information that quote needs.

=item $dbh->ping()

This should be implemented as a simple efficient way to determine
whether the connection to the database is still alive. Typically
code like this:

  sub ping {
      my $dbh = shift;
      $sth = $dbh->prepare_cached(q{
          select * from A_TABLE_NAME where 1=0
      }) or return 0;
      $sth->execute or return 0;
      $sth->finish;
      return 1;
  }

where I<A_TABLE_NAME> is the name of a table that always exists (such as a
database system catalogue).

=back

=head1 METADATA METHODS

The exposition above ignores the B<DBI> MetaData methods.
The metadata methods are all associated with a database handle.

=head2 Using DBI::DBD::Metadata

The B<DBI::DBD::Metadata> module is a good semi-automatic way for the
developer of a B<DBD> module to write the C<get_info()> and C<type_info()>
functions quickly and accurately.

=head3 Generating the get_info method

Prior to B<DBI> v1.33, this existed as the method C<write_getinfo_pm()>
in the B<DBI::DBD> module. From B<DBI> v1.33, it exists as the method
C<write_getinfo_pm()> in the B<DBI::DBD::Metadata> module. This
discussion assumes you have B<DBI> v1.33 or later.

You examine the documentation for C<write_getinfo_pm()> using:

    perldoc DBI::DBD::Metadata

To use it, you need a Perl B<DBI> driver for your database which implements
the C<get_info()> method. In practice, this means you need to install
B<DBD::ODBC>, an ODBC driver manager, and an ODBC driver for your
database.

With the pre-requisites in place, you might type:

    perl -MDBI::DBD::Metadata -e write_getinfo_pm \
            dbi:ODBC:foo_db username password Driver

The procedure writes to standard output the code that should be added to
your F<Driver.pm> file and the code that should be written to
F<lib/DBD/Driver/GetInfo.pm>.

You should review the output to ensure that it is sensible.

=head3 Generating the type_info method

Given the idea of the C<write_getinfo_pm()> method, it was not hard
to devise a parallel method, C<write_typeinfo_pm()>, which does the
analogous job for the B<DBI> C<type_info_all()> metadata method. The
C<write_typeinfo_pm()> method was added to B<DBI> v1.33.

You examine the documentation for C<write_typeinfo_pm()> using:

    perldoc DBI::DBD::Metadata

The setup is exactly analogous to the mechanism descibed in
L</Generating the get_info method>.

With the pre-requisites in place, you might type:

    perl -MDBI::DBD::Metadata -e write_typeinfo \
            dbi:ODBC:foo_db username password Driver

The procedure writes to standard output the code that should be added to
your F<Driver.pm> file and the code that should be written to
F<lib/DBD/Driver/TypeInfo.pm>.

You should review the output to ensure that it is sensible.

=head2 Writing DBD::Driver::db::get_info

If you use the B<DBI::DBD::Metadata> module, then the code you need is
generated for you.

If you decide not to use the B<DBI::DBD::Metadata> module, you
should probably borrow the code from a driver that has done so (eg
B<DBD::Informix> from version 1.05 onwards) and crib the code from
there, or look at the code that generates that module and follow
that. The method in F<Driver.pm> will be very simple; the method in
F<lib/DBD/Driver/GetInfo.pm> is not very much more complex unless your
DBMS itself is much more complex.

Note that some of the B<DBI> utility methods rely on information from the
C<get_info()> method to perform their operations correctly. See, for
example, the C<quote_identifier()> and quote methods, discussed below.

=head2 Writing DBD::Driver::db::type_info_all

If you use the C<DBI::DBD::Metadata> module, then the code you need is
generated for you.

If you decide not to use the C<DBI::DBD::Metadata> module, you
should probably borrow the code from a driver that has done so (eg
C<DBD::Informix> from version 1.05 onwards) and crib the code from
there, or look at the code that generates that module and follow
that. The method in F<Driver.pm> will be very simple; the method in
F<lib/DBD/Driver/TypeInfo.pm> is not very much more complex unless your
DBMS itself is much more complex.

=head2 Writing DBD::Driver::db::type_info

The guidelines on writing this method are still not really clear.
No sample implementation is available.

=head2 Writing DBD::Driver::db::table_info

 *FIX ME* The guidelines on writing this method have not been written yet.
 No sample implementation is available.

=head2 Writing DBD::Driver::db::column_info

 *FIX ME* The guidelines on writing this method have not been written yet.
 No sample implementation is available.

=head2 Writing DBD::Driver::db::primary_key_info

 *FIX ME* The guidelines on writing this method have not been written yet.
 No sample implementation is available.

=head2 Writing DBD::Driver::db::primary_key

 *FIX ME* The guidelines on writing this method have not been written yet.
 No sample implementation is available.

=head2 Writing DBD::Driver::db::foreign_key_info

 *FIX ME* The guidelines on writing this method have not been written yet.
 No sample implementation is available.

=head2 Writing DBD::Driver::db::tables

This method generates an array of names in a format suitable for being
embedded in SQL statements in places where a table name is expected.

If your database hews close enough to the SQL standard or if you have
implemented an appropriate C<table_info()> function and and the appropriate
C<quote_identifier()> function, then the B<DBI> default version of this method
will work for your driver too.

Otherwise, you have to write a function yourself, such as:

    sub tables
    {
        my($dbh, $cat, $sch, $tab, $typ) = @_;
        my(@res);
        my($sth) = $dbh->table_info($cat, $sch, $tab, $typ);
        my(@arr);
        while (@arr = $sth->fetchrow_array)
        {
            push @res, $dbh->quote_identifier($arr[0], $arr[1], $arr[2]);
        }
        return @res;
    }

See also the default implementation in F<DBI.pm>.

=head2 Writing DBD::Driver::db::quote

This method takes a value and converts it into a string suitable for
embedding in an SQL statement as a string literal.

If your DBMS accepts the SQL standard notation for strings (single
quotes around the string as a whole with any embedded single quotes
doubled up), then you do not need to write this method as B<DBI> provides a
default method that does it for you.

If your DBMS uses an alternative notation or escape mechanism, then you
need to provide an equivalent function. For example, suppose your DBMS
used C notation with double quotes around the string and backslashes
escaping both double quotes and backslashes themselves. Then you might
write the function as:

    sub quote
    {
        my($dbh, $str) = @_;
        $str =~ s/["\\]/\\$&/gmo;
        return qq{"$str"};
    }

Handling newlines and other control characters is left as an exercise
for the reader.

This sample method ignores the I<$data_type> indicator which is the
optional second argument to the method.

=head2 Writing DBD::Driver::db::quote_identifier

This method is called to ensure that the name of the given table (or
other database object) can be embedded into an SQL statement without
danger of misinterpretation. The result string should be usable in the
text of an SQL statement as the identifier for a table.

If your DBMS accepts the SQL standard notation for quoted identifiers
(which uses double quotes around the identifier as a whole, with any
embedded double quotes doubled up) and accepts I<"schema"."identifier">
(and I<"catalog"."schema"."identifier"> when a catalog is specified), then
you do not need to write this method as B<DBI> provides a default method
that does it for you.

In fact, even if your DBMS does not handle exactly that notation but
you have implemented the C<get_info()> method and it gives the correct
responses, then it will work for you. If your database is fussier, then
you need to implement your own version of the function.

For example, B<DBD::Informix> has to deal with an environment variable
I<DELIMIDENT>. If it is not set, then the DBMS treats names enclosed in
double quotes as strings rather than names, which is usually a syntax
error. Additionally, the catalog portion of the name is separated from
the schema and table by a different delimiter (colon instead of dot),
and the catalog portion is never enclosed in quotes. (Fortunately,
valid strings for the catalog will never contain weird characters that
might need to be escaped, unless you count dots, dashes, slashes and
at-signs as weird.) Finally, an Informix database can contain objects
that cannot be accessed because they were created by a user with the
I<DELIMIDENT> environment variable set, but the current user does not
have it set. By design choice, the C<quote_identifier()> method encloses
those identifiers in double quotes anyway, which generally triggers a
syntax error, and the metadata methods which generate lists of tables
etc omit those identifiers from the result sets.

    sub quote_identifier
    {
        my($dbh, $cat, $sch, $obj) = @_;
        my($rv) = "";
        my($qq) = (defined $ENV{DELIMIDENT}) ? '"' : '';
        $rv .= qq{$cat:} if (defined $cat);
        if (defined $sch)
        {
            if ($sch !~ m/^\w+$/o)
            {
                $qq = '"';
                $sch =~ s/$qq/$qq$qq/gm;
            }
            $rv .= qq{$qq$sch$qq.};
        }
        if (defined $obj)
        {
            if ($obj !~ m/^\w+$/o)
            {
                $qq = '"';
                $obj =~ s/$qq/$qq$qq/gm;
            }
            $rv .= qq{$qq$obj$qq};
        }
        return $rv;
    }

Handling newlines and other control characters is left as an exercise
for the reader.

Note that there is an optional fourth parameter to this function which
is a reference to a hash of attributes; this sample implementation
ignores that.

This sample implementation also ignores the single-argument variant of
the method.

=head1 WRITING AN EMULATION LAYER FOR AN OLD PERL INTERFACE

Study F<Oraperl.pm> (supplied with B<DBD::Oracle>) and F<Ingperl.pm> (supplied
with B<DBD::Ingres>) and the corresponding I<dbdimp.c> files for ideas.

Note that the emulation code sets C<$dbh-E<gt>{CompatMode} = 1;> for each
connection so that the internals of the driver can implement behaviour
compatible with the old interface when dealing with those handles.

=head2 Setting emulation perl variables

For example, ingperl has a I<$sql_rowcount> variable. Rather than try
to manually update this in F<Ingperl.pm> it can be done faster in C code.
In C<dbd_init()>:

  sql_rowcount = perl_get_sv("Ingperl::sql_rowcount", GV_ADDMULTI);

In the relevant places do:

  if (DBIc_COMPAT(imp_sth))     /* only do this for compatibility mode handles */
      sv_setiv(sql_rowcount, the_row_count);

=head1 OTHER MISCELLANEOUS INFORMATION

=head2 The imp_xyz_t types

Any handle has a corresponding C structure filled with private data.
Some of this data is reserved for use by B<DBI> (except for using the
DBIc macros below), some is for you. See the description of the
F<dbdimp.h> file above for examples. Most functions in F<dbdimp.c>
are passed both the handle C<xyz> and a pointer to C<imp_xyz>. In
rare cases, however, you may use the following macros:

=over 4

=item D_imp_dbh(dbh)

Given a function argument I<dbh>, declare a variable I<imp_dbh> and
initialize it with a pointer to the handles private data. Note: This
must be a part of the function header, because it declares a variable.

=item D_imp_sth(sth)

Likewise for statement handles.

=item D_imp_xxx(h)

Given any handle, declare a variable I<imp_xxx> and initialize it
with a pointer to the handles private data. It is safe, for example,
to cast I<imp_xxx> to C<imp_dbh_t*>, if C<DBIc_TYPE(imp_xxx) == DBIt_DB>.
(You can also call C<sv_derived_from(h, "DBI::db")>, but that's much
slower.)

=item D_imp_dbh_from_sth

Given a I<imp_sth>, declare a variable I<imp_dbh> and initialize it with a
pointer to the parent database handle's implementors structure.

=back

=head2 Using DBIc_IMPSET_on

The driver code which initializes a handle should use C<DBIc_IMPSET_on()>
as soon as its state is such that the cleanup code must be called.
When this happens is determined by your driver code.

B<Failure to call this can lead to corruption of data structures.>

For example, B<DBD::Informix> maintains a linked list of database
handles in the driver, and within each handle, a linked list of
statements. Once a statement is added to the linked list, it is crucial
that it is cleaned up (removed from the list). When I<DBIc_IMPSET_on()>
was being called too late, it was able to cause all sorts of problems.

=head2 Using DBIc_is(), DBIc_has(), DBIc_on() and DBIc_off()

Once upon a long time ago, the only way of handling the internal B<DBI>
boolean flags/attributes was through macros such as:

  DBIc_WARN       DBIc_WARN_on        DBIc_WARN_off
  DBIc_COMPAT     DBIc_COMPAT_on      DBIc_COMPAT_off

Each of these took an I<imp_xxh> pointer as an argument.

Since then, new attributes have been added such as I<ChopBlanks>,
I<RaiseError> and I<PrintError>, and these do not have the full set of
macros. The approved method for handling these is now the four macros:

  DBIc_is(imp, flag)
  DBIc_has(imp, flag)       an alias for DBIc_is
  DBIc_on(imp, flag)
  DBIc_off(imp, flag)
  DBIc_set(imp, flag, on)   set if on is true, else clear

Consequently, the C<DBIc_XXXXX> family of macros is now mostly deprecated
and new drivers should avoid using them, even though the older drivers
will probably continue to do so for quite a while yet. However...

There is an I<important exception> to that. The I<ACTIVE> and I<IMPSET>
flags should be set via the C<DBIc_ACTIVE_on()> and C<DBIc_IMPSET_on()> macros,
and unset via the C<DBIc_ACTIVE_off()> and C<DBIc_IMPSET_off()> macros.

=head2 Using the get_fbav() method

B<THIS IS CRITICAL for C/XS drivers>.

The C<$sth-E<gt>bind_col()> and C<$sth-E<gt>bind_columns()> documented
in the B<DBI> specification do not have to be implemented by the driver
writer because B<DBI> takes care of the details for you.

However, the key to ensuring that bound columns work is to call the
function C<DBIc_DBISTATE(imp_xxh)-E<gt>get_fbav()> in the code which
fetches a row of data.

This returns an C<AV>, and each element of the C<AV> contains the C<SV> which
should be set to contain the returned data.

The pure Perl equivalent is the C<$sth-E<gt>_set_fbav($data)> method, as
described in the part on pure Perl drivers.

=head1 SUBCLASSING DBI DRIVERS

This is definitely an open subject. It can be done, as demonstrated by
the B<DBD::File> driver, but it is not as simple as one might think.

(Note that this topic is different from subclassing the B<DBI>. For an
example of that, see the F<t/subclass.t> file supplied with the B<DBI>.)

The main problem is that the I<dbh>'s and I<sth>'s that your C<connect()> and
C<prepare()> methods return are not instances of your B<DBD::Driver::db>
or B<DBD::Driver::st> packages, they are not even derived from it.
Instead they are instances of the B<DBI::db> or B<DBI::st> classes or
a derived subclass. Thus, if you write a method C<mymethod()> and do a

  $dbh->mymethod()

then the autoloader will search for that method in the package B<DBI::db>.
Of course you can instead to a

  $dbh->func('mymethod')

and that will indeed work, even if C<mymethod()> is inherited, but not
without additional work. Setting I<@ISA> is not sufficient.

=head2 Overwriting methods

The first problem is, that the C<connect()> method has no idea of
subclasses. For example, you cannot implement base class and subclass
in the same file: The C<install_driver()> method wants to do a

  require DBD::Driver;

In particular, your subclass B<has> to be a separate driver, from
the view of B<DBI>, and you cannot share driver handles.

Of course that's not much of a problem. You should even be able
to inherit the base classes C<connect()> method. But you cannot
simply overwrite the method, unless you do something like this,
quoted from B<DBD::CSV>:

  sub connect ($$;$$$) {
      my ($drh, $dbname, $user, $auth, $attr) = @_;

      my $this = $drh->DBD::File::dr::connect($dbname, $user, $auth, $attr);
      if (!exists($this->{csv_tables})) {
          $this->{csv_tables} = {};
      }

      $this;
  }

Note that we cannot do a

  $drh->SUPER::connect($dbname, $user, $auth, $attr);

as we would usually do in a an OO environment, because I<$drh> is an instance
of B<DBI::dr>. And note, that the C<connect()> method of B<DBD::File> is
able to handle subclass attributes. See the description of Pure Perl
drivers above.

It is essential that you always call superclass method in the above
manner. However, that should do.

=head2 Attribute handling

Fortunately the B<DBI> specifications allow a simple, but still
performant way of handling attributes. The idea is based on the
convention that any driver uses a prefix I<driver_> for its private
methods. Thus it's always clear whether to pass attributes to the super
class or not. For example, consider this C<STORE()> method from the
B<DBD::CSV> class:

  sub STORE {
      my ($dbh, $attr, $val) = @_;
      if ($attr !~ /^driver_/) {
          return $dbh->DBD::File::db::STORE($attr, $val);
      }
      if ($attr eq 'driver_foo') {
      ...
  }

=cut

use Exporter ();
use Config qw(%Config);
use Carp;
use Cwd;
use File::Spec;
use strict;
use vars qw(
    @ISA @EXPORT
    $is_dbi
);

BEGIN {
    if ($^O eq 'VMS') {
	require vmsish;
	import  vmsish;
	require VMS::Filespec;
	import  VMS::Filespec;
    }
    else {
	*vmsify  = sub { return $_[0] };
	*unixify = sub { return $_[0] };
    }
}

@ISA = qw(Exporter);

@EXPORT = qw(
    dbd_dbi_dir
    dbd_dbi_arch_dir
    dbd_edit_mm_attribs
    dbd_postamble
);

BEGIN {
    $is_dbi = (-r 'DBI.pm' && -r 'DBI.xs' && -r 'DBIXS.h');
    require DBI unless $is_dbi;
}

my $done_inst_checks;

sub _inst_checks {
    return if $done_inst_checks++;
    my $cwd = cwd();
    if ($cwd =~ /\Q$Config{path_sep}/) {
	warn "*** Warning: Path separator characters (`$Config{path_sep}') ",
	    "in the current directory path ($cwd) may cause problems\a\n\n";
        sleep 2;
    }
    if ($cwd =~ /\s/) {
	warn "*** Warning: whitespace characters ",
	    "in the current directory path ($cwd) may cause problems\a\n\n";
        sleep 2;
    }
    if (   $^O eq 'MSWin32'
	&& $Config{cc} eq 'cl'
	&& !(exists $ENV{'LIB'} && exists $ENV{'INCLUDE'}))
    {
	die <<EOT;
*** You're using Microsoft Visual C++ compiler or similar but
    the LIB and INCLUDE environment variables are not both set.

    You need to run the VCVARS32.BAT batch file that was supplied
    with the compiler before you can use it.

    A copy of vcvars32.bat can typically be found in the following
    directories under your Visual Studio install directory:
        Visual C++ 6.0:     vc98\\bin
        Visual Studio .NET: vc7\\bin

    Find it, run it, then retry this.

    If you think this error is not correct then just set the LIB and
    INCLUDE environment variables to some value to disable the check.
EOT
    }
}

sub dbd_edit_mm_attribs {
    # this both edits the attribs in-place and returns the flattened attribs
    my $mm_attr = shift;
    my $dbd_attr = shift || {};
    croak "dbd_edit_mm_attribs( \%makemaker [, \%other ]): too many parameters"
	if @_;
    _inst_checks();

    # decide what needs doing

    # do whatever needs doing
    if ($dbd_attr->{create_pp_tests}) {
	# XXX need to convert this to work within the generated Makefile
	# so 'make' creates them and 'make clean' deletes them
	my %test_variants = (
	    p => {	name => "DBI::PurePerl",
			add => [ '$ENV{DBI_PUREPERL} = 2' ],
	    },
	    g => {	name => "DBD::Gofer",
			add => [ q{$ENV{DBI_AUTOPROXY} = 'dbi:Gofer:transport=null;policy=pedantic'} ],
	    },
	    xgp => {	name => "PurePerl & Gofer",
			add => [ q{$ENV{DBI_PUREPERL} = 2; $ENV{DBI_AUTOPROXY} = 'dbi:Gofer:transport=null;policy=pedantic'} ],
	    },
	#   mx => {	name => "DBD::Multiplex",
	#               add => [ q{local $ENV{DBI_AUTOPROXY} = 'dbi:Multiplex:';} ],
	#   }
	#   px => {	name => "DBD::Proxy",
	#		need mechanism for starting/stopping the proxy server
	#		add => [ q{local $ENV{DBI_AUTOPROXY} = 'dbi:Proxy:XXX';} ],
	#   }
	);

	opendir DIR, 't' or die "Can't read 't' directory: $!";
	my @tests = grep { /\.t$/ } readdir DIR;
	closedir DIR;

        while ( my ($v_type, $v_info) = each %test_variants ) {
            printf "Creating test wrappers for $v_info->{name}:\n";

            foreach my $test (sort @tests) {
                next if $test !~ /^\d/;
                my $usethr = ($test =~ /(\d+|\b)thr/ && $] >= 5.008 && $Config{useithreads});
                my $v_test = "t/zv${v_type}_$test";
                my $v_perl = ($test =~ /taint/) ? "perl -wT" : "perl -w";
		printf "%s %s\n", $v_test, ($usethr) ? "(use threads)" : "";
		open PPT, ">$v_test" or warn "Can't create $v_test: $!";
		print PPT "#!$v_perl\n";
		print PPT "use threads;\n" if $usethr;
		print PPT "$_;\n" foreach @{$v_info->{add}};
		print PPT "require './t/$test'; # or warn \$!;\n";
		close PPT or warn "Error writing $v_test: $!";
	    }
	}
    }
    return %$mm_attr;
}

sub dbd_dbi_dir {
    _inst_checks();
    return '.' if $is_dbi;
    my $dbidir = $INC{'DBI.pm'} || die "DBI.pm not in %INC!";
    $dbidir =~ s:/DBI\.pm$::;
    return $dbidir;
}

sub dbd_dbi_arch_dir {
    _inst_checks();
    return '$(INST_ARCHAUTODIR)' if $is_dbi;
    my $dbidir = dbd_dbi_dir();
    my %seen;
    my @try = grep { not $seen{$_}++ } map { vmsify( unixify($_) . "/auto/DBI/" ) } @INC;
    my @xst = grep { -f vmsify( unixify($_) . "/Driver.xst" ) } @try;
    Carp::croak("Unable to locate Driver.xst in @try") unless @xst;
    Carp::carp( "Multiple copies of Driver.xst found in: @xst") if @xst > 1;
    print "Using DBI $DBI::VERSION (for perl $] on $Config{archname}) installed in $xst[0]\n";
    return File::Spec->canonpath($xst[0]);
}

sub dbd_postamble {
    my $self = shift;
    _inst_checks();
    my $dbi_instarch_dir = ($is_dbi) ? "." : dbd_dbi_arch_dir();
    my $dbi_driver_xst= File::Spec->catfile($dbi_instarch_dir, 'Driver.xst');
    my $xstf_h = File::Spec->catfile($dbi_instarch_dir, 'Driver_xst.h');

    # we must be careful of quotes, expecially for Win32 here.
    return '
# --- This section was generated by DBI::DBD::dbd_postamble()
DBI_INSTARCH_DIR='.$dbi_instarch_dir.'
DBI_DRIVER_XST='.$dbi_driver_xst.'

# The main dependancy (technically correct but probably not used)
$(BASEEXT).c: $(BASEEXT).xsi

# This dependancy is needed since MakeMaker uses the .xs.o rule
$(BASEEXT)$(OBJ_EXT): $(BASEEXT).xsi

$(BASEEXT).xsi: $(DBI_DRIVER_XST) '.$xstf_h.'
	$(PERL) -p -e "s/~DRIVER~/$(BASEEXT)/g" $(DBI_DRIVER_XST) > $(BASEEXT).xsi

# ---
';
}

package DBDI; # just to reserve it via PAUSE for the future

1;

__END__

=head1 AUTHORS

Jonathan Leffler <jleffler@us.ibm.com> (previously <jleffler@informix.com>),
Jochen Wiedmann <joe@ispsoft.de>,
Steffen Goeldner <sgoeldner@cpan.org>,
and Tim Bunce <dbi-users@perl.org>.

=cut
