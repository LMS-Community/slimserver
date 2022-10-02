package IO::Interface::Simple;
use strict;
use IO::Socket;
use IO::Interface;

use overload '""' => \&as_string,
  eq => '_eq_',
  fallback => 1;

# class variable
my $socket;

# class methods
sub interfaces {
  my $class = shift;
  my $s     = $class->sock;
  return sort {($a->index||0) <=> ($b->index||0) } map {$class->new($_)} $s->if_list;
}

sub new {
  my $class    = shift;
  my $if_name  = shift;
  my $s        = $class->sock;
  return unless defined $s->if_mtu($if_name);
  return bless {s    => $s,
		name => $if_name},ref $class || $class;
}

sub new_from_address {
  my $class = shift;
  my $addr  = shift;
  my $s     = $class->sock;
  my $name  = $s->addr_to_interface($addr) or return;
  return $class->new($name);
}

sub new_from_index {
  my $class = shift;
  my $index  = shift;
  my $s     = $class->sock;
  my $name  = $s->if_indextoname($index) or return;
  return $class->new($name);
}

sub sock {
  my $self = shift;
  if (ref $self) {
    return $self->{s} ||= $socket;
  } else {
    return $socket ||= IO::Socket::INET->new(Proto=>'udp');
  }
}

sub _eq_ {
  return shift->name eq shift;
}

sub as_string {
  shift->name;
}

sub name {
  shift->{name};
}

sub address {
  my $self = shift;
  $self->sock->if_addr($self->name,@_);
}

sub broadcast {
  my $self = shift;
  $self->sock->if_broadcast($self->name,@_);
}

sub netmask {
  my $self = shift;
  $self->sock->if_netmask($self->name,@_);
}

sub dstaddr {
  my $self = shift;
  $self->sock->if_dstaddr($self->name,@_);
}

sub hwaddr {
  my $self = shift;
  $self->sock->if_hwaddr($self->name,@_);
}

sub flags {
  my $self = shift;
  $self->sock->if_flags($self->name,@_);
}

sub mtu {
  my $self = shift;
  $self->sock->if_mtu($self->name,@_);
}

sub metric {
  my $self = shift;
  $self->sock->if_metric($self->name,@_);
}

sub index {
  my $self = shift;
  return $self->sock->if_index($self->name);
}

sub is_running   { shift->_gettestflag(IO::Interface::IFF_RUNNING(),@_) }
sub is_broadcast { shift->_gettestflag(IO::Interface::IFF_BROADCAST(),@_) }
sub is_pt2pt     { shift->_gettestflag(IO::Interface::IFF_POINTOPOINT(),@_) }
sub is_loopback  { shift->_gettestflag(IO::Interface::IFF_LOOPBACK(),@_) }
sub is_promiscuous   { shift->_gettestflag(IO::Interface::IFF_PROMISC(),@_) }
sub is_multicast    { shift->_gettestflag(IO::Interface::IFF_MULTICAST(),@_) }
sub is_notrailers   { shift->_gettestflag(IO::Interface::IFF_NOTRAILERS(),@_) }
sub is_noarp     { shift->_gettestflag(IO::Interface::IFF_NOARP(),@_) }

sub _gettestflag {
  my $self    = shift;
  my $bitmask = shift;
  my $flags   = $self->flags;
  if (@_) {
    $flags |= $bitmask;
    $self->flags($flags);
  } else {
    return ($flags & $bitmask) != 0;
  }
}

1;

=head1 NAME

IO::Interface::Simple - Perl extension for access to network card configuration information

=head1 SYNOPSIS

 use IO::Interface::Simple;

 my $if1   = IO::Interface::Simple->new('eth0');
 my $if2   = IO::Interface::Simple->new_from_address('127.0.0.1');
 my $if3   = IO::Interface::Simple->new_from_index(1);

 my @interfaces = IO::Interface::Simple->interfaces;

 for my $if (@interfaces) {
    print "interface = $if\n";
    print "addr =      ",$if->address,"\n",
          "broadcast = ",$if->broadcast,"\n",
          "netmask =   ",$if->netmask,"\n",
          "dstaddr =   ",$if->dstaddr,"\n",
          "hwaddr =    ",$if->hwaddr,"\n",
          "mtu =       ",$if->mtu,"\n",
          "metric =    ",$if->metric,"\n",
          "index =     ",$if->index,"\n";

    print "is running\n"     if $if->is_running;
    print "is broadcast\n"   if $if->is_broadcast;
    print "is p-to-p\n"      if $if->is_pt2pt;
    print "is loopback\n"    if $if->is_loopback;
    print "is promiscuous\n" if $if->is_promiscuous;
    print "is multicast\n"   if $if->is_multicast;
    print "is notrailers\n"  if $if->is_notrailers;
    print "is noarp\n"       if $if->is_noarp;
  }


=head1 DESCRIPTION

IO::Interface::Simple allows you to interrogate and change network
interfaces. It has overlapping functionality with Net::Interface, but
might compile and run on more platforms.

=head2 Class Methods

=over 4

=item $interface = IO::Interface::Simple->new('eth0')

Given an interface name, new() creates an interface object.

=item @iflist = IO::Interface::Simple->interfaces;

Returns a list of active interface objects.

=item $interface = IO::Interface::Simple->new_from_address('192.168.0.1')

Returns the interface object corresponding to the given address.

=item $interface = IO::Interface::Simple->new_from_index(2)

Returns the interface object corresponding to the given numeric
index. This is only supported on BSD-ish platforms.

=back

=head2 Object Methods

=over 4

=item $name = $interface->name

Get the name of the interface. The interface object is also overloaded
so that if you use it in a string context it is the same as calling
name().

=item $index = $interface->index

Get the index of the interface. This is only supported on BSD-like
platforms.

=item $addr = $interface->address([$newaddr])

Get or set the interface's address.


=item $addr = $interface->broadcast([$newaddr])

Get or set the interface's broadcast address.

=item $addr = $interface->netmask([$newmask])

Get or set the interface's netmask.

=item $addr = $interface->hwaddr([$newaddr])

Get or set the interface's hardware address.

=item $addr = $interface->mtu([$newmtu])

Get or set the interface's MTU.

=item $addr = $interface->metric([$newmetric])

Get or set the interface's metric.

=item $flags = $interface->flags([$newflags])

Get or set the interface's flags. These can be ANDed with the IFF
constants exported by IO::Interface or Net::Interface in order to
interrogate the state and capabilities of the interface. However, it
is probably more convenient to use the broken-out methods listed
below.

=item $flag = $interface->is_running([$newflag])

=item $flag = $interface->is_broadcast([$newflag])

=item $flag = $interface->is_pt2pt([$newflag])

=item $flag = $interface->is_loopback([$newflag])

=item $flag = $interface->is_promiscuous([$newflag])

=item $flag = $interface->is_multicast([$newflag])

=item $flag = $interface->is_notrailers([$newflag])

=item $flag = $interface->is_noarp([$newflag])

Get or set the corresponding configuration parameters. Note that the
operating system may not let you set some of these.

=back

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>

This module is distributed under the same license as Perl itself.

=head1 SEE ALSO

L<perl>, L<IO::Socket>, L<IO::Multicast>), L<IO::Interface>, L<Net::Interface>

=cut

