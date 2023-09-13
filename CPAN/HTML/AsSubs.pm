package HTML::AsSubs;

=head1 NAME

HTML::AsSubs - functions that construct a HTML syntax tree

=head1 SYNOPSIS

 use HTML::AsSubs;
 $h = body(
	   h1("This is the heading"),
	   p("This is the first paragraph which contains a ",
	     a({href=>'link.html'}, "link"),
	     " and an ",
	     img({src=>'img.gif', alt=>'image'}),
	     "."
	    ),
	  );
 print $h->as_HTML;

=head1 DESCRIPTION

This module exports functions that can be used to construct various
HTML elements. The functions are named after the tags of the
corresponding HTML element and are all written in lower case. If the
first argument is a hash reference then it will be used to initialize the
attributes of this element. The remaining arguments are regarded as
content.

For a similar idea (i.e., it's another case where the syntax tree
of the Perl source mirrors the syntax tree of the HTML produced),
see HTML::Element's C<new_from_lol> method.

For what I now think is a cleaner implementation of this same idea,
see the excellent module C<XML::Generator>, which is what I suggest
for actual real-life use.  (I suggest this over C<HTML::AsSubs> and
over C<CGI.pm>'s HTML-making functions.)

=head1 ACKNOWLEDGEMENT

This module was inspired by the following message:

 Date: Tue, 4 Oct 1994 16:11:30 +0100
 Subject: Wow! I have a large lightbulb above my head!

 Take a moment to consider these lines:

 %OVERLOAD=( '""' => sub { join("", @{$_[0]}) } );

 sub html { my($type)=shift; bless ["<$type>", @_, "</$type>"]; }

 :-)  I *love* Perl 5!  Thankyou Larry and Ilya.

 Regards,
 Tim Bunce.

 p.s. If you didn't get it, think about recursive data types: html(html())
 p.p.s. I'll turn this into a much more practical example in a day or two.
 p.p.p.s. It's a pity that overloads are not inherited. Is this a bug?

=head1 BUGS

The exported link() function overrides the builtin link() function.
The exported tr() function must be called using &tr(...) syntax
because it clashes with the builtin tr/../../ operator.

=head1 SEE ALSO

L<HTML::Element>, L<XML::Generator>

=cut

use warnings;
use strict;
use vars qw(@ISA $VERSION @EXPORT);

require HTML::Element;
require Exporter;
@ISA = qw(Exporter);

$VERSION = 4.2;

# Problem: exports so damned much.  Has no concept of "export only HTML4
#  elements".  TODO:?? make something that make functions that just
#  wrap XML::Generator calls?

=head2 html head title base link meta isindex nextid script style body h1 h2 h3 h4 h5 h6 p pre div blockquote a img br hr ol ul dir menu li dl dt dd dfn cite code em kbd samp strong var address span b i u tt center font big small strike sub sup table tr td th caption form input select option textarea object applet param map area frame frameset noframe

A bunch of methods for creating tags.

=cut

use vars qw(@TAGS);
@TAGS = qw(html
    head title base link meta isindex nextid script style
    body h1 h2 h3 h4 h5 h6 p pre div blockquote
    a img br hr
    ol ul dir menu li
    dl dt dd
    dfn cite code em kbd samp strong var address span
    b i u tt
    center font big small strike
    sub sup
    table tr td th caption
    form input select option textarea
    object applet param
    map area
    frame frameset noframe
);

for (@TAGS) {
    my $code;
    $code = "sub $_ { _elem('$_', \@_); }\n";
    push( @EXPORT, $_ );
## no critic
    eval $code;
## use critic
    if ($@) {
        die $@;
    }
}

=head1 Private Functions

=head2 _elem()

The _elem() function is wrapped by all the html 'tag' functions. It
takes a tag-name, optional hashref of attributes and a list of content
as parameters.

=cut

sub _elem {
    my $tag = shift;
    my $attributes;
    if ( @_ and defined $_[0] and ref( $_[0] ) eq "HASH" ) {
        $attributes = shift;
    }
    my $elem = HTML::Element->new( $tag, %$attributes );
    $elem->push_content(@_);
    $elem;
}

1;
