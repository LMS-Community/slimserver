package HTML::TreeBuilder;

# ABSTRACT: Parser that builds a HTML syntax tree

use warnings;
use strict;
use integer;    # vroom vroom!
use Carp ();

our $VERSION = '5.07'; # VERSION from OurPkgVersion

#---------------------------------------------------------------------------
# Make a 'DEBUG' constant...

our $DEBUG; # Must be set BEFORE loading this file
BEGIN {

    # We used to have things like
    #  print $indent, "lalala" if $Debug;
    # But there were an awful lot of having to evaluate $Debug's value.
    # If we make that depend on a constant, like so:
    #   sub DEBUG () { 1 } # or whatever value.
    #   ...
    #   print $indent, "lalala" if DEBUG;
    # Which at compile-time (thru the miracle of constant folding) turns into:
    #   print $indent, "lalala";
    # or, if DEBUG is a constant with a true value, then that print statement
    # is simply optimized away, and doesn't appear in the target code at all.
    # If you don't believe me, run:
    #    perl -MO=Deparse,-uHTML::TreeBuilder -e 'BEGIN { \
    #      $HTML::TreeBuilder::DEBUG = 4}  use HTML::TreeBuilder'
    # and see for yourself (substituting whatever value you want for $DEBUG
    # there).
## no critic
    if ( defined &DEBUG ) {

        # Already been defined!  Do nothing.
    }
    elsif ( $] < 5.00404 ) {

        # Grudgingly accomodate ancient (pre-constant) versions.
        eval 'sub DEBUG { $Debug } ';
    }
    elsif ( !$DEBUG ) {
        eval 'sub DEBUG () {0}';    # Make it a constant.
    }
    elsif ( $DEBUG =~ m<^\d+$>s ) {
        eval 'sub DEBUG () { ' . $DEBUG . ' }';    # Make THAT a constant.
    }
    else {                                         # WTF?
        warn "Non-numeric value \"$DEBUG\" in \$HTML::Element::DEBUG";
        eval 'sub DEBUG () { $DEBUG }';            # I guess.
    }
## use critic
}

#---------------------------------------------------------------------------

use HTML::Entities ();
use HTML::Tagset 3.02 ();

use HTML::Element ();
use HTML::Parser 3.46 ();
our @ISA = qw(HTML::Element HTML::Parser);

# This looks schizoid, I know.
# It's not that we ARE an element AND a parser.
# We ARE an element, but one that knows how to handle signals
#  (method calls) from Parser in order to elaborate its subtree.

# Legacy aliases:
*HTML::TreeBuilder::isKnown             = \%HTML::Tagset::isKnown;
*HTML::TreeBuilder::canTighten          = \%HTML::Tagset::canTighten;
*HTML::TreeBuilder::isHeadElement       = \%HTML::Tagset::isHeadElement;
*HTML::TreeBuilder::isBodyElement       = \%HTML::Tagset::isBodyElement;
*HTML::TreeBuilder::isPhraseMarkup      = \%HTML::Tagset::isPhraseMarkup;
*HTML::TreeBuilder::isHeadOrBodyElement = \%HTML::Tagset::isHeadOrBodyElement;
*HTML::TreeBuilder::isList              = \%HTML::Tagset::isList;
*HTML::TreeBuilder::isTableElement      = \%HTML::Tagset::isTableElement;
*HTML::TreeBuilder::isFormElement       = \%HTML::Tagset::isFormElement;
*HTML::TreeBuilder::p_closure_barriers  = \@HTML::Tagset::p_closure_barriers;

#==========================================================================
# Two little shortcut constructors:

sub new_from_file {    # or from a FH
    my $class = shift;
    Carp::croak("new_from_file takes only one argument")
        unless @_ == 1;
    Carp::croak("new_from_file is a class method only")
        if ref $class;
    my $new = $class->new();
    defined $new->parse_file( $_[0] )
        or Carp::croak("unable to parse file: $!");
    return $new;
}

sub new_from_content {    # from any number of scalars
    my $class = shift;
    Carp::croak("new_from_content is a class method only")
        if ref $class;
    my $new = $class->new();
    foreach my $whunk (@_) {
        if ( ref($whunk) eq 'SCALAR' ) {
            $new->parse($$whunk);
        }
        else {
            $new->parse($whunk);
        }
        last if $new->{'_stunted'};    # might as well check that.
    }
    $new->eof();
    return $new;
}

sub new_from_url {                     # should accept anything that LWP does.
    undef our $lwp_response;
    my $class = shift;
    Carp::croak("new_from_url takes only one argument")
        unless @_ == 1;
    Carp::croak("new_from_url is a class method only")
        if ref $class;
    my $url = shift;
    my $new = $class->new();

    require LWP::UserAgent;
    # RECOMMEND PREREQ: LWP::UserAgent 5.815
    LWP::UserAgent->VERSION( 5.815 ); # HTTP::Headers content_is_html method
    $lwp_response = LWP::UserAgent->new->get( $url );

    Carp::croak("GET failed on $url: " . $lwp_response->status_line)
          unless $lwp_response->is_success;
    Carp::croak("$url returned " . $lwp_response->content_type . " not HTML")
          unless $lwp_response->content_is_html;

    $new->parse( $lwp_response->decoded_content );
    $new->eof;
    undef $lwp_response;        # Processed successfully
    return $new;
}

# TODO: document more fully?
sub parse_content {    # from any number of scalars
    my $tree = shift;
    my $retval;
    foreach my $whunk (@_) {
        if ( ref($whunk) eq 'SCALAR' ) {
            $retval = $tree->parse($$whunk);
        }
        else {
            $retval = $tree->parse($whunk);
        }
        last if $tree->{'_stunted'};    # might as well check that.
    }
    $tree->eof();
    return $retval;
}

#---------------------------------------------------------------------------

sub new {                               # constructor!
    my $class = shift;
    $class = ref($class) || $class;

    # Initialize HTML::Element part
    my $self = $class->element_class->new('html');

    {

        # A hack for certain strange versions of Parser:
        my $other_self = HTML::Parser->new();
        %$self = ( %$self, %$other_self );    # copy fields
           # Yes, multiple inheritance is messy.  Kids, don't try this at home.
        bless $other_self, "HTML::TreeBuilder::_hideyhole";

        # whack it out of the HTML::Parser class, to avoid the destructor
    }

    # The root of the tree is special, as it has these funny attributes,
    # and gets reblessed into this class.

    # Initialize parser settings
    $self->{'_implicit_tags'}       = 1;
    $self->{'_implicit_body_p_tag'} = 0;

    # If true, trying to insert text, or any of %isPhraseMarkup right
    #  under 'body' will implicate a 'p'.  If false, will just go there.

    $self->{'_tighten'} = 1;

    # whether ignorable WS in this tree should be deleted

    $self->{'_implicit'} = 1; # to delete, once we find a real open-"html" tag

    $self->{'_ignore_unknown'}      = 1;
    $self->{'_ignore_text'}         = 0;
    $self->{'_warn'}                = 0;
    $self->{'_no_space_compacting'} = 0;
    $self->{'_store_comments'}      = 0;
    $self->{'_store_declarations'}  = 1;
    $self->{'_store_pis'}           = 0;
    $self->{'_p_strict'}            = 0;
    $self->{'_no_expand_entities'}  = 0;

    # Parse attributes passed in as arguments
    if (@_) {
        my %attr = @_;
        for ( keys %attr ) {
            $self->{"_$_"} = $attr{$_};
        }
    }

    $HTML::Element::encoded_content = $self->{'_no_expand_entities'};

    # rebless to our class
    bless $self, $class;

    $self->{'_element_count'} = 1;

    # undocumented, informal, and maybe not exactly correct

    $self->{'_head'} = $self->insert_element( 'head', 1 );
    $self->{'_pos'}  = undef;                                # pull it back up
    $self->{'_body'} = $self->insert_element( 'body', 1 );
    $self->{'_pos'} = undef;    # pull it back up again

    return $self;
}

#==========================================================================

sub _elem                       # universal accessor...
{
    my ( $self, $elem, $val ) = @_;
    my $old = $self->{$elem};
    $self->{$elem} = $val if defined $val;
    return $old;
}

# accessors....
sub implicit_tags       { shift->_elem( '_implicit_tags',       @_ ); }
sub implicit_body_p_tag { shift->_elem( '_implicit_body_p_tag', @_ ); }
sub p_strict            { shift->_elem( '_p_strict',            @_ ); }
sub no_space_compacting { shift->_elem( '_no_space_compacting', @_ ); }
sub ignore_unknown      { shift->_elem( '_ignore_unknown',      @_ ); }
sub ignore_text         { shift->_elem( '_ignore_text',         @_ ); }
sub ignore_ignorable_whitespace { shift->_elem( '_tighten',            @_ ); }
sub store_comments              { shift->_elem( '_store_comments',     @_ ); }
sub store_declarations          { shift->_elem( '_store_declarations', @_ ); }
sub store_pis                   { shift->_elem( '_store_pis',          @_ ); }
sub warn                        { shift->_elem( '_warn',               @_ ); }

sub no_expand_entities {
    shift->_elem( '_no_expand_entities', @_ );
    $HTML::Element::encoded_content = @_;
}

#==========================================================================

sub warning {
    my $self = shift;
    CORE::warn("HTML::Parse: $_[0]\n") if $self->{'_warn'};

    # should maybe say HTML::TreeBuilder instead
}

#==========================================================================

{

    # To avoid having to rebuild these lists constantly...
    my $_Closed_by_structurals = [qw(p h1 h2 h3 h4 h5 h6 pre textarea)];
    my $indent;

    sub start {
        return if $_[0]{'_stunted'};

        # Accept a signal from HTML::Parser for start-tags.
        my ( $self, $tag, $attr ) = @_;

        # Parser passes more, actually:
        #   $self->start($tag, $attr, $attrseq, $origtext)
        # But we can merrily ignore $attrseq and $origtext.

        if ( $tag eq 'x-html' ) {
            print "Ignoring open-x-html tag.\n" if DEBUG;

            # inserted by some lame code-generators.
            return;    # bypass tweaking.
        }

        $tag =~ s{/$}{}s;    # So <b/> turns into <b>.  Silently forgive.

        unless ( $tag =~ m/^[-_a-zA-Z0-9:%]+$/s ) {
            DEBUG and print "Start-tag name $tag is no good.  Skipping.\n";
            return;

            # This avoids having Element's new() throw an exception.
        }

        my $ptag = ( my $pos = $self->{'_pos'} || $self )->{'_tag'};
        my $already_inserted;

        #my($indent);
        if (DEBUG) {

       # optimization -- don't figure out indenting unless we're in debug mode
            my @lineage = $pos->lineage;
            $indent = '  ' x ( 1 + @lineage );
            print $indent, "Proposing a new \U$tag\E under ",
                join( '/', map $_->{'_tag'}, reverse( $pos, @lineage ) )
                || 'Root',
                ".\n";

            #} else {
            #  $indent = ' ';
        }

        #print $indent, "POS: $pos ($ptag)\n" if DEBUG > 2;
        # $attr = {%$attr};

        foreach my $k ( keys %$attr ) {

            # Make sure some stooge doesn't have "<span _content='pie'>".
            # That happens every few million Web pages.
            $attr->{ ' ' . $k } = delete $attr->{$k}
                if length $k and substr( $k, 0, 1 ) eq '_';

            # Looks bad, but is fine for round-tripping.
        }

        my $e = $self->element_class->new( $tag, %$attr );

        # Make a new element object.
        # (Only rarely do we end up just throwing it away later in this call.)

      # Some prep -- custom messiness for those damned tables, and strict P's.
        if ( $self->{'_implicit_tags'} ) {    # wallawallawalla!

            unless ( $HTML::TreeBuilder::isTableElement{$tag} ) {
                if ( $ptag eq 'table' ) {
                    print $indent,
                        " * Phrasal \U$tag\E right under TABLE makes implicit TR and TD\n"
                        if DEBUG > 1;
                    $self->insert_element( 'tr', 1 );
                    $pos = $self->insert_element( 'td', 1 )
                        ;                     # yes, needs updating
                }
                elsif ( $ptag eq 'tr' ) {
                    print $indent,
                        " * Phrasal \U$tag\E right under TR makes an implicit TD\n"
                        if DEBUG > 1;
                    $pos = $self->insert_element( 'td', 1 )
                        ;                     # yes, needs updating
                }
                $ptag = $pos->{'_tag'};       # yes, needs updating
            }

            # end of table-implication block.

            # Now maybe do a little dance to enforce P-strictness.
            # This seems like it should be integrated with the big
            # "ALL HOPE..." block, further below, but that doesn't
            # seem feasable.
            if (    $self->{'_p_strict'}
                and $HTML::TreeBuilder::isKnown{$tag}
                and not $HTML::Tagset::is_Possible_Strict_P_Content{$tag} )
            {
                my $here     = $pos;
                my $here_tag = $ptag;
                while (1) {
                    if ( $here_tag eq 'p' ) {
                        print $indent, " * Inserting $tag closes strict P.\n"
                            if DEBUG > 1;
                        $self->end( \q{p} );

                    # NB: same as \'q', but less confusing to emacs cperl-mode
                        last;
                    }

                    #print("Lasting from $here_tag\n"),
                    last
                        if $HTML::TreeBuilder::isKnown{$here_tag}
                            and
                            not $HTML::Tagset::is_Possible_Strict_P_Content{
                                $here_tag};

               # Don't keep looking up the tree if we see something that can't
               #  be strict-P content.

                    $here_tag
                        = ( $here = $here->{'_parent'} || last )->{'_tag'};
                }    # end while
                $ptag = ( $pos = $self->{'_pos'} || $self )
                    ->{'_tag'};    # better update!
            }

            # end of strict-p block.
        }

       # And now, get busy...
       #----------------------------------------------------------------------
        if ( !$self->{'_implicit_tags'} ) {    # bimskalabim
                                               # do nothing
            print $indent, " * _implicit_tags is off.  doing nothing\n"
                if DEBUG > 1;

       #----------------------------------------------------------------------
        }
        elsif ( $HTML::TreeBuilder::isHeadOrBodyElement{$tag} ) {
            if ( $pos->is_inside('body') ) {    # all is well
                print $indent,
                    " * ambilocal element \U$tag\E is fine under BODY.\n"
                    if DEBUG > 1;
            }
            elsif ( $pos->is_inside('head') ) {
                print $indent,
                    " * ambilocal element \U$tag\E is fine under HEAD.\n"
                    if DEBUG > 1;
            }
            else {

                # In neither head nor body!  mmmmm... put under head?

                if ( $ptag eq 'html' ) {    # expected case
                     # TODO?? : would there ever be a case where _head would be
                     #  absent from a tree that would ever be accessed at this
                     #  point?
                    die "Where'd my head go?" unless ref $self->{'_head'};
                    if ( $self->{'_head'}{'_implicit'} ) {
                        print $indent,
                            " * ambilocal element \U$tag\E makes an implicit HEAD.\n"
                            if DEBUG > 1;

                        # or rather, points us at it.
                        $self->{'_pos'}
                            = $self->{'_head'};    # to insert under...
                    }
                    else {
                        $self->warning(
                            "Ambilocal element <$tag> not under HEAD or BODY!?"
                        );

                        # Put it under HEAD by default, I guess
                        $self->{'_pos'}
                            = $self->{'_head'};    # to insert under...
                    }

                }
                else {

             # Neither under head nor body, nor right under html... pass thru?
                    $self->warning(
                        "Ambilocal element <$tag> neither under head nor body, nor right under html!?"
                    );
                }
            }

       #----------------------------------------------------------------------
        }
        elsif ( $HTML::TreeBuilder::isBodyElement{$tag} ) {

            # Ensure that we are within <body>
            if ( $ptag eq 'body' ) {

                # We're good.
            }
            elsif (
                $HTML::TreeBuilder::isBodyElement{$ptag}    # glarg
                and not $HTML::TreeBuilder::isHeadOrBodyElement{$ptag}
                )
            {

              # Special case: Save ourselves a call to is_inside further down.
              # If our $ptag is an isBodyElement element (but not an
              # isHeadOrBodyElement element), then we must be under body!
                print $indent, " * Inferring that $ptag is under BODY.\n",
                    if DEBUG > 3;

                # I think this and the test for 'body' trap everything
                # bodyworthy, except the case where the parent element is
                # under an unknown element that's a descendant of body.
            }
            elsif ( $pos->is_inside('head') ) {
                print $indent,
                    " * body-element \U$tag\E minimizes HEAD, makes implicit BODY.\n"
                    if DEBUG > 1;
                $ptag = (
                    $pos = $self->{'_pos'}
                        = $self->{'_body'}    # yes, needs updating
                        || die "Where'd my body go?"
                )->{'_tag'};                  # yes, needs updating
            }
            elsif ( !$pos->is_inside('body') ) {
                print $indent,
                    " * body-element \U$tag\E makes implicit BODY.\n"
                    if DEBUG > 1;
                $ptag = (
                    $pos = $self->{'_pos'}
                        = $self->{'_body'}    # yes, needs updating
                        || die "Where'd my body go?"
                )->{'_tag'};                  # yes, needs updating
            }

            # else we ARE under body, so okay.

            # Handle implicit endings and insert based on <tag> and position
            # ... ALL HOPE ABANDON ALL YE WHO ENTER HERE ...
            if (   $tag eq 'p'
                or $tag eq 'h1'
                or $tag eq 'h2'
                or $tag eq 'h3'
                or $tag eq 'h4'
                or $tag eq 'h5'
                or $tag eq 'h6'
                or $tag eq 'form'

                # Hm, should <form> really be here?!
                )
            {

                # Can't have <p>, <h#> or <form> inside these
                $self->end(
                    $_Closed_by_structurals,
                    @HTML::TreeBuilder::p_closure_barriers

                        # used to be just li!
                );

            }
            elsif ( $tag eq 'ol' or $tag eq 'ul' or $tag eq 'dl' ) {

                # Can't have lists inside <h#> -- in the unlikely
                #  event anyone tries to put them there!
                if (   $ptag eq 'h1'
                    or $ptag eq 'h2'
                    or $ptag eq 'h3'
                    or $ptag eq 'h4'
                    or $ptag eq 'h5'
                    or $ptag eq 'h6' )
                {
                    $self->end( \$ptag );
                }

                # TODO: Maybe keep closing up the tree until
                #  the ptag isn't any of the above?
                # But anyone that says <h1><h2><ul>...
                #  deserves what they get anyway.

            }
            elsif ( $tag eq 'li' ) {    # list item
                    # Get under a list tag, one way or another
                unless (
                    exists $HTML::TreeBuilder::isList{$ptag}
                    or $self->end( \q{*}, keys %HTML::TreeBuilder::isList ) #'
                    )
                {
                    print $indent,
                        " * inserting implicit UL for lack of containing ",
                        join( '|', keys %HTML::TreeBuilder::isList ), ".\n"
                        if DEBUG > 1;
                    $self->insert_element( 'ul', 1 );
                }

            }
            elsif ( $tag eq 'dt' or $tag eq 'dd' ) {

                # Get under a DL, one way or another
                unless ( $ptag eq 'dl' or $self->end( \q{*}, 'dl' ) ) {    #'
                    print $indent,
                        " * inserting implicit DL for lack of containing DL.\n"
                        if DEBUG > 1;
                    $self->insert_element( 'dl', 1 );
                }

            }
            elsif ( $HTML::TreeBuilder::isFormElement{$tag} ) {
                if ($self->{
                        '_ignore_formies_outside_form'}  # TODO: document this
                    and not $pos->is_inside('form')
                    )
                {
                    print $indent,
                        " * ignoring \U$tag\E because not in a FORM.\n"
                        if DEBUG > 1;
                    return;                              # bypass tweaking.
                }
                if ( $tag eq 'option' ) {

                    # return unless $ptag eq 'select';
                    $self->end( \q{option} );
                    $ptag = ( $self->{'_pos'} || $self )->{'_tag'};
                    unless ( $ptag eq 'select' or $ptag eq 'optgroup' ) {
                        print $indent,
                            " * \U$tag\E makes an implicit SELECT.\n"
                            if DEBUG > 1;
                        $pos = $self->insert_element( 'select', 1 );

                    # but not a very useful select -- has no 'name' attribute!
                    # is $pos's value used after this?
                    }
                }
            }
            elsif ( $HTML::TreeBuilder::isTableElement{$tag} ) {
                if ( !$pos->is_inside('table') ) {
                    print $indent, " * \U$tag\E makes an implicit TABLE\n"
                        if DEBUG > 1;
                    $self->insert_element( 'table', 1 );
                }

                if ( $tag eq 'td' or $tag eq 'th' ) {

                    # Get under a tr one way or another
                    unless (
                        $ptag eq 'tr'    # either under a tr
                        or $self->end( \q{*}, 'tr',
                            'table' )    #or we can get under one
                        )
                    {
                        print $indent,
                            " * \U$tag\E under \U$ptag\E makes an implicit TR\n"
                            if DEBUG > 1;
                        $self->insert_element( 'tr', 1 );

                        # presumably pos's value isn't used after this.
                    }
                }
                else {
                    $self->end( \$tag, 'table' );    #'
                }

                # Hmm, I guess this is right.  To work it out:
                #   tr closes any open tr (limited at a table)
                #   thead closes any open thead (limited at a table)
                #   tbody closes any open tbody (limited at a table)
                #   tfoot closes any open tfoot (limited at a table)
                #   colgroup closes any open colgroup (limited at a table)
                #   col can try, but will always fail, at the enclosing table,
                #     as col is empty, and therefore never open!
                # But!
                #   td closes any open td OR th (limited at a table)
                #   th closes any open th OR td (limited at a table)
                #   ...implementable as "close to a tr, or make a tr"

            }
            elsif ( $HTML::TreeBuilder::isPhraseMarkup{$tag} ) {
                if ( $ptag eq 'body' and $self->{'_implicit_body_p_tag'} ) {
                    print
                        " * Phrasal \U$tag\E right under BODY makes an implicit P\n"
                        if DEBUG > 1;
                    $pos = $self->insert_element( 'p', 1 );

                    # is $pos's value used after this?
                }
            }

            # End of implicit endings logic

       # End of "elsif ($HTML::TreeBuilder::isBodyElement{$tag}"
       #----------------------------------------------------------------------

        }
        elsif ( $HTML::TreeBuilder::isHeadElement{$tag} ) {
            if ( $pos->is_inside('body') ) {
                print $indent, " * head element \U$tag\E found inside BODY!\n"
                    if DEBUG;
                $self->warning("Header element <$tag> in body");    # [sic]
            }
            elsif ( !$pos->is_inside('head') ) {
                print $indent,
                    " * head element \U$tag\E makes an implicit HEAD.\n"
                    if DEBUG > 1;
            }
            else {
                print $indent,
                    " * head element \U$tag\E goes inside existing HEAD.\n"
                    if DEBUG > 1;
            }
            $self->{'_pos'} = $self->{'_head'} || die "Where'd my head go?";

       #----------------------------------------------------------------------
        }
        elsif ( $tag eq 'html' ) {
            if ( delete $self->{'_implicit'} ) {    # first time here
                print $indent, " * good! found the real HTML element!\n"
                    if DEBUG > 1;
            }
            else {
                print $indent, " * Found a second HTML element\n"
                    if DEBUG;
                $self->warning("Found a nested <html> element");
            }

            # in either case, migrate attributes to the real element
            for ( keys %$attr ) {
                $self->attr( $_, $attr->{$_} );
            }
            $self->{'_pos'} = undef;
            return $self;    # bypass tweaking.

       #----------------------------------------------------------------------
        }
        elsif ( $tag eq 'head' ) {
            my $head = $self->{'_head'} || die "Where'd my head go?";
            if ( delete $head->{'_implicit'} ) {    # first time here
                print $indent, " * good! found the real HEAD element!\n"
                    if DEBUG > 1;
            }
            else {                                  # been here before
                print $indent, " * Found a second HEAD element\n"
                    if DEBUG;
                $self->warning("Found a second <head> element");
            }

            # in either case, migrate attributes to the real element
            for ( keys %$attr ) {
                $head->attr( $_, $attr->{$_} );
            }
            return $self->{'_pos'} = $head;         # bypass tweaking.

       #----------------------------------------------------------------------
        }
        elsif ( $tag eq 'body' ) {
            my $body = $self->{'_body'} || die "Where'd my body go?";
            if ( delete $body->{'_implicit'} ) {    # first time here
                print $indent, " * good! found the real BODY element!\n"
                    if DEBUG > 1;
            }
            else {                                  # been here before
                print $indent, " * Found a second BODY element\n"
                    if DEBUG;
                $self->warning("Found a second <body> element");
            }

            # in either case, migrate attributes to the real element
            for ( keys %$attr ) {
                $body->attr( $_, $attr->{$_} );
            }
            return $self->{'_pos'} = $body;         # bypass tweaking.

       #----------------------------------------------------------------------
        }
        elsif ( $tag eq 'frameset' ) {
            if (!( $self->{'_frameset_seen'}++ )    # first frameset seen
                and !$self->{'_noframes_seen'}

                # otherwise it'll be under the noframes already
                and !$self->is_inside('body')
                )
            {

           # The following is a bit of a hack.  We don't use the normal
           #  insert_element because 1) we don't want it as _pos, but instead
           #  right under $self, and 2), more importantly, that we don't want
           #  this inserted at the /end/ of $self's content_list, but instead
           #  in the middle of it, specifically right before the body element.
           #
                my $c    = $self->{'_content'} || die "Contentless root?";
                my $body = $self->{'_body'}    || die "Where'd my BODY go?";
                for ( my $i = 0; $i < @$c; ++$i ) {
                    if ( $c->[$i] eq $body ) {
                        splice( @$c, $i, 0, $self->{'_pos'} = $pos = $e );
                        HTML::Element::_weaken($e->{'_parent'} = $self);
                        $already_inserted = 1;
                        print $indent,
                            " * inserting 'frameset' right before BODY.\n"
                            if DEBUG > 1;
                        last;
                    }
                }
                die "BODY not found in children of root?"
                    unless $already_inserted;
            }

        }
        elsif ( $tag eq 'frame' ) {

            # Okay, fine, pass thru.
            # Should probably enforce that these should be under a frameset.
            # But hey.  Ditto for enforcing that 'noframes' should be under
            # a 'frameset', as the DTDs say.

        }
        elsif ( $tag eq 'noframes' ) {

           # This basically assumes there'll be exactly one 'noframes' element
           #  per document.  At least, only the first one gets to have the
           #  body under it.  And if there are no noframes elements, then
           #  the body pretty much stays where it is.  Is that ever a problem?
            if ( $self->{'_noframes_seen'}++ ) {
                print $indent, " * ANOTHER noframes element?\n" if DEBUG;
            }
            else {
                if ( $pos->is_inside('body') ) {
                    print $indent, " * 'noframes' inside 'body'.  Odd!\n"
                        if DEBUG;

               # In that odd case, we /can't/ make body a child of 'noframes',
               # because it's an ancestor of the 'noframes'!
                }
                else {
                    $e->push_content( $self->{'_body'}
                            || die "Where'd my body go?" );
                    print $indent, " * Moving body to be under noframes.\n"
                        if DEBUG;
                }
            }

       #----------------------------------------------------------------------
        }
        else {

            # unknown tag
            if ( $self->{'_ignore_unknown'} ) {
                print $indent, " * Ignoring unknown tag \U$tag\E\n" if DEBUG;
                $self->warning("Skipping unknown tag $tag");
                return;
            }
            else {
                print $indent, " * Accepting unknown tag \U$tag\E\n"
                    if DEBUG;
            }
        }

       #----------------------------------------------------------------------
       # End of mumbo-jumbo

        print $indent, "(Attaching ", $e->{'_tag'}, " under ",
            ( $self->{'_pos'} || $self )->{'_tag'}, ")\n"

            # because if _pos isn't defined, it goes under self
            if DEBUG;

        # The following if-clause is to delete /some/ ignorable whitespace
        #  nodes, as we're making the tree.
        # This'd be a node we'd catch later anyway, but we might as well
        #  nip it in the bud now.
        # This doesn't catch /all/ deletable WS-nodes, so we do have to call
        #  the tightener later to catch the rest.

        if ( $self->{'_tighten'} and !$self->{'_ignore_text'} )
        {    # if tightenable
            my ( $sibs, $par );
            if (( $sibs = ( $par = $self->{'_pos'} || $self )->{'_content'} )
                and @$sibs            # parent already has content
                and !
                ref( $sibs->[-1] )    # and the last one there is a text node
                and $sibs->[-1] !~ m<[^\n\r\f\t ]>s  # and it's all whitespace

                and (    # one of these has to be eligible...
                    $HTML::TreeBuilder::canTighten{$tag}
                    or (( @$sibs == 1 )
                        ?    # WS is leftmost -- so parent matters
                        $HTML::TreeBuilder::canTighten{ $par->{'_tag'} }
                        :    # WS is after another node -- it matters
                        (   ref $sibs->[-2]
                                and
                                $HTML::TreeBuilder::canTighten{ $sibs->[-2]
                                    {'_tag'} }
                        )
                    )
                )

                and !$par->is_inside( 'pre', 'xmp', 'textarea', 'plaintext' )

                # we're clear
                )
            {
                pop @$sibs;
                print $indent, "Popping a preceding all-WS node\n" if DEBUG;
            }
        }

        $self->insert_element($e) unless $already_inserted;

        if (DEBUG) {
            if ( $self->{'_pos'} ) {
                print $indent, "(Current lineage of pos:  \U$tag\E under ",
                    join(
                    '/',
                    reverse(

                        # $self->{'_pos'}{'_tag'},  # don't list myself!
                        $self->{'_pos'}->lineage_tag_names
                    )
                    ),
                    ".)\n";
            }
            else {
                print $indent, "(Pos points nowhere!?)\n";
            }
        }

        unless ( ( $self->{'_pos'} || '' ) eq $e ) {

            # if it's an empty element -- i.e., if it didn't change the _pos
            &{         $self->{"_tweak_$tag"}
                    || $self->{'_tweak_*'}
                    || return $e }( map $_, $e, $tag, $self )
                ;    # make a list so the user can't clobber
        }

        return $e;
    }
}

#==========================================================================

{
    my $indent;

    sub end {
        return if $_[0]{'_stunted'};

       # Either: Acccept an end-tag signal from HTML::Parser
       # Or: Method for closing currently open elements in some fairly complex
       #  way, as used by other methods in this class.
        my ( $self, $tag, @stop ) = @_;
        if ( $tag eq 'x-html' ) {
            print "Ignoring close-x-html tag.\n" if DEBUG;

            # inserted by some lame code-generators.
            return;
        }

        unless ( ref($tag) or $tag =~ m/^[-_a-zA-Z0-9:%]+$/s ) {
            DEBUG and print "End-tag name $tag is no good.  Skipping.\n";
            return;

            # This avoids having Element's new() throw an exception.
        }

       # This method accepts two calling formats:
       #  1) from Parser:  $self->end('tag_name', 'origtext')
       #        in which case we shouldn't mistake origtext as a blocker tag
       #  2) from myself:  $self->end(\q{tagname1}, 'blk1', ... )
       #     from myself:  $self->end(['tagname1', 'tagname2'], 'blk1',  ... )

        # End the specified tag, but don't move above any of the blocker tags.
        # The tag can also be a reference to an array.  Terminate the first
        # tag found.

        my $ptag = ( my $p = $self->{'_pos'} || $self )->{'_tag'};

        # $p and $ptag are sort-of stratch

        if ( ref($tag) ) {

            # First param is a ref of one sort or another --
            #  THE CALL IS COMING FROM INSIDE THE HOUSE!
            $tag = $$tag if ref($tag) eq 'SCALAR';

            # otherwise it's an arrayref.
        }
        else {

            # the call came from Parser -- just ignore origtext
            # except in a table ignore unmatched table tags RT #59980
            @stop = $tag =~ /^t[hdr]\z/ ? 'table' : ();
        }

        #my($indent);
        if (DEBUG) {

           # optimization -- don't figure out depth unless we're in debug mode
            my @lineage_tags = $p->lineage_tag_names;
            $indent = '  ' x ( 1 + @lineage_tags );

            # now announce ourselves
            print $indent, "Ending ",
                ref($tag) ? ( '[', join( ' ', @$tag ), ']' ) : "\U$tag\E",
                scalar(@stop)
                ? ( " no higher than [", join( ' ', @stop ), "]" )
                : (), ".\n";

            print $indent, " (Current lineage: ", join( '/', @lineage_tags ),
                ".)\n"
                if DEBUG > 1;

            if ( DEBUG > 3 ) {

                #my(
                # $package, $filename, $line, $subroutine,
                # $hasargs, $wantarray, $evaltext, $is_require) = caller;
                print $indent,
                    " (Called from ", ( caller(1) )[3], ' line ',
                    ( caller(1) )[2],
                    ")\n";
            }

            #} else {
            #  $indent = ' ';
        }

        # End of if DEBUG

        # Now actually do it
        my @to_close;
        if ( $tag eq '*' ) {

        # Special -- close everything up to (but not including) the first
        #  limiting tag, or return if none found.  Somewhat of a special case.
        PARENT:
            while ( defined $p ) {
                $ptag = $p->{'_tag'};
                print $indent, " (Looking at $ptag.)\n" if DEBUG > 2;
                for (@stop) {
                    if ( $ptag eq $_ ) {
                        print $indent,
                            " (Hit a $_; closing everything up to here.)\n"
                            if DEBUG > 2;
                        last PARENT;
                    }
                }
                push @to_close, $p;
                $p = $p->{'_parent'};    # no match so far? keep moving up
                print $indent,
                    " (Moving on up to ", $p ? $p->{'_tag'} : 'nil', ")\n"
                    if DEBUG > 1;
            }
            unless ( defined $p ) { # We never found what we were looking for.
                print $indent, " (We never found a limit.)\n" if DEBUG > 1;
                return;
            }

            #print
            #   $indent,
            #   " (To close: ", join('/', map $_->tag, @to_close), ".)\n"
            #  if DEBUG > 4;

            # Otherwise update pos and fall thru.
            $self->{'_pos'} = $p;
        }
        elsif ( ref $tag ) {

           # Close the first of any of the matching tags, giving up if you hit
           #  any of the stop-tags.
        PARENT:
            while ( defined $p ) {
                $ptag = $p->{'_tag'};
                print $indent, " (Looking at $ptag.)\n" if DEBUG > 2;
                for (@$tag) {
                    if ( $ptag eq $_ ) {
                        print $indent, " (Closing $_.)\n" if DEBUG > 2;
                        last PARENT;
                    }
                }
                for (@stop) {
                    if ( $ptag eq $_ ) {
                        print $indent,
                            " (Hit a limiting $_ -- bailing out.)\n"
                            if DEBUG > 1;
                        return;    # so it was all for naught
                    }
                }
                push @to_close, $p;
                $p = $p->{'_parent'};
            }
            return unless defined $p;    # We went off the top of the tree.
               # Otherwise specified element was found; set pos to its parent.
            push @to_close, $p;
            $self->{'_pos'} = $p->{'_parent'};
        }
        else {

            # Close the first of the specified tag, giving up if you hit
            #  any of the stop-tags.
            while ( defined $p ) {
                $ptag = $p->{'_tag'};
                print $indent, " (Looking at $ptag.)\n" if DEBUG > 2;
                if ( $ptag eq $tag ) {
                    print $indent, " (Closing $tag.)\n" if DEBUG > 2;
                    last;
                }
                for (@stop) {
                    if ( $ptag eq $_ ) {
                        print $indent,
                            " (Hit a limiting $_ -- bailing out.)\n"
                            if DEBUG > 1;
                        return;    # so it was all for naught
                    }
                }
                push @to_close, $p;
                $p = $p->{'_parent'};
            }
            return unless defined $p;    # We went off the top of the tree.
               # Otherwise specified element was found; set pos to its parent.
            push @to_close, $p;
            $self->{'_pos'} = $p->{'_parent'};
        }

        $self->{'_pos'} = undef if $self eq ( $self->{'_pos'} || '' );
        print $indent, "(Pos now points to ",
            $self->{'_pos'} ? $self->{'_pos'}{'_tag'} : '???', ".)\n"
            if DEBUG > 1;

        ### EXPENSIVE, because has to check that it's not under a pre
        ### or a CDATA-parent.  That's one more method call per end()!
        ### Might as well just do this at the end of the tree-parse, I guess,
        ### at which point we'd be parsing top-down, and just not traversing
        ### under pre's or CDATA-parents.
        ##
        ## Take this opportunity to nix any terminal whitespace nodes.
        ## TODO: consider whether this (plus the logic in start(), above)
        ## would ever leave any WS nodes in the tree.
        ## If not, then there's no reason to have eof() call
        ## delete_ignorable_whitespace on the tree, is there?
        ##
    #if(@to_close and $self->{'_tighten'} and !$self->{'_ignore_text'} and
    #  ! $to_close[-1]->is_inside('pre', keys %HTML::Tagset::isCDATA_Parent)
    #) {  # if tightenable
    #  my($children, $e_tag);
    #  foreach my $e (reverse @to_close) { # going top-down
    #    last if 'pre' eq ($e_tag = $e->{'_tag'}) or
    #     $HTML::Tagset::isCDATA_Parent{$e_tag};
    #
    #    if(
    #      $children = $e->{'_content'}
    #      and @$children      # has children
    #      and !ref($children->[-1])
    #      and $children->[-1] =~ m<^\s+$>s # last node is all-WS
    #      and
    #        (
    #         # has a tightable parent:
    #         $HTML::TreeBuilder::canTighten{ $e_tag }
    #         or
    #          ( # has a tightenable left sibling:
    #            @$children > 1 and
    #            ref($children->[-2])
    #            and $HTML::TreeBuilder::canTighten{ $children->[-2]{'_tag'} }
    #          )
    #        )
    #    ) {
    #      pop @$children;
    #      #print $indent, "Popping a terminal WS node from ", $e->{'_tag'},
    #      #  " (", $e->address, ") while exiting.\n" if DEBUG;
    #    }
    #  }
    #}

        foreach my $e (@to_close) {

            # Call the applicable callback, if any
            $ptag = $e->{'_tag'};
            &{         $self->{"_tweak_$ptag"}
                    || $self->{'_tweak_*'}
                    || next }( map $_, $e, $ptag, $self );
            print $indent, "Back from tweaking.\n" if DEBUG;
            last
                if $self->{ '_stunted'
                    };    # in case one of the handlers called stunt
        }
        return @to_close;
    }
}

#==========================================================================
{
    my ( $indent, $nugget );

    sub text {
        return if $_[0]{'_stunted'};

        # Accept a "here's a text token" signal from HTML::Parser.
        my ( $self, $text, $is_cdata ) = @_;

        # the >3.0 versions of Parser may pass a cdata node.
        # Thanks to Gisle Aas for pointing this out.

        return unless length $text;    # I guess that's always right

        my $ignore_text         = $self->{'_ignore_text'};
        my $no_space_compacting = $self->{'_no_space_compacting'};
        my $no_expand_entities  = $self->{'_no_expand_entities'};
        my $pos                 = $self->{'_pos'} || $self;

        HTML::Entities::decode($text)
            unless $ignore_text
                || $is_cdata
                || $HTML::Tagset::isCDATA_Parent{ $pos->{'_tag'} }
                || $no_expand_entities;

        #my($indent, $nugget);
        if (DEBUG) {

           # optimization -- don't figure out depth unless we're in debug mode
            my @lineage_tags = $pos->lineage_tag_names;
            $indent = '  ' x ( 1 + @lineage_tags );

            $nugget
                = ( length($text) <= 25 )
                ? $text
                : ( substr( $text, 0, 25 ) . '...' );
            $nugget =~ s<([\x00-\x1F])>
                 <'\\x'.(unpack("H2",$1))>eg;
            print $indent, "Proposing a new text node ($nugget) under ",
                join( '/', reverse( $pos->{'_tag'}, @lineage_tags ) )
                || 'Root',
                ".\n";

            #} else {
            #  $indent = ' ';
        }

        my $ptag;
        if ($HTML::Tagset::isCDATA_Parent{ $ptag = $pos->{'_tag'} }

            #or $pos->is_inside('pre')
            or $pos->is_inside( 'pre', 'textarea' )
            )
        {
            return if $ignore_text;
            $pos->push_content($text);
        }
        else {

            # return unless $text =~ /\S/;  # This is sometimes wrong

            if ( !$self->{'_implicit_tags'} || $text !~ /[^\n\r\f\t ]/ ) {

                # don't change anything
            }
            elsif ( $ptag eq 'head' or $ptag eq 'noframes' ) {
                if ( $self->{'_implicit_body_p_tag'} ) {
                    print $indent,
                        " * Text node under \U$ptag\E closes \U$ptag\E, implicates BODY and P.\n"
                        if DEBUG > 1;
                    $self->end( \$ptag );
                    $pos = $self->{'_body'}
                        ? ( $self->{'_pos'}
                            = $self->{'_body'} )    # expected case
                        : $self->insert_element( 'body', 1 );
                    $pos = $self->insert_element( 'p', 1 );
                }
                else {
                    print $indent,
                        " * Text node under \U$ptag\E closes, implicates BODY.\n"
                        if DEBUG > 1;
                    $self->end( \$ptag );
                    $pos = $self->{'_body'}
                        ? ( $self->{'_pos'}
                            = $self->{'_body'} )    # expected case
                        : $self->insert_element( 'body', 1 );
                }
            }
            elsif ( $ptag eq 'html' ) {
                if ( $self->{'_implicit_body_p_tag'} ) {
                    print $indent,
                        " * Text node under HTML implicates BODY and P.\n"
                        if DEBUG > 1;
                    $pos = $self->{'_body'}
                        ? ( $self->{'_pos'}
                            = $self->{'_body'} )    # expected case
                        : $self->insert_element( 'body', 1 );
                    $pos = $self->insert_element( 'p', 1 );
                }
                else {
                    print $indent,
                        " * Text node under HTML implicates BODY.\n"
                        if DEBUG > 1;
                    $pos = $self->{'_body'}
                        ? ( $self->{'_pos'}
                            = $self->{'_body'} )    # expected case
                        : $self->insert_element( 'body', 1 );

                    #print "POS is $pos, ", $pos->{'_tag'}, "\n";
                }
            }
            elsif ( $ptag eq 'body' ) {
                if ( $self->{'_implicit_body_p_tag'} ) {
                    print $indent, " * Text node under BODY implicates P.\n"
                        if DEBUG > 1;
                    $pos = $self->insert_element( 'p', 1 );
                }
            }
            elsif ( $ptag eq 'table' ) {
                print $indent,
                    " * Text node under TABLE implicates TR and TD.\n"
                    if DEBUG > 1;
                $self->insert_element( 'tr', 1 );
                $pos = $self->insert_element( 'td', 1 );

                # double whammy!
            }
            elsif ( $ptag eq 'tr' ) {
                print $indent, " * Text node under TR implicates TD.\n"
                    if DEBUG > 1;
                $pos = $self->insert_element( 'td', 1 );
            }

            # elsif (
            #       # $ptag eq 'li'   ||
            #       # $ptag eq 'dd'   ||
            #         $ptag eq 'form') {
            #    $pos = $self->insert_element('p', 1);
            #}

            # Whatever we've done above should have had the side
            # effect of updating $self->{'_pos'}

            #print "POS is now $pos, ", $pos->{'_tag'}, "\n";

            return if $ignore_text;
            $text =~ s/[\n\r\f\t ]+/ /g    # canonical space
                unless $no_space_compacting;

            print $indent, " (Attaching text node ($nugget) under ",

           # was: $self->{'_pos'} ? $self->{'_pos'}{'_tag'} : $self->{'_tag'},
                $pos->{'_tag'}, ").\n"
                if DEBUG > 1;

            $pos->push_content($text);
        }

        &{ $self->{'_tweak_~text'} || return }( $text, $pos,
            $pos->{'_tag'} . '' );

        # Note that this is very exceptional -- it doesn't fall back to
        #  _tweak_*, and it gives its tweak different arguments.
        return;
    }
}

#==========================================================================

# TODO: test whether comment(), declaration(), and process(), do the right
#  thing as far as tightening and whatnot.
# Also, currently, doctypes and comments that appear before head or body
#  show up in the tree in the wrong place.  Something should be done about
#  this.  Tricky.  Maybe this whole business of pre-making the body and
#  whatnot is wrong.

sub comment {
    return if $_[0]{'_stunted'};

    # Accept a "here's a comment" signal from HTML::Parser.

    my ( $self, $text ) = @_;
    my $pos = $self->{'_pos'} || $self;
    return
        unless $self->{'_store_comments'}
            || $HTML::Tagset::isCDATA_Parent{ $pos->{'_tag'} };

    if (DEBUG) {
        my @lineage_tags = $pos->lineage_tag_names;
        my $indent = '  ' x ( 1 + @lineage_tags );

        my $nugget
            = ( length($text) <= 25 )
            ? $text
            : ( substr( $text, 0, 25 ) . '...' );
        $nugget =~ s<([\x00-\x1F])>
                 <'\\x'.(unpack("H2",$1))>eg;
        print $indent, "Proposing a Comment ($nugget) under ",
            join( '/', reverse( $pos->{'_tag'}, @lineage_tags ) ) || 'Root',
            ".\n";
    }

    ( my $e = $self->element_class->new('~comment') )->{'text'} = $text;
    $pos->push_content($e);
    ++( $self->{'_element_count'} );

    &{         $self->{'_tweak_~comment'}
            || $self->{'_tweak_*'}
            || return $e }( map $_, $e, '~comment', $self );

    return $e;
}

sub declaration {
    return if $_[0]{'_stunted'};

    # Accept a "here's a markup declaration" signal from HTML::Parser.

    my ( $self, $text ) = @_;
    my $pos = $self->{'_pos'} || $self;

    if (DEBUG) {
        my @lineage_tags = $pos->lineage_tag_names;
        my $indent = '  ' x ( 1 + @lineage_tags );

        my $nugget
            = ( length($text) <= 25 )
            ? $text
            : ( substr( $text, 0, 25 ) . '...' );
        $nugget =~ s<([\x00-\x1F])>
                 <'\\x'.(unpack("H2",$1))>eg;
        print $indent, "Proposing a Declaration ($nugget) under ",
            join( '/', reverse( $pos->{'_tag'}, @lineage_tags ) ) || 'Root',
            ".\n";
    }
    ( my $e = $self->element_class->new('~declaration') )->{'text'} = $text;

    $self->{_decl} = $e;
    return $e;
}

#==========================================================================

sub process {
    return if $_[0]{'_stunted'};

    # Accept a "here's a PI" signal from HTML::Parser.

    return unless $_[0]->{'_store_pis'};
    my ( $self, $text ) = @_;
    my $pos = $self->{'_pos'} || $self;

    if (DEBUG) {
        my @lineage_tags = $pos->lineage_tag_names;
        my $indent = '  ' x ( 1 + @lineage_tags );

        my $nugget
            = ( length($text) <= 25 )
            ? $text
            : ( substr( $text, 0, 25 ) . '...' );
        $nugget =~ s<([\x00-\x1F])>
                 <'\\x'.(unpack("H2",$1))>eg;
        print $indent, "Proposing a PI ($nugget) under ",
            join( '/', reverse( $pos->{'_tag'}, @lineage_tags ) ) || 'Root',
            ".\n";
    }
    ( my $e = $self->element_class->new('~pi') )->{'text'} = $text;
    $pos->push_content($e);
    ++( $self->{'_element_count'} );

    &{ $self->{'_tweak_~pi'} || $self->{'_tweak_*'} || return $e }( map $_,
        $e, '~pi', $self );

    return $e;
}

#==========================================================================

#When you call $tree->parse_file($filename), and the
#tree's ignore_ignorable_whitespace attribute is on (as it is
#by default), HTML::TreeBuilder's logic will manage to avoid
#creating some, but not all, nodes that represent ignorable
#whitespace.  However, at the end of its parse, it traverses the
#tree and deletes any that it missed.  (It does this with an
#around-method around HTML::Parser's eof method.)
#
#However, with $tree->parse($content), the cleanup-traversal step
#doesn't happen automatically -- so when you're done parsing all
#content for a document (regardless of whether $content is the only
#bit, or whether it's just another chunk of content you're parsing into
#the tree), call $tree->eof() to signal that you're at the end of the
#text you're inputting to the tree.  Besides properly cleaning any bits
#of ignorable whitespace from the tree, this will also ensure that
#HTML::Parser's internal buffer is flushed.

sub eof {

    # Accept an "end-of-file" signal from HTML::Parser, or thrown by the user.

    return if $_[0]->{'_done'};    # we've already been here

    return $_[0]->SUPER::eof() if $_[0]->{'_stunted'};

    my $x = $_[0];
    print "EOF received.\n" if DEBUG;
    my (@rv);
    if (wantarray) {

        # I don't think this makes any difference for this particular
        #  method, but let's be scrupulous, for once.
        @rv = $x->SUPER::eof();
    }
    else {
        $rv[0] = $x->SUPER::eof();
    }

    $x->end('html') unless $x eq ( $x->{'_pos'} || $x );

    # That SHOULD close everything, and will run the appropriate tweaks.
    # We /could/ be running under some insane mode such that there's more
    #  than one HTML element, but really, that's just insane to do anyhow.

    unless ( $x->{'_implicit_tags'} ) {

        # delete those silly implicit head and body in case we put
        # them there in implicit tags mode
        foreach my $node ( $x->{'_head'}, $x->{'_body'} ) {
            $node->replace_with_content
                if defined $node
                    and ref $node
                    and $node->{'_implicit'}
                    and $node->{'_parent'};

            # I think they should be empty anyhow, since the only
            # logic that'd insert under them can apply only, I think,
            # in the case where _implicit_tags is on
        }

        # this may still leave an implicit 'html' at the top, but there's
        # nothing we can do about that, is there?
    }

    $x->delete_ignorable_whitespace()

        # this's why we trap this -- an after-method
        if $x->{'_tighten'} and !$x->{'_ignore_text'};
    $x->{'_done'} = 1;

    return @rv if wantarray;
    return $rv[0];
}

#==========================================================================

# TODO: document

sub stunt {
    my $self = $_[0];
    print "Stunting the tree.\n" if DEBUG;
    $self->{'_done'} = 1;

    if ( $HTML::Parser::VERSION < 3 ) {

        #This is a MEAN MEAN HACK.  And it works most of the time!
        $self->{'_buf'} = '';
        my $fh = *HTML::Parser::F{IO};

        # the local'd FH used by parse_file loop
        if ( defined $fh ) {
            print "Closing Parser's filehandle $fh\n" if DEBUG;
            close($fh);
        }

      # But if they called $tree->parse_file($filehandle)
      #  or $tree->parse_file(*IO), then there will be no *HTML::Parser::F{IO}
      #  to close.  Ahwell.  Not a problem for most users these days.

    }
    else {
        $self->SUPER::eof();

        # Under 3+ versions, calling eof from inside a parse will abort the
        #  parse / parse_file
    }

    # In the off chance that the above didn't work, we'll throw
    #  this flag to make any future events be no-ops.
    $self->stunted(1);
    return;
}

# TODO: document
sub stunted { shift->_elem( '_stunted', @_ ); }
sub done    { shift->_elem( '_done',    @_ ); }

#==========================================================================

sub delete {

    # Override Element's delete method.
    # This does most, if not all, of what Element's delete does anyway.
    # Deletes content, including content in some special attributes.
    # But doesn't empty out the hash.

    $_[0]->{'_element_count'} = 1;    # never hurts to be scrupulously correct

    delete @{ $_[0] }{ '_body', '_head', '_pos' };
    for (
        @{ delete( $_[0]->{'_content'} ) || [] },    # all/any content

     #       delete @{$_[0]}{'_body', '_head', '_pos'}
     # ...and these, in case these elements don't appear in the
     #   content, which is possible.  If they did appear (as they
     #   usually do), then calling $_->delete on them again is harmless.
     #  I don't think that's such a hot idea now.  Thru creative reattachment,
     #  those could actually now point to elements in OTHER trees (which we do
     #  NOT want to delete!).
## Reasoned out:
  #  If these point to elements not in the content list of any element in this
  #   tree, but not in the content list of any element in any OTHER tree, then
  #   just deleting these will make their refcounts hit zero.
  #  If these point to elements in the content lists of elements in THIS tree,
  #   then we'll get to deleting them when we delete from the top.
  #  If these point to elements in the content lists of elements in SOME OTHER
  #   tree, then they're not to be deleted.
        )
    {
        $_->delete
            if defined $_ and ref $_    #  Make sure it's an object.
                and $_ ne $_[0];    #  And avoid hitting myself, just in case!
    }

    $_[0]->detach if $_[0]->{'_parent'} and $_[0]->{'_parent'}{'_content'};

    # An 'html' element having a parent is quite unlikely.

    return;
}

sub tighten_up {                    # legacy
    shift->delete_ignorable_whitespace(@_);
}

sub elementify {

    # Rebless this object down into the normal element class.
    my $self     = $_[0];
    my $to_class = $self->element_class;
    delete @{$self}{
        grep {
            ;
            length $_ and substr( $_, 0, 1 ) eq '_'

                # The private attributes that we'll retain:
                and $_ ne '_tag'
                and $_ ne '_parent'
                and $_ ne '_content'
                and $_ ne '_implicit'
                and $_ ne '_pos'
                and $_ ne '_element_class'
            } keys %$self
        };
    bless $self, $to_class;    # Returns the same object we were fed
}

sub element_class {
    return 'HTML::Element' if not ref $_[0];
    return $_[0]->{_element_class} || 'HTML::Element';
}

#--------------------------------------------------------------------------

sub guts {
    my @out;
    my @stack       = ( $_[0] );
    my $destructive = $_[1];
    my $this;
    while (@stack) {
        $this = shift @stack;
        if ( !ref $this ) {
            push @out, $this;    # yes, it can include text nodes
        }
        elsif ( !$this->{'_implicit'} ) {
            push @out, $this;
            delete $this->{'_parent'} if $destructive;
        }
        else {

            # it's an implicit node.  Delete it and recurse
            delete $this->{'_parent'} if $destructive;
            unshift @stack,
                @{
                (   $destructive
                    ? delete( $this->{'_content'} )
                    : $this->{'_content'}
                    )
                    || []
                };
        }
    }

    # Doesn't call a real $root->delete on the (when implicit) root,
    #  but I don't think it needs to.

    return @out if wantarray;    # one simple normal case.
    return unless @out;
    return $out[0] if @out == 1 and ref( $out[0] );
    my $x = HTML::Element->new( 'div', '_implicit' => 1 );
    $x->push_content(@out);
    return $x;
}

sub disembowel { $_[0]->guts(1) }

#--------------------------------------------------------------------------
1;

__END__

=pod

=head1 NAME

HTML::TreeBuilder - Parser that builds a HTML syntax tree

=head1 VERSION

This document describes version 5.07 of
HTML::TreeBuilder, released August 31, 2017
as part of L<HTML-Tree|HTML::Tree>.

=head1 SYNOPSIS

  use HTML::TreeBuilder 5 -weak; # Ensure weak references in use

  foreach my $file_name (@ARGV) {
    my $tree = HTML::TreeBuilder->new; # empty tree
    $tree->parse_file($file_name);
    print "Hey, here's a dump of the parse tree of $file_name:\n";
    $tree->dump; # a method we inherit from HTML::Element
    print "And here it is, bizarrely rerendered as HTML:\n",
      $tree->as_HTML, "\n";

    # Now that we're done with it, we must destroy it.
    # $tree = $tree->delete; # Not required with weak references
  }

=head1 DESCRIPTION

(This class is part of the L<HTML::Tree|HTML::Tree> dist.)

This class is for HTML syntax trees that get built out of HTML
source.  The way to use it is to:

1. start a new (empty) HTML::TreeBuilder object,

2. then use one of the methods from HTML::Parser (presumably with
C<< $tree->parse_file($filename) >> for files, or with
C<< $tree->parse($document_content) >> and C<< $tree->eof >> if you've got
the content in a string) to parse the HTML
document into the tree C<$tree>.

(You can combine steps 1 and 2 with the "new_from_file" or
"new_from_content" methods.)

2b. call C<< $root->elementify() >> if you want.

3. do whatever you need to do with the syntax tree, presumably
involving traversing it looking for some bit of information in it,

4. previous versions of HTML::TreeBuilder required you to call
C<< $tree->delete() >> to erase the contents of the tree from memory
when you're done with the tree.  This is not normally required anymore.
See L<HTML::Element/"Weak References"> for details.

=head1 ATTRIBUTES

Most of the following attributes native to HTML::TreeBuilder control how
parsing takes place; they should be set I<before> you try parsing into
the given object.  You can set the attributes by passing a TRUE or
FALSE value as argument.  E.g., C<< $root->implicit_tags >> returns
the current setting for the C<implicit_tags> option,
C<< $root->implicit_tags(1) >> turns that option on,
and C<< $root->implicit_tags(0) >> turns it off.

=head2 implicit_tags

Setting this attribute to true will instruct the parser to try to
deduce implicit elements and implicit end tags.  If it is false you
get a parse tree that just reflects the text as it stands, which is
unlikely to be useful for anything but quick and dirty parsing.
(In fact, I'd be curious to hear from anyone who finds it useful to
have C<implicit_tags> set to false.)
Default is true.

Implicit elements have the L<HTML::Element/implicit> attribute set.

=head2 implicit_body_p_tag

This controls an aspect of implicit element behavior, if C<implicit_tags>
is on:  If a text element (PCDATA) or a phrasal element (such as
C<< <em> >>) is to be inserted under C<< <body> >>, two things
can happen: if C<implicit_body_p_tag> is true, it's placed under a new,
implicit C<< <p> >> tag.  (Past DTDs suggested this was the only
correct behavior, and this is how past versions of this module
behaved.)  But if C<implicit_body_p_tag> is false, nothing is implicated
-- the PCDATA or phrasal element is simply placed under
C<< <body> >>.  Default is false.

=head2 no_expand_entities

This attribute controls whether entities are decoded during the initial
parse of the source. Enable this if you don't want entities decoded to
their character value. e.g. '&amp;' is decoded to '&' by default, but
will be unchanged if this is enabled.
Default is false (entities will be decoded.)

=head2 ignore_unknown

This attribute controls whether unknown tags should be represented as
elements in the parse tree, or whether they should be ignored.
Default is true (to ignore unknown tags.)

=head2 ignore_text

Do not represent the text content of elements.  This saves space if
all you want is to examine the structure of the document.  Default is
false.

=head2 ignore_ignorable_whitespace

If set to true, TreeBuilder will try to avoid
creating ignorable whitespace text nodes in the tree.  Default is
true.  (In fact, I'd be interested in hearing if there's ever a case
where you need this off, or where leaving it on leads to incorrect
behavior.)

=head2 no_space_compacting

This determines whether TreeBuilder compacts all whitespace strings
in the document (well, outside of PRE or TEXTAREA elements), or
leaves them alone.  Normally (default, value of 0), each string of
contiguous whitespace in the document is turned into a single space.
But that's not done if C<no_space_compacting> is set to 1.

Setting C<no_space_compacting> to 1 might be useful if you want
to read in a tree just to make some minor changes to it before
writing it back out.

This method is experimental.  If you use it, be sure to report
any problems you might have with it.

=head2 p_strict

If set to true (and it defaults to false), TreeBuilder will take a
narrower than normal view of what can be under a C<< <p> >> element; if it sees
a non-phrasal element about to be inserted under a C<< <p> >>, it will
close that C<< <p> >>.  Otherwise it will close C<< <p> >> elements only for
other C<< <p> >>'s, headings, and C<< <form> >> (although the latter may be
removed in future versions).

For example, when going thru this snippet of code,

  <p>stuff
  <ul>

TreeBuilder will normally (with C<p_strict> false) put the C<< <ul> >> element
under the C<< <p> >> element.  However, with C<p_strict> set to true, it will
close the C<< <p> >> first.

In theory, there should be strictness options like this for other/all
elements besides just C<< <p> >>; but I treat this as a special case simply
because of the fact that C<< <p> >> occurs so frequently and its end-tag is
omitted so often; and also because application of strictness rules
at parse-time across all elements often makes tiny errors in HTML
coding produce drastically bad parse-trees, in my experience.

If you find that you wish you had an option like this to enforce
content-models on all elements, then I suggest that what you want is
content-model checking as a stage after TreeBuilder has finished
parsing.

=head2 store_comments

This determines whether TreeBuilder will normally store comments found
while parsing content into C<$root>.  Currently, this is off by default.

=head2 store_declarations

This determines whether TreeBuilder will normally store markup
declarations found while parsing content into C<$root>.  This is on
by default.

=head2 store_pis

This determines whether TreeBuilder will normally store processing
instructions found while parsing content into C<$root> -- assuming a
recent version of HTML::Parser (old versions won't parse PIs
correctly).  Currently, this is off (false) by default.

It is somewhat of a known bug (to be fixed one of these days, if
anyone needs it?) that PIs in the preamble (before the C<< <html> >>
start-tag) end up actually I<under> the C<< <html> >> element.

=head2 warn

This determines whether syntax errors during parsing should generate
warnings, emitted via Perl's C<warn> function.

This is off (false) by default.

=head1 METHODS

Objects of this class inherit the methods of both HTML::Parser and
HTML::Element.  The methods inherited from HTML::Parser are used for
building the HTML tree, and the methods inherited from HTML::Element
are what you use to scrutinize the tree.  Besides this
(HTML::TreeBuilder) documentation, you must also carefully read the
HTML::Element documentation, and also skim the HTML::Parser
documentation -- probably only its parse and parse_file methods are of
interest.

=head2 new_from_file

  $root = HTML::TreeBuilder->new_from_file($filename_or_filehandle);

This "shortcut" constructor merely combines constructing a new object
(with the L</new> method, below), and calling C<< $new->parse_file(...) >> on
it.  Returns the new object.  Note that this provides no way of
setting any parse options like C<store_comments> (for that, call C<new>, and
then set options, before calling C<parse_file>).  See the notes (below)
on parameters to L</parse_file>.

If HTML::TreeBuilder is unable to read the file, then C<new_from_file>
dies.  The error can also be found in C<$!>.  (This behavior is new in
HTML-Tree 5. Previous versions returned a tree with only implicit elements.)

=head2 new_from_content

  $root = HTML::TreeBuilder->new_from_content(...);

This "shortcut" constructor merely combines constructing a new object
(with the L</new> method, below), and calling C<< for(...){$new->parse($_)} >>
and C<< $new->eof >> on it.  Returns the new object.  Note that this provides
no way of setting any parse options like C<store_comments> (for that,
call C<new>, and then set options, before calling C<parse>).  Example
usages: C<< HTML::TreeBuilder->new_from_content(@lines) >>, or
C<< HTML::TreeBuilder->new_from_content($content) >>.

=head2 new_from_url

  $root = HTML::TreeBuilder->new_from_url($url)

This "shortcut" constructor combines constructing a new object (with
the L</new> method, below), loading L<LWP::UserAgent>, fetching the
specified URL, and calling C<< $new->parse( $response->decoded_content) >>
and C<< $new->eof >> on it.
Returns the new object.  Note that this provides no way of setting any
parse options like C<store_comments>.

If LWP is unable to fetch the URL, or the response is not HTML (as
determined by L<HTTP::Headers/content_is_html>), then C<new_from_url>
dies, and the HTTP::Response object is found in
C<$HTML::TreeBuilder::lwp_response>.

You must have installed LWP::UserAgent for this method to work.  LWP
is not installed automatically, because it's a large set of modules
and you might not need it.

=head2 new

  $root = HTML::TreeBuilder->new();

This creates a new HTML::TreeBuilder object.  This method takes no
attributes.

=head2 parse_file

 $root->parse_file(...)

[An important method inherited from L<HTML::Parser|HTML::Parser>, which
see.  Current versions of HTML::Parser can take a filespec, or a
filehandle object, like *FOO, or some object from class IO::Handle,
IO::File, IO::Socket) or the like.
I think you should check that a given file exists I<before> calling
C<< $root->parse_file($filespec) >>.]

When you pass a filename to C<parse_file>, HTML::Parser opens it in
binary mode, which means it's interpreted as Latin-1 (ISO-8859-1).  If
the file is in another encoding, like UTF-8 or UTF-16, this will not
do the right thing.

One solution is to open the file yourself using the proper
C<:encoding> layer, and pass the filehandle to C<parse_file>.  You can
automate this process by using L<IO::HTML/html_file>, which will use
the HTML5 encoding sniffing algorithm to automatically determine the
proper C<:encoding> layer and apply it.

In the next major release of HTML-Tree, I plan to have it use IO::HTML
automatically.  If you really want your file opened in binary mode,
you should open it yourself and pass the filehandle to C<parse_file>.

The return value is C<undef> if there's an error opening the file.  In
that case, the error will be in C<$!>.

=head2 parse

  $root->parse(...)

[A important method inherited from L<HTML::Parser|HTML::Parser>, which
see.  See the note below for C<< $root->eof() >>.]

=head2 eof

  $root->eof();

This signals that you're finished parsing content into this tree; this
runs various kinds of crucial cleanup on the tree.  This is called
I<for you> when you call C<< $root->parse_file(...) >>, but not when
you call C<< $root->parse(...) >>.  So if you call
C<< $root->parse(...) >>, then you I<must> call C<< $root->eof() >>
once you've finished feeding all the chunks to C<parse(...)>, and
before you actually start doing anything else with the tree in C<$root>.

=head2 parse_content

  $root->parse_content(...);

Basically a handy alias for C<< $root->parse(...); $root->eof >>.
Takes the exact same arguments as C<< $root->parse() >>.

=head2 delete

  $root->delete();

[A previously important method inherited from L<HTML::Element|HTML::Element>,
which see.]

=head2 elementify

  $root->elementify();

This changes the class of the object in C<$root> from
HTML::TreeBuilder to the class used for all the rest of the elements
in that tree (generally HTML::Element).  Returns C<$root>.

For most purposes, this is unnecessary, but if you call this after
(after!!)
you've finished building a tree, then it keeps you from accidentally
trying to call anything but HTML::Element methods on it.  (I.e., if
you accidentally call C<$root-E<gt>parse_file(...)> on the
already-complete and elementified tree, then instead of charging ahead
and I<wreaking havoc>, it'll throw a fatal error -- since C<$root> is
now an object just of class HTML::Element which has no C<parse_file>
method.

Note that C<elementify> currently deletes all the private attributes of
C<$root> except for "_tag", "_parent", "_content", "_pos", and
"_implicit".  If anyone requests that I change this to leave in yet
more private attributes, I might do so, in future versions.

=head2 guts

 @nodes = $root->guts();
 $parent_for_nodes = $root->guts();

In list context (as in the first case), this method returns the topmost
non-implicit nodes in a tree.  This is useful when you're parsing HTML
code that you know doesn't expect an HTML document, but instead just
a fragment of an HTML document.  For example, if you wanted the parse
tree for a file consisting of just this:

  <li>I like pie!

Then you would get that with C<< @nodes = $root->guts(); >>.
It so happens that in this case, C<@nodes> will contain just one
element object, representing the C<< <li> >> node (with "I like pie!" being
its text child node).  However, consider if you were parsing this:

  <hr>Hooboy!<hr>

In that case, C<< $root->guts() >> would return three items:
an element object for the first C<< <hr> >>, a text string "Hooboy!", and
another C<< <hr> >> element object.

For cases where you want definitely one element (so you can treat it as
a "document fragment", roughly speaking), call C<guts()> in scalar
context, as in C<< $parent_for_nodes = $root->guts() >>. That works like
C<guts()> in list context; in fact, C<guts()> in list context would
have returned exactly one value, and if it would have been an object (as
opposed to a text string), then that's what C<guts> in scalar context
will return.  Otherwise, if C<guts()> in list context would have returned
no values at all, then C<guts()> in scalar context returns undef.  In
all other cases, C<guts()> in scalar context returns an implicit C<< <div> >>
element node, with children consisting of whatever nodes C<guts()>
in list context would have returned.  Note that that may detach those
nodes from C<$root>'s tree.

=head2 disembowel

  @nodes = $root->disembowel();
  $parent_for_nodes = $root->disembowel();

The C<disembowel()> method works just like the C<guts()> method, except
that disembowel definitively destroys the tree above the nodes that
are returned.  Usually when you want the guts from a tree, you're just
going to toss out the rest of the tree anyway, so this saves you the
bother.  (Remember, "disembowel" means "remove the guts from".)

=head1 INTERNAL METHODS

You should not need to call any of the following methods directly.

=head2 element_class

  $classname = $h->element_class;

This method returns the class which will be used for new elements.  It
defaults to HTML::Element, but can be overridden by subclassing or esoteric
means best left to those will will read the source and then not complain when
those esoteric means change.  (Just subclass.)

=head2 comment

Accept a "here's a comment" signal from HTML::Parser.

=head2 declaration

Accept a "here's a markup declaration" signal from HTML::Parser.

=head2 done

TODO: document

=head2 end

Either: Acccept an end-tag signal from HTML::Parser
Or: Method for closing currently open elements in some fairly complex
way, as used by other methods in this class.

TODO: Why is this hidden?

=head2 process

Accept a "here's a PI" signal from HTML::Parser.

=head2 start

Accept a signal from HTML::Parser for start-tags.

TODO: Why is this hidden?

=head2 stunt

TODO: document

=head2 stunted

TODO: document

=head2 text

Accept a "here's a text token" signal from HTML::Parser.

TODO: Why is this hidden?

=head2 tighten_up

Legacy

Redirects to L<HTML::Element/delete_ignorable_whitespace>.

=head2 warning

Wrapper for CORE::warn

TODO: why not just use carp?

=head1 SUBROUTINES

=head2 DEBUG

Are we in Debug mode?  This is a constant subroutine, to allow
compile-time optimizations.  To control debug mode, set
C<$HTML::TreeBuilder::DEBUG> I<before> loading HTML::TreeBuilder.

=head1 HTML AND ITS DISCONTENTS

HTML is rather harder to parse than people who write it generally
suspect.

Here's the problem: HTML is a kind of SGML that permits "minimization"
and "implication".  In short, this means that you don't have to close
every tag you open (because the opening of a subsequent tag may
implicitly close it), and if you use a tag that can't occur in the
context you seem to using it in, under certain conditions the parser
will be able to realize you mean to leave the current context and
enter the new one, that being the only one that your code could
correctly be interpreted in.

Now, this would all work flawlessly and unproblematically if: 1) all
the rules that both prescribe and describe HTML were (and had been)
clearly set out, and 2) everyone was aware of these rules and wrote
their code in compliance to them.

However, it didn't happen that way, and so most HTML pages are
difficult if not impossible to correctly parse with nearly any set of
straightforward SGML rules.  That's why the internals of
HTML::TreeBuilder consist of lots and lots of special cases -- instead
of being just a generic SGML parser with HTML DTD rules plugged in.

=head1 TRANSLATIONS?

The techniques that HTML::TreeBuilder uses to perform what I consider
very robust parses on everyday code are not things that can work only
in Perl.  To date, the algorithms at the center of HTML::TreeBuilder
have been implemented only in Perl, as far as I know; and I don't
foresee getting around to implementing them in any other language any
time soon.

If, however, anyone is looking for a semester project for an applied
programming class (or if they merely enjoy I<extra-curricular>
masochism), they might do well to see about choosing as a topic the
implementation/adaptation of these routines to any other interesting
programming language that you feel currently suffers from a lack of
robust HTML-parsing.  I welcome correspondence on this subject, and
point out that one can learn a great deal about languages by trying to
translate between them, and then comparing the result.

The HTML::TreeBuilder source may seem long and complex, but it is
rather well commented, and symbol names are generally
self-explanatory.  (You are encouraged to read the Mozilla HTML parser
source for comparison.)  Some of the complexity comes from little-used
features, and some of it comes from having the HTML tokenizer
(HTML::Parser) being a separate module, requiring somewhat of a
different interface than you'd find in a combined tokenizer and
tree-builder.  But most of the length of the source comes from the fact
that it's essentially a long list of special cases, with lots and lots
of sanity-checking, and sanity-recovery -- because, as Roseanne
Rosannadanna once said, "it's always I<something>".

Users looking to compare several HTML parsers should look at the
source for Raggett's Tidy
(C<E<lt>http://www.w3.org/People/Raggett/tidy/E<gt>>),
Mozilla
(C<E<lt>http://www.mozilla.org/E<gt>>),
and possibly root around the browsers section of Yahoo
to find the various open-source ones
(C<E<lt>http://dir.yahoo.com/Computers_and_Internet/Software/Internet/World_Wide_Web/Browsers/E<gt>>).

=head1 BUGS

* Framesets seem to work correctly now.  Email me if you get a strange
parse from a document with framesets.

* Really bad HTML code will, often as not, make for a somewhat
objectionable parse tree.  Regrettable, but unavoidably true.

* If you're running with C<implicit_tags> off (God help you!), consider
that C<< $tree->content_list >> probably contains the tree or grove from the
parse, and not C<$tree> itself (which will, oddly enough, be an implicit
C<< <html> >> element).  This seems counter-intuitive and problematic; but
seeing as how almost no HTML ever parses correctly with C<implicit_tags>
off, this interface oddity seems the least of your problems.

=head1 BUG REPORTS

When a document parses in a way different from how you think it
should, I ask that you report this to me as a bug.  The first thing
you should do is copy the document, trim out as much of it as you can
while still producing the bug in question, and I<then> email me that
mini-document I<and> the code you're using to parse it, to the HTML::Tree
bug queue at S<C<< <bug-html-tree at rt.cpan.org> >>>.

Include a note as to how it
parses (presumably including its C<< $tree->dump >> output), and then a
I<careful and clear> explanation of where you think the parser is
going astray, and how you would prefer that it work instead.

=head1 SEE ALSO

For more information about the HTML-Tree distribution: L<HTML::Tree>.

Modules used by HTML::TreeBuilder:
L<HTML::Parser>, L<HTML::Element>, L<HTML::Tagset>.

For converting between L<XML::DOM::Node>, L<HTML::Element>, and
L<XML::Element> trees: L<HTML::DOMbo>.

For opening a HTML file with automatic charset detection: L<IO::HTML>.

=head1 AUTHOR

Current maintainers:

=over

=item * Christopher J. Madsen S<C<< <perl AT cjmweb.net> >>>

=item * Jeff Fearn S<C<< <jfearn AT cpan.org> >>>

=back

Original HTML-Tree author:

=over

=item * Gisle Aas

=back

Former maintainers:

=over

=item * Sean M. Burke

=item * Andy Lester

=item * Pete Krawczyk S<C<< <petek AT cpan.org> >>>

=back

You can follow or contribute to HTML-Tree's development at
L<< https://github.com/kentfredric/HTML-Tree >>.

=head1 COPYRIGHT AND LICENSE

Copyright 1995-1998 Gisle Aas, 1999-2004 Sean M. Burke,
2005 Andy Lester, 2006 Pete Krawczyk, 2010 Jeff Fearn,
2012 Christopher J. Madsen.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

The programs in this library are distributed in the hope that they
will be useful, but without any warranty; without even the implied
warranty of merchantability or fitness for a particular purpose.

=cut
