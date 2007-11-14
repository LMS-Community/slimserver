# $Id: Find.pm 8491 2006-07-18 21:23:19Z andy $
#
# Copyright (c) 2000 Michael G. Schwern.  All rights reserved.  This
# program is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.

package URI::Find;

require 5.005;

use strict;
use base qw(Exporter);
use vars qw($VERSION @EXPORT);

$VERSION	= '0.16';
@EXPORT		= qw(find_uris);

use constant YES => (1==1);
use constant NO  => !YES;

use Carp	qw(croak);
use URI::URL;

require URI;

my($schemeRe) = $URI::scheme_re;
my($uricSet)  = $URI::uric;

# We need to avoid picking up 'HTTP::Request::Common' so we have a
# subset of uric without a colon ("I have no colon and yet I must poop")
my($uricCheat) = __PACKAGE__->uric_set;
$uricCheat =~ tr/://d;

# Identifying characters accidentally picked up with a URI.
my($cruftSet) = q{]),.'";}; #'#


=head1 NAME

  URI::Find - Find URIs in arbitrary text


=head1 SYNOPSIS

  require URI::Find;

  my $finder = URI::Find->new(\&callback);

  $how_many_found = $finder->find(\$text);


=head1 DESCRIPTION

This module does one thing: Finds URIs and URLs in plain text.  It finds
them quickly and it finds them B<all> (or what URI::URL considers a URI
to be.)  It only finds URIs which include a scheme (http:// or the
like), for something a bit less strict have a look at
L<URI::Find::Schemeless|URI::Find::Schemeless>.

For a command-line interface, see Darren Chamberlain's C<urifind>
script.  It's available from his CPAN directory,
L<http://www.cpan.org/authors/id/D/DA/DARREN/>.

=head2 Public Methods

=over 4

=item B<new>

  my $finder = URI::Find->new(\&callback);

Creates a new URI::Find object.

&callback is a function which is called on each URI found.  It is
passed two arguments, the first is a URI::URL object representing the
URI found.  The second is the original text of the URI found.  The
return value of the callback will replace the original URI in the
text.

=cut

sub new {
    @_ == 2 || __PACKAGE__->badinvo;
    my($proto, $callback) = @_;
    my($class) = ref $proto || $proto;
    my $self = bless {}, $class;

    $self->{callback} = $callback;

    return $self;
}

=item B<find>

  my $how_many_found = $finder->find(\$text);

$text is a string to search and possibly modify with your callback.

=cut

sub find {
    @_ == 2 || __PACKAGE__->badinvo;
    my($self, $r_text) = @_;

    my $urlsfound = 0;

    # Don't assume http.
    my $old_strict = URI::URL::strict(1);

    # Yes, evil.  Basically, look for something vaguely resembling a URL,
    # then hand it off to URI::URL for examination.  If it passes, throw
    # it to a callback and put the result in its place.
    local $SIG{__DIE__} = 'DEFAULT';
    my $uri_cand;
    my $uri;

    my $uriRe = sprintf '(?:%s|%s)', $self->uri_re, $self->schemeless_uri_re;

    $$r_text =~ s{(<$uriRe>|$uriRe)}{
        my($orig_match) = $1;

        # A heruristic.  Often you'll see things like:
        # "I saw this site, http://www.foo.com, and its really neat!"
        # or "Foo Industries (at http://www.foo.com)"
        # We want to avoid picking up the trailing paren, period or comma.
        # Of course, this might wreck a perfectly valid URI, more often than
        # not it corrects a parse mistake.
        $orig_match = $self->decruft($orig_match);

        if( my $uri = $self->_is_uri(\$orig_match) ) { # Its a URI.
            $urlsfound++;

            # Don't forget to put any cruft we accidentally matched back.
            $self->recruft($self->{callback}->($uri, $orig_match));
        }
        else {                        # False alarm.
            # Again, don't forget the cruft.
            $self->recruft($orig_match);
        }
    }eg;

    URI::URL::strict($old_strict);
    return $urlsfound;
}

=back

=head2 Protected Methods

I got a bunch of mail from people asking if I'd add certain features
to URI::Find.  Most wanted the search to be less restrictive, do more
heuristics, etc...  Since many of the requests were contradictory, I'm
letting people create their own custom subclasses to do what they
want.

The following are methods internal to URI::Find which a subclass can
override to change the way URI::Find acts.  They are only to be called
B<inside> a URI::Find subclass.  Users of this module are NOT to use
these methods.

=over

=item B<uri_re>

  my $uri_re = $self->uri_re;

Returns the regex for finding absolute, schemed URIs
(http://www.foo.com and such).  This, combined with
schemeless_uri_re() is what finds candidate URIs.

Usually this method does not have to be overridden.

=cut

sub uri_re {
    @_ == 1 || __PACKAGE__->badinvo;
    my($self) = shift;
    return sprintf '%s:[%s][%s#]*', $schemeRe,
                                    $uricCheat,
                                    $self->uric_set;
}

=item B<schemeless_uri_re>

  my $schemeless_re = $self->schemeless_uri_re;

Returns the regex for finding schemeless URIs (www.foo.com and such) and
other things which might be URIs.  By default this will match nothing
(though it used to try to find schemeless URIs which started with C<www>
and C<ftp>).

Many people will want to override this method.  See L<URI::Find::Schemeless>
for a subclass does a reasonable job of finding URIs which might be missing
the scheme.

=cut

sub schemeless_uri_re {
    @_ == 1 || __PACKAGE__->badinvo;
    my($self) = shift;
    return qr/\b\B/; # match nothing
}

=item B<uric_set>

  my $uric_set = $self->uric_set;

Returns a set matching the 'uric' set defined in RFC 2396 suitable for
putting into a character set ([]) in a regex.

You almost never have to override this.

=cut

sub uric_set {
    @_ == 1 || __PACKAGE__->badinvo;
    return $uricSet;
}

=item B<cruft_set>

  my $cruft_set = $self->cruft_set;

Returns a set of characters which are considered garbage.  Used by
decruft().

=cut

sub cruft_set {
    @_ == 1 || __PACKAGE__->badinvo;
    return $cruftSet;
}

=item B<decruft>

  my $uri = $self->decruft($uri);

Sometimes garbage characters like periods and parenthesis get
accidentally matched along with the URI.  In order for the URI to be
properly identified, it must sometimes be "decrufted", the garbage
characters stripped.

This method takes a candidate URI and strips off any cruft it finds.

=cut

sub decruft {
    @_ == 2 || __PACKAGE__->badinvo;
    my($self, $orig_match) = @_;

    $self->{start_cruft} = '';
    $self->{end_cruft} = '';

    if( $orig_match =~ s/([\Q$cruftSet\E]+)$// ) {
        $self->{end_cruft} = $1;
    }

    return $orig_match;
}

=item B<recruft>

  my $uri = $self->recruft($uri);

This method puts back the cruft taken off with decruft().  This is necessary
because the cruft is destructively removed from the string before invoking
the user's callback, so it has to be put back afterwards.

=cut

#'#

sub recruft {
    @_ == 2 || __PACKAGE__->badinvo;
    my($self, $uri) = @_;

    return $self->{start_cruft} . $uri . $self->{end_cruft};
}

=item B<schemeless_to_schemed>

  my $schemed_uri = $self->schemeless_to_schemed($schemeless_uri);

This takes a schemeless URI and returns an absolute, schemed URI.  The
standard implementation supplies ftp:// for URIs which start with ftp.,
and http:// otherwise.

=cut

sub schemeless_to_schemed {
    @_ == 2 || __PACKAGE__->badinvo;
    my($self, $uri_cand) = @_;

    $uri_cand =~ s|^(<?)ftp\.|$1ftp://ftp\.|
	or $uri_cand =~ s|^(<?)|${1}http://|;

    return $uri_cand;
}

=item B<is_schemed>

  $obj->is_schemed($uri);

Returns whether or not the given URI is schemed or schemeless.  True for
schemed, false for schemeless.

=cut

sub is_schemed {
    @_ == 2 || __PACKAGE__->badinvo;
    my($self, $uri) = @_;
    return scalar $uri =~ /^<?$schemeRe:/;
}

=item I<badinvo>

  __PACKAGE__->badinvo($extra_levels, $msg)

This is used to complain about bogus subroutine/method invocations.
The args are optional.

=cut

sub badinvo {
    my $package	= shift;
    my $level	= @_ ? shift : 0;
    my $msg	= @_ ? " (" . shift() . ")" : '';
    my $subname	= (caller $level + 1)[3];
    croak "Bogus invocation of $subname$msg";
}

=head2 Old Functions

The old find_uri() function is still around and it works, but its
deprecated.


=back

=head1 EXAMPLES

Simply print the original URI text found and the normalized
representation.

  my $finder = URI::Find->new(
                      sub {
                          my($uri, $orig_uri) = @_;
                          print "The text '$orig_uri' represents '$uri'\n";
                          return $orig_uri;
                      });
  $finder->find(\$text);

Check each URI in document to see if it exists.

  use LWP::Simple;

  my $finder = URI::Find->new(sub {
                                  my($uri, $orig_uri) = @_;
                                  if( head $uri ) {
                                      print "$orig_uri is okay\n";
                                  }
                                  else {
                                      print "$orig_uri cannot be found\n";
                                  }
                                  return $orig_uri;
                              });
  $finder->find(\$text);


Turn plain text into HTML, with each URI found wrapped in an HTML anchor.

  use CGI qw(escapeHTML);

  $text = "<pre>\n" . escapeHTML($text) . "</pre>\n";
  my $finder = URI::Find->new(
                              sub {
                                  my($uri, $orig_uri) = @_;
                                  return qq|<a href="$uri">$orig_uri</a>|;
                              });
  $finder->find(\$text);


=head1 CAVEATS, BUGS, ETC...

RFC 2396 Appendix E suggests using the form '<http://www.foo.com>' or
'<URL:http://www.foo.com>' when putting URLs in plain text.  URI::Find
accomidates this suggestion and considers the entire thing (brackets
and all) to be part of the URL found.  This means that when
find_uris() sees '<URL:http://www.foo.com>' it will hand that entire
string to your callback, not just the URL.

NOTE:  The prototype on find_uris() is already getting annoying to me.
I might remove it in a future version.


=head1 SEE ALSO

  L<URI::Find::Schemeless>, L<URI::URL>, L<URI>,
  RFC 2396 (especially Appendix E)


=head1 AUTHOR

Michael G Schwern <schwern@pobox.com> with insight from Uri Gutman,
Greg Bacon, Jeff Pinyan, Roderick Schertler and others.

Currently maintained by Roderick Schertler <roderick@argon.org>.

=cut


sub _is_uri {
    @_ == 2 || __PACKAGE__->badinvo;
    my($self, $r_uri_cand) = @_;

    my $uri = $$r_uri_cand;

    # Translate schemeless to schemed if necessary.
    $uri = $self->schemeless_to_schemed($uri) unless
      $uri =~ /^<?$schemeRe:/;

    eval {
        $uri = URI::URL->new($uri);
    };

    if($@ || !defined $uri) {	# leave everything untouched, its not a URI.
        return NO;
    }
    else {			# Its a URI.
        return $uri;
    }
}


# Old interface.
sub find_uris (\$&) {
    @_ == 2 || __PACKAGE__->badinvo;
    my($r_text, $callback) = @_;

    my $self = __PACKAGE__->new($callback);
    return $self->find($r_text);
}



1;
