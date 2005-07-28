###############################################################################
#
# This file copyright (c) 2002 by Randy J. Ray, all rights reserved
#
# Copying and distribution are permitted under the terms of the Artistic
# License as distributed with Perl versions 5.005 and later. See
# http://www.opensource.org/licenses/artistic-license.php
#
###############################################################################
#
#   $Id: Function.pm,v 1.3 2004/12/09 08:50:17 rjray Exp $
#
#   Description:    This is a type of Procedure that does no signature tests
#                   at either creation or invocation.
#
#   Functions:      new (superclass new expects signatures)
#                   signature
#                   make_sig_table (called by some superclass methods)
#                   clone
#                   is_valid
#                   match_signature
#
#   Libraries:      RPC::XML::Procedure (base class)
#
#   Global Consts:  $VERSION
#
#   Environment:    None
#
###############################################################################

package RPC::XML::Function;

use 5.005;
use strict;
use vars qw($VERSION @ISA);
use subs qw(new signature make_sig_table clone is_valid match_signature);

use AutoLoader 'AUTOLOAD';

require RPC::XML::Procedure;

@ISA = qw(RPC::XML::Procedure);
$VERSION = do { my @r=(q$Revision: 1.3 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };

###############################################################################
#
#   Sub Name:       new
#
#   Description:    Create a new object of this class, storing the info on
#                   regular keys (no obfuscation used here).
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $class    in      scalar    Class to bless into
#                   @argz     in      variable  Disposition is variable; see
#                                                 below
#
#   Returns:        Success:    object ref
#                   Failure:    error string
#
###############################################################################
sub new
{
    #
    # This is largely a verbatim-copy of RPC::XML::Procedure::new. I plan on
    # going back and coming up with a way for this class to be able to use
    # the super-class new, but this is sufficient for now.
    #

    my $class = shift;
    my @argz  = @_;

    my $data; # This will be a hashref that eventually gets blessed

    $class = ref($class) || $class;

    #
    # There are three things that @argz could be:
    #
    if (ref $argz[0])
    {
        # 1. A hashref containing all the relevant keys
        $data = {};
        %$data = %{$argz[0]};
    }
    elsif (@argz == 1)
    {
        # 2. Exactly one non-ref element, a file to load

        # And here is where I cheat in a way that makes even me uncomfortable.
        #
        # Loading code from an XPL file, it can actually be of a type other
        # than how this constructor was called. So what we are going to do is
        # this: If $class is undef, that can only mean that we were called
        # with the intent of letting the XPL file dictate the resulting object.
        # If $class is set, then we'll call load_XPL_file normally, as a
        # method, to allow for subclasses to tweak things.
        if (defined $class)
        {
            $data = $class->load_XPL_file($argz[0]);
            return $data unless ref $data; # load_XPL_path signalled an error
        }
        else
        {
            # Spoofing the "class" argument to load_XPL_file makes me feel
            # even dirtier...
            $data = load_XPL_file(\$class, $argz[0]);
            return $data unless ref $data; # load_XPL_path signalled an error
            $class = "RPC::XML::$class";
        }
    }
    else
    {
        # 3. If there is more than one arg, it's a sort-of-hash. That is, the
        #    key 'signature' is allowed to repeat. (But this class ignores it)
        my ($key, $val);
        $data = {};
        while (@argz)
        {
            ($key, $val) = splice(@argz, 0, 2);
            if ($key eq 'signature')
            {
                # Noop
                next;
            }
            elsif (exists $data->{$key})
            {
                return "${class}::new: Key '$key' may not be repeated";
            }
            else
            {
                $data->{$key} = $val;
            }
        }
    }

    return "${class}::new: Missing required data"
        unless ($data->{name} and $data->{code});
    bless $data, $class;
}

#
# These two are only implemented here at all, because some of the logic in
# other places call them
#
sub signature      { undef; }
sub make_sig_table { $_[0]; }

1;

=pod

=head1 NAME

RPC::XML::Function - Object class for RPC routines that do not check signatures

=head1 SYNOPSIS

    require RPC::XML::Function;

    ...
    $method_1 = RPC::XML::Function->new(name => 'system.identity',
                                        code => sub { ... });
    $method_2 = RPC::XML::Function->new('/path/to/status.xpl');

=head1 DESCRIPTION

The B<RPC::XML::Function> is a class that derives from B<RPC::XML::Procedure>
(see L<RPC::XML::Procedure>), while bypassing all the signature-specific logic
associated with server-side methods in the B<RPC::XML> suite.

By doing this, the encapsulated code becomes responsible for how the server
(and ultimately, the client) interprets returned values. For the classes that
adhere to signatures, the signature includes the expected type of the returned
value. If an object of this class anticipates that the data may be ambiguous
(an intended string being interpreted as an integer, for example), the code
it encapsulates should consider encoding the response with the data-classes
documented in L<RPC::XML> prior to return.

=head1 USAGE

Only those routines different from B<RPC::XML::Procedure> are listed:

=over 4

=item new(LIST)

The constructor for this class is identical to the super-class versions,
except that it disregards any C<signature> keys on the input list. The
return value upon success is a newly-blessed object reference, otherwise
an error message is returned.

=item signature

Returns C<undef> only.

=item make_sig_table

This method does nothing, though in keeping with the interface from the
parent class, it returns the object reference to permit chaining methods
together.

=item clone

Acts as the parent C<clone> method, save that in the absence of any signature
data, the clone is in fact a perfect copy of the original.

=item is_valid

Uses the same validity test, minus the checking of signature data (tests only
for valid C<name> and C<code> keys).

=item match_signature

Always returns the string, C<scalar>.

=back

=head1 DIAGNOSTICS

Unless otherwises specified, routines return the object reference itself upon
a successful operation, and an error string (which is not a blessed reference)
upon error.

=head1 LICENSE

This module is licensed under the terms of the Artistic License that covers
Perl. See <http://www.opensource.org/licenses/artistic-license.php> for the
license itself.

=head1 SEE ALSO

L<RPC::XML>, L<RPC::XML::Procedure>, L<make_method>

=head1 AUTHOR

Randy J. Ray <rjray@blackperl.com>

=cut

__END__

#
# These are the same as RPC::XML::Procedure subs, except that they have no
# references to signatures.
#
###############################################################################
#
#   Sub Name:       clone
#
#   Description:    Create a copy of the invoking object.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#
#   Returns:        Success:    $new_self
#                   Failure:    error message
#
###############################################################################
sub clone
{
    my $self = shift;

    my $new_self = {};
    %$new_self = %$self;

    bless $new_self, ref($self);
}

###############################################################################
#
#   Sub Name:       is_valid
#
#   Description:    Boolean test to tell if the calling object has sufficient
#                   data to be used as a server method for RPC::XML::Server or
#                   Apache::RPC::Server.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object to test
#
#   Returns:        Success:    1, valid/complete
#                   Failure:    0, invalid/incomplete
#
###############################################################################
sub is_valid
{
    my $self = shift;

    return ((ref($self->{code}) eq 'CODE') and $self->{name});
}

###############################################################################
#
#   Sub Name:       match_signature
#
#   Description:    Noop. Needed for RPC::XML::Server.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $sig      in      scalar    Signature to check for
#
#   Returns:        Success:    return type as a string
#                   Failure:    0
#
###############################################################################
sub match_signature
{
    'scalar';
}
