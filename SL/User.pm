#=====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger Accounting
# Copyright (C) 2001
#
#  Author: Dieter Simader
#   Email: dsimader@sql-ledger.org
#     Web: http://www.sql-ledger.org
#
#  Contributors:
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
#=====================================================================
#
# user related functions
#
#=====================================================================

package User;

use IO::File;
use Fcntl qw(:seek);

#use SL::Auth;
use SL::DBConnect;
use SL::DBUpgrade2;
use SL::DBUtils;
use SL::Iconv;
use SL::Inifile;

use strict;

sub new {
  $main::lxdebug->enter_sub();

  my ($type, $login) = @_;

  my $self = {};

  if ($login ne "") {
    my %user_data = $main::auth->read_user($login);
    map { $self->{$_} = $user_data{$_} } keys %user_data;
  }

  $main::lxdebug->leave_sub();

  bless $self, $type;
}

sub country_codes {
  $main::lxdebug->enter_sub();

  local *DIR;

  my %cc       = ();
  my @language = ();

  # scan the locale directory and read in the LANGUAGE files
  opendir(DIR, "locale");

  my @dir = grep(!/(^\.\.?$|\..*)/, readdir(DIR));

  foreach my $dir (@dir) {
    next unless open(FH, "locale/$dir/LANGUAGE");
    @language = <FH>;
    close FH;

    $cc{$dir} = "@language";
  }

  closedir(DIR);

  $main::lxdebug->leave_sub();

  return %cc;
}

sub login {
  $main::lxdebug->enter_sub();

  my ($self, $form) = @_;
  our $sid;

  local *FH;

  my $rc = -3;

  if ($self->{login}) {
    my %myconfig = $main::auth->read_user($self->{login});

    # check if database is down
    my $dbh = SL::DBConnect->connect($myconfig{dbconnect}, $myconfig{dbuser}, $myconfig{dbpasswd})
      or $self->error($DBI::errstr);

    # we got a connection, check the version
    my $query = qq|SELECT version FROM defaults|;
    my $sth   = $dbh->prepare($query);
    $sth->execute || $form->dberror($query);

    my ($dbversion) = $sth->fetchrow_array;
    $sth->finish;

    $self->create_employee_entry($form, $dbh, \%myconfig);

    $self->create_schema_info_table($form, $dbh);

    $rc = 0;

    my $dbupdater = SL::DBUpgrade2->new(form => $form, dbdriver => $myconfig{dbdriver})->parse_dbupdate_controls;

    map({ $form->{$_} = $myconfig{$_} } qw(dbname dbhost dbport dbdriver dbuser dbpasswd dbconnect dateformat));
    dbconnect_vars($form, $form->{dbname});
    my $update_available = $dbupdater->update_available($dbversion) || $dbupdater->update2_available($dbh);
    $dbh->disconnect;

    if ($update_available) {
      $form->{"stylesheet"} = "lx-office-erp.css";
      $form->{"title"} = $main::locale->text("Dataset upgrade");
      $form->header();
      print $form->parse_html_template("dbupgrade/header");

      $form->{dbupdate} = "db$myconfig{dbname}";
      $form->{ $form->{dbupdate} } = 1;

      if ($form->{"show_dbupdate_warning"}) {
        print $form->parse_html_template("dbupgrade/warning");
        ::end_of_request();
      }

      # update the tables
      if (!open(FH, ">" . $::lx_office_conf{paths}->{userspath} . "/nologin")) {
        $form->show_generic_error($main::locale->text('A temporary file could not be created. ' .
                                                      'Please verify that the directory "#1" is writeable by the webserver.',
                                                      $::lx_office_conf{paths}->{userspath}),
                                  'back_button' => 1);
      }

      # required for Oracle
      $form->{dbdefault} = $sid;

      # ignore HUP, QUIT in case the webserver times out
      $SIG{HUP}  = 'IGNORE';
      $SIG{QUIT} = 'IGNORE';

      $self->dbupdate($form);
      $self->dbupdate2($form, $dbupdater);
      SL::DBUpgrade2->new(form => $::form, dbdriver => 'Pg', auth => 1)->apply_admin_dbupgrade_scripts(0);

      close(FH);

      # remove lock file
      unlink($::lx_office_conf{paths}->{userspath} . "/nologin");

      my $menufile =
        $self->{"menustyle"} eq "v3" ? "menuv3.pl" :
        $self->{"menustyle"} eq "neu" ? "menunew.pl" :
        $self->{"menustyle"} eq "js" ? "menujs.pl" :
        $self->{"menustyle"} eq "xml" ? "menuXML.pl" :
        "menu.pl";

      print $form->parse_html_template("dbupgrade/footer", { "menufile" => $menufile });

      $rc = -2;
    }
  }

  $main::lxdebug->leave_sub();

  return $rc;
}

sub dbconnect_vars {
  $main::lxdebug->enter_sub();

  my ($form, $db) = @_;

  my %dboptions = (
        'Pg' => { 'yy-mm-dd'   => 'set DateStyle to \'ISO\'',
                  'yyyy-mm-dd' => 'set DateStyle to \'ISO\'',
                  'mm/dd/yy'   => 'set DateStyle to \'SQL, US\'',
                  'mm-dd-yy'   => 'set DateStyle to \'POSTGRES, US\'',
                  'dd/mm/yy'   => 'set DateStyle to \'SQL, EUROPEAN\'',
                  'dd-mm-yy'   => 'set DateStyle to \'POSTGRES, EUROPEAN\'',
                  'dd.mm.yy'   => 'set DateStyle to \'GERMAN\''
        },
        'Oracle' => {
          'yy-mm-dd'   => 'ALTER SESSION SET NLS_DATE_FORMAT = \'YY-MM-DD\'',
          'yyyy-mm-dd' => 'ALTER SESSION SET NLS_DATE_FORMAT = \'YYYY-MM-DD\'',
          'mm/dd/yy'   => 'ALTER SESSION SET NLS_DATE_FORMAT = \'MM/DD/YY\'',
          'mm-dd-yy'   => 'ALTER SESSION SET NLS_DATE_FORMAT = \'MM-DD-YY\'',
          'dd/mm/yy'   => 'ALTER SESSION SET NLS_DATE_FORMAT = \'DD/MM/YY\'',
          'dd-mm-yy'   => 'ALTER SESSION SET NLS_DATE_FORMAT = \'DD-MM-YY\'',
          'dd.mm.yy'   => 'ALTER SESSION SET NLS_DATE_FORMAT = \'DD.MM.YY\'',
        });

  $form->{dboptions} = $dboptions{ $form->{dbdriver} }{ $form->{dateformat} };

  if ($form->{dbdriver} eq 'Pg') {
    $form->{dbconnect} = "dbi:Pg:dbname=$db";
  }

  if ($form->{dbdriver} eq 'Oracle') {
    $form->{dbconnect} = "dbi:Oracle:sid=$form->{sid}";
  }

  if ($form->{dbhost}) {
    $form->{dbconnect} .= ";host=$form->{dbhost}";
  }
  if ($form->{dbport}) {
    $form->{dbconnect} .= ";port=$form->{dbport}";
  }

  $main::lxdebug->leave_sub();
}

sub dbdrivers {
  $main::lxdebug->enter_sub();

  my @drivers = DBI->available_drivers();

  $main::lxdebug->leave_sub();

  return (grep { /(Pg|Oracle)/ } @drivers);
}

sub dbsources {
  $main::lxdebug->enter_sub();

  my ($self, $form) = @_;

  my @dbsources = ();
  my ($sth, $query);

  $form->{dbdefault} = $form->{dbuser} unless $form->{dbdefault};
  $form->{sid} = $form->{dbdefault};
  &dbconnect_vars($form, $form->{dbdefault});

  my $dbh = SL::DBConnect->connect($form->{dbconnect}, $form->{dbuser}, $form->{dbpasswd})
    or $form->dberror;

  if ($form->{dbdriver} eq 'Pg') {
    $query =
      qq|SELECT datname FROM pg_database | .
      qq|WHERE NOT datname IN ('template0', 'template1')|;
    $sth = $dbh->prepare($query);
    $sth->execute() || $form->dberror($query);

    while (my ($db) = $sth->fetchrow_array) {

      if ($form->{only_acc_db}) {

        next if ($db =~ /^template/);

        &dbconnect_vars($form, $db);
        my $dbh = SL::DBConnect->connect($form->{dbconnect}, $form->{dbuser}, $form->{dbpasswd})
          or $form->dberror;

        $query =
          qq|SELECT tablename FROM pg_tables | .
          qq|WHERE (tablename = 'defaults') AND (tableowner = ?)|;
        my $sth = $dbh->prepare($query);
        $sth->execute($form->{dbuser}) ||
          $form->dberror($query . " ($form->{dbuser})");

        if ($sth->fetchrow_array) {
          push(@dbsources, $db);
        }
        $sth->finish;
        $dbh->disconnect;
        next;
      }
      push(@dbsources, $db);
    }
  }

  if ($form->{dbdriver} eq 'Oracle') {
    if ($form->{only_acc_db}) {
      $query =
        qq|SELECT owner FROM dba_objects | .
        qq|WHERE object_name = 'DEFAULTS' AND object_type = 'TABLE'|;
    } else {
      $query = qq|SELECT username FROM dba_users|;
    }

    $sth = $dbh->prepare($query);
    $sth->execute || $form->dberror($query);

    while (my ($db) = $sth->fetchrow_array) {
      push(@dbsources, $db);
    }
  }

  $sth->finish;
  $dbh->disconnect;

  $main::lxdebug->leave_sub();

  return @dbsources;
}

sub dbclusterencoding {
  $main::lxdebug->enter_sub();

  my ($self, $form) = @_;

  $form->{dbdefault} ||= $form->{dbuser};

  dbconnect_vars($form, $form->{dbdefault});

  my $dbh                = SL::DBConnect->connect($form->{dbconnect}, $form->{dbuser}, $form->{dbpasswd}) || $form->dberror();
  my $query              = qq|SELECT pg_encoding_to_char(encoding) FROM pg_database WHERE datname = 'template0'|;
  my ($cluster_encoding) = $dbh->selectrow_array($query);
  $dbh->disconnect();

  $main::lxdebug->leave_sub();

  return $cluster_encoding;
}

sub dbcreate {
  $main::lxdebug->enter_sub();

  my ($self, $form) = @_;

  $form->{sid} = $form->{dbdefault};
  &dbconnect_vars($form, $form->{dbdefault});
  my $dbh =
    SL::DBConnect->connect($form->{dbconnect}, $form->{dbuser}, $form->{dbpasswd})
    or $form->dberror;
  $form->{db} =~ s/\"//g;
  my %dbcreate = (
    'Pg'     => qq|CREATE DATABASE "$form->{db}"|,
    'Oracle' =>
    qq|CREATE USER "$form->{db}" DEFAULT TABLESPACE USERS | .
    qq|TEMPORARY TABLESPACE TEMP IDENTIFIED BY "$form->{db}"|
  );

  my %dboptions = (
    'Pg' => [],
  );

  push(@{$dboptions{"Pg"}}, "ENCODING = " . $dbh->quote($form->{"encoding"}))
    if ($form->{"encoding"});
  if ($form->{"dbdefault"}) {
    my $dbdefault = $form->{"dbdefault"};
    $dbdefault =~ s/[^a-zA-Z0-9_\-]//g;
    push(@{$dboptions{"Pg"}}, "TEMPLATE = $dbdefault");
  }

  my $query = $dbcreate{$form->{dbdriver}};
  $query .= " WITH " . join(" ", @{$dboptions{"Pg"}}) if (@{$dboptions{"Pg"}});

  # Ignore errors if the database exists.
  $dbh->do($query);

  if ($form->{dbdriver} eq 'Oracle') {
    $query = qq|GRANT CONNECT, RESOURCE TO "$form->{db}"|;
    do_query($form, $dbh, $query);
  }
  $dbh->disconnect;

  # setup variables for the new database
  if ($form->{dbdriver} eq 'Oracle') {
    $form->{dbuser}   = $form->{db};
    $form->{dbpasswd} = $form->{db};
  }

  &dbconnect_vars($form, $form->{db});

  $dbh = SL::DBConnect->connect($form->{dbconnect}, $form->{dbuser}, $form->{dbpasswd})
    or $form->dberror;

  my $db_charset = $Common::db_encoding_to_charset{$form->{encoding}};
  $db_charset ||= Common::DEFAULT_CHARSET;

  my $dbupdater = SL::DBUpgrade2->new(form => $form, dbdriver => $form->{dbdriver});
  # create the tables
  $dbupdater->process_query($dbh, "sql/lx-office.sql", undef, $db_charset);

  # load chart of accounts
  $dbupdater->process_query($dbh, "sql/$form->{chart}-chart.sql", undef, $db_charset);

  $query = "UPDATE defaults SET coa = ?";
  do_query($form, $dbh, $query, $form->{chart});

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub dbdelete {
  $main::lxdebug->enter_sub();

  my ($self, $form) = @_;
  $form->{db} =~ s/\"//g;
  my %dbdelete = ('Pg'     => qq|DROP DATABASE "$form->{db}"|,
                  'Oracle' => qq|DROP USER "$form->{db}" CASCADE|);

  $form->{sid} = $form->{dbdefault};
  &dbconnect_vars($form, $form->{dbdefault});
  my $dbh = SL::DBConnect->connect($form->{dbconnect}, $form->{dbuser}, $form->{dbpasswd})
    or $form->dberror;
  my $query = $dbdelete{$form->{dbdriver}};
  do_query($form, $dbh, $query);

  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub dbsources_unused {
  $main::lxdebug->enter_sub();

  my ($self, $form) = @_;

  $form->{only_acc_db} = 1;

  my %members = $main::auth->read_all_users();
  my %dbexcl  = map { $_ => 1 } grep { $_ } map { $_->{dbname} } values %members;

  $dbexcl{$form->{dbdefault}}             = 1;
  $dbexcl{$main::auth->{DB_config}->{db}} = 1;

  my @dbunused = grep { !$dbexcl{$_} } dbsources("", $form);

  $main::lxdebug->leave_sub();

  return @dbunused;
}

sub dbneedsupdate {
  $main::lxdebug->enter_sub();

  my ($self, $form) = @_;

  my %members   = $main::auth->read_all_users();
  my $dbupdater = SL::DBUpgrade2->new(form => $form, dbdriver => $form->{dbdriver})->parse_dbupdate_controls;

  my ($query, $sth, %dbs_needing_updates);

  foreach my $login (grep /[a-z]/, keys %members) {
    my $member = $members{$login};

    map { $form->{$_} = $member->{$_} } qw(dbname dbuser dbpasswd dbhost dbport);
    dbconnect_vars($form, $form->{dbname});

    my $dbh = SL::DBConnect->connect($form->{dbconnect}, $form->{dbuser}, $form->{dbpasswd});

    next unless $dbh;

    my $version;

    $query = qq|SELECT version FROM defaults|;
    $sth = prepare_query($form, $dbh, $query);
    if ($sth->execute()) {
      ($version) = $sth->fetchrow_array();
    }
    $sth->finish();

    $dbh->disconnect and next unless $version;

    my $update_available = $dbupdater->update_available($version) || $dbupdater->update2_available($dbh);
    $dbh->disconnect;

   if ($update_available) {
      my $dbinfo = {};
      map { $dbinfo->{$_} = $member->{$_} } grep /^db/, keys %{ $member };
      $dbs_needing_updates{$member->{dbhost} . "::" . $member->{dbname}} = $dbinfo;
    }
  }

  $main::lxdebug->leave_sub();

  return values %dbs_needing_updates;
}

sub calc_version {
  $main::lxdebug->enter_sub(2);

  my (@v, $version, $i);

  @v = split(/\./, $_[0]);
  while (scalar(@v) < 4) {
    push(@v, 0);
  }
  $version = 0;
  for ($i = 0; $i < 4; $i++) {
    $version *= 1000;
    $version += $v[$i];
  }

  $main::lxdebug->leave_sub(2);
  return $version;
}

sub cmp_script_version {
  my ($a_from, $a_to, $b_from, $b_to);
  my ($i, $res_a, $res_b);
  my ($my_a, $my_b) = ($a, $b);

  $my_a =~ s/.*-upgrade-//;
  $my_a =~ s/.sql$//;
  $my_b =~ s/.*-upgrade-//;
  $my_b =~ s/.sql$//;
  my ($my_a_from, $my_a_to) = split(/-/, $my_a);
  my ($my_b_from, $my_b_to) = split(/-/, $my_b);

  $res_a = calc_version($my_a_from);
  $res_b = calc_version($my_b_from);

  if ($res_a == $res_b) {
    $res_a = calc_version($my_a_to);
    $res_b = calc_version($my_b_to);
  }

  return $res_a <=> $res_b;
}

sub create_schema_info_table {
  $main::lxdebug->enter_sub();

  my ($self, $form, $dbh) = @_;

  my $query = "SELECT tag FROM schema_info LIMIT 1";
  if (!$dbh->do($query)) {
    $dbh->rollback();
    $query =
      qq|CREATE TABLE schema_info (| .
      qq|  tag text, | .
      qq|  login text, | .
      qq|  itime timestamp DEFAULT now(), | .
      qq|  PRIMARY KEY (tag))|;
    $dbh->do($query) || $form->dberror($query);
  }

  $main::lxdebug->leave_sub();
}

sub dbupdate {
  $main::lxdebug->enter_sub();

  my ($self, $form) = @_;

  local *SQLDIR;

  $form->{sid} = $form->{dbdefault};

  my @upgradescripts = ();
  my $query;
  my $rc = -2;

  if ($form->{dbupdate}) {

    # read update scripts into memory
    opendir(SQLDIR, "sql/" . $form->{dbdriver} . "-upgrade")
      or &error("", "sql/" . $form->{dbdriver} . "-upgrade : $!");
    @upgradescripts =
      sort(cmp_script_version
           grep(/$form->{dbdriver}-upgrade-.*?\.(sql|pl)$/,
                readdir(SQLDIR)));
    closedir(SQLDIR);
  }

  my $db_charset = $::lx_office_conf{system}->{dbcharset};
  $db_charset ||= Common::DEFAULT_CHARSET;

  my $dbupdater = SL::DBUpgrade2->new(form => $form, dbdriver => $form->{dbdriver});

  foreach my $db (split(/ /, $form->{dbupdate})) {

    next unless $form->{$db};

    # strip db from dataset
    $db =~ s/^db//;
    &dbconnect_vars($form, $db);

    my $dbh = SL::DBConnect->connect($form->{dbconnect}, $form->{dbuser}, $form->{dbpasswd})
      or $form->dberror;

    $dbh->do($form->{dboptions}) if ($form->{dboptions});

    # check version
    $query = qq|SELECT version FROM defaults|;
    my ($version) = selectrow_query($form, $dbh, $query);

    next unless $version;

    $version = calc_version($version);

    foreach my $upgradescript (@upgradescripts) {
      my $a = $upgradescript;
      $a =~ s/^\Q$form->{dbdriver}\E-upgrade-|\.(sql|pl)$//g;

      my ($mindb, $maxdb) = split /-/, $a;
      my $str_maxdb = $maxdb;
      $mindb = calc_version($mindb);
      $maxdb = calc_version($maxdb);

      next if ($version >= $maxdb);

      # if there is no upgrade script exit
      last if ($version < $mindb);

      # apply upgrade
      $main::lxdebug->message(LXDebug->DEBUG2(), "Applying Update $upgradescript");
      $dbupdater->process_file($dbh, "sql/" . $form->{"dbdriver"} . "-upgrade/$upgradescript", $str_maxdb, $db_charset);

      $version = $maxdb;

    }

    $rc = 0;
    $dbh->disconnect;

  }

  $main::lxdebug->leave_sub();

  return $rc;
}

sub dbupdate2 {
  $main::lxdebug->enter_sub();

  my ($self, $form, $dbupdater) = @_;

  $form->{sid} = $form->{dbdefault};

  my $rc         = -2;
  my $db_charset = $::lx_office_conf{system}->{dbcharset} || Common::DEFAULT_CHARSET;

  map { $_->{description} = SL::Iconv::convert($_->{charset}, $db_charset, $_->{description}) } values %{ $dbupdater->{all_controls} };

  foreach my $db (split / /, $form->{dbupdate}) {
    next unless $form->{$db};

    # strip db from dataset
    $db =~ s/^db//;
    &dbconnect_vars($form, $db);

    my $dbh = SL::DBConnect->connect($form->{dbconnect}, $form->{dbuser}, $form->{dbpasswd}) or $form->dberror;

    $dbh->do($form->{dboptions}) if ($form->{dboptions});

    $self->create_schema_info_table($form, $dbh);

    my @upgradescripts = $dbupdater->unapplied_upgrade_scripts($dbh);

    $dbh->disconnect and next if !@upgradescripts;

    foreach my $control (@upgradescripts) {
      # apply upgrade
      $main::lxdebug->message(LXDebug->DEBUG2(), "Applying Update $control->{file}");
      print $form->parse_html_template("dbupgrade/upgrade_message2", $control);

      $dbupdater->process_file($dbh, "sql/" . $form->{"dbdriver"} . "-upgrade2/$control->{file}", $control, $db_charset);
    }

    $rc = 0;
    $dbh->disconnect;

  }

  $main::lxdebug->leave_sub();

  return $rc;
}

sub save_member {
  $main::lxdebug->enter_sub();

  my ($self) = @_;
  my $form   = \%main::form;

  # format dbconnect and dboptions string
  dbconnect_vars($self, $self->{dbname});

  map { $self->{$_} =~ s/\r//g; } qw(address signature);

  $main::auth->save_user($self->{login}, map { $_, $self->{$_} } config_vars());

  my $dbh = SL::DBConnect->connect($self->{dbconnect}, $self->{dbuser}, $self->{dbpasswd});
  if ($dbh) {
    $self->create_employee_entry($form, $dbh, $self, 1);
    $dbh->disconnect();
  }

  $main::lxdebug->leave_sub();
}

sub create_employee_entry {
  $main::lxdebug->enter_sub();

  my $self            = shift;
  my $form            = shift;
  my $dbh             = shift;
  my $myconfig        = shift;
  my $update_existing = shift;

  if (!does_table_exist($dbh, 'employee')) {
    $main::lxdebug->leave_sub();
    return;
  }

  # add login to employee table if it does not exist
  # no error check for employee table, ignore if it does not exist
  my ($id)  = selectrow_query($form, $dbh, qq|SELECT id FROM employee WHERE login = ?|, $self->{login});

  if (!$id) {
    my $query = qq|INSERT INTO employee (login, name, workphone, role) VALUES (?, ?, ?, ?)|;
    do_query($form, $dbh, $query, ($self->{login}, $myconfig->{name}, $myconfig->{tel}, "user"));

  } elsif ($update_existing) {
    my $query = qq|UPDATE employee SET name = ?, workphone = ?, role = 'user' WHERE id = ?|;
    do_query($form, $dbh, $query, $myconfig->{name}, $myconfig->{tel}, $id);
  }

  $main::lxdebug->leave_sub();
}

sub config_vars {
  $main::lxdebug->enter_sub();

  my @conf = qw(address admin businessnumber company countrycode
    currency dateformat dbconnect dbdriver dbhost dbport dboptions
    dbname dbuser dbpasswd email fax name numberformat password
    printer role sid signature stylesheet tel templates vclimit angebote
    bestellungen rechnungen anfragen lieferantenbestellungen einkaufsrechnungen
    taxnumber co_ustid duns menustyle template_format default_media
    default_printer_id copies show_form_details favorites
    pdonumber sdonumber hide_cvar_search_options mandatory_departments
    sepa_creditor_id);

  $main::lxdebug->leave_sub();

  return @conf;
}

sub error {
  $main::lxdebug->enter_sub();

  my ($self, $msg) = @_;

  $main::lxdebug->show_backtrace();

  if ($ENV{HTTP_USER_AGENT}) {
    print qq|Content-Type: text/html

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0//EN">

<body bgcolor=ffffff>

<h2><font color=red>Error!</font></h2>
<p><b>$msg</b>|;

  }

  die "Error: $msg\n";

  $main::lxdebug->leave_sub();
}

1;

