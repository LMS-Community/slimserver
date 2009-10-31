package DBIx::Class::InflateColumn::DateTime;

use strict;
use warnings;
use base qw/DBIx::Class/;
use Carp::Clan qw/^DBIx::Class/;

=head1 NAME

DBIx::Class::InflateColumn::DateTime - Auto-create DateTime objects from date and datetime columns.

=head1 SYNOPSIS

Load this component and then declare one or more 
columns to be of the datetime, timestamp or date datatype.

  package Event;
  __PACKAGE__->load_components(qw/InflateColumn::DateTime Core/);
  __PACKAGE__->add_columns(
    starts_when => { data_type => 'datetime' }
    create_date => { data_type => 'date' }
  );

NOTE: You B<must> load C<InflateColumn::DateTime> B<before> C<Core>. See
L<DBIx::Class::Manual::Component> for details.

Then you can treat the specified column as a L<DateTime> object.

  print "This event starts the month of ".
    $event->starts_when->month_name();

If you want to set a specific timezone and locale for that field, use:

  __PACKAGE__->add_columns(
    starts_when => { data_type => 'datetime', timezone => "America/Chicago", locale => "de_DE" }
  );

If you want to inflate no matter what data_type your column is,
use inflate_datetime or inflate_date:

  __PACKAGE__->add_columns(
    starts_when => { data_type => 'varchar', inflate_datetime => 1 }
  );

  __PACKAGE__->add_columns(
    starts_when => { data_type => 'varchar', inflate_date => 1 }
  );

It's also possible to explicitly skip inflation:

  __PACKAGE__->add_columns(
    starts_when => { data_type => 'datetime', inflate_datetime => 0 }
  );

NOTE: Don't rely on C<InflateColumn::DateTime> to parse date strings for you.
The column is set directly for any non-references and C<InflateColumn::DateTime>
is completely bypassed.  Instead, use an input parser to create a DateTime
object. For instance, if your user input comes as a 'YYYY-MM-DD' string, you can
use C<DateTime::Format::ISO8601> thusly:

  use DateTime::Format::ISO8601;
  my $dt = DateTime::Format::ISO8601->parse_datetime('YYYY-MM-DD');

=head1 DESCRIPTION

This module figures out the type of DateTime::Format::* class to 
inflate/deflate with based on the type of DBIx::Class::Storage::DBI::* 
that you are using.  If you switch from one database to a different 
one your code should continue to work without modification (though note
that this feature is new as of 0.07, so it may not be perfect yet - bug
reports to the list very much welcome).

If the data_type of a field is C<date>, C<datetime> or C<timestamp> (or
a derivative of these datatypes, e.g. C<timestamp with timezone>), this
module will automatically call the appropriate parse/format method for
deflation/inflation as defined in the storage class. For instance, for
a C<datetime> field the methods C<parse_datetime> and C<format_datetime>
would be called on deflation/inflation. If the storage class does not
provide a specialized inflator/deflator, C<[parse|format]_datetime> will
be used as a fallback. See L<DateTime::Format> for more information on
date formatting.

For more help with using components, see L<DBIx::Class::Manual::Component/USING>.

=cut

__PACKAGE__->load_components(qw/InflateColumn/);

=head2 register_column

Chains with the L<DBIx::Class::Row/register_column> method, and sets
up datetime columns appropriately.  This would not normally be
directly called by end users.

In the case of an invalid date, L<DateTime> will throw an exception.  To
bypass these exceptions and just have the inflation return undef, use
the C<datetime_undef_if_invalid> option in the column info:

    "broken_date",
    {
        data_type => "datetime",
        default_value => '0000-00-00',
        is_nullable => 1,
        datetime_undef_if_invalid => 1
    }

=cut

sub register_column {
  my ($self, $column, $info, @rest) = @_;
  $self->next::method($column, $info, @rest);
  return unless defined($info->{data_type});

  my $type;

  for (qw/date datetime timestamp/) {
    my $key = "inflate_${_}";

    next unless exists $info->{$key};
    return unless $info->{$key};

    $type = $_;
    last;
  }

  unless ($type) {
    $type = lc($info->{data_type});
    if ($type eq "timestamp with time zone" || $type eq "timestamptz") {
      $type = "timestamp";
      $info->{_ic_dt_method} ||= "timestamp_with_timezone";
    } elsif ($type eq "timestamp without time zone") {
      $type = "timestamp";
      $info->{_ic_dt_method} ||= "timestamp_without_timezone";
    } elsif ($type eq "smalldatetime") {
      $type = "datetime";
      $info->{_ic_dt_method} ||= "datetime";
    }
  }

  my $timezone;
  if ( defined $info->{extra}{timezone} ) {
    carp "Putting timezone into extra => { timezone => '...' } has been deprecated, ".
         "please put it directly into the '$column' column definition.";
    $timezone = $info->{extra}{timezone};
  }

  my $locale;
  if ( defined $info->{extra}{locale} ) {
    carp "Putting locale into extra => { locale => '...' } has been deprecated, ".
         "please put it directly into the '$column' column definition.";
    $locale = $info->{extra}{locale};
  }

  $locale   = $info->{locale}   if defined $info->{locale};
  $timezone = $info->{timezone} if defined $info->{timezone};

  my $undef_if_invalid = $info->{datetime_undef_if_invalid};

  if ($type eq 'datetime' || $type eq 'date' || $type eq 'timestamp') {
    # This shallow copy of %info avoids t/52_cycle.t treating
    # the resulting deflator as a circular reference.
    my %info = ( '_ic_dt_method' => $type , %{ $info } );

    if (defined $info->{extra}{floating_tz_ok}) {
      carp "Putting floating_tz_ok into extra => { floating_tz_ok => 1 } has been deprecated, ".
           "please put it directly into the '$column' column definition.";
      $info{floating_tz_ok} = $info->{extra}{floating_tz_ok};
    }

    $self->inflate_column(
      $column =>
        {
          inflate => sub {
            my ($value, $obj) = @_;

            my $dt = eval { $obj->_inflate_to_datetime( $value, \%info ) };
            if (my $err = $@ ) {
              return undef if ($undef_if_invalid);
              $self->throw_exception ("Error while inflating ${value} for ${column} on ${self}: $err");
            }

            $dt->set_time_zone($timezone) if $timezone;
            $dt->set_locale($locale) if $locale;
            return $dt;
          },
          deflate => sub {
            my ($value, $obj) = @_;
            if ($timezone) {
                carp "You're using a floating timezone, please see the documentation of"
                  . " DBIx::Class::InflateColumn::DateTime for an explanation"
                  if ref( $value->time_zone ) eq 'DateTime::TimeZone::Floating'
                      and not $info{floating_tz_ok}
                      and not $ENV{DBIC_FLOATING_TZ_OK};
                $value->set_time_zone($timezone);
                $value->set_locale($locale) if $locale;
            }
            $obj->_deflate_from_datetime( $value, \%info );
          },
        }
    );
  }
}

sub _flate_or_fallback
{
  my( $self, $value, $info, $method_fmt ) = @_;

  my $parser = $self->_datetime_parser;
  my $preferred_method = sprintf($method_fmt, $info->{ _ic_dt_method });
  my $method = $parser->can($preferred_method) ? $preferred_method : sprintf($method_fmt, 'datetime');
  return $parser->$method($value);
}

sub _inflate_to_datetime {
  my( $self, $value, $info ) = @_;
  return $self->_flate_or_fallback( $value, $info, 'parse_%s' );
}

sub _deflate_from_datetime {
  my( $self, $value, $info ) = @_;
  return $self->_flate_or_fallback( $value, $info, 'format_%s' );
}

sub _datetime_parser {
  shift->result_source->storage->datetime_parser (@_);
}

1;
__END__

=head1 USAGE NOTES

If you have a datetime column with an associated C<timezone>, and subsequently
create/update this column with a DateTime object in the L<DateTime::TimeZone::Floating>
timezone, you will get a warning (as there is a very good chance this will not have the
result you expect). For example:

  __PACKAGE__->add_columns(
    starts_when => { data_type => 'datetime', timezone => "America/Chicago" }
  );

  my $event = $schema->resultset('EventTZ')->create({
    starts_at => DateTime->new(year=>2007, month=>12, day=>31, ),
  });

The warning can be avoided in several ways:

=over

=item Fix your broken code

When calling C<set_time_zone> on a Floating DateTime object, the timezone is simply
set to the requested value, and B<no time conversion takes place>. It is always a good idea
to be supply explicit times to the database:

  my $event = $schema->resultset('EventTZ')->create({
    starts_at => DateTime->new(year=>2007, month=>12, day=>31, time_zone => "America/Chicago" ),
  });

=item Suppress the check on per-column basis

  __PACKAGE__->add_columns(
    starts_when => { data_type => 'datetime', timezone => "America/Chicago", floating_tz_ok => 1 }
  );

=item Suppress the check globally

Set the environment variable DBIC_FLOATING_TZ_OK to some true value.

=back

Putting extra attributes like timezone, locale or floating_tz_ok into extra => {} has been
B<DEPRECATED> because this gets you into trouble using L<DBIx::Class::Schema::Versioned>.
Instead put it directly into the columns definition like in the examples above. If you still
use the old way you'll see a warning - please fix your code then!

=head1 SEE ALSO

=over 4

=item More information about the add_columns method, and column metadata, 
      can be found in the documentation for L<DBIx::Class::ResultSource>.

=item Further discussion of problems inherent to the Floating timezone:
      L<Floating DateTimes|DateTime/Floating_DateTimes> 
      and L<< $dt->set_time_zone|DateTime/"Set" Methods >>

=back

=head1 AUTHOR

Matt S. Trout <mst@shadowcatsystems.co.uk>

=head1 CONTRIBUTORS

Aran Deltac <bluefeet@cpan.org>

=head1 LICENSE

You may distribute this code under the same terms as Perl itself.

