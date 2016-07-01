package HTML::FormatText;
BEGIN {
  $HTML::FormatText::VERSION = '2.05';
}
BEGIN {
  $HTML::FormatText::AUTHORITY = 'cpan:NIGELM';
}

# ABSTRACT: Format HTML as plaintext


use strict;
use vars qw(@ISA $VERSION);

use HTML::Formatter ();
BEGIN { *DEBUG = \&HTML::Formatter::DEBUG unless defined &DEBUG }

@ISA = qw(HTML::Formatter);

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
    my($self, $level) = @_;
    $self->vspace(1 + (6-$level) * 0.4);
    $self->{maxpos} = 0;
    1;
}

sub header_end
{
    my($self, $level) = @_;
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
# don't corrupt multi-byte Unicode characters
# https://rt.cpan.org/Public/Bug/Display.html?id=9700
#    $text =~ tr/\xA0\xAD/ /d;

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


__END__
=pod

=for test_synopsis 1;
__END__

=for stopwords latin1 leftmargin lm plaintext rightmargin

=head1 NAME

HTML::FormatText - Format HTML as plaintext

=head1 VERSION

version 2.05

=head1 SYNOPSIS

    use HTML::TreeBuilder;
    $tree = HTML::TreeBuilder->new->parse_file("test.html");

    use HTML::FormatText;
    $formatter = HTML::FormatText->new(leftmargin => 0, rightmargin => 50);
    print $formatter->format($tree);

or, more simply:

    use HTML::FormatText;
    my $string = HTML::FormatText->format_file(
        'test.html',
        leftmargin => 0, rightmargin => 50
        );

=head1 DESCRIPTION

HTML::FormatText is a formatter that outputs plain latin1 text.
All character attributes (bold/italic/underline) are ignored.
Formatting of HTML tables and forms is not implemented.

HTML::FormatText is built on L<HTML::Formatter> and documentation
for that module applies to this - especially
L<HTML::Formatter/new>, L<HTML::Formatter/format_file> and
L<HTML::Formatter/format_string>.

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

=head1 INSTALLATION

See perlmodinstall for information and options on installing Perl modules.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests through the web interface at
L<http://rt.cpan.org/Public/Dist/Display.html?Name=HTML-Format>.

=head1 AVAILABILITY

The project homepage is L<http://search.cpan.org/dist/HTML-Format>.

The latest version of this module is available from the Comprehensive Perl
Archive Network (CPAN). Visit L<http://www.perl.com/CPAN/> to find a CPAN
site near you, or see L<http://search.cpan.org/dist/HTML-Format/>.

The development version lives at L<http://github.com/nigelm/html-format>
and may be cloned from L<git://github.com/nigelm/html-format.git>.
Instead of sending patches, please fork this project using the standard
git and github infrastructure.

=head1 AUTHORS

=over 4

=item *

Nigel Metheringham <nigelm@cpan.org>

=item *

Sean M Burke <sburke@cpan.org>

=item *

Gisle Aas <gisle@ActiveState.com>

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Nigel Metheringham, 2002-2005 Sean M Burke, 1999-2002 Gisle Aas.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

