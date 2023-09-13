package HTML::Tree;

=head1 NAME

HTML::Tree - build and scan parse-trees of HTML

=head1 VERSION

4.2

=cut

# HTML::Tree is basically just a happy alias to HTML::TreeBuilder.

use warnings;
use strict;

use HTML::TreeBuilder ();

use vars qw( $VERSION );
$VERSION = 4.2;

=head1 SYNOPSIS

    use HTML::TreeBuilder;
    my $tree = HTML::TreeBuilder->new();
    $tree->parse_file($filename);

        # Then do something with the tree, using HTML::Element
        # methods -- for example:

    $tree->dump

        # Finally:

    $tree->delete;

=cut

sub new {
    shift;
    unshift @_, 'HTML::TreeBuilder';
    goto &HTML::TreeBuilder::new;
}

sub new_from_file {
    shift;
    unshift @_, 'HTML::TreeBuilder';
    goto &HTML::TreeBuilder::new_from_file;
}

sub new_from_content {
    shift;
    unshift @_, 'HTML::TreeBuilder';
    goto &HTML::TreeBuilder::new_from_content;
}

1;
__END__

=head1 DESCRIPTION

HTML-Tree is a suite of Perl modules for making parse trees out of
HTML source.  It consists of mainly two modules, whose documentation
you should refer to: L<HTML::TreeBuilder|HTML::TreeBuilder>
and L<HTML::Element|HTML::Element>.

HTML::TreeBuilder is the module that builds the parse trees.  (It uses
HTML::Parser to do the work of breaking the HTML up into tokens.)

The tree that TreeBuilder builds for you is made up of objects of the
class HTML::Element.

If you find that you do not properly understand the documentation
for HTML::TreeBuilder and HTML::Element, it may be because you are
unfamiliar with tree-shaped data structures, or with object-oriented
modules in general. Sean Burke has written some articles for
I<The Perl Journal> (C<www.tpj.com>) that seek to provide that background.
The full text of those articles is contained in this distribution, as:

=over 4

=item L<HTML::Tree::AboutObjects|HTML::Tree::AboutObjects>

"User's View of Object-Oriented Modules" from TPJ17.

=item L<HTML::Tree::AboutTrees|HTML::Tree::AboutTrees>

"Trees" from TPJ18

=item L<HTML::Tree::Scanning|HTML::Tree::Scanning>

"Scanning HTML" from TPJ19

=back

Readers already familiar with object-oriented modules and tree-shaped
data structures should read just the last article.  Readers without
that background should read the first, then the second, and then the
third.

=head2 new

Redirects to HTML::TreeBuilder::new

=cut

=head2 new_from_file

Redirects to HTML::TreeBuilder::new_from_file

=cut

=head2 new_from_content

Redirects to HTML::TreeBuilder::new_from_content

=cut

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc HTML::Tree

    You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/HTML-Tree>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/HTML-Tree>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=HTML-Tree>

=item * Search CPAN

L<http://search.cpan.org/dist/HTML-Tree>

=back

=head1 SEE ALSO

L<HTML::TreeBuilder>, L<HTML::Element>, L<HTML::Tagset>,
L<HTML::Parser>, L<HTML::DOMbo>

The book I<Perl & LWP> by Sean M. Burke published by
O'Reilly and Associates, 2002.  ISBN: 0-596-00178-9

It has several chapters to do with HTML processing in general,
and HTML-Tree specifically.  There's more info at:

    http://www.oreilly.com/catalog/perllwp/

    http://www.amazon.com/exec/obidos/ASIN/0596001789

=head1 SOURCE REPOSITORY

HTML::Tree is maintained in Subversion hosted at perl.org.

    http://svn.perl.org/modules/HTML-Tree

The latest development work is always at:

    http://svn.perl.org/modules/HTML-Tree/trunk

Any patches sent should be diffed against this repository.

=head1 ACKNOWLEDGEMENTS

Thanks to Gisle Aas, Sean Burke and Andy Lester for their original work.

Thanks to Chicago Perl Mongers (http://chicago.pm.org) for their
patches submitted to HTML::Tree as part of the Phalanx project
(http://qa.perl.org/phalanx).

Thanks to the following people for additional patches and documentation:
Terrence Brannon, Gordon Lack, Chris Madsen and Ricardo Signes.

=head1 AUTHOR

Current Author:
	Jeff Fearn C<< <jfearn@cpan.org> >>.

Original HTML-Tree author:
	Gisle Aas.

Former Authors:
	Sean M. Burke.
	Andy Lester.
	Pete Krawczyk C<< <petek@cpan.org> >>.

=head1 COPYRIGHT

Copyright 1995-1998 Gisle Aas; 1999-2004 Sean M. Burke; 
2005 Andy Lester; 2006 Pete Krawczyk.  (Except the articles
contained in HTML::Tree::AboutObjects, HTML::Tree::AboutTrees, and
HTML::Tree::Scanning, which are all copyright 2000 The Perl Journal.)

Except for those three TPJ articles, the whole HTML-Tree distribution,
of which this file is a part, is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

Those three TPJ articles may be distributed under the same terms as
Perl itself.

The programs in this library are distributed in the hope that they
will be useful, but without any warranty; without even the implied
warranty of merchantability or fitness for a particular purpose.

=cut

