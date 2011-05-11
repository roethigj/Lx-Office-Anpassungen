#=====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger Accounting
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
#======================================================================
#
# Helper for oe,is,ir
#
#======================================================================

#use SL::FU;
use SL::IS;
use SL::IR;
#use SL::PE;
#use SL::OE;
use Data::Dumper;
#use List::Util qw(max sum);

require "bin/mozilla/io.pl";
#require "bin/mozilla/invoice_io.pl";
#require "bin/mozilla/arap.pl";
#require "bin/mozilla/drafts.pl";

use strict;

1;

# end of main

sub get_part_for_new_row {
  $main::lxdebug->enter_sub();

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $main::auth->assert('invoice_edit vendor_invoice_edit');

  $form->{print_and_post} = 0         if $form->{second_run};

  my $i  = $form->{rowcount};
  map {$form->{"${_}_$i"} = $form->{${_}}} qw(partnumber description qty sellprice discount selected_unit unit_old basefactor pricegroup_old sellprice_pg price_new price_old);
  if (   ($form->{"partnumber_$i"} ne "")
      || ($form->{"description_$i"} ne "")) {

    if ($form->{type} =~ /^sales/ || ($form->{type} =~ /^invoice/ && $form->{vc} =~ /^customer/)) {
      IS->retrieve_item(\%myconfig, \%$form);
    } else {
      IR->retrieve_item(\%myconfig, \%$form);
    };

    my $rows = scalar @{ $form->{item_list} };
    if ($form->{"$form->{vc}_discount"} && !($form->{"discount_$i"})){
      $form->{"discount_$i"} = $form->format_amount(\%myconfig, $form->{"$form->{vc}_discount"} * 100);
    }

    if ($rows <= 1) {
      my $sellprice = $form->parse_amount(\%myconfig, $form->{"sellprice_$i"});
      map { $form->{item_list}[$i]{$_} =~ s/\"/&quot;/g } qw(partnumber description unit);
      map { $form->{"${_}_$i"} = $form->{item_list}[0]{$_} } keys %{ $form->{item_list}[0] };
      $form->{"discount_$i"} = 0                             if $form->{"not_discountable_$i"};
      $form->{"marge_price_factor_$i"} = $form->{item_list}->[0]->{price_factor};
      ($sellprice || $form->{"sellprice_$i"}) =~ /\.(\d+)/;
      my $decimalplaces = max 2, length $1;
      $form->{"sellprice_$i"} = $sellprice if $sellprice;
      if (!(($form->{type} =~ /^sales/) || ($form->{type} =~ /^invoice/ && $form->{vc} =~ /^customer/))) {
         my $exchangerate = $form->{exchangerate} || 1;
         $form->{"price_old_$i"} = $form->{"sellprice_$i"};
         $form->{"sellprice_$i"} *= (1 - $form->{"tradediscount_$i"});
         $form->{"sellprice_$i"} /= $exchangerate;   # if there is an exchange rate adjust sellprice
      }
      $form->{"listprice_$i"} /= $form->{exchangerate} || 1;
      $form->{"qty_$i"} = $form->format_amount(\%myconfig, $form->{"qty_$i"});
      if ($::lx_office_conf{features}->{lizenzen}) {
        if ($form->{"inventory_accno_$i"} ne "") {
          $form->{"lizenzen_$i"} = qq|<option></option>|;
          foreach my $item (@{ $form->{LIZENZEN}{ $form->{"id_$i"} } }) {
            $form->{"lizenzen_$i"} .= qq|<option value="$item->{"id"}">$item->{"licensenumber"}</option>|;
          }
          $form->{"lizenzen_$i"} .= qq|<option value=-1>Neue Lizenz</option>|;
        }
      }
      map { $form->{"${_}_$i"} = $form->format_amount(\%myconfig, $form->{"${_}_$i"}, $decimalplaces) } qw(listprice sellprice lastcost);
    }
    display_one_row($form, $i, $i+1);
  }  
  $main::lxdebug->leave_sub();
}

