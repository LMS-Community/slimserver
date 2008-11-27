
require 5;
package HTML::FormatText;

=head1 NAME

HTML::FormatText - Format HTML as plaintext

=head1 SYNOPSIS

 require HTML::TreeBuilder;
 $tree = HTML::TreeBuilder->new->parse_file("test.html");

 require HTML::FormatText;
 $formatter = HTML::FormatText->new(leftmargin => 0, rightmargin => 50);
 print $formatter->format($tree);

=head1 DESCRIPTION

The HTML::FormatText is a formatter that outputs plain latin1 text.
All character attributes (bold/italic/underline) are ignored.
Formatting of HTML tables and forms is not implemented.

You might specify the following parameters when constructing the
formatter:

=over 4

=item I<leftmargin> (alias I<lm>)

The column of the left margin. The default is 3.

=item I<rightmargin> (alias I<rm>)

The column of the right margin. The default is 72.

=back

=head1 SEE ALSO

L<HTML::Formatter>

=head1 COPYRIGHT

Copyright (c) 1995-2002 Gisle Aas, and 2002- Sean M. Burke. All rights
reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.


=head1 AUTHOR

Current maintainer: Sean M. Burke <sburke@cpan.org>

Original author: Gisle Aas <gisle@aas.no>


=cut

use strict;
use vars qw(@ISA $VERSION);

use HTML::Formatter ();
BEGIN { *DEBUG = \&HTML::Formatter::DEBUG unless defined &DEBUG }

@ISA = qw(HTML::Formatter);

$VERSION = sprintf("%d.%02d", q$Revision: 2.04 $ =~ /(\d+)\.(\d+)/);


sub default_values
{
    (
     shift->SUPER::default_values(),
     lm =>  3, # left margin
     rm => 72, # right margin (actually, maximum text width)
    );
}

sub configure
{
    my($self,$hash) = @_;
    my $lm = $self->{lm};
    my $rm = $self->{rm};

    $lm = delete $hash->{lm} if exists $hash->{lm};
    $lm = delete $hash->{leftmargin} if exists $hash->{leftmargin};
    $rm = delete $hash->{rm} if exists $hash->{rm};
    $rm = delete $hash->{rightmargin} if exists $hash->{rightmargin};

    my $width = $rm - $lm;
    if ($width < 1) {
	warn "Bad margins, ignored" if $^W;
	return;
    }
    if ($width < 20) {
	warn "Page probably too narrow" if $^W;
    }

    for (keys %$hash) {
	warn "Unknown configure option '$_'" if $^W;
    }

    $self->{lm} = $lm;
    $self->{rm} = $rm;
    $self;
}


sub begin
{
    my $self = shift;
    $self->HTML::Formatter::begin;
    $self->{curpos} = 0;  # current output position.
    $self->{maxpos} = 0;  # highest value of $pos (used by header underliner)
    $self->{hspace} = 0;  # horizontal space pending flag
}


sub end
{
    shift->collect("\n");
}


sub header_start
{
    my($self, $level, $node) = @_;
    $self->vspace(1 + (6-$level) * 0.4);
    $self->{maxpos} = 0;
    1;
}

sub header_end
{
    my($self, $level, $node) = @_;
    if ($level <= 2) {
	my $line;
	$line = '=' if $level == 1;
	$line = '-' if $level == 2;
	$self->vspace(0);
	$self->out($line x ($self->{maxpos} - $self->{lm}));
    }
    $self->vspace(1);
    1;
}

sub bullet {
  my $self = shift;
  $self->SUPER::bullet($_[0] . ' ');
}


sub hr_start
{
    my $self = shift;
    $self->vspace(1);
    $self->out('-' x ($self->{rm} - $self->{lm}));
    $self->vspace(1);
}


sub pre_out
{
    my $self = shift;
    # should really handle bold/italic etc.
    if (defined $self->{vspace}) {
	if ($self->{out}) {
	    $self->nl() while $self->{vspace}-- >= 0;
	    $self->{vspace} = undef;
	}
    }
    my $indent = ' ' x $self->{lm};
    my $pre = shift;
    $pre =~ s/^/$indent/mg;
    $self->collect($pre);
    $self->{out}++;
}


sub out
{
    my $self = shift;
    my $text = shift;

    $text =~ tr/\xA0\xAD/ /d;

    if ($text =~ /^\s*$/) {
	$self->{hspace} = 1;
	return;
    }

    if (defined $self->{vspace}) {
	if ($self->{out}) {
	    $self->nl while $self->{vspace}-- >= 0;
        }
	$self->goto_lm;
	$self->{vspace} = undef;
	$self->{hspace} = 0;
    }

    if ($self->{hspace}) {
	if ($self->{curpos} + length($text) > $self->{rm}) {
	    # word will not fit on line; do a line break
	    $self->nl;
	    $self->goto_lm;
	} else {
	    # word fits on line; use a space
	    $self->collect(' ');
	    ++$self->{curpos};
	}
	$self->{hspace} = 0;
    }

    $self->collect($text);
    my $pos = $self->{curpos} += length $text;
    $self->{maxpos} = $pos if $self->{maxpos} < $pos;
    $self->{'out'}++;
}


sub goto_lm
{
    my $self = shift;
    my $pos = $self->{curpos};
    my $lm  = $self->{lm};
    if ($pos < $lm) {
	$self->{curpos} = $lm;
	$self->collect(" " x ($lm - $pos));
    }
}


sub nl
{
    my $self = shift;
    $self->{'out'}++;
    $self->{curpos} = 0;
    $self->collect("\n");
}


sub adjust_lm
{
    my $self = shift;
    $self->{lm} += $_[0];
    $self->goto_lm;
}


sub adjust_rm
{
    shift->{rm} += $_[0];
}

1;

