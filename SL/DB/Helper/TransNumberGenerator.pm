package SL::DB::Helper::TransNumberGenerator;

use strict;

use parent qw(Exporter);
our @EXPORT = qw(get_next_trans_number create_trans_number);

use Carp;
use List::Util qw(max);

use SL::DB::Default;

my $oe_scoping = sub {
  SL::DB::Manager::Order->type_filter($_[0]);
};

my $do_scoping = sub {
  SL::DB::Manager::DeliveryOrder->type_filter($_[0]);
};

my %specs = ( ar                      => { number_column => 'invnumber',                                                             fill_holes_in_range => 1 },
              sales_quotation         => { number_column => 'quonumber', number_range_column => 'sqnumber',  scoping => $oe_scoping,                          },
              sales_order             => { number_column => 'ordnumber', number_range_column => 'sonumber',  scoping => $oe_scoping,                          },
              request_quotation       => { number_column => 'quonumber', number_range_column => 'rfqnumber', scoping => $oe_scoping,                          },
              purchase_order          => { number_column => 'ordnumber', number_range_column => 'ponumber',  scoping => $oe_scoping,                          },
              sales_delivery_order    => { number_column => 'donumber',  number_range_column => 'sdonumber', scoping => $do_scoping, fill_holes_in_range => 1 },
              purchase_delivery_order => { number_column => 'donumber',  number_range_column => 'pdonumber', scoping => $do_scoping, fill_holes_in_range => 1 },
            );

sub get_next_trans_number {
  my ($self, %params) = @_;

  my $spec_type           = $specs{ $self->meta->table } ? $self->meta->table : $self->type;
  my $spec                = $specs{ $spec_type } || croak("Unsupported class " . ref($self));

  my $number_column       = $spec->{number_column};
  my $number              = $self->$number_column;
  my $number_range_column = $spec->{number_range_column} || $number_column;
  my $scoping_conditions  = $spec->{scoping};
  my $fill_holes_in_range = $spec->{fill_holes_in_range};

  return $number if $self->id && $number;

  my $re              = '^(.*?)(\d+)$';
  my %conditions      = $scoping_conditions ? ( query => [ $scoping_conditions->($spec_type) ] ) : ();
  my @numbers         = map { $_->$number_column } @{ $self->_get_manager_class->get_all(%conditions) };
  my %numbers_in_use  = map { ( $_ => 1 )        } @numbers;
  @numbers            = grep { $_ } map { my @matches = m/$re/; @matches ? $matches[-1] * 1 : undef } @numbers;

  my $defaults        = SL::DB::Default->get;
  my $number_range    = $defaults->$number_range_column;
  my @matches         = $number_range =~ m/$re/;
  my $prefix          = (2 != scalar(@matches)) ? ''  : $matches[ 0];
  my $ref_number      = !@matches               ? '1' : $matches[-1];
  my $min_places      = length($ref_number);

  my $new_number      = $fill_holes_in_range ? $ref_number : max($ref_number, @numbers);
  my $new_number_full = undef;

  while (1) {
    $new_number      =  $new_number + 1;
    my $new_number_s =  $new_number;
    $new_number_s    =~ s/\.\d+//g;
    $new_number_full =  $prefix . ('0' x max($min_places - length($new_number_s), 0)) . $new_number_s;
    last if !$numbers_in_use{$new_number_full};
  }

  $defaults->update_attributes($number_range_column => $new_number_full) if $params{update_defaults};
  $self->$number_column($new_number_full)                                if $params{update_record};

  return $new_number_full;
}

sub create_trans_number {
  my ($self, %params) = @_;

  return $self->get_next_trans_number(update_defaults => 1, update_record => 1, %params);
}

1;

__END__

=pod

=encoding utf8

=head1 NAME

SL::DB::Helper::TransNumberGenerator - A mixin for creating unique record numbers

=head1 FUNCTIONS

=over 4

=item C<get_next_trans_number %params>

Generates a new unique record number for the mixing class. Each record
type (invoices, sales quotations, purchase orders etc) has its own
number range. Within these ranges all numbers should be unique. The
table C<defaults> contains the last record number assigned for all of
the number ranges.

This function contains hard-coded knowledge about the modules it can
be mixed into. This way the models themselves don't have to contain
boilerplate code for the details like the the number range column's
name in the C<defaults> table.

The process of creating a unique number involves the following steps:

At first all existing record numbers for the current type are
retrieved from the database as well as the last number assigned from
the table C<defaults>.

The next step is separating the number range from C<defaults> into two
parts: an optional non-numeric prefix and its numeric suffix. The
prefix, if present, will be kept intact.

Now the number itself is increased as often as neccessary to create a
unique one by comparing the generated numbers with the existing ones
retrieved in the first step. In this step gaps in the assigned numbers
are filled for some tables (e.g. invoices) but not for others
(e.g. sales orders).

After creating the unique record number this function can update
C<$self> and the C<defaults> table if requested. This is controlled
with the following parameters:

=over 2

=item * C<update_record>

Determines whether or not C<$self>'s record number field is set to the
newly generated number. C<$self> will not be saved even if this
parameter is trueish. Defaults to false.

=item * C<update_defaults>

Determines whether or not the number range value in the C<defaults>
table should be updated. Unlike C<$self> the C<defaults> table will be
saved. Defaults to false.

=back

Always returns the newly generated number. This function cannot fail
and return a value. If it fails then it is due to exceptions.

=item C<create_trans_number %params>

Calls and returns </get_next_trans_number> with the parameters
C<update_defaults = 1> and C<update_record = 1>. C<%params> is passed
to it as well.

=back

=head1 EXPORTS

This mixin exports all of its functions: L</get_next_trans_number> and
L</create_trans_number>. There are no optional exports.

=head1 BUGS

Nothing here yet.

=head1 AUTHOR

Moritz Bunkus E<lt>m.bunkus@linet-services.deE<gt>

=cut
