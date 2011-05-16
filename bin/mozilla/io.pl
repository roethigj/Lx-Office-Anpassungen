#=====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#############################################################################
# Changelog: Wann - Wer - Was
# Veraendert 2005-01-05 - Marco Welter <mawe@linux-studio.de> - Neue Optik
# 08.11.2008 - information@richardson-bueren.de jb  - Backport von Revision 7339 xplace - E-Mail-Vorlage automatisch auswählen
# 02.02.2009 - information@richardson-bueren.de jb - Backport von Revision 8535 xplace - Erweiterung der Waren bei Lieferantenauftrag um den Eintrag Mindestlagerbestand. Offen: Auswahlliste auf Lieferantenaufträge einschränken -> Erledigt 2.2.09 Prüfung wie das Skript heisst (oe.pl) -> das ist nur die halbe Miete, nochmal mb fragen -> mb gefragt und es gibt die variable is_purchase
#############################################################################
# SQL-Ledger, Accounting
# Copyright (c) 1998-2002
#
#  Author: Dieter Simader
#   Email: dsimader@sql-ledger.org
#     Web: http://www.sql-ledger.org
#
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
#######################################################################
#
# common routines used in is, ir, oe
#
#######################################################################

use CGI;
use CGI::Ajax;
use List::Util qw(min max first);

use SL::CVar;
use SL::Common;
use SL::CT;
use SL::IC;
use SL::IO;

require "bin/mozilla/common.pl";

use strict;

# any custom scripts for this one
if (-f "bin/mozilla/custom_io.pl") {
  eval { require "bin/mozilla/custom_io.pl"; };
}
if (-f "bin/mozilla/$::form->{login}_io.pl") {
  eval { require "bin/mozilla/$::form->{login}_io.pl"; };
}

1;

# end of main

# this is for our long dates
# $locale->text('January')
# $locale->text('February')
# $locale->text('March')
# $locale->text('April')
# $locale->text('May ')
# $locale->text('June')
# $locale->text('July')
# $locale->text('August')
# $locale->text('September')
# $locale->text('October')
# $locale->text('November')
# $locale->text('December')

# this is for our short month
# $locale->text('Jan')
# $locale->text('Feb')
# $locale->text('Mar')
# $locale->text('Apr')
# $locale->text('May')
# $locale->text('Jun')
# $locale->text('Jul')
# $locale->text('Aug')
# $locale->text('Sep')
# $locale->text('Oct')
# $locale->text('Nov')
# $locale->text('Dec')
use SL::IS;
use SL::PE;
use SL::AM;
use Data::Dumper;

sub _check_io_auth {
  $main::auth->assert('part_service_assembly_edit   | vendor_invoice_edit       | sales_order_edit    | invoice_edit |' .
                'request_quotation_edit       | sales_quotation_edit      | purchase_order_edit | ' .
                'purchase_delivery_order_edit | sales_delivery_order_edit');
}

########################################
# Eintrag fuer Version 2.2.0 geaendert #
# neue Optik im Rechnungsformular      #
########################################
sub display_row {
  $main::lxdebug->enter_sub();

  _check_io_auth();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my $cgi      = $main::cgi;

  my $numrows = shift;

  my ($readonly, $stock_in_out, $stock_in_out_title);

  my $is_purchase        = (first { $_ eq $form->{type} } qw(request_quotation purchase_order purchase_delivery_order)) || ($form->{script} eq 'ir.pl');
  my $show_min_order_qty =  first { $_ eq $form->{type} } qw(request_quotation purchase_order);
  my $is_delivery_order  = $form->{type} =~ /_delivery_order$/;
  my $is_s_p_order       = (first { $_ eq $form->{type} } qw(sales_order purchase_order));

  if ($is_delivery_order) {
    $readonly             = ' readonly' if ($form->{closed});

    if ($form->{type} eq 'sales_delivery_order') {
      $stock_in_out_title = $locale->text('Release From Stock');
      $stock_in_out       = 'out';
    } else {
      $stock_in_out_title = $locale->text('Transfer To Stock');
      $stock_in_out       = 'in';
    }

    retrieve_partunits();
  }

  # column_index
  my @header_sort = qw(runningnumber partnumber description ship qty unit sellprice_pg sellprice discount linetotal);
  my @HEADER = (
    {  id => 'runningnumber', width => 5,     value => $locale->text('No.'),                  display => 1, },
    {  id => 'partnumber',    width => 8,     value => $locale->text('Number'),               display => 1, },
    {  id => 'description',   width => 30,    value => $locale->text('Part Description'),     display => 1, },
    {  id => 'ship',          width => 5,     value => $locale->text('Delivered'),            display => $is_s_p_order, },
    {  id => 'qty',           width => 5,     value => $locale->text('Qty'),                  display => 1, },
    {  id => 'price_factor',  width => 5,     value => $locale->text('Price Factor'),         display => !$is_delivery_order, },
    {  id => 'unit',          width => 5,     value => $locale->text('Unit'),                 display => 1, },
    {  id => 'license',       width => 10,    value => $locale->text('License'),              display => 0, },
    {  id => 'serialnr',      width => 10,    value => $locale->text('Serial No.'),           display => 0, },
    {  id => 'projectnr',     width => 10,    value => $locale->text('Project'),              display => 0, },
    {  id => 'sellprice',     width => 15,    value => $locale->text('Price'),                display => !$is_delivery_order, },
    {  id => 'sellprice_pg',  width => 8,     value => $locale->text('Pricegroup'),           display => !$is_delivery_order && !$is_purchase, },
    {  id => 'discount',      width => 5,     value => $locale->text('Discount'),             display => !$is_delivery_order, },
    {  id => 'linetotal',     width => 10,    value => $locale->text('Extended'),             display => !$is_delivery_order, },
    {  id => 'bin',           width => 10,    value => $locale->text('Bin'),                  display => 0, },
    {  id => 'stock_in_out',  width => 10,    value => $stock_in_out_title,                   display => $is_delivery_order, },
  );
  my @column_index = map { $_->{id} } grep { $_->{display} } @HEADER;


  # cache units
  my $all_units       = AM->retrieve_units(\%myconfig, $form);

  my %price_factors   = map { $_->{id} => $_->{factor} } @{ $form->{ALL_PRICE_FACTORS} };

  my $colspan = scalar @column_index;

  $form->{invsubtotal} = 0;
  map { $form->{"${_}_base"} = 0 } (split(/ /, $form->{taxaccounts}));

  # about details
  $myconfig{show_form_details} = 1                            unless (defined($myconfig{show_form_details}));
  $form->{show_details}        = $myconfig{show_form_details} unless (defined($form->{show_details}));
  # /about details

  # translations, unused commented out
#  $runningnumber = $locale->text('No.');
#  my $deliverydate  = $locale->text('Delivery Date');
  my $serialnumber  = $locale->text('Serial No.');
  my $projectnumber = $locale->text('Project');
#  $partsgroup    = $locale->text('Group');
  my $reqdate       = $locale->text('Reqdate');
  my $deliverydate  = $locale->text('Required by');

  # special alignings
  my %align  = map { $_ => 'right' } qw(qty ship right sellprice_pg discount linetotal stock_in_out);
  my %nowrap = map { $_ => 1 }       qw(description unit);

  $form->{marge_total}           = 0;
  $form->{sellprice_total}       = 0;
  $form->{lastcost_total}        = 0;
  my %projectnumber_labels = ();
  my @projectnumber_values = ("");

  foreach my $item (@{ $form->{"ALL_PROJECTS"} }) {
    push(@projectnumber_values, $item->{"id"});
    $projectnumber_labels{$item->{"id"}} = $item->{"projectnumber"};
  }

  _update_part_information();
  _update_ship() if ($is_s_p_order);
  _update_custom_variables();

  # rows

  my @ROWS;
  for my $i (1 .. $numrows) {
    my %column_data = ();
    

    # undo formatting
    map { $form->{"${_}_$i"} = $form->parse_amount(\%myconfig, $form->{"${_}_$i"}) }
      qw(qty discount sellprice lastcost price_new)
        unless ($form->{simple_save});
    
   # get pricegroups
    IS->get_pricegroups_new(\%myconfig, $form, $i);
    set_pricegroup_for_i($i);
    map { $form->{"${_}_$i"} = $form->parse_amount(\%myconfig, $form->{"${_}_$i"}) } qw(sellprice price_new);

    my $this_unit = $form->{"unit_$i"};
    $this_unit    = $form->{"selected_unit_$i"} if AM->convert_unit($this_unit, $form->{"selected_unit_$i"}, $all_units);

    if (0 < scalar @{ $form->{ALL_PRICE_FACTORS} }) {
      my @values = ('', map { $_->{id}                      } @{ $form->{ALL_PRICE_FACTORS} });
      my %labels =      map { $_->{id} => $_->{description} } @{ $form->{ALL_PRICE_FACTORS} };

      $column_data{price_factor} =
        NTI($cgi->popup_menu('-name'    => "price_factor_id_$i",
                             '-default' => $form->{"price_factor_id_$i"},
                             '-values'  => \@values,
                             '-labels'  => \%labels,
                             '-style'   => 'width:90px'));
    } else {
      $column_data{price_factor} = '&nbsp;';
    }

    $column_data{"unit"} = AM->unit_select_html($all_units, "unit_$i", $this_unit, $form->{"id_$i"} ? $form->{"unit_$i"} : undef);

    my $decimalplaces = ($form->{"sellprice_$i"} =~ /\.(\d+)/) ? max 2, length $1 : 2;

    my $price_factor   = $price_factors{$form->{"price_factor_id_$i"}} || 1;
    my $discount       = $form->round_amount($form->{"qty_$i"} * $form->{"sellprice_$i"} *        $form->{"discount_$i"}  / 100 / $price_factor, 2);
    my $linetotal      = $form->round_amount($form->{"qty_$i"} * $form->{"sellprice_$i"} * (100 - $form->{"discount_$i"}) / 100 / $price_factor, 2);
    my $rows            = $form->numtextrows($form->{"description_$i"}, 30, 6);

    $column_data{runningnumber} = $cgi->textfield(-name => "runningnumber_$i", -size => 5,  -value => $i);    # HuT
    $column_data{partnumber}    = $cgi->textfield(-name => "partnumber_$i",    -size => 12, -value => $form->{"partnumber_$i"});
    $column_data{description} = (($rows > 1) # if description is too large, use a textbox instead
                                ? $cgi->textarea( -name => "description_$i", -default => $form->{"description_$i"}, -rows => $rows, -columns => 30)
                                : $cgi->textfield(-name => "description_$i",   -size => 30, -value => $form->{"description_$i"}))
                                . $cgi->button(-value => $locale->text('L'), -onClick => "set_longdescription_window('longdescription_$i')");

    my $qty_dec = ($form->{"qty_$i"} =~ /\.(\d+)/) ? length $1 : 2;

    $column_data{qty}  = $cgi->textfield(-name => "qty_$i", -size => 5, -value => $form->format_amount(\%myconfig, $form->{"qty_$i"}, $qty_dec));
    $column_data{qty} .= $cgi->button(-onclick => "calculate_qty_selection_window('qty_$i','alu_$i', 'formel_$i', $i)", -value => $locale->text('*/'))
                       . $cgi->hidden(-name => "formel_$i", -value => $form->{"formel_$i"}) . $cgi->hidden("-name" => "alu_$i", "-value" => $form->{"alu_$i"})
      if $form->{"formel_$i"};

    $column_data{ship} = '';
    if ($form->{"id_$i"}) {
      my $ship_qty        = $form->{"ship_$i"} * 1;
      $ship_qty          *= $all_units->{$form->{"partunit_$i"}}->{factor};
      $ship_qty          /= ( $all_units->{$form->{"unit_$i"}}->{factor} || 1 );

      $column_data{ship}  = $form->format_amount(\%myconfig, $form->round_amount($ship_qty, 2) * 1) . ' ' . $form->{"unit_$i"};
    }

    my $sellprice = $form->{"sellprice_$i"};
    
    # build in drop down list for pricesgroups
    if ($form->{"prices_$i"}) {
      $column_data{sellprice_pg} = qq|<select name="sellprice_pg_$i" style="width: 8em">$form->{"prices_$i"}</select>|;
      $column_data{sellprice}    = $cgi->textfield(-name => "sellprice_$i", -size => 10, -onBlur => 'check_right_number_format(this)', -value =>
                                     $form->format_amount(\%myconfig, $form->{"sellprice_$i"}, 2));
    } else {
      # for last row and 
      $column_data{sellprice_pg} = qq|&nbsp;|;
      $column_data{sellprice} = $cgi->textfield(-name => "sellprice_$i", -size => 10, -onBlur => "check_right_number_format(this)", -value =>
                                                $form->format_amount(\%myconfig, $form->{"sellprice_$i"}, 2));
    }

    if ($form->{"price_old_$i"} != 0) {
      #store tradediscount as fallback
      if ($form->{"tradediscount_$i"}) {
        if ($form->{"tradediscount_ori_$i"} eq undef) {
          $form->{"tradediscount_ori_$i"} = $form->{"tradediscount_$i"};
        }
      }
      my $listprice = $form->{"price_old_$i"};
      $form->{"tradediscount_$i"} = $listprice != 0 ? (1 - ($sellprice / $listprice)) : 1;
      if ($form->{"tradediscount_$i"} != 0) {
        $column_data{sellprice}    .= "->".$form->format_amount(\%myconfig, $form->{"tradediscount_$i"}*100, 1)."%";
      }
    } elsif ($form->{"tradediscount_$i"} != 0) {
        $column_data{sellprice}    .= "->".$form->format_amount(\%myconfig, $form->{"tradediscount_$i"}*100, 1)."%";
    }

    $column_data{discount}    = $cgi->textfield(-name => "discount_$i", -size => 3, -value => $form->format_amount(\%myconfig, $form->{"discount_$i"}));
    $form->{"linetotal_$i"}   = $linetotal;
    $column_data{linetotal}   = $form->format_amount(\%myconfig, $linetotal, 2);
    $column_data{bin}         = $form->{"bin_$i"};
    map { $form->{"taxrate_$i"} = ($form->{"${_}_rate"}) } split / /, $form->{"taxaccounts_$i"};
    map { $form->{"taxname_$i"} = ($form->{"${_}_description"}) } split / /, $form->{"taxaccounts_$i"};

    if ($is_delivery_order) {
      $column_data{stock_in_out} =  calculate_stock_in_out($i);
    }

    my @ROW1 = map { value => $column_data{$_}, align => $align{$_}, nowrap => $nowrap{$_} }, @column_index;

    # second row
    my @ROW2 = ();
    push @ROW2, { value => qq|<b>$serialnumber</b> <input name="serialnumber_$i" size="15" value="$form->{"serialnumber_$i"}">| }
      if $form->{type} !~ /_quotation/;
    push @ROW2, { value => qq|<b>$projectnumber</b> | . NTI($cgi->popup_menu('-name'  => "project_id_$i",        '-values'  => \@projectnumber_values,
                                                                             '-labels' => \%projectnumber_labels, '-default' => $form->{"project_id_$i"})) };
    push @ROW2, { value => qq|<b>$reqdate</b> <input name="reqdate_$i" size="11" onBlur="check_right_date_format(this)" value="$form->{"reqdate_$i"}">| }
      if ($form->{type} =~ /order/ ||  $form->{type} =~ /invoice/);
    push @ROW2, { value => sprintf qq|<b>%s</b>&nbsp;<input type="checkbox" name="subtotal_$i" value="1" %s>|,
                   $locale->text('Subtotal'), $form->{"subtotal_$i"} ? 'checked' : '' };

# begin marge calculations
    $form->{"lastcost_$i"}     *= 1;
    $form->{"marge_percent_$i"} = 0;

    my $marge_color;
    my $real_sellprice           = $linetotal;
    my $real_lastcost            = $form->{"lastcost_$i"} * $form->{"qty_$i"} / ( $form->{"marge_price_factor_$i"} || 1 );
    my $marge_percent_warn       = $myconfig{marge_percent_warn} * 1 || 15;
    my $marge_adjust_credit_note = $form->{type} eq 'credit_note' ? -1 : 1;

    if ($real_sellprice * 1 && ($form->{"qty_$i"} * 1)) {
      $form->{"marge_percent_$i"} = ($real_sellprice - $real_lastcost) * 100 / $real_sellprice;
      $marge_color                = 'color="#ff0000"' if $form->{"id_$i"} && $form->{"marge_percent_$i"} < $marge_percent_warn;
    }

    $form->{"marge_absolut_$i"}  = ($real_sellprice - $real_lastcost) * $marge_adjust_credit_note;
    $form->{"marge_total"}      += $form->{"marge_absolut_$i"};
    $form->{"lastcost_total"}   += $real_lastcost;
    $form->{"sellprice_total"}  += $real_sellprice;

    map { $form->{"${_}_$i"} = $form->round_amount($form->{"${_}_$i"}, 2) } qw(marge_absolut marge_percent);

    push @ROW2, { value => sprintf qq|
         <font %s><b>%s</b> %s &nbsp;%s%% </font>
        &nbsp;<b>%s</b> %s
        &nbsp;<b>%s</b> <input size="5" name="lastcost_$i" value="%s">|,
                   $marge_color, $locale->text('Ertrag'),$form->format_amount(\%myconfig, $form->{"marge_absolut_$i"}, 2),
                   $form->format_amount(\%myconfig, $form->{"marge_percent_$i"}, 2),
                   $locale->text('LP'), $form->format_amount(\%myconfig, $form->{"listprice_$i"}, 2),
                   $locale->text('EK'), $form->format_amount(\%myconfig, $form->{"lastcost_$i"}, 2) }
      if $form->{"id_$i"} && ($form->{type} =~ /^sales_/ ||  $form->{type} =~ /invoice/) && !$is_delivery_order;
# / marge calculations ending

# calculate onhand
    if ($form->{"id_$i"}) {
      my $part         = IC->get_basic_part_info(id => $form->{"id_$i"});
      my $onhand_color = 'color="#ff0000"' if  $part->{onhand} < $part->{rop};
      push @ROW2, { value => sprintf "<b>%s</b> <font %s>%s %s</font>",
                      $locale->text('On Hand'),
                      $onhand_color,
                      $form->format_amount(\%myconfig, $part->{onhand}, 2),
                      $part->{unit}
      };
    }
# / calculate onhand

    my @hidden_vars;

    if ($is_delivery_order) {
      map { $form->{"${_}_${i}"} = $form->format_amount(\%myconfig, $form->{"${_}_${i}"}) } qw(sellprice discount lastcost);
      push @hidden_vars, qw(sellprice discount price_factor_id lastcost);
      push @hidden_vars, "stock_${stock_in_out}_sum_qty", "stock_${stock_in_out}";
    }

    my @HIDDENS = map { value => $_}, (
          $cgi->hidden("-name" => "unit_old_$i", "-value" => $form->{"selected_unit_$i"}),
          $cgi->hidden("-name" => "price_new_$i", "-value" => $form->format_amount(\%myconfig, $form->{"price_new_$i"})),
          map { ($cgi->hidden("-name" => $_, "-value" => $form->{$_})); } map { $_."_$i" }
            (qw(orderitems_id bo pricegroup_old price_old id inventory_accno bin partsgroup partnotes
                income_accno expense_accno listprice assembly taxaccounts ordnumber transdate cusordnumber
                longdescription basefactor marge_absolut marge_percent marge_price_factor linetotal taxrate taxname tradediscount tradediscount_ori), @hidden_vars)
    );

    map { $form->{"${_}_base"} += $linetotal } (split(/ /, $form->{"taxaccounts_$i"}));

    $form->{invsubtotal} += $linetotal;

    # Benutzerdefinierte Variablen für Waren/Dienstleistungen/Erzeugnisse
    _render_custom_variables_inputs(ROW2 => \@ROW2, row => $i, part_id => $form->{"id_$i"});

    push @ROWS, { ROW1 => \@ROW1, ROW2 => \@ROW2, HIDDENS => \@HIDDENS, colspan => $colspan, error => $form->{"row_error_$i"}, };
  }

  print $form->parse_html_template('oe/sales_order', { ROWS   => \@ROWS,
                                                       HEADER => \@HEADER,
                                                     });

  if (0 != ($form->{sellprice_total} * 1)) {
    $form->{marge_percent} = ($form->{sellprice_total} - $form->{lastcost_total}) / $form->{sellprice_total} * 100;
  }

  $main::lxdebug->leave_sub();
}

sub display_one_row {
  $main::lxdebug->enter_sub();

  _check_io_auth();

  #my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my $cgi      = $main::cgi;

  my ($form, $i) = @_;
  my ($readonly, $stock_in_out, $stock_in_out_title);

  my $is_purchase        = (first { $_ eq $form->{type} } qw(request_quotation purchase_order purchase_delivery_order)) || ($form->{type} eq 'invoice' && $form->{vc} eq 'vendor');
  my $show_min_order_qty =  first { $_ eq $form->{type} } qw(request_quotation purchase_order);
  my $is_delivery_order  = $form->{type} =~ /_delivery_order$/;
  my $is_s_p_order       = (first { $_ eq $form->{type} } qw(sales_order purchase_order));

  if ($is_delivery_order) {
    $readonly             = ' readonly' if ($form->{closed});

    if ($form->{type} eq 'sales_delivery_order') {
      $stock_in_out_title = $locale->text('Release From Stock');
      $stock_in_out       = 'out';
    } else {
      $stock_in_out_title = $locale->text('Transfer To Stock');
      $stock_in_out       = 'in';
    }
  }

  # column_index
  my @showcolumn = (
    {  id => 'runningnumber',   display => 1, },
    {  id => 'partnumber',      display => 1, },
    {  id => 'description',     display => 1, },
    {  id => 'ship',            display => $is_s_p_order, },
    {  id => 'qty',             display => 1, },
    {  id => 'price_factor',    display => !$is_delivery_order, },
    {  id => 'unit',            display => 1, },
    {  id => 'license',         display => 0, },
    {  id => 'serialnr',        display => 0, },
    {  id => 'projectnr',       display => 0, },
    {  id => 'sellprice',       display => !$is_delivery_order, },
    {  id => 'sellprice_pg',    display => !$is_delivery_order && !$is_purchase, },
    {  id => 'discount',        display => !$is_delivery_order, },
    {  id => 'linetotal',       display => !$is_delivery_order, },
    {  id => 'bin',             display => 0, },
    {  id => 'stock_in_out',    display => $is_delivery_order, },
  );
  my @column_index = map { $_->{id} } grep { $_->{display} } @showcolumn;


  # cache units
  my $all_units       = AM->retrieve_units(\%myconfig, $form);
  $form->get_lists('price_factors' => 'ALL_PRICE_FACTORS');
  my %price_factors   = map { $_->{id} => $_->{factor} } @{ $form->{ALL_PRICE_FACTORS} };
  $form->{"price_factor_id_$i"} = $form->{price_factor_id};
  my $colspan = scalar @column_index;

  # about details
  $myconfig{show_form_details} = 1                            unless (defined($myconfig{show_form_details}));
  $form->{show_details}        = $myconfig{show_form_details} unless (defined($form->{show_details}));
  # /about details

  my $serialnumber  = $locale->text('Serial No.');
  my $projectnumber = $locale->text('Project');
  my $reqdate       = $locale->text('Reqdate');
  my $deliverydate  = $locale->text('Required by');

  # special alignings
  my %align  = map { $_ => 'right' } qw(qty ship sellprice_pg discount linetotal stock_in_out);
  my %nowrap = map { $_ => 1 }       qw(description unit);

  my %projectnumber_labels = ();
  my @projectnumber_values = ("");

  foreach my $item (@{ $form->{"ALL_PROJECTS"} }) {
    push(@projectnumber_values, $item->{"id"});
    $projectnumber_labels{$item->{"id"}} = $item->{"projectnumber"};
  }

  # row
  my $evenodd;
  my @ROW;
  for $i ($i..$i+1){
    my %column_data = ();

    # undo formatting
    map { $form->{"${_}_$i"} = $form->parse_amount(\%myconfig, $form->{"${_}_$i"}) }
    qw(qty discount sellprice lastcost price_new);

    IS->get_pricegroups_new(\%myconfig, $form, $i);
    set_pricegroup_for_i($i);
    map { $form->{"${_}_$i"} = $form->parse_amount(\%myconfig, $form->{"${_}_$i"}) }
      qw(sellprice price_new);
  
    my $this_unit = $form->{"unit_$i"};
    $this_unit    = $form->{"selected_unit_$i"} if AM->convert_unit($this_unit, $form->{"selected_unit_$i"}, $all_units);
    if (0 < scalar @{ $form->{ALL_PRICE_FACTORS} }) {
      my @values = ('', map { $_->{id}                      } @{ $form->{ALL_PRICE_FACTORS} });
      my %labels =      map { $_->{id} => $_->{description} } @{ $form->{ALL_PRICE_FACTORS} };
      $column_data{price_factor} =
        NTI($cgi->popup_menu('-name'    => "price_factor_id_$i",
                             '-default' => $form->{"price_factor_id_$i"},
                             '-values'  => \@values,
                             '-labels'  => \%labels,
                             '-style'   => 'width:90px'));
    } else {
      $column_data{price_factor} = '&nbsp;';
    }
  
    $column_data{"unit"} = AM->unit_select_html($all_units, "unit_$i", $this_unit, $form->{"id_$i"} ? $form->{"unit_$i"} : undef);
  
    my $decimalplaces = ($form->{"sellprice_$i"} =~ /\.(\d+)/) ? max 2, length $1 : 2;
    my $price_factor   = $price_factors{$form->{"price_factor_id_$i"}} || 1;
    my $discount       = $form->round_amount($form->{"qty_$i"} * $form->{"sellprice_$i"} *        $form->{"discount_$i"}  / 100 / $price_factor, 2);
    my $linetotal      = $form->round_amount($form->{"qty_$i"} * $form->{"sellprice_$i"} * (100 - $form->{"discount_$i"}) / 100 / $price_factor, 2);
    my $rows            = $form->numtextrows($form->{"description_$i"}, 30, 6);
  
    $column_data{runningnumber} = $cgi->textfield(-name => "runningnumber_$i", -size => 5,  -value => $i);    # HuT
    $column_data{partnumber}    = $cgi->textfield(-name => "partnumber_$i",    -size => 12, -value => $form->{"partnumber_$i"});
    $column_data{description} = (($rows > 1) # if description is too large, use a textbox instead
                                ? $cgi->textarea( -name => "description_$i", -default => $form->{"description_$i"}, -rows => $rows, -columns => 30)
                                : $cgi->textfield(-name => "description_$i",   -size => 30, -value => $form->{"description_$i"}))
                                . $cgi->button(-value => $locale->text('L'), -onClick => "set_longdescription_window('longdescription_$i')");
  
    my $qty_dec = ($form->{"qty_$i"} =~ /\.(\d+)/) ? length $1 : 2;
  
    $column_data{qty}  = $cgi->textfield(-name => "qty_$i", -size => 5, -value => $form->format_amount(\%myconfig, $form->{"qty_$i"}, $qty_dec));
    $column_data{qty} .= $cgi->button(-onclick => "calculate_qty_selection_window('qty_$i','alu_$i', 'formel_$i', $i)", -value => $locale->text('*/'))
                       . $cgi->hidden(-name => "formel_$i", -value => $form->{"formel_$i"}) . $cgi->hidden("-name" => "alu_$i", "-value" => $form->{"alu_$i"})
                         if $form->{"formel_$i"};
  
    $column_data{ship} = '';
    if ($form->{"id_$i"}) {
      my $ship_qty        = $form->{"ship_$i"} * 1;
      $ship_qty          *= $all_units->{$form->{"partunit_$i"}}->{factor};
      $ship_qty          /= ( $all_units->{$form->{"unit_$i"}}->{factor} || 1 );
  
      $column_data{ship}  = $form->format_amount(\%myconfig, $form->round_amount($ship_qty, 2) * 1) . ' ' . $form->{"unit_$i"};
    }

    my $sellprice = $form->{"sellprice_$i"};
    
    # build in drop down list for pricesgroups
    if ($form->{"prices_$i"}) {
      $column_data{sellprice_pg} = qq|<select name="sellprice_pg_$i" style="width: 8em">$form->{"prices_$i"}</select>|;
      $column_data{sellprice}    = $cgi->textfield(-name => "sellprice_$i", -size => 10, -onBlur => 'check_right_number_format(this)', -value =>
                                     $form->format_amount(\%myconfig, $form->{"sellprice_$i"}, 2));
    } else {
      # for last row and 
      $column_data{sellprice_pg} = qq|&nbsp;|;
      $column_data{sellprice} = $cgi->textfield(-name => "sellprice_$i", -size => 10, -onBlur => "check_right_number_format(this)", -value =>
                                                $form->format_amount(\%myconfig, $form->{"sellprice_$i"}, 2));
    }

    if ($form->{"price_old_$i"} != 0) {
      #store tradediscount as fallback
      if ($form->{"tradediscount_$i"}) {
        if ($form->{"tradediscount_ori_$i"} eq undef) {
          $form->{"tradediscount_ori_$i"} = $form->{"tradediscount_$i"};
        }
      }
      my $listprice = $form->{"price_old_$i"};
      $form->{"tradediscount_$i"} = $listprice != 0 ? (1 - ($sellprice / $listprice)) : 1;
      if ($form->{"tradediscount_$i"} != 0) {
        $column_data{sellprice}    .= "->".$form->format_amount(\%myconfig, $form->{"tradediscount_$i"}*100, 1)."%";
      }
    } elsif ($form->{"tradediscount_$i"} != 0) {
        $column_data{sellprice}    .= "->".$form->format_amount(\%myconfig, $form->{"tradediscount_$i"}*100, 1)."%";
    }


    $column_data{discount}    = $cgi->textfield(-name => "discount_$i", -size => 3, -value => $form->format_amount(\%myconfig, $form->{"discount_$i"}));
    $form->{"linetotal_$i"}   = $linetotal;
    $column_data{linetotal}   = $form->format_amount(\%myconfig, $linetotal, 2);
    $column_data{bin}         = $form->{"bin_$i"};
    map { $form->{"taxrate_$i"} = ($form->{"${_}_rate"}) } split / /, $form->{"taxaccounts_$i"};
    map { $form->{"taxname_$i"} = ($form->{"${_}_description"}) } split / /, $form->{"taxaccounts_$i"};
  
    if ($is_delivery_order) {
      $column_data{stock_in_out} =  calculate_stock_in_out($i);
    }
    my @ROW1 = map { value => $column_data{$_}, align => $align{$_}, nowrap => $nowrap{$_} }, @column_index;
  
    # second row
    my @ROW2 = ();
    push @ROW2, { value => qq|<b>$serialnumber</b> <input name="serialnumber_$i" size="15" value="$form->{"serialnumber_$i"}">| }
      if $form->{type} !~ /_quotation/;
    push @ROW2, { value => qq|<b>$projectnumber</b> | . NTI($cgi->popup_menu('-name'  => "project_id_$i",        '-values'  => \@projectnumber_values,
                                                                             '-labels' => \%projectnumber_labels, '-default' => $form->{"project_id_$i"})) };
    push @ROW2, { value => qq|<b>$reqdate</b> <input name="reqdate_$i" size="11" onBlur="check_right_date_format(this)" value="$form->{"reqdate_$i"}">| }
      if ($form->{type} =~ /order/ ||  $form->{type} =~ /invoice/);
    push @ROW2, { value => sprintf qq|<b>%s</b>&nbsp;<input type="checkbox" name="subtotal_$i" value="1" %s>|,
                   $locale->text('Subtotal'), $form->{"subtotal_$i"} ? 'checked' : '' };

  # begin marge calculations
    $form->{"lastcost_$i"}     *= 1;
    $form->{"marge_percent_$i"} = 0;
    my $marge_color;
    my $real_sellprice           = $linetotal;
    my $real_lastcost            = $form->{"lastcost_$i"} * $form->{"qty_$i"} / ( $form->{"marge_price_factor_$i"} || 1 );
    my $marge_percent_warn       = $myconfig{marge_percent_warn} * 1 || 15;
    my $marge_adjust_credit_note = $form->{type} eq 'credit_note' ? -1 : 1;
    if ($real_sellprice * 1 && ($form->{"qty_$i"} * 1)) {
      $form->{"marge_percent_$i"} = ($real_sellprice - $real_lastcost) * 100 / $real_sellprice;
      $marge_color                = 'color="#ff0000"' if $form->{"id_$i"} && $form->{"marge_percent_$i"} < $marge_percent_warn;
   }

    $form->{"marge_absolut_$i"}  = ($real_sellprice - $real_lastcost) * $marge_adjust_credit_note;

    map { $form->{"${_}_$i"} = $form->round_amount($form->{"${_}_$i"}, 2) } qw(marge_absolut marge_percent);
 
    push @ROW2, { value => sprintf qq|
         <font %s><b>%s</b> %s &nbsp;%s%% </font>
          &nbsp;<b>%s</b> %s
          &nbsp;<b>%s</b> <input size="5" name="lastcost_$i" value="%s">|,
            $marge_color, $locale->text('Ertrag'),$form->format_amount(\%myconfig, $form->{"marge_absolut_$i"}, 2),
            $form->format_amount(\%myconfig, $form->{"marge_percent_$i"}, 2),
            $locale->text('LP'), $form->format_amount(\%myconfig, $form->{"listprice_$i"}, 2),
            $locale->text('EK'), $form->format_amount(\%myconfig, $form->{"lastcost_$i"}, 2) }
              if $form->{"id_$i"} && ($form->{type} =~ /^sales_/ ||  $form->{type} =~ /invoice/) && !$is_delivery_order;
  # / marge calculations ending
  
  # calculate onhand
    if ($form->{"id_$i"}) {
      my $part         = IC->get_basic_part_info(id => $form->{"id_$i"});
      my $onhand_color = 'color="#ff0000"' if  $part->{onhand} < $part->{rop};
      push @ROW2, { value => sprintf "<b>%s</b> <font %s>%s %s</font>",
                      $locale->text('On Hand'),
                      $onhand_color,
                      $form->format_amount(\%myconfig, $part->{onhand}, 2),
                      $part->{unit}
      };
    }
  # / calculate onhand

    my @hidden_vars;

    if ($is_delivery_order) {
      map { $form->{"${_}_${i}"} = $form->format_amount(\%myconfig, $form->{"${_}_${i}"}) } qw(sellprice discount lastcost);
      push @hidden_vars, qw(sellprice discount not_discountable price_factor_id lastcost);
      push @hidden_vars, "stock_${stock_in_out}_sum_qty", "stock_${stock_in_out}";
    }

    my @HIDDENS = map { value => $_}, (
          $cgi->hidden("-name" => "unit_old_$i", "-value" => $form->{"selected_unit_$i"}),
          $cgi->hidden("-name" => "price_new_$i", "-value" => $form->format_amount(\%myconfig, $form->{"price_new_$i"})),
          map { ($cgi->hidden("-name" => $_, "-value" => $form->{$_})); } map { $_."_$i" }
            (qw(orderitems_id bo pricegroup_old price_old id inventory_accno bin partsgroup partnotes
                income_accno expense_accno listprice assembly taxaccounts ordnumber transdate cusordnumber
                longdescription basefactor marge_absolut marge_percent marge_price_factor linetotal taxrate taxname tradediscount tradediscount_ori), @hidden_vars)
    );

  # Benutzerdefinierte Variablen für Waren/Dienstleistungen/Erzeugnisse
    _render_custom_variables_inputs(ROW2 => \@ROW2, row => $i, part_id => $form->{"id_$i"});

    push @ROW, { ROW1 => \@ROW1, ROW2 => \@ROW2, HIDDENS => \@HIDDENS, colspan => $colspan, error => $form->{"row_error_$i"}, };
    $evenodd = ($i+1) % 2; 
    last if ($form->{"description_$i"} eq undef || $form->{"partnumber_$i"} eq undef);
  } 
  print $form->parse_html_template('oe/oneline', { ROWS   => \@ROW,
                                                   evenodd => $evenodd
                                                     });

  $main::lxdebug->leave_sub();
}


##################################################
# build html-code for pricegroups in variable $form->{prices_$j}

sub set_pricegroup_for_i {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my $locale   = $main::locale;
  my $cgi      = $main::cgi;
  my %myconfig = %main::myconfig;

  _check_io_auth();

  my $i = shift;

  # build drop down list for pricegroups
  my $option_tmpl = qq|<option value="%s--%s" %s>%s</option>|;
  $form->{"prices_$i"}  = join '', map { sprintf $option_tmpl, @$_{qw(price pricegroup_id selected pricegroup)} }
                                       ( @{ $form->{PRICES}{$i} });
  if (@{ $form->{PRICES}{$i} }) {
    foreach my $item (@{ $form->{PRICES}{$i} }) {
      # set new selectedpricegroup_id and prices for "Preis"
      $form->{"pricegroup_old_$i"} = $item->{pricegroup_id}   if ($item->{selected} eq ' selected'); 
      $form->{"sellprice_$i"}      = $item->{price}           if ($item->{selected} eq ' selected'); 
      $form->{"price_new_$i"}      = $form->{"sellprice_$i"};  
    }
  } else {
    #Einkaufsbelege
    if ($form->{"sellprice_$i"} == $form->round_amount($form->{"price_new_$i"}, 2 )) {$form->{"sellprice_$i"} = $form->{"price_new_$i"};}
    $form->{"sellprice_$i"} = $form->format_amount(\%myconfig, $form->{"sellprice_$i"}, 5);
    $form->{"price_new_$i"}      = $form->{"sellprice_$i"};
  }
  
  $main::lxdebug->leave_sub();
}

sub set_pricegroup {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my $locale   = $main::locale;
  my $cgi      = $main::cgi;

  _check_io_auth();

  my $rowcount = shift;
  for my $j (1 .. $rowcount) {
    next unless $form->{PRICES}{$j};
    # build drop down list for pricegroups
    my $option_tmpl = qq|<option value="%s--%s" %s>%s</option>|;
    $form->{"prices_$j"}  = join '', map { sprintf $option_tmpl, @$_{qw(price pricegroup_id selected pricegroup)} }
                                         ( @{ $form->{PRICES}{$j} });

    foreach my $item (@{ $form->{PRICES}{$j} }) {
      # set new selectedpricegroup_id and prices for "Preis"
      $form->{"pricegroup_old_$j"} = $item->{pricegroup_id}   if $item->{selected} &&  $item->{pricegroup_id};
      $form->{"sellprice_$j"}      = $item->{price}           if $item->{selected} &&  $item->{pricegroup_id};
      $form->{"price_new_$j"}      = $form->{"sellprice_$j"}  if $item->{selected} || !$item->{pricegroup_id};
    }
  }
  $main::lxdebug->leave_sub();
}

sub select_item {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my $cgi      = $main::cgi;

# diese variable kommt schon in der methode display_row vor, kann man die besser wiederverwenden? @mb fragen.  ich check das jetzt erstmal so ein
  my $is_purchase        = (first { $_ eq $form->{type} } qw(request_quotation purchase_order purchase_delivery_order)) || ($form->{script} eq 'ir.pl');
  _check_io_auth();

  my @column_index = qw(ndx partnumber description rop onhand unit sellprice);
  my %column_data;
  $column_data{ndx}        = qq|<th>&nbsp;</th>|;
  $column_data{partnumber} =
    qq|<th class="listheading">| . $locale->text('Number') . qq|</th>|;
  $column_data{description} =
    qq|<th class="listheading">| . $locale->text('Part Description') . qq|</th>|;
  $column_data{sellprice} =
    qq|<th class="listheading">| . $locale->text('Price') . qq|</th>|;
    if ($is_purchase){
      $column_data{rop} =
      qq|<th class="listheading">| . $locale->text('ROP') . qq|</th>|;
    }# ende if $is_purchase -> Überschrift Mindestlagerbestand - ähnliche Prüfung weiter unten
  $column_data{onhand} =
    qq|<th class="listheading">| . $locale->text('Qty') . qq|</th>|;
  $column_data{unit} =
    qq|<th class="listheading">| . $locale->text('Unit') . qq|</th>|;
  # list items with radio button on a form
  $form->header;

  my $title   = $locale->text('Select from one of the items below');
  my $colspan = $#column_index + 1;

  print qq|
  <body>

<form method="post" action="$form->{script}">

<table width="100%">
  <tr>
    <th class="listtop" colspan="$colspan">$title</th>
  </tr>
  <tr height="5"></tr>
  <tr class="listheading">|;

  map { print "\n$column_data{$_}" } @column_index;

  print qq|</tr>|;

  my @new_fields =
    qw(bin listprice inventory_accno income_accno expense_accno unit weight
       assembly taxaccounts partsgroup formel longdescription not_discountable
       part_payment_id partnotes id lastcost price_factor_id price_factor);
  push @new_fields, "lizenzen" if $::lx_office_conf{features}->{lizenzen};
  push @new_fields, grep { m/^ic_cvar_/ } keys %{ $form->{item_list}->[0] };

  my $i = 0;
  my $j;
  foreach my $ref (@{ $form->{item_list} }) {
    my $checked = ($i++) ? "" : "checked";

    if ($::lx_office_conf{features}->{lizenzen}) {
      if ($ref->{inventory_accno} > 0) {
        $ref->{"lizenzen"} = qq|<option></option>|;
        foreach my $item (@{ $form->{LIZENZEN}{ $ref->{"id"} } }) {
          $ref->{"lizenzen"} .=
            qq|<option value=\"$item->{"id"}\">$item->{"licensenumber"}</option>|;
        }
        $ref->{"lizenzen"} .= qq|<option value="-1">Neue Lizenz</option>|;
        $ref->{"lizenzen"} =~ s/\"/&quot;/g;
      }
    }

    map { $ref->{$_} =~ s/\"/&quot;/g } qw(partnumber description unit);

    my $display_sellprice  = $ref->{sellprice};
    $display_sellprice    /= $ref->{price_factor} if ($ref->{price_factor});
    $display_sellprice     = $form->format_amount(\%myconfig, $display_sellprice, 2);

    $column_data{ndx} =
      qq|<td><input name="ndx" class="radio" type="radio" value="$i" $checked></td>|;
    $column_data{partnumber} =
      qq|<td><input name="new_partnumber_$i" type="hidden" value="$ref->{partnumber}">$ref->{partnumber}</td>|;
    $column_data{description} =
      qq|<td><input name="new_description_$i" type="hidden" value="$ref->{description}">$ref->{description}</td>|;
    $column_data{sellprice} =
      qq|<td align="right"><input name="new_sellprice_$i" type="hidden" value="$ref->{sellprice}">|
      . $display_sellprice
      . qq|</td>|;
    $column_data{onhand} =
      qq|<td align="right"><input name="new_onhand_$i" type="hidden" value="$ref->{onhand}">|
      . $form->format_amount(\%myconfig, $ref->{onhand}, '', "&nbsp;")
      . qq|</td>|;
    if ($is_purchase){
    $column_data{rop} =
      qq|<td align="right"><input name="new_rop$i" type="hidden" value="$ref->{rop}">|
      . $form->format_amount(\%myconfig, $ref->{rop}, '', "&nbsp;")
      . qq|</td>|;
    }# ende if $is_purchase -> Falls der Aufruf über eine Einkaufsmaske kam, handelt es sich um einen Lieferantenauftrag und uns interessiert auch die Mindestbestandsmenge
    $column_data{unit} =
      qq|<td>$ref->{unit}</td>|;
    $j++;
    $j %= 2;
    print qq|
<tr class=listrow$j>|;

    map { print "\n$column_data{$_}" } @column_index;

    print("</tr>\n");

    print join "\n", map { $cgi->hidden("-name" => "new_${_}_$i", "-value" => $ref->{$_}) } @new_fields;
    print "\n";
  }

  print qq|
<tr><td colspan="8"><hr size="3" noshade></td></tr>
</table>

<input name="lastndx" type="hidden" value="$i">

|;

  # delete action variable
  map { delete $form->{$_} } qw(action item_list header);

  # save all other form variables
  foreach my $key (keys %${form}) {
    next if (($key eq 'login') || ($key eq 'password') || ('' ne ref $form->{$key}));
    $form->{$key} =~ s/\"/&quot;/g;
    print qq|<input name="$key" type="hidden" value="$form->{$key}">\n|;
  }

  print qq|
<input type="hidden" name="nextsub" value="item_selected">

<br>
<input class="submit" type="submit" name="action" value="|
    . $locale->text('Continue') . qq|">
</form>

</body>
</html>
|;

  $main::lxdebug->leave_sub();
}

sub item_selected {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  _check_io_auth();

  # replace the last row with the checked row
  my $i = $form->{rowcount};
  $i = $form->{assembly_rows} if ($form->{item} eq 'assembly');

  # index for new item
  my $j = $form->{ndx};

  #sk
  #($form->{"sellprice_$i"},$form->{"$pricegroup_old_$i"}) = split /--/, $form->{"sellprice_$i"};
  #$form->{"sellprice_$i"} = $form->{"sellprice_$i"};

  # if there was a price entered, override it
  my $sellprice = $form->parse_amount(\%myconfig, $form->{"sellprice_$i"});

  my @new_fields =
    qw(id partnumber description sellprice listprice inventory_accno
       income_accno expense_accno bin unit weight assembly taxaccounts
       partsgroup formel longdescription not_discountable partnotes lastcost
       price_factor_id price_factor);

  my $ic_cvar_configs = CVar->get_configs(module => 'IC');
  push @new_fields, map { "ic_cvar_$_->{name}" } @{ $ic_cvar_configs };

  map { $form->{"${_}_$i"} = $form->{"new_${_}_$j"} } @new_fields;

  $form->{"marge_price_factor_$i"} = $form->{"new_price_factor_$j"};

  if ($form->{"part_payment_id_$i"} ne "") {
    $form->{payment_id} = $form->{"part_payment_id_$i"};
  }

  if ($::lx_office_conf{features}->{lizenzen}) {
    map { $form->{"${_}_$i"} = $form->{"new_${_}_$j"} } qw(lizenzen);
  }

  my ($dec) = ($form->{"sellprice_$i"} =~ /\.(\d+)/);
  $dec           = length $dec;
  my $decimalplaces = ($dec > 2) ? $dec : 2;

  if ($sellprice) {
    $form->{"sellprice_$i"} = $sellprice;
  } else {
#wird in get_pricegroups_new erledigt:
    # if there is an exchange rate adjust sellprice
    #if (($form->{exchangerate} * 1) != 0) {
    #  $form->{"sellprice_$i"} /= $form->{exchangerate};
    #  $form->{"sellprice_$i"} =
    #    $form->round_amount($form->{"sellprice_$i"}, $decimalplaces);
    #}
  }

  map { $form->{$_} = $form->parse_amount(\%myconfig, $form->{$_}) }
    qw(sellprice listprice weight);

  $form->{sellprice} += ($form->{"sellprice_$i"} * $form->{"qty_$i"});
  $form->{weight}    += ($form->{"weight_$i"} * $form->{"qty_$i"});

  if ($form->{"not_discountable_$i"}) {
    $form->{"discount_$i"} = 0;
  }

  my $amount =
    $form->{"sellprice_$i"} * (1 - $form->{"discount_$i"} / 100) *
    $form->{"qty_$i"};
  map { $form->{"${_}_base"} += $amount }
    (split / /, $form->{"taxaccounts_$i"});
  map { $amount += ($form->{"${_}_base"} * $form->{"${_}_rate"}) } split / /,
    $form->{"taxaccounts_$i"}
    if !$form->{taxincluded};

  $form->{creditremaining} -= $amount;

  $form->{"runningnumber_$i"} = $i;

  # delete all the new_ variables
  for $i (1 .. $form->{lastndx}) {
    map { delete $form->{"new_${_}_$i"} } @new_fields;
  }

  map { delete $form->{$_} } qw(ndx lastndx nextsub);

  # format amounts
  map {
    $form->{"${_}_$i"} =
      $form->format_amount(\%myconfig, $form->{"${_}_$i"}, $decimalplaces)
  } qw(sellprice listprice lastcost) if $form->{item} ne 'assembly';
  # muß das hier nochmal sein? erstmal raus!
  # get pricegroups for parts
  # IS->get_pricegroups_for_parts(\%myconfig, \%$form);

  # build up html code for prices_$i
  # set_pricegroup($form->{rowcount});

  &display_form;

  $main::lxdebug->leave_sub();
}

sub new_item {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  _check_io_auth();

  my $price_key = ($form->{type} =~ m/request_quotation|purchase_order/) || ($form->{script} eq 'ir.pl') ? 'lastcost' : 'sellprice';
  
  if ($form->{redraw}) { 
    map {$form->{"${_}_$form->{rowcount}"} = $form->{${_}}} qw(partnumber description qty sellprice longdescription unit);
    # change callback
    $form->{old_callback} = $form->escape($form->{callback}, 1);
    $form->{callback}     = $form->escape("$form->{script}?action=display_form", 1);
  } else {
    # change callback
    $form->{old_callback} = $form->escape($form->{callback}, 1);
    $form->{callback}     = $form->escape("$form->{script}?action=display_form", 1);
  }

  # save all form variables except action in the session and keep the key in the previousform variable
  my $previousform = $::auth->save_form_in_session(skip_keys => [ qw(action) ]);

  my @HIDDENS;
  push @HIDDENS,      { 'name' => 'previousform', 'value' => $previousform };
  push @HIDDENS, map +{ 'name' => $_,             'value' => $form->{$_} },                       qw(rowcount vc redraw);
  push @HIDDENS, map +{ 'name' => $_,             'value' => $form->{"${_}_$form->{rowcount}"} }, qw(partnumber description unit);
  push @HIDDENS,      { 'name' => 'taxaccount2',  'value' => $form->{taxaccounts} };
  push @HIDDENS,      { 'name' => $price_key,     'value' => $form->parse_amount(\%myconfig, $form->{"sellprice_$form->{rowcount}"}) };
  push @HIDDENS,      { 'name' => 'notes',        'value' => $form->{"longdescription_$form->{rowcount}"} };

  $form->header();
  print $form->parse_html_template("generic/new_item", { HIDDENS => [ sort { $a->{name} cmp $b->{name} } @HIDDENS ] } );

  $main::lxdebug->leave_sub();
}

sub check_form {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  _check_io_auth();

  my @a     = ();
  my $count = 0;

  # remove any makes or model rows
  if ($form->{item} eq 'part') {
    map { $form->{$_} = $form->parse_amount(\%myconfig, $form->{$_}) }
      qw(listprice sellprice lastcost weight rop);

  } elsif ($form->{item} eq 'assembly') {

    # fuer assemblies auskommentiert. seiteneffekte? ;-) wird die woanders benoetigt?
    #$form->{sellprice} = 0;
    $form->{weight}    = 0;
    map { $form->{$_} = $form->parse_amount(\%myconfig, $form->{$_}) }
      qw(listprice sellprice rop stock);

    my @flds = qw(id qty unit bom partnumber description sellprice weight runningnumber partsgroup lastcost);

    for my $i (1 .. ($form->{assembly_rows} - 1)) {
      if ($form->{"qty_$i"}) {
        push @a, {};
        my $j = $#a;

        $form->{"qty_$i"} = $form->parse_amount(\%myconfig, $form->{"qty_$i"});

        map { $a[$j]->{$_} = $form->{"${_}_$i"} } @flds;

        #($form->{"sellprice_$i"},$form->{"$pricegroup_old_$i"}) = split /--/, $form->{"sellprice_$i"};

        # fuer assemblies auskommentiert. siehe oben
        #    $form->{sellprice} += ($form->{"qty_$i"} * $form->{"sellprice_$i"} / ($form->{"price_factor_$i"} || 1));
        $form->{weight}    += ($form->{"qty_$i"} * $form->{"weight_$i"} / ($form->{"price_factor_$i"} || 1));
        $count++;
      }
    }
    # kann das hier auch weg? s.o. jb
    $form->{sellprice} = $form->round_amount($form->{sellprice}, 2);

    $form->redo_rows(\@flds, \@a, $count, $form->{assembly_rows});
    $form->{assembly_rows} = $count;

  } elsif ($form->{item} eq 'service') {
    map { $form->{$_} = $form->parse_amount(\%myconfig, $form->{$_}) } qw(listprice sellprice lastcost);

  } else {
    remove_emptied_rows(1);

    $form->{creditremaining} -= &invoicetotal;
  }

  #sk
  # if pricegroups
  if (   $form->{type} =~ (/sales_quotation/)
      or (($form->{level} =~ /Sales/) and ($form->{type} =~ /invoice/))
      or (($form->{level} eq undef) and ($form->{type} =~ /invoice/))
      or ($form->{type} =~ /sales_order/)) {
    # muß das hier nochmal sein? erstmal raus!
    # get pricegroups for parts
    #IS->get_pricegroups_for_parts(\%myconfig, \%$form);

    # build up html code for prices_$i
    #set_pricegroup($form->{rowcount});

  }

  display_form();

  $main::lxdebug->leave_sub();
}

sub remove_emptied_rows {
  my $dont_add_empty = shift;
  my $form           = $::form;

  return unless $form->{rowcount};

  my @flds = qw(id partnumber description qty ship sellprice unit
                discount inventory_accno income_accno expense_accno listprice
                taxaccounts bin assembly weight projectnumber project_id
                oldprojectnumber runningnumber serialnumber partsgroup payment_id
                not_discountable shop ve gv buchungsgruppen_id language_values
                sellprice_pg pricegroup_old price_old price_new unit_old ordnumber
                transdate longdescription basefactor marge_total marge_percent
                marge_price_factor lastcost price_factor_id partnotes
                stock_out stock_in has_sernumber reqdate tradediscount tradediscount_ori);

  my $ic_cvar_configs = CVar->get_configs(module => 'IC');
  push @flds, map { "ic_cvar_$_->{name}" } @{ $ic_cvar_configs };

  my @new_rows;
  for my $i (1 .. $form->{rowcount} - 1) {
    next unless $form->{"partnumber_$i"};

    push @new_rows, { map { $_ => $form->{"${_}_$i" } } @flds };
  }

  my $new_rowcount = scalar @new_rows;
  $form->redo_rows(\@flds, \@new_rows, $new_rowcount, $form->{rowcount});
  $form->{rowcount} = $new_rowcount + ($dont_add_empty ? 0 : 1);
}

sub invoicetotal {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  _check_io_auth();

  $form->{oldinvtotal} = 0;

  # add all parts and deduct paid
  map { $form->{"${_}_base"} = 0 } split / /, $form->{taxaccounts};

  my ($amount, $sellprice, $discount, $qty);

  for my $i (1 .. $form->{rowcount}) {
    $sellprice = $form->parse_amount(\%myconfig, $form->{"sellprice_$i"});
    $discount  = $form->parse_amount(\%myconfig, $form->{"discount_$i"});
    $qty       = $form->parse_amount(\%myconfig, $form->{"qty_$i"});

    #($form->{"sellprice_$i"}, $form->{"$pricegroup_old_$i"}) = split /--/, $form->{"sellprice_$i"};

    $amount = $sellprice * (1 - $discount / 100) * $qty;
    map { $form->{"${_}_base"} += $amount }
      (split (/ /, $form->{"taxaccounts_$i"}));
    $form->{oldinvtotal} += $amount;
  }

  map { $form->{oldinvtotal} += ($form->{"${_}_base"} * $form->{"${_}_rate"}) }
    split(/ /, $form->{taxaccounts})
    if !$form->{taxincluded};

  $form->{oldtotalpaid} = 0;
  for my $i (1 .. $form->{paidaccounts}) {
    $form->{oldtotalpaid} += $form->{"paid_$i"};
  }

  $main::lxdebug->leave_sub();

  # return total
  return ($form->{oldinvtotal} - $form->{oldtotalpaid});
}

sub validate_items {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my $locale   = $main::locale;

  _check_io_auth();

  # check if items are valid
  if ($form->{rowcount} == 1) {
    &update;
    ::end_of_request();
  }

  for my $i (1 .. $form->{rowcount} - 1) {
    $form->isblank("partnumber_$i",
                   $locale->text('Number missing in Row') . " $i");
  }

  $main::lxdebug->leave_sub();
}

sub order {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  _check_io_auth();

  if ($form->{second_run}) {
    $form->{print_and_post} = 0;
  }
  $form->{ordnumber} = $form->{invnumber};

  $form->{old_employee_id} = $form->{employee_id};
  $form->{old_salesman_id} = $form->{salesman_id};

  map { delete $form->{$_} } qw(id printed emailed queued);
  my $buysell;
  if ($form->{script} eq 'ir.pl' || $form->{type} eq 'request_quotation') {
    $form->{title} = $locale->text('Add Purchase Order');
    $form->{vc}    = 'vendor';
    $form->{type}  = 'purchase_order';
    $buysell       = 'sell';
  }
  if ($form->{script} eq 'is.pl' || $form->{type} eq 'sales_quotation') {
    $form->{title} = $locale->text('Add Sales Order');
    $form->{vc}    = 'customer';
    $form->{type}  = 'sales_order';
    $buysell       = 'buy';
  }
  $form->{script} = 'oe.pl';

  $form->{shipto} = 1;

  $form->{rowcount}--;

  $form->{cp_id} *= 1;

  require "bin/mozilla/$form->{script}";
  my $script = $form->{"script"};
  $script =~ s|.*/||;
  $script =~ s|.pl$||;
  $locale = new Locale($::lx_office_conf{system}->{language}, $script);

  map { $form->{"select$_"} = "" } ($form->{vc}, "currency");

  my $currency = $form->{currency};

  &order_links;

  $form->{currency}     = $currency;
  $form->{forex}        = $form->check_exchangerate(\%myconfig, $form->{currency}, $form->{transdate}, $buysell);
  $form->{exchangerate} = $form->{forex} || '';

  for my $i (1 .. $form->{rowcount}) {
    map({ $form->{"${_}_${i}"} = $form->parse_amount(\%myconfig, $form->{"${_}_${i}"})
            if ($form->{"${_}_${i}"}) }
        qw(ship qty sellprice listprice basefactor discount));
  }

  &prepare_order;
  &display_form;

  $main::lxdebug->leave_sub();
}

sub quotation {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  _check_io_auth();

  if ($form->{second_run}) {
    $form->{print_and_post} = 0;
  }
  map { delete $form->{$_} } qw(id printed emailed queued);

  my $buysell;
  if ($form->{script} eq 'ir.pl' || $form->{type} eq 'purchase_order') {
    $form->{title} = $locale->text('Add Request for Quotation');
    $form->{vc}    = 'vendor';
    $form->{type}  = 'request_quotation';
    $buysell       = 'sell';
  }
  if ($form->{script} eq 'is.pl' || $form->{type} eq 'sales_order') {
    $form->{title} = $locale->text('Add Quotation');
    $form->{vc}    = 'customer';
    $form->{type}  = 'sales_quotation';
    $buysell       = 'buy';
  }

  $form->{cp_id} *= 1;

  $form->{script} = 'oe.pl';

  $form->{shipto} = 1;

  $form->{rowcount}--;

  require "bin/mozilla/$form->{script}";

  map { $form->{"select$_"} = "" } ($form->{vc}, "currency");

  my $currency = $form->{currency};

  &order_links;

  $form->{currency}     = $currency;
  $form->{forex}        = $form->check_exchangerate( \%myconfig, $form->{currency}, $form->{transdate}, $buysell);
  $form->{exchangerate} = $form->{forex} || '';

  for my $i (1 .. $form->{rowcount}) {
    map({ $form->{"${_}_${i}"} = $form->parse_amount(\%myconfig,
                                                     $form->{"${_}_${i}"})
            if ($form->{"${_}_${i}"}) }
        qw(ship qty sellprice listprice basefactor discount));
  }

  &prepare_order;
  &display_form;

  $main::lxdebug->leave_sub();
}

sub request_for_quotation {
  quotation();
}

sub edit_e_mail {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  _check_io_auth();

  if ($form->{second_run}) {
    $form->{print_and_post} = 0;
    $form->{resubmit}       = 0;
  }

  $form->{email} = $form->{shiptoemail} if $form->{shiptoemail} && $form->{formname} =~ /(pick|packing|bin)_list/;

  if ($form->{"cp_id"}) {
    CT->get_contact(\%myconfig, $form);
    $form->{"email"} = $form->{"cp_email"} if $form->{"cp_email"};
  }

  my $title = $locale->text('E-mail') . " " . $form->get_formname_translation();

  $form->{oldmedia} = $form->{media};
  $form->{media}    = "email";

  my $attachment_filename = $form->generate_attachment_filename();
  my $subject             = $form->{subject} || $form->generate_email_subject();

  $form->{"fokus"} = $form->{"email"} ? "Form.subject" : "Form.email";
  $form->header;

  my (@dont_hide_key_list, %dont_hide_key, @hidden_keys);
  @dont_hide_key_list = qw(action email cc bcc subject message sendmode format header override login password);
  @dont_hide_key{@dont_hide_key_list} = (1) x @dont_hide_key_list;
  @hidden_keys = sort grep { !$dont_hide_key{$_} } grep { !ref $form->{$_} } keys %$form;

  print $form->parse_html_template('generic/edit_email',
                                   { title         => $title,
                                     a_filename    => $attachment_filename,
                                     subject       => $subject,
                                     print_options => print_options('inline' => 1),
                                     HIDDEN        => [ map +{ name => $_, value => $form->{$_} }, @hidden_keys ],
                                     SHOW_BCC      => $myconfig{role} eq 'admin' });

  $main::lxdebug->leave_sub();
}

sub send_email {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  _check_io_auth();

  my $callback = $form->{script} . "?action=edit";
  map({ $callback .= "\&${_}=" . E($form->{$_}); } qw(type id));

  print_form("return");

  Common->save_email_status(\%myconfig, $form);

  $form->{callback} = $callback;
  $form->redirect();

  $main::lxdebug->leave_sub();
}

# generate the printing options displayed at the bottom of oe and is forms.
# this function will attempt to guess what type of form is displayed, and will generate according options
#
# about the coding:
# this version builds the arrays of options pretty directly. if you have trouble understanding how,
# the opthash function builds hashrefs which are then pieced together for the template arrays.
# unneeded options are "undef"ed out, and then grepped out.
#
# the inline options is untested, but intended to be used later in metatemplating
sub print_options {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  _check_io_auth();

  my %options = @_;

  # names 3 parameters and returns a hashref, for use in templates
  sub opthash { +{ value => shift, selected => shift, oname => shift } }
  my (@FORMNAME, @LANGUAGE_ID, @FORMAT, @SENDMODE, @MEDIA, @PRINTER_ID, @SELECTS) = ();

  # note: "||"-selection is only correct for values where "0" is _not_ a correct entry
  $form->{sendmode}   = "attachment";
  $form->{format}     = $form->{format} || $myconfig{template_format} || "pdf";
  $form->{copies}     = $form->{copies} || $myconfig{copies}          || 3;
  $form->{media}      = $form->{media}  || $myconfig{default_media}   || "screen";
  $form->{printer_id} = defined $form->{printer_id}           ? $form->{printer_id} :
                        defined $myconfig{default_printer_id} ? $myconfig{default_printer_id} : "";

  $form->{PD}{ $form->{formname} } = "selected";
  $form->{DF}{ $form->{format} }   = "selected";
  $form->{OP}{ $form->{media} }    = "selected";
  $form->{SM}{ $form->{formname} } = "selected";

  push @FORMNAME, grep $_,
    ($form->{type} eq 'purchase_order') ? (
      opthash("purchase_order",      $form->{PD}{purchase_order},      $locale->text('Purchase Order')),
      opthash("bin_list",            $form->{PD}{bin_list},            $locale->text('Bin List'))
    ) : undef,
    ($form->{type} eq 'credit_note') ?
      opthash("credit_note",         $form->{PD}{credit_note},         $locale->text('Credit Note')) : undef,
    ($form->{type} eq 'sales_order') ? (
      opthash("sales_order",         $form->{PD}{sales_order},         $locale->text('Confirmation')),
      opthash("proforma",            $form->{PD}{proforma},            $locale->text('Proforma Invoice')),
    ) : undef,
    ($form->{type} =~ /sales_quotation$/) ?
      opthash('sales_quotation',     $form->{PD}{sales_quotation},     $locale->text('Quotation')) : undef,
    ($form->{type} =~ /request_quotation$/) ?
      opthash('request_quotation',   $form->{PD}{request_quotation},   $locale->text('Request for Quotation')) : undef,
    ($form->{type} eq 'invoice') ? (
      opthash("invoice",             $form->{PD}{invoice},             $locale->text('Invoice')),
      opthash("proforma",            $form->{PD}{proforma},            $locale->text('Proforma Invoice')),
    ) : undef,
    ($form->{type} eq 'invoice' && $form->{storno}) ? (
      opthash("storno_invoice",      $form->{PD}{storno_invoice},      $locale->text('Storno Invoice')),
    ) : undef,
    ($form->{type} =~ /_delivery_order$/) ? (
      opthash($form->{type},         $form->{PD}{$form->{type}},       $locale->text('Delivery Order')),
      opthash('pick_list',           $form->{PD}{pick_list},           $locale->text('Pick List')),
    ) : undef;

  push @SENDMODE,
    opthash("attachment",            $form->{SM}{attachment},          $locale->text('Attachment')),
    opthash("inline",                $form->{SM}{inline},              $locale->text('In-line'))
      if ($form->{media} eq 'email');

  push @MEDIA, grep $_,
      opthash("screen",              $form->{OP}{screen},              $locale->text('Screen')),
    ($form->{printers} && scalar @{ $form->{printers} } && $::lx_office_conf{print_templates}->{latex}) ?
      opthash("printer",             $form->{OP}{printer},             $locale->text('Printer')) : undef,
    ($::lx_office_conf{print_templates}->{latex} && !$options{no_queue}) ?
      opthash("queue",               $form->{OP}{queue},               $locale->text('Queue')) : undef
        if ($form->{media} ne 'email');

  push @FORMAT, grep $_,
    ($::lx_office_conf{print_templates}->{opendocument} &&     $::lx_office_conf{applications}->{openofficeorg_writer}  &&     $::lx_office_conf{applications}->{xvfb}
                                                        && (-x $::lx_office_conf{applications}->{openofficeorg_writer}) && (-x $::lx_office_conf{applications}->{xvfb})
     && !$options{no_opendocument_pdf}) ?
      opthash("opendocument_pdf",    $form->{DF}{"opendocument_pdf"},  $locale->text("PDF (OpenDocument/OASIS)")) : undef,
    ($::lx_office_conf{print_templates}->{latex}) ?
      opthash("pdf",                 $form->{DF}{pdf},                 $locale->text('PDF')) : undef,
    ($::lx_office_conf{print_templates}->{latex} && !$options{no_postscript}) ?
      opthash("postscript",          $form->{DF}{postscript},          $locale->text('Postscript')) : undef,
    (!$options{no_html}) ?
      opthash("html", $form->{DF}{html}, "HTML") : undef,
    ($::lx_office_conf{print_templates}->{opendocument} && !$options{no_opendocument}) ?
      opthash("opendocument",        $form->{DF}{opendocument},        $locale->text("OpenDocument/OASIS")) : undef,
    ($::lx_office_conf{print_templates}->{excel} && !$options{no_excel}) ?
      opthash("excel",               $form->{DF}{excel},               $locale->text("Excel")) : undef;

  push @LANGUAGE_ID,
    map { opthash($_->{id}, ($_->{id} eq $form->{language_id} ? 'selected' : ''), $_->{description}) } +{}, @{ $form->{languages} }
      if (ref $form->{languages} eq 'ARRAY');

  push @PRINTER_ID,
    map { opthash($_->{id}, ($_->{id} eq $form->{printer_id} ? 'selected' : ''), $_->{printer_description}) } +{}, @{ $form->{printers} }
      if ((ref $form->{printers} eq 'ARRAY') && scalar @{ $form->{printers } });

  @SELECTS = map {
    sname => $_->[1],
    DATA  => $_->[0],
    show  => !$options{"hide_" . $_->[1]} && scalar @{ $_->[0] }
  },
  [ \@FORMNAME,    'formname',    ],
  [ \@LANGUAGE_ID, 'language_id', ],
  [ \@FORMAT,      'format',      ],
  [ \@SENDMODE,    'sendmode',    ],
  [ \@MEDIA,       'media',       ],
  [ \@PRINTER_ID,  'printer_id',  ];

  my %dont_display_groupitems = (
    'dunning' => 1,
    );

  my %template_vars = (
    display_copies       => scalar @{ $form->{printers} || [] } && $::lx_office_conf{print_templates}->{latex} && $form->{media} ne 'email',
    display_remove_draft => (!$form->{id} && $form->{draft_id}),
    display_groupitems   => !$dont_display_groupitems{$form->{type}},
    groupitems_checked   => $form->{groupitems} ? "checked" : '',
    remove_draft_checked => $form->{remove_draft} ? "checked" : ''
  );

  my $print_options = $form->parse_html_template("generic/print_options", { SELECTS  => \@SELECTS, %template_vars } );

  if ($options{inline}) {
    $main::lxdebug->leave_sub();
    return $print_options;
  }

  print $print_options;

  $main::lxdebug->leave_sub();
}

sub print {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my $locale   = $main::locale;

  _check_io_auth();

  if ($form->{print_nextsub}) {
    call_sub($form->{print_nextsub});
    $main::lxdebug->leave_sub();
    return;
  }

  # if this goes to the printer pass through
  my $old_form;
  if ($form->{media} eq 'printer' || $form->{media} eq 'queue') {
    $form->error($locale->text('Select postscript or PDF!'))
      if ($form->{format} !~ /(postscript|pdf)/);

    $old_form = new Form;
    map { $old_form->{$_} = $form->{$_} } keys %$form;
  }

  if (!$form->{id} || (($form->{formname} eq "proforma") && !$form->{proforma} && (($form->{type} =~ /_order$/) || ($form->{type} =~ /_quotation$/)))) {
    if ($form->{formname} eq "proforma") {
      $form->{proforma} = 1;
    }
    $form->{print_and_save} = 1;
    my $formname = $form->{formname};
    &save();
    $form->{formname} = $formname;
    &edit();
    $::lxdebug->leave_sub();
    ::end_of_request();
  }

  &print_form($old_form);

  $main::lxdebug->leave_sub();
}

sub print_form {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  _check_io_auth();

  my ($old_form) = @_;

  my $inv       = "inv";
  my $due       = "due";
  my $numberfld = "invnumber";
  my $order;

  my $display_form =
    ($form->{display_form}) ? $form->{display_form} : "display_form";

  # $form->{"notes"} will be overridden by the customer's/vendor's "notes" field. So save it here.
  $form->{ $form->{"formname"} . "notes" } = $form->{"notes"};

  if ($form->{formname} eq "invoice") {
    $form->{label} = $locale->text('Invoice');
  }
  if ($form->{formname} eq 'sales_order') {
    $inv                  = "ord";
    $due                  = "req";
    $form->{"${inv}date"} = $form->{transdate};
    $form->{label}        = $locale->text('Confirmation');
    $numberfld            = "sonumber";
    $order                = 1;
  }

  if (($form->{type} eq 'invoice') && ($form->{formname} eq 'proforma') ) {
    $inv                  = "inv";
    $due                  = "due";
    $form->{"${inv}date"} = $form->{invdate};
    $form->{label}        = $locale->text('Proforma Invoice');
    $numberfld            = "sonumber";
    $order                = 0;
  }

  if (($form->{type} eq 'sales_order') && ($form->{formname} eq 'proforma') ) {
    $inv                  = "inv";
    $due                  = "due";
    $form->{"${inv}date"} = $form->{transdate};
    $form->{"invdate"}    = $form->{transdate};
    $form->{invnumber}    = $form->{ordnumber};
    $form->{label}        = $locale->text('Proforma Invoice');
    $numberfld            = "sonumber";
    $order                = 1;
  }

  if ($form->{formname} eq 'purchase_order') {
    $inv                  = "ord";
    $due                  = "req";
    $form->{"${inv}date"} = $form->{transdate};
    $form->{label}        = $locale->text('Purchase Order');
    $numberfld            = "ponumber";
    $order                = 1;
  }
  if ($form->{formname} eq 'bin_list') {
    $inv                  = "ord";
    $due                  = "req";
    $form->{"${inv}date"} = $form->{transdate};
    $form->{label}        = $locale->text('Bin List');
    $order                = 1;
  }
  if ($form->{formname} eq 'sales_quotation') {
    $inv                  = "quo";
    $due                  = "req";
    $form->{"${inv}date"} = $form->{transdate};
    $form->{label}        = $locale->text('Quotation');
    $numberfld            = "sqnumber";
    $order                = 1;
  }

  if (($form->{type} eq 'sales_quotation') && ($form->{formname} eq 'proforma') ) {
    $inv                  = "quo";
    $due                  = "req";
    $form->{"${inv}date"} = $form->{transdate};
    $form->{"invdate"}    = $form->{transdate};
    $form->{label}        = $locale->text('Proforma Invoice');
    $numberfld            = "sqnumber";
    $order                = 1;
  }

  if ($form->{formname} eq 'request_quotation') {
    $inv                  = "quo";
    $due                  = "req";
    $form->{"${inv}date"} = $form->{transdate};
    $form->{label}        = $locale->text('RFQ');
    $numberfld            = "rfqnumber";
    $order                = 1;
  }

  if ($form->{type} =~ /_delivery_order$/) {
    undef $due;
    $inv                  = "do";
    $form->{"${inv}date"} = $form->{transdate};
    $numberfld            = $form->{type} =~ /^sales/ ? 'sdonumber' : 'pdonumber';
    $form->{label}        = $form->{formname} eq 'pick_list' ? $locale->text('Pick List') : $locale->text('Delivery Order');
  }

  $form->isblank("email", $locale->text('E-mail address missing!'))
    if ($form->{media} eq 'email');
  $form->isblank("${inv}date",
           $locale->text($form->{label})
           . ": "
           . $locale->text(' Date missing!'));

  # $locale->text('Invoice Number missing!')
  # $locale->text('Invoice Date missing!')
  # $locale->text('Order Number missing!')
  # $locale->text('Order Date missing!')
  # $locale->text('Quotation Number missing!')
  # $locale->text('Quotation Date missing!')

  # assign number
  $form->{what_done} = $form->{formname};
  if (!$form->{"${inv}number"} && !$form->{preview} && !$form->{id}) {
    $form->{"${inv}number"} = $form->update_defaults(\%myconfig, $numberfld);
    if ($form->{media} ne 'email') {
      # muß das hier nochmal sein? erstmal raus!  
      # get pricegroups for parts
      #IS->get_pricegroups_for_parts(\%myconfig, \%$form);

      # build up html code for prices_$i
      #set_pricegroup($form->{rowcount});

      $form->{rowcount}--;

      call_sub($display_form);
      # saving the history
      if(!exists $form->{addition}) {
        $form->{snumbers} = qq|ordnumber_| . $form->{ordnumber};
        $form->{addition} = "PRINTED";
        $form->save_history;
      }
      # /saving the history
      ::end_of_request();
    }
  }

  &validate_items;

  # Save the email address given in the form because it should override the setting saved for the customer/vendor.
  my ($saved_email, $saved_cc, $saved_bcc) =
    ($form->{"email"}, $form->{"cc"}, $form->{"bcc"});

  my $language_saved = $form->{language_id};
  my $payment_id_saved = $form->{payment_id};
  my $salesman_id_saved = $form->{salesman_id};
  my $cp_id_saved = $form->{cp_id};

  call_sub("$form->{vc}_details") if ($form->{vc});

  $form->{language_id} = $language_saved;
  $form->{payment_id} = $payment_id_saved;

  $form->{"email"} = $saved_email if ($saved_email);
  $form->{"cc"}    = $saved_cc    if ($saved_cc);
  $form->{"bcc"}   = $saved_bcc   if ($saved_bcc);

  if (!$cp_id_saved) {
    # No contact was selected. Delete all contact variables because
    # IS->customer_details() and IR->vendor_details() get the default
    # contact anyway.
    map({ delete($form->{$_}); } grep(/^cp_/, keys(%{ $form })));
  }

  my ($language_tc, $output_numberformat, $output_dateformat, $output_longdates);
  if ($form->{"language_id"}) {
    ($language_tc, $output_numberformat, $output_dateformat, $output_longdates) =
      AM->get_language_details(\%myconfig, $form, $form->{language_id});
  } else {
    $output_dateformat = $myconfig{"dateformat"};
    $output_numberformat = $myconfig{"numberformat"};
    $output_longdates = 1;
  }

  ($form->{employee}) = split /--/, $form->{employee};

  # create the form variables
  if ($form->{type} =~ /_delivery_order$/) {
    DO->order_details();
  } elsif ($order) {
    OE->order_details(\%myconfig, \%$form);
  } else {
    IS->invoice_details(\%myconfig, \%$form, $locale);
  }

  $form->get_employee_data('prefix' => 'employee', 'id' => $form->{employee_id});
  $form->get_employee_data('prefix' => 'salesman', 'id' => $salesman_id_saved);

  if ($form->{shipto_id}) {
    $form->get_shipto(\%myconfig);
  }

  my @a = qw(name street zipcode city country contact);

  my $shipto = 1;

  # if there is no shipto fill it in from billto
  foreach my $item (@a) {
    if ($form->{"shipto$item"}) {
      $shipto = 0;
      last;
    }
  }

  if ($shipto) {
    if (   $form->{formname} eq 'purchase_order'
        || $form->{formname} eq 'request_quotation') {
      $form->{shiptoname}   = $myconfig{company};
      $form->{shiptostreet} = $myconfig{address};
    } else {
      map { $form->{"shipto$_"} = $form->{$_} } @a;
    }
  }

  $form->{notes} =~ s/^\s+//g;

  $form->{templates} = "$myconfig{templates}";

  delete $form->{printer_command};

  $form->{language} = $form->get_template_language(\%myconfig);

  my $printer_code;
  if ($form->{media} ne 'email') {
    $printer_code = $form->get_printer_code(\%myconfig);
    if ($printer_code ne "") {
      $printer_code = "_" . $printer_code;
    }
  }

  if ($form->{language} ne "") {
    my $template_arrays = $form->{TEMPLATE_ARRAYS} || $form;
    map { $template_arrays->{unit}->[$_] = AM->translate_units($form, $form->{language}, $template_arrays->{unit}->[$_], $template_arrays->{qty}->[$_]); } (0..scalar(@{ $template_arrays->{unit} }) - 1);

    $form->{language} = "_" . $form->{language};
  }

  # Format dates.
  format_dates($output_dateformat, $output_longdates,
               qw(invdate orddate quodate pldate duedate reqdate transdate
                  shippingdate deliverydate validitydate paymentdate
                  datepaid transdate_oe deliverydate_oe
                  employee_startdate employee_enddate
                  ),
               grep({ /^datepaid_\d+$/ ||
                        /^transdate_oe_\d+$/ ||
                        /^deliverydate_oe_\d+$/ ||
                        /^reqdate_\d+$/ ||
                        /^deliverydate_\d+$/ ||
                        /^transdate_\d+$/
                    } keys(%{$form})));

  reformat_numbers($output_numberformat, 2,
                   qw(invtotal ordtotal quototal subtotal linetotal
                      listprice sellprice netprice discount
                      tax taxbase total paid),
                   grep({ /^(?:linetotal|nodiscount_linetotal|listprice|sellprice|netprice|taxbase|discount|p_discount|discount_sub|nodiscount_sub|paid|subtotal|total|tax)_\d+$/ } keys(%{$form})));

  reformat_numbers($output_numberformat, undef,
                   qw(qty price_factor),
                   grep({ /^qty_\d+$/
                        } keys(%{$form})));

  my ($cvar_date_fields, $cvar_number_fields) = CVar->get_field_format_list('module' => 'CT', 'prefix' => 'vc_');

  if (scalar @{ $cvar_date_fields }) {
    format_dates($output_dateformat, $output_longdates, @{ $cvar_date_fields });
  }

  while (my ($precision, $field_list) = each %{ $cvar_number_fields }) {
    reformat_numbers($output_numberformat, $precision, @{ $field_list });
  }

  my $extension = 'html';
  if ($form->{format} eq 'postscript') {
    $form->{postscript}   = 1;
    $extension            = 'tex';

  } elsif ($form->{"format"} =~ /pdf/) {
    $form->{pdf}          = 1;
    $extension            = $form->{'format'} =~ m/opendocument/i ? 'odt' : 'tex';

  } elsif ($form->{"format"} =~ /opendocument/) {
    $form->{opendocument} = 1;
    $extension            = 'odt';
  } elsif ($form->{"format"} =~ /excel/) {
    $form->{excel} = 1;
    $extension            = 'xls';
  }

  my $email_extension = '_email' if (($form->{media} eq 'email') && (-f "$myconfig{templates}/$form->{formname}_email$form->{language}${printer_code}.${extension}"));

  $form->{IN}         = "$form->{formname}${email_extension}$form->{language}${printer_code}.${extension}";

  delete $form->{OUT};

  if ($form->{media} eq 'printer') {
    #$form->{OUT} = "| $form->{printer_command} &>/dev/null";
    $form->{OUT} = "| $form->{printer_command} ";
    $form->{printed} .= " $form->{formname}";
    $form->{printed} =~ s/^ //;
  }
  my $printed = $form->{printed};

  if ($form->{media} eq 'email') {
    $form->{subject} = qq|$form->{label} $form->{"${inv}number"}|
      unless $form->{subject};

    $form->{emailed} .= " $form->{formname}";
    $form->{emailed} =~ s/^ //;
  }
  my $emailed = $form->{emailed};

  if ($form->{media} eq 'queue') {
    my %queued = map { s|.*/|| } split / /, $form->{queued};

    my $filename;
    if ($filename = $queued{ $form->{formname} }) {
      $form->{queued} =~ s/\Q$form->{formname} $filename\E//;
      unlink $::lx_office_conf{paths}->{spool} . "/$filename";
      $filename =~ s/\..*$//g;
    } else {
      $filename = time;
      $filename .= $$;
    }

    $filename .= ($form->{postscript}) ? '.ps' : '.pdf';
    $form->{OUT} = ">" . $::lx_office_conf{paths}->{spool} . "/$filename";

    # add type
    $form->{queued} .= " $form->{formname} $filename";

    $form->{queued} =~ s/^ //;
  }
  my $queued = $form->{queued};

# saving the history
  if(!exists $form->{addition}) {
    $form->{snumbers} = qq|ordnumber_| . $form->{ordnumber};
    if($form->{media} =~ /printer/) {
      $form->{addition} = "PRINTED";
    }
    elsif($form->{media} =~ /email/) {
      $form->{addition} = "MAILED";
    }
    elsif($form->{media} =~ /queue/) {
      $form->{addition} = "QUEUED";
    }
    elsif($form->{media} =~ /screen/) {
      $form->{addition} = "SCREENED";
    }
    $form->save_history;
  }
  # /saving the history

  $form->parse_template(\%myconfig);

  $form->{callback} = "";

  if ($form->{media} eq 'email') {
    $form->{message} = $locale->text('sent') unless $form->{message};
  }
  my $message = $form->{message};

  # if we got back here restore the previous form
  if ($form->{media} =~ /(printer|email|queue)/) {

    $form->update_status(\%myconfig)
      if ($form->{media} eq 'queue' && $form->{id});

    return $main::lxdebug->leave_sub() if ($old_form eq "return");

    if ($old_form) {

      $old_form->{"${inv}number"} = $form->{"${inv}number"};

      # restore and display form
      map { $form->{$_} = $old_form->{$_} } keys %$old_form;

      $form->{queued}  = $queued;
      $form->{printed} = $printed;
      $form->{emailed} = $emailed;
      $form->{message} = $message;

      $form->{rowcount}--;
      map { $form->{$_} = $form->parse_amount(\%myconfig, $form->{$_}) }
        qw(exchangerate creditlimit creditremaining);

      for my $i (1 .. $form->{paidaccounts}) {
        map {
          $form->{"${_}_$i"} =
            $form->parse_amount(\%myconfig, $form->{"${_}_$i"})
        } qw(paid exchangerate);
      }

      call_sub($display_form);
      ::end_of_request();
    }

    my $msg =
      ($form->{media} eq 'printer')
      ? $locale->text('sent to printer')
      : $locale->text('emailed to') . " $form->{email}";
    $form->redirect(qq|$form->{label} $form->{"${inv}number"} $msg|);
  }
  if ($form->{printing}) {
   call_sub($display_form);
   ::end_of_request();
  }

  $main::lxdebug->leave_sub();
}

sub customer_details {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  IS->customer_details(\%myconfig, \%$form, @_);

  $main::lxdebug->leave_sub();
}

sub vendor_details {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  IR->vendor_details(\%myconfig, \%$form, @_);

  $main::lxdebug->leave_sub();
}

sub post_as_new {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;

  _check_io_auth();

  $form->{postasnew} = 1;
  map { delete $form->{$_} } qw(printed emailed queued);

  &post;

  $main::lxdebug->leave_sub();
}

sub ship_to {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my $cgi      = $main::cgi;

  _check_io_auth();

  if ($form->{second_run}) {
    $form->{print_and_post} = 0;
  }

  my $title = $form->{title};
  $form->{title} = $locale->text('Ship to');

  map { $form->{$_} = $form->parse_amount(\%myconfig, $form->{$_}) }
    qw(exchangerate creditlimit creditremaining);

  my @shipto_vars =
    qw(shiptoname shiptostreet shiptozipcode shiptocity shiptocountry
       shiptocontact shiptocp_gender shiptophone shiptofax shiptoemail
       shiptodepartment_1 shiptodepartment_2);

  my @addr_vars =
    (qw(name department_1 department_2 street zipcode city country
        contact email phone fax));

  # get details for name
  call_sub("$form->{vc}_details", @addr_vars);

  my $number =
    ($form->{vc} eq 'customer')
    ? $locale->text('Customer Number')
    : $locale->text('Vendor Number');

  # sieht nicht nett aus, funktioniert aber
  # das vorausgewählte select-feld wird über shiptocp_gender
  # entsprechend vorbelegt
  my $selected_m='';
  my $selected_f='';
  if ($form->{shiptocp_gender} eq 'm') {
    $selected_m='selected';
    $selected_f='';
  } elsif ($form->{shiptocp_gender} eq 'f') {
    $selected_m='';
    $selected_f='selected';
  }
  # muß das hier nochmal sein? erstmal raus!
  # get pricegroups for parts
  #IS->get_pricegroups_for_parts(\%myconfig, \%$form);

  # build up html code for prices_$i
  #set_pricegroup($form->{rowcount});

  my $nextsub = ($form->{display_form}) ? $form->{display_form} : "display_form";

  $form->{rowcount}--;

  $form->header;

  print qq|
<body>

<form method="post" action="$form->{script}">

<table width="100%">
  <tr>
    <td>
      <table>
        <tr class="listheading">
          <th class="listheading" colspan="2" width="50%">|
    . $locale->text('Billing Address') . qq|</th>
          <th class="listheading" width="50%">|
    . $locale->text('Shipping Address') . qq|</th>
        </tr>
        <tr height="5"></tr>
        <tr>
          <th align="right" nowrap>$number</th>
          <td>$form->{"$form->{vc}number"}</td>
        </tr>
        <tr>
          <th align="right" nowrap>| . $locale->text('Company Name') . qq|</th>
          <td>$form->{name}</td>
          <td><input name="shiptoname" size="35" value="$form->{shiptoname}"></td>
        </tr>
        <tr>
          <th align="right" nowrap>| . $locale->text('Department') . qq|</th>
          <td>$form->{department_1}</td>
          <td><input name="shiptodepartment_1" size="35" value="$form->{shiptodepartment_1}"></td>
        </tr>
        <tr>
          <th align="right" nowrap>&nbsp;</th>
          <td>$form->{department_2}</td>
          <td><input name="shiptodepartment_2" size="35" value="$form->{shiptodepartment_2}"></td>
        </tr>
        <tr>
          <th align="right" nowrap>| . $locale->text('Street') . qq|</th>
          <td>$form->{street}</td>
          <td><input name="shiptostreet" size="35" value="$form->{shiptostreet}"></td>
        </tr>
        <tr>
          <th align="right" nowrap>| . $locale->text('Zipcode') . qq|</th>
          <td>$form->{zipcode}</td>
          <td><input name="shiptozipcode" size="35" value="$form->{shiptozipcode}"></td>
        </tr>
        <tr>
          <th align="right" nowrap>| . $locale->text('City') . qq|</th>
          <td>$form->{city}</td>
          <td><input name="shiptocity" size="35" value="$form->{shiptocity}"></td>
        </tr>
        <tr>
          <th align="right" nowrap>| . $locale->text('Country') . qq|</th>
          <td>$form->{country}</td>
          <td><input name="shiptocountry" size="35" value="$form->{shiptocountry}"></td>
        </tr>
        <tr>
          <th align="right" nowrap>| . $locale->text('Contact') . qq|</th>
          <td>$form->{contact}</td>
          <td><input name="shiptocontact" size="35" value="$form->{shiptocontact}"></td>
        </tr>
        <tr>
          <th align="right" nowrap>| . $locale->text('Gender') . qq|</th>
          <td></td>
          <td><select id="shiptocp_gender" name="shiptocp_gender">
              <option value="m"| .  $selected_m . qq|>| . $locale->text('male') . qq|</option>
              <option value="f"| .  $selected_f . qq|>| . $locale->text('female') . qq|</option>
              </select>
          </td>
        </tr>
        <tr>
          <th align="right" nowrap>| . $locale->text('Phone') . qq|</th>
          <td>$form->{phone}</td>
          <td><input name="shiptophone" size="20" value="$form->{shiptophone}"></td>
        </tr>
        <tr>
          <th align="right" nowrap>| . $locale->text('Fax') . qq|</th>
          <td>$form->{fax}</td>
          <td><input name="shiptofax" size="20" value="$form->{shiptofax}"></td>
        </tr>
        <tr>
          <th align="right" nowrap>| . $locale->text('E-mail') . qq|</th>
          <td>$form->{email}</td>
          <td><input name="shiptoemail" size="35" value="$form->{shiptoemail}"></td>
        </tr>
      </table>
    </td>
  </tr>
</table>
| . $cgi->hidden("-name" => "nextsub", "-value" => $nextsub);
;



  # delete shipto
  map({ delete $form->{$_} } (@shipto_vars, qw(header shipto_id)));
  $form->{title} = $title;

  foreach my $key (keys %$form) {
    next if (($key eq 'login') || ($key eq 'password') || ('' ne ref $form->{$key}));
    $form->{$key} =~ s/\"/&quot;/g;
    print qq|<input type="hidden" name="$key" value="$form->{$key}">\n|;
  }

  print qq|

<hr size="3" noshade>

<br>
<input class="submit" type="submit" name="action" value="|
    . $locale->text('Continue') . qq|">
</form>

</body>
</html>
|;

  $main::lxdebug->leave_sub();
}

sub new_license {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;

  _check_io_auth();

  my $row = shift;

  # change callback
  $form->{old_callback} = $form->escape($form->{callback}, 1);
  $form->{callback} = $form->escape("$form->{script}?action=display_form", 1);
  $form->{old_callback} = $form->escape($form->{old_callback}, 1);

  # delete action
  delete $form->{action};
  my $customer = $form->{customer};
  map { $form->{"old_$_"} = $form->{"${_}_$row"} } qw(partnumber description);

  # save all other form variables in a previousform variable
  $form->{row} = $row;
  my $previousform;
  foreach my $key (keys %$form) {
    next if (($key eq 'login') || ($key eq 'password') || ('' ne ref $form->{$key}));

    # escape ampersands
    $form->{$key} =~ s/&/%26/g;
    $previousform .= qq|$key=$form->{$key}&|;
  }
  chop $previousform;
  $previousform = $form->escape($previousform, 1);

  $form->{script} = "licenses.pl";

  map { $form->{$_} = $form->{"old_$_"} } qw(partnumber description);
  map { $form->{$_} = $form->escape($form->{$_}, 1) }
    qw(partnumber description);
  $form->{callback} =
    qq|$form->{script}?action=add&vc=$form->{db}&$form->{db}_id=$form->{id}&$form->{db}=$form->{name}&type=$form->{type}&customer=$customer&partnumber=$form->{partnumber}&description=$form->{description}&previousform="$previousform"&initial=1|;
  $form->redirect;

  $main::lxdebug->leave_sub();
}

sub relink_accounts {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  _check_io_auth();

  $form->{"taxaccounts"} =~ s/\s*$//;
  $form->{"taxaccounts"} =~ s/^\s*//;
  foreach my $accno (split(/\s*/, $form->{"taxaccounts"})) {
    map({ delete($form->{"${accno}_${_}"}); } qw(rate description taxnumber));
  }
  $form->{"taxaccounts"} = "";

  IC->retrieve_accounts(\%myconfig, $form, map { $_ => $form->{"id_$_"} } 1 .. $form->{rowcount});

  $main::lxdebug->leave_sub();
}

sub set_duedate {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  _check_io_auth();

  my $invdate = $form->{invdate} eq 'undefined' ? undef : $form->{invdate};
  my $duedate = $form->get_duedate(\%myconfig, $invdate);

  print $form->ajax_response_header() . $duedate;

  $main::lxdebug->leave_sub();
}

sub _update_part_information {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;

  my %part_information = IC->get_basic_part_info('id'        => [ grep { $_ } map { $form->{"id_${_}"} } (1..$form->{rowcount}) ],
                                                 'vendor_id' => $form->{vendor_id});

  $form->{PART_INFORMATION} = \%part_information;

  foreach my $i (1..$form->{rowcount}) {
    next unless ($form->{"id_${i}"});

    my $info                 = $form->{PART_INFORMATION}->{$form->{"id_${i}"}} || { };
    $form->{"partunit_${i}"} = $info->{unit};
  }

  $main::lxdebug->leave_sub();
}

sub _update_ship {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  if (!$form->{ordnumber} || !$form->{id}) {
    map { $form->{"ship_$_"} = 0 } (1..$form->{rowcount});
    $main::lxdebug->leave_sub();
    return;
  }

  my $all_units = AM->retrieve_all_units();

  my %ship = DO->get_shipped_qty('type'  => ($form->{type} eq 'purchase_order') ? 'purchase' : 'sales',
                                 'oe_id' => $form->{id},);

  foreach my $i (1..$form->{rowcount}) {
    next unless ($form->{"id_${i}"});

    $form->{"ship_$i"} = 0;

    my $ship_entry = $ship{$form->{"id_$i"}};

    next if (!$ship_entry || ($ship_entry->{qty} <= 0));

    my $rowqty =
      ($form->{simple_save} ? $form->{"qty_$i"} : $form->parse_amount(\%myconfig, $form->{"qty_$i"}))
      * $all_units->{$form->{"unit_$i"}}->{factor}
      / $all_units->{$form->{"partunit_$i"}}->{factor};

    $form->{"ship_$i"}  = min($rowqty, $ship_entry->{qty});
    $ship_entry->{qty} -= $form->{"ship_$i"};
  }

  foreach my $i (1..$form->{rowcount}) {
    next unless ($form->{"id_${i}"});

    my $ship_entry = $ship{$form->{"id_$i"}};

    next if (!$ship_entry || ($ship_entry->{qty} <= 0.01));

    $form->{"ship_$i"} += $ship_entry->{qty};
    $ship_entry->{qty}  = 0;
  }

  $main::lxdebug->leave_sub();
}

sub _update_custom_variables {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;

  $form->{CVAR_CONFIGS}         = { } unless ref $form->{CVAR_CONFIGS} eq 'HASH';
  $form->{CVAR_CONFIGS}->{IC} ||= CVar->get_configs(module => 'IC');

  $main::lxdebug->leave_sub();
}

sub _render_custom_variables_inputs {
  $main::lxdebug->enter_sub(2);

  my $form     = $main::form;

  my %params = @_;

  if (!$form->{CVAR_CONFIGS}->{IC}) {
    $main::lxdebug->leave_sub();
    return;
  }

  my $valid = CVar->custom_variables_validity_by_trans_id(trans_id => $params{part_id});

  my $num_visible_cvars = 0;
  foreach my $cvar (@{ $form->{CVAR_CONFIGS}->{IC} }) {
    $cvar->{valid} = $params{part_id} && $valid->($cvar->{id});

    my $description = '';
    if ($cvar->{flag_editable} && $cvar->{valid}) {
      $num_visible_cvars++;
      $description = $cvar->{description} . ' ';
    }

    push @{ $params{ROW2} }, {
      line_break     => $num_visible_cvars == 1,
      description    => $description,
      cvar           => 1,
      render_options => {
         hide_non_editable => 1,
         var               => $cvar,
         name_prefix       => 'ic_',
         name_postfix      => "_$params{row}",
         valid             => $cvar->{valid},
         value             => $form->{"ic_cvar_" . $cvar->{name} . "_$params{row}"},
      }
    };
  }

  $main::lxdebug->leave_sub(2);
}
