package DBI::Gofer::Request;

#   $Id: Request.pm 12536 2009-02-24 22:37:09Z Tim $
#
#   Copyright (c) 2007, Tim Bunce, Ireland
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.

use strict;

use DBI qw(neat neat_list);

use base qw(DBI::Util::_accessor);

our $VERSION = "0.012537";

use constant GOf_REQUEST_IDEMPOTENT => 0x0001;
use constant GOf_REQUEST_READONLY   => 0x0002;

our @EXPORT = qw(GOf_REQUEST_IDEMPOTENT GOf_REQUEST_READONLY);


__PACKAGE__->mk_accessors(qw(
    version
    flags
    dbh_connect_call
    dbh_method_call
    dbh_attributes
    dbh_last_insert_id_args
    sth_method_calls
    sth_result_attr
));
__PACKAGE__->mk_accessors_using(make_accessor_autoviv_hashref => qw(
    meta
));


sub new {
    my ($self, $args) = @_;
    $args->{version} ||= $VERSION;
    return $self->SUPER::new($args);
}


sub reset {
    my ($self, $flags) = @_;
    # remove everything except connect and version
    %$self = (
        version => $self->{version},
        dbh_connect_call => $self->{dbh_connect_call},
    );
    $self->{flags} = $flags if $flags;
}


sub init_request {
    my ($self, $method_and_args, $dbh) = @_;
    $self->reset( $dbh->{ReadOnly} ? GOf_REQUEST_READONLY : 0 );
    $self->dbh_method_call($method_and_args);
}


sub is_sth_request {
    return shift->{sth_result_attr};
}


sub statements {
    my $self = shift;
    my @statements;
    if (my $dbh_method_call = $self->dbh_method_call) {
        my $statement_method_regex = qr/^(?:do|prepare)$/;
        my (undef, $method, $arg1) = @$dbh_method_call;
        push @statements, $arg1 if $method && $method =~ $statement_method_regex;
    }
    return @statements;
}


sub is_idempotent {
    my $self = shift;

    if (my $flags = $self->flags) {
        return 1 if $flags & (GOf_REQUEST_IDEMPOTENT|GOf_REQUEST_READONLY);
    }

    # else check if all statements are SELECT statement that don't include FOR UPDATE
    my @statements = $self->statements;
    # XXX this is very minimal for now, doesn't even allow comments before the select
    # (and can't ever work for "exec stored_procedure_name" kinds of statements)
    # XXX it also doesn't deal with multiple statements: prepare("select foo; update bar")
    return 1 if @statements == grep {
                m/^ \s* SELECT \b /xmsi && !m/ \b FOR \s+ UPDATE \b /xmsi
             } @statements;

    return 0;
}


sub summary_as_text {
    my $self = shift;
    my ($context) = @_;
    my @s = '';

    if ($context && %$context) {
        my @keys = sort keys %$context;
        push @s, join(", ", map { "$_=>".$context->{$_} } @keys);
    }

    my ($method, $dsn, $user, $pass, $attr) = @{ $self->dbh_connect_call };
    $method ||= 'connect_cached';
    $pass = '***' if defined $pass;
    my $tmp = '';
    if ($attr) {
        $tmp = { %{$attr||{}} }; # copy so we can edit
        $tmp->{Password} = '***' if exists $tmp->{Password};
        $tmp = "{ ".neat_list([ %$tmp ])." }";
    }
    push @s, sprintf "dbh= $method(%s, %s)", neat_list([$dsn, $user, $pass]), $tmp;

    if (my $flags = $self->flags) {
        push @s, sprintf "flags: 0x%x", $flags;
    }

    if (my $dbh_attr = $self->dbh_attributes) {
        push @s, sprintf "dbh->FETCH: %s", @$dbh_attr
            if @$dbh_attr;
    }

    my ($wantarray, $meth, @args) = @{ $self->dbh_method_call };
    my $args = neat_list(\@args);
    $args =~ s/\n+/ /g;
    push @s, sprintf "dbh->%s(%s)", $meth, $args;

    if (my $lii_args = $self->dbh_last_insert_id_args) {
        push @s, sprintf "dbh->last_insert_id(%s)", neat_list($lii_args);
    }

    for my $call (@{ $self->sth_method_calls || [] }) {
        my ($meth, @args) = @$call;
        ($args = neat_list(\@args)) =~ s/\n+/ /g;
        push @s, sprintf "sth->%s(%s)", $meth, $args;
    }

    if (my $sth_attr = $self->sth_result_attr) {
        push @s, sprintf "sth->FETCH: %s", %$sth_attr
            if %$sth_attr;
    }

    return join("\n\t", @s) . "\n";
}


sub outline_as_text { # one-line version of summary_as_text
    my $self = shift;
    my @s = '';
    my $neatlen = 80;

    if (my $flags = $self->flags) {
        push @s, sprintf "flags=0x%x", $flags;
    }

    my (undef, $meth, @args) = @{ $self->dbh_method_call };
    push @s, sprintf "%s(%s)", $meth, neat_list(\@args, $neatlen);

    for my $call (@{ $self->sth_method_calls || [] }) {
        my ($meth, @args) = @$call;
        push @s, sprintf "%s(%s)", $meth, neat_list(\@args, $neatlen);
    }

    my ($method, $dsn) = @{ $self->dbh_connect_call };
    push @s, "$method($dsn,...)"; # dsn last as it's usually less interesting

    (my $outline = join("; ", @s)) =~ s/\s+/ /g; # squish whitespace, incl newlines
    return $outline;
}

1;

=head1 NAME

DBI::Gofer::Request - Encapsulate a request from DBD::Gofer to DBI::Gofer::Execute

=head1 DESCRIPTION

This is an internal class.

=head1 AUTHOR

Tim Bunce, L<http://www.tim.bunce.name>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, Tim Bunce, Ireland. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=cut
