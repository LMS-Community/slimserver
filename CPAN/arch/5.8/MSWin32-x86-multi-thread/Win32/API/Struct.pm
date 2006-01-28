package Win32::API::Struct;

# See the bottom of this file for the POD documentation.  Search for the
# string '=head'.

#######################################################################
#
# Win32::API::Struct - Perl Win32 API struct Facility
# 
# Version: 0.40 
# Date: 07 Mar 2003
# Author: Aldo Calpini <dada@perl.it>
# $Id$
#######################################################################

$VERSION = "0.40";

use Win32::API::Type;

use Carp;

require Exporter;       # to export the constants to the main:: space
require DynaLoader;     # to dynuhlode the module.
@ISA = qw( Exporter DynaLoader );

my %Known = ();

sub DEBUG { 
    if ($Win32::API::DEBUG) { 
        printf @_ if @_ or return 1; 
    } else {
        return 0;
    }
}

sub typedef {
    my $class = shift;
    my $struct = shift;
    my($type, $name);
    my $self = {
    	align 	=> undef,
        typedef => [],
    };
    while(defined($type = shift)) {
        $name = shift;
        $name =~ s/;$//;
        push( @{ $self->{typedef} }, [ recognize($type, $name) ] );
    }

    $Known{$struct} = $self;
    return 1;
}


sub recognize {
    my($type, $name) = @_;
    my($size, $packing);
    if(exists $Known{$type}) {
        $packing = ">";
        return $name, $packing, $type;
    } else {
        $packing = Win32::API::Type::packing($type);
        return undef unless defined $packing;           
        if($name =~ s/\[(.*)\]$//) {
            $size = $1;     
            $packing = $packing."*".$size;  
        }
        DEBUG "(PM)Struct::recognize got '$name', '$type' -> '$packing'\n";
        return $name, $packing, $type;
    }   
}

sub new {
    my $class = shift;
    my($type, $name);
    my $self = {
        typedef => [],
    };
    if($#_ == 0) {
        if(exists $Known{$_[0]}) {
            DEBUG "(PM)Struct::new: got '$_[0]'\n";
            $self->{typedef} = $Known{$_[0]}->{typedef};
            foreach my $member (@{ $self->{typedef} }) {
                ($name, $packing, $type) = @$member;
                if($packing eq '>') {
                    $self->{$name} = Win32::API::Struct->new($type);
                }
            }
            $self->{__typedef__} = $_[0];
        } else {
            carp "Unknown Win32::API::Struct '$_[0]'";
            return undef;
        }
    } else {
        while(defined($type = shift)) {
            $name = shift;
            # print "new: found member $name ($type)\n";
            if(not exists $Win32::API::Type::Known{$type}) {
                warn "Unknown Win32::API::Struct type '$type'";
                return undef;
            } else {
                push( @{ $self->{typedef} }, [ $name, $Win32::API::Type::Known{$type}, $type ] );
            }
        }
    }
    return bless $self;
}

sub members {
    my $self = shift;
    return map {$_->[0]} @{ $self->{typedef} };
}

sub sizeof {
    my $self = shift;
    my $size = 0;
    my $align = 0;
    my $first = undef;
    foreach my $member (@{ $self->{typedef} }) {
        my($name, $packing, $type) = @$member;
        
        if(ref( $self->{$name} ) eq "Win32::API::Struct") {
            $size += $self->{$name}->sizeof();
            # $align = $self->{$name}->sizeof() if $self->{$name}->sizeof() > $align;
        } else {        
            if($packing =~ /\w\*(\d+)/) {           
                $size += Win32::API::Type::sizeof($type) * $1;
            	$first = Win32::API::Type::sizeof($type) * $1 unless defined $first;
                DEBUG "(PM)Struct::sizeof: sizeof with member($name) now = ". $size. "\n";
            } else {            
                $size += Win32::API::Type::sizeof($type);
                $first = Win32::API::Type::sizeof($type) unless defined $first;
            	$align = Win32::API::Type::sizeof($type)
            		if Win32::API::Type::sizeof($type) > $align;                
                DEBUG "(PM)Struct::sizeof: sizeof with member($name) now = ". $size. "\n";
            }
        }
    }
    DEBUG "(PM)Struct::sizeof first=$first align=$align\n";
    #DEBUG "(PM)Struct::sizeof returning %d\n", $first + (scalar(@{ $self->{typedef} })-1) * $align;    
    #return $first + (scalar(@{ $self->{typedef} })-1) * $align;    
    DEBUG "(PM)Struct::sizeof returning %d\n", scalar(@{ $self->{typedef} }) * $align;    
	if(defined $align and $align > 0) {
    	return scalar(@{ $self->{typedef} }) * $align;
    } else {
    	return $size;
    }
    return $size;
}

sub align {
    my $self = shift;
	my $align = shift;
	
	if(not defined $align) {
		return $self->{align} unless $self->{align} eq 'auto';
		$align = 0;
		foreach my $member (@{ $self->{typedef} }) {
			my($name, $packing, $type) = @$member;

			if(ref( $self->{$name} ) eq "Win32::API::Struct") {
				 #### ????
			} else {        
				if($packing =~ /\w\*(\d+)/) {           
					#### ????
				} else {            
					$align = Win32::API::Type::sizeof($type)
						if Win32::API::Type::sizeof($type) > $align;                
				}
			}
		}
		return $align;	
	} else {
		$self->{align} = $align;	
	
	}
}

sub getPack {
    my $self = shift;
    my $packing = "";
    my($type, $name);
    my @items = ();
    my @recipients = ();    
    
    my $align = $self->align();
    
    foreach my $member (@{ $self->{typedef} }) {
        ($name, $type, $orig) = @$member;
        if($type eq '>') {
            my($subpacking, $subitems, $subrecipients) = $self->{$name}->getPack();
            
            DEBUG "(PM)Struct::getPack($self->{__typedef__}) ++ $subpacking\n";
            
            $packing .= $subpacking;
            push(@items, @$subitems);
            push(@recipients, @$subrecipients);
        } else {
            if($type =~ /\w\*(\d+)/) {
                my $size = $1;
                $type = "a$size";
            }
            
            DEBUG "(PM)Struct::getPack($self->{__typedef__}) ++ $type\n"; 
            
            if($type eq 'p') {
                $type = "L";
                push(@items, Win32::API::PointerTo($self->{$name}));
            } else {
                push(@items, $self->{$name});
            }
            $packing .= $type;
            
            if($Win32::API::Type::PackSize{$type} < $align) {
            	$packing .= ("x" x ($align - $Win32::API::Type::PackSize{$type}));
            }
            
            push(@recipients, $self);
        }
    }
    DEBUG "(PM)Struct::getPack: $self->{__typedef__}(buffer) = pack($packing, @items)\n";
    return($packing, [@items], [@recipients]);
}
    

sub Pack {
    my $self = shift;
    my($packing, $items, $recipients) = $self->getPack();
    DEBUG "(PM)Struct::Pack: $self->{__typedef__}(buffer) = pack($packing, @$items)\n";
    $self->{buffer} = pack($packing, @$items);
    if(DEBUG) {
        for my $i (0..$self->sizeof-1) {
            printf "    %3d: 0x%02x\n", $i, ord(substr($self->{buffer}, $i, 1));
        }
    }
    $self->{buffer_recipients} = $recipients
}

sub getUnpack {
    my $self = shift;
    my $packing = "";
    my($type, $name);
    my @items = ();
    my $align = $self->align();
    foreach my $member (@{ $self->{typedef} }) {
        ($name, $type, $orig) = @$member;
        if($type eq '>') {
            my($subpacking, @subitems) = $self->{$name}->getUnpack();
            
            DEBUG "(PM)Struct::getUnpack($self->{__typedef__}) ++ $subpacking\n";
            $packing .= $subpacking;
            
            
            push(@items, @subitems);
        } else {
            if($type =~ /\w\*(\d+)/) {
                my $size = $1;
                $type = "Z$size";
            }
          
          	#if($type eq 'p') {
			#	$packing .= 'Z*';
			#	DEBUG "(PM)Struct::getUnpack($self->{__typedef__}) ++ Z*\n";
			#} else {
				$packing .= $type;
				DEBUG "(PM)Struct::getUnpack($self->{__typedef__}) ++ $type\n";
			#}
            if($type ne 'p' and $type !~ /^Z(\d+)/ and $Win32::API::Type::PackSize{$type} < $align) {
				DEBUG "(PM)Struct::getUnpack %s(%d) < %d\n",
					$type, $Win32::API::Type::PackSize{$type}, $align
				;
            	$packing .= ("x" x ($align - $Win32::API::Type::PackSize{$type}));
            }

            push(@items, $name);
        }
    }
    DEBUG "(PM)Struct::getUnpack($self->{__typedef__}): unpack($packing, @items)\n";
    return($packing, @items);
}

sub Unpack {
    my $self = shift;
    my($packing, @items) = $self->getUnpack();
    my @itemvalue = unpack($packing, $self->{buffer});
    DEBUG "(PM)Struct::Unpack: unpack($packing, buffer) = @itemvalue\n";
    foreach my $i (0..$#items) {
        my $recipient = $self->{buffer_recipients}->[$i];
        DEBUG "(PM)Struct::Unpack: %s(%s) = '%s' (0x%08x)\n",
        	$recipient->{__typedef__},
        	$items[$i],
        	$itemvalue[$i],
        	$itemvalue[$i],
        ;       
        $recipient->{$items[$i]} = $itemvalue[$i];
        DEBUG "(PM)Struct::Unpack: self.$items[$i] = $self->{$items[$i]}\n";        
    }
}

sub FromMemory {
    my($self, $addr) = @_;
    DEBUG "(PM)Struct::FromMemory: doing Pack\n";
    $self->Pack();
    DEBUG "(PM)Struct::FromMemory: doing GetMemory( 0x%08x, %d )\n", $addr, $self->sizeof;
    $self->{buffer} = Win32::API::ReadMemory( $addr, $self->sizeof );
    $self->Unpack();
    DEBUG "(PM)Struct::FromMemory: doing Unpack\n";
    DEBUG "(PM)Struct::FromMemory: structure is now:\n";
    $self->Dump() if DEBUG;
    DEBUG "\n";
}

sub Dump {
    my $self = shift;
    my $prefix = shift;
    foreach my $member (@{ $self->{typedef} }) {
        ($name, $packing, $type) = @$member;
        if( ref($self->{$name}) ) {
            $self->{$name}->Dump($name);
        } else {        
            printf "%-20s %-20s %-20s\n", $prefix, $name, $self->{$name};
        }
    }
}   


sub is_known {
    my $name = shift;
    if(exists $Known{ $name }) {
    	return 1;
    } else {
    	if($name =~ s/^LP//) {
        	return exists $Known{ $name };
        }
        return 0;
    }
}

sub TIEHASH {
    return Win32::API::Struct::new(@_);
}

sub EXISTS {

}

sub FETCH {
    my $self = shift;
    my $key = shift;
    
    if($key eq 'sizeof') {
        return $self->sizeof;
    }
    my @members = map { $_->[0] } @{ $self->{typedef} };
    if(grep(/^\Q$key\E$/, @members)) {
        return $self->{$key};
    } else {
        warn "'$key' is not a member of Win32::API::Struct $self->{__typedef__}";
    }   
}

sub STORE {
    my $self = shift;
    my($key, $val) = @_;
    my @members = map { $_->[0] } @{ $self->{typedef} };
    if(grep(/^\Q$key\E$/, @members)) {
        $self->{$key} = $val;
    } else {
        warn "'$key' is not a member of Win32::API::Struct $self->{__typedef__}";
    }
}

sub FIRSTKEY {
    my $self = shift;
    my @members = map { $_->[0] } @{ $self->{typedef} };
    return $members[0]; 
}

sub NEXTKEY {
    my $self = shift;
    my $key = shift;
    my @members = map { $_->[0] } @{ $self->{typedef} };
    for my $i (0..$#members-1) {    
        return $members[$i+1] if $members[$i] eq $key;
    }
    return undef;
}

1;

#######################################################################
# DOCUMENTATION
#

=head1 NAME

Win32::API::Struct - C struct support package for Win32::API

=head1 SYNOPSIS

  use Win32::API;
  
  Win32::API::Struct->typedef( 'POINT', qw(
    LONG x; 
    LONG y; 
  ));
  
  my $Point = Win32::API::Struct->new( 'POINT' ); 
  $Point->{x} = 1024;
  $Point->{y} = 768;

  #### alternatively
  
  tie %Point, 'Win32::API::Struct', 'POINT';
  $Point{x} = 1024;
  $Point{y} = 768;


=head1 ABSTRACT

This module enables you to define C structs for use with
Win32::API. 

See L<Win32::API> for more info about its usage.

=head1 DESCRIPTION

This module is automatically imported by Win32::API, so you don't 
need to 'use' it explicitly. The main methods are C<typedef> and
C<new>, which are documented below.

=over 4

=item C<typedef NAME, TYPE, MEMBER, TYPE, MEMBER, ...>

This method defines a structure named C<NAME>. The definition consists
of types and member names, just like in C. In fact, most of the
times you can cut the C definition for a structure and paste it
verbatim to your script, enclosing it in a C<qw()> block. The 
function takes care of removing the semicolon after the member
name.

The synopsis example could be written like this:

  Win32::API::Struct->typedef('POINT', 'LONG', 'x', 'LONG', 'y');

But it could also be written like this (note the indirect object
syntax), which is pretty cool:

  typedef Win32::API::Struct POINT => qw{
    LONG x; 
    LONG y; 
  };

Also note that C<typedef> automatically defines an 'LPNAME' type,
which holds a pointer to your structure. In the example above,
'LPPOINT' is also defined and can be used in a call to a 
Win32::API (in fact, this is what you're really going to use when
doing API calls).

=item C<new NAME>

This creates a structure (a Win32::API::Struct object) of the
type C<NAME> (it must have been defined with C<typedef>). In Perl,
when you create a structure, all the members are undefined. But
when you use that structure in C (eg. a Win32::API call), you
can safely assume that they will be treated as zero (or NULL).

=item C<sizeof>

This returns the size, in bytes, of the structure. Acts just like
the C function of the same name. It is particularly useful for 
structures that need a member to be initialized to the structure's
own size.

=item C<align [SIZE]>

Sets or returns the structure alignment (eg. how the structure is
stored in memory). This is a very advanced option, and you normally 
don't need to mess with it. 
All structures in the Win32 Platform SDK should work without it. 
But if you define your own structure, you may need to give it an 
explicit alignment. In most cases, passing a C<SIZE> of 'auto' 
should keep the world happy.

=back

=head2 THE C<tie> INTERFACE

Instead of creating an object with the C<new> method, you can
tie a hash, which will hold the desired structure, using the 
C<tie> builtin function:

  tie %structure, Win32::API::Struct => 'NAME';

The differences between the tied and non-tied approaches are:

=over 4

=item *
with tied structures, you can access members directly as
hash lookups, eg.

  # tied              # non-tied
  $Point{x}    vs.    $Point->{x}

=item *
with tied structures, when you try to fetch or store a
member that is not part of the structure, it will result
in a warning, eg.

  print $Point{z};
  # this will warn: 'z' is not a member of Win32::API::Struct POINT

=item *
when you pass a tied structure as a Win32::API parameter, 
remember to backslash it, eg.

  # tied                            # non-tied
  GetCursorPos( \%Point )    vs.    GetCursorPos( $Point )

=back

=head1 AUTHOR

Aldo Calpini ( I<dada@perl.it> ).

=cut
