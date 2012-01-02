package SL::Controller::Autocomplete;

use strict;

use parent qw(SL::Controller::Base);
use SL::Common;
use SL::DBUtils;
use JSON;


sub action_ct_search {
  $main::lxdebug->enter_sub();

  my ( $self ) = @_;
  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $column;
  if ($form->{column} eq "name") {
    $column = "name";
  } elsif ($form->{column} eq "street") {
    $column = "street";
  } elsif ($form->{column} eq "zipcode") {
    $column = "zipcode";
  } elsif ($form->{column} eq "city") {
    $column = "city";
  } else {
    $main::lxdebug->leave_sub();
    return;
  }
  my $cv = $form->{vc} eq "customer" ? "customer" : "vendor";
  my $query;
  # connect to database
  my $dbh = $form->dbconnect(\%myconfig);

  my $where = "$column ILIKE ? OR shipto$column ILIKE ?";
  my $term = '%'. $form->{term} .'%';
  $query =
    qq|SELECT (ct.|.$cv.qq|number \|\|'--'\|\| ct.name \|\|'--'\|\|
      (CASE WHEN sh.shiptostreet <> ''
       THEN sh.shiptostreet
       ELSE ct.street
       END)\|\|'--'\|\| 
       (CASE WHEN sh.shiptozipcode <> ''
       THEN sh.shiptozipcode
       ELSE ct.zipcode
       END)\|\|'--'\|\|
       (CASE WHEN sh.shiptocity <> ''
       THEN sh.shiptocity
       ELSE ct.city
       END)) as label, ct.id as vc_id, ct.name as vc_name, (ct.name \|\| '--' \|\| ct.id) as vc_oldcustomer  | .
    qq|FROM $cv ct LEFT OUTER JOIN shipto AS sh ON (sh.trans_id = ct.id)| .
    qq|WHERE $where|;

  $form->{CT} = selectall_hashref_query($form, $dbh, $query, $term, $term);
  print $form->ajax_response_header(),
        to_json($form->{CT});

  $main::lxdebug->leave_sub();
}

sub action_part_search {
  $main::lxdebug->enter_sub();

  my ( $self ) = @_;
  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $column = $form->{column} eq 'partnumber' ? 'partnumber' : 'description';
  my $term = '%'.$form->{term}.'%';
  my $query;
  # connect to database
  my $dbh = $form->dbconnect(\%myconfig);
  $query = qq|SELECT (p.partnumber \|\| '--' \|\| p.description \|\| '--' \|\| p.sellprice) as label, p.partnumber as partnumber, p.description as desc | .
           qq|FROM parts p | .
           qq|WHERE $column ILIKE ?|;

  $form->{parts} = selectall_hashref_query($form, $dbh, $query, $term);

  print $form->ajax_response_header(),
        to_json($form->{parts});

  $main::lxdebug->leave_sub();

}

1;
