package HTML::Element;

=head1 NAME

HTML::Element - Class for objects that represent HTML elements

=head1 VERSION

Version 4.2

=cut

use strict;
use Carp           ();
use HTML::Entities ();
use HTML::Tagset   ();
use integer;    # vroom vroom!

use vars qw( $VERSION );
$VERSION = 4.2;

# This contorls encoding entities on output.
# When set entities won't be re-encoded.
# Defaulting off because parser defaults to unencoding entities
our $encoded_content = 0;

use vars qw($html_uc $Debug $ID_COUNTER %list_type_to_sub);

=head1 SYNOPSIS

    use HTML::Element;
    $a = HTML::Element->new('a', href => 'http://www.perl.com/');
    $a->push_content("The Perl Homepage");

    $tag = $a->tag;
    print "$tag starts out as:",  $a->starttag, "\n";
    print "$tag ends as:",  $a->endtag, "\n";
    print "$tag\'s href attribute is: ", $a->attr('href'), "\n";

    $links_r = $a->extract_links();
    print "Hey, I found ", scalar(@$links_r), " links.\n";

    print "And that, as HTML, is: ", $a->as_HTML, "\n";
    $a = $a->delete;

=head1 DESCRIPTION

(This class is part of the L<HTML::Tree|HTML::Tree> dist.)

Objects of the HTML::Element class can be used to represent elements
of HTML document trees.  These objects have attributes, notably attributes that
designates each element's parent and content.  The content is an array
of text segments and other HTML::Element objects.  A tree with HTML::Element
objects as nodes can represent the syntax tree for a HTML document.

=head1 HOW WE REPRESENT TREES

Consider this HTML document:

  <html lang='en-US'>
    <head>
      <title>Stuff</title>
      <meta name='author' content='Jojo'>
    </head>
    <body>
     <h1>I like potatoes!</h1>
    </body>
  </html>

Building a syntax tree out of it makes a tree-structure in memory
that could be diagrammed as:

                     html (lang='en-US')
                      / \
                    /     \
                  /         \
                head        body
               /\               \
             /    \               \
           /        \               \
         title     meta              h1
          |       (name='author',     |
       "Stuff"    content='Jojo')    "I like potatoes"

This is the traditional way to diagram a tree, with the "root" at the
top, and it's this kind of diagram that people have in mind when they
say, for example, that "the meta element is under the head element
instead of under the body element".  (The same is also said with
"inside" instead of "under" -- the use of "inside" makes more sense
when you're looking at the HTML source.)

Another way to represent the above tree is with indenting:

  html (attributes: lang='en-US')
    head
      title
        "Stuff"
      meta (attributes: name='author' content='Jojo')
    body
      h1
        "I like potatoes"

Incidentally, diagramming with indenting works much better for very
large trees, and is easier for a program to generate.  The C<< $tree->dump >>
method uses indentation just that way.

However you diagram the tree, it's stored the same in memory -- it's a
network of objects, each of which has attributes like so:

  element #1:  _tag: 'html'
               _parent: none
               _content: [element #2, element #5]
               lang: 'en-US'

  element #2:  _tag: 'head'
               _parent: element #1
               _content: [element #3, element #4]

  element #3:  _tag: 'title'
               _parent: element #2
               _content: [text segment "Stuff"]

  element #4   _tag: 'meta'
               _parent: element #2
               _content: none
               name: author
               content: Jojo

  element #5   _tag: 'body'
               _parent: element #1
               _content: [element #6]

  element #6   _tag: 'h1'
               _parent: element #5
               _content: [text segment "I like potatoes"]

The "treeness" of the tree-structure that these elements comprise is
not an aspect of any particular object, but is emergent from the
relatedness attributes (_parent and _content) of these element-objects
and from how you use them to get from element to element.

While you could access the content of a tree by writing code that says
"access the 'src' attribute of the root's I<first> child's I<seventh>
child's I<third> child", you're more likely to have to scan the contents
of a tree, looking for whatever nodes, or kinds of nodes, you want to
do something with.  The most straightforward way to look over a tree
is to "traverse" it; an HTML::Element method (C<< $h->traverse >>) is
provided for this purpose; and several other HTML::Element methods are
based on it.

(For everything you ever wanted to know about trees, and then some,
see Niklaus Wirth's I<Algorithms + Data Structures = Programs> or
Donald Knuth's I<The Art of Computer Programming, Volume 1>.)

=cut

$Debug = 0 unless defined $Debug;

=head2 Version

Why is this a sub?

=cut

sub Version { $VERSION; }

my $nillio = [];

*HTML::Element::emptyElement   = \%HTML::Tagset::emptyElement;      # legacy
*HTML::Element::optionalEndTag = \%HTML::Tagset::optionalEndTag;    # legacy
*HTML::Element::linkElements   = \%HTML::Tagset::linkElements;      # legacy
*HTML::Element::boolean_attr   = \%HTML::Tagset::boolean_attr;      # legacy
*HTML::Element::canTighten     = \%HTML::Tagset::canTighten;        # legacy

# Constants for signalling back to the traverser:
my $travsignal_package = __PACKAGE__ . '::_travsignal';
my ( $ABORT, $PRUNE, $PRUNE_SOFTLY, $OK, $PRUNE_UP )
    = map { my $x = $_; bless \$x, $travsignal_package; }
    qw(
    ABORT  PRUNE   PRUNE_SOFTLY   OK   PRUNE_UP
);

=head2 ABORT OK PRUNE PRUNE_SOFTLY PRUNE_UP

Constants for signalling back to the traverser

=cut

## Comments from Father Chrysostomos RT #58880
## The sole purpose for empty parentheses after a sub name is to make it
## parse as a 0-ary (nihilary?) function. I.e., ABORT+1 should parse as
## ABORT()+1, not ABORT(+1). The parentheses also tell perl that it can
### be inlined.
##Deparse is really useful for demonstrating this:
##$ perl -MO=Deparse,-p -e 'sub ABORT {7} print ABORT+8'
# Vs
# perl -MO=Deparse,-p -e 'sub ABORT() {7} print ABORT+8'
#
# With the parentheses, it not only makes it parse as a term.
# It even resolves the constant at compile-time, making the code run faster.

## no critic
sub ABORT ()        {$ABORT}
sub PRUNE ()        {$PRUNE}
sub PRUNE_SOFTLY () {$PRUNE_SOFTLY}
sub OK ()           {$OK}
sub PRUNE_UP ()     {$PRUNE_UP}
## use critic

$html_uc = 0;

# set to 1 if you want tag and attribute names from starttag and endtag
#  to be uc'd

# regexs for XML names
# http://www.w3.org/TR/2006/REC-xml11-20060816/NT-NameStartChar
my $START_CHAR
    = qr/(?:\:|[A-Z]|_|[a-z]|[\x{C0}-\x{D6}]|[\x{D8}-\x{F6}]|[\x{F8}-\x{2FF}]|[\x{370}-\x{37D}]|[\x{37F}-\x{1FFF}]|[\x{200C}-\x{200D}]|[\x{2070}-\x{218F}]|[\x{2C00}-\x{2FEF}]|[\x{3001}-\x{D7FF}]|[\x{F900}-\x{FDCF}]|[\x{FDF0}-\x{FFFD}]|[\x{10000}-\x{EFFFF}])/;

# http://www.w3.org/TR/2006/REC-xml11-20060816/#NT-NameChar
my $NAME_CHAR
    = qr/(?:$START_CHAR|-|\.|[0-9]|\x{B7}|[\x{0300}-\x{036F}]|[\x{203F}-\x{2040}])/;

# Elements that does not have corresponding end tags (i.e. are empty)

#==========================================================================

=head1 BASIC METHODS

=head2 $h = HTML::Element->new('tag', 'attrname' => 'value', ... )

This constructor method returns a new HTML::Element object.  The tag
name is a required argument; it will be forced to lowercase.
Optionally, you can specify other initial attributes at object
creation time.

=cut

#
# An HTML::Element is represented by blessed hash reference, much like
# Tree::DAG_Node objects.  Key-names not starting with '_' are reserved
# for the SGML attributes of the element.
# The following special keys are used:
#
#    '_tag':    The tag name (i.e., the generic identifier)
#    '_parent': A reference to the HTML::Element above (when forming a tree)
#    '_pos':    The current position (a reference to a HTML::Element) is
#               where inserts will be placed (look at the insert_element
#               method)  If not set, the implicit value is the object itself.
#    '_content': A ref to an array of nodes under this.
#                It might not be set.
#
# Example: <img src="gisle.jpg" alt="Gisle's photo"> is represented like this:
#
#  bless {
#     _tag => 'img',
#     src  => 'gisle.jpg',
#     alt  => "Gisle's photo",
#  }, 'HTML::Element';
#

sub new {
    my $class = shift;
    $class = ref($class) || $class;

    my $tag = shift;
    Carp::croak("No tagname") unless defined $tag and length $tag;
    Carp::croak "\"$tag\" isn't a good tag name!"
        if $tag =~ m/[<>\/\x00-\x20]/;    # minimal sanity, certainly!
    my $self = bless { _tag => scalar( $class->_fold_case($tag) ) }, $class;
    my ( $attr, $val );
    while ( ( $attr, $val ) = splice( @_, 0, 2 ) ) {
## RT #42209 why does this default to the attribute name and not remain unset or the empty string?
        $val = $attr unless defined $val;
        $self->{ $class->_fold_case($attr) } = $val;
    }
    if ( $tag eq 'html' ) {
        $self->{'_pos'} = undef;
    }
    return $self;
}

=head2 $h->attr('attr') or $h->attr('attr', 'value')

Returns (optionally sets) the value of the given attribute of $h.  The
attribute name (but not the value, if provided) is forced to
lowercase.  If trying to read the value of an attribute not present
for this element, the return value is undef.
If setting a new value, the old value of that attribute is
returned.

If methods are provided for accessing an attribute (like C<< $h->tag >> for
"_tag", C<< $h->content_list >>, etc. below), use those instead of calling
attr C<< $h->attr >>, whether for reading or setting.

Note that setting an attribute to C<undef> (as opposed to "", the empty
string) actually deletes the attribute.

=cut

sub attr {
    my $self = shift;
    my $attr = scalar( $self->_fold_case(shift) );
    if (@_) {    # set
        if ( defined $_[0] ) {
            my $old = $self->{$attr};
            $self->{$attr} = $_[0];
            return $old;
        }
        else {    # delete, actually
            return delete $self->{$attr};
        }
    }
    else {        # get
        return $self->{$attr};
    }
}

=head2 $h->tag() or $h->tag('tagname')

Returns (optionally sets) the tag name (also known as the generic
identifier) for the element $h.  In setting, the tag name is always
converted to lower case.

There are four kinds of "pseudo-elements" that show up as
HTML::Element objects:

=over

=item Comment pseudo-elements

These are element objects with a C<$h-E<gt>tag> value of "~comment",
and the content of the comment is stored in the "text" attribute
(C<$h-E<gt>attr("text")>).  For example, parsing this code with
HTML::TreeBuilder...

  <!-- I like Pie.
     Pie is good
  -->

produces an HTML::Element object with these attributes:

  "_tag",
  "~comment",
  "text",
  " I like Pie.\n     Pie is good\n  "

=item Declaration pseudo-elements

Declarations (rarely encountered) are represented as HTML::Element
objects with a tag name of "~declaration", and content in the "text"
attribute.  For example, this:

  <!DOCTYPE foo>

produces an element whose attributes include:

  "_tag", "~declaration", "text", "DOCTYPE foo"

=item Processing instruction pseudo-elements

PIs (rarely encountered) are represented as HTML::Element objects with
a tag name of "~pi", and content in the "text" attribute.  For
example, this:

  <?stuff foo?>

produces an element whose attributes include:

  "_tag", "~pi", "text", "stuff foo?"

(assuming a recent version of HTML::Parser)

=item ~literal pseudo-elements

These objects are not currently produced by HTML::TreeBuilder, but can
be used to represent a "super-literal" -- i.e., a literal you want to
be immune from escaping.  (Yes, I just made that term up.)

That is, this is useful if you want to insert code into a tree that
you plan to dump out with C<as_HTML>, where you want, for some reason,
to suppress C<as_HTML>'s normal behavior of amp-quoting text segments.

For example, this:

  my $literal = HTML::Element->new('~literal',
    'text' => 'x < 4 & y > 7'
  );
  my $span = HTML::Element->new('span');
  $span->push_content($literal);
  print $span->as_HTML;

prints this:

  <span>x < 4 & y > 7</span>

Whereas this:

  my $span = HTML::Element->new('span');
  $span->push_content('x < 4 & y > 7');
    # normal text segment
  print $span->as_HTML;

prints this:

  <span>x &lt; 4 &amp; y &gt; 7</span>

Unless you're inserting lots of pre-cooked code into existing trees,
and dumping them out again, it's not likely that you'll find
C<~literal> pseudo-elements useful.

=back

=cut

sub tag {
    my $self = shift;
    if (@_) {    # set
        $self->{'_tag'} = $self->_fold_case( $_[0] );
    }
    else {       # get
        $self->{'_tag'};
    }
}

=head2 $h->parent() or $h->parent($new_parent)

Returns (optionally sets) the parent (aka "container") for this element.
The parent should either be undef, or should be another element.

You B<should not> use this to directly set the parent of an element.
Instead use any of the other methods under "Structure-Modifying
Methods", below.

Note that not($h->parent) is a simple test for whether $h is the
root of its subtree.

=cut

sub parent {
    my $self = shift;
    if (@_) {    # set
        Carp::croak "an element can't be made its own parent"
            if defined $_[0] and ref $_[0] and $self eq $_[0];    # sanity
        $self->{'_parent'} = $_[0];
    }
    else {
        $self->{'_parent'};                                       # get
    }
}

=head2 $h->content_list()

Returns a list of the child nodes of this element -- i.e., what
nodes (elements or text segments) are inside/under this element. (Note
that this may be an empty list.)

In a scalar context, this returns the count of the items,
as you may expect.

=cut

sub content_list {
    return wantarray
        ? @{ shift->{'_content'} || return () }
        : scalar @{ shift->{'_content'} || return 0 };
}

=head2 $h->content()

This somewhat deprecated method returns the content of this element;
but unlike content_list, this returns either undef (which you should
understand to mean no content), or a I<reference to the array> of
content items, each of which is either a text segment (a string, i.e.,
a defined non-reference scalar value), or an HTML::Element object.
Note that even if an arrayref is returned, it may be a reference to an
empty array.

While older code should feel free to continue to use C<< $h->content >>,
new code should use C<< $h->content_list >> in almost all conceivable
cases.  It is my experience that in most cases this leads to simpler
code anyway, since it means one can say:

    @children = $h->content_list;

instead of the inelegant:

    @children = @{$h->content || []};

If you do use C<< $h->content >> (or C<< $h->content_array_ref >>), you should not
use the reference returned by it (assuming it returned a reference,
and not undef) to directly set or change the content of an element or
text segment!  Instead use L<content_refs_list> or any of the other
methods under "Structure-Modifying Methods", below.

=cut

# a read-only method!  can't say $h->content( [] )!
sub content {
    return shift->{'_content'};
}

=head2 $h->content_array_ref()

This is like C<content> (with all its caveats and deprecations) except
that it is guaranteed to return an array reference.  That is, if the
given node has no C<_content> attribute, the C<content> method would
return that undef, but C<content_array_ref> would set the given node's
C<_content> value to C<[]> (a reference to a new, empty array), and
return that.

=cut

sub content_array_ref {
    return shift->{'_content'} ||= [];
}

=head2 $h->content_refs_list

This returns a list of scalar references to each element of C<$h>'s
content list.  This is useful in case you want to in-place edit any
large text segments without having to get a copy of the current value
of that segment value, modify that copy, then use the
C<splice_content> to replace the old with the new.  Instead, here you
can in-place edit:

    foreach my $item_r ($h->content_refs_list) {
        next if ref $$item_r;
        $$item_r =~ s/honour/honor/g;
    }

You I<could> currently achieve the same affect with:

    foreach my $item (@{ $h->content_array_ref }) {
        # deprecated!
        next if ref $item;
        $item =~ s/honour/honor/g;
    }

...except that using the return value of C<< $h->content >> or
C<< $h->content_array_ref >> to do that is deprecated, and just might stop
working in the future.

=cut

sub content_refs_list {
    return \( @{ shift->{'_content'} || return () } );
}

=head2 $h->implicit() or $h->implicit($bool)

Returns (optionally sets) the "_implicit" attribute.  This attribute is
a flag that's used for indicating that the element was not originally
present in the source, but was added to the parse tree (by
HTML::TreeBuilder, for example) in order to conform to the rules of
HTML structure.

=cut

sub implicit {
    return shift->attr( '_implicit', @_ );
}

=head2 $h->pos() or $h->pos($element)

Returns (and optionally sets) the "_pos" (for "current I<pos>ition")
pointer of C<$h>.  This attribute is a pointer used during some
parsing operations, whose value is whatever HTML::Element element
at or under C<$h> is currently "open", where C<< $h->insert_element(NEW) >>
will actually insert a new element.

(This has nothing to do with the Perl function called "pos", for
controlling where regular expression matching starts.)

If you set C<< $h->pos($element) >>, be sure that C<$element> is
either C<$h>, or an element under C<$h>.

If you've been modifying the tree under C<$h> and are no longer
sure C<< $h->pos >> is valid, you can enforce validity with:

    $h->pos(undef) unless $h->pos->is_inside($h);

=cut

sub pos {
    my $self = shift;
    my $pos  = $self->{'_pos'};
    if (@_) {    # set
        my $parm = shift;
        if ( defined $parm and $parm ne $self ) {
            $self->{'_pos'} = $parm;    # means that element
        }
        else {
            $self->{'_pos'} = undef;    # means $self
        }
    }
    return $pos if defined($pos);
    return $self;
}

=head2 $h->all_attr()

Returns all this element's attributes and values, as key-value pairs.
This will include any "internal" attributes (i.e., ones not present
in the original element, and which will not be represented if/when you
call C<< $h->as_HTML >>).  Internal attributes are distinguished by the fact
that the first character of their key (not value! key!) is an
underscore ("_").

Example output of C<< $h->all_attr() >> :
C<'_parent', >I<[object_value]>C< , '_tag', 'em', 'lang', 'en-US',
'_content', >I<[array-ref value]>.

=head2 $h->all_attr_names()

Like all_attr, but only returns the names of the attributes.

Example output of C<< $h->all_attr_names() >> :
C<'_parent', '_tag', 'lang', '_content', >.

=cut

sub all_attr {
    return %{ $_[0] };

    # Yes, trivial.  But no other way for the user to do the same
    #  without breaking encapsulation.
    # And if our object representation changes, this method's behavior
    #  should stay the same.
}

sub all_attr_names {
    return keys %{ $_[0] };
}

=head2 $h->all_external_attr()

Like C<all_attr>, except that internal attributes are not present.

=head2 $h->all_external_attr_names()

Like C<all_external_attr_names>, except that internal attributes' names
are not present.

=cut

sub all_external_attr {
    my $self = $_[0];
    return map( ( length($_) && substr( $_, 0, 1 ) eq '_' )
        ? ()
        : ( $_, $self->{$_} ),
        keys %$self );
}

sub all_external_attr_names {
    return grep !( length($_) && substr( $_, 0, 1 ) eq '_' ), keys %{ $_[0] };
}

=head2 $h->id() or $h->id($string)

Returns (optionally sets to C<$string>) the "id" attribute.
C<< $h->id(undef) >> deletes the "id" attribute.

=cut

sub id {
    if ( @_ == 1 ) {
        return $_[0]{'id'};
    }
    elsif ( @_ == 2 ) {
        if ( defined $_[1] ) {
            return $_[0]{'id'} = $_[1];
        }
        else {
            return delete $_[0]{'id'};
        }
    }
    else {
        Carp::croak '$node->id can\'t take ' . scalar(@_) . ' parameters!';
    }
}

=head2 $h->idf() or $h->idf($string)

Just like the C<id> method, except that if you call C<< $h->idf() >> and
no "id" attribute is defined for this element, then it's set to a
likely-to-be-unique value, and returned.  (The "f" is for "force".)

=cut

sub _gensym {
    unless ( defined $ID_COUNTER ) {

        # start it out...
        $ID_COUNTER = sprintf( '%04x', rand(0x1000) );
        $ID_COUNTER =~ tr<0-9a-f><J-NP-Z>;    # yes, skip letter "oh"
        $ID_COUNTER .= '00000';
    }
    ++$ID_COUNTER;
}

sub idf {
    my $nparms = scalar @_;

    if ( $nparms == 1 ) {
        my $x;
        if ( defined( $x = $_[0]{'id'} ) and length $x ) {
            return $x;
        }
        else {
            return $_[0]{'id'} = _gensym();
        }
    }
    if ( $nparms == 2 ) {
        if ( defined $_[1] ) {
            return $_[0]{'id'} = $_[1];
        }
        else {
            return delete $_[0]{'id'};
        }
    }
    Carp::croak '$node->idf can\'t take ' . scalar(@_) . ' parameters!';
}

=head1 STRUCTURE-MODIFYING METHODS

These methods are provided for modifying the content of trees
by adding or changing nodes as parents or children of other nodes.

=head2 $h->push_content($element_or_text, ...)

Adds the specified items to the I<end> of the content list of the
element C<$h>.  The items of content to be added should each be either a
text segment (a string), an HTML::Element object, or an arrayref.
Arrayrefs are fed thru C<< $h->new_from_lol(that_arrayref) >> to
convert them into elements, before being added to the content
list of C<$h>.  This means you can say things concise things like:

  $body->push_content(
    ['br'],
    ['ul',
      map ['li', $_], qw(Peaches Apples Pears Mangos)
    ]
  );

See C<new_from_lol> method's documentation, far below, for more
explanation.

The push_content method will try to consolidate adjacent text segments
while adding to the content list.  That's to say, if $h's content_list is

  ('foo bar ', $some_node, 'baz!')

and you call

   $h->push_content('quack?');

then the resulting content list will be this:

  ('foo bar ', $some_node, 'baz!quack?')

and not this:

  ('foo bar ', $some_node, 'baz!', 'quack?')

If that latter is what you want, you'll have to override the
feature of consolidating text by using splice_content,
as in:

  $h->splice_content(scalar($h->content_list),0,'quack?');

Similarly, if you wanted to add 'Skronk' to the beginning of
the content list, calling this:

   $h->unshift_content('Skronk');

then the resulting content list will be this:

  ('Skronkfoo bar ', $some_node, 'baz!')

and not this:

  ('Skronk', 'foo bar ', $some_node, 'baz!')

What you'd to do get the latter is:

  $h->splice_content(0,0,'Skronk');

=cut

sub push_content {
    my $self = shift;
    return $self unless @_;

    my $content = ( $self->{'_content'} ||= [] );
    for (@_) {
        if ( ref($_) eq 'ARRAY' ) {

            # magically call new_from_lol
            push @$content, $self->new_from_lol($_);
            $content->[-1]->{'_parent'} = $self;
        }
        elsif ( ref($_) ) {    # insert an element
            $_->detach if $_->{'_parent'};
            $_->{'_parent'} = $self;
            push( @$content, $_ );
        }
        else {                 # insert text segment
            if ( @$content && !ref $content->[-1] ) {

                # last content element is also text segment -- append
                $content->[-1] .= $_;
            }
            else {
                push( @$content, $_ );
            }
        }
    }
    return $self;
}

=head2 $h->unshift_content($element_or_text, ...)

Just like C<push_content>, but adds to the I<beginning> of the $h
element's content list.

The items of content to be added should each be
either a text segment (a string), an HTML::Element object, or
an arrayref (which is fed thru C<new_from_lol>).

The unshift_content method will try to consolidate adjacent text segments
while adding to the content list.  See above for a discussion of this.

=cut

sub unshift_content {
    my $self = shift;
    return $self unless @_;

    my $content = ( $self->{'_content'} ||= [] );
    for ( reverse @_ ) {    # so they get added in the order specified
        if ( ref($_) eq 'ARRAY' ) {

            # magically call new_from_lol
            unshift @$content, $self->new_from_lol($_);
            $content->[0]->{'_parent'} = $self;
        }
        elsif ( ref $_ ) {    # insert an element
            $_->detach if $_->{'_parent'};
            $_->{'_parent'} = $self;
            unshift( @$content, $_ );
        }
        else {                # insert text segment
            if ( @$content && !ref $content->[0] ) {

                # last content element is also text segment -- prepend
                $content->[0] = $_ . $content->[0];
            }
            else {
                unshift( @$content, $_ );
            }
        }
    }
    return $self;
}

# Cf.  splice ARRAY,OFFSET,LENGTH,LIST

=head2 $h->splice_content($offset, $length, $element_or_text, ...)

Detaches the elements from $h's list of content-nodes, starting at
$offset and continuing for $length items, replacing them with the
elements of the following list, if any.  Returns the elements (if any)
removed from the content-list.  If $offset is negative, then it starts
that far from the end of the array, just like Perl's normal C<splice>
function.  If $length and the following list is omitted, removes
everything from $offset onward.

The items of content to be added (if any) should each be either a text
segment (a string), an arrayref (which is fed thru C<new_from_lol>),
or an HTML::Element object that's not already
a child of $h.

=cut

sub splice_content {
    my ( $self, $offset, $length, @to_add ) = @_;
    Carp::croak "splice_content requires at least one argument"
        if @_ < 2;    # at least $h->splice_content($offset);
    return $self unless @_;

    my $content = ( $self->{'_content'} ||= [] );

    # prep the list

    my @out;
    if ( @_ > 2 ) {    # self, offset, length, ...
        foreach my $n (@to_add) {
            if ( ref($n) eq 'ARRAY' ) {
                $n = $self->new_from_lol($n);
                $n->{'_parent'} = $self;
            }
            elsif ( ref($n) ) {
                $n->detach;
                $n->{'_parent'} = $self;
            }
        }
        @out = splice @$content, $offset, $length, @to_add;
    }
    else {    #  self, offset
        @out = splice @$content, $offset;
    }
    foreach my $n (@out) {
        $n->{'_parent'} = undef if ref $n;
    }
    return @out;
}

=head2 $h->detach()

This unlinks $h from its parent, by setting its 'parent' attribute to
undef, and by removing it from the content list of its parent (if it
had one).  The return value is the parent that was detached from (or
undef, if $h had no parent to start with).  Note that neither $h nor
its parent are explicitly destroyed.

=cut

sub detach {
    my $self = $_[0];
    return unless ( my $parent = $self->{'_parent'} );
    $self->{'_parent'} = undef;
    my $cohort = $parent->{'_content'} || return $parent;
    @$cohort = grep { not( ref($_) and $_ eq $self ) } @$cohort;

    # filter $self out, if parent has any evident content

    return $parent;
}

=head2 $h->detach_content()

This unlinks all of $h's children from $h, and returns them.
Note that these are not explicitly destroyed; for that, you
can just use $h->delete_content.

=cut

sub detach_content {
    my $c = $_[0]->{'_content'} || return ();    # in case of no content
    for (@$c) {
        $_->{'_parent'} = undef if ref $_;
    }
    return splice @$c;
}

=head2 $h->replace_with( $element_or_text, ... ) 

This replaces C<$h> in its parent's content list with the nodes
specified.  The element C<$h> (which by then may have no parent)
is returned.  This causes a fatal error if C<$h> has no parent.
The list of nodes to insert may contain C<$h>, but at most once.
Aside from that possible exception, the nodes to insert should not
already be children of C<$h>'s parent.

Also, note that this method does not destroy C<$h> -- use
C<< $h->replace_with(...)->delete >> if you need that.

=cut

sub replace_with {
    my ( $self, @replacers ) = @_;
    Carp::croak "the target node has no parent"
        unless my ($parent) = $self->{'_parent'};

    my $parent_content = $parent->{'_content'};
    Carp::croak "the target node's parent has no content!?"
        unless $parent_content and @$parent_content;

    my $replacers_contains_self;
    for (@replacers) {
        if ( !ref $_ ) {

            # noop
        }
        elsif ( $_ eq $self ) {

            # noop, but check that it's there just once.
            Carp::croak "Replacement list contains several copies of target!"
                if $replacers_contains_self++;
        }
        elsif ( $_ eq $parent ) {
            Carp::croak "Can't replace an item with its parent!";
        }
        elsif ( ref($_) eq 'ARRAY' ) {
            $_ = $self->new_from_lol($_);
            $_->{'_parent'} = $parent;
        }
        else {
            $_->detach;
            $_->{'_parent'} = $parent;

            # each of these are necessary
        }
    }    # for @replacers
    @$parent_content = map { ( ref($_) and $_ eq $self ) ? @replacers : $_ }
        @$parent_content;

    $self->{'_parent'} = undef unless $replacers_contains_self;

    # if replacers does contain self, then the parent attribute is fine as-is

    return $self;
}

=head2 $h->preinsert($element_or_text...)

Inserts the given nodes right BEFORE C<$h> in C<$h>'s parent's
content list.  This causes a fatal error if C<$h> has no parent.
None of the given nodes should be C<$h> or other children of C<$h>.
Returns C<$h>.

=cut

sub preinsert {
    my $self = shift;
    return $self unless @_;
    return $self->replace_with( @_, $self );
}

=head2 $h->postinsert($element_or_text...)

Inserts the given nodes right AFTER C<$h> in C<$h>'s parent's content
list.  This causes a fatal error if C<$h> has no parent.  None of
the given nodes should be C<$h> or other children of C<$h>.  Returns
C<$h>.

=cut

sub postinsert {
    my $self = shift;
    return $self unless @_;
    return $self->replace_with( $self, @_ );
}

=head2 $h->replace_with_content()

This replaces C<$h> in its parent's content list with its own content.
The element C<$h> (which by then has no parent or content of its own) is
returned.  This causes a fatal error if C<$h> has no parent.  Also, note
that this does not destroy C<$h> -- use
C<< $h->replace_with_content->delete >> if you need that.

=cut

sub replace_with_content {
    my $self = $_[0];
    Carp::croak "the target node has no parent"
        unless my ($parent) = $self->{'_parent'};

    my $parent_content = $parent->{'_content'};
    Carp::croak "the target node's parent has no content!?"
        unless $parent_content and @$parent_content;

    my $content_r = $self->{'_content'} || [];
    @$parent_content = map { ( ref($_) and $_ eq $self ) ? @$content_r : $_ }
        @$parent_content;

    $self->{'_parent'} = undef;    # detach $self from its parent

    # Update parentage link, removing from $self's content list
    for ( splice @$content_r ) { $_->{'_parent'} = $parent if ref $_ }

    return $self;                  # note: doesn't destroy it.
}

=head2 $h->delete_content()

Clears the content of C<$h>, calling C<< $h->delete >> for each content
element.  Compare with C<< $h->detach_content >>.

Returns C<$h>.

=cut

sub delete_content {
    for (
        splice @{
            delete( $_[0]->{'_content'} )

                # Deleting it here (while holding its value, for the moment)
                #  will keep calls to detach() from trying to uselessly filter
                #  the list (as they won't be able to see it once it's been
                #  deleted)
                || return ( $_[0] )    # in case of no content
        },
        0

        # the splice is so we can null the array too, just in case
        # something somewhere holds a ref to it
        )
    {
        $_->delete if ref $_;
    }
    $_[0];
}

=head2 $h->delete() destroy destroy_content

Detaches this element from its parent (if it has one) and explicitly
destroys the element and all its descendants.  The return value is
undef.

Perl uses garbage collection based on reference counting; when no
references to a data structure exist, it's implicitly destroyed --
i.e., when no value anywhere points to a given object anymore, Perl
knows it can free up the memory that the now-unused object occupies.

But this fails with HTML::Element trees, because a parent element
always holds references to its children, and its children elements
hold references to the parent, so no element ever looks like it's
I<not> in use.  So, to destroy those elements, you need to call
C<< $h->delete >> on the parent.

=cut

# two handy aliases
sub destroy         { shift->delete(@_) }
sub destroy_content { shift->delete_content(@_) }

sub delete {
    my $self = $_[0];
    $self->delete_content    # recurse down
        if $self->{'_content'} && @{ $self->{'_content'} };

    $self->detach if $self->{'_parent'} and $self->{'_parent'}{'_content'};

    # not the typical case

    %$self = ();             # null out the whole object on the way out
    return;
}

=head2 $h->clone()

Returns a copy of the element (whose children are clones (recursively)
of the original's children, if any).

The returned element is parentless.  Any '_pos' attributes present in the
source element/tree will be absent in the copy.  For that and other reasons,
the clone of an HTML::TreeBuilder object that's in mid-parse (i.e, the head
of a tree that HTML::TreeBuilder is elaborating) cannot (currently) be used
to continue the parse.

You are free to clone HTML::TreeBuilder trees, just as long as:
1) they're done being parsed, or 2) you don't expect to resume parsing
into the clone.  (You can continue parsing into the original; it is
never affected.)

=cut

sub clone {

    #print "Cloning $_[0]\n";
    my $it = shift;
    Carp::croak "clone() can be called only as an object method"
        unless ref $it;
    Carp::croak "clone() takes no arguments" if @_;

    my $new = bless {%$it}, ref($it);    # COPY!!! HOOBOY!
    delete @$new{ '_content', '_parent', '_pos', '_head', '_body' };

    # clone any contents
    if ( $it->{'_content'} and @{ $it->{'_content'} } ) {
        $new->{'_content'}
            = [ ref($it)->clone_list( @{ $it->{'_content'} } ) ];
        for ( @{ $new->{'_content'} } ) {
            $_->{'_parent'} = $new if ref $_;
        }
    }

    return $new;
}

=head2 HTML::Element->clone_list(...nodes...)

Returns a list consisting of a copy of each node given.
Text segments are simply copied; elements are cloned by
calling $it->clone on each of them.

Note that this must be called as a class method, not as an instance
method.  C<clone_list> will croak if called as an instance method.
You can also call it like so:

    ref($h)->clone_list(...nodes...)

=cut

sub clone_list {
    Carp::croak "clone_list can be called only as a class method"
        if ref shift @_;

    # all that does is get me here
    return map {
        ref($_)
            ? $_->clone    # copy by method
            : $_           # copy by evaluation
    } @_;
}

=head2 $h->normalize_content

Normalizes the content of C<$h> -- i.e., concatenates any adjacent
text nodes.  (Any undefined text segments are turned into empty-strings.)
Note that this does not recurse into C<$h>'s descendants.

=cut

sub normalize_content {
    my $start = $_[0];
    my $c;
    return
        unless $c = $start->{'_content'} and ref $c and @$c;   # nothing to do
        # TODO: if we start having text elements, deal with catenating those too?
    my @stretches = (undef);    # start with a barrier

    # I suppose this could be rewritten to treat stretches as it goes, instead
    #  of at the end.  But feh.

    # Scan:
    for ( my $i = 0; $i < @$c; ++$i ) {
        if ( defined $c->[$i] and ref $c->[$i] ) {    # not a text segment
            if ( $stretches[0] ) {

                # put in a barrier
                if ( $stretches[0][1] == 1 ) {

                    #print "Nixing stretch at ", $i-1, "\n";
                    undef $stretches[0]; # nix the previous one-node "stretch"
                }
                else {

                    #print "End of stretch at ", $i-1, "\n";
                    unshift @stretches, undef;
                }
            }

            # else no need for a barrier
        }
        else {                           # text segment
            $c->[$i] = '' unless defined $c->[$i];
            if ( $stretches[0] ) {
                ++$stretches[0][1];      # increase length
            }
            else {

                #print "New stretch at $i\n";
                unshift @stretches, [ $i, 1 ];    # start and length
            }
        }
    }

    # Now combine.  Note that @stretches is in reverse order, so the indexes
    # still make sense as we work our way thru (i.e., backwards thru $c).
    foreach my $s (@stretches) {
        if ( $s and $s->[1] > 1 ) {

            #print "Stretch at ", $s->[0], " for ", $s->[1], "\n";
            $c->[ $s->[0] ]
                .= join( '', splice( @$c, $s->[0] + 1, $s->[1] - 1 ) )

                # append the subsequent ones onto the first one.
        }
    }
    return;
}

=head2 $h->delete_ignorable_whitespace()

This traverses under C<$h> and deletes any text segments that are ignorable
whitespace.  You should not use this if C<$h> under a 'pre' element.

=cut

sub delete_ignorable_whitespace {

    # This doesn't delete all sorts of whitespace that won't actually
    #  be used in rendering, tho -- that's up to the rendering application.
    # For example:
    #   <input type='text' name='foo'>
    #     [some whitespace]
    #   <input type='text' name='bar'>
    # The WS between the two elements /will/ get used by the renderer.
    # But here:
    #   <input type='hidden' name='foo' value='1'>
    #     [some whitespace]
    #   <input type='text' name='bar' value='2'>
    # the WS between them won't be rendered in any way, presumably.

    #my $Debug = 4;
    die "delete_ignorable_whitespace can be called only as an object method"
        unless ref $_[0];

    print "About to tighten up...\n" if $Debug > 2;
    my (@to_do) = ( $_[0] );    # Start off.
    my ( $i, $sibs, $ptag, $this );    # scratch for the loop...
    while (@to_do) {
        if (   ( $ptag = ( $this = shift @to_do )->{'_tag'} ) eq 'pre'
            or $ptag eq 'textarea'
            or $HTML::Tagset::isCDATA_Parent{$ptag} )
        {

            # block the traversal under those
            print "Blocking traversal under $ptag\n" if $Debug;
            next;
        }
        next unless ( $sibs = $this->{'_content'} and @$sibs );
        for ( $i = $#$sibs; $i >= 0; --$i ) {   # work backwards thru the list
            if ( ref $sibs->[$i] ) {
                unshift @to_do, $sibs->[$i];

                # yes, this happens in pre order -- we're going backwards
                # thru this sibling list.  I doubt it actually matters, tho.
                next;
            }
            next if $sibs->[$i] =~ m<[^\n\r\f\t ]>s;   # it's /all/ whitespace

            print "Under $ptag whose canTighten ",
                "value is ", 0 + $HTML::Element::canTighten{$ptag}, ".\n"
                if $Debug > 3;

            # It's all whitespace...

            if ( $i == 0 ) {
                if ( @$sibs == 1 ) {                   # I'm an only child
                    next unless $HTML::Element::canTighten{$ptag};    # parent
                }
                else {    # I'm leftmost of many
                          # if either my parent or sib are eligible, I'm good.
                    next
                        unless $HTML::Element::canTighten{$ptag}    # parent
                            or (ref $sibs->[1]
                                and $HTML::Element::canTighten{ $sibs->[1]
                                        {'_tag'} }    # right sib
                            );
                }
            }
            elsif ( $i == $#$sibs ) {                 # I'm rightmost of many
                    # if either my parent or sib are eligible, I'm good.
                next
                    unless $HTML::Element::canTighten{$ptag}    # parent
                        or (ref $sibs->[ $i - 1 ]
                            and $HTML::Element::canTighten{ $sibs->[ $i - 1 ]
                                    {'_tag'} }                  # left sib
                        );
            }
            else {    # I'm the piggy in the middle
                      # My parent doesn't matter -- it all depends on my sibs
                next
                    unless ref $sibs->[ $i - 1 ]
                        or ref $sibs->[ $i + 1 ];

                # if NEITHER sib is a node, quit

                next if

                    # bailout condition: if BOTH are INeligible nodes
                    #  (as opposed to being text, or being eligible nodes)
                    ref $sibs->[ $i - 1 ]
                        and ref $sibs->[ $i + 1 ]
                        and !$HTML::Element::canTighten{ $sibs->[ $i - 1 ]
                                {'_tag'} }    # left sib
                        and !$HTML::Element::canTighten{ $sibs->[ $i + 1 ]
                                {'_tag'} }    # right sib
                ;
            }

       # Unknown tags aren't in canTighten and so AREN'T subject to tightening

            print "  delendum: child $i of $ptag\n" if $Debug > 3;
            splice @$sibs, $i, 1;
        }

        # end of the loop-over-children
    }

    # end of the while loop.

    return;
}

=head2 $h->insert_element($element, $implicit)

Inserts (via push_content) a new element under the element at
C<< $h->pos() >>.  Then updates C<< $h->pos() >> to point to the inserted
element, unless $element is a prototypically empty element like
"br", "hr", "img", etc.  The new C<< $h->pos() >> is returned.  This
method is useful only if your particular tree task involves setting
C<< $h->pos() >>.

=cut

sub insert_element {
    my ( $self, $tag, $implicit ) = @_;
    return $self->pos() unless $tag;    # noop if nothing to insert

    my $e;
    if ( ref $tag ) {
        $e   = $tag;
        $tag = $e->tag;
    }
    else {    # just a tag name -- so make the element
        $e = $self->element_class->new($tag);
        ++( $self->{'_element_count'} ) if exists $self->{'_element_count'};

        # undocumented.  see TreeBuilder.
    }

    $e->{'_implicit'} = 1 if $implicit;

    my $pos = $self->{'_pos'};
    $pos = $self unless defined $pos;

    $pos->push_content($e);

    $self->{'_pos'} = $pos = $e
        unless $self->_empty_element_map->{$tag} || $e->{'_empty_element'};

    $pos;
}

#==========================================================================
# Some things to override in XML::Element

sub _empty_element_map {
    \%HTML::Element::emptyElement;
}

sub _fold_case_LC {
    if (wantarray) {
        shift;
        map lc($_), @_;
    }
    else {
        return lc( $_[1] );
    }
}

sub _fold_case_NOT {
    if (wantarray) {
        shift;
        @_;
    }
    else {
        return $_[1];
    }
}

*_fold_case = \&_fold_case_LC;

#==========================================================================

=head1 DUMPING METHODS

=head2 $h->dump()

=head2 $h->dump(*FH)  ; # or *FH{IO} or $fh_obj

Prints the element and all its children to STDOUT (or to a specified
filehandle), in a format useful
only for debugging.  The structure of the document is shown by
indentation (no end tags).

=cut

sub dump {
    my ( $self, $fh, $depth ) = @_;
    $fh    = *STDOUT{IO} unless defined $fh;
    $depth = 0           unless defined $depth;
    print $fh "  " x $depth, $self->starttag, " \@", $self->address,
        $self->{'_implicit'} ? " (IMPLICIT)\n" : "\n";
    for ( @{ $self->{'_content'} } ) {
        if ( ref $_ ) {    # element
            $_->dump( $fh, $depth + 1 );    # recurse
        }
        else {                              # text node
            print $fh "  " x ( $depth + 1 );
            if ( length($_) > 65 or m<[\x00-\x1F]> ) {

                # it needs prettyin' up somehow or other
                my $x
                    = ( length($_) <= 65 )
                    ? $_
                    : ( substr( $_, 0, 65 ) . '...' );
                $x =~ s<([\x00-\x1F])>
                     <'\\x'.(unpack("H2",$1))>eg;
                print $fh qq{"$x"\n};
            }
            else {
                print $fh qq{"$_"\n};
            }
        }
    }
}

=head2 $h->as_HTML() or $h->as_HTML($entities)

=head2 or $h->as_HTML($entities, $indent_char)

=head2 or $h->as_HTML($entities, $indent_char, \%optional_end_tags)

Returns a string representing in HTML the element and its
descendants.  The optional argument C<$entities> specifies a string of
the entities to encode.  For compatibility with previous versions,
specify C<'E<lt>E<gt>&'> here.  If omitted or undef, I<all> unsafe
characters are encoded as HTML entities.  See L<HTML::Entities> for
details.  If passed an empty string, no entities are encoded.

If $indent_char is specified and defined, the HTML to be output is
intented, using the string you specify (which you probably should
set to "\t", or some number of spaces, if you specify it).

If C<\%optional_end_tags> is specified and defined, it should be
a reference to a hash that holds a true value for every tag name
whose end tag is optional.  Defaults to
C<\%HTML::Element::optionalEndTag>, which is an alias to 
C<%HTML::Tagset::optionalEndTag>, which, at time of writing, contains
true values for C<p, li, dt, dd>.  A useful value to pass is an empty
hashref, C<{}>, which means that no end-tags are optional for this dump.
Otherwise, possibly consider copying C<%HTML::Tagset::optionalEndTag> to a 
hash of your own, adding or deleting values as you like, and passing
a reference to that hash.

=cut

sub as_HTML {
    my ( $self, $entities, $indent, $omissible_map ) = @_;

    #my $indent_on = defined($indent) && length($indent);
    my @html = ();

    $omissible_map ||= \%HTML::Element::optionalEndTag;
    my $empty_element_map = $self->_empty_element_map;

    my $last_tag_tightenable    = 0;
    my $this_tag_tightenable    = 0;
    my $nonindentable_ancestors = 0;    # count of nonindentible tags over us.

    my ( $tag, $node, $start, $depth ); # per-iteration scratch

    if ( defined($indent) && length($indent) ) {
        $self->traverse(
            sub {
                ( $node, $start, $depth ) = @_;
                if ( ref $node ) {      # it's an element

                    # detect bogus classes. RT #35948, #61673
                    $node->can('starttag')
                        or Carp::confess( "Object of class "
                            . ref($node)
                            . " cannot be processed by HTML::Element" );

                    $tag = $node->{'_tag'};

                    if ($start) {       # on the way in
                        if ((   $this_tag_tightenable
                                = $HTML::Element::canTighten{$tag}
                            )
                            and !$nonindentable_ancestors
                            and $last_tag_tightenable
                            )
                        {
                            push
                                @html,
                                "\n",
                                $indent x $depth,
                                $node->starttag($entities),
                                ;
                        }
                        else {
                            push( @html, $node->starttag($entities) );
                        }
                        $last_tag_tightenable = $this_tag_tightenable;

                        ++$nonindentable_ancestors
                            if $tag eq 'pre'
                                or $HTML::Tagset::isCDATA_Parent{$tag};

                    }
                    elsif (
                        not(   $empty_element_map->{$tag}
                            or $omissible_map->{$tag} )
                        )
                    {

                        # on the way out
                        if (   $tag eq 'pre'
                            or $HTML::Tagset::isCDATA_Parent{$tag} )
                        {
                            --$nonindentable_ancestors;
                            $last_tag_tightenable
                                = $HTML::Element::canTighten{$tag};
                            push @html, $node->endtag;

                        }
                        else {    # general case
                            if ((   $this_tag_tightenable
                                    = $HTML::Element::canTighten{$tag}
                                )
                                and !$nonindentable_ancestors
                                and $last_tag_tightenable
                                )
                            {
                                push
                                    @html,
                                    "\n",
                                    $indent x $depth,
                                    $node->endtag,
                                    ;
                            }
                            else {
                                push @html, $node->endtag;
                            }
                            $last_tag_tightenable = $this_tag_tightenable;

                           #print "$tag tightenable: $this_tag_tightenable\n";
                        }
                    }
                }
                else {    # it's a text segment

                    $last_tag_tightenable = 0;    # I guess this is right
                    HTML::Entities::encode_entities( $node, $entities )

                        # That does magic things if $entities is undef.
                        unless (
                        ( defined($entities) && !length($entities) )

                        # If there's no entity to encode, don't call it
                        || $HTML::Tagset::isCDATA_Parent{ $_[3]{'_tag'} }

                        # To keep from amp-escaping children of script et al.
                        # That doesn't deal with descendants; but then, CDATA
                        #  parents shouldn't /have/ descendants other than a
                        #  text children (or comments?)
                        || $encoded_content
                        );
                    if ($nonindentable_ancestors) {
                        push @html, $node;    # say no go
                    }
                    else {
                        if ($last_tag_tightenable) {
                            $node =~ s<[\n\r\f\t ]+>< >s;

                            #$node =~ s< $><>s;
                            $node =~ s<^ ><>s;
                            push
                                @html,
                                "\n",
                                $indent x $depth,
                                $node,

           #Text::Wrap::wrap($indent x $depth, $indent x $depth, "\n" . $node)
                                ;
                        }
                        else {
                            push
                                @html,
                                $node,

                                #Text::Wrap::wrap('', $indent x $depth, $node)
                                ;
                        }
                    }
                }
                1;    # keep traversing
            }
        );            # End of parms to traverse()
    }
    else {            # no indenting -- much simpler code
        $self->traverse(
            sub {
                ( $node, $start ) = @_;
                if ( ref $node ) {

                    # detect bogus classes. RT #35948
                    $node->isa( $self->element_class )
                        or Carp::confess( "Object of class "
                            . ref($node)
                            . " cannot be processed by HTML::Element" );

                    $tag = $node->{'_tag'};
                    if ($start) {    # on the way in
                        push( @html, $node->starttag($entities) );
                    }
                    elsif (
                        not(   $empty_element_map->{$tag}
                            or $omissible_map->{$tag} )
                        )
                    {

                        # on the way out
                        push( @html, $node->endtag );
                    }
                }
                else {

                    # simple text content
                    HTML::Entities::encode_entities( $node, $entities )

                        # That does magic things if $entities is undef.
                        unless (
                        ( defined($entities) && !length($entities) )

                        # If there's no entity to encode, don't call it
                        || $HTML::Tagset::isCDATA_Parent{ $_[3]{'_tag'} }

                        # To keep from amp-escaping children of script et al.
                        # That doesn't deal with descendants; but then, CDATA
                        #  parents shouldn't /have/ descendants other than a
                        #  text children (or comments?)
                        || $encoded_content
                        );
                    push( @html, $node );
                }
                1;    # keep traversing
            }
        );            # End of parms to traverse()
    }

    if ( $self->{_store_declarations} && defined $self->{_decl} ) {
        unshift @html, sprintf "<!%s>\n", $self->{_decl}->{text};
    }

    return join( '', @html );
}

=head2 $h->as_text()

=head2 $h->as_text(skip_dels => 1, extra_chars => '\xA0')

Returns a string consisting of only the text parts of the element's
descendants.

Text under 'script' or 'style' elements is never included in what's
returned.  If C<skip_dels> is true, then text content under "del"
nodes is not included in what's returned.

=head2 $h->as_trimmed_text(...) as_text_trimmed

This is just like as_text(...) except that leading and trailing
whitespace is deleted, and any internal whitespace is collapsed.

This will not remove hard spaces, unicode spaces, or any other
non ASCII white space unless you supplye the extra characters as
a string argument. e.g. $h->as_trimmed_text(extra_chars => '\xA0')

=cut

sub as_text {

    # Yet another iteratively implemented traverser
    my ( $this, %options ) = @_;
    my $skip_dels = $options{'skip_dels'} || 0;
    my (@pile) = ($this);
    my $tag;
    my $text = '';
    while (@pile) {
        if ( !defined( $pile[0] ) ) {    # undef!
                                         # no-op
        }
        elsif ( !ref( $pile[0] ) ) {     # text bit!  save it!
            $text .= shift @pile;
        }
        else {                           # it's a ref -- traverse under it
            unshift @pile, @{ $this->{'_content'} || $nillio }
                unless ( $tag = ( $this = shift @pile )->{'_tag'} ) eq 'style'
                or $tag eq 'script'
                or ( $skip_dels and $tag eq 'del' );
        }
    }
    return $text;
}

# extra_chars added for RT #26436
sub as_trimmed_text {
    my ( $this, %options ) = @_;
    my $text = $this->as_text(%options);
    my $extra_chars = $options{'extra_chars'} || '';

    $text =~ s/[\n\r\f\t$extra_chars ]+$//s;
    $text =~ s/^[\n\r\f\t$extra_chars ]+//s;
    $text =~ s/[\n\r\f\t$extra_chars ]+/ /g;
    return $text;
}

sub as_text_trimmed { shift->as_trimmed_text(@_) }   # alias, because I forget

=head2 $h->as_XML()

Returns a string representing in XML the element and its descendants.

The XML is not indented.

=cut

# TODO: make it wrap, if not indent?

sub as_XML {

    # based an as_HTML
    my ($self) = @_;

    #my $indent_on = defined($indent) && length($indent);
    my @xml               = ();
    my $empty_element_map = $self->_empty_element_map;

    my ( $tag, $node, $start );    # per-iteration scratch
    $self->traverse(
        sub {
            ( $node, $start ) = @_;
            if ( ref $node ) {     # it's an element
                $tag = $node->{'_tag'};
                if ($start) {      # on the way in

                    foreach my $attr ( $node->all_attr_names() ) {
                        Carp::croak(
                            "$tag has an invalid attribute name '$attr'")
                            unless ( $attr eq '/' || $self->_valid_name($attr) );
                    }

                    if ( $empty_element_map->{$tag}
                        and !@{ $node->{'_content'} || $nillio } )
                    {
                        push( @xml, $node->starttag_XML( undef, 1 ) );
                    }
                    else {
                        push( @xml, $node->starttag_XML(undef) );
                    }
                }
                else {    # on the way out
                    unless ( $empty_element_map->{$tag}
                        and !@{ $node->{'_content'} || $nillio } )
                    {
                        push( @xml, $node->endtag_XML() );
                    }     # otherwise it will have been an <... /> tag.
                }
            }
            else {        # it's just text
                _xml_escape($node);
                push( @xml, $node );
            }
            1;            # keep traversing
        }
    );

    join( '', @xml, "\n" );
}

sub _xml_escape {

# DESTRUCTIVE (a.k.a. "in-place")
# Five required escapes: http://www.w3.org/TR/2006/REC-xml11-20060816/#syntax
# We allow & if it's part of a valid escape already: http://www.w3.org/TR/2006/REC-xml11-20060816/#sec-references
    foreach my $x (@_) {

        # In strings with no encoded entities all & should be encoded.
        if ($encoded_content) {
            $x
                =~ s/&(?!                 # An ampersand that isn't followed by...
                (\#\d+; |                 # A hash mark, digits and semicolon, or
                \#x[\da-f]+; |            # A hash mark, "x", hex digits and semicolon, or
                $START_CHAR$NAME_CHAR+; ) # A valid unicode entity name and semicolon
           )/&amp;/gx;    # Needs to be escaped to amp
        }
        else {
            $x =~ s/&/&amp;/g;
        }

        # simple character escapes
        $x =~ s/</&lt;/g;
        $x =~ s/>/&gt;/g;
        $x =~ s/"/&quot;/g;
        $x =~ s/'/&apos;/g;
    }
    return;
}

=head2 $h->as_Lisp_form()

Returns a string representing the element and its descendants as a
Lisp form.  Unsafe characters are encoded as octal escapes.

The Lisp form is indented, and contains external ("href", etc.)  as
well as internal attributes ("_tag", "_content", "_implicit", etc.),
except for "_parent", which is omitted.

Current example output for a given element:

  ("_tag" "img" "border" "0" "src" "pie.png" "usemap" "#main.map")

=cut

# NOTES:
#
# It's been suggested that attribute names be made :-keywords:
#   (:_tag "img" :border 0 :src "pie.png" :usemap "#main.map")
# However, it seems that Scheme has no such data type as :-keywords.
# So, for the moment at least, I tend toward simplicity, uniformity,
#  and universality, where everything a string or a list.

sub as_Lisp_form {
    my @out;

    my $sub;
    my $depth = 0;
    my ( @list, $val );
    $sub = sub {    # Recursor
        my $self = $_[0];
        @list = ( '_tag', $self->{'_tag'} );
        @list = () unless defined $list[-1];    # unlikely

        for ( sort keys %$self ) {              # predictable ordering
            next
                if $_ eq '_content'
                    or $_ eq '_tag'
                    or $_ eq '_parent'
                    or $_ eq '/';

            # Leave the other private attributes, I guess.
            push @list, $_, $val
                if defined( $val = $self->{$_} );    # and !ref $val;
        }

        for (@list) {

            # octal-escape it
            s<([^\x20\x21\x23\x27-\x5B\x5D-\x7E])>
         <sprintf('\\%03o',ord($1))>eg;
            $_ = qq{"$_"};
        }
        push @out, ( '  ' x $depth ) . '(' . join ' ', splice @list;
        if ( @{ $self->{'_content'} || $nillio } ) {
            $out[-1] .= " \"_content\" (\n";
            ++$depth;
            foreach my $c ( @{ $self->{'_content'} } ) {
                if ( ref($c) ) {

                    # an element -- recurse
                    $sub->($c);
                }
                else {

                    # a text segment -- stick it in and octal-escape it
                    push @out, $c;
                    $out[-1] =~ s<([^\x20\x21\x23\x27-\x5B\x5D-\x7E])>
             <sprintf('\\%03o',ord($1))>eg;

                    # And quote and indent it.
                    $out[-1] .= "\"\n";
                    $out[-1] = ( '  ' x $depth ) . '"' . $out[-1];
                }
            }
            --$depth;
            substr( $out[-1], -1 )
                = "))\n";    # end of _content and of the element
        }
        else {
            $out[-1] .= ")\n";
        }
        return;
    };

    $sub->( $_[0] );
    undef $sub;
    return join '', @out;
}

=head2 format

Formats text output. Defaults to HTML::FormatText.

Takes a second argument that is a reference to a formatter.

=cut

sub format {
    my ( $self, $formatter ) = @_;
    unless ( defined $formatter ) {
        require HTML::FormatText;
        $formatter = HTML::FormatText->new();
    }
    $formatter->format($self);
}

=head2 $h->starttag() or $h->starttag($entities)

Returns a string representing the complete start tag for the element.
I.e., leading "<", tag name, attributes, and trailing ">".
All values are surrounded with
double-quotes, and appropriate characters are encoded.  If C<$entities>
is omitted or undef, I<all> unsafe characters are encoded as HTML
entities.  See L<HTML::Entities> for details.  If you specify some
value for C<$entities>, remember to include the double-quote character in
it.  (Previous versions of this module would basically behave as if
C<'&"E<gt>'> were specified for C<$entities>.)  If C<$entities> is
an empty string, no entity is escaped.

=cut

sub starttag {
    my ( $self, $entities ) = @_;

    my $name = $self->{'_tag'};

    return $self->{'text'}              if $name eq '~literal';
    return "<!" . $self->{'text'} . ">" if $name eq '~declaration';
    return "<?" . $self->{'text'} . ">" if $name eq '~pi';

    if ( $name eq '~comment' ) {
        if ( ref( $self->{'text'} || '' ) eq 'ARRAY' ) {

            # Does this ever get used?  And is this right?
            return
                "<!"
                . join( ' ', map( "--$_--", @{ $self->{'text'} } ) ) . ">";
        }
        else {
            return "<!--" . $self->{'text'} . "-->";
        }
    }

    my $tag = $html_uc ? "<\U$name" : "<\L$name";
    my $val;
    for ( sort keys %$self ) {    # predictable ordering
        next if !length $_ or m/^_/s or $_ eq '/';
        $val = $self->{$_};
        next if !defined $val;    # or ref $val;
        if ($_ eq $val &&         # if attribute is boolean, for this element
            exists( $HTML::Element::boolean_attr{$name} )
            && (ref( $HTML::Element::boolean_attr{$name} )
                ? $HTML::Element::boolean_attr{$name}{$_}
                : $HTML::Element::boolean_attr{$name} eq $_
            )
            )
        {
            $tag .= $html_uc ? " \U$_" : " \L$_";
        }
        else {                    # non-boolean attribute

            if ( ref $val eq 'HTML::Element'
                and $val->{_tag} eq '~literal' )
            {
                $val = $val->{text};
            }
            else {
                HTML::Entities::encode_entities( $val, $entities )
                    unless (
                    defined($entities) && !length($entities)
                    || $encoded_content

                    );
            }

            $val = qq{"$val"};
            $tag .= $html_uc ? qq{ \U$_\E=$val} : qq{ \L$_\E=$val};
        }
    }    # for keys
    if ( scalar $self->content_list == 0
        && $self->_empty_element_map->{ $self->tag } )
    {
        return $tag . " />";
    }
    else {
        return $tag . ">";
    }
}

=head2 starttag_XML

Returns a string representing the complete start tag for the element.

=cut

sub starttag_XML {
    my ($self) = @_;

    # and a third parameter to signal emptiness?

    my $name = $self->{'_tag'};

    return $self->{'text'}               if $name eq '~literal';
    return '<!' . $self->{'text'} . '>'  if $name eq '~declaration';
    return "<?" . $self->{'text'} . "?>" if $name eq '~pi';

    if ( $name eq '~comment' ) {
        if ( ref( $self->{'text'} || '' ) eq 'ARRAY' ) {

            # Does this ever get used?  And is this right?
            $name = join( ' ', @{ $self->{'text'} } );
        }
        else {
            $name = $self->{'text'};
        }
        $name =~ s/--/-&#45;/g;    # can't have double --'s in XML comments
        return "<!-- $name -->";
    }

    my $tag = "<$name";
    my $val;
    for ( sort keys %$self ) {     # predictable ordering
        next if !length $_ or m/^_/s or $_ eq '/';

        # Hm -- what to do if val is undef?
        # I suppose that shouldn't ever happen.
        next if !defined( $val = $self->{$_} );    # or ref $val;
        _xml_escape($val);
        $tag .= qq{ $_="$val"};
    }
    @_ == 3 ? "$tag />" : "$tag>";
}

=head2 $h->endtag() || endtag_XML

Returns a string representing the complete end tag for this element.
I.e., "</", tag name, and ">".

=cut

sub endtag {
    $html_uc ? "</\U$_[0]->{'_tag'}>" : "</\L$_[0]->{'_tag'}>";
}

# TODO: document?
sub endtag_XML {
    "</$_[0]->{'_tag'}>";
}

#==========================================================================
# This, ladies and germs, is an iterative implementation of a
# recursive algorithm.  DON'T TRY THIS AT HOME.
# Basically, the algorithm says:
#
# To traverse:
#   1: pre-order visit this node
#   2: traverse any children of this node
#   3: post-order visit this node, unless it's a text segment,
#       or a prototypically empty node (like "br", etc.)
# Add to that the consideration of the callbacks' return values,
# so you can block visitation of the children, or siblings, or
# abort the whole excursion, etc.
#
# So, why all this hassle with making the code iterative?
# It makes for real speed, because it eliminates the whole
# hassle of Perl having to allocate scratch space for each
# instance of the recursive sub.  Since the algorithm
# is basically simple (and not all recursive ones are!) and
# has few necessary lexicals (basically just the current node's
# content list, and the current position in it), it was relatively
# straightforward to store that information not as the frame
# of a sub, but as a stack, i.e., a simple Perl array (well, two
# of them, actually: one for content-listrefs, one for indexes of
# current position in each of those).

my $NIL = [];

sub traverse {
    my ( $start, $callback, $ignore_text ) = @_;

    Carp::croak "traverse can be called only as an object method"
        unless ref $start;

    Carp::croak('must provide a callback for traverse()!')
        unless defined $callback and ref $callback;

    # Elementary type-checking:
    my ( $c_pre, $c_post );
    if ( UNIVERSAL::isa( $callback, 'CODE' ) ) {
        $c_pre = $c_post = $callback;
    }
    elsif ( UNIVERSAL::isa( $callback, 'ARRAY' ) ) {
        ( $c_pre, $c_post ) = @$callback;
        Carp::croak(
            "pre-order callback \"$c_pre\" is true but not a coderef!")
            if $c_pre and not UNIVERSAL::isa( $c_pre, 'CODE' );
        Carp::croak(
            "pre-order callback \"$c_post\" is true but not a coderef!")
            if $c_post and not UNIVERSAL::isa( $c_post, 'CODE' );
        return $start unless $c_pre or $c_post;

        # otherwise there'd be nothing to actually do!
    }
    else {
        Carp::croak("$callback is not a known kind of reference")
            unless ref($callback);
    }

    my $empty_element_map = $start->_empty_element_map;

    my (@C) = [$start];    # a stack containing lists of children
    my (@I) = (-1);        # initial value must be -1 for each list
         # a stack of indexes to current position in corresponding lists in @C
         # In each of these, 0 is the active point

    # scratch:
    my ($rv,           # return value of callback
        $this,         # current node
        $content_r,    # child list of $this
    );

    # THE BIG LOOP
    while (@C) {

        # Move to next item in this frame
        if ( !defined( $I[0] ) or ++$I[0] >= @{ $C[0] } ) {

            # We either went off the end of this list, or aborted the list
            # So call the post-order callback:
            if (    $c_post
                and defined $I[0]
                and @C > 1

                # to keep the next line from autovivifying
                and defined( $this = $C[1][ $I[1] ] )    # sanity, and
                     # suppress callbacks on exiting the fictional top frame
                and ref($this)    # sanity
                and not(
                    $this->{'_empty_element'}
                    || ( $empty_element_map->{ $this->{'_tag'} || '' }
                        && !@{ $this->{'_content'} } )    # RT #49932
                )    # things that don't get post-order callbacks
                )
            {
                shift @I;
                shift @C;

                #print "Post! at depth", scalar(@I), "\n";
                $rv = $c_post->(

                    #map $_, # copy to avoid any messiness
                    $this,     # 0: this
                    0,         # 1: startflag (0 for post-order call)
                    @I - 1,    # 2: depth
                );

                if ( defined($rv) and ref($rv) eq $travsignal_package ) {
                    $rv = $$rv;    #deref
                    if ( $rv eq 'ABORT' ) {
                        last;      # end of this excursion!
                    }
                    elsif ( $rv eq 'PRUNE' ) {

                        # NOOP on post!!
                    }
                    elsif ( $rv eq 'PRUNE_SOFTLY' ) {

                        # NOOP on post!!
                    }
                    elsif ( $rv eq 'OK' ) {

                        # noop
                    }
                    elsif ( $rv eq 'PRUNE_UP' ) {
                        $I[0] = undef;
                    }
                    else {
                        die "Unknown travsignal $rv\n";

                        # should never happen
                    }
                }
            }
            else {
                shift @I;
                shift @C;
            }
            next;
        }

        $this = $C[0][ $I[0] ];

        if ($c_pre) {
            if ( defined $this and ref $this ) {    # element
                $rv = $c_pre->(

                    #map $_, # copy to avoid any messiness
                    $this,     # 0: this
                    1,         # 1: startflag (1 for pre-order call)
                    @I - 1,    # 2: depth
                );
            }
            else {             # text segment
                next if $ignore_text;
                $rv = $c_pre->(

                    #map $_, # copy to avoid any messiness
                    $this,           # 0: this
                    1,               # 1: startflag (1 for pre-order call)
                    @I - 1,          # 2: depth
                    $C[1][ $I[1] ],  # 3: parent
                                     # And there will always be a $C[1], since
                             #  we can't start traversing at a text node
                    $I[0]    # 4: index of self in parent's content list
                );
            }
            if ( not $rv ) {    # returned false.  Same as PRUNE.
                next;           # prune
            }
            elsif ( ref($rv) eq $travsignal_package ) {
                $rv = $$rv;     # deref
                if ( $rv eq 'ABORT' ) {
                    last;       # end of this excursion!
                }
                elsif ( $rv eq 'PRUNE' ) {
                    next;
                }
                elsif ( $rv eq 'PRUNE_SOFTLY' ) {
                    if (ref($this)
                        and not( $this->{'_empty_element'}
                            || $empty_element_map->{ $this->{'_tag'} || '' } )
                        )
                    {

             # push a dummy empty content list just to trigger a post callback
                        unshift @I, -1;
                        unshift @C, $NIL;
                    }
                    next;
                }
                elsif ( $rv eq 'OK' ) {

                    # noop
                }
                elsif ( $rv eq 'PRUNE_UP' ) {
                    $I[0] = undef;
                    next;

                    # equivalent of last'ing out of the current child list.

            # Used to have PRUNE_UP_SOFTLY and ABORT_SOFTLY here, but the code
            # for these was seriously upsetting, served no particularly clear
            # purpose, and could not, I think, be easily implemented with a
            # recursive routine.  All bad things!
                }
                else {
                    die "Unknown travsignal $rv\n";

                    # should never happen
                }
            }

            # else fall thru to meaning same as \'OK'.
        }

        # end of pre-order calling

        # Now queue up content list for the current element...
        if (ref $this
            and not(    # ...except for those which...
                not( $content_r = $this->{'_content'} and @$content_r )

                # ...have empty content lists...
                and $this->{'_empty_element'}
                || $empty_element_map->{ $this->{'_tag'} || '' }

                # ...and that don't get post-order callbacks
            )
            )
        {
            unshift @I, -1;
            unshift @C, $content_r || $NIL;

            #print $this->{'_tag'}, " ($this) adds content_r ", $C[0], "\n";
        }
    }
    return $start;
}

=head1 SECONDARY STRUCTURAL METHODS

These methods all involve some structural aspect of the tree;
either they report some aspect of the tree's structure, or they involve
traversal down the tree, or walking up the tree.

=head2 $h->is_inside('tag', ...) or $h->is_inside($element, ...)

Returns true if the $h element is, or is contained anywhere inside an
element that is any of the ones listed, or whose tag name is any of
the tag names listed.

=cut

sub is_inside {
    my $self = shift;
    return unless @_;    # if no items specified, I guess this is right.

    my $current = $self;

    # the loop starts by looking at the given element
    while ( defined $current and ref $current ) {
        for (@_) {
            if (ref) {    # element
                return 1 if $_ eq $current;
            }
            else {        # tag name
                return 1 if $_ eq $current->{'_tag'};
            }
        }
        $current = $current->{'_parent'};
    }
    0;
}

=head2 $h->is_empty()

Returns true if $h has no content, i.e., has no elements or text
segments under it.  In other words, this returns true if $h is a leaf
node, AKA a terminal node.  Do not confuse this sense of "empty" with
another sense that it can have in SGML/HTML/XML terminology, which
means that the element in question is of the type (like HTML's "hr",
"br", "img", etc.) that I<can't> have any content.

That is, a particular "p" element may happen to have no content, so
$that_p_element->is_empty will be true -- even though the prototypical
"p" element isn't "empty" (not in the way that the prototypical "hr"
element is).

If you think this might make for potentially confusing code, consider
simply using the clearer exact equivalent:  not($h->content_list)

=cut

sub is_empty {
    my $self = shift;
    !$self->{'_content'} || !@{ $self->{'_content'} };
}

=head2 $h->pindex()

Return the index of the element in its parent's contents array, such
that $h would equal

  $h->parent->content->[$h->pindex]
  or
  ($h->parent->content_list)[$h->pindex]

assuming $h isn't root.  If the element $h is root, then
$h->pindex returns undef.

=cut

sub pindex {
    my $self = shift;

    my $parent = $self->{'_parent'}    || return;
    my $pc     = $parent->{'_content'} || return;
    for ( my $i = 0; $i < @$pc; ++$i ) {
        return $i if ref $pc->[$i] and $pc->[$i] eq $self;
    }
    return;    # we shouldn't ever get here
}

#--------------------------------------------------------------------------

=head2 $h->left()

In scalar context: returns the node that's the immediate left sibling
of $h.  If $h is the leftmost (or only) child of its parent (or has no
parent), then this returns undef.

In list context: returns all the nodes that're the left siblings of $h
(starting with the leftmost).  If $h is the leftmost (or only) child
of its parent (or has no parent), then this returns empty-list.

(See also $h->preinsert(LIST).)

=cut

sub left {
    Carp::croak "left() is supposed to be an object method"
        unless ref $_[0];
    my $pc = ( $_[0]->{'_parent'} || return )->{'_content'}
        || die "parent is childless?";

    die "parent is childless" unless @$pc;
    return if @$pc == 1;    # I'm an only child

    if (wantarray) {
        my @out;
        foreach my $j (@$pc) {
            return @out if ref $j and $j eq $_[0];
            push @out, $j;
        }
    }
    else {
        for ( my $i = 0; $i < @$pc; ++$i ) {
            return $i ? $pc->[ $i - 1 ] : undef
                if ref $pc->[$i] and $pc->[$i] eq $_[0];
        }
    }

    die "I'm not in my parent's content list?";
    return;
}

=head2 $h->right()

In scalar context: returns the node that's the immediate right sibling
of $h.  If $h is the rightmost (or only) child of its parent (or has
no parent), then this returns undef.

In list context: returns all the nodes that're the right siblings of
$h, starting with the leftmost.  If $h is the rightmost (or only) child
of its parent (or has no parent), then this returns empty-list.

(See also $h->postinsert(LIST).)

=cut

sub right {
    Carp::croak "right() is supposed to be an object method"
        unless ref $_[0];
    my $pc = ( $_[0]->{'_parent'} || return )->{'_content'}
        || die "parent is childless?";

    die "parent is childless" unless @$pc;
    return if @$pc == 1;    # I'm an only child

    if (wantarray) {
        my ( @out, $seen );
        foreach my $j (@$pc) {
            if ($seen) {
                push @out, $j;
            }
            else {
                $seen = 1 if ref $j and $j eq $_[0];
            }
        }
        die "I'm not in my parent's content list?" unless $seen;
        return @out;
    }
    else {
        for ( my $i = 0; $i < @$pc; ++$i ) {
            return +( $i == $#$pc ) ? undef : $pc->[ $i + 1 ]
                if ref $pc->[$i] and $pc->[$i] eq $_[0];
        }
        die "I'm not in my parent's content list?";
        return;
    }
}

#--------------------------------------------------------------------------

=head2 $h->address()

Returns a string representing the location of this node in the tree.
The address consists of numbers joined by a '.', starting with '0',
and followed by the pindexes of the nodes in the tree that are
ancestors of $h, starting from the top.

So if the way to get to a node starting at the root is to go to child
2 of the root, then child 10 of that, and then child 0 of that, and
then you're there -- then that node's address is "0.2.10.0".

As a bit of a special case, the address of the root is simply "0".

I forsee this being used mainly for debugging, but you may
find your own uses for it.

=head2 $h->address($address)

This returns the node (whether element or text-segment) at
the given address in the tree that $h is a part of.  (That is,
the address is resolved starting from $h->root.)

If there is no node at the given address, this returns undef.

You can specify "relative addressing" (i.e., that indexing is supposed
to start from $h and not from $h->root) by having the address start
with a period -- e.g., $h->address(".3.2") will look at child 3 of $h,
and child 2 of that.

=cut

sub address {
    if ( @_ == 1 ) {    # report-address form
        return join(
            '.',
            reverse(    # so it starts at the top
                map( $_->pindex() || '0',    # so that root's undef -> '0'
                    $_[0],                   # self and...
                    $_[0]->lineage )
            )
        );
    }
    else {                                   # get-node-at-address
        my @stack = split( /\./, $_[1] );
        my $here;

        if ( @stack and !length $stack[0] ) {    # relative addressing
            $here = $_[0];
            shift @stack;
        }
        else {                                   # absolute addressing
            return unless 0 == shift @stack;   # to pop the initial 0-for-root
            $here = $_[0]->root;
        }

        while (@stack) {
            return
                unless $here->{'_content'}
                    and @{ $here->{'_content'} } > $stack[0];

            # make sure the index isn't too high
            $here = $here->{'_content'}[ shift @stack ];
            return if @stack and not ref $here;

            # we hit a text node when we expected a non-terminal element node
        }

        return $here;
    }
}

=head2 $h->depth()

Returns a number expressing C<$h>'s depth within its tree, i.e., how many
steps away it is from the root.  If C<$h> has no parent (i.e., is root),
its depth is 0.

=cut

sub depth {
    my $here  = $_[0];
    my $depth = 0;
    while ( defined( $here = $here->{'_parent'} ) and ref($here) ) {
        ++$depth;
    }
    return $depth;
}

=head2 $h->root()

Returns the element that's the top of C<$h>'s tree.  If C<$h> is
root, this just returns C<$h>.  (If you want to test whether C<$h>
I<is> the root, instead of asking what its root is, just test
C<< not($h->parent) >>.)

=cut

sub root {
    my $here = my $root = shift;
    while ( defined( $here = $here->{'_parent'} ) and ref($here) ) {
        $root = $here;
    }
    return $root;
}

=head2 $h->lineage()

Returns the list of C<$h>'s ancestors, starting with its parent,
and then that parent's parent, and so on, up to the root.  If C<$h>
is root, this returns an empty list.

If you simply want a count of the number of elements in C<$h>'s lineage,
use $h->depth.

=cut

sub lineage {
    my $here = shift;
    my @lineage;
    while ( defined( $here = $here->{'_parent'} ) and ref($here) ) {
        push @lineage, $here;
    }
    return @lineage;
}

=head2 $h->lineage_tag_names()

Returns the list of the tag names of $h's ancestors, starting
with its parent, and that parent's parent, and so on, up to the
root.  If $h is root, this returns an empty list.
Example output: C<('em', 'td', 'tr', 'table', 'body', 'html')>

=cut

sub lineage_tag_names {
    my $here = my $start = shift;
    my @lineage_names;
    while ( defined( $here = $here->{'_parent'} ) and ref($here) ) {
        push @lineage_names, $here->{'_tag'};
    }
    return @lineage_names;
}

=head2 $h->descendants()

In list context, returns the list of all $h's descendant elements,
listed in pre-order (i.e., an element appears before its
content-elements).  Text segments DO NOT appear in the list.
In scalar context, returns a count of all such elements.

=head2 $h->descendents()

This is just an alias to the C<descendants> method.

=cut

sub descendents { shift->descendants(@_) }

sub descendants {
    my $start = shift;
    if (wantarray) {
        my @descendants;
        $start->traverse(
            [    # pre-order sub only
                sub {
                    push( @descendants, $_[0] );
                    return 1;
                },
                undef    # no post
            ],
            1,           # ignore text
        );
        shift @descendants;    # so $self doesn't appear in the list
        return @descendants;
    }
    else {                     # just returns a scalar
        my $descendants = -1;    # to offset $self being counted
        $start->traverse(
            [                    # pre-order sub only
                sub {
                    ++$descendants;
                    return 1;
                },
                undef            # no post
            ],
            1,                   # ignore text
        );
        return $descendants;
    }
}

=head2 $h->find_by_tag_name('tag', ...)

In list context, returns a list of elements at or under $h that have
any of the specified tag names.  In scalar context, returns the first
(in pre-order traversal of the tree) such element found, or undef if
none.

=head2 $h->find('tag', ...)

This is just an alias to C<find_by_tag_name>.  (There was once
going to be a whole find_* family of methods, but then look_down
filled that niche, so there turned out not to be much reason for the
verboseness of the name "find_by_tag_name".)

=cut

sub find { shift->find_by_tag_name(@_) }

# yup, a handy alias

sub find_by_tag_name {
    my (@pile) = shift(@_);    # start out the to-do stack for the traverser
    Carp::croak "find_by_tag_name can be called only as an object method"
        unless ref $pile[0];
    return () unless @_;
    my (@tags) = $pile[0]->_fold_case(@_);
    my ( @matching, $this, $this_tag );
    while (@pile) {
        $this_tag = ( $this = shift @pile )->{'_tag'};
        foreach my $t (@tags) {
            if ( $t eq $this_tag ) {
                if (wantarray) {
                    push @matching, $this;
                    last;
                }
                else {
                    return $this;
                }
            }
        }
        unshift @pile, grep ref($_), @{ $this->{'_content'} || next };
    }
    return @matching if wantarray;
    return;
}

=head2 $h->find_by_attribute('attribute', 'value')

In a list context, returns a list of elements at or under $h that have
the specified attribute, and have the given value for that attribute.
In a scalar context, returns the first (in pre-order traversal of the
tree) such element found, or undef if none.

This method is B<deprecated> in favor of the more expressive
C<look_down> method, which new code should use instead.

=cut

sub find_by_attribute {

    # We could limit this to non-internal attributes, but hey.
    my ( $self, $attribute, $value ) = @_;
    Carp::croak "Attribute must be a defined value!"
        unless defined $attribute;
    $attribute = $self->_fold_case($attribute);

    my @matching;
    my $wantarray = wantarray;
    my $quit;
    $self->traverse(
        [    # pre-order only
            sub {
                if ( exists $_[0]{$attribute}
                    and $_[0]{$attribute} eq $value )
                {
                    push @matching, $_[0];
                    return HTML::Element::ABORT
                        unless $wantarray;    # only take the first
                }
                1;                            # keep traversing
            },
            undef                             # no post
        ],
        1,                                    # yes, ignore text nodes.
    );

    if ($wantarray) {
        return @matching;
    }
    else {
        return unless @matching;
        return $matching[0];
    }
}

#--------------------------------------------------------------------------

=head2 $h->look_down( ...criteria... )

This starts at $h and looks thru its element descendants (in
pre-order), looking for elements matching the criteria you specify.
In list context, returns all elements that match all the given
criteria; in scalar context, returns the first such element (or undef,
if nothing matched).

There are three kinds of criteria you can specify:

=over

=item (attr_name, attr_value)

This means you're looking for an element with that value for that
attribute.  Example: C<"alt", "pix!">.  Consider that you can search
on internal attribute values too: C<"_tag", "p">.

=item (attr_name, qr/.../)

This means you're looking for an element whose value for that
attribute matches the specified Regexp object.

=item a coderef

This means you're looking for elements where coderef->(each_element)
returns true.  Example:

  my @wide_pix_images
    = $h->look_down(
                    "_tag", "img",
                    "alt", "pix!",
                    sub { $_[0]->attr('width') > 350 }
                   );

=back

Note that C<(attr_name, attr_value)> and C<(attr_name, qr/.../)>
criteria are almost always faster than coderef
criteria, so should presumably be put before them in your list of
criteria.  That is, in the example above, the sub ref is called only
for elements that have already passed the criteria of having a "_tag"
attribute with value "img", and an "alt" attribute with value "pix!".
If the coderef were first, it would be called on every element, and
I<then> what elements pass that criterion (i.e., elements for which
the coderef returned true) would be checked for their "_tag" and "alt"
attributes.

Note that comparison of string attribute-values against the string
value in C<(attr_name, attr_value)> is case-INsensitive!  A criterion
of C<('align', 'right')> I<will> match an element whose "align" value
is "RIGHT", or "right" or "rIGhT", etc.

Note also that C<look_down> considers "" (empty-string) and undef to
be different things, in attribute values.  So this:

  $h->look_down("alt", "")

will find elements I<with> an "alt" attribute, but where the value for
the "alt" attribute is "".  But this:

  $h->look_down("alt", undef)

is the same as:

  $h->look_down(sub { !defined($_[0]->attr('alt')) } )

That is, it finds elements that do not have an "alt" attribute at all
(or that do have an "alt" attribute, but with a value of undef --
which is not normally possible).

Note that when you give several criteria, this is taken to mean you're
looking for elements that match I<all> your criterion, not just I<any>
of them.  In other words, there is an implicit "and", not an "or".  So
if you wanted to express that you wanted to find elements with a
"name" attribute with the value "foo" I<or> with an "id" attribute
with the value "baz", you'd have to do it like:

  @them = $h->look_down(
    sub {
      # the lcs are to fold case
      lc($_[0]->attr('name')) eq 'foo'
      or lc($_[0]->attr('id')) eq 'baz'
    }
  );

Coderef criteria are more expressive than C<(attr_name, attr_value)>
and C<(attr_name, qr/.../)>
criteria, and all C<(attr_name, attr_value)>
and C<(attr_name, qr/.../)>
criteria could be
expressed in terms of coderefs.  However, C<(attr_name, attr_value)>
and C<(attr_name, qr/.../)>
criteria are a convenient shorthand.  (In fact, C<look_down> itself is
basically "shorthand" too, since anything you can do with C<look_down>
you could do by traversing the tree, either with the C<traverse>
method or with a routine of your own.  However, C<look_down> often
makes for very concise and clear code.)

=cut

sub look_down {
    ref( $_[0] ) or Carp::croak "look_down works only as an object method";

    my @criteria;
    for ( my $i = 1; $i < @_; ) {
        Carp::croak "Can't use undef as an attribute name"
            unless defined $_[$i];
        if ( ref $_[$i] ) {
            Carp::croak "A " . ref( $_[$i] ) . " value is not a criterion"
                unless ref $_[$i] eq 'CODE';
            push @criteria, $_[ $i++ ];
        }
        else {
            Carp::croak "param list to look_down ends in a key!" if $i == $#_;
            push @criteria, [
                scalar( $_[0]->_fold_case( $_[$i] ) ),
                defined( $_[ $i + 1 ] )
                ? ( ( ref $_[ $i + 1 ] ? $_[ $i + 1 ] : lc( $_[ $i + 1 ] ) ),
                    ref( $_[ $i + 1 ] )
                    )

                    # yes, leave that LC!
                : undef
            ];
            $i += 2;
        }
    }
    Carp::croak "No criteria?" unless @criteria;

    my (@pile) = ( $_[0] );
    my ( @matching, $val, $this );
Node:
    while ( defined( $this = shift @pile ) ) {

        # Yet another traverser implemented with merely iterative code.
        foreach my $c (@criteria) {
            if ( ref($c) eq 'CODE' ) {
                next Node unless $c->($this);    # jump to the continue block
            }
            else {                               # it's an attr-value pair
                next Node                        # jump to the continue block
                    if                           # two values are unequal if:
                        ( defined( $val = $this->{ $c->[0] } ) )
                    ? (     !defined $c->[ 1
                                ]    # actual is def, critval is undef => fail
                                     # allow regex matching
                                     # allow regex matching
                                or (
                                  $c->[2] eq 'Regexp'
                                ? $val !~ $c->[1]
                                : ( ref $val ne $c->[2]

                                        # have unequal ref values => fail
                                        or lc($val) ne lc( $c->[1] )

                                       # have unequal lc string values => fail
                                )
                                )
                        )
                    : (     defined $c->[1]
                        )    # actual is undef, critval is def => fail
            }
        }

        # We make it this far only if all the criteria passed.
        return $this unless wantarray;
        push @matching, $this;
    }
    continue {
        unshift @pile, grep ref($_), @{ $this->{'_content'} || $nillio };
    }
    return @matching if wantarray;
    return;
}

=head2 $h->look_up( ...criteria... )

This is identical to $h->look_down, except that whereas $h->look_down
basically scans over the list:

   ($h, $h->descendants)

$h->look_up instead scans over the list

   ($h, $h->lineage)

So, for example, this returns all ancestors of $h (possibly including
$h itself) that are "td" elements with an "align" attribute with a
value of "right" (or "RIGHT", etc.):

   $h->look_up("_tag", "td", "align", "right");

=cut

sub look_up {
    ref( $_[0] ) or Carp::croak "look_up works only as an object method";

    my @criteria;
    for ( my $i = 1; $i < @_; ) {
        Carp::croak "Can't use undef as an attribute name"
            unless defined $_[$i];
        if ( ref $_[$i] ) {
            Carp::croak "A " . ref( $_[$i] ) . " value is not a criterion"
                unless ref $_[$i] eq 'CODE';
            push @criteria, $_[ $i++ ];
        }
        else {
            Carp::croak "param list to look_up ends in a key!" if $i == $#_;
            push @criteria, [
                scalar( $_[0]->_fold_case( $_[$i] ) ),
                defined( $_[ $i + 1 ] )
                ? ( ( ref $_[ $i + 1 ] ? $_[ $i + 1 ] : lc( $_[ $i + 1 ] ) ),
                    ref( $_[ $i + 1 ] )
                    )
                : undef    # Yes, leave that LC!
            ];
            $i += 2;
        }
    }
    Carp::croak "No criteria?" unless @criteria;

    my ( @matching, $val );
    my $this = $_[0];
Node:
    while (1) {

       # You'll notice that the code here is almost the same as for look_down.
        foreach my $c (@criteria) {
            if ( ref($c) eq 'CODE' ) {
                next Node unless $c->($this);    # jump to the continue block
            }
            else {                               # it's an attr-value pair
                next Node                        # jump to the continue block
                    if                           # two values are unequal if:
                        ( defined( $val = $this->{ $c->[0] } ) )
                    ? (     !defined $c->[ 1
                                ]    # actual is def, critval is undef => fail
                                or (
                                  $c->[2] eq 'Regexp'
                                ? $val !~ $c->[1]
                                : ( ref $val ne $c->[2]

                                        # have unequal ref values => fail
                                        or lc($val) ne $c->[1]

                                       # have unequal lc string values => fail
                                )
                                )
                        )
                    : (     defined $c->[1]
                        )    # actual is undef, critval is def => fail
            }
        }

        # We make it this far only if all the criteria passed.
        return $this unless wantarray;
        push @matching, $this;
    }
    continue {
        last unless defined( $this = $this->{'_parent'} ) and ref $this;
    }

    return @matching if wantarray;
    return;
}

#--------------------------------------------------------------------------

=head2 $h->traverse(...options...)

Lengthy discussion of HTML::Element's unnecessary and confusing
C<traverse> method has been moved to a separate file:
L<HTML::Element::traverse>

=head2 $h->attr_get_i('attribute')

In list context, returns a list consisting of the values of the given
attribute for $self and for all its ancestors starting from $self and
working its way up.  Nodes with no such attribute are skipped.
("attr_get_i" stands for "attribute get, with inheritance".)
In scalar context, returns the first such value, or undef if none.

Consider a document consisting of:

   <html lang='i-klingon'>
     <head><title>Pati Pata</title></head>
     <body>
       <h1 lang='la'>Stuff</h1>
       <p lang='es-MX' align='center'>
         Foo bar baz <cite>Quux</cite>.
       </p>
       <p>Hooboy.</p>
     </body>
   </html>

If $h is the "cite" element, $h->attr_get_i("lang") in list context
will return the list ('es-MX', 'i-klingon').  In scalar context, it
will return the value 'es-MX'.

If you call with multiple attribute names...

=head2 $h->attr_get_i('a1', 'a2', 'a3')

...in list context, this will return a list consisting of
the values of these attributes which exist in $self and its ancestors.
In scalar context, this returns the first value (i.e., the value of
the first existing attribute from the first element that has
any of the attributes listed).  So, in the above example,

  $h->attr_get_i('lang', 'align');

will return:

   ('es-MX', 'center', 'i-klingon') # in list context
  or
   'es-MX' # in scalar context.

But note that this:

 $h->attr_get_i('align', 'lang');

will return:

   ('center', 'es-MX', 'i-klingon') # in list context
  or
   'center' # in scalar context.

=cut

sub attr_get_i {
    if ( @_ > 2 ) {
        my $self = shift;
        Carp::croak "No attribute names can be undef!"
            if grep !defined($_), @_;
        my @attributes = $self->_fold_case(@_);
        if (wantarray) {
            my @out;
            foreach my $x ( $self, $self->lineage ) {
                push @out,
                    map { exists( $x->{$_} ) ? $x->{$_} : () } @attributes;
            }
            return @out;
        }
        else {
            foreach my $x ( $self, $self->lineage ) {
                foreach my $attribute (@attributes) {
                    return $x->{$attribute}
                        if exists $x->{$attribute};    # found
                }
            }
            return;                                    # never found
        }
    }
    else {

        # Single-attribute search.  Simpler, most common, so optimize
        #  for the most common case
        Carp::croak "Attribute name must be a defined value!"
            unless defined $_[1];
        my $self      = $_[0];
        my $attribute = $self->_fold_case( $_[1] );
        if (wantarray) {                               # list context
            return
                map { exists( $_->{$attribute} ) ? $_->{$attribute} : () }
                $self, $self->lineage;
        }
        else {                                         # scalar context
            foreach my $x ( $self, $self->lineage ) {
                return $x->{$attribute} if exists $x->{$attribute};    # found
            }
            return;    # never found
        }
    }
}

=head2 $h->tagname_map()

Scans across C<$h> and all its descendants, and makes a hash (a
reference to which is returned) where each entry consists of a key
that's a tag name, and a value that's a reference to a list to all
elements that have that tag name.  I.e., this method returns:

   {
     # Across $h and all descendants...
     'a'   => [ ...list of all 'a'   elements... ],
     'em'  => [ ...list of all 'em'  elements... ],
     'img' => [ ...list of all 'img' elements... ],
   }

(There are entries in the hash for only those tagnames that occur
at/under C<$h> -- so if there's no "img" elements, there'll be no
"img" entry in the hashr(ref) returned.)

Example usage:

    my $map_r = $h->tagname_map();
    my @heading_tags = sort grep m/^h\d$/s, keys %$map_r;
    if(@heading_tags) {
      print "Heading levels used: @heading_tags\n";
    } else {
      print "No headings.\n"
    }

=cut

sub tagname_map {
    my (@pile) = $_[0];    # start out the to-do stack for the traverser
    Carp::croak "find_by_tag_name can be called only as an object method"
        unless ref $pile[0];
    my ( %map, $this_tag, $this );
    while (@pile) {
        $this_tag = ''
            unless defined( $this_tag = ( $this = shift @pile )->{'_tag'} )
        ;    # dance around the strange case of having an undef tagname.
        push @{ $map{$this_tag} ||= [] }, $this;    # add to map
        unshift @pile, grep ref($_),
            @{ $this->{'_content'} || next };       # traverse
    }
    return \%map;
}

=head2 $h->extract_links() or $h->extract_links(@wantedTypes)

Returns links found by traversing the element and all of its children
and looking for attributes (like "href" in an "a" element, or "src" in
an "img" element) whose values represent links.  The return value is a
I<reference> to an array.  Each element of the array is reference to
an array with I<four> items: the link-value, the element that has the
attribute with that link-value, and the name of that attribute, and
the tagname of that element.
(Example: C<['http://www.suck.com/',> I<$elem_obj> C<, 'href', 'a']>.)
You may or may not end up using the
element itself -- for some purposes, you may use only the link value.

You might specify that you want to extract links from just some kinds
of elements (instead of the default, which is to extract links from
I<all> the kinds of elements known to have attributes whose values
represent links).  For instance, if you want to extract links from
only "a" and "img" elements, you could code it like this:

  for (@{  $e->extract_links('a', 'img')  }) {
      my($link, $element, $attr, $tag) = @$_;
      print
        "Hey, there's a $tag that links to ",
        $link, ", in its $attr attribute, at ",
        $element->address(), ".\n";
  }

=cut

sub extract_links {
    my $start = shift;

    my %wantType;
    @wantType{ $start->_fold_case(@_) } = (1) x @_;    # if there were any
    my $wantType = scalar(@_);

    my @links;

    # TODO: add xml:link?

    my ( $link_attrs, $tag, $self, $val );    # scratch for each iteration
    $start->traverse(
        [   sub {                             # pre-order call only
                $self = $_[0];

                $tag = $self->{'_tag'};
                return 1
                    if $wantType && !$wantType{$tag};    # if we're selective

                if (defined(
                        $link_attrs = $HTML::Element::linkElements{$tag}
                    )
                    )
                {

                    # If this is a tag that has any link attributes,
                    #  look over possibly present link attributes,
                    #  saving the value, if found.
                    for ( ref($link_attrs) ? @$link_attrs : $link_attrs ) {
                        if ( defined( $val = $self->attr($_) ) ) {
                            push( @links, [ $val, $self, $_, $tag ] );
                        }
                    }
                }
                1;    # return true, so we keep recursing
            },
            undef
        ],
        1,            # ignore text nodes
    );
    \@links;
}

=head2 $h->simplify_pres

In text bits under PRE elements that are at/under $h, this routine
nativizes all newlines, and expands all tabs.

That is, if you read a file with lines delimited by C<\cm\cj>'s, the
text under PRE areas will have C<\cm\cj>'s instead of C<\n>'s. Calling
$h->nativize_pre_newlines on such a tree will turn C<\cm\cj>'s into
C<\n>'s.

Tabs are expanded to however many spaces it takes to get
to the next 8th column -- the usual way of expanding them.

=cut

sub simplify_pres {
    my $pre = 0;

    my $sub;
    my $line;
    $sub = sub {
        ++$pre if $_[0]->{'_tag'} eq 'pre';
        foreach my $it ( @{ $_[0]->{'_content'} || return } ) {
            if ( ref $it ) {
                $sub->($it);    # recurse!
            }
            elsif ($pre) {

                #$it =~ s/(?:(?:\cm\cj*)|(?:\cj))/\n/g;

                $it = join "\n", map {
                    ;
                    $line = $_;
                    while (
                        $line
                        =~ s/^([^\t]*)(\t+)/$1.(" " x ((length($2)<<3)-(length($1)&7)))/e

              # Sort of adapted from Text::Tabs -- yes, it's hardwired-in that
              # tabs are at every EIGHTH column.
                        )
                    {
                    }
                    $line;
                    }
                    split /(?:(?:\cm\cj*)|(?:\cj))/, $it, -1;
            }
        }
        --$pre if $_[0]->{'_tag'} eq 'pre';
        return;
    };
    $sub->( $_[0] );

    undef $sub;
    return;

}

=head2 $h->same_as($i)

Returns true if $h and $i are both elements representing the same tree
of elements, each with the same tag name, with the same explicit
attributes (i.e., not counting attributes whose names start with "_"),
and with the same content (textual, comments, etc.).

Sameness of descendant elements is tested, recursively, with
C<$child1-E<gt>same_as($child_2)>, and sameness of text segments is tested
with C<$segment1 eq $segment2>.

=cut

sub same_as {
    die 'same_as() takes only one argument: $h->same_as($i)' unless @_ == 2;
    my ( $h, $i ) = @_[ 0, 1 ];
    die "same_as() can be called only as an object method" unless ref $h;

    return 0 unless defined $i and ref $i;

    # An element can't be same_as anything but another element!
    # They needn't be of the same class, tho.

    return 1 if $h eq $i;

    # special (if rare) case: anything is the same as... itself!

    # assumes that no content lists in/under $h or $i contain subsequent
    #  text segments, like: ['foo', ' bar']

    # compare attributes now.
    #print "Comparing tags of $h and $i...\n";

    return 0 unless $h->{'_tag'} eq $i->{'_tag'};

    # only significant attribute whose name starts with "_"

    #print "Comparing attributes of $h and $i...\n";
    # Compare attributes, but only the real ones.
    {

        # Bear in mind that the average element has very few attributes,
        #  and that element names are rather short.
        # (Values are a different story.)

    # XXX I would think that /^[^_]/ would be faster, at least easier to read.
        my @keys_h
            = sort grep { length $_ and substr( $_, 0, 1 ) ne '_' } keys %$h;
        my @keys_i
            = sort grep { length $_ and substr( $_, 0, 1 ) ne '_' } keys %$i;

        return 0 unless @keys_h == @keys_i;

        # different number of real attributes?  they're different.
        for ( my $x = 0; $x < @keys_h; ++$x ) {
            return 0
                unless $keys_h[$x] eq $keys_i[$x] and    # same key name
                    $h->{ $keys_h[$x] } eq $i->{ $keys_h[$x] };   # same value
             # Should this test for definedness on values?
             # People shouldn't be putting undef in attribute values, I think.
        }
    }

    #print "Comparing children of $h and $i...\n";
    my $hcl = $h->{'_content'} || [];
    my $icl = $i->{'_content'} || [];

    return 0 unless @$hcl == @$icl;

    # different numbers of children?  they're different.

    if (@$hcl) {

        # compare each of the children:
        for ( my $x = 0; $x < @$hcl; ++$x ) {
            if ( ref $hcl->[$x] ) {
                return 0 unless ref( $icl->[$x] );

                # an element can't be the same as a text segment
                # Both elements:
                return 0 unless $hcl->[$x]->same_as( $icl->[$x] );  # RECURSE!
            }
            else {
                return 0 if ref( $icl->[$x] );

                # a text segment can't be the same as an element
                # Both text segments:
                return 0 unless $hcl->[$x] eq $icl->[$x];
            }
        }
    }

    return 1;    # passed all the tests!
}

=head2 $h = HTML::Element->new_from_lol(ARRAYREF)

Resursively constructs a tree of nodes, based on the (non-cyclic)
data structure represented by ARRAYREF, where that is a reference
to an array of arrays (of arrays (of arrays (etc.))).

In each arrayref in that structure, different kinds of values are
treated as follows:

=over

=item * Arrayrefs

Arrayrefs are considered to
designate a sub-tree representing children for the node constructed
from the current arrayref.

=item * Hashrefs

Hashrefs are considered to contain
attribute-value pairs to add to the element to be constructed from
the current arrayref

=item * Text segments

Text segments at the start of any arrayref
will be considered to specify the name of the element to be
constructed from the current araryref; all other text segments will
be considered to specify text segments as children for the current
arrayref.

=item * Elements

Existing element objects are either inserted into the treelet
constructed, or clones of them are.  That is, when the lol-tree is
being traversed and elements constructed based what's in it, if
an existing element object is found, if it has no parent, then it is
added directly to the treelet constructed; but if it has a parent,
then C<$that_node-E<gt>clone> is added to the treelet at the
appropriate place.

=back

An example will hopefully make this more obvious:

  my $h = HTML::Element->new_from_lol(
    ['html',
      ['head',
        [ 'title', 'I like stuff!' ],
      ],
      ['body',
        {'lang', 'en-JP', _implicit => 1},
        'stuff',
        ['p', 'um, p < 4!', {'class' => 'par123'}],
        ['div', {foo => 'bar'}, '123'],
      ]
    ]
  );
  $h->dump;

Will print this:

  <html> @0
    <head> @0.0
      <title> @0.0.0
        "I like stuff!"
    <body lang="en-JP"> @0.1 (IMPLICIT)
      "stuff"
      <p class="par123"> @0.1.1
        "um, p < 4!"
      <div foo="bar"> @0.1.2
        "123"

And printing $h->as_HTML will give something like:

  <html><head><title>I like stuff!</title></head>
  <body lang="en-JP">stuff<p class="par123">um, p &lt; 4!
  <div foo="bar">123</div></body></html>

You can even do fancy things with C<map>:

  $body->push_content(
    # push_content implicitly calls new_from_lol on arrayrefs...
    ['br'],
    ['blockquote',
      ['h2', 'Pictures!'],
      map ['p', $_],
      $body2->look_down("_tag", "img"),
        # images, to be copied from that other tree.
    ],
    # and more stuff:
    ['ul',
      map ['li', ['a', {'href'=>"$_.png"}, $_ ] ],
      qw(Peaches Apples Pears Mangos)
    ],
  );

=head2 @elements = HTML::Element->new_from_lol(ARRAYREFS)

Constructs I<several> elements, by calling
new_from_lol for every arrayref in the ARRAYREFS list.

  @elements = HTML::Element->new_from_lol(
    ['hr'],
    ['p', 'And there, on the door, was a hook!'],
  );
   # constructs two elements.

=cut

sub new_from_lol {
    my $class = shift;
    $class = ref($class) || $class;

  # calling as an object method is just the same as ref($h)->new_from_lol(...)
    my $lol = $_[1];

    my @ancestor_lols;

    # So we can make sure there's no cyclicities in this lol.
    # That would be perverse, but one never knows.
    my ( $sub, $k, $v, $node );    # last three are scratch values
    $sub = sub {

        #print "Building for $_[0]\n";
        my $lol = $_[0];
        return unless @$lol;
        my ( @attributes, @children );
        Carp::croak "Cyclicity detected in source LOL tree, around $lol?!?"
            if grep( $_ eq $lol, @ancestor_lols );
        push @ancestor_lols, $lol;

        my $tag_name = 'null';

        # Recursion in in here:
        for ( my $i = 0; $i < @$lol; ++$i ) {    # Iterate over children
            if ( ref( $lol->[$i] ) eq 'ARRAY' )
            {    # subtree: most common thing in loltree
                push @children, $sub->( $lol->[$i] );
            }
            elsif ( !ref( $lol->[$i] ) ) {
                if ( $i == 0 ) {    # name
                    $tag_name = $lol->[$i];
                    Carp::croak "\"$tag_name\" isn't a good tag name!"
                        if $tag_name =~ m/[<>\/\x00-\x20]/
                    ;               # minimal sanity, certainly!
                }
                else {              # text segment child
                    push @children, $lol->[$i];
                }
            }
            elsif ( ref( $lol->[$i] ) eq 'HASH' ) {    # attribute hashref
                keys %{ $lol->[$i] };   # reset the each-counter, just in case
                while ( ( $k, $v ) = each %{ $lol->[$i] } ) {
                    push @attributes, $class->_fold_case($k), $v
                        if defined $v
                            and $k ne '_name'
                            and $k ne '_content'
                            and $k ne '_parent';

                    # enforce /some/ sanity!
                }
            }
            elsif ( UNIVERSAL::isa( $lol->[$i], __PACKAGE__ ) ) {
                if ( $lol->[$i]->{'_parent'} ) {    # if claimed
                        #print "About to clone ", $lol->[$i], "\n";
                    push @children, $lol->[$i]->clone();
                }
                else {
                    push @children, $lol->[$i];    # if unclaimed...
                         #print "Claiming ", $lol->[$i], "\n";
                    $lol->[$i]->{'_parent'} = 1;    # claim it NOW
                      # This WILL be replaced by the correct value once we actually
                      #  construct the parent, just after the end of this loop...
                }
            }
            else {
                Carp::croak "new_from_lol doesn't handle references of type "
                    . ref( $lol->[$i] );
            }
        }

        pop @ancestor_lols;
        $node = $class->new($tag_name);

        #print "Children: @children\n";

        if ( $class eq __PACKAGE__ ) {    # Special-case it, for speed:
            %$node = ( %$node, @attributes ) if @attributes;

            #print join(' ', $node, ' ' , map("<$_>", %$node), "\n");
            if (@children) {
                $node->{'_content'} = \@children;
                foreach my $c (@children) {
                    $c->{'_parent'} = $node
                        if ref $c;
                }
            }
        }
        else {                            # Do it the clean way...
                                          #print "Done neatly\n";
            while (@attributes) { $node->attr( splice @attributes, 0, 2 ) }
            $node->push_content( map { $_->{'_parent'} = $node if ref $_; $_ }
                    @children )
                if @children;
        }

        return $node;
    };

    # End of sub definition.

    if (wantarray) {
        my (@nodes) = map { ; ( ref($_) eq 'ARRAY' ) ? $sub->($_) : $_ } @_;

        # Let text bits pass thru, I guess.  This makes this act more like
        #  unshift_content et al.  Undocumented.
        undef $sub;

        # so it won't be in its own frame, so its refcount can hit 0
        return @nodes;
    }
    else {
        Carp::croak "new_from_lol in scalar context needs exactly one lol"
            unless @_ == 1;
        return $_[0] unless ref( $_[0] ) eq 'ARRAY';

        # used to be a fatal error.  still undocumented tho.
        $node = $sub->( $_[0] );
        undef $sub;

        # so it won't be in its own frame, so its refcount can hit 0
        return $node;
    }
}

=head2 $h->objectify_text()

This turns any text nodes under $h from mere text segments (strings)
into real objects, pseudo-elements with a tag-name of "~text", and the
actual text content in an attribute called "text".  (For a discussion
of pseudo-elements, see the "tag" method, far above.)  This method is
provided because, for some purposes, it is convenient or necessary to
be able, for a given text node, to ask what element is its parent; and
clearly this is not possible if a node is just a text string.

Note that these "~text" objects are not recognized as text nodes by
methods like as_text.  Presumably you will want to call
$h->objectify_text, perform whatever task that you needed that for,
and then call $h->deobjectify_text before calling anything like
$h->as_text.

=head2 $h->deobjectify_text()

This undoes the effect of $h->objectify_text.  That is, it takes any
"~text" pseudo-elements in the tree at/under $h, and deletes each one,
replacing each with the content of its "text" attribute. 

Note that if $h itself is a "~text" pseudo-element, it will be
destroyed -- a condition you may need to treat specially in your
calling code (since it means you can't very well do anything with $h
after that).  So that you can detect that condition, if $h is itself a
"~text" pseudo-element, then this method returns the value of the
"text" attribute, which should be a defined value; in all other cases,
it returns undef.

(This method assumes that no "~text" pseudo-element has any children.)

=cut

sub objectify_text {
    my (@stack) = ( $_[0] );

    my ($this);
    while (@stack) {
        foreach my $c ( @{ ( $this = shift @stack )->{'_content'} } ) {
            if ( ref($c) ) {
                unshift @stack, $c;    # visit it later.
            }
            else {
                $c = $this->element_class->new(
                    '~text',
                    'text'    => $c,
                    '_parent' => $this
                );
            }
        }
    }
    return;
}

sub deobjectify_text {
    my (@stack) = ( $_[0] );
    my ($old_node);

    if ( $_[0]{'_tag'} eq '~text' ) {    # special case
            # Puts the $old_node variable to a different purpose
        if ( $_[0]{'_parent'} ) {
            $_[0]->replace_with( $old_node = delete $_[0]{'text'} )->delete;
        }
        else {    # well, that's that, then!
            $old_node = delete $_[0]{'text'};
        }

        if ( ref( $_[0] ) eq __PACKAGE__ ) {    # common case
            %{ $_[0] } = ();                    # poof!
        }
        else {

            # play nice:
            delete $_[0]{'_parent'};
            $_[0]->delete;
        }
        return '' unless defined $old_node;     # sanity!
        return $old_node;
    }

    while (@stack) {
        foreach my $c ( @{ ( shift @stack )->{'_content'} } ) {
            if ( ref($c) ) {
                if ( $c->{'_tag'} eq '~text' ) {
                    $c = ( $old_node = $c )->{'text'};
                    if ( ref($old_node) eq __PACKAGE__ ) {    # common case
                        %$old_node = ();                      # poof!
                    }
                    else {

                        # play nice:
                        delete $old_node->{'_parent'};
                        $old_node->delete;
                    }
                }
                else {
                    unshift @stack, $c;    # visit it later.
                }
            }
        }
    }

    return;
}

=head2 $h->number_lists()

For every UL, OL, DIR, and MENU element at/under $h, this sets a
"_bullet" attribute for every child LI element.  For LI children of an
OL, the "_bullet" attribute's value will be something like "4.", "d.",
"D.", "IV.", or "iv.", depending on the OL element's "type" attribute.
LI children of a UL, DIR, or MENU get their "_bullet" attribute set
to "*".
There should be no other LIs (i.e., except as children of OL, UL, DIR,
or MENU elements), and if there are, they are unaffected.

=cut

{

    # The next three subs are basically copied from Number::Latin,
    # based on a one-liner by Abigail.  Yes, I could simply require that
    # module, and a Roman numeral module too, but really, HTML-Tree already
    # has enough dependecies as it is; and anyhow, I don't need the functions
    # that do latin2int or roman2int.
    no integer;

    sub _int2latin {
        return unless defined $_[0];
        return '0' if $_[0] < 1 and $_[0] > -1;
        return '-' . _i2l( abs int $_[0] )
            if $_[0] <= -1;    # tolerate negatives
        return _i2l( int $_[0] );
    }

    sub _int2LATIN {

        # just the above plus uc
        return unless defined $_[0];
        return '0' if $_[0] < 1 and $_[0] > -1;
        return '-' . uc( _i2l( abs int $_[0] ) )
            if $_[0] <= -1;    # tolerate negs
        return uc( _i2l( int $_[0] ) );
    }

    my @alpha = ( 'a' .. 'z' );

    sub _i2l {                 # the real work
        my $int = $_[0] || return "";
        _i2l( int( ( $int - 1 ) / 26 ) )
            . $alpha[ $int % 26 - 1 ];    # yes, recursive
            # Yes, 26 => is (26 % 26 - 1), which is -1 => Z!
    }
}

{

    # And now, some much less impressive Roman numerals code:

    my (@i) = ( '', qw(I II III IV V VI VII VIII IX) );
    my (@x) = ( '', qw(X XX XXX XL L LX LXX LXXX XC) );
    my (@c) = ( '', qw(C CC CCC CD D DC DCC DCCC CM) );
    my (@m) = ( '', qw(M MM MMM) );

    sub _int2ROMAN {
        my ( $i, $pref );
        return '0'
            if 0 == ( $i = int( $_[0] || 0 ) );    # zero is a special case
        return $i + 0 if $i <= -4000 or $i >= 4000;

       # Because over 3999 would require non-ASCII chars, like D-with-)-inside
        if ( $i < 0 ) {    # grumble grumble tolerate negatives grumble
            $pref = '-';
            $i    = abs($i);
        }
        else {
            $pref = '';    # normal case
        }

        my ( $x, $c, $m ) = ( 0, 0, 0 );
        if ( $i >= 10 ) {
            $x = $i / 10;
            $i %= 10;
            if ( $x >= 10 ) {
                $c = $x / 10;
                $x %= 10;
                if ( $c >= 10 ) { $m = $c / 10; $c %= 10; }
            }
        }

        #print "m$m c$c x$x i$i\n";

        return join( '', $pref, $m[$m], $c[$c], $x[$x], $i[$i] );
    }

    sub _int2roman { lc( _int2ROMAN( $_[0] ) ) }
}

sub _int2int { $_[0] }    # dummy

%list_type_to_sub = (
    'I' => \&_int2ROMAN,
    'i' => \&_int2roman,
    'A' => \&_int2LATIN,
    'a' => \&_int2latin,
    '1' => \&_int2int,
);

sub number_lists {
    my (@stack) = ( $_[0] );
    my ( $this, $tag, $counter, $numberer );    # scratch
    while (@stack) {    # yup, pre-order-traverser idiom
        if ( ( $tag = ( $this = shift @stack )->{'_tag'} ) eq 'ol' ) {

            # Prep some things:
            $counter
                = ( ( $this->{'start'} || '' ) =~ m<^\s*(\d{1,7})\s*$>s )
                ? $1
                : 1;
            $numberer = $list_type_to_sub{ $this->{'type'} || '' }
                || $list_type_to_sub{'1'};

            # Immeditately iterate over all children
            foreach my $c ( @{ $this->{'_content'} || next } ) {
                next unless ref $c;
                unshift @stack, $c;
                if ( $c->{'_tag'} eq 'li' ) {
                    $counter = $1
                        if (
                        ( $c->{'value'} || '' ) =~ m<^\s*(\d{1,7})\s*$>s );
                    $c->{'_bullet'} = $numberer->($counter) . '.';
                    ++$counter;
                }
            }

        }
        elsif ( $tag eq 'ul' or $tag eq 'dir' or $tag eq 'menu' ) {

            # Immeditately iterate over all children
            foreach my $c ( @{ $this->{'_content'} || next } ) {
                next unless ref $c;
                unshift @stack, $c;
                $c->{'_bullet'} = '*' if $c->{'_tag'} eq 'li';
            }

        }
        else {
            foreach my $c ( @{ $this->{'_content'} || next } ) {
                unshift @stack, $c if ref $c;
            }
        }
    }
    return;
}

=head2 $h->has_insane_linkage

This method is for testing whether this element or the elements
under it have linkage attributes (_parent and _content) whose values
are deeply aberrant: if there are undefs in a content list; if an
element appears in the content lists of more than one element;
if the _parent attribute of an element doesn't match its actual
parent; or if an element appears as its own descendant (i.e.,
if there is a cyclicity in the tree).

This returns empty list (or false, in scalar context) if the subtree's
linkage methods are sane; otherwise it returns two items (or true, in
scalar context): the element where the error occurred, and a string
describing the error.

This method is provided is mainly for debugging and troubleshooting --
it should be I<quite impossible> for any document constructed via
HTML::TreeBuilder to parse into a non-sane tree (since it's not
the content of the tree per se that's in question, but whether
the tree in memory was properly constructed); and it I<should> be
impossible for you to produce an insane tree just thru reasonable
use of normal documented structure-modifying methods.  But if you're
constructing your own trees, and your program is going into infinite
loops as during calls to traverse() or any of the secondary
structural methods, as part of debugging, consider calling is_insane
on the tree.

=cut

sub has_insane_linkage {
    my @pile = ( $_[0] );
    my ( $c, $i, $p, $this );    # scratch

    # Another iterative traverser; this time much simpler because
    #  only in pre-order:
    my %parent_of = ( $_[0], 'TOP-OF-SCAN' );
    while (@pile) {
        $this = shift @pile;
        $c = $this->{'_content'} || next;
        return ( $this, "_content attribute is true but nonref." )
            unless ref($c) eq 'ARRAY';
        next unless @$c;
        for ( $i = 0; $i < @$c; ++$i ) {
            return ( $this, "Child $i is undef" )
                unless defined $c->[$i];
            if ( ref( $c->[$i] ) ) {
                return ( $c->[$i], "appears in its own content list" )
                    if $c->[$i] eq $this;
                return ( $c->[$i],
                    "appears twice in the tree: once under $this, once under $parent_of{$c->[$i]}"
                ) if exists $parent_of{ $c->[$i] };
                $parent_of{ $c->[$i] } = '' . $this;

                # might as well just use the stringification of it.

                return ( $c->[$i],
                    "_parent attribute is wrong (not defined)" )
                    unless defined( $p = $c->[$i]{'_parent'} );
                return ( $c->[$i], "_parent attribute is wrong (nonref)" )
                    unless ref($p);
                return ( $c->[$i],
                    "_parent attribute is wrong (is $p; should be $this)" )
                    unless $p eq $this;
            }
        }
        unshift @pile, grep ref($_), @$c;

        # queue up more things on the pile stack
    }
    return;    #okay
}

sub _asserts_fail {    # to be run on trusted documents only
    my (@pile) = ( $_[0] );
    my ( @errors, $this, $id, $assert, $parent, $rv );
    while (@pile) {
        $this = shift @pile;
        if ( defined( $assert = $this->{'assert'} ) ) {
            $id = ( $this->{'id'} ||= $this->address )
                ;      # don't use '0' as an ID, okay?
            unless ( ref($assert) ) {

                package main;
## no critic
                $assert = $this->{'assert'} = (
                    $assert =~ m/\bsub\b/
                    ? eval($assert)
                    : eval("sub {  $assert\n}")
                );
## use critic
                if ($@) {
                    push @errors,
                        [ $this, "assertion at $id broke in eval: $@" ];
                    $assert = $this->{'assert'} = sub { };
                }
            }
            $parent = $this->{'_parent'};
            $rv     = undef;
            eval {
                $rv = $assert->(
                    $this, $this->{'_tag'}, $this->{'_id'},    # 0,1,2
                    $parent
                    ? ( $parent, $parent->{'_tag'}, $parent->{'id'} )
                    : ()                                       # 3,4,5
                );
            };
            if ($@) {
                push @errors, [ $this, "assertion at $id died: $@" ];
            }
            elsif ( !$rv ) {
                push @errors, [ $this, "assertion at $id failed" ];
            }

            # else OK
        }
        push @pile, grep ref($_), @{ $this->{'_content'} || next };
    }
    return @errors;
}

## _valid_name
#  validate XML style attribute names
#  http://www.w3.org/TR/2006/REC-xml11-20060816/#NT-Name

sub _valid_name {
    my $self = shift;
    my $attr = shift
        or Carp::croak("sub valid_name requires an attribute name");

    return (0) unless ( $attr =~ /^$START_CHAR$NAME_CHAR+$/ );

    return (1);
}

=head2 $h->element_class

This method returns the class which will be used for new elements.  It
defaults to HTML::Element, but can be overridden by subclassing or esoteric
means best left to those will will read the source and then not complain when
those esoteric means change.  (Just subclass.)

=cut

sub element_class {
    $_[0]->{_element_class} || __PACKAGE__;
}

1;

=head1 BUGS

* If you want to free the memory associated with a tree built of
HTML::Element nodes, then you will have to delete it explicitly.
See the $h->delete method, above.

* There's almost nothing to stop you from making a "tree" with
cyclicities (loops) in it, which could, for example, make the
traverse method go into an infinite loop.  So don't make
cyclicities!  (If all you're doing is parsing HTML files,
and looking at the resulting trees, this will never be a problem
for you.)

* There's no way to represent comments or processing directives
in a tree with HTML::Elements.  Not yet, at least.

* There's (currently) nothing to stop you from using an undefined
value as a text segment.  If you're running under C<perl -w>, however,
this may make HTML::Element's code produce a slew of warnings.

=head1 NOTES ON SUBCLASSING

You are welcome to derive subclasses from HTML::Element, but you
should be aware that the code in HTML::Element makes certain
assumptions about elements (and I'm using "element" to mean ONLY an
object of class HTML::Element, or of a subclass of HTML::Element):

* The value of an element's _parent attribute must either be undef or
otherwise false, or must be an element.

* The value of an element's _content attribute must either be undef or
otherwise false, or a reference to an (unblessed) array.  The array
may be empty; but if it has items, they must ALL be either mere
strings (text segments), or elements.

* The value of an element's _tag attribute should, at least, be a 
string of printable characters.

Moreover, bear these rules in mind:

* Do not break encapsulation on objects.  That is, access their
contents only thru $obj->attr or more specific methods.

* You should think twice before completely overriding any of the
methods that HTML::Element provides.  (Overriding with a method that
calls the superclass method is not so bad, though.)

=head1 SEE ALSO

L<HTML::Tree>; L<HTML::TreeBuilder>; L<HTML::AsSubs>; L<HTML::Tagset>; 
and, for the morbidly curious, L<HTML::Element::traverse>.

=head1 COPYRIGHT

Copyright 1995-1998 Gisle Aas, 1999-2004 Sean M. Burke, 2005 Andy Lester,
2006 Pete Krawczyk, 2010 Jeff Fearn.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=head1 AUTHOR

Current Author:
	Jeff Fearn C<< <jfearn@cpan.org> >>.

Original HTML-Tree author:
	Gisle Aas.

Former Authors:
	Sean M. Burke.
	Andy Lester.
	Pete Krawczyk C<< <petek@cpan.org> >>.

Thanks to Mark-Jason Dominus for a POD suggestion.

=cut

1;
