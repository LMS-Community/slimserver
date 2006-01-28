package Win32::API;

# See the bottom of this file for the POD documentation.  Search for the
# string '=head'.

#######################################################################
#
# Win32::API - Perl Win32 API Import Facility
# 
# Version: 0.41 
# Date: 10 Mar 2003
# Author: Aldo Calpini <dada@perl.it>
# $Id$
#######################################################################

require Exporter;       # to export the constants to the main:: space
require DynaLoader;     # to dynuhlode the module.
@ISA = qw( Exporter DynaLoader );

use vars qw( $DEBUG );
$DEBUG = 0;

sub DEBUG { 
    if ($Win32::API::DEBUG) { 
        printf @_ if @_ or return 1; 
    } else {
        return 0;
    }
}

use Win32::API::Type;
use Win32::API::Struct;

#######################################################################
# STATIC OBJECT PROPERTIES
#
$VERSION = "0.41";

#### some package-global hash to 
#### keep track of the imported 
#### libraries and procedures
my %Libraries = ();
my %Procedures = ();


#######################################################################
# dynamically load in the API extension module.
#
bootstrap Win32::API;

#######################################################################
# PUBLIC METHODS
#
sub new {
    my($class, $dll, $proc, $in, $out) = @_;
    my $hdll;   
    my $self = {};
  
    #### avoid loading a library more than once
    if(exists($Libraries{$dll})) {
        # print "Win32::API::new: Library '$dll' already loaded, handle=$Libraries{$dll}\n";
        $hdll = $Libraries{$dll};
    } else {
        # print "Win32::API::new: Loading library '$dll'\n";
        $hdll = Win32::API::LoadLibrary($dll);
        $Libraries{$dll} = $hdll;
    }

    #### if the dll can't be loaded, set $! to Win32's GetLastError()
    if(!$hdll) {
        $! = Win32::GetLastError();
        return undef;
    }

    #### determine if we have a prototype or not
    if( (not defined $in) and (not defined $out) ) {
        ($proc, $self->{in}, $self->{intypes}, $self->{out}) = parse_prototype( $proc );
        return undef unless $proc;
        $self->{proto} = 1;
    } else {
        $self->{in} = [];
        if(ref($in) eq 'ARRAY') {
            foreach (@$in) {
                push(@{ $self->{in} }, type_to_num($_));
            }   
        } else {
            my @in = split '', $in;
            foreach (@in) {
                push(@{ $self->{in} }, type_to_num($_));
            }           
        }
        $self->{out} = type_to_num($out);
    }

    #### first try to import the function of given name...
    my $hproc = Win32::API::GetProcAddress($hdll, $proc);

    #### ...then try appending either A or W (for ASCII or Unicode)
    if(!$hproc) {
        my $tproc = $proc;
        $tproc .= (IsUnicode() ? "W" : "A");
        # print "Win32::API::new: procedure not found, trying '$tproc'...\n";
        $hproc = Win32::API::GetProcAddress($hdll, $tproc);
    }

    #### ...if all that fails, set $! accordingly
    if(!$hproc) {
        $! = Win32::GetLastError();
        return undef;
    }
    
    #### ok, let's stuff the object
    $self->{procname} = $proc;
    $self->{dll} = $hdll;
    $self->{dllname} = $dll;
    $self->{proc} = $hproc;

    #### keep track of the imported function
    $Libraries{$dll} = $hdll;
    $Procedures{$dll}++;

    #### cast the spell
    bless($self, $class);
    return $self;
}

sub Import {
    my($class, $dll, $proc, $in, $out) = @_;
    $Imported{"$dll:$proc"} = Win32::API->new($dll, $proc, $in, $out) or return 0;
    my $P = (caller)[0];
    eval qq(
        sub ${P}::$Imported{"$dll:$proc"}->{procname} { \$Win32::API::Imported{"$dll:$proc"}->Call(\@_); }
    );
    return $@ ? 0 : 1;
}


#######################################################################
# PRIVATE METHODS
#
sub DESTROY {
    my($self) = @_;

    #### decrease this library's procedures reference count
    $Procedures{$self->{dllname}}--;

    #### once it reaches 0, free it
    if($Procedures{$self->{dllname}} == 0) {
        # print "Win32::API::DESTROY: Freeing library '$self->{dllname}'\n";
        Win32::API::FreeLibrary($Libraries{$self->{dllname}});
        delete($Libraries{$self->{dllname}});
    }    
}

sub type_to_num {
    my $type = shift;
    my $out = shift;
    my $num;
    
    if(     $type eq 'N'
    or      $type eq 'n'
    or      $type eq 'l'
    or      $type eq 'L'
    ) {
        $num = 1;
    } elsif($type eq 'P'
    or      $type eq 'p'
    ) {
        $num = 2;
    } elsif($type eq 'I'
    or      $type eq 'i'
    ) {
        $num = 3;
    } elsif($type eq 'f'
    or      $type eq 'F'
    ) {
        $num = 4;
    } elsif($type eq 'D'
    or      $type eq 'd'
    ) {
        $num = 5;
    } elsif($type eq 'c'
    or      $type eq 'C'
    ) {
        $num = 6;
    } else {
        $num = 0;
    }       
    unless(defined $out) {
        if(     $type eq 's'
        or      $type eq 'S'
        ) {
            $num = 51;
        } elsif($type eq 'b'
        or      $type eq 'B'
        ) {
            $num = 22;
        } elsif($type eq 'k'
        or      $type eq 'K'
        ) {
            $num = 101;
        }       
    }
    return $num;
}

sub parse_prototype {
    my($proto) = @_;
    
    my @in_params = ();
    my @in_types = ();
    if($proto =~ /^\s*(\S+)\s+(\S+)\s*\(([^\)]*)\)/) {
        my $ret = $1;
        my $proc = $2;
        my $params = $3;
        
        $params =~ s/^\s+//;
        $params =~ s/\s+$//;
        
        DEBUG "(PM)parse_prototype: got PROC '%s'\n", $proc;
        DEBUG "(PM)parse_prototype: got PARAMS '%s'\n", $params;
        
        foreach my $param (split(/\s*,\s*/, $params)) {
            my($type, $name);
            if($param =~ /(\S+)\s+(\S+)/) {
                ($type, $name) = ($1, $2);
            }
            
            if(Win32::API::Type::is_known($type)) {
                if(Win32::API::Type::is_pointer($type)) {
                    DEBUG "(PM)parse_prototype: IN='%s' PACKING='%s' API_TYPE=%d\n",
                        $type, 
                        Win32::API::Type->packing( $type ), 
                        type_to_num('P');
                    push(@in_params, type_to_num('P'));
                } else {        
                    DEBUG "(PM)parse_prototype: IN='%s' PACKING='%s' API_TYPE=%d\n",
                        $type, 
                        Win32::API::Type->packing( $type ), 
                        type_to_num( Win32::API::Type->packing( $type ) );
                    push(@in_params, type_to_num( Win32::API::Type->packing( $type ) ));
                }
            } elsif( Win32::API::Struct::is_known( $type ) ) {
                DEBUG "(PM)parse_prototype: IN='%s' PACKING='%s' API_TYPE=%d\n",
                    $type, 'S', type_to_num('S');
                push(@in_params, type_to_num('S'));
            } else {
                warn "Win32::API::parse_prototype: WARNING unknown parameter type '$type'";
                push(@in_params, type_to_num('I'));
            }
            push(@in_types, $type);
            
        }
        DEBUG "parse_prototype: IN=[ @in_params ]\n";


            
        if(Win32::API::Type::is_known($ret)) {
            if(Win32::API::Type::is_pointer($ret)) {
                DEBUG "parse_prototype: OUT='%s' PACKING='%s' API_TYPE=%d\n",
                    $ret, 
                    Win32::API::Type->packing( $ret ), 
                    type_to_num('P');
                return ( $proc, \@in_params, \@in_types, type_to_num('P') );
            } else {        
                DEBUG "parse_prototype: OUT='%s' PACKING='%s' API_TYPE=%d\n",
                    $ret, 
                    Win32::API::Type->packing( $ret ), 
                    type_to_num( Win32::API::Type->packing( $ret ) );
                return ( $proc, \@in_params, \@in_types, type_to_num(Win32::API::Type->packing($ret)) );
            }
        } else {
            warn "Win32::API::parse_prototype: WARNING unknown output parameter type '$ret'";
            return ( $proc, \@in_params, \@in_types, type_to_num('I') );
        }

    } else {
        warn "Win32::API::parse_prototype: bad prototype '$proto'";
        return undef;
    }
}   

1;

__END__

#######################################################################
# DOCUMENTATION
#

=head1 NAME

Win32::API - Perl Win32 API Import Facility

=head1 SYNOPSIS

  #### Method 1: with prototype

  use Win32::API;
  $function = Win32::API->new(
      'mydll, 'int sum_integers(int a, int b)',
  );
  $return = $function->Call(3, 2);
  
  #### Method 2: with parameter list
  
  use Win32::API;
  $function = Win32::API->new(
      'mydll', 'sum_integers', 'II', 'I',
  );
  $return = $function->Call(3, 2);
  
  #### Method 3: with Import
  
  use Win32::API;
  Win32::API->Import(
      'mydll', 'int sum_integers(int a, int b)',
  );  
  $return = sum_integers(3, 2);


=for LATER-UNIMPLEMENTED
  #### or
  use Win32::API mydll => 'int sum_integers(int a, int b)';
  $return = sum_integers(3, 2);


=head1 ABSTRACT

With this module you can import and call arbitrary functions
from Win32's Dynamic Link Libraries (DLL), without having
to write an XS extension. Note, however, that this module 
can't do anything (parameters input and output is limited 
to simpler cases), and anyway a regular XS extension is
always safer and faster. 

The current version of Win32::API is available at my website:

  http://dada.perl.it/

It's also available on your nearest CPAN mirror (but allow a few days 
for worldwide spreading of the latest version) reachable at:

  http://www.perl.com/CPAN/authors/Aldo_Calpini/

A short example of how you can use this module (it just gets the PID of 
the current process, eg. same as Perl's internal C<$$>):

    use Win32::API;
    Win32::API->Import("kernel32", "int GetCurrentProcessId()");
    $PID = GetCurrentProcessId();

The possibilities are nearly infinite (but not all are good :-).
Enjoy it.


=head1 CREDITS

All the credits go to Andrea Frosini 
for the neat assembler trick that makes this thing work.
I've also used some work by Dave Roth for the prototyping stuff.
A big thank you also to Gurusamy Sarathy for his
unvaluable help in XS development, and to all the Perl community for
being what it is.


=head1 DESCRIPTION

To use this module put the following line at the beginning of your script:

    use Win32::API;

You can now use the C<new()> function of the Win32::API module to create a
new Win32::API object (see L<IMPORTING A FUNCTION>) and then invoke the 
C<Call()> method on this object to perform a call to the imported API
(see L<CALLING AN IMPORTED FUNCTION>).

Starting from version 0.40, you can also avoid creating a Win32::API object
and instead automatically define a Perl sub with the same name of the API
function you're importing. The details of the API definitions are the same,
just the call is different:

    my $GetCurrentProcessId = Win32::API->new(
        "kernel32", "int GetCurrentProcessId()"
    );
    my $PID = $GetCurrentProcessId->Call();

    #### vs.

    Win32::API->Import("kernel32", "int GetCurrentProcessId()");
    $PID = GetCurrentProcessId();

Note that C<Import> returns 1 on success and 0 on failure (in which case you
can check the content of C<$^E>). 

=head2 IMPORTING A FUNCTION

You can import a function from a 32 bit Dynamic Link Library (DLL) file 
with the C<new()> function. This will create a Perl object that contains the
reference to that function, which you can later C<Call()>.

What you need to know is the prototype of the function you're going to import
(eg. the definition of the function expressed in C syntax).

Starting from version 0.40, there are 2 different approaches for this step:
(the preferred) one uses the prototype directly, while the other (now deprecated)
one uses Win32::API's internal representation for parameters.

=head2 IMPORTING A FUNCTION BY PROTOTYPE

You need to pass 2 parameters:

=over 4

=item 1.
The name of the library from which you want to import the function.

=item 2.
The C prototype of the function.

=back

See L<Win32::API::Type> for a list of the known parameter types and
L<Win32::API::Struct> for information on how to define a structure.

=head2 IMPORTING A FUNCTION WITH A PARAMETER LIST

You need to pass 4 parameters:

=over 4

=item 1.
The name of the library from which you want to import the function.

=item 2.
The name of the function (as exported by the library).

=item 3.
The number and types of the arguments the function expects as input.

=item 4.
The type of the value returned by the function.

=back

To better explain their meaning, let's suppose that we
want to import and call the Win32 API C<GetTempPath()>.
This function is defined in C as:

    DWORD WINAPI GetTempPathA( DWORD nBufferLength, LPSTR lpBuffer );

This is documented in the B<Win32 SDK Reference>; you can look
for it on the Microsoft's WWW site, or in your C compiler's 
documentation, if you own one.

=over 4

=item B<1.>

The first parameter is the name of the library file that 
exports this function; our function resides in the F<KERNEL32.DLL>
system file.
When specifying this name as parameter, the F<.DLL> extension
is implicit, and if no path is given, the file is searched through
a couple of directories, including: 

=over 4

=item 1. The directory from which the application loaded. 

=item 2. The current directory. 

=item 3. The Windows system directory (eg. c:\windows\system or system32).

=item 4. The Windows directory (eg. c:\windows).

=item 5. The directories that are listed in the PATH environment variable. 

=back

So, you don't have to write F<C:\windows\system\kernel32.dll>; 
only F<kernel32> is enough:

    $GetTempPath = new Win32::API('kernel32', ...

=item B<2.>

Now for the second parameter: the name of the function.
It must be written exactly as it is exported 
by the library (case is significant here). 
If you are using Windows 95 or NT 4.0, you can use the B<Quick View> 
command on the DLL file to see the function it exports. 
Remember that you can only import functions from 32 bit DLLs:
in Quick View, the file's characteristics should report
somewhere "32 bit word machine"; as a rule of thumb,
when you see that all the exported functions are in upper case,
the DLL is a 16 bit one and you can't use it. 
If their capitalization looks correct, then it's probably a 32 bit
DLL.

Also note that many Win32 APIs are exported twice, with the addition of
a final B<A> or B<W> to their name, for - respectively - the ASCII 
and the Unicode version.
When a function name is not found, Win32::API will actually append
an B<A> to the name and try again; if the extension is built on a
Unicode system, then it will try with the B<W> instead.
So our function name will be:

    $GetTempPath = new Win32::API('kernel32', 'GetTempPath', ...

In our case C<GetTempPath> is really loaded as C<GetTempPathA>.

=item B<3.>

The third parameter, the input parameter list, specifies how many 
arguments the function wants, and their types. It can be passed as
a single string, in which each character represents one parameter, 
or as a list reference. The following forms are valid:

    "abcd"
    [a, b, c, d]
    \@LIST

But those are not:

    (a, b, c, d)
    @LIST

The number of characters, or elements in the list, specifies the number 
of parameters, and each character or element specifies the type of an 
argument; allowed types are:

=over 4

=item C<I>: 
value is an integer (int)

=item C<N>: 
value is a number (long)

=item C<F>: 
value is a floating point number (float)

=item C<D>: 
value is a double precision number (double)

=item C<C>: 
value is a char (char)

=item C<P>: 
value is a pointer (to a string, structure, etc...)

=item C<S>: 
value is a Win32::API::Struct object (see below)

=item C<K>:
value is a Win32::API::Callback object (see L<Win32::API::Callback>)

=back

Our function needs two parameters: a number (C<DWORD>) and a pointer to a 
string (C<LPSTR>):

    $GetTempPath = new Win32::API('kernel32', 'GetTempPath', 'NP', ...

=item B<4.>

The fourth and final parameter is the type of the value returned by the 
function. It can be one of the types seen above, plus another type named B<V> 
(for C<void>), used for functions that do not return a value.
In our example the value returned by GetTempPath() is a C<DWORD>, so 
our return type will be B<N>:

    $GetTempPath = new Win32::API('kernel32', 'GetTempPath', 'NP', 'N');

Now the line is complete, and the GetTempPath() API is ready to be used
in Perl. Before calling it, you should test that $GetTempPath is 
C<defined>, otherwise either the function or the library could not be
loaded; in this case, C<$!> will be set to the error message reported 
by Windows.
Our definition, with error checking added, should then look like this:

    $GetTempPath = new Win32::API('kernel32', 'GetTempPath', 'NP', 'N');
    if(not defined $GetTempPath) {
        die "Can't import API GetTempPath: $!\n";
    }

=back

=head2 CALLING AN IMPORTED FUNCTION

To effectively make a call to an imported function you must use the
Call() method on the Win32::API object you created.
Continuing with the example from the previous paragraph, 
the GetTempPath() API can be called using the method:

    $GetTempPath->Call(...

Of course, parameters have to be passed as defined in the import phase.
In particular, if the number of parameters does not match (in the example,
if GetTempPath() is called with more or less than two parameters), 
Perl will C<croak> an error message and C<die>.

The two parameters needed here are the length of the buffer
that will hold the returned temporary path, and a pointer to the 
buffer itself.
For numerical parameters, you can use either a constant expression
or a variable, while B<for pointers you must use a variable name> (no 
Perl references, just a plain variable name).
Also note that B<memory must be allocated before calling the function>,
just like in C.
For example, to pass a buffer of 80 characters to GetTempPath(),
it must be initialized before with:

    $lpBuffer = " " x 80;

This allocates a string of 80 characters. If you don't do so, you'll
probably get C<Runtime exception> errors, and generally nothing will 
work. The call should therefore include:

    $lpBuffer = " " x 80;
    $GetTempPath->Call(80, $lpBuffer);

And the result will be stored in the $lpBuffer variable.
Note that you don't need to pass a reference to the variable
(eg. you B<don't need> C<\$lpBuffer>), even if its value will be set 
by the function. 

A little problem here is that Perl does not trim the variable, 
so $lpBuffer will still contain 80 characters in return; the exceeding 
characters will be spaces, because we said C<" " x 80>.

In this case we're lucky enough, because the value returned by 
the GetTempPath() function is the length of the string, so to get
the actual temporary path we can write:

    $lpBuffer = " " x 80;
    $return = $GetTempPath->Call(80, $lpBuffer);
    $TempPath = substr($lpBuffer, 0, $return);

If you don't know the length of the string, you can usually
cut it at the C<\0> (ASCII zero) character, which is the string
delimiter in C:

    $TempPath = ((split(/\0/, $lpBuffer))[0];  
    # or    
    $lpBuffer =~ s/\0.*$//;

=head2 USING STRUCTURES

Starting from version 0.40, Win32::API comes with a support package
named Win32::API::Struct. The package is loaded automatically with
Win32::API, so you don't need to use it explicitly.

With this module you can conveniently define structures and use
them as parameters to Win32::API functions. A short example follows:


    # the 'POINT' structure is defined in C as:
    #     typedef struct {
    #        LONG  x;
    #        LONG  y;
    #     } POINT;
    

    #### define the structure
    Win32::API::Struct->typedef( POINT => qw{
        LONG x; 
        LONG y; 
    });
    
    #### import an API that uses this structure
    Win32::API->Import('user32', 'BOOL GetCursorPos(LPPOINT lpPoint)');
    
    #### create a 'POINT' object
    my $pt = Win32::API::Struct->new('POINT');
    
    #### call the function passing our structure object
    GetCursorPos($pt);
    
    #### and now, access its members
    print "The cursor is at: $pt->{x}, $pt->{y}\n";

Note that this works only when the function wants a 
B<pointer to a structure>: as you can see, our structure is named 
'POINT', but the API used 'LPPOINT'. 'LP' is automatically added at 
the beginning of the structure name when feeding it to a Win32::API
call.

For more information, see also L<Win32::API::Struct>.

If you don't want (or can't) use the Win32::API::Struct facility,
you can still use the low-level approach to use structures:


=over 4

=item 1.
you have to pack() the required elements in a variable:

    $lpPoint = pack('LL', 0, 0); # store two LONGs

=item 2. to access the values stored in a structure, unpack() it as required:

    ($x, $y) = unpack('LL', $lpPoint); # get the actual values

=back


The rest is left as an exercise to the reader...


=head1 AUTHOR

Aldo Calpini ( I<dada@perl.it> ).

=cut


