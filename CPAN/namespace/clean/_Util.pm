###       !!!ACHTUNG!!!
#
# This module is to be loaded at configure time straight from the Makefile.PL
# in order to get access to some of the constants / utils
# None of the dependencies will be available yet at this point, so make
# sure to never use anything beyond what the minimum supported perl came with
# (no, relying on configure_requires is not ok)

package # hide from the pauses
  namespace::clean::_Util;

use warnings;
use strict;

use base 'Exporter';
our @EXPORT_OK = qw( DEBUGGER_NEEDS_CV_RENAME DEBUGGER_NEEDS_CV_PIVOT );

use constant DEBUGGER_NEEDS_CV_RENAME => ( ( "$]" > 5.008_008 ) and ( "$]" < 5.013_006 ) );
use constant DEBUGGER_NEEDS_CV_PIVOT => ( ( ! DEBUGGER_NEEDS_CV_RENAME ) and ( "$]" < 5.015_005 ) );

# FIXME - ideally this needs to be provided by some abstraction lib
# but we don't have that yet
BEGIN {
  #
  # Note - both get_subname and set_subname are only called by one block
  # which is compiled away unless CV_RENAME is true ( the 5.8.9 ~ 5.12 range ).
  # Hence we compile/provide the definitions here only when needed
  #
  DEBUGGER_NEEDS_CV_RENAME and ( eval <<'EOS' or die $@ );
{
  my( $sub_name_loaded, $sub_util_loaded );

  sub _namer_load_error {
    return '' if $sub_util_loaded or $sub_name_loaded;

    # if S::N is loaded first *and* so is B - then go with that, otherwise
    # prefer Sub::Util as S::U will provide a faster get_subname and will
    # not need further require() calls
    # this is rather arbitrary but remember this code exists only perls
    # between 5.8.9 ~ 5.13.5

    # when changing version also change in Makefile.PL
    my $sn_ver = 0.04;

    local $@;
    my $err = '';

    (
      ! (
        $INC{"B.pm"}
          and
        $INC{"Sub/Name.pm"}
          and
        eval { Sub::Name->VERSION($sn_ver) }
      )
        and
      eval { require Sub::Util }
        and
      # see https://github.com/moose/Moo/commit/dafa5118
      defined &Sub::Util::set_subname
        and
      $sub_util_loaded = 1
    )
      or
    (
      eval { require Sub::Name and Sub::Name->VERSION($sn_ver) }
        and
      $sub_name_loaded = 1
    )
      or
    $err = "When running under -d on this perl $], namespace::clean requires either Sub::Name $sn_ver or Sub::Util to be installed"
    ;

    $err;
  }

  sub set_subname {
    if( my $err = _namer_load_error() ) {
      die $err;
    }
    elsif( $sub_name_loaded ) {
      &Sub::Name::subname;
    }
    elsif( $sub_util_loaded ) {
      &Sub::Util::set_subname;
    }
    else {
      die "How the fuck did we get here? Read source and debug please!";
    }
  }

  sub get_subname {
    if(
      _namer_load_error()
        or
      ! $sub_util_loaded
    ) {
      require B;
      my $gv = B::svref_2object( $_[0] )->GV;
      join '::', $gv->STASH->NAME, $gv->NAME;
    }
    else {
      &Sub::Util::subname;
    }
  }
}
1;
EOS

}

1;
