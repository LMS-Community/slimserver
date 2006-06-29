# -*- perl -*-
# vim:ts=4:sw=4:aw:ai:
#
#   DBI::Format::SQLMinus - a package for displaying result tables
#
#   Copyright (c) 2001, 2002  Thomas A. Lowery
#
#   The DBI::Shell::SQLMinus module is free software; you can redistribute
#   it and/or modify it under the same terms as Perl itself.
#

#
#  The "meat" of this format comes from interaction with the sqlminus
#  plugin module.
#

use strict;

package DBI::Format::SQLMinus;

@DBI::Format::SQLMinus::ISA = qw(DBI::Format::Base);

use Text::Abbrev;
use Text::Reform qw(form break_with);

use Data::Dumper;

use vars qw($VERSION);

$VERSION = sprintf( "%d.%02d", q$Revision: 11.91 $ =~ /(\d+)\.(\d+)/ );

sub header {
    my($self, $sth, $fh, $sep) = @_;
    $self->{'fh'} = $self->setup_fh($fh);
    $self->{'sth'} = $sth;
    $self->{'data'} = [];
    $self->{'formats'} = [];
    $self->{sep} = $sep if defined $sep;
	#
	# determine default behavior based either on the setting in
	# sqlminus, or pre-defined defaults.  Without sqlminus loaded,
	# these defaults setting are static.  Using the sqlminus "set"
	# command to change setting.
	#

	my ($breaks, $set, $column_format, $column_header_format, $sqlminus);

	if ( exists $self->{plugin}->{sqlminus} ) {

		# sqlminus plugin installed.
		$sqlminus = $self->{plugin}->{sqlminus};

		$set			= $sqlminus->{set_current};
		$column_format	= $sqlminus->{column_format};
		$column_header_format = 
			$sqlminus->{column_header_format};
		$breaks			= $sqlminus->{break_current};
	} else {
		warn 'sqlminus plugin not installed\n';
		$sqlminus = undef;
		$set = {};
		$column_format = {};
		$column_header_format = {};
	}

	$self->{feedback}	= $set->{feedback};
	$self->{limit}		= $set->{limit};
	$self->{null}       = $set->{null};
	$self->{pagesize}	= $set->{pagesize};
	$self->{recsepchar}	= $set->{recsepchar};
	$self->{recsep}		= $set->{recsep};

	$self->{pagefeed}	= undef;
	$self->{pagelen}	= 66;
	$self->{pagenum}	= 0;

	# $self->{breaks};

    my $types = $sth->{'TYPE'};
    my @right_justify;
    my @widths;
    my @heading;
    my @display;
    my $names = $sth->{'NAME'};
    my $names_lc = $sth->{'NAME_lc'};
    my $type;
	my $format_row;
	my @ul;
	my @fmtfunc;
	my @commify;

	my $attribs = {
		 name		=> undef
		,name_lc	=> undef
		,precision	=> undef
		,scale		=> undef
		,len		=> undef
		,commify	=> undef
		,fmtfunc	=> undef
		,justify	=> undef
		,type		=> undef
		,format		=> undef
		,display	=> undef
		,heading	=> undef
	};

	my @columns = ();

    for (my $i = 0;  $i < $sth->{'NUM_OF_FIELDS'};  $i++) {


		my $myattribs = ();
		$myattribs->{$_} = undef foreach ( sort keys %$attribs );

    	my ($format_names, $heading, $width, $type, $justify);
		# Default, left justify everything.
		$justify = '<';
		$myattribs->{justify} = q{<};

		push(@display, 1);

		$myattribs->{display}++;

		$myattribs->{name} = $names->[$i];
		$myattribs->{name_lc} = $names_lc->[$i];

		my $n_lc = $names_lc->[$i];
# Determine if a break point exists.
		if ( exists $breaks->{$n_lc} ) {
			print "Column " . $n_lc . " has a break point\n";
			push @{$self->{breaks}->{order_of}}, $n_lc;
			for (keys %{$breaks->{$n_lc}}) {
				$self->{breaks}->{$n_lc}->{$_} =
					$breaks->{$n_lc}->{$_};
			}

			$self->{breaks}->{$n_lc}->{last_break_point} = undef;
		}

		if ( exists $column_format->{$names_lc->[$i]} ) {
			my $cf = $column_format->{$names_lc->[$i]};

			# Determine if the column formating is on or off.
			if ( exists $cf->{on} and $cf->{on} ) {

				# Determine if this column is printed.
				# If this column is set to noprint, then skip.
				if (exists $cf->{noprint} and $cf->{noprint}) {
					$myattribs->{display} = 0;
					$display[$i] = 0;
# Need to remember the attributes set for this column
					push(@columns, $myattribs);
					next;
				}

				if ( exists $cf->{format} and defined $cf->{format} ) {
					$format_names = $cf->{format};
					$width = length sprintf( $format_names, " " );
				}

				if ( exists $cf->{justify} and defined $cf->{justify} ) {
					$justify = '^' if $cf->{justify} =~ m/^c/;
					$justify = '<' if $cf->{justify} =~ m/^l/;
					$justify = '>' if $cf->{justify} =~ m/^r/;

					$myattribs->{justify} = $justify;
				}

				if (exists $cf->{heading} and defined $cf->{heading}) {
					$heading = $cf->{heading};
					$myattribs->{heading} = $heading;
				}
				
			} 

			push( @fmtfunc , $cf->{format_function} );
			$myattribs->{fmtfunc} = $cf->{format_function};
			push( @commify , $cf->{'commify'} || 0 );
			$myattribs->{commify} = $cf->{commify};

			$myattribs->{precision} = $cf->{precision};
			$myattribs->{scale} = $cf->{scale};
			$myattribs->{len} = $cf->{len};
		} 
			

		$heading = $names->[$i] unless $heading;

		push(@heading, $heading);

		$type = $types->[$i];
		$myattribs->{type} = $type;

		if ( $width ) {
			push( @widths, $width );
			$myattribs->{width} = $width;
		} else {
			push(@widths, $self->_determine_width( 
				$type, $sth->{PRECISION}->[$i] ));

			$widths[$i] = length $names->[$i]
				if (length $names->[$i] > ($widths[$i]||0));
			$width = $widths[$i];
			$myattribs->{width} = $width;
		}


		if ( $justify ) {
			push( @right_justify, $justify );
			$myattribs->{justify} = $justify;
		} else {
			push(@right_justify,
			 ($type == DBI::SQL_NUMERIC()   ||
			  $type == DBI::SQL_DECIMAL()   ||
			  $type == DBI::SQL_INTEGER()   ||
			  $type == DBI::SQL_SMALLINT()  ||
			  $type == DBI::SQL_FLOAT()     ||
			  $type == DBI::SQL_REAL()      ||
			  $type == DBI::SQL_BIGINT()    ||
			  $type == DBI::SQL_TINYINT()));
			$myattribs->{justify} = 
			 ($type == DBI::SQL_NUMERIC()   ||
			  $type == DBI::SQL_DECIMAL()   ||
			  $type == DBI::SQL_INTEGER()   ||
			  $type == DBI::SQL_SMALLINT()  ||
			  $type == DBI::SQL_FLOAT()     ||
			  $type == DBI::SQL_REAL()      ||
			  $type == DBI::SQL_BIGINT()    ||
			  $type == DBI::SQL_TINYINT());
		}

		$format_names = $justify x $width
			unless $format_names;
		
		push( @ul, defined $set->{underline}
					? "$set->{underline}" x $width
					: '-' x $width
		); 
			

		$set->{linesize} += $widths[$i]
			unless $set->{linesize};

		$format_row .= $format_names;
		$format_row .= $set->{headsep};


		push(@columns, $myattribs);
    }

	$self->{'formats'}	= \$format_row;
	$self->{'columns'}	= \@columns;
	$self->{'headings'}	= \@heading;
	$self->{'ul'}		= \@ul;

	$column_header_format = $format_row;
	# print $fh form $header_form, (sprintf($format_row, @heading)), "\n" if $set->{heading};
	print $fh form $column_header_format, @heading
		if $set->{heading};
	print $fh form $column_header_format, @ul
		if $set->{underline};
	print $fh "\n"
		if $set->{heading} and ! $set->{underline};
}

sub re_headers {
    my($self) = @_;
    my $fh = $self->{'fh'};


	my ($set, $column_format, $column_header_format, $sqlminus);

	if ( exists $self->{plugin}->{sqlminus} ) {
		# sqlminus plugin installed.
		$sqlminus = $self->{plugin}->{sqlminus};
		$set = $sqlminus->{set_current};
	} else {
		return warn 'sqlminus plugin not installed\n';
	}

	$column_header_format = ${$self->{'formats'}};

	print $fh "\n"
		if defined $set->{heading};
	print $fh form $column_header_format, @{$self->{headings}}
		if defined $set->{heading};
	print $fh form $column_header_format, @{$self->{ul}}
		if defined $set->{underline};
	print $fh "\n"
		if defined $set->{heading} and not defined $set->{underline};

}


sub row {
    my($self, $orig_row) = @_;
    my $i = 0;
    my @row = @$orig_row; # don't mess with the original row

# default value for null, is blank.
	my $null = $self->{'null'} || '';
	my $columns = $self->{'columns'};

	my $breaks	= $self->{'breaks'};

    map {
		if (!defined($_)) {
			$_ = $null;
		} else {
			$_ =~ s/\n/\\n/g;
			$_ =~ s/\t/\\t/g;
			$_ =~ s/\r/\\r/g;
			$_ =~ s/[\000-\037\177-\237]/./g;
		}
		++$i;
    } @row;

    my $format_rows  = ${$self->{'formats'}};

	# if (exists $self->{'formats'} and defined $self->{'formats'} ){
	# 	#print "using existing format '$format_rows'\n";
	# 	$format_rows = ${$self->{'formats'}};
	# } else {
	# 	for (my $i = 0;  $i < $sth->{'NUM_OF_FIELDS'};  $i++) {
	# 	$format_rows  .= 
	# 			($right_justify->[$i] ? "<" : ">") 
	# 				x $widths->[$i]
	# 			. ($self->{recsep}?$self->{recsepchar}:'');
	# 	}
	# }

    $format_rows  .= "\n";

    my $fh = $self->{'fh'};
	my @data; my $skip_rows = 0; my $skip_page = undef;
	COLUMN:
	for (my $i = 0;  $i < $self->{'sth'}->{'NUM_OF_FIELDS'};  $i++) {

		my $attribs = $columns->[$i];
		if ( exists $breaks->{$attribs->{name_lc}} ) {

			my $brk = $breaks->{$attribs->{name_lc}};

			if (defined $brk->{last_break_point} and
				$brk->{last_break_point} ne $row[$i]) {
				if (exists $brk->{skip}) {
					$skip_rows = $skip_rows >= $brk->{skip} ? $skip_rows :
						$brk->{skip};
				}

				if (exists $brk->{skip_page}) {
					$skip_page = 1;
				}
			}

			if (exists $brk->{nodup}) {
				if (defined $brk->{last_break_point} 
					and $brk->{last_break_point} eq $row[$i]) {
					push (@data, q{}); # empty row (noduplicate display) 
					$brk->{last_break_point} = $row[$i];
					next COLUMN;
				}
			}

			$brk->{last_break_point} = $row[$i];
		}

		next unless ($attribs->{'display'});

		if ((ref $attribs->{fmtfunc}) eq 'CODE') {
			# warn "fmtcall\n";
			push( @data , 
				$attribs->{fmtfunc}(
					 $row[$i]
					,$attribs->{precision} || $attribs->{width}
					,$attribs->{scale} || 0
					,$attribs->{'commify'}) );
		} else {
			push( @data , $row[$i] );
		}
	}

# Deal with the breaks.
	if ($skip_page) {
		print $fh q{};
	} elsif ($skip_rows) {
		print $fh "\n" x $skip_rows;
	}

    print $fh form ( 
		{ 'break'	=> break_with('') }
		, $format_rows, @data
		);

	++$self->{'rows'};

# Send a undef back to caller, signal limit reached.
	if (defined $self->{limit} and $self->{rows} >= $self->{limit}) {
		return undef;
	}
# Determine if this number of rows displayed is modulo of pagesize
	if (defined $self->{pagesize} 
		and ($self->{'rows'} % $self->{pagesize}) == 0 ) {
		$self->re_headers();
	}

return $self->{rows};
}


sub trailer {
    my $self = shift;
    my $widths = delete $self->{'widths'};
    my $right_justify = delete $self->{'right_justify'};

	delete $self->{recsep};
	delete $self->{recsepchar};
	print "Page Number: ", $self->{pagenum}, "\n";

    $self->SUPER::trailer(@_);
} 

1;

=head1 NAME

DBI::Format::SQLMinus - A package for displaying result tables

=head1 SYNOPSIS

=head1 DESCRIPTION

THIS PACKAGE IS STILL VERY EXPERIMENTAL. THINGS WILL CHANGE.

=head1 AUTHOR AND COPYRIGHT

Orignal Format module is Copyright (c) 1997, 1998

    Jochen Wiedmann
    Am Eisteich 9
    72555 Metzingen
    Germany

    Email: joe@ispsoft.de
    Phone: +49 7123 14887

SQLMinus is Copyright (c) 2001, 2002  Thomas A. Lowery

The DBI::Format::SQLMinus module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.


=head1 SEE ALSO

L<DBI::Shell(3)>, L<DBI(3)>, L<dbish(1)>
