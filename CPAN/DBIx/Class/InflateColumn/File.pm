package DBIx::Class::InflateColumn::File;

use strict;
use warnings;
use base 'DBIx::Class';
use File::Path;
use File::Copy;
use Path::Class;

__PACKAGE__->load_components(qw/InflateColumn/);

sub register_column {
    my ($self, $column, $info, @rest) = @_;
    $self->next::method($column, $info, @rest);
    return unless defined($info->{is_file_column});

    $self->inflate_column($column => {
        inflate => sub { 
            my ($value, $obj) = @_;
            $obj->_inflate_file_column($column, $value);
        },
        deflate => sub {
            my ($value, $obj) = @_;
            $obj->_save_file_column($column, $value);
        },
    });
}

sub _file_column_file {
    my ($self, $column, $filename) = @_;

    my $column_info = $self->column_info($column);

    return unless $column_info->{is_file_column};

    my $id = $self->id || $self->throw_exception(
        'id required for filename generation'
    );

    $filename ||= $self->$column->{filename};
    return Path::Class::file(
        $column_info->{file_column_path}, $id, $filename,
    );
}

sub delete {
    my ( $self, @rest ) = @_;

    for ( $self->columns ) {
        if ( $self->column_info($_)->{is_file_column} ) {
            rmtree( [$self->_file_column_file($_)->dir], 0, 0 );
            last; # if we've deleted one, we've deleted them all
        }
    }

    return $self->next::method(@rest);
}

sub insert {
    my $self = shift;

    # cache our file columns so we can write them to the fs
    # -after- we have a PK
    my %file_column;
    for ( $self->columns ) {
        if ( $self->column_info($_)->{is_file_column} ) {
            $file_column{$_} = $self->$_;
            $self->store_column($_ => $self->$_->{filename});
        }
    }

    $self->next::method(@_);

    # write the files to the fs
    while ( my ($col, $file) = each %file_column ) {
        $self->_save_file_column($col, $file);
    }

    return $self;
}


sub _inflate_file_column {
    my ( $self, $column, $value ) = @_;

    my $fs_file = $self->_file_column_file($column, $value);

    return { handle => $fs_file->open('r'), filename => $value };
}

sub _save_file_column {
    my ( $self, $column, $value ) = @_;

    return unless ref $value;

    my $fs_file = $self->_file_column_file($column, $value->{filename});
    mkpath [$fs_file->dir];

    # File::Copy doesn't like Path::Class (or any for that matter) objects,
    # thus ->stringify (http://rt.perl.org/rt3/Public/Bug/Display.html?id=59650)
    File::Copy::copy($value->{handle}, $fs_file->stringify);

    $self->_file_column_callback($value, $self, $column);

    return $value->{filename};
}

=head1 NAME

DBIx::Class::InflateColumn::File -  map files from the Database to the filesystem.

=head1 SYNOPSIS

In your L<DBIx::Class> table class:

    __PACKAGE__->load_components( "PK::Auto", "InflateColumn::File", "Core" );

    # define your columns
    __PACKAGE__->add_columns(
        "id",
        {
            data_type         => "integer",
            is_auto_increment => 1,
            is_nullable       => 0,
            size              => 4,
        },
        "filename",
        {
            data_type           => "varchar",
            is_file_column      => 1,
            file_column_path    =>'/tmp/uploaded_files',
            # or for a Catalyst application 
            # file_column_path  => MyApp->path_to('root','static','files'),
            default_value       => undef,
            is_nullable         => 1,
            size                => 255,
        },
    );


In your L<Catalyst::Controller> class:

FileColumn requires a hash that contains L<IO::File> as handle and the file's
name as name.

    my $entry = $c->model('MyAppDB::Articles')->create({ 
        subject => 'blah',
        filename => { 
            handle => $c->req->upload('myupload')->fh, 
            filename => $c->req->upload('myupload')->basename 
        },
        body => '....'
    });
    $c->stash->{entry}=$entry;


And Place the following in your TT template

    Article Subject: [% entry.subject %]
    Uploaded File: 
    <a href="/static/files/[% entry.id %]/[% entry.filename.filename %]">File</a>
    Body: [% entry.body %]

The file will be stored on the filesystem for later retrieval.  Calling delete
on your resultset will delete the file from the filesystem.  Retrevial of the
record automatically inflates the column back to the set hash with the
IO::File handle and filename.

=head1 DESCRIPTION

InflateColumn::File

=head1 METHODS

=head2 _file_column_callback ($file,$ret,$target)

method made to be overridden for callback purposes.

=cut

sub _file_column_callback {}

=head1 AUTHOR

Victor Igumnov

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
