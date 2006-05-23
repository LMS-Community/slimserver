package DBIx::Class::Validation;

use strict;
use warnings;

use base qw( DBIx::Class );
use English qw( -no_match_vars );

#local $^W = 0; # Silence C:D:I redefined sub errors.
# Switched to C::D::Accessor which doesn't do this. Hate hate hate hate.

our $VERSION = '0.01';

__PACKAGE__->mk_classdata( 'validation_module' => 'FormValidator::Simple' );
__PACKAGE__->mk_classdata( 'validation_profile'  );
__PACKAGE__->mk_classdata( 'validation_auto' => 1 );

sub validation_module {
    my $class = shift;
    my $module = shift;
    
    eval("use $module");
    $class->throw_exception("Unable to load the validation module '$module' because $EVAL_ERROR") if ($EVAL_ERROR);
    $class->throw_exception("The '$module' module does not support the check method") if (!$module->can('check'));
    
    $class->_validation_module_accessor( $module );
}

sub validation {
    my $class = shift;
    my %args = @_;
    
    $class->validation_module( $args{module} ) if (exists $args{module});
    $class->validation_profile( $args{profile} ) if (exists $args{profile});
    $class->validation_auto( $args{auto} ) if (exists $args{auto});
}

sub validate {
    my $self = shift;
    my %data = $self->get_columns();
    my $module = $self->validation_module();
    my $profile = $self->validation_profile();
    my $result = $module->check( \%data => $profile );
    return $result if ($result->success());
    $self->throw_exception( $result );
}

sub insert {
    my $self = shift;
    $self->validate if ($self->validation_auto());
    $self->next::method(@_);
}

sub update {
    my $self = shift;
    $self->validate if ($self->validation_auto());
    $self->next::method(@_);
}

1;
__END__

=head1 NAME

DBIx::Class::Validation - Validate all data before submitting to your database.

=head1 SYNOPSIS

In your base DBIC package:

  __PACKAGE__->load_components(qw/... Validation/);

And in your subclasses:

  __PACKAGE__->validation(
    module => 'FormValidator::Simple',
    profile => { ... },
    auto => 1,
  );

And then somewhere else:

  eval{ $obj->validate() };
  if( my $results = $EVAL_ERROR ){
    ...
  }

=head1 METHODS

=head2 validation

  __PACKAGE__->validation(
    module => 'FormValidator::Simple',
    profile => { ... },
    auto => 1,
  );

Calls validation_module(), validation_profile(), and validation_auto() if the corresponding 
argument is defined.

=head2 validation_module

  __PACKAGE__->validation_module('Data::FormValidator');

Sets the validation module to use.  Any module that supports a check() method just like 
Data::FormValidator's can be used here, such as FormValidator::Simple.

Defaults to FormValidator::Simple.

=head2 validation_profile

  __PACKAGE__->validation_profile(
    { ... }
  );

Sets the profile that will be passed to the validation module.

=head2 validation_auto

  __PACKAGE__->validation_auto( 1 );

This flag, when enabled, causes any updates or inserts of the class 
to call validate() before actually executing.

=head2 validate

  $obj->validate();

Validates all the data in the object against the pre-defined validation 
module and profile.  If there is a problem then a hard error will be 
thrown.  If you put the validation in an eval you can capture whatever 
the module's check() method returned.

=head2 auto_validate

  __PACKAGE__->auto_validate( 0 );

Turns on and off auto-validation.  This feature makes all UPDATEs and 
INSERTs call the validate() method before doing anything.  The default 
is for auto-validation to be on.

Defaults to on.

=head1 AUTHOR

Aran C. Deltac <bluefeet@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

