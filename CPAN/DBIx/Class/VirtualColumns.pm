# ============================================================================
package DBIx::Class::VirtualColumns;
# ============================================================================
use strict;
use warnings;

use base qw(DBIx::Class);

our $VERSION = '1.03';

__PACKAGE__->mk_classdata('_virtual_columns');

=encoding utf8

=head1 NAME

DBIx::Class::VirtualColumns - Add virtual columns to DBIx::Class schemata

=head1 SYNOPSIS

 package Your::Schema::Class;
 use strict;
 use warnings;
 
 use base 'DBIx::Class';
 
 __PACKAGE__->load_components(
   "VirtualColumns",
   "PK",
   "Core",
 );
 
 __PACKAGE__->table("sometable");
 __PACKAGE__->add_columns(qw/dbcol1 dbcol2/);
 __PACKAGE__->add_virtual_columns(qw/vcol1 vcol2 vcol3/);
 
 # =========================================================
 # Somewhere else
 
 my $item = $schema->resultset('Artist')->find($id);
 $item->vcol1('test'); # Set 'test'
 $item->get_column('vcol1'); # Return 'test'
 
 my $otheritem = $schema->resultset('Artist')->create({
     dbcol1 => 'value1',
     dbcol2 => 'value2',
     vcol1  => 'value3',
     vcol2  => 'value4',
 });
 
 $otheritem->vcol1(); # Now is 'value3'
 
 # Get the column metadata just like for a regular DBIC column
 my $info = $result_source->column_info('vcol1');

=head1 DESCRIPTION

This module allows to specify 'virtual columns' in DBIx::Class schema
classes. Virtual columns behave almost like regular columns but are not
stored in the database. They may be used to store temporary information in
the L<DBIx::Class::Row> object and without introducting an additional
interface.

Most L<DBIx::Class> methods like C<set_column>, C<set_columns>, C<get_column>,
C<get_columns>, C<column_info>, ... will work with regular as well as 
virtual columns.

=head1 USAGE

Use this module if you want to add 'virtual' columns to a DBIC class 
which behave like real columns (e.g. if you want to use the C<set_column>, 
C<get_column> methods)

However if you only want to add non-column data to L<DBIx::Class::Row> 
objects, then there are easier/better ways:

 __PACKAGE__->mk_group_accessors(simple => qw(foo bar baz));

=head1 METHODS

=head2 add_virtual_columns 

Adds virtual columns to the result source. If supplied key => hashref pairs,
uses the hashref as the column_info for that column. Repeated calls of this 
method will add more columns, not replace them.

 $table->add_virtual_columns(qw/column1 column2/); 
 OR 
 $table->add_virtual_columns(column1 => \%column1_info, column2 => \%column2_info, ...); 

The column names given will be created as accessor methods on your 
C<DBIx::Class::Row objects>, you can change the name of the accessor by 
supplying an "accessor" in the column_info hash. 

The following options are currently recognised/used by 
DBIx::Class::VirtualColumns:

=over

=item * accessor

Use this to set the name of the accessor method for this column. If not set, 
the name of the column will be used.

=back

=cut

sub add_virtual_columns {
    my $self = shift;
    my @columns = @_;
    
    $self->_virtual_columns( {} ) 
        unless defined $self->_virtual_columns() ;
    
    # Add columns & accessors
    while (my $column = shift @columns) {
        my $column_info = ref $columns[0] ? shift(@columns) : {};
        
        # Check column
        $self->throw_exception("Cannot override existing column '$column' with virtual one")
            if ($self->has_column($column) or exists $self->_virtual_columns->{$column});

        $self->_virtual_columns->{$column} = $column_info;
        
        my $accessor = $column_info->{accessor} || $column;
        
        # Add default acceccor 
        no strict 'refs';
        *{$self.'::'.$accessor} = sub {
            my $self = shift;
            return $self->get_column($column) unless @_;
            $self->set_column($column, shift);
        };
        
    }
}

=head2 add_virtual_column

Shortcut for L<add_virtual_columns>

=cut

sub add_virtual_column { shift->add_virtual_columns(@_) }

=head2 has_any_column

Returns true if the source has a virtual or regular column of this name, 
false otherwise.

=cut

sub has_any_column {
    my $self = shift;
    my $column = shift;
    return ($self->_virtual_columns->{$column} || 
        $self->has_column($column)) ? 1:0;
}

=head2 has_virtual_column

Returns true if the source has a virtual column of this name, false otherwise.

=cut

sub has_virtual_column {
    my $self = shift;
    my $column = shift;
    return (exists $self->_virtual_columns->{$column}) ? 1:0
}

=head2 remove_virtual_columns

 $table->remove_columns(qw/col1 col2 col3/);
  
Removes virtual columns from the result source.

=cut

sub remove_virtual_columns {
    my $self = shift;
    my @columns = @_;
    
    foreach my $column  (@columns)  {
        delete $self->_virtual_columns->{$column};
    }
}

=head2 remove_virtual_column

Shortcut for L<remove_virtual_columns>

=cut

sub remove_virtual_column { shift->remove_virtual_columns(@_) }

=head2 _virtual_filter

Splits attributes for regular and virtual columns

=cut

sub _virtual_filter {
    my ($self,$attrs) = @_;  

    if ( !$self->_virtual_columns ) {
        $self->_virtual_columns( {} );
    }
    
    my $virtual_attrs = {};
    my $main_attrs = {};
    foreach my $attr (keys %$attrs) {
        if (exists $self->_virtual_columns->{$attr}) {
            $virtual_attrs->{$attr} = $attrs->{$attr};
        } else {
            $main_attrs->{$attr} = $attrs->{$attr};
        }
    }
    return ($virtual_attrs,$main_attrs);
}

=head2 new

Overloaded method. L<DBIx::Class::Row/"new">

=cut

sub new {
    my ( $class, $attrs ) = @_;
    
    # Split main and virtual values
    my ($virtual_attrs,$main_attrs) = $class->_virtual_filter($attrs);

    # Call new method
    my $return = $class->next::method($main_attrs);
    
    # Prefill localized data
    $return->{_virtual_values} = {};
    
    # Set localized data
    while ( my($key,$value) = each %$virtual_attrs ) {
        $return->store_column($key,$value);
    }
    
    return $return;
}

=head2 get_column

Overloaded method. L<DBIx::Class::Row/"get_colum">

=cut

sub get_column {
    my ($self, $column) = @_;

    # Check if a virtual colum has been requested
    if (defined $self->_virtual_columns
        && exists $self->_virtual_columns->{$column}) {
        return $self->{_virtual_values}{$column};
    }

    return $self->next::method($column);
}

=head2 get_columns

Overloaded method. L<DBIx::Class::Row/"get_colums">

=cut

sub get_columns {
    my $self = shift;
    
    return $self->next::method(@_) unless $self->in_storage;
    my %data = $self->next::method(@_);
    
    if (defined $self->_virtual_columns) {
        foreach my $column (keys %{$self->_virtual_columns}) {
            $data{$column} = $self->{_virtual_values}{$column};
        }
    }
    return %data;
}

=head2 store_column

Overloaded method. L<DBIx::Class::Row/"store_column">

=cut

sub store_column {
    my ($self, $column, $value) = @_;

    # Check if a localized colum has been requested
    if (defined $self->_virtual_columns
        && exists $self->_virtual_columns->{$column}) {
        return $self->{_virtual_values}{$column} = $value;
    }

    return $self->next::method($column, $value);
}

=head2 set_column

Overloaded method. L<DBIx::Class::Row/"set_column">

=cut

sub set_column {
    my ($self, $column, $value) = @_;

    if (defined $self->_virtual_columns
        && exists $self->_virtual_columns->{$column}) {
        return $self->{_virtual_values}{$column} = $value;
    }
    return $self->next::method($column, $value);
}

=head2 column_info

Overloaded method. L<DBIx::Class::ResultSource/"column_info">

Additionally returns the HASH key 'virtual' which indicates if the requested
column is virtual or not.

=cut

sub column_info {
    my ($self, $column) = @_;

    # Fetch localized column info
    if (defined $self->_virtual_columns
        && exists $self->_virtual_columns->{$column}) {
        my $column_info = $self->_virtual_columns->{$column};
        $column_info->{virtual} = 1;
        return $column_info;
    }
    
    my $column_info = $self->next::method($column);
    $column_info->{virtual} = 0;
    return $column_info;
}


=head2 update

Overloaded method. L<DBIx::Class::Row/"update">

=cut

sub update {
    my $self = shift;
    my $attr = shift;
 
    # Filter localized values
    my ($virtual_attrs,$main_attrs) = $self->_virtual_filter($attr);
    
    # Do regular update
    $self->next::method($main_attrs);
    
    if (scalar %{$virtual_attrs}) {
        while ( my($column,$value) = each %$virtual_attrs ) {
            $self->{_virtual_values}{$column} = $value;
        }
    }
    return $self;
}

=head1 CAVEATS

The best way to add non-column data to DBIC objects is to use 
L<Class::Accessor::Grouped>. 

 __PACKAGE__->mk_group_accessors(simple => qw(foo bar baz));

Use L<DBIx::Class::VirtualColumns> only if you rely on L<DBIx::Class::Row> 
methods like C<set_column>, C<get_column>, ... 

=head1 SUPPORT

This module was just a proof of concept, and is not actively developed 
anymore. Patches are still welcome though.

Please report any bugs to 
C<bug-dbix-class-virtualcolumns@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/Public/Bug/Report.html?Queue=DBIx::Class::VirtualColumns>.
I will be notified, and then you'll automatically be notified of progress on 
your report as I make changes.

=head1 AUTHOR

    Maroš Kollár
    CPAN ID: MAROS
    maros [at] k-1.com
    L<http://www.revdev.at>

=head1 ACKNOWLEDGEMENTS 

This module was written for Revdev L<http://www.revdev.at>, a nice litte
software company I run with Koki and Domm (L<http://search.cpan.org/~domm/>).

=head1 COPYRIGHT

DBIx::Class::VirtualColumns is Copyright (c) 2008 Maroš Kollár 
- L<http://www.revdev.at>

This program is free software; you can redistribute it and/or modify it under 
the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut

"This ist virtually the end of the package";