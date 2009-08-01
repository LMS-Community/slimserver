package Module::Find;

use 5.006001;
use strict;
use warnings;

use File::Spec;
use File::Find;

our $VERSION = '0.06';

our $basedir = undef;
our @results = ();
our $prune = 0;

our @ISA = qw(Exporter);

our @EXPORT = qw(findsubmod findallmod usesub useall setmoduledirs);

=head1 NAME

Module::Find - Find and use installed modules in a (sub)category

=head1 SYNOPSIS

  use Module::Find;

  # use all modules in the Plugins/ directory
  @found = usesub Mysoft::Plugins;

  # use modules in all subdirectories
  @found = useall Mysoft::Plugins;

  # find all DBI::... modules
  @found = findsubmod DBI;

  # find anything in the CGI/ directory
  @found = findallmod CGI;
  
  # set your own search dirs (uses @INC otherwise)
  setmoduledirs(@INC, @plugindirs, $appdir);

=head1 DESCRIPTION

Module::Find lets you find and use modules in categories. This can be very 
useful for auto-detecting driver or plugin modules. You can differentiate
between looking in the category itself or in all subcategories.

If you want Module::Find to search in a certain directory on your 
harddisk (such as the plugins directory of your software installation),
make sure you modify C<@INC> before you call the Module::Find functions.

=head1 FUNCTIONS

=over

=item C<setmoduledirs(@directories)>

Sets the directories to be searched for modules. If not set, Module::Find
will use @INC. If you use this function, @INC will I<not> be included
automatically, so add it if you want it. Set to undef to revert to
default behaviour.

=cut

sub setmoduledirs {
    return @Module::Find::ModuleDirs = @_;
}

=item C<@found = findsubmod Module::Category>

Returns modules found in the Module/Category subdirectories of your perl 
installation. E.g. C<findsubmod CGI> will return C<CGI::Session>, but 
not C<CGI::Session::File> .

=cut

sub findsubmod(*) {
	$prune = 1;
		
	return _find($_[0]);
}

=item C<@found = findallmod Module::Category>

Returns modules found in the Module/Category subdirectories of your perl 
installation. E.g. C<findallmod CGI> will return C<CGI::Session> and also 
C<CGI::Session::File> .

=cut

sub findallmod(*) {
	$prune = 0;
	
	return _find($_[0]);
}

=item C<@found = usesub Module::Category>

Uses and returns modules found in the Module/Category subdirectories of your perl 
installation. E.g. C<usesub CGI> will return C<CGI::Session>, but 
not C<CGI::Session::File> .

=cut

sub usesub(*) {
	$prune = 1;
	
	my @r = _find($_[0]);
	
	foreach my $m (@r) {
		eval " require $m; import $m ; ";
		die $@ if $@;
	}
	
	return @r;
}

=item C<@found = useall Module::Category>

Uses and returns modules found in the Module/Category subdirectories of your perl 
installation. E.g. C<useall CGI> will return C<CGI::Session> and also 
C<CGI::Session::File> .

=cut

sub useall(*) {
	$prune = 0;
	
	my @r = _find($_[0]);
	
	foreach my $m (@r) {
		eval " require $m; import $m; ";
		die $@ if $@;
	}
	
	return @r;
}

# 'wanted' functions for find()
# you know, this would be a nice application for currying...
sub _wanted {
    my $name = File::Spec->abs2rel($_, $basedir);
    return unless $name && $name ne File::Spec->curdir();

    if (-d && $prune) {
        $File::Find::prune = 1;
        return;
    }

    return unless /\.pm$/ && -r;

    $name =~ s|\.pm$||;
    $name = join('::', File::Spec->splitdir($name));

    push @results, $name;
}


# helper functions for finding files

sub _find(*) {
    my ($category) = @_;
    return undef unless defined $category;

    my $dir = File::Spec->catdir(split(/::/, $category));

    my @dirs;
    if (defined @Module::Find::ModuleDirs) {
        @dirs = map { File::Spec->catdir($_, $dir) }
            @Module::Find::ModuleDirs;
    } else {
        @dirs = map { File::Spec->catdir($_, $dir) } @INC;
    }
    @results = ();

    foreach $basedir (@dirs) {
        	next unless -d $basedir;
    	
        find({wanted   => \&_wanted,
              no_chdir => 1}, $basedir);
    }

    # filter duplicate modules
    my %seen = ();
    @results = grep { not $seen{$_}++ } @results;

    @results = map "$category\::$_", @results;
    return @results;
}

=back

=head1 HISTORY

=over 8

=item 0.01, 2004-04-22

Original version; created by h2xs 1.22

=item 0.02, 2004-05-25

Added test modules that were left out in the first version. Thanks to
Stuart Johnston for alerting me to this.

=item 0.03, 2004-06-18

Fixed a bug (non-localized $_) by declaring a loop variable in use functions.
Thanks to Stuart Johnston for alerting me to this and providing a fix.

Fixed non-platform compatibility by using File::Spec.
Thanks to brian d foy.

Added setmoduledirs and updated tests. Idea shamelessly stolen from
...errm... inspired by brian d foy.

=item 0.04, 2005-05-20

Added POD tests.

=item 0.05, 2005-11-30

Fixed issue with bugfix in PathTools-3.14.

=item 0.06, 2008-01-26

Module::Find now won't report duplicate modules several times anymore (thanks to Uwe Všlker for the report and the patch)

=back

=head1 SEE ALSO

L<perl>

=head1 AUTHOR

Christian Renz, E<lt>crenz@web42.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2004-2008 by Christian Renz <crenz@web42.com>. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut

1;
