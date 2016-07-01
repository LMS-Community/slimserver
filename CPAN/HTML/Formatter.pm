package HTML::Formatter;
BEGIN {
  $HTML::Formatter::VERSION = '2.05';
}
BEGIN {
  $HTML::Formatter::AUTHORITY = 'cpan:NIGELM';
}

# ABSTRACT: Base class for HTML formatters


BEGIN { *DEBUG = sub(){0} unless defined &DEBUG }

use HTML::Element 3.15 ();

use strict;
use Carp;

use vars qw($VERSION @Size_magic_numbers);

#
# A typical formatter will not use all of the features of this
# class.  But it will use some, as best fits the mapping
# of HTML to the particular output format.
#


sub new
{
    my($class,%arg) = @_;
    my $self = bless { $class->default_values }, $class;
    $self->configure(\%arg) if keys %arg;
    $self;
}

sub default_values
{
    ();
}

sub configure
{
    my($self, $arg) = @_;
    for (keys %$arg) {
    warn "Unknown configure argument '$_'" if $^W;
    }
    $self;
}

sub massage_tree {
  my($self, $html) = @_;
  return if $html->tag eq 'p'; # sanity

  DEBUG > 4 and print("Before massaging:\n"), $html->dump();

  $html->simplify_pres();

  # Does anything else need doing?

  DEBUG > 4 and print("After massaging:\n"), $html->dump();

  return;
}



sub format_from_file   { shift->format_file(@_) }
sub format_file {
  my($self, $filename, @params) = @_;
  $self = $self->new(@params) unless ref $self;

  croak "What filename to format from?"
   unless defined $filename and length $filename;

  my $tree = $self->_default_tree();
  $tree->parse_file($filename);

  my $out = $self->format($tree);
  $tree->delete;
  return $out;
}


sub format_from_string { shift->format_string(@_) }
sub format_string {
  my($self, $content, @params) = @_;
  $self = $self->new(@params) unless ref $self;

  croak "What string to format?" unless defined $content;

  my $tree = $self->_default_tree();
  $tree->parse($content);
  $tree->eof();
  undef $content;

  my $out = $self->format($tree);
  $tree->delete;
  return $out;
}

sub _default_tree {
  require HTML::TreeBuilder;
  my $t = HTML::TreeBuilder->new;

  # If nothing else works, try using these parser options:s
  #$t->implicit_body_p_tag(1);
  #$t->p_strict(1);

  return $t;
}



sub format
{
    my($self, $html) = @_;

    croak "Usage: \$formatter->format(\$tree)"
     unless defined $html and ref $html and $html->can('tag');

    if( $self->DEBUG() > 4 ) {
      print "Tree to format:\n";
      $html->dump;
    }

    $self->set_version_tag($html);
    $self->massage_tree($html);
    $self->begin($html);
    $html->number_lists();


    # Per-iteration scratch:
    my($node, $start, $depth, $tag, $func);
    $html->traverse(
    sub {
        ($node, $start, $depth) = @_;
        if (ref $node) {
        $tag = $node->tag;
        $func = $tag . '_' . ($start ? "start" : "end");
        # Use ->can so that we can recover if
        # a handler is not defined for the tag.
        if ($self->can($func)) {
            DEBUG > 3 and print '  ' x $depth, "Calling $func\n";
            return $self->$func($node);
        } else {
            DEBUG > 3 and print '  ' x $depth,
              "Skipping $func: no handler for it.\n";
            return 1;
        }
        } else {
        $self->textflow($node);
        }
        1;
    }
    );
    $self->end($html);
    join('', @{$self->{output}});
}

sub begin
{
    my $self = shift;

    # Flags
    $self->{anchor}    = 0;
    $self->{underline} = 0;
    $self->{bold}      = 0;
    $self->{italic}    = 0;
    $self->{center}    = 0;

    $self->{superscript}   = 0;
    $self->{subscript}     = 0;
    $self->{strikethrough} = 0;

    $self->{center_stack} = []; # push and pop 'center' states to it
    $self->{nobr}      = 0;

    $self->{'font_size'}   = [3];   # last element is current size
    $self->{basefont_size} = [3];

    $self->{vspace} = undef;        # vertical space (dimension)

    $self->{output} = [];
}

sub end
{
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
sub set_version_tag {
  my($self, $html) = @_;

  if($html) {
    $self->{'version_tag'} = sprintf(
      "%s (v%s, using %s v%s%s)",
      ref($self), $self->VERSION || '?',
      ref($html), $html->VERSION || '?',
      $HTML::Parser::VERSION
        ? ", and HTML::Parser v$HTML::Parser::VERSION"
        : ''
    );
  } elsif( $HTML::Parser::VERSION ) {
    $self->{'version_tag'} = sprintf(
      "%s (v%s, using %s)",
      ref($self), $self->VERSION || "?",
      "HTML::Parser v$HTML::Parser::VERSION",
    );
  } else {
    $self->{'version_tag'} = sprintf(
      "%s (v%s)",
      ref($self), $self->VERSION || '?',
    );
  }
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub version_tag { shift->{'version_tag'} }

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub html_start { 1; }  sub html_end {}
sub body_start { 1; }  sub body_end {}

# some elements that we don't want to render anyway
sub     head_start { 0; }
sub   script_start { 0; }
sub    style_start { 0; }
sub frameset_start { 0; }


sub header_start
{
    my($self, undef, $node) = @_;
    my $align = $node->attr('align');
    if (defined($align) && lc($align) eq 'center') {
    $self->{center}++;
    }
    1;
}

sub header_end
{
    my($self, undef, $node) = @_;
    my $align = $node->attr('align');
    if (defined($align) && lc($align) eq 'center') {
    $self->{center}--;
    }
}

sub h1_start { shift->header_start(1, @_) }
sub h2_start { shift->header_start(2, @_) }
sub h3_start { shift->header_start(3, @_) }
sub h4_start { shift->header_start(4, @_) }
sub h5_start { shift->header_start(5, @_) }
sub h6_start { shift->header_start(6, @_) }

sub h1_end   { shift->header_end(1, @_) }
sub h2_end   { shift->header_end(2, @_) }
sub h3_end   { shift->header_end(3, @_) }
sub h4_end   { shift->header_end(4, @_) }
sub h5_end   { shift->header_end(5, @_) }
sub h6_end   { shift->header_end(6, @_) }

sub br_start
{
    my $self = shift;
    $self->vspace(0, 1);
     # add one formatting newline, regardless of how many are there
}

sub hr_start
{
    my $self = shift;
    $self->vspace(1);
     # assert one line's worth of vertical space
    1;
}

sub img_start
{
    my($self,$node) = @_;
    my $alt = $node->attr('alt');
    $self->out(  defined($alt) ? $alt : "[IMAGE]" );
}

sub a_start
{
    shift->{anchor}++;
    1;
}

sub a_end
{
    shift->{anchor}--;
}


sub u_start
{
    shift->{underline}++;
    1;
}

sub u_end
{
    shift->{underline}--;
}

sub b_start
{
    shift->{bold}++;
    1;
}

sub b_end
{
    shift->{bold}--;
}

sub tt_start
{
    shift->{teletype}++;
    1;
}

sub tt_end
{
    shift->{teletype}--;
}

sub i_start
{
    shift->{italic}++;
    1;
}

sub i_end
{
    shift->{italic}--;
}

sub center_start
{
    shift->{center}++;
    1;
}

sub center_end
{
    shift->{center}--;
}


sub div_start   # interesting only for its 'align' attribute
{
    my($self, $node) = @_;
    my $align = $node->attr('align');
    if (defined($align) && lc($align) eq 'center') {
    return $self->center_start;
    }
    1;
}

sub div_end
{
    my($self, $node) = @_;
    my $align = $node->attr('align');
    if (defined($align) && lc($align) eq 'center') {
    return $self->center_end;
    }
}


sub nobr_start
{
    shift->{nobr}++;
    1;
}

sub nobr_end
{
    shift->{nobr}--;
}

sub wbr_start
{
    1;
}

# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

sub font_start
{
    my($self, $elem) = @_;
    my $size = $elem->attr('size');
    return 1 unless defined $size;
    if ($size =~ /^\s*[+\-]/) {
    my $base = $self->{basefont_size}[-1];
      # yes, base it on the most recent one
    $size = $base + $size;
    }
    push @{$self->{'font_size'}}, $size;
    $self->new_font_size( $size );
    1;
}

sub font_end
{
    my($self, $elem) = @_;
    my $size = $elem->attr('size');
    return unless defined $size;
    pop @{$self->{'font_size'}};
    $self->restore_font_size(  $self->{'font_size'}[-1]  );
}



sub big_start
{
    my $self = $_[0];
    push @{$self->{'font_size'}},
      $self->{basefont_size}[-1] + 1;   # same as font size="+1"
    $self->new_font_size(  $self->{'font_size'}[ -1 ]  );
    1;
}

sub small_start
{
    my $self = $_[0];
    push @{$self->{'font_size'}},
      $self->{basefont_size}[-1] - 1,   # same as font size="-1"
    ;
    $self->new_font_size(  $self->{'font_size'}[ -1 ]  );
    1;
}

sub big_end
{
    my $self = $_[0];
    pop @{ $self->{'font_size'} };
    $self->restore_font_size(  $self->{'font_size'}[-1]  );
    1;
}

sub small_end
{
    my $self = $_[0];
    pop @{ $self->{'font_size'} };
    $self->restore_font_size(  $self->{'font_size'}[-1]  );
    1;
}

# ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~

sub basefont_start
{
    my($self, $elem) = @_;
    my $size = $elem->attr('size');
    return unless defined $size;
    push(@{$self->{basefont_size}}, $size);
    1;
}

sub basefont_end
{
    my($self, $elem) = @_;
    my $size = $elem->attr('size');
    return unless defined $size;
    pop(@{$self->{basefont_size}});
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Override in subclasses, if you like.

sub new_font_size {
    #my( $self, $font_size_number ) = @_;
}

sub restore_font_size {
    #my( $self, $font_size_number ) = @_;
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub q_start { shift->out( q<"> ); 1; }
sub q_end   { shift->out( q<"> ); 1; }


sub sup_start { shift->{superscript}++; 1; }
sub sup_end   { shift->{superscript}--; 1; }

sub sub_start { shift->{subscript}  ++; 1; }
sub sub_end   { shift->{subscript}  --; 1; }

sub strike_start { shift->{strikethrough}++; 1; }
sub strike_end   { shift->{strikethrough}--; 1; }

# Alias:
sub s_start { shift->strike_start(@_) }
sub s_end   { shift->strike_end(  @_) }


## No actual appearance change, so no point in defining:
#
# sub dfn_start { 1; }
# sub dfn_end   { 1; }
# sub abbr_start { 1; }
# sub abbr_end   { 1; }
# sub acronym_start { 1; }
# sub acronym_end   { 1; }
# sub span_start { 1; }
# sub span_end   { 1; }
# sub div_start { 1; }
# sub div_end   { 1; }
# sub ins_start { 1; }
# sub ins_end   { 1; }

sub del_start { 0; } # Don't render the del'd bits
sub del_end   { 0; }

@Size_magic_numbers = (
  .60,  .75,  .89,   1,  1.20,  1.50,  2.00,  3.00
 # #0    #1    #2   #3     #4     #5     #6     #7
 #________________ - | + _________________________
 # -3    -2    -1    0     +1     +2     +3     +4
);

sub scale_font_for {
  my($self, $reference_size) = @_;

  # Mozilla's source, at
  # http://lxr.mozilla.org/seamonkey/source/content/html/style/src/nsStyleUtil.cpp#299
  # says:
  #  static PRInt32 sFontSizeFactors[8] = { 60,75,89,100,120,150,200,300 };
  #
  # For comparison, Gisle's earlier HTML::FormatPS has:
  #    |           # size   0   1   2   3   4   5   6   7
  #    | @FontSizes = ( 5,  6,  8, 10, 12, 14, 18, 24, 32);
  # ...and gets different sizing via just a scaling factor.

  my $size_number = int( defined($_[2]) ? $_[2] : $self->{'font_size'}[-1] );

  # force the size_number into range:
  $size_number =
      ( $size_number < 0 ) ?  0
    : ( $size_number > $#Size_magic_numbers ) ?  $#Size_magic_numbers
    : int( $size_number )
  ;

  my $result = int( .5 + $reference_size * $Size_magic_numbers[ $size_number ] );

  $self->DEBUG() > 1
   and printf "  Turning reference size %s and size number %s into %s.\n",
    $reference_size, $size_number, $result,
  ;

  return $result;
}


# Aliases for logical markup:
sub strong_start   { shift-> b_start( @_) }
sub strong_end     { shift-> b_end(   @_) }
sub   cite_start   { shift-> i_start( @_) }
sub   cite_end     { shift-> i_end(   @_) }
sub     em_start   { shift-> i_start( @_) }
sub     em_end     { shift-> i_end(   @_) }
sub   code_start   { shift->tt_start( @_) }
sub   code_end     { shift->tt_end(   @_) }
sub    kbd_start   { shift->tt_start( @_) }
sub    kbd_end     { shift->tt_end(   @_) }
sub   samp_start   { shift->tt_start( @_) }
sub   samp_end     { shift->tt_end(   @_) }
sub    var_start   { shift->tt_start( @_) }
sub    var_end     { shift->tt_end(   @_) }

sub p_start
{
    my $self = shift;
    #$self->adjust_lm(0); # assert new paragraph
    $self->vspace(1);
     # assert one line's worth of vertical space at para-start
    $self->out('');
    1;
}

sub p_end
{
    shift->vspace(1);
     # assert one line's worth of vertical space at para-end
}

sub pre_start
{
    my $self = shift;
    $self->{pre}++;
    $self->vspace(1);
     # assert one line's worth of vertical space at pre-start
    1;
}

sub pre_end
{
    my $self = shift;
    $self->{pre}--;
     # assert one line's worth of vertical space at pre-end
    $self->vspace(1);
}

sub listing_start      { shift->pre_start( @_ ) }
sub listing_end        { shift->pre_end(   @_ ) }
sub     xmp_start      { shift->pre_start( @_ ) }
sub     xmp_end        { shift->pre_end(   @_ ) }

sub blockquote_start
{
    my $self = shift;
    $self->vspace(1);
     # assert one line's worth of vertical space at blockquote-start
    $self->adjust_lm( +2 );
    $self->adjust_rm( -2 );
    1;
}

sub blockquote_end
{
    my $self = shift;
    $self->vspace(1);
     # assert one line's worth of vertical space at blockquote-end
    $self->adjust_lm( -2 );
    $self->adjust_rm( +2 );
}

sub address_start
{
    my $self = shift;
    $self->vspace(1);
     # assert one line's worth of vertical space at address-para-start
    $self->i_start(@_);
    1;
}

sub address_end
{
    my $self = shift;
    $self->i_end(@_);
     # assert one line's worth of vertical space at address-para-end
    $self->vspace(1);
}

# Handling of list elements

sub ul_start
{
    my $self = shift;
    $self->vspace(1);
     # assert one line's worth of vertical space at ul-start
    $self->adjust_lm( +2 );
    1;
}

sub ul_end
{
    my $self = shift;
    $self->adjust_lm( -2 );
     # assert one line's worth of vertical space at ul-end
    $self->vspace(1);
}

sub li_start
{
    my $self = shift;
    $self->bullet( shift->attr('_bullet') || '' );
    $self->adjust_lm(+2);
    1;
}

sub bullet
{
    shift->out(@_);
}

sub li_end
{
    my $self = shift;
    $self->vspace(1);
    $self->adjust_lm( -2);
}

sub menu_start      { shift->ul_start(@_) }
sub menu_end        { shift->ul_end(@_) }
sub  dir_start      { shift->ul_start(@_) }
sub  dir_end        { shift->ul_end(@_) }

sub ol_start
{
    my $self = shift;

    $self->vspace(1);
    $self->adjust_lm(+2);
    1;
}

sub ol_end
{
    my $self = shift;
    $self->adjust_lm(-2);
    $self->vspace(1);
}


sub dl_start
{
    my $self = shift;
    # $self->adjust_lm(+2);
    $self->vspace(1);
     # assert one line's worth of vertical space at dl-start
    1;
}

sub dl_end
{
    my $self = shift;
    # $self->adjust_lm(-2);
    $self->vspace(1);
     # assert one line's worth of vertical space at dl-end
}


sub dt_start
{
    my $self = shift;
    $self->vspace(1);
     # assert one line's worth of vertical space at dt-start
    1;
}

sub dt_end
{
}


sub dd_start
{
    my $self = shift;
    $self->adjust_lm(+6);
    $self->vspace(0);
     # hm, what's that do?  nothing?
    1;
}

sub dd_end
{
    my $self = shift;
    $self->vspace(1);
     # assert one line's worth of vertical space at dd-end
    $self->adjust_lm(-6);
}

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# And now some things that are basically sane fall-throughs for classes
#  that don't really handle tables or forms specially...

# Things not formatted at all
sub input_start    { 0; }
sub textarea_start { 0; }
sub select_start   { 0; }
sub option_start   { 0; }

sub td_start {
  my $self = shift;

  push @{$self->{'center_stack'}}, $self->{'center'};
  $self->{center} = 0;

  $self->p_start(@_);
}
sub td_end {
  my $self = shift;
  $self->{'center'} = pop @{$self->{'center_stack'}};
  $self->p_end(@_);
}

sub th_start {
  my $self = shift;

  push @{$self->{'center_stack'}}, $self->{'center'};
  $self->{center} = 0;

  $self->p_start(@_);
  $self->b_start(@_);
}
sub th_end {
  my $self = shift;
  $self->b_end(@_);
  $self->{'center'} = pop @{$self->{'center_stack'}};
  $self->p_end(@_);
}

# But if you wanted to just SKIP tables and forms, you'd do this:
#  sub table_start { shift->out('[TABLE NOT SHOWN]'); 0; }
#  sub form_start  { shift->out('[FORM NOT SHOWN]');  0; }

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

sub textflow
{
    my $self = shift;
    if ($self->{pre}) {
    # Strip one leading and one trailing newline so that a <pre>
    #  tag can be placed on a line of its own without causing extra
    #  vertical space as part of the preformatted text.
    $_[0] =~ s/\n$//;
    $_[0] =~ s/^\n//;
    $self->pre_out( $_[0] );
    } else {
    for (split(/(\s+)/, $_[0])) {
        next unless length $_;
        $self->out($_);
    }
    }
}



sub vspace
{
    # This method sets the vspace attribute.  When vspace is
    # defined, then a new line should be started.  If vspace
    # is a nonzero value, then that should be taken as the
    # number of lines to be skipped before following text
    # is written out.
    #
    # You may think it odd to conflate the two concepts of
    # ending this paragraph, and asserting how much space should
    # follow; but it happens to work out pretty well.

    my($self, $min, $add) = @_;
    my $old = $self->{vspace};
    if (defined $old) {
    my $new = $old;
    $new += $add || 0;
    $new = $min if $new < $min;
    $self->{vspace} = $new;
    } else {
    $self->{vspace} = $min;
        DEBUG > 1 and print " vspace not set, so setting to $min\n";
    #my $new = $add || 0;
    #$new = $min if $new < $min;
    #$self->{vspace} = $new;
    }
    DEBUG > 1 and print " vspace now set to $min\n";
    $old;
}

sub collect
{
    push(@{shift->{output}}, @_);
}

#``````````````````````````````````````````````````````````````````````````

sub out  # Output a word
{
    # my($self, $text) = @_;
    # $text =~ tr/\xA0\xAD/ /d;
      # The 0xAD-killing is if you don't support anything like a soft hyphen
      #  in your destination format

    confess "Must be overridden by subclass";
}

sub pre_out
{
    confess "Must be overridden by subclass";
}


sub adjust_lm
{
    confess "Must be overridden by subclass";
}

sub adjust_rm
{
    confess "Must be overridden by subclass";
}


#``````````````````````````````````````````````````````````````````````````


1;

__END__
=pod

=for test_synopsis 1;
__END__

=for stopwords formatters

=head1 NAME

HTML::Formatter - Base class for HTML formatters

=head1 VERSION

version 2.05

=head1 SYNOPSIS

  use HTML::FormatSomething;
  my $infile  = "whatever.html";
  my $outfile = "whatever.file";
  open OUT, ">$outfile"
   or die "Can't write-open $outfile: $!\n";

  print OUT HTML::FormatSomething->format_file(
    $infile,
      'option1' => 'value1',
      'option2' => 'value2',
      ...
  );
  close(OUT);

=head1 DESCRIPTION

HTML::Formatter is a base class for classes that take HTML
and format it to some output format.  When you take an object
of such a base class and call C<< $formatter->format( $tree ) >>
with an HTML::TreeBuilder (or HTML::Element) object, they return
the

HTML formatters are able to format a HTML syntax tree into various
printable formats.  Different formatters produce output for different
output media.  Common for all formatters are that they will return the
formatted output when the format() method is called.  The format()
method takes a HTML::Element object (usually the HTML::TreeBuilder
root object) as parameter.

=head1 METHODS

=head2 new

    my $formatter = FormatterClass->new(
        option1 => value1, option2 => value2, ...
    );

This creates a new formatter object with the given options.

=head2 format_file

=head2 format_from_file

    $string = FormatterClass->format_file(
        $html_source,
        option1 => value1, option2 => value2, ...
        );

Return a string consisting of the result of using the given class
to format the given HTML file according to the given (optional) options.
Internally it calls C<< SomeClass->new( ... )->format( ... ) >> on a new
HTML::TreeBuilder object based on the given HTML file.

=head2 format_string

=head2 format_from_string

    $string = FormatterClass->format_string(
        $html_source,
        option1 => value1, option2 => value2, ...
        );

Return a string consisting of the result of using the given class
to format the given HTML source according to the given (optional)
options. Internally it calls C<< SomeClass->new( ... )->format( ... ) >>
on a new HTML::TreeBuilder object based on the given source.

=head2 format

    my $render_string = $formatter->format( $html_tree_object );

This renders the given HTML object according to the options set for
$formatter.

After you've used a particular formatter object to format a particular
HTML tree object, you probably should not use either again.

=head1 SEE ALSO

The three specific formatters:-

=over

=item L<HTML::FormatText>

Format HTML into plain text

=item L<HTML::FormatPS>

Format HTML into postscript

=item L<HTML::FormatRTF>

Format HTML into Rich Text Format

=back

Also the HTML manipulation libraries used - L<HTML::TreeBuilder>,
L<HTML::Element> and L<HTML::Tree>

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

