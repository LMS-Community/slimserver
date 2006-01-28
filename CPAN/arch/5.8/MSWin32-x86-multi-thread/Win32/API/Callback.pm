package Win32::API::Callback;

# See the bottom of this file for the POD documentation.  Search for the
# string '=head'.

#######################################################################
#
# Win32::API::Callback - Perl Win32 API Import Facility
# 
# Version: 0.41
# Date: 10 Mar 2003
# Author: Aldo Calpini <dada@perl.it>
# $Id$
#######################################################################

$VERSION = "0.41";

require Exporter;       # to export the constants to the main:: space
require DynaLoader;     # to dynuhlode the module.
@ISA = qw( Exporter DynaLoader );

sub DEBUG { 
	if ($WIN32::API::DEBUG) { 
		printf @_ if @_ or return 1; 
	} else {
		return 0;
	}
}

use Win32::API;
use Win32::API::Type;
use Win32::API::Struct;

#######################################################################
# This AUTOLOAD is used to 'autoload' constants from the constant()
# XS function.  If a constant is not found then control is passed
# to the AUTOLOAD in AutoLoader.
#

sub AUTOLOAD {
    my($constname);
    ($constname = $AUTOLOAD) =~ s/.*:://;
    #reset $! to zero to reset any current errors.
    $!=0;
    my $val = constant($constname, @_ ? $_[0] : 0);
    if ($! != 0) {
        if ($! =~ /Invalid/) {
            $AutoLoader::AUTOLOAD = $AUTOLOAD;
            goto &AutoLoader::AUTOLOAD;
        } else {
            ($pack,$file,$line) = caller;
            die "Your vendor has not defined Win32::API::Callback macro $constname, used at $file line $line.";
        }
    }
    eval "sub $AUTOLOAD { $val }";
    goto &$AUTOLOAD;
}


#######################################################################
# dynamically load in the API extension module.
#
bootstrap Win32::API::Callback;

#######################################################################
# PUBLIC METHODS
#
sub new {
    my($class, $proc, $in, $out) = @_;
    my %self = ();

	# printf "(PM)Callback::new: got proc='%s', in='%s', out='%s'\n", $proc, $in, $out;
		
	$self{in} = [];
	if(ref($in) eq 'ARRAY') {
		foreach (@$in) {
			push(@{ $self{in} }, Win32::API::type_to_num($_));
		}	
	} else {
		my @in = split '', $in;
		foreach (@in) {
			push(@{ $self{in} }, Win32::API::type_to_num($_));
		}			
	}
	$self{out} = Win32::API::type_to_num($out);
	$self{sub} = $proc;
	my $self = bless \%self, $class;
	
	DEBUG "(PM)Callback::new: calling CallbackCreate($self)...\n";
    my $hproc = CallbackCreate($self);

	DEBUG "(PM)Callback::new: hproc=$hproc\n";

    #### ...if that fails, set $! accordingly
    if(!$hproc) {
        $! = Win32::GetLastError();
        return undef;
    }
    
    #### ok, let's stuff the object
    $self->{code} = $hproc;
    $self->{sub}  = $proc;

    #### cast the spell
    return $self;
}

sub MakeStruct {
	my($self, $n, $addr) = @_;	
	DEBUG "(PM)Win32::API::Callback::MakeStruct: got self='$self'\n";
	my $struct = Win32::API::Struct->new($self->{intypes}->[$n]);	
	$struct->FromMemory($addr);
	return $struct;
}

1;

__END__

#######################################################################
# DOCUMENTATION
#

=head1 NAME

Win32::API::Callback - Callback support for Win32::API

=head1 SYNOPSIS

  use Win32::API;
  use Win32::API::Callback;

  my $callback = Win32::API::Callback->new(
    sub { my($a, $b) = @_; return $a+$b; },
    "NN", "N",
  );

  Win32::API->Import(
      'mydll', 'two_integers_cb', 'KNN', 'N',
  );

  $sum = two_integers_cb( $callback, 3, 2 );


=head1 FOREWORDS

=over 4

=item *
Support for this module is B<highly experimental> at this point.

=item *
I won't be surprised if it doesn't work for you.

=item *
Feedback is very appreciated.

=item *
Documentation is in the work. Either see the SYNOPSIS above
or the samples in the F<samples> directory.

=back

=head1 AUTHOR

Aldo Calpini ( I<dada@perl.it> ).

=cut


