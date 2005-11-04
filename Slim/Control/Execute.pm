package Slim::Control::Execute;

use strict;
use Carp;

use Slim::Utils::Misc;

=pod

    Contains the functions called by Slim::Control::Command::execute().

=cut

sub default {
	my($client, $parrayref, $callbackf, $callbackargs) = @_;
    confess "Called default handler: don't do that."
}

# this will be a lot nicer if we don't have to care about the return array.
sub pref {
	my($client, $parrayref, $callbackf, $callbackargs) = @_;

    # it would be nice not to have to preserve the array.
    my ($prefName, $newValue) = @{$parrayref}[0,1];

    if (defined($newValue) && $newValue ne '?' && !$::nosetup) {
        Slim::Utils::Prefs::set($prefName, $newValue);
    }

    $newValue = Slim::Utils::Prefs::get($prefName);
    $parrayref->[2] = $newValue;
    $::d_command && msg( "prefs(): Successfully set '$prefName' to '$newValue'\n" );
    return $parrayref;
}

sub rescan {
    confess "Called unimplemented command 'rescan'."
}

sub wipecache {
    confess "Called unimplemented command 'wipecache'."
}

1;
