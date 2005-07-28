###############################################################################
#
# This file copyright (c) 2001 by Randy J. Ray, all rights reserved
#
# Copying and distribution are permitted under the terms of the Artistic
# License as distributed with Perl versions 5.005 and later. See
# http://www.opensource.org/licenses/artistic-license.php
#
###############################################################################
#
#   $Id: Parser.pm,v 1.12 2004/12/09 08:50:18 rjray Exp $
#
#   Description:    This is the RPC::XML::Parser class, a container for the
#                   XML::Parser class. It was moved here from RPC::XML in
#                   order to reduce the weight of that module.
#
#   Functions:      new
#                   parse
#                   message_init
#                   tag_start
#                   error
#                   stack_error
#                   tag_end
#                   char_data
#
#   Libraries:      RPC::XML
#                   XML::Parser
#
#   Global Consts:  Uses $RPC::XML::ERROR
#
#   Environment:    None.
#
###############################################################################

package RPC::XML::Parser;

use 5.005;
use strict;
use vars qw($VERSION @ISA);
use subs qw(error stack_error new message_init message_end tag_start tag_end
            final char_data parse);

# These constants are only used by the internal stack machine
use constant PARSE_ERROR => 0;
use constant METHOD      => 1;
use constant METHODSET   => 2;
use constant RESPONSE    => 3;
use constant RESPONSESET => 4;
use constant STRUCT      => 5;
use constant ARRAY       => 6;
use constant DATATYPE    => 7;
use constant ATTR_SET    => 8;
use constant METHODNAME  => 9;
use constant VALUEMARKER => 10;
use constant PARAMSTART  => 11;
use constant PARAM       => 12;
use constant STRUCTMEM   => 13;
use constant STRUCTNAME  => 14;
use constant DATAOBJECT  => 15;
use constant PARAMLIST   => 16;
use constant NAMEVAL     => 17;
use constant MEMBERENT   => 18;
use constant METHODENT   => 19;
use constant RESPONSEENT => 20;
use constant FAULTENT    => 21;
use constant FAULTSTART  => 22;

# This is to identify valid types
use constant VALIDTYPES  => { map { $_, 1 } qw(int i4 string double reference
                                               boolean dateTime.iso8601
                                               base64) };
# This maps XML tags to stack-machine tokens
use constant TAG2TOKEN   => { methodCall        => METHOD,
                              methodResponse    => RESPONSE,
                              methodName        => METHODNAME,
                              params            => PARAMSTART,
                              param             => PARAM,
                              value             => VALUEMARKER,
                              fault             => FAULTSTART,
                              array             => ARRAY,
                              struct            => STRUCT,
                              member            => STRUCTMEM,
                              name              => STRUCTNAME  };

use XML::Parser;
require File::Spec;

require RPC::XML;

$VERSION = do { my @r=(q$Revision: 1.12 $=~/\d+/g); sprintf "%d."."%02d"x$#r,@r };

###############################################################################
#
#   Sub Name:       new
#
#   Description:    Constructor. Save any important attributes, leave the
#                   heavy lifting for the parse() routine and XML::Parser.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $class    in      scalar    Class we're initializing
#                   %attr     in      hash      Any extras the caller wants
#
#   Globals:        $RPC::XML::ERROR
#
#   Returns:        Success:    object ref
#                   Failure:    undef
#
###############################################################################
sub new
{
    my $class = shift;
    my %attrs = @_;

    my $self = {};
    %$self = %attrs if (keys %attrs);

    bless $self, $class;
}

###############################################################################
#
#   Sub Name:       parse
#
#   Description:    Parse the requested string or stream. This behaves mostly
#                   like parse() in the XML::Parser namespace, but does some
#                   extra, as well.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $stream   in      scalar    Either the string to parse or
#                                                 an open filehandle of sorts
#
#   Returns:        Success:    ref to request or response object
#                   Failure:    error string
#
###############################################################################
sub parse
{
    my $self = shift;
    my $stream = shift;

    my $parser = XML::Parser->new(Namespaces => 0, ParseParamEnt => 0,
                                  Handlers =>
                                  {
                                   Init      => sub { message_init $self, @_ },
                                   Start     => sub { tag_start    $self, @_ },
                                   End       => sub { tag_end      $self, @_ },
                                   Char      => sub { char_data    $self, @_ },
                                   Final     => sub { final        $self, @_ },
                                   ExternEnt => sub { extern_ent   $self, @_ },
                                  });

    # If there is no stream given, then create an incremental parser handle
    # and return it.
    return $parser->parse_start() unless $stream;

    my $retval;
    eval { $retval = $parser->parse($stream) };
    return $@ if $@;

    $retval;
}

# This is called when a new document is about to start parsing
sub message_init
{
    my $robj = shift;
    my $self = shift;

    $robj->{stack} = [];
    $self;
}

# This is called when the parsing process is complete
sub final
{
    my $robj = shift;
    my $self = shift;

    # Look at the top-most marker, it'll need to be one of the end cases
    my $marker = pop(@{$robj->{stack}});
    # There should be only on item on the stack after it
    my $retval = pop(@{$robj->{stack}});
    # If the top-most marker isn't the error marker, check the stack
    $retval = 'RPC::XML Error: Extra data on parse stack at document end'
        if ($marker != PARSE_ERROR and (@{$robj->{stack}}));

    $retval;
}

# This gets called each time an opening tag is parsed
sub tag_start
{
    my $robj = shift;
    my $self = shift;
    my $elem = shift;
    my %attr = @_;

    $robj->{cdata} = '';
    return if ($elem eq 'data');
    if (TAG2TOKEN->{$elem})
    {
        push(@{$robj->{stack}}, TAG2TOKEN->{$elem});
    }
    elsif (VALIDTYPES->{$elem})
    {
        # All datatypes are represented on the stack by this generic token
        push(@{$robj->{stack}}, DATATYPE);
        # If the tag is <base64> and we've been told to use filehandles, set
        # that up.
        if ($elem eq 'base64')
        {
            return unless ($robj->{base64_to_fh});
            require Symbol;
            my ($fh, $file) = (Symbol::gensym(), File::Spec->tmpdir);

            $file = $robj->{base64_temp_dir} if ($robj->{base64_temp_dir});
            $file  = File::Spec->catfile($file, 'b64' . $self->current_byte);
            unless (open($fh, "+> $file"))
            {
                push(@{$robj->{stack}},
                     "Error opening temp file for base64: $!", PARSE_ERROR);
                $self->finish;
            }
            unlink($file);
            $robj->{cdata} = $fh;
            $robj->{spooling_base64_data} = 1;
        }
    }
    else
    {
        push(@{$robj->{stack}},
             "Unknown tag encountered: $elem", PARSE_ERROR);
        $self->finish;
    }
}

# Very simple error-text generator, just to eliminate heavy reduncancy in the
# next sub:
sub error
{
    my $robj = shift;
    my $self = shift;
    my $mesg = shift;
    my $elem = shift || '';

    my $fmt = $elem ?
        '%s at document line %d, column %d (byte %d, closing tag %s)' :
        '%s at document line %d, column %d (byte %d)';

    push(@{$robj->{stack}},
         sprintf($fmt, $mesg, $self->current_line, $self->current_column,
                 $self->current_byte, $elem),
         PARSE_ERROR);
    $self->finish;
}

# A shorter-cut for stack integrity errors
sub stack_error
{
    my $robj = shift;
    my $self = shift;
    my $elem = shift;

    error($robj, $self, 'Stack corruption detected', $elem);
}

# This is a hairy subroutine-- what to do at the end-tag. The actions range
# from simply new-ing a datatype all the way to building the final object.
sub tag_end
{
    my $robj = shift;
    my $self = shift;
    my $elem = shift;

    my ($op, $attr, $obj, $class, $list, $name, $err);

    return if ($elem eq 'data');
    # This should always be one of the stack machine ops defined above
    $op = pop(@{$robj->{stack}});

    # Decide what to do from here
    if (VALIDTYPES->{$elem})
    {
        # This is the closing tag of one of the data-types.
        $class = $elem;
        # Cheaper than the regex that was here, and more locale-portable
        $class = 'datetime_iso8601' if ($class eq 'dateTime.iso8601');
        # Some minimal data-integrity checking
        if ($class eq 'int' or $class eq 'i4')
        {
            return error($robj, $self, 'Bad integer data read')
                unless ($robj->{cdata} =~ /^[-+]?\d+$/);
        }
        elsif ($class eq 'double')
        {
            return error($robj, $self, 'Bad floating-point data read')
                unless ($robj->{cdata} =~
                        # Taken from perldata(1)
                        /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/);
        }

        $class = "RPC::XML::$class";
        # The string at the end is only seen by the RPC::XML::base64 class
        $obj = $class->new($robj->{cdata}, 'base64 already encoded');
        return error($robj, $self, 'Error instantiating data object: ' .
                            $RPC::XML::ERROR)
            unless ($obj);
        push(@{$robj->{stack}}, $obj, DATAOBJECT);
        delete $robj->{spooling_base64_data}; # Just in case
    }
    elsif ($elem eq 'value')
    {
        # For <value></value>, there should already be a dataobject, or else
        # the marker token in which case the CDATA is used as a string value.
        if ($op == DATAOBJECT)
        {
            ($op, $obj) = splice(@{$robj->{stack}}, -2);
            return stack_error($robj, $self, $elem)
                unless ($op == VALUEMARKER);
        }
        elsif ($op == VALUEMARKER)
        {
            $obj = RPC::XML::string->new($robj->{cdata});
        }
        else
        {
            return error($robj, $self,
                         'No datatype found within <value> container');
        }

        push(@{$robj->{stack}}, $obj, DATAOBJECT);
    }
    elsif ($elem eq 'param')
    {
        # Almost like above, since this is really a NOP anyway
        return error($robj, $self, 'No <value> found within <param> container')
            unless ($op == DATAOBJECT);
        ($op, $obj) = splice(@{$robj->{stack}}, -2);
        return stack_error($robj, $self, $elem) unless ($op == PARAM);
        push(@{$robj->{stack}}, $obj, DATAOBJECT);
    }
    elsif ($elem eq 'params')
    {
        # At this point, there should be zero or more DATAOBJECT tokens on the
        # stack, each with a data object right below it.
        $list = [];
        return stack_error($robj, $self, $elem)
            unless ($op == DATAOBJECT or $op == PARAMSTART);
        while ($op == DATAOBJECT)
        {
            unshift(@$list, pop(@{$robj->{stack}}));
            $op = pop(@{$robj->{stack}});
        }
        # Now that we see something ! DATAOBJECT, it needs to be PARAMSTART
        return stack_error($robj, $self, $elem) unless ($op == PARAMSTART);
        push(@{$robj->{stack}}, $list, PARAMLIST);
    }
    elsif ($elem eq 'fault')
    {
        # If we're finishing up a fault definition, there needs to be a struct
        # on the stack.
        return stack_error($robj, $self, $elem) unless ($op == DATAOBJECT);
        ($op, $obj) = splice(@{$robj->{stack}}, -2);
        return error($robj, $self,
                     'Only a <struct> value may be within a <fault>')
            unless ($obj->isa('RPC::XML::struct'));

        $obj = RPC::XML::fault->new($obj);
        return error($robj, $self, 'Unable to instantiate fault object: ' .
                            $RPC::XML::ERROR)
            unless $obj;
        push(@{$robj->{stack}}, $obj, FAULTENT);
    }
    elsif ($elem eq 'member')
    {
        # We need to see a DATAOBJECT followed by a STRUCTNAME
        return stack_error($robj, $self, $elem) unless ($op == DATAOBJECT);
        ($op, $obj) = splice(@{$robj->{stack}}, -2);
        return stack_error($robj, $self, $elem) unless ($op == STRUCTNAME);
        # Get the name off the stack to clear the way for the STRUCTMEM marker
        # under it
        ($op, $name) = splice(@{$robj->{stack}}, -2);
        # Push the name back on, with the value and the new marker (STRUCTMEM)
        push(@{$robj->{stack}}, $name, $obj, STRUCTMEM);
    }
    elsif ($elem eq 'name')
    {
        # Fairly simple: just push the current content of CDATA on w/ a marker
        push(@{$robj->{stack}}, $robj->{cdata}, STRUCTNAME);
    }
    elsif ($elem eq 'struct')
    {
        # Create the hash table in-place, then pass the ref to the constructor
        $list = {};
        # First off the stack needs to be STRUCTMEM or STRUCT
        return stack_error($robj, $self, $elem)
            unless ($op == STRUCTMEM or $op == STRUCT);
        while ($op == STRUCTMEM)
        {
            # Next on stack (in list-order): name, value
            ($name, $obj) = splice(@{$robj->{stack}}, -2);
            $list->{$name} = $obj;
            $op = pop(@{$robj->{stack}});
        }
        # Now that we see something ! STRUCTMEM, it needs to be STRUCT
        return stack_error($robj, $self, $elem) unless ($op == STRUCT);
        $obj = RPC::XML::struct->new($list);
        return error($robj, $self,
                     'Error creating a RPC::XML::struct object: ' .
                     $RPC::XML::ERROR)
            unless $obj;
        push(@{$robj->{stack}}, $obj, DATAOBJECT);
    }
    elsif ($elem eq 'array')
    {
        # This is similar in most ways to struct creation, save for the lack
        # of naming for the elements.
        # Create the list in-place, then pass the ref to the constructor
        $list = [];
        # Only DATAOBJECT or ARRAY should be visible
        return stack_error($robj, $self, $elem)
            unless ($op == DATAOBJECT or $op == ARRAY);
        while ($op == DATAOBJECT)
        {
            unshift(@$list, pop(@{$robj->{stack}}));
            $op = pop(@{$robj->{stack}});
        }
        # Now that we see something ! DATAOBJECT, it needs to be ARRAY
        return stack_error($robj, $self, $elem) unless ($op == ARRAY);
        $obj = RPC::XML::array->new($list);
        return error($robj, $self,
                     'Error creating a RPC::XML::array object: ' .
                     $RPC::XML::ERROR)
            unless $obj;
        push(@{$robj->{stack}}, $obj, DATAOBJECT);
    }
    elsif ($elem eq 'methodName')
    {
        return error($robj, $self,
                     "<$elem> tag must immediately follow a <methodCall> tag")
            unless ($robj->{stack}->[$#{$robj->{stack}}] == METHOD);
        push(@{$robj->{stack}}, $robj->{cdata}, NAMEVAL);
    }
    elsif ($elem eq 'methodCall')
    {
        # A methodCall closing should have on the stack an optional PARAMLIST
        # marker, a NAMEVAL marker, then the METHOD token from the
        # opening tag. An ATTR_SET may follow the METHOD token.
        if ($op == PARAMLIST)
        {
            ($op, $list) = splice(@{$robj->{stack}}, -2);
        }
        else
        {
            $list = [];
        }
        if ($op == NAMEVAL)
        {
            ($op, $name) = splice(@{$robj->{stack}}, -2);
        }
        return error($robj, $self,
                     "No methodName tag detected during methodCall parsing")
            unless $name;
        return stack_error($robj, $self, $elem) unless ($op == METHOD);
        # Create the request object and push it on the stack
        $obj = RPC::XML::request->new($name, @$list);
        return error($robj, $self,
                     "Error creating request object: $RPC::XML::ERROR")
            unless $obj;
        push(@{$robj->{stack}}, $obj, METHODENT);
    }
    elsif ($elem eq 'methodResponse')
    {
        # A methodResponse closing should have on the stack only the
        # DATAOBJECT marker, then the RESPONSE token from the opening tag.
        if ($op == PARAMLIST)
        {
            # To my knowledge, the XML-RPC spec limits the params list for
            # a response to exactly one object. Extract it from the listref
            # and put it back.
            $list = pop(@{$robj->{stack}});
            return error($robj, $self,
                         "Params list for <$elem> tag invalid")
                unless (@$list == 1);
            $obj = $list->[0];
            return error($robj, $self,
                         "Returned value on stack not a type reference")
                unless (ref $obj and $obj->isa('RPC::XML::datatype'));
            push(@{$robj->{stack}}, $obj);
        }
        elsif (! ($op == DATAOBJECT or $op == FAULTENT))
        {
            return error($robj, $self,
                         "No parameter was declared for the <$elem> tag");
        }
        ($op, $list) = splice(@{$robj->{stack}}, -2);
        return stack_error($robj, $self, $elem) unless ($op == RESPONSE);
        # Create the response object and push it on the stack
        $obj = RPC::XML::response->new($list);
        return error($robj, $self,
                     "Error creating response object: $RPC::XML::ERROR")
            unless $obj;
        push(@{$robj->{stack}}, $obj, RESPONSEENT);
    }
}

# This just spools the character data until a closing tag makes use of it
sub char_data
{
    my $robj = shift;
    my $self = shift;
    my $data = shift;

    if ($robj->{spooling_base64_data})
    {
        print { $robj->{cdata} } $data;
    }
    else
    {
        $robj->{cdata} .= $data;
    }
}

# At some future point, this may be expanded to provide more entities than
# just the four basic XML ones.
sub extern_ent
{
    my $robj = shift;
    local $" = ', ';
    warn ref($robj) . '::extern_ent: Attempt to reference external entity ' .
        "(@_)\n";
    return '';
}

1;

__END__

=head1 NAME

RPC::XML::Parser - A container class for XML::Parser

=head1 SYNOPSIS

    use RPC::XML::Parser;
    ...
    $P = RPC::XML::Parser->new();
    $P->parse($message);

=head1 DESCRIPTION

The B<RPC::XML::Parser> class encapsulates the parsing process, for turning a
string or an input stream into a B<RPC::XML::request> or B<RPC::XML::response>
object. The B<XML::Parser> class is used internally, with a new instance
created for each call to C<parse> (detailed below). This allows the
B<RPC::XML::Parser> object to be reusable, even though the B<XML::Parser>
objects are not. The methods are:

=over 4

=item new([ARGS])

Create a new instance of the class. Any extra data passed to the constructor
is taken as key/value pairs (B<not> a hash reference) and attached to the
object.

The following parameters are currently recognized:

=over 8

=item base64_to_fh

If passed with a true value, this tells the parser that incoming Base64 data
is to be spooled to a filehandle opened onto an anonymous temporary file. The
file itself is unlinked after opening, though the resulting B<RPC::XML::base64>
object can use its C<to_file> method to save the data to a specific file at a
later point. No checks on size are made; if this option is set, B<all> Base64
data goes to filehandles.

=item base64_temp_dir

If this argument is passed, the value is taken as the directory under which
the temporary files are created. This is so that the application is not locked
in to the list of directories that B<File::Spec> defaults to with its
C<tmpdir> method. If this is not passed, the previously-mentioned method is
used to derive the directory in which to create the temporary files. Only
relevant if B<base64_to_fh> is set.

=back

=item parse [ { STRING | STREAM } ]

Parse the XML document specified in either a string or a stream. The stream
may be any file descriptor, derivative of B<IO::Handle>, etc. The return
value is either an object reference (to one of B<RPC::XML::request> or
B<RPC::XML::response>) or an error string. Any non-reference return value
should be treated as an error condition.

If no argument is given, then the C<parse_start> method of B<XML::Parser> is
used to create a B<XML::Parser::ExpatNB> object, which is returned. This
object may then be used to parse the data in chunks, rather than a steady
stream. See the B<XML::Parser> manual page for more details on how this
works.

=back

=head1 DIAGNOSTICS

The constructor returns C<undef> upon failure, with the error message available
in the global variable B<C<$RPC::XML::ERROR>>.

=head1 CAVEATS

This began as a reference implementation in which clarity of process and
readability of the code took precedence over general efficiency. It is now
being maintained as production code, but may still have parts that could be
written more efficiently.

=head1 CREDITS

The B<XML-RPC> standard is Copyright (c) 1998-2001, UserLand Software, Inc.
See <http://www.xmlrpc.com> for more information about the B<XML-RPC>
specification.

=head1 LICENSE

This module is licensed under the terms of the Artistic License that covers
Perl. See <http://www.opensource.org/licenses/artistic-license.php> for the
license itself.

=head1 SEE ALSO

L<RPC::XML>, L<RPC::XML::Client>, L<RPC::XML::Server>, L<XML::Parser>

=head1 AUTHOR

Randy J. Ray <rjray@blackperl.com>

=cut
