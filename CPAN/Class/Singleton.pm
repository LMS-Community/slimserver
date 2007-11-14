#============================================================================
#
# Class::Singleton.pm
#
# Implementation of a "singleton" module which ensures that a class has
# only one instance and provides global access to it.  For a description 
# of the Singleton class, see "Design Patterns", Gamma et al, Addison-
# Wesley, 1995, ISBN 0-201-63361-2
#
# Written by Andy Wardley <abw@cre.canon.co.uk>
#
# Copyright (C) 1998 Canon Research Centre Europe Ltd.  All Rights Reserved.
#
#----------------------------------------------------------------------------
#
# $Id: Singleton.pm 8645 2006-07-25 20:07:23Z dsully $
#
#============================================================================

package Class::Singleton;

require 5.004;

use strict;
use vars qw( $RCS_ID $VERSION );

$VERSION = sprintf("%d.%02d", q$Revision: 1.3 $ =~ /(\d+)\.(\d+)/);
$RCS_ID  = q$Id: Singleton.pm 8645 2006-07-25 20:07:23Z dsully $;



#========================================================================
#                      -----  PUBLIC METHODS -----
#========================================================================

#========================================================================
#
# instance()
#
# Module constructor.  Creates an Class::Singleton (or derivative) instance 
# if one doesn't already exist.  The instance reference is stored in the
# _instance variable of the $class package.  This means that classes 
# derived from Class::Singleton will have the variables defined in *THEIR*
# package, rather than the Class::Singleton package.  The impact of this is
# that you can create any number of classes derived from Class::Singleton
# and create a single instance of each one.  If the _instance variable
# was stored in the Class::Singleton package, you could only instantiate 
# *ONE* object of *ANY* class derived from Class::Singleton.  The first
# time the instance is created, the _new_instance() constructor is called 
# which simply returns a reference to a blessed hash.  This can be 
# overloaded for custom constructors.  Any addtional parameters passed to 
# instance() are forwarded to _new_instance().
#
# Returns a reference to the existing, or a newly created Class::Singleton
# object.  If the _new_instance() method returns an undefined value
# then the constructer is deemed to have failed.
#
#========================================================================

sub instance {
    my $class = shift;

    # get a reference to the _instance variable in the $class package 
    no strict 'refs';
    my $instance = \${ "$class\::_instance" };

    defined $$instance
	? $$instance
	: ($$instance = $class->_new_instance(@_));
}



#========================================================================
#
# _new_instance(...)
#
# Simple constructor which returns a hash reference blessed into the 
# current class.  May be overloaded to create non-hash objects or 
# handle any specific initialisation required.
#
# Returns a reference to the blessed hash.
#
#========================================================================

sub _new_instance {
    bless { }, $_[0];
}



1;

__END__

=head1 NAME

Class::Singleton - Implementation of a "Singleton" class 

=head1 SYNOPSIS

    use Class::Singleton;

    my $one = Class::Singleton->instance();   # returns a new instance
    my $two = Class::Singleton->instance();   # returns same instance

=head1 DESCRIPTION

This is the Class::Singleton module.  A Singleton describes an object class
that can have only one instance in any system.  An example of a Singleton
might be a print spooler or system registry.  This module implements a
Singleton class from which other classes can be derived.  By itself, the
Class::Singleton module does very little other than manage the instantiation
of a single object.  In deriving a class from Class::Singleton, your module 
will inherit the Singleton instantiation method and can implement whatever
specific functionality is required.

For a description and discussion of the Singleton class, see 
"Design Patterns", Gamma et al, Addison-Wesley, 1995, ISBN 0-201-63361-2.

=head1 PREREQUISITES

Class::Singleton requires Perl version 5.004 or later.  If you have an older 
version of Perl, please upgrade to latest version.  Perl 5.004 is known 
to be stable and includes new features and bug fixes over previous
versions.  Perl itself is available from your nearest CPAN site (see
INSTALLATION below).

=head1 INSTALLATION

The Class::Singleton module is available from CPAN. As the 'perlmod' man
page explains:

    CPAN stands for the Comprehensive Perl Archive Network.
    This is a globally replicated collection of all known Perl
    materials, including hundreds of unbunded modules.

    [...]

    For an up-to-date listing of CPAN sites, see
    http://www.perl.com/perl/ or ftp://ftp.perl.com/perl/ .

The module is available in the following directories:

    /modules/by-module/Class/Class-Singleton-<version>.tar.gz
    /authors/id/ABW/Class-Singleton-<version>.tar.gz

For the latest information on Class-Singleton or to download the latest
pre-release/beta version of the module, consult the definitive reference:

    http://www.kfs.org/~abw/perl/

Class::Singleton is distributed as a single gzipped tar archive file:

    Class-Singleton-<version>.tar.gz

Note that "<version>" represents the current version number, of the 
form "1.23".  See L<REVISION> below to determine the current version 
number for Class::Singleton.

Unpack the archive to create an installation directory:

    gunzip Class-Singleton-<version>.tar.gz
    tar xvf Class-Singleton-<version>.tar

'cd' into that directory, make, test and install the module:

    cd Class-Singleton-<version>
    perl Makefile.PL
    make
    make test
    make install

The 'make install' will install the module on your system.  You may need 
root access to perform this task.  If you install the module in a local 
directory (for example, by executing "perl Makefile.PL LIB=~/lib" in the 
above - see C<perldoc MakeMaker> for full details), you will need to ensure 
that the PERL5LIB environment variable is set to include the location, or 
add a line to your scripts explicitly naming the library location:

    use lib '/local/path/to/lib';

=head1 USING THE CLASS::SINGLETON MODULE

To import and use the Class::Singleton module the following line should 
appear in your Perl script:

    use Class::Singleton;

The instance() method is used to create a new Class::Singleton instance, 
or return a reference to an existing instance.  Using this method, it
is only possible to have a single instance of the class in any system.

    my $highlander = Class::Singleton->instance();

Assuming that no Class::Singleton object currently exists, this first
call to instance() will create a new Class::Singleton and return a reference
to it.  Future invocations of instance() will return the same reference.

    my $macleod    = Class::Singleton->instance();

In the above example, both $highlander and $macleod contain the same
reference to a Class::Singleton instance.  There can be only one.

=head1 DERIVING SINGLETON CLASSES

A module class may be derived from Class::Singleton and will inherit the 
instance() method that correctly instantiates only one object.

    package PrintSpooler;
    use vars qw(@ISA);
    @ISA = qw(Class::Singleton);

    # derived class specific code
    sub submit_job {
        ...
    }

    sub cancel_job {
        ...
    }

The PrintSpooler class defined above could be used as follows:

    use PrintSpooler;

    my $spooler = PrintSpooler->instance();

    $spooler->submit_job(...);

The instance() method calls the _new_instance() constructor method the 
first and only time a new instance is created.  All parameters passed to 
the instance() method are forwarded to _new_instance().  In the base class
this method returns a blessed reference to an empty hash array.  Derived 
classes may redefine it to provide specific object initialisation or change
the underlying object type (to a list reference, for example).

    package MyApp::Database;
    use vars qw( $ERROR );
    use base qw( Class::Singleton );
    use DBI;

    $ERROR = '';

    # this only gets called the first time instance() is called
    sub _new_instance {
	my $class = shift;
	my $self  = bless { }, $class;
	my $db    = shift || "myappdb";    
	my $host  = shift || "localhost";

	unless (defined ($self->{ DB } 
			 = DBI->connect("DBI:mSQL:$db:$host"))) {
	    $ERROR = "Cannot connect to database: $DBI::errstr\n";
	    # return failure;
	    return undef;
	}

	# any other initialisation...
	
	# return sucess
	$self;
    }

The above example might be used as follows:

    use MyApp::Database;

    # first use - database gets initialised
    my $database = MyApp::Database->instance();
    die $MyApp::Database::ERROR unless defined $database;

Some time later on in a module far, far away...

    package MyApp::FooBar
    use MyApp::Database;

    sub new {
	# usual stuff...
	
	# this FooBar object needs access to the database; the Singleton
	# approach gives a nice wrapper around global variables.

	# subsequent use - existing instance gets returned
	my $database = MyApp::Database->instance();

	# the new() isn't called if an instance already exists,
	# so the above constructor shouldn't fail, but we check
	# anyway.  One day things might change and this could be the
	# first call to instance()...  
	die $MyAppDatabase::ERROR unless defined $database;

	# more stuff...
    }

The Class::Singleton instance() method uses a package variable to store a
reference to any existing instance of the object.  This variable, 
"_instance", is coerced into the derived class package rather than
the base class package.

Thus, in the MyApp::Database example above, the instance variable would
be:

    $MyApp::Database::_instance;

This allows different classes to be derived from Class::Singleton that 
can co-exist in the same system, while still allowing only one instance
of any one class to exists.  For example, it would be possible to 
derive both 'PrintSpooler' and 'MyApp::Database' from Class::Singleton and
have a single instance of I<each> in a system, rather than a single 
instance of I<either>.

=head1 AUTHOR

Andy Wardley, C<E<lt>abw@cre.canon.co.ukE<gt>>

Web Technology Group, Canon Research Centre Europe Ltd.

Thanks to Andreas Koenig C<E<lt>andreas.koenig@anima.deE<gt>> for providing
some significant speedup patches and other ideas.

=head1 REVISION

$Revision: 1.3 $

=head1 COPYRIGHT

Copyright (C) 1998 Canon Research Centre Europe Ltd.  All Rights Reserved.

This module is free software; you can redistribute it and/or modify it under 
the term of the Perl Artistic License.

=head1 SEE ALSO

=over 4

=item Canon Research Centre Europe Perl Pages

http://www.cre.canon.co.uk/perl/

=item The Author's Home Page

http://www.kfs.org/~abw/

=item Design Patterns

Class::Singleton is an implementation of the Singleton class described in 
"Design Patterns", Gamma et al, Addison-Wesley, 1995, ISBN 0-201-63361-2

=back

=cut
