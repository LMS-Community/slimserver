package Log::Dispatch::Base;

use strict;
use warnings;

our $VERSION = '1.09';


sub _get_callbacks
{
    shift;
    my %p = @_;

    return unless exists $p{callbacks};

    return @{ $p{callbacks} }
        if UNIVERSAL::isa( $p{callbacks}, 'ARRAY' );

    return $p{callbacks}
        if UNIVERSAL::isa( $p{callbacks}, 'CODE' );

    return;
}

sub _apply_callbacks
{
    my $self = shift;
    my %p = @_;

    my $msg = delete $p{message};
    foreach my $cb ( @{ $self->{callbacks} } )
    {
        $msg = $cb->( message => $msg, %p );
    }

    return $msg;
}


1;

__END__

=head1 NAME

Log::Dispatch::Base - Code shared by dispatch and output objects.

=head1 SYNOPSIS

  use Log::Dispatch::Base;

  ...

  @ISA = qw(Log::Dispatch::Base);

=head1 DESCRIPTION

Unless you are me, you probably don't need to know what this class
does.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=cut
