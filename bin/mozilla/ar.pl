#=====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger Accounting
# Copyright (c) 2001
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
# Accounts Receivables
#
#======================================================================

use POSIX qw(strftime);
use List::Util qw(sum first);

use SL::AR;
use SL::FU;
use SL::IS;
use SL::PE;
use SL::ReportGenerator;

require "bin/mozilla/arap.pl";
require "bin/mozilla/common.pl";
require "bin/mozilla/drafts.pl";
require "bin/mozilla/reportgenerator.pl";

use strict;
#use warnings;

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

sub add {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  return $main::lxdebug->leave_sub() if (load_draft_maybe());

  # saving the history
  if(!exists $form->{addition} && ($form->{id} ne "")) {
    $form->{snumbers} = qq|invnumber_| . $form->{invnumber};
    $form->{addition} = "ADDED";
    $form->save_history;
  }
  # /saving the history

  $form->{title}    = "Add";
  $form->{callback} = "ar.pl?action=add&DONT_LOAD_DRAFT=1" unless $form->{callback};

  AR->get_transdate(\%myconfig, $form);
  $form->{initial_transdate} = $form->{transdate};
  &create_links;
  $form->{transdate} = $form->{initial_transdate};
  &display_form;
  $main::lxdebug->leave_sub();
}

sub edit {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;

  # show history button
  $form->{javascript} = qq|<script type="text/javascript" src="js/show_history.js"></script>|;
  #/show hhistory button
  $form->{javascript} .= qq|<script type="text/javascript" src="js/common.js"></script>|;
  $form->{title} = "Edit";

  &create_links;
  &display_form;

  $main::lxdebug->leave_sub();
}

sub display_form {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;

  &form_header;
  &form_footer;

  $main::lxdebug->leave_sub();
}

sub create_links {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  my ($duedate, $taxincluded);

  $form->create_links("AR", \%myconfig, "customer");
  $duedate = $form->{duedate};

  $taxincluded = $form->{taxincluded};
  my $id = $form->{id};
  IS->get_customer(\%myconfig, \%$form);
  $form->{taxincluded} = $taxincluded;
  $form->{id} = $id;

  $form->{duedate}     = $duedate if $duedate;
  $form->{oldcustomer} = "$form->{customer}--$form->{customer_id}";
  $form->{rowcount}    = 1;

  # notes
  $form->{notes} = $form->{intnotes} unless $form->{notes};

  # currencies
  $form->{defaultcurrency} = $form->get_default_currency(\%myconfig);

  map { $form->{selectcurrency} .= "<option>$_\n" } $form->get_all_currencies(\%myconfig);

  # customers
  if (@{ $form->{all_customer} || [] }) {
    $form->{customer} = "$form->{customer}--$form->{customer_id}";
    map { $form->{selectcustomer} .= "<option>$_->{name}--$_->{id}\n" }
      (@{ $form->{all_customer} });
  }

  # departments
  if (@{ $form->{all_departments} || [] }) {
    $form->{selectdepartment} = "<option>\n";
    $form->{department}       = "$form->{department}--$form->{department_id}";

    map {
      $form->{selectdepartment} .=
        "<option>$_->{description}--$_->{id}\n"
    } (@{ $form->{all_departments} || [] });
  }

  $form->{employee} = "$form->{employee}--$form->{employee_id}";

  # sales staff
  if (@{ $form->{all_employees} || [] }) {
    $form->{selectemployee} = "";
    map { $form->{selectemployee} .= "<option>$_->{name}--$_->{id}\n" }
      (@{ $form->{all_employees} || [] });
  }

  # build the popup menus
  $form->{taxincluded} = ($form->{id}) ? $form->{taxincluded} : "checked";

  AR->setup_form($form);

  $form->{locked} =
    ($form->datetonum($form->{transdate}, \%myconfig) <=
     $form->datetonum($form->{closedto}, \%myconfig));

  $main::lxdebug->leave_sub();
}

sub form_header {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my $cgi      = $main::cgi;

  my ($title, $readonly, $exchangerate, $rows);
  my ($taxincluded, $notes, $department, $customer, $employee, $amount, $project);
  my ($jsscript, $button1, $button2, $onload);
  my ($selectAR_amount, $selectAR_paid, $ARselected, $tax);
  my (@column_index, %column_data);


  $title = $form->{title};
  $form->{title} = $locale->text("$title Accounts Receivables Transaction");

  $form->{taxincluded} = ($form->{taxincluded}) ? "checked" : "";

  # $locale->text('Add Accounts Receivables Transaction')
  # $locale->text('Edit Accounts Receivables Transaction')
  $form->{javascript} = qq|<script type="text/javascript">
  <!--
  function setTaxkey(accno, row) {
    var taxkey = accno.options[accno.selectedIndex].value;
    var reg = /--([0-9]*)/;
    var found = reg.exec(taxkey);
    var index = found[1];
    index = parseInt(index);
    var tax = 'taxchart_' + row;
    for (var i = 0; i < document.getElementById(tax).options.length; ++i) {
      var reg2 = new RegExp("^"+ index, "");
      if (reg2.exec(document.getElementById(tax).options[i].value)) {
        document.getElementById(tax).options[i].selected = true;
        break;
      }
    }
  };
  //-->
  </script>|;
  # show history button js
  $form->{javascript} .= qq|<script type="text/javascript" src="js/show_history.js"></script>|;
  #/show history button js
  $form->{javascript} .= qq|<script type="text/javascript" src="js/common.js"></script>|;
  $readonly = ($form->{id}) ? "readonly" : "";

  $form->{radier} =
    ($form->current_date(\%myconfig) eq $form->{gldate}) ? 1 : 0;
  $readonly = ($form->{radier}) ? "" : $readonly;

  # set option selected
  foreach my $item (qw(customer currency department employee)) {
    $form->{"select$item"} =~ s/ selected//;
    $form->{"select$item"} =~
      s/option>\Q$form->{$item}\E/option selected>$form->{$item}/;
  }

  $form->{forex}        = $form->check_exchangerate( \%myconfig, $form->{currency}, $form->{transdate}, 'buy');
  $form->{exchangerate} = $form->{forex} if $form->{forex};

  # format amounts
  $form->{exchangerate}    = $form->{exchangerate} ? $form->format_amount(\%myconfig, $form->{exchangerate}) : '';
  $form->{creditlimit}     = $form->format_amount(\%myconfig, $form->{creditlimit}, 0, "0");
  $form->{creditremaining} = $form->format_amount(\%myconfig, $form->{creditremaining}, 0, "0");

  $exchangerate = qq|
<input type=hidden name=forex value=$form->{forex}>
|;
  if ($form->{defaultcurrency} && ($form->{currency} ne $form->{defaultcurrency})) {
    if ($form->{forex}) {
      $exchangerate .= qq|
        <th align=right>| . $locale->text('Exchangerate') . qq|</th>
        <td><input type=hidden name=exchangerate value=$form->{exchangerate}>$form->{exchangerate}</td>
|;
    } else {
      $exchangerate .= qq|
        <th align=right>| . $locale->text('Exchangerate') . qq|</th>
        <td><input name=exchangerate size=10 value=$form->{exchangerate}></td>
|;
    }
  }

  $taxincluded = qq|
              <tr>
                <td align=right><input name=taxincluded class=checkbox type=checkbox value=1 $form->{taxincluded}></td>
                <th align=left nowrap>| . $locale->text('Tax Included') . qq|</th>
              </tr>
|;

  if (($rows = $form->numtextrows($form->{notes}, 50)) < 2) {
    $rows = 2;
  }
  $notes =
    qq|<textarea name=notes rows=$rows cols=50 wrap=soft>$form->{notes}</textarea>|;

  $department = qq|
              <tr>
                <th align="right" nowrap>| . $locale->text('Department') . qq|</th>
                <td colspan=3><select name=department>$form->{selectdepartment}</select>
                <input type=hidden name=selectdepartment value="$form->{selectdepartment}">
                </td>
              </tr>
| if $form->{selectdepartment};

  my $n = ($form->{creditremaining} =~ /-/) ? "0" : "1";

  $customer = ($form->{selectcustomer})
    ? qq|<select name="customer" onchange="document.getElementById('update_button').click();">$form->{selectcustomer}</select>|
    : qq|<input name=customer value="$form->{customer}" size=35>|;

  $employee = qq|
                <input type=hidden name=employee value="$form->{employee}">
|;

  if ($form->{selectemployee}) {
    $employee = qq|
              <tr>
                <th align=right nowrap>| . $locale->text('Salesperson') . qq|</th>
                <td  colspan=2><select name=employee>$form->{selectemployee}</select></td>
                <input type=hidden name=selectemployee value="$form->{selectemployee}">
              </tr>
|;
  }

  my @old_project_ids = ();
  map({ push(@old_project_ids, $form->{"project_id_$_"})
          if ($form->{"project_id_$_"}); } (1..$form->{"rowcount"}));

  $form->get_lists("projects"  => { "key"       => "ALL_PROJECTS",
                                    "all"       => 0,
                                    "old_id"    => \@old_project_ids },
                   "charts"    => { "key"       => "ALL_CHARTS",
                                    "transdate" => $form->{transdate} },
                   "taxcharts" => { "key"       => "ALL_TAXCHARTS",
                                    "module"    => "AR" },);

  map({ $_->{link_split} = [ split(/:/, $_->{link}) ]; }
      @{ $form->{ALL_CHARTS} });

  my %project_labels = ();
  my @project_values = ("");
  foreach my $item (@{ $form->{"ALL_PROJECTS"} }) {
    push(@project_values, $item->{"id"});
    $project_labels{$item->{"id"}} = $item->{"projectnumber"};
  }

  my (%AR_amount_labels, @AR_amount_values);
  my (%AR_labels, @AR_values);
  my (%AR_paid_labels, @AR_paid_values);
  my %charts;
  my $taxchart_init;

  foreach my $item (@{ $form->{ALL_CHARTS} }) {
    if (grep({ $_ eq "AR_amount" } @{ $item->{link_split} })) {
      $taxchart_init = $item->{tax_id} if ($taxchart_init eq "");
      my $key = "$item->{accno}--$item->{tax_id}";
      push(@AR_amount_values, $key);
      $AR_amount_labels{$key} =
        "$item->{accno}--$item->{description}";

    } elsif (grep({ $_ eq "AR" } @{ $item->{link_split} })) {
      push(@AR_values, $item->{accno});
      $AR_labels{$item->{accno}} = "$item->{accno}--$item->{description}";

    } elsif (grep({ $_ eq "AR_paid" } @{ $item->{link_split} })) {
      push(@AR_paid_values, $item->{accno});
      $AR_paid_labels{$item->{accno}} =
        "$item->{accno}--$item->{description}";
    }

    $charts{$item->{accno}} = $item;
  }

  my %taxchart_labels = ();
  my @taxchart_values = ();
  my %taxcharts = ();
  foreach my $item (@{ $form->{ALL_TAXCHARTS} }) {
    my $key = "$item->{id}--$item->{rate}";
    $taxchart_init = $key if ($taxchart_init eq $item->{id});
    push(@taxchart_values, $key);
    $taxchart_labels{$key} =
      "$item->{taxdescription} " . ($item->{rate} * 100) . ' %';
    $taxcharts{$item->{id}} = $item;
  }

  $form->{fokus} = "arledger.customer";

  # use JavaScript Calendar or not
  $form->{jsscript} = 1;
  $jsscript = "";
  if ($form->{jsscript}) {

    # with JavaScript Calendar
    $button1 = qq|
       <td><input name=transdate id=transdate size=11 title="$myconfig{dateformat}" value="$form->{transdate}" onBlur=\"check_right_date_format(this)\"></td>
       <td><input type=button name=transdate id="trigger1" value=|
      . $locale->text('button') . qq|></td>
       |;
    $button2 = qq|
       <td><input name=duedate id=duedate size=11 title="$myconfig{dateformat}" value="$form->{duedate}" onBlur=\"check_right_date_format(this)\"></td>
       <td><input type=button name=duedate id="trigger2" value=|
      . $locale->text('button') . qq|></td></td>
     |;

    #write Trigger
    $jsscript =
      Form->write_trigger(\%myconfig, "2", "transdate", "BL", "trigger1",
                          "duedate", "BL", "trigger2");
  } else {

    # without JavaScript Calendar
    $button1 =
      qq|<td><input name=transdate id=transdate size=11 title="$myconfig{dateformat}" value="$form->{transdate}" onBlur=\"check_right_date_format(this)\"></td>|;
    $button2 =
      qq|<td><input name=duedate id=duedate size=11 title="$myconfig{dateformat}" value="$form->{duedate}" onBlur=\"check_right_date_format(this)\"></td>|;
  }

  my $follow_up_vc         =  $form->{customer};
  $follow_up_vc            =~ s/--.*?//;
  my $follow_up_trans_info =  "$form->{invnumber} ($follow_up_vc)";

  $form->{javascript} .=
    qq|<script type="text/javascript" src="js/common.js"></script>| .
    qq|<script type="text/javascript" src="js/show_vc_details.js"></script>| .
    qq|<script type="text/javascript" src="js/follow_up.js"></script>|;

  $form->header;
  $onload = qq|focus()|;
  $onload .= qq|;setupDateFormat('|. $myconfig{dateformat} .qq|', '|. $locale->text("Falsches Datumsformat!") .qq|')|;
  $onload .= qq|;setupPoints('|. $myconfig{numberformat} .qq|', '|. $locale->text("wrongformat") .qq|')|;
  print qq|
<body onLoad="$onload">

<form method=post name="arledger" action=$form->{script}>

<input type=hidden name=id value=$form->{id}>
<input type=hidden name=sort value=$form->{sort}>
<input type=hidden name=closedto value=$form->{closedto}>
<input type=hidden name=locked value=$form->{locked}>
<input type=hidden name=title value="$title">
<input type="hidden" name="follow_up_trans_id_1" value="| . H($form->{id}) . qq|">
<input type="hidden" name="follow_up_trans_type_1" value="ar_transaction">
<input type="hidden" name="follow_up_trans_info_1" value="| . H($follow_up_trans_info) . qq|">
<input type="hidden" name="follow_up_rowcount" value="1">

| . ($form->{saved_message} ? qq|<p>$form->{saved_message}</p>| : "") . qq|

<table width=100%>
  <tr class=listtop>
    <th class=listtop>$form->{title}</th>
  </tr>
  <tr height="5"></tr>
  <tr valign=top>
    <td>
      <table width=100%>
        <tr valign=top>
          <td>
            <table>
              <tr>
                <th align="right" nowrap>| . $locale->text('Customer') . qq|</th>
                <td colspan=3>$customer <input type="button" value="| . $locale->text('Details (one letter abbreviation)') . qq|" onclick="show_vc_details('customer')"></td>
                <input type=hidden name=selectcustomer value="$form->{selectcustomer}">
                <input type=hidden name=oldcustomer value="$form->{oldcustomer}">
                <input type=hidden name=customer_id value="$form->{customer_id}">
                <input type=hidden name=terms value=$form->{terms}>
              </tr>
              <tr>
                <td></td>
                <td colspan=3>
                  <table width=100%>
                    <tr>
                      <th align=left nowrap>| . $locale->text('Credit Limit') . qq|</th>
                      <td>$form->{creditlimit}</td>
                      <th align=left nowrap>| . $locale->text('Remaining') . qq|</th>
                      <td class="plus$n">$form->{creditremaining}</td>
                      <input type=hidden name=creditlimit value=$form->{creditlimit}>
                      <input type=hidden name=creditremaining value=$form->{creditremaining}>
                    </tr>
                  </table>
                </td>
              </tr>
              <tr>
                <th align=right>| . $locale->text('Currency') . qq|</th>
                <td><select name=currency>$form->{selectcurrency}</select></td>
                <input type=hidden name=selectcurrency value="$form->{selectcurrency}">
                <input type=hidden name=defaultcurrency value=$form->{defaultcurrency}>
                <input type=hidden name=fxgain_accno value=$form->{fxgain_accno}>
                <input type=hidden name=fxloss_accno value=$form->{fxloss_accno}>
                $exchangerate
              </tr>
              $department
              $taxincluded
            </table>
          </td>
          <td align=right>
            <table>
              $employee
              <tr>
                <th align=right nowrap>| . $locale->text('Invoice Number') . qq|</th>
                <td><input name=invnumber size=11 value="$form->{invnumber}"></td>
              </tr>
              <tr>
                <th align=right nowrap>| . $locale->text('Order Number') . qq|</th>
                <td><input name=ordnumber size=11 value="$form->{ordnumber}"></td>
              </tr>
              <tr>
                <th align=right nowrap>| . $locale->text('Invoice Date') . qq|</th>
                $button1
              </tr>
              <tr>
                <th align=right nowrap>| . $locale->text('Due Date') . qq|</th>
                $button2
              </tr>
     </table>
          </td>
        </tr>
      </table>
    </td>
  </tr>

$jsscript
  <input type=hidden name=rowcount value=$form->{rowcount}>
  <tr>
      <td>
          <table width=100%>
           <tr class=listheading>
          <th class=listheading style="width:15%">|
    . $locale->text('Account') . qq|</th>
          <th class=listheading style="width:10%">|
    . $locale->text('Amount') . qq|</th>
          <th class=listheading style="width:10%">|
    . $locale->text('Tax') . qq|</th>
          <th class=listheading style="width:5%">|
    . $locale->text('Taxkey') . qq|</th>
          <th class=listheading style="width:10%">|
    . $locale->text('Project') . qq|</th>
        </tr>
|;

  $amount  = $locale->text('Amount');
  $project = $locale->text('Project');

  for my $i (1 .. $form->{rowcount}) {

    # format amounts
    $form->{"amount_$i"} =
      $form->format_amount(\%myconfig, $form->{"amount_$i"}, 2);
    $form->{"tax_$i"} = $form->format_amount(\%myconfig, $form->{"tax_$i"}, 2);

    my $selected_accno_full;
    my ($accno_row) = split(/--/, $form->{"AR_amount_$i"});
    my $item = $charts{$accno_row};
    $selected_accno_full = "$item->{accno}--$item->{tax_id}";

    my $selected_taxchart = $form->{"taxchart_$i"};
    my ($selected_accno, $selected_tax_id) = split(/--/, $selected_accno_full);
    my ($previous_accno, $previous_tax_id) = split(/--/, $form->{"previous_AR_amount_$i"});

    if ($previous_accno &&
        ($previous_accno eq $selected_accno) &&
        ($previous_tax_id ne $selected_tax_id)) {
      my $item = $taxcharts{$selected_tax_id};
      $selected_taxchart = "$item->{id}--$item->{rate}";
    }

    if (!$form->{"taxchart_$i"}) {
      if ($form->{"AR_amount_$i"} =~ m/.--./) {
        $selected_taxchart = join '--', map { ($_->{id}, $_->{rate}) } first { $_->{id} == $item->{tax_id} } @{ $form->{ALL_TAXCHARTS} };
      } else {
        $selected_taxchart = $taxchart_init;
      }
    }

    $selectAR_amount =
      NTI($cgi->popup_menu('-name' => "AR_amount_$i",
                           '-id' => "AR_amount_$i",
                           '-style' => 'width:400px',
                           '-onChange' => "setTaxkey(this, $i)",
                           '-values' => \@AR_amount_values,
                           '-labels' => \%AR_amount_labels,
                           '-default' => $selected_accno_full))
      . $cgi->hidden('-name' => "previous_AR_amount_$i",
                     '-default' => $selected_accno_full);

    $tax = qq|<td>| .
      NTI($cgi->popup_menu('-name' => "taxchart_$i",
                           '-id' => "taxchart_$i",
                           '-style' => 'width:200px',
                           '-values' => \@taxchart_values,
                           '-labels' => \%taxchart_labels,
                           '-default' => $selected_taxchart))
      . qq|</td>|;

    my $projectnumber =
      NTI($cgi->popup_menu('-name' => "project_id_$i",
                           '-values' => \@project_values,
                           '-labels' => \%project_labels,
                           '-default' => $form->{"project_id_$i"} ));

    print qq|
        <tr>
          <td>$selectAR_amount</td>
          <td><input name="amount_$i" size=10 value=$form->{"amount_$i"}></td>
          <td><input type="hidden" name="tax_$i" value="$form->{"tax_$i"}">$form->{"tax_$i"}</td>
          $tax
          <td>$projectnumber</td>
        </tr>
|;
    $amount  = "";
    $project = "";
  }

  $form->{invtotal_unformatted} = $form->{invtotal};
  $form->{invtotal} = $form->format_amount(\%myconfig, $form->{invtotal}, 2);

  $ARselected =
    NTI($cgi->popup_menu('-name' => "ARselected", '-id' => "ARselected",
                         '-style' => 'width:400px',
                         '-values' => \@AR_values, '-labels' => \%AR_labels,
                         '-default' => $form->{ARselected}));

  print qq|
        <tr>
          <td colspan=6>
            <hr noshade>
          </td>
        </tr>
        <tr>
          <td>${ARselected}</td>
          <th align=left>$form->{invtotal}</th>

          <input type=hidden name=oldinvtotal value=$form->{oldinvtotal}>
          <input type=hidden name=oldtotalpaid value=$form->{oldtotalpaid}>

          <input type=hidden name=taxaccounts value="$form->{taxaccounts}">

          <td colspan=4></td>


        </tr>
        </table>
        </td>
    </tr>
    <tr>
      <td>
        <table width=100%>
        <tr>
          <th align=left width=1%>| . $locale->text('Notes') . qq|</th>
          <td align=left>$notes</td>
        </tr>
      </table>
    </td>
  </tr>
  <tr>
    <td>
      <table width=100%>
        <tr class=listheading>
          <th colspan=7 class=listheading>|
    . $locale->text('Incoming Payments') . qq|</th>
        </tr>
|;

  if ($form->{defaultcurrency} && ($form->{currency} eq $form->{defaultcurrency})) {
    @column_index = qw(datepaid source memo paid AR_paid paid_project_id);
  } else {
    @column_index = qw(datepaid source memo paid exchangerate AR_paid paid_project_id);
  }

  $column_data{datepaid}     = "<th>" . $locale->text('Date') . "</th>";
  $column_data{paid}         = "<th>" . $locale->text('Amount') . "</th>";
  $column_data{exchangerate} = "<th>" . $locale->text('Exch') . "</th>";
  $column_data{AR_paid}      = "<th>" . $locale->text('Account') . "</th>";
  $column_data{source}       = "<th>" . $locale->text('Source') . "</th>";
  $column_data{memo}         = "<th>" . $locale->text('Memo') . "</th>";
  $column_data{paid_project_id} = "<th>" . $locale->text('Project Number') . "</th>";

  print "
        <tr>
";
  map { print "$column_data{$_}\n" } @column_index;
  print "
        </tr>
";

  my @triggers  = ();
  $form->{totalpaid} = 0;

  $form->{paidaccounts}++ if ($form->{"paid_$form->{paidaccounts}"});
  for my $i (1 .. $form->{paidaccounts}) {
    print "
        <tr>
";

    $selectAR_paid =
      NTI($cgi->popup_menu('-name' => "AR_paid_$i",
                           '-id' => "AR_paid_$i",
                           '-values' => \@AR_paid_values,
                           '-labels' => \%AR_paid_labels,
                           '-default' => $form->{"AR_paid_$i"}));

    $form->{totalpaid} += $form->{"paid_$i"};

    # format amounts
    if ($form->{"paid_$i"}) {
      $form->{"paid_$i"} =
        $form->format_amount(\%myconfig, $form->{"paid_$i"}, 2);
    }
    $form->{"exchangerate_$i"} =
      $form->format_amount(\%myconfig, $form->{"exchangerate_$i"});

    if ($form->{"exchangerate_$i"} == 0) {
      $form->{"exchangerate_$i"} = "";
    }

    $exchangerate = qq|&nbsp;|;
    if ($form->{defaultcurrency} && ($form->{currency} ne $form->{defaultcurrency})) {
      if ($form->{"forex_$i"}) {
        $exchangerate =
          qq|<input type=hidden name="exchangerate_$i" value=$form->{"exchangerate_$i"}>$form->{"exchangerate_$i"}|;
      } else {
        $exchangerate =
          qq|<input name="exchangerate_$i" size=10 value=$form->{"exchangerate_$i"}>|;
      }
    }

    $exchangerate .= qq|
<input type=hidden name="forex_$i" value=$form->{"forex_$i"}>
|;

    $column_data{paid} =
      qq|<td align=center><input name="paid_$i" size=11 value="$form->{"paid_$i"}" onBlur=\"check_right_number_format(this)\"></td>|;
    $column_data{AR_paid} =
      qq|<td align=center>${selectAR_paid}</td>|;
    $column_data{exchangerate} = qq|<td align=center>$exchangerate</td>|;
    $column_data{datepaid}     =
      qq|<td align=center><input name="datepaid_$i" id="datepaid_$i" size=11 value="$form->{"datepaid_$i"}" onBlur=\"check_right_date_format(this)\">
         <input type="button" name="datepaid_$i" id="trigger_datepaid_$i" value="?"></td>|;
    $column_data{source} =
      qq|<td align=center><input name="source_$i" size=11 value="$form->{"source_$i"}"></td>|;
    $column_data{memo} =
      qq|<td align=center><input name="memo_$i" size=11 value="$form->{"memo_$i"}"></td>|;

    $column_data{paid_project_id} =
      qq|<td>|
      . NTI($cgi->popup_menu('-name' => "paid_project_id_$i",
                             '-values' => \@project_values,
                             '-labels' => \%project_labels,
                             '-default' => $form->{"paid_project_id_$i"} ))
      . qq|</td>|;

    map { print qq|$column_data{$_}\n| } @column_index;

    print "
        </tr>
";
    push(@triggers, "datepaid_$i", "BL", "trigger_datepaid_$i");
  }

  my $paid_missing = $form->{invtotal_unformatted} - $form->{totalpaid};

  print qq|
        <tr>
          <td></td>
          <td></td>
          <td align="center">| . $locale->text('Total') . qq|</td>
          <td align="center">| . H($form->format_amount(\%myconfig, $form->{totalpaid}, 2)) . qq|</td>
        </tr>
        <tr>
          <td></td>
          <td></td>
          <td align="center">| . $locale->text('Missing amount') . qq|</td>
          <td align="center">| . H($form->format_amount(\%myconfig, $paid_missing, 2)) . qq|</td>
        </tr>
| . $form->write_trigger(\%myconfig, scalar(@triggers) / 3, @triggers) .
    qq|
<input type=hidden name=paidaccounts value=$form->{paidaccounts}>

      </table>
    </td>
  </tr>
  <tr>
    <td><hr size=3 noshade></td>
  </tr>
</table>
|;

  $main::lxdebug->leave_sub();
}

sub form_footer {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my $cgi      = $main::cgi;

  my ($transdate, $closedto);

  my $follow_ups_block;
  if ($form->{id}) {
    my $follow_ups = FU->follow_ups('trans_id' => $form->{id});

    if (@{ $follow_ups} ) {
      my $num_due       = sum map { $_->{due} * 1 } @{ $follow_ups };
      $follow_ups_block = qq|<p>| . $locale->text("There are #1 unfinished follow-ups of which #2 are due.", scalar @{ $follow_ups }, $num_due) . qq|</p>|;
    }
  }

  print qq|

$follow_ups_block

<input name=gldate type=hidden value="| . Q($form->{gldate}) . qq|">

<input name=callback type=hidden value="$form->{callback}">
|
. $cgi->hidden('-name' => 'draft_id', '-default' => [$form->{draft_id}])
. $cgi->hidden('-name' => 'draft_description', '-default' => [$form->{draft_description}])
. qq|

<br>
|;

  if (!$form->{id} && $form->{draft_id}) {
    print(NTI($cgi->checkbox('-name' => 'remove_draft', '-id' => 'remove_draft',
                             '-value' => 1, '-checked' => $form->{remove_draft},
                             '-label' => '')) .
          qq|&nbsp;<label for="remove_draft">| .
          $locale->text("Remove draft when posting") .
          qq|</label><br>|);
  }

  $transdate = $form->datetonum($form->{transdate}, \%myconfig);
  $closedto  = $form->datetonum($form->{closedto},  \%myconfig);

  print qq|<input class="submit" type="submit" name="action" id="update_button" value="| . $locale->text('Update') . qq|">\n|;

  # ToDO: - insert a global check for stornos, so that a storno is only possible a limited time after saving it
  print qq| <input class=submit type=submit name=action value="| . $locale->text('Storno') . qq|"> |
    if ($form->{id} && !IS->has_storno(\%myconfig, $form, 'ar') && !IS->is_storno(\%myconfig, $form, 'ar') && (($form->{totalpaid} == 0) || ($form->{totalpaid} eq "")));

  if ($form->{id}) {
    if ($form->{radier}) {
      print qq|
        <input class=submit type=submit name=action value="| . $locale->text('Post') .            qq|">
        <input class=submit type=submit name=action value="| . $locale->text('Delete') .          qq|"> |;
    }
    if ($transdate > $closedto) {
      print qq|
        <input class=submit type=submit name=action value="| . $locale->text('Use As Template') . qq|"> |;
    }
    print qq|
        <input class=submit type=submit name=action value="| . $locale->text('Post Payment') .    qq|">
        <input type="button" class="submit" onclick="follow_up_window()" value="|
      . $locale->text('Follow-Up')
      . qq|"> |;

  } else {
    if ($transdate > $closedto) {
      print qq| <input class=submit type=submit name=action value="| . $locale->text('Post') .     qq|"> | .
        NTI($cgi->submit('-name' => 'action', '-value' => $locale->text('Save draft'), '-class' => 'submit'));
    }
  }

  if ($form->{menubar}) {
    require "bin/mozilla/menu.pl";
    &menubar;
  }
  # button for saving history
  if($form->{id} ne "") {
    print qq| <input type=button class=submit onclick=set_history_window($form->{id}); name=history id=history value=| . $locale->text('history') . qq|> |;
  }
  # /button for saving history
  # mark_as_paid button
  if($form->{id} ne "") {
    print qq|<input type="submit" class="submit" name="action" value="|
          . $locale->text('mark as paid') . qq|">|;
  }
  # /mark_as_paid button

  print "
</form>

</body>
</html>
";

  $main::lxdebug->leave_sub();
}

sub mark_as_paid {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  &mark_as_paid_common(\%myconfig,"ar");

  $main::lxdebug->leave_sub();
}

sub update {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  my $display = shift;

  my ($totaltax, $exchangerate);

  $form->{invtotal} = 0;

  delete @{ $form }{ grep { m/^tax_\d+$/ } keys %{ $form } };

  map { $form->{$_} = $form->parse_amount(\%myconfig, $form->{$_}) }
    qw(exchangerate creditlimit creditremaining);

  my @flds  = qw(amount AR_amount projectnumber oldprojectnumber project_id);
  my $count = 0;
  my @a     = ();

  for my $i (1 .. $form->{rowcount}) {
    $form->{"amount_$i"} = $form->parse_amount(\%myconfig, $form->{"amount_$i"});
    $form->{"tax_$i"} = $form->parse_amount(\%myconfig, $form->{"tax_$i"});
    if ($form->{"amount_$i"}) {
      push @a, {};
      my $j = $#a;
      my ($taxkey, $rate) = split(/--/, $form->{"taxchart_$i"});
      if ($taxkey > 1) {
        if ($form->{taxincluded}) {
          $form->{"tax_$i"} = $form->{"amount_$i"} / ($rate + 1) * $rate;
        } else {
          $form->{"tax_$i"} = $form->{"amount_$i"} * $rate;
        }
      } else {
        $form->{"tax_$i"} = 0;
      }
      $form->{"tax_$i"} = $form->round_amount($form->{"tax_$i"}, 2);

      $totaltax += $form->{"tax_$i"};
      map { $a[$j]->{$_} = $form->{"${_}_$i"} } @flds;
      $count++;
    }
  }

  $form->redo_rows(\@flds, \@a, $count, $form->{rowcount});
  $form->{rowcount} = $count + 1;
  map { $form->{invtotal} += $form->{"amount_$_"} } (1 .. $form->{rowcount});

  $form->{forex}        = $form->check_exchangerate( \%myconfig, $form->{currency}, $form->{transdate}, 'buy');
  $form->{exchangerate} = $form->{forex} if $form->{forex};

  $form->{invdate} = $form->{transdate};

  $form->{invdate} = $form->{transdate};

  my %saved_variables = map +( $_ => $form->{$_} ), qw(AR AR_amount_1 taxchart_1 oldcustomer);

  &check_name("customer");

  # check_name ruft get_customer auf, oldcustomer wird überschrieben, daher wird dies vorher gemerkt
  # get_customer holt Bemerkungen als intnotes, für Debitorenbuchungen gibt es aber nur das Feld notes
  $form->{notes} = $form->{intnotes} if $saved_variables{oldcustomer} ne $form->{customer};

  $form->{AR} = $saved_variables{AR};
  if ($saved_variables{AR_amount_1} =~ m/.--./) {
    map { $form->{$_} = $saved_variables{$_} } qw(AR_amount_1 taxchart_1);
  } else {
    delete $form->{taxchart_1};
  }

  $form->{invtotal} =
    ($form->{taxincluded}) ? $form->{invtotal} : $form->{invtotal} + $totaltax;

  for my $i (1 .. $form->{paidaccounts}) {
    if ($form->parse_amount(\%myconfig, $form->{"paid_$i"})) {
      map {
        $form->{"${_}_$i"} =
          $form->parse_amount(\%myconfig, $form->{"${_}_$i"})
      } qw(paid exchangerate);

      $form->{totalpaid} += $form->{"paid_$i"};

      $form->{"forex_$i"}        = $form->check_exchangerate( \%myconfig, $form->{currency}, $form->{"datepaid_$i"}, 'buy');
      $form->{"exchangerate_$i"} = $form->{"forex_$i"} if $form->{"forex_$i"};
    }
  }

  $form->{creditremaining} -=
    ($form->{invtotal} - $form->{totalpaid} + $form->{oldtotalpaid} -
     $form->{oldinvtotal});
  $form->{oldinvtotal}  = $form->{invtotal};
  $form->{oldtotalpaid} = $form->{totalpaid};

  &display_form;

  $main::lxdebug->leave_sub();
}

#
# ToDO: fix $closedto and $invdate
#
sub post_payment {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  $form->{defaultcurrency} = $form->get_default_currency(\%myconfig);

  my $invdate = $form->datetonum($form->{transdate}, \%myconfig);

  for my $i (1 .. $form->{paidaccounts}) {

    if ($form->parse_amount(\%myconfig, $form->{"paid_$i"})) {
      my $datepaid = $form->datetonum($form->{"datepaid_$i"}, \%myconfig);

      $form->isblank("datepaid_$i", $locale->text('Payment date missing!'));

      $form->error($locale->text('Cannot post payment for a closed period!')) if ($form->date_closed($form->{"datepaid_$i"}, \%myconfig));

      if ($form->{defaultcurrency} && ($form->{currency} ne $form->{defaultcurrency})) {
#        $form->{"exchangerate_$i"} = $form->{exchangerate} if ($invdate == $datepaid);
        $form->isblank("exchangerate_$i", $locale->text('Exchangerate for payment missing!'));
      }
    }
  }

  ($form->{AR})      = split /--/, $form->{AR};
  ($form->{AR_paid}) = split /--/, $form->{AR_paid};
  $form->redirect($locale->text('Payment posted!')) if (AR->post_payment(\%myconfig, \%$form));
  $form->error($locale->text('Cannot post payment!'));

  $main::lxdebug->leave_sub();
}

sub _post {

  $main::auth->assert('general_ledger');

  my $form     = $main::form;

  # inline post
  post(1);
}

sub post {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  my ($inline) = @_;

  my ($datepaid);

  # check if there is an invoice number, invoice and due date
  $form->isblank("transdate", $locale->text('Invoice Date missing!'));
  $form->isblank("duedate",   $locale->text('Due Date missing!'));
  $form->isblank("customer",  $locale->text('Customer missing!'));

  if ($myconfig{mandatory_departments} && !$form->{department}) {
    $form->{saved_message} = $::locale->text('You have to specify a department.');
    update();
    exit;
  }

  my $closedto  = $form->datetonum($form->{closedto},  \%myconfig);
  my $transdate = $form->datetonum($form->{transdate}, \%myconfig);
  $form->error($locale->text('Cannot post transaction for a closed period!')) if ($form->date_closed($form->{"transdate"}, \%myconfig));

  $form->error($locale->text('Zero amount posting!'))
    unless grep $_*1, map $form->parse_amount(\%myconfig, $form->{"amount_$_"}), 1..$form->{rowcount};

  $form->isblank("exchangerate", $locale->text('Exchangerate missing!'))
    if ($form->{defaultcurrency} && ($form->{currency} ne $form->{defaultcurrency}));

  delete($form->{AR});

  for my $i (1 .. $form->{paidaccounts}) {
    if ($form->parse_amount(\%myconfig, $form->{"paid_$i"})) {
      $datepaid = $form->datetonum($form->{"datepaid_$i"}, \%myconfig);

      $form->isblank("datepaid_$i", $locale->text('Payment date missing!'));

      $form->error($locale->text('Cannot post payment for a closed period!'))
        if ($form->date_closed($form->{"datepaid_$i"}, \%myconfig));

      if ($form->{defaultcurrency} && ($form->{currency} ne $form->{defaultcurrency})) {
        $form->{"exchangerate_$i"} = $form->{exchangerate} if ($transdate == $datepaid);
        $form->isblank("exchangerate_$i", $locale->text('Exchangerate for payment missing!'));
      }
    }
  }

  # if oldcustomer ne customer redo form
  my ($customer) = split /--/, $form->{customer};
  if ($form->{oldcustomer} ne "$customer--$form->{customer_id}") {
    update();
    ::end_of_request();
  }

  $form->{AR}{receivables} = $form->{ARselected};
  $form->{storno}          = 0;

  $form->{id} = 0 if $form->{postasnew};
  $form->error($locale->text('Cannot post transaction!')) unless AR->post_transaction(\%myconfig, \%$form);

  # saving the history
  if(!exists $form->{addition} && $form->{id} ne "") {
    $form->{snumbers} = "invnumber_$form->{invnumber}";
    $form->{addition} = "POSTED";
    $form->save_history;
  }
  # /saving the history
  remove_draft() if $form->{remove_draft};

  $form->redirect($locale->text('Transaction posted!')) unless $inline;

  $main::lxdebug->leave_sub();
}

sub post_as_new {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  $form->{postasnew} = 1;
  # saving the history
  if(!exists $form->{addition} && $form->{id} ne "") {
    $form->{snumbers} = qq|invnumber_| . $form->{invnumber};
    $form->{addition} = "POSTED AS NEW";
    $form->save_history;
  }
  # /saving the history
  &post;

  $main::lxdebug->leave_sub();
}

sub use_as_template {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  map { delete $form->{$_} } qw(printed emailed queued invnumber invdate deliverydate id datepaid_1 source_1 memo_1 paid_1 exchangerate_1 AP_paid_1 storno);
  $form->{paidaccounts} = 1;
  $form->{rowcount}--;
  $form->{invdate} = $form->current_date(\%myconfig);
  &update;

  $main::lxdebug->leave_sub();
}

sub delete {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my $locale   = $main::locale;

  $form->{title} = $locale->text('Confirm!');

  $form->header;

  delete $form->{header};

  print qq|
<body>

<form method=post action=$form->{script}>
|;

  foreach my $key (keys %$form) {
    next if (($key eq 'login') || ($key eq 'password') || ('' ne ref $form->{$key}));
    $form->{$key} =~ s/\"/&quot;/g;
    print qq|<input type=hidden name=$key value="$form->{$key}">\n|;
  }

  print qq|
<h2 class=confirm>$form->{title}</h2>

<h4>|
    . $locale->text('Are you sure you want to delete Transaction')
    . qq| $form->{invnumber}</h4>

<input name=action class=submit type=submit value="|
    . $locale->text('Yes') . qq|">
</form>

</body>
</html>
|;

  $main::lxdebug->leave_sub();
}

sub yes {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  if (AR->delete_transaction(\%myconfig, \%$form)) {
    # saving the history
    if(!exists $form->{addition}) {
      $form->{snumbers} = qq|invnumber_| . $form->{invnumber};
      $form->{addition} = "DELETED";
      $form->save_history;
    }
    # /saving the history
    $form->redirect($locale->text('Transaction deleted!'));
  }
  $form->error($locale->text('Cannot delete transaction!'));

  $main::lxdebug->leave_sub();
}

sub search {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger | invoice_edit');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;
  my $cgi      = $main::cgi;

  my ($customer, $department);
  my ($jsscript, $button1, $button2, $onload);

  # setup customer selection
  $form->all_vc(\%myconfig, "customer", "AR");

  $form->{title}    = $locale->text('AR Transactions');
  $form->{jsscript} = 1;

  # Auch in Rechnungsübersicht nach Kundentyp filtern - jan
  $form->get_lists("projects"       => { "key" => "ALL_PROJECTS", "all" => 1 },
                   "departments"    => "ALL_DEPARTMENTS",
                   "customers"      => "ALL_CUSTOMERS",
                   "employees"    => "ALL_EMPLOYEES",
                   "salesmen"     => "ALL_SALESMEN",
                   "business_types" => "ALL_BUSINESS_TYPES");
  $form->{SHOW_BUSINESS_TYPES} = scalar @{ $form->{ALL_BUSINESS_TYPES} } > 0;

  # constants and subs for template
  $form->{vc} = "customer";
  $form->{jsscript}  = 1;
  $form->{vc_keys}   = sub { "$_[0]->{name}--$_[0]->{id}" };
  $form->{employee_labels} = sub { $_[0]->{"name"} || $_[0]->{"login"} };
  $form->{salesman_labels} = $form->{employee_labels};

  $form->header;
  print $form->parse_html_template('ar/search', { %myconfig });

  $main::lxdebug->leave_sub();
}

sub create_subtotal_row {
  $main::lxdebug->enter_sub();

  my ($totals, $columns, $column_alignment, $subtotal_columns, $class) = @_;

  my $form     = $main::form;
  my %myconfig = %main::myconfig;

  my $row = { map { $_ => { 'data' => '', 'class' => $class, 'align' => $column_alignment->{$_}, } } @{ $columns } };

  map { $row->{$_}->{data} = $form->format_amount(\%myconfig, $totals->{$_}, 2) } @{ $subtotal_columns };

  $row->{tax}->{data} = $form->format_amount(\%myconfig, $totals->{amount} - $totals->{netamount}, 2);

  map { $totals->{$_} = 0 } @{ $subtotal_columns };

  $main::lxdebug->leave_sub();

  return $row;
}

sub ar_transactions {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger | invoice_edit');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  my ($callback, $href, @columns);

  ($form->{customer}, $form->{customer_id}) = split(/--/, $form->{customer});

  report_generator_set_default_sort('transdate', 1);

  AR->ar_transactions(\%myconfig, \%$form);

  $form->{title} = $locale->text('AR Transactions');

  my $report = SL::ReportGenerator->new(\%myconfig, $form);

  @columns =
    qw(transdate id type invnumber ordnumber name netamount tax amount paid
       datepaid due duedate transaction_description notes salesman employee shippingpoint shipvia
       marge_total marge_percent globalprojectnumber customernumber country ustid taxzone payment_terms charts customertype);

  my @hidden_variables = map { "l_${_}" } @columns;
  push @hidden_variables, "l_subtotal", qw(open closed customer invnumber ordnumber transaction_description notes project_id transdatefrom transdateto employee_id salesman_id);

  $href = build_std_url('action=ar_transactions', grep { $form->{$_} } @hidden_variables);

  my %column_defs = (
    'transdate'               => { 'text' => $locale->text('Date'), },
    'id'                      => { 'text' => $locale->text('ID'), },
    'type'                    => { 'text' => $locale->text('Type'), },
    'invnumber'               => { 'text' => $locale->text('Invoice'), },
    'ordnumber'               => { 'text' => $locale->text('Order'), },
    'name'                    => { 'text' => $locale->text('Customer'), },
    'netamount'               => { 'text' => $locale->text('Amount'), },
    'tax'                     => { 'text' => $locale->text('Tax'), },
    'amount'                  => { 'text' => $locale->text('Total'), },
    'paid'                    => { 'text' => $locale->text('Paid'), },
    'datepaid'                => { 'text' => $locale->text('Date Paid'), },
    'due'                     => { 'text' => $locale->text('Amount Due'), },
    'duedate'                 => { 'text' => $locale->text('Due Date'), },
    'transaction_description' => { 'text' => $locale->text('Transaction description'), },
    'notes'                   => { 'text' => $locale->text('Notes'), },
    'salesman'                => { 'text' => $locale->text('Salesperson'), },
    'employee'                => { 'text' => $locale->text('Employee'), },
    'shippingpoint'           => { 'text' => $locale->text('Shipping Point'), },
    'shipvia'                 => { 'text' => $locale->text('Ship via'), },
    'globalprojectnumber'     => { 'text' => $locale->text('Project Number'), },
    'marge_total'             => { 'text' => $locale->text('Ertrag'), },
    'marge_percent'           => { 'text' => $locale->text('Ertrag prozentual'), },
    'customernumber'          => { 'text' => $locale->text('Customer Number'), },
    'country'                 => { 'text' => $locale->text('Country'), },
    'ustid'                   => { 'text' => $locale->text('USt-IdNr.'), },
    'taxzone'                 => { 'text' => $locale->text('Steuersatz'), },
    'payment_terms'           => { 'text' => $locale->text('Payment Terms'), },
    'charts'                  => { 'text' => $locale->text('Buchungskonto'), },
    'customertype'            => { 'text' => $locale->text('Customer type'), },
  );

  foreach my $name (qw(id transdate duedate invnumber ordnumber name datepaid employee shippingpoint shipvia transaction_description)) {
    my $sortdir                 = $form->{sort} eq $name ? 1 - $form->{sortdir} : $form->{sortdir};
    $column_defs{$name}->{link} = $href . "&sort=$name&sortdir=$sortdir";
  }

  my %column_alignment = map { $_ => 'right' } qw(netamount tax amount paid due);

  $form->{"l_type"} = "Y";
  map { $column_defs{$_}->{visible} = $form->{"l_${_}"} ? 1 : 0 } @columns;

  $report->set_columns(%column_defs);
  $report->set_column_order(@columns);

  $report->set_export_options('ar_transactions', @hidden_variables, qw(sort sortdir));

  $report->set_sort_indicator($form->{sort}, $form->{sortdir});

  my @options;
  if ($form->{customer}) {
    push @options, $locale->text('Customer') . " : $form->{customer}";
  }
  if ($form->{department}) {
    my ($department) = split /--/, $form->{department};
    push @options, $locale->text('Department') . " : $department";
  }
  if ($form->{department_id}) {
    push @options, $locale->text('Department Id') . " : $form->{department_id}";
  }
  if ($form->{invnumber}) {
    push @options, $locale->text('Invoice Number') . " : $form->{invnumber}";
  }
  if ($form->{ordnumber}) {
    push @options, $locale->text('Order Number') . " : $form->{ordnumber}";
  }
  if ($form->{notes}) {
    push @options, $locale->text('Notes') . " : $form->{notes}";
  }
  if ($form->{transaction_description}) {
    push @options, $locale->text('Transaction description') . " : $form->{transaction_description}";
  }
  if ($form->{transdatefrom}) {
    push @options, $locale->text('From') . " " . $locale->date(\%myconfig, $form->{transdatefrom}, 1);
  }
  if ($form->{transdateto}) {
    push @options, $locale->text('Bis') . " " . $locale->date(\%myconfig, $form->{transdateto}, 1);
  }
  if ($form->{open}) {
    push @options, $locale->text('Open');
  }
  if ($form->{closed}) {
    push @options, $locale->text('Closed');
  }

  $report->set_options('top_info_text'        => join("\n", @options),
                       'raw_bottom_info_text' => $form->parse_html_template('ar/ar_transactions_bottom'),
                       'output_format'        => 'HTML',
                       'title'                => $form->{title},
                       'attachment_basename'  => $locale->text('invoice_list') . strftime('_%Y%m%d', localtime time),
    );
  $report->set_options_from_form();
  $locale->set_numberformat_wo_thousands_separator(\%myconfig) if lc($report->{options}->{output_format}) eq 'csv';

  # add sort and escape callback, this one we use for the add sub
  $form->{callback} = $href .= "&sort=$form->{sort}";

  # escape callback for href
  $callback = $form->escape($href);

  my @subtotal_columns = qw(netamount amount paid due marge_total marge_percent);

  my %totals    = map { $_ => 0 } @subtotal_columns;
  my %subtotals = map { $_ => 0 } @subtotal_columns;

  my $idx = 0;

  foreach my $ar (@{ $form->{AR} }) {
    $ar->{tax} = $ar->{amount} - $ar->{netamount};
    $ar->{due} = $ar->{amount} - $ar->{paid};

    map { $subtotals{$_} += $ar->{$_};
          $totals{$_}    += $ar->{$_} } @subtotal_columns;

    $subtotals{marge_percent} = $subtotals{netamount} ? ($subtotals{marge_total} * 100 / $subtotals{netamount}) : 0;
    $totals{marge_percent}    = $totals{netamount}    ? ($totals{marge_total}    * 100 / $totals{netamount}   ) : 0;

    map { $ar->{$_} = $form->format_amount(\%myconfig, $ar->{$_}, 2) } qw(netamount tax amount paid due marge_total marge_percent);

    my $is_storno  = $ar->{storno} &&  $ar->{storno_id};
    my $has_storno = $ar->{storno} && !$ar->{storno_id};

    $ar->{type} =
      $has_storno       ? $locale->text("Invoice with Storno (abbreviation)") :
      $is_storno        ? $locale->text("Storno (one letter abbreviation)") :
      $ar->{amount} < 0 ? $locale->text("Credit note (one letter abbreviation)") :
      $ar->{invoice}    ? $locale->text("Invoice (one letter abbreviation)") :
                          $locale->text("AR Transaction (abbreviation)");

    my $row = { };

    foreach my $column (@columns) {
      $row->{$column} = {
        'data'  => $ar->{$column},
        'align' => $column_alignment{$column},
      };
    }

    $row->{invnumber}->{link} = build_std_url("script=" . ($ar->{invoice} ? 'is.pl' : 'ar.pl'), 'action=edit')
      . "&id=" . E($ar->{id}) . "&callback=${callback}";

    my $row_set = [ $row ];

    if (($form->{l_subtotal} eq 'Y')
        && (($idx == (scalar @{ $form->{AR} } - 1))
            || ($ar->{ $form->{sort} } ne $form->{AR}->[$idx + 1]->{ $form->{sort} }))) {
      push @{ $row_set }, create_subtotal_row(\%subtotals, \@columns, \%column_alignment, \@subtotal_columns, 'listsubtotal');
    }

    $report->add_data($row_set);

    $idx++;
  }

  $report->add_separator();
  $report->add_data(create_subtotal_row(\%totals, \@columns, \%column_alignment, \@subtotal_columns, 'listtotal'));

  $report->generate_with_headers();

  $main::lxdebug->leave_sub();
}

sub storno {
  $main::lxdebug->enter_sub();

  $main::auth->assert('general_ledger');

  my $form     = $main::form;
  my %myconfig = %main::myconfig;
  my $locale   = $main::locale;

  # don't cancel cancelled transactions
  if (IS->has_storno(\%myconfig, $form, 'ar')) {
    $form->{title} = $locale->text("Cancel Accounts Receivables Transaction");
    $form->error($locale->text("Transaction has already been cancelled!"));
  }

  AR->storno($form, \%myconfig, $form->{id});

  # saving the history
  if(!exists $form->{addition} && $form->{id} ne "") {
    $form->{snumbers} = "ordnumber_$form->{ordnumber}";
    $form->{addition} = "STORNO";
    $form->save_history;
  }
  # /saving the history

  $form->redirect(sprintf $locale->text("Transaction %d cancelled."), $form->{storno_id});

  $main::lxdebug->leave_sub();
}

1;
