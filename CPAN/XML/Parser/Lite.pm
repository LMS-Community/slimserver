# ======================================================================
#
# Copyright (C) 2000-2001 Paul Kulchenko (paulclinger@yahoo.com)
# SOAP::Lite is free software; you can redistribute it
# and/or modify it under the same terms as Perl itself.
#
# $Id: Lite.pm,v 1.1.1.1 2002/11/01 14:53:57 paulclinger Exp $
#
# ======================================================================

package XML::Parser::Lite;

use strict;
use vars qw($VERSION);
$VERSION = sprintf("%d.%s", map {s/_//g; $_} q$Name: release-0_60-public $ =~ /-(\d+)_([\d_]+)/);

sub new { 
  my $self = shift;
  my $class = ref($self) || $self;
  return $self if ref $self;

  $self = bless {} => $class;
  my %parameters = @_;
  $self->setHandlers(); # clear first 
  $self->setHandlers(%{$parameters{Handlers} || {}});
  return $self;
}

sub setHandlers {
  my $self = shift; 
  no strict 'refs'; local $^W;
  # clear all handlers if called without parameters
  unless (@_) { foreach (qw(Start End Char Final Init)) { *$_ = sub {} } }
  while (@_) { my($name => $func) = splice(@_, 0, 2); *$name = defined $func ? $func : sub {} }
  return $self;
}

sub regexp {
  my $patch = shift || '';
  my $package = __PACKAGE__;

  # This parser is based on "shallow parser" http://www.cs.sfu.ca/~cameron/REX.html 

  # Robert D. Cameron "REX: XML Shallow Parsing with Regular Expressions",
  # Technical Report TR 1998-17, School of Computing Science, Simon Fraser University, November, 1998.
  # Copyright (c) 1998, Robert D. Cameron. 
  # The following code may be freely used and distributed provided that
  # this copyright and citation notice remains intact and that modifications
  # or additions are clearly identified.

  my $TextSE = "[^<]+";
  my $UntilHyphen = "[^-]*-";
  my $Until2Hyphens = "$UntilHyphen(?:[^-]$UntilHyphen)*-";
  my $CommentCE = "$Until2Hyphens>?";
  my $UntilRSBs = "[^\\]]*](?:[^\\]]+])*]+";
  my $CDATA_CE = "$UntilRSBs(?:[^\\]>]$UntilRSBs)*>";
  my $S = "[ \\n\\t\\r]+";
  my $NameStrt = "[A-Za-z_:]|[^\\x00-\\x7F]";
  my $NameChar = "[A-Za-z0-9_:.-]|[^\\x00-\\x7F]";
  my $Name = "(?:$NameStrt)(?:$NameChar)*";
  my $QuoteSE = "\"[^\"]*\"|'[^']*'";
  my $DT_IdentSE = "$S$Name(?:$S(?:$Name|$QuoteSE))*";
  my $MarkupDeclCE = "(?:[^\\]\"'><]+|$QuoteSE)*>";
  my $S1 = "[\\n\\r\\t ]";
  my $UntilQMs = "[^?]*\\?+";
  my $PI_Tail = "\\?>|$S1$UntilQMs(?:[^>?]$UntilQMs)*>";
  my $DT_ItemSE = "<(?:!(?:--$Until2Hyphens>|[^-]$MarkupDeclCE)|\\?$Name(?:$PI_Tail))|%$Name;|$S";
  my $DocTypeCE = "$DT_IdentSE(?:$S)?(?:\\[(?:$DT_ItemSE)*](?:$S)?)?>?";
  my $DeclCE = "--(?:$CommentCE)?|\\[CDATA\\[(?:$CDATA_CE)?|DOCTYPE(?:$DocTypeCE)?";
  my $PI_CE = "$Name(?:$PI_Tail)?";

  # these expressions were modified for backtracking and events
  my $EndTagCE = "($Name)(?{${package}::end(\$2)})(?:$S)?>";
  my $AttValSE = "\"([^<\"]*)\"|'([^<']*)'";
  my $ElemTagCE = "($Name)(?:$S($Name)(?:$S)?=(?:$S)?(?:$AttValSE)(?{[\@{\$^R||[]},\$4=>defined\$5?\$5:\$6]}))*(?:$S)?(/)?>(?{${package}::start(\$3,\@{\$^R||[]})})(?{\${7} and ${package}::end(\$3)})";
  my $MarkupSPE = "<(?:!(?:$DeclCE)?|\\?(?:$PI_CE)?|/(?:$EndTagCE)?|(?:$ElemTagCE)?)";

  # Next expression is under "black magic".
  # Ideally it should be '($TextSE)(?{${package}::char(\$1)})|$MarkupSPE',
  # but it doesn't work under Perl 5.005 and only magic with
  # (?:....)?? solved the problem. 
  # I would appreciate if someone let me know what is the right thing to do 
  # and what's the reason for all this magic. 
  # Seems like a problem related to (?:....)? rather than to ?{} feature.
  # Tests are in t/31-xmlparserlite.t if you decide to play with it.
  "(?:($TextSE)(?{${package}::char(\$1)}))$patch|$MarkupSPE";
}

sub compile { local $^W; 
  # try regexp as it should be, apply patch if doesn't work
  foreach (regexp(), regexp('??')) {
    eval qq{sub parse_re { use re "eval"; 1 while \$_[0] =~ m{$_}go }; 1} or die;
    last if eval { parse_re('<foo>bar</foo>'); 1 }
  };

  *compile = sub {};
}

setHandlers();
compile();

sub parse { 
  init(); 
  parse_re($_[1]);
  final(); 
}

my(@stack, $level);

sub init { 
  @stack = (); $level = 0;
  Init(__PACKAGE__, @_);  
}

sub final { 
  die "not properly closed tag '$stack[-1]'\n" if @stack;
  die "no element found\n" unless $level;
  Final(__PACKAGE__, @_) 
} 

sub start { 
  die "multiple roots, wrong element '$_[0]'\n" if $level++ && !@stack;
  push(@stack, $_[0]);
  Start(__PACKAGE__, @_); 
}

sub char { 
  Char(__PACKAGE__, $_[0]), return if @stack;

  # check for junk before or after element
  # can't use split or regexp due to limitations in ?{} implementation, 
  # will iterate with loop, but we'll do it no more than two times, so
  # it shouldn't affect performance
  for (my $i=0; $i < length $_[0]; $i++) {
    die "junk '$_[0]' @{[$level ? 'after' : 'before']} XML element\n"
      if index("\n\r\t ", substr($_[0],$i,1)) < 0; # or should '< $[' be there
  }
}

sub end { 
  pop(@stack) eq $_[0] or die "mismatched tag '$_[0]'\n";
  End(__PACKAGE__, $_[0]);
}

# ======================================================================

1;

__END__

=head1 NAME

XML::Parser::Lite - Lightweight regexp-based XML parser

=head1 SYNOPSIS

  use XML::Parser::Lite;
  
  $p1 = new XML::Parser::Lite;
  $p1->setHandlers(
    Start => sub { shift; print "start: @_\n" },
    Char => sub { shift; print "char: @_\n" },
    End => sub { shift; print "end: @_\n" },
  );
  $p1->parse('<foo id="me">Hello World!</foo>');

  $p2 = new XML::Parser::Lite
    Handlers => {
      Start => sub { shift; print "start: @_\n" },
      Char => sub { shift; print "char: @_\n" },
      End => sub { shift; print "end: @_\n" },
    }
  ;
  $p2->parse('<foo id="me">Hello <bar>cruel</bar> World!</foo>');

=head1 DESCRIPTION

This Perl module gives you access to XML parser with interface similar to
XML::Parser interface. Though only basic calls are supported (init, final,
start, char, and end) you should be able to use it in the same way you use
XML::Parser. Due to using experimantal regexp features it'll work only on
Perl 5.6 and may behave differently on different platforms.
 
=head1 SEE ALSO

 XML::Parser

=head1 COPYRIGHT

Copyright (C) 2000-2001 Paul Kulchenko. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

This parser is based on "shallow parser" http://www.cs.sfu.ca/~cameron/REX.html
Copyright (c) 1998, Robert D. Cameron.

=head1 AUTHOR

Paul Kulchenko (paulclinger@yahoo.com)

=cut
