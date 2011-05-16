#====================================================================
# LX-Office ERP
# Copyright (C) 2004
# Based on SQL-Ledger Version 2.1.9
# Web http://www.lx-office.org
#
#=====================================================================
# SQL-Ledger Accounting
# Copyright (C) 1998-2002
#
#  Author: Dieter Simader
#   Email: dsimader@sql-ledger.org
#     Web: http://www.sql-ledger.org
#
# Contributors: Thomas Bayen <bayen@gmx.de>
#               Antti Kaihola <akaihola@siba.fi>
#               Moritz Bunkus (tex code)
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
# Utilities for parsing forms
# and supporting routines for linking account numbers
# used in AR, AP and IS, IR modules
#
#======================================================================

package Form;

use Data::Dumper;

use CGI;
use CGI::Ajax;
use Cwd;
use Encode;
use File::Copy;
use IO::File;
use SL::Auth;
use SL::Auth::DB;
use SL::Auth::LDAP;
use SL::AM;
use SL::Common;
use SL::CVar;
use SL::DB;
use SL::DBConnect;
use SL::DBUtils;
use SL::DO;
use SL::IC;
use SL::IS;
use SL::Mailer;
use SL::Menu;
use SL::OE;
use SL::Template;
use SL::User;
use SL::X;
use Template;
use URI;
use List::Util qw(first max min sum);
use List::MoreUtils qw(all any apply);

use strict;

my $standard_dbh;

END {
  disconnect_standard_dbh();
}

sub disconnect_standard_dbh {
  return unless $standard_dbh;
  $standard_dbh->disconnect();
  undef $standard_dbh;
}

sub _store_value {
  $main::lxdebug->enter_sub(2);

  my $self  = shift;
  my $key   = shift;
  my $value = shift;

  my @tokens = split /((?:\[\+?\])?(?:\.|$))/, $key;

  my $curr;

  if (scalar @tokens) {
     $curr = \ $self->{ shift @tokens };
  }

  while (@tokens) {
    my $sep = shift @tokens;
    my $key = shift @tokens;

    $curr = \ $$curr->[++$#$$curr], next if $sep eq '[]';
    $curr = \ $$curr->[max 0, $#$$curr]  if $sep eq '[].';
    $curr = \ $$curr->[++$#$$curr]       if $sep eq '[+].';
    $curr = \ $$curr->{$key}
  }

  $$curr = $value;

  $main::lxdebug->leave_sub(2);

  return $curr;
}

sub _input_to_hash {
  $main::lxdebug->enter_sub(2);

  my $self  = shift;
  my $input = shift;

  my @pairs = split(/&/, $input);

  foreach (@pairs) {
    my ($key, $value) = split(/=/, $_, 2);
    $self->_store_value($self->unescape($key), $self->unescape($value)) if ($key);
  }

  $main::lxdebug->leave_sub(2);
}

sub _request_to_hash {
  $main::lxdebug->enter_sub(2);

  my $self  = shift;
  my $input = shift;
  my $uploads = {};

  if (!$ENV{'CONTENT_TYPE'}
      || ($ENV{'CONTENT_TYPE'} !~ /multipart\/form-data\s*;\s*boundary\s*=\s*(.+)$/)) {

    $self->_input_to_hash($input);

    $main::lxdebug->leave_sub(2);
    return $uploads;
  }

  my ($name, $filename, $headers_done, $content_type, $boundary_found, $need_cr, $previous);

  my $boundary = '--' . $1;

  foreach my $line (split m/\n/, $input) {
    last if (($line eq "${boundary}--") || ($line eq "${boundary}--\r"));

    if (($line eq $boundary) || ($line eq "$boundary\r")) {
      ${ $previous } =~ s|\r?\n$|| if $previous;

      undef $previous;
      undef $filename;

      $headers_done   = 0;
      $content_type   = "text/plain";
      $boundary_found = 1;
      $need_cr        = 0;

      next;
    }

    next unless $boundary_found;

    if (!$headers_done) {
      $line =~ s/[\r\n]*$//;

      if (!$line) {
        $headers_done = 1;
        next;
      }

      if ($line =~ m|^content-disposition\s*:.*?form-data\s*;|i) {
        if ($line =~ m|filename\s*=\s*"(.*?)"|i) {
          $filename = $1;
          substr $line, $-[0], $+[0] - $-[0], "";
        }

        if ($line =~ m|name\s*=\s*"(.*?)"|i) {
          $name = $1;
          substr $line, $-[0], $+[0] - $-[0], "";
        }

        $previous         = _store_value($uploads, $name, '') if ($name);
        $self->{FILENAME} = $filename if ($filename);

        next;
      }

      if ($line =~ m|^content-type\s*:\s*(.*?)$|i) {
        $content_type = $1;
      }

      next;
    }

    next unless $previous;

    ${ $previous } .= "${line}\n";
  }

  ${ $previous } =~ s|\r?\n$|| if $previous;

  $main::lxdebug->leave_sub(2);

  return $uploads;
}

sub _recode_recursively {
  $main::lxdebug->enter_sub();
  my ($iconv, $param) = @_;

  if (any { ref $param eq $_ } qw(Form HASH)) {
    foreach my $key (keys %{ $param }) {
      if (!ref $param->{$key}) {
        # Workaround for a bug: converting $param->{$key} directly
        # leads to 'undef'. I don't know why. Converting a copy works,
        # though.
        $param->{$key} = $iconv->convert("" . $param->{$key});
      } else {
        _recode_recursively($iconv, $param->{$key});
      }
    }

  } elsif (ref $param eq 'ARRAY') {
    foreach my $idx (0 .. scalar(@{ $param }) - 1) {
      if (!ref $param->[$idx]) {
        # Workaround for a bug: converting $param->[$idx] directly
        # leads to 'undef'. I don't know why. Converting a copy works,
        # though.
        $param->[$idx] = $iconv->convert("" . $param->[$idx]);
      } else {
        _recode_recursively($iconv, $param->[$idx]);
      }
    }
  }
  $main::lxdebug->leave_sub();
}

sub new {
  $main::lxdebug->enter_sub();

  my $type = shift;

  my $self = {};

  if ($LXDebug::watch_form) {
    require SL::Watchdog;
    tie %{ $self }, 'SL::Watchdog';
  }

  bless $self, $type;

  $self->_input_to_hash($ENV{QUERY_STRING}) if $ENV{QUERY_STRING};
  $self->_input_to_hash($ARGV[0])           if @ARGV && $ARGV[0];

  my $uploads;
  if ($ENV{CONTENT_LENGTH}) {
    my $content;
    read STDIN, $content, $ENV{CONTENT_LENGTH};
    $uploads = $self->_request_to_hash($content);
  }

  my $db_charset   = $::lx_office_conf{system}->{dbcharset};
  $db_charset    ||= Common::DEFAULT_CHARSET;

  my $encoding     = $self->{INPUT_ENCODING} || $db_charset;
  delete $self->{INPUT_ENCODING};

  _recode_recursively(SL::Iconv->new($encoding, $db_charset), $self);

  map { $self->{$_} = $uploads->{$_} } keys %{ $uploads } if $uploads;

  #$self->{version} =  "2.6.1";                 # Old hardcoded but secure style
  open VERSION_FILE, "VERSION";                 # New but flexible code reads version from VERSION-file
  $self->{version} =  <VERSION_FILE>;
  close VERSION_FILE;
  $self->{version}  =~ s/[^0-9A-Za-z\.\_\-]//g; # only allow numbers, letters, points, underscores and dashes. Prevents injecting of malicious code.

  $main::lxdebug->leave_sub();

  return $self;
}

sub _flatten_variables_rec {
  $main::lxdebug->enter_sub(2);

  my $self   = shift;
  my $curr   = shift;
  my $prefix = shift;
  my $key    = shift;

  my @result;

  if ('' eq ref $curr->{$key}) {
    @result = ({ 'key' => $prefix . $key, 'value' => $curr->{$key} });

  } elsif ('HASH' eq ref $curr->{$key}) {
    foreach my $hash_key (sort keys %{ $curr->{$key} }) {
      push @result, $self->_flatten_variables_rec($curr->{$key}, $prefix . $key . '.', $hash_key);
    }

  } else {
    foreach my $idx (0 .. scalar @{ $curr->{$key} } - 1) {
      my $first_array_entry = 1;

      foreach my $hash_key (sort keys %{ $curr->{$key}->[$idx] }) {
        push @result, $self->_flatten_variables_rec($curr->{$key}->[$idx], $prefix . $key . ($first_array_entry ? '[+].' : '[].'), $hash_key);
        $first_array_entry = 0;
      }
    }
  }

  $main::lxdebug->leave_sub(2);

  return @result;
}

sub flatten_variables {
  $main::lxdebug->enter_sub(2);

  my $self = shift;
  my @keys = @_;

  my @variables;

  foreach (@keys) {
    push @variables, $self->_flatten_variables_rec($self, '', $_);
  }

  $main::lxdebug->leave_sub(2);

  return @variables;
}

sub flatten_standard_variables {
  $main::lxdebug->enter_sub(2);

  my $self      = shift;
  my %skip_keys = map { $_ => 1 } (qw(login password header stylesheet titlebar version), @_);

  my @variables;

  foreach (grep { ! $skip_keys{$_} } keys %{ $self }) {
    push @variables, $self->_flatten_variables_rec($self, '', $_);
  }

  $main::lxdebug->leave_sub(2);

  return @variables;
}

sub debug {
  $main::lxdebug->enter_sub();

  my ($self) = @_;

  print "\n";

  map { print "$_ = $self->{$_}\n" } (sort keys %{$self});

  $main::lxdebug->leave_sub();
}

sub dumper {
  $main::lxdebug->enter_sub(2);

  my $self          = shift;
  my $password      = $self->{password};

  $self->{password} = 'X' x 8;

  local $Data::Dumper::Sortkeys = 1;
  my $output                    = Dumper($self);

  $self->{password} = $password;

  $main::lxdebug->leave_sub(2);

  return $output;
}

sub escape {
  $main::lxdebug->enter_sub(2);

  my ($self, $str) = @_;

  $str =  Encode::encode('utf-8-strict', $str) if $::locale->is_utf8;
  $str =~ s/([^a-zA-Z0-9_.:-])/sprintf("%%%02x", ord($1))/ge;

  $main::lxdebug->leave_sub(2);

  return $str;
}

sub unescape {
  $main::lxdebug->enter_sub(2);

  my ($self, $str) = @_;

  $str =~ tr/+/ /;
  $str =~ s/\\$//;

  $str =~ s/%([0-9a-fA-Z]{2})/pack("c",hex($1))/eg;
  $str =  Encode::decode('utf-8-strict', $str) if $::locale->is_utf8;

  $main::lxdebug->leave_sub(2);

  return $str;
}

sub quote {
  $main::lxdebug->enter_sub();
  my ($self, $str) = @_;

  if ($str && !ref($str)) {
    $str =~ s/\"/&quot;/g;
  }

  $main::lxdebug->leave_sub();

  return $str;
}

sub unquote {
  $main::lxdebug->enter_sub();
  my ($self, $str) = @_;

  if ($str && !ref($str)) {
    $str =~ s/&quot;/\"/g;
  }

  $main::lxdebug->leave_sub();

  return $str;
}

sub hide_form {
  $main::lxdebug->enter_sub();
  my $self = shift;

  if (@_) {
    map({ print($main::cgi->hidden("-name" => $_, "-default" => $self->{$_}) . "\n"); } @_);
  } else {
    for (sort keys %$self) {
      next if (($_ eq "header") || (ref($self->{$_}) ne ""));
      print($main::cgi->hidden("-name" => $_, "-default" => $self->{$_}) . "\n");
    }
  }
  $main::lxdebug->leave_sub();
}

sub throw_on_error {
  my ($self, $code) = @_;
  local $self->{__ERROR_HANDLER} = sub { die SL::X::FormError->new($_[0]) };
  $code->();
}

sub error {
  $main::lxdebug->enter_sub();

  $main::lxdebug->show_backtrace();

  my ($self, $msg) = @_;

  if ($self->{__ERROR_HANDLER}) {
    $self->{__ERROR_HANDLER}->($msg);

  } elsif ($ENV{HTTP_USER_AGENT}) {
    $msg =~ s/\n/<br>/g;
    $self->show_generic_error($msg);

  } else {
    print STDERR "Error: $msg\n";
    ::end_of_request();
  }

  $main::lxdebug->leave_sub();
}

sub info {
  $main::lxdebug->enter_sub();

  my ($self, $msg) = @_;

  if ($ENV{HTTP_USER_AGENT}) {
    $msg =~ s/\n/<br>/g;

    if (!$self->{header}) {
      $self->header;
      print qq|<body>|;
    }

    print qq|
    <p class="message_ok"><b>$msg</b></p>

    <script type="text/javascript">
    <!--
    // If JavaScript is enabled, the whole thing will be reloaded.
    // The reason is: When one changes his menu setup (HTML / XUL / CSS ...)
    // it now loads the correct code into the browser instead of do nothing.
    setTimeout("top.frames.location.href='login.pl'",500);
    //-->
    </script>

</body>
    |;

  } else {

    if ($self->{info_function}) {
      &{ $self->{info_function} }($msg);
    } else {
      print "$msg\n";
    }
  }

  $main::lxdebug->leave_sub();
}

# calculates the number of rows in a textarea based on the content and column number
# can be capped with maxrows
sub numtextrows {
  $main::lxdebug->enter_sub();
  my ($self, $str, $cols, $maxrows, $minrows) = @_;

  $minrows ||= 1;

  my $rows   = sum map { int((length() - 2) / $cols) + 1 } split /\r/, $str;
  $maxrows ||= $rows;

  $main::lxdebug->leave_sub();

  return max(min($rows, $maxrows), $minrows);
}

sub dberror {
  $main::lxdebug->enter_sub();

  my ($self, $msg) = @_;

  $self->error("$msg\n" . $DBI::errstr);

  $main::lxdebug->leave_sub();
}

sub isblank {
  $main::lxdebug->enter_sub();

  my ($self, $name, $msg) = @_;

  my $curr = $self;
  foreach my $part (split m/\./, $name) {
    if (!$curr->{$part} || ($curr->{$part} =~ /^\s*$/)) {
      $self->error($msg);
    }
    $curr = $curr->{$part};
  }

  $main::lxdebug->leave_sub();
}

sub _get_request_uri {
  my $self = shift;

  return URI->new($ENV{HTTP_REFERER})->canonical() if $ENV{HTTP_X_FORWARDED_FOR};

  my $scheme =  $ENV{HTTPS} && (lc $ENV{HTTPS} eq 'on') ? 'https' : 'http';
  my $port   =  $ENV{SERVER_PORT} || '';
  $port      =  undef if (($scheme eq 'http' ) && ($port == 80))
                      || (($scheme eq 'https') && ($port == 443));

  my $uri    =  URI->new("${scheme}://");
  $uri->scheme($scheme);
  $uri->port($port);
  $uri->host($ENV{HTTP_HOST} || $ENV{SERVER_ADDR});
  $uri->path_query($ENV{REQUEST_URI});
  $uri->query('');

  return $uri;
}

sub _add_to_request_uri {
  my $self              = shift;

  my $relative_new_path = shift;
  my $request_uri       = shift || $self->_get_request_uri;
  my $relative_new_uri  = URI->new($relative_new_path);
  my @request_segments  = $request_uri->path_segments;

  my $new_uri           = $request_uri->clone;
  $new_uri->path_segments(@request_segments[0..scalar(@request_segments) - 2], $relative_new_uri->path_segments);

  return $new_uri;
}

sub create_http_response {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my %params   = @_;

  my $cgi      = $main::cgi;
  $cgi       ||= CGI->new('');

  my $session_cookie;
  if (defined $main::auth) {
    my $uri      = $self->_get_request_uri;
    my @segments = $uri->path_segments;
    pop @segments;
    $uri->path_segments(@segments);

    my $session_cookie_value = $main::auth->get_session_id();

    if ($session_cookie_value) {
      $session_cookie = $cgi->cookie('-name'   => $main::auth->get_session_cookie_name(),
                                     '-value'  => $session_cookie_value,
                                     '-path'   => $uri->path,
                                     '-secure' => $ENV{HTTPS});
    }
  }

  my %cgi_params = ('-type' => $params{content_type});
  $cgi_params{'-charset'} = $params{charset} if ($params{charset});
  $cgi_params{'-cookie'}  = $session_cookie  if ($session_cookie);

  map { $cgi_params{'-' . $_} = $params{$_} if exists $params{$_} } qw(content_disposition content_length);

  my $output = $cgi->header(%cgi_params);

  $main::lxdebug->leave_sub();

  return $output;
}


sub header {
  $::lxdebug->enter_sub;

  # extra code is currently only used by menuv3 and menuv4 to set their css.
  # it is strongly deprecated, and will be changed in a future version.
  my ($self, $extra_code) = @_;
  my $db_charset = $::lx_office_conf{system}->{dbcharset} || Common::DEFAULT_CHARSET;
  my @header;

  $::lxdebug->leave_sub and return if !$ENV{HTTP_USER_AGENT} || $self->{header}++;

  $self->{favicon} ||= "favicon.ico";
  $self->{titlebar}  = "$self->{title} - $self->{titlebar}" if $self->{title};

  # build includes
  if ($self->{refresh_url} || $self->{refresh_time}) {
    my $refresh_time = $self->{refresh_time} || 3;
    my $refresh_url  = $self->{refresh_url}  || $ENV{REFERER};
    push @header, "<meta http-equiv='refresh' content='$refresh_time;$refresh_url'>";
  }

  push @header, "<link rel='stylesheet' href='css/$_' type='text/css' title='Lx-Office stylesheet'>"
    for grep { -f "css/$_" } apply { s|.*/|| } $self->{stylesheet}, $self->{stylesheets};

  push @header, "<style type='text/css'>\@page { size:landscape; }</style>" if $self->{landscape};
  push @header, "<link rel='shortcut icon' href='$self->{favicon}' type='image/x-icon'>" if -f $self->{favicon};
  push @header, '<script type="text/javascript" src="js/jquery.js"></script>',
                '<script type="text/javascript" src="js/jquery.autocomplete.js"></script>',
                '<script type="text/javascript" src="js/jquery.alerts.js"></script>',
                '<link type="text/css" href="css/start/jquery-ui-1.8.11.custom.css" rel="stylesheet" />',
                '<link type="text/css" href="css/jquery.alerts.css" rel="stylesheet" />',
                '<script type="text/javascript" src="js/common.js"></script>',
                '<style type="text/css">@import url(js/jscalendar/calendar-win2k-1.css);</style>',
                '<script type="text/javascript" src="js/jscalendar/calendar.js"></script>',
                '<script type="text/javascript" src="js/jscalendar/lang/calendar-de.js"></script>',
                '<script type="text/javascript" src="js/jscalendar/calendar-setup.js"></script>',
                '<script type="text/javascript" src="js/part_selection.js"></script>';
  push @header, $self->{javascript} if $self->{javascript};
  push @header, map { $_->show_javascript } @{ $self->{AJAX} || [] };
  push @header, "<script type='text/javascript'>function fokus(){ document.$self->{fokus}.focus(); }</script>" if $self->{fokus};
  push @header, sprintf "<script type='text/javascript'>top.document.title='%s';</script>",
    join ' - ', grep $_, $self->{title}, $self->{login}, $::myconfig{dbname}, $self->{version} if $self->{title};

  # if there is a title, we put some JavaScript in to the page, wich writes a
  # meaningful title-tag for our frameset.
  my $title_hack = '';
  if ($self->{title}) {
    $title_hack = qq|
    <script type="text/javascript">
    <!--
      // Write a meaningful title-tag for our frameset.
      top.document.title="| . $self->{"title"} . qq| - | . $self->{"login"} . qq| - | . $::myconfig{dbname} . qq| - V| . $self->{"version"} . qq|";
    //-->
    </script>|;
  }

  # output
  print $self->create_http_response(content_type => 'text/html', charset => $db_charset);
  print "<!DOCTYPE HTML PUBLIC '-//W3C//DTD HTML 4.01//EN' 'http://www.w3.org/TR/html4/strict.dtd'>\n"
    if  $ENV{'HTTP_USER_AGENT'} =~ m/MSIE\s+\d/; # Other browsers may choke on menu scripts with DOCTYPE.
  print <<EOT;
<html>
 <head>
  <meta http-equiv="Content-Type" content="text/html; charset=$db_charset">
  <title>$self->{titlebar}</title>
EOT
  print "  $_\n" for @header;
  print <<EOT;
  <meta name="robots" content="noindex,nofollow" />
  <link rel="stylesheet" type="text/css" href="css/tabcontent.css" />
  <script type="text/javascript" src="js/tabcontent.js">

  /***********************************************
   * Tab Content script v2.2- � Dynamic Drive DHTML code library (www.dynamicdrive.com)
   * This notice MUST stay intact for legal use
   * Visit Dynamic Drive at http://www.dynamicdrive.com/ for full source code
   ***********************************************/

  </script>
  $extra_code
  $title_hack
 </head>

EOT

  $::lxdebug->leave_sub;
}

sub ajax_response_header {
  $main::lxdebug->enter_sub();

  my ($self) = @_;

  my $db_charset = $::lx_office_conf{system}->{dbcharset} || Common::DEFAULT_CHARSET;
  my $cgi        = $main::cgi || CGI->new('');
  my $output     = $cgi->header('-charset' => $db_charset);

  $main::lxdebug->leave_sub();

  return $output;
}

sub redirect_header {
  my $self     = shift;
  my $new_url  = shift;

  my $base_uri = $self->_get_request_uri;
  my $new_uri  = URI->new_abs($new_url, $base_uri);

  die "Headers already sent" if $self->{header};
  $self->{header} = 1;

  my $cgi = $main::cgi || CGI->new('');
  return $cgi->redirect($new_uri);
}

sub set_standard_title {
  $::lxdebug->enter_sub;
  my $self = shift;

  $self->{titlebar}  = "Lx-Office " . $::locale->text('Version') . " $self->{version}";
  $self->{titlebar} .= "- $::myconfig{name}"   if $::myconfig{name};
  $self->{titlebar} .= "- $::myconfig{dbname}" if $::myconfig{name};

  $::lxdebug->leave_sub;
}

sub _prepare_html_template {
  $main::lxdebug->enter_sub();

  my ($self, $file, $additional_params) = @_;
  my $language;

  if (!%::myconfig || !$::myconfig{"countrycode"}) {
    $language = $::lx_office_conf{system}->{language};
  } else {
    $language = $main::myconfig{"countrycode"};
  }
  $language = "de" unless ($language);

  if (-f "templates/webpages/${file}.html") {
    if ((-f ".developer") && ((stat("templates/webpages/${file}.html"))[9] > (stat("locale/${language}/all"))[9])) {
      my $info = "Developer information: templates/webpages/${file}.html is newer than the translation file locale/${language}/all.\n" .
        "Please re-run 'locales.pl' in 'locale/${language}'.";
      print(qq|<pre>$info</pre>|);
      ::end_of_request();
    }

    $file = "templates/webpages/${file}.html";

  } else {
    my $info = "Web page template '${file}' not found.\n";
    print qq|<pre>$info</pre>|;
    ::end_of_request();
  }

  if ($self->{"DEBUG"}) {
    $additional_params->{"DEBUG"} = $self->{"DEBUG"};
  }

  if ($additional_params->{"DEBUG"}) {
    $additional_params->{"DEBUG"} =
      "<br><em>DEBUG INFORMATION:</em><pre>" . $additional_params->{"DEBUG"} . "</pre>";
  }

  if (%main::myconfig) {
    $::myconfig{jsc_dateformat} = apply {
      s/d+/\%d/gi;
      s/m+/\%m/gi;
      s/y+/\%Y/gi;
    } $::myconfig{"dateformat"};
    $additional_params->{"myconfig"} ||= \%::myconfig;
    map { $additional_params->{"myconfig_${_}"} = $main::myconfig{$_}; } keys %::myconfig;
  }

  $additional_params->{"conf_dbcharset"}              = $::lx_office_conf{system}->{dbcharset};
  $additional_params->{"conf_webdav"}                 = $::lx_office_conf{features}->{webdav};
  $additional_params->{"conf_lizenzen"}               = $::lx_office_conf{features}->{lizenzen};
  $additional_params->{"conf_latex_templates"}        = $::lx_office_conf{print_templates}->{latex};
  $additional_params->{"conf_opendocument_templates"} = $::lx_office_conf{print_templates}->{opendocument};
  $additional_params->{"conf_vertreter"}              = $::lx_office_conf{features}->{vertreter};
  $additional_params->{"conf_show_best_before"}       = $::lx_office_conf{features}->{show_best_before};
  $additional_params->{"conf_parts_image_css"}        = $::lx_office_conf{features}->{parts_image_css};
  $additional_params->{"conf_parts_listing_images"}   = $::lx_office_conf{features}->{parts_listing_images};
  $additional_params->{"conf_parts_show_image"}       = $::lx_office_conf{features}->{parts_show_image};

  if (%main::debug_options) {
    map { $additional_params->{'DEBUG_' . uc($_)} = $main::debug_options{$_} } keys %main::debug_options;
  }

  if ($main::auth && $main::auth->{RIGHTS} && $main::auth->{RIGHTS}->{$self->{login}}) {
    while (my ($key, $value) = each %{ $main::auth->{RIGHTS}->{$self->{login}} }) {
      $additional_params->{"AUTH_RIGHTS_" . uc($key)} = $value;
    }
  }

  $main::lxdebug->leave_sub();

  return $file;
}

sub parse_html_template {
  $main::lxdebug->enter_sub();

  my ($self, $file, $additional_params) = @_;

  $additional_params ||= { };

  my $real_file = $self->_prepare_html_template($file, $additional_params);
  my $template  = $self->template || $self->init_template;

  map { $additional_params->{$_} ||= $self->{$_} } keys %{ $self };

  my $output;
  $template->process($real_file, $additional_params, \$output) || die $template->error;

  $main::lxdebug->leave_sub();

  return $output;
}

sub init_template {
  my $self = shift;

  return if $self->template;

  return $self->template(Template->new({
     'INTERPOLATE'  => 0,
     'EVAL_PERL'    => 0,
     'ABSOLUTE'     => 1,
     'CACHE_SIZE'   => 0,
     'PLUGIN_BASE'  => 'SL::Template::Plugin',
     'INCLUDE_PATH' => '.:templates/webpages',
     'COMPILE_EXT'  => '.tcc',
     'COMPILE_DIR'  => $::lx_office_conf{paths}->{userspath} . '/templates-cache',
  })) || die;
}

sub template {
  my $self = shift;
  $self->{template_object} = shift if @_;
  return $self->{template_object};
}

sub show_generic_error {
  $main::lxdebug->enter_sub();

  my ($self, $error, %params) = @_;

  if ($self->{__ERROR_HANDLER}) {
    $self->{__ERROR_HANDLER}->($error);
    $main::lxdebug->leave_sub();
    return;
  }

  my $add_params = {
    'title_error' => $params{title},
    'label_error' => $error,
  };

  if ($params{action}) {
    my @vars;

    map { delete($self->{$_}); } qw(action);
    map { push @vars, { "name" => $_, "value" => $self->{$_} } if (!ref($self->{$_})); } keys %{ $self };

    $add_params->{SHOW_BUTTON}  = 1;
    $add_params->{BUTTON_LABEL} = $params{label} || $params{action};
    $add_params->{VARIABLES}    = \@vars;

  } elsif ($params{back_button}) {
    $add_params->{SHOW_BACK_BUTTON} = 1;
  }

  $self->{title} = $params{title} if $params{title};

  $self->header();
  print $self->parse_html_template("generic/error", $add_params);

  print STDERR "Error: $error\n";

  $main::lxdebug->leave_sub();

  ::end_of_request();
}

sub show_generic_information {
  $main::lxdebug->enter_sub();

  my ($self, $text, $title) = @_;

  my $add_params = {
    'title_information' => $title,
    'label_information' => $text,
  };

  $self->{title} = $title if ($title);

  $self->header();
  print $self->parse_html_template("generic/information", $add_params);

  $main::lxdebug->leave_sub();

  ::end_of_request();
}

# write Trigger JavaScript-Code ($qty = quantity of Triggers)
# changed it to accept an arbitrary number of triggers - sschoeling
sub write_trigger {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my $myconfig = shift;
  my $qty      = shift;

  # set dateform for jsscript
  # default
  my %dateformats = (
    "dd.mm.yy" => "%d.%m.%Y",
    "dd-mm-yy" => "%d-%m-%Y",
    "dd/mm/yy" => "%d/%m/%Y",
    "mm/dd/yy" => "%m/%d/%Y",
    "mm-dd-yy" => "%m-%d-%Y",
    "yyyy-mm-dd" => "%Y-%m-%d",
    );

  my $ifFormat = defined($dateformats{$myconfig->{"dateformat"}}) ?
    $dateformats{$myconfig->{"dateformat"}} : "%d.%m.%Y";

  my @triggers;
  while ($#_ >= 2) {
    push @triggers, qq|
       Calendar.setup(
      {
      inputField : "| . (shift) . qq|",
      ifFormat :"$ifFormat",
      align : "| .  (shift) . qq|",
      button : "| . (shift) . qq|"
      }
      );
       |;
  }
  my $jsscript = qq|
       <script type="text/javascript">
       <!--| . join("", @triggers) . qq|//-->
        </script>
        |;

  $main::lxdebug->leave_sub();

  return $jsscript;
}    #end sub write_trigger

sub redirect {
  $main::lxdebug->enter_sub();

  my ($self, $msg) = @_;

  if (!$self->{callback}) {
    $self->info($msg);

  } else {
    print $::form->redirect_header($self->{callback});
  }

  ::end_of_request();

  $main::lxdebug->leave_sub();
}

# sort of columns removed - empty sub
sub sort_columns {
  $main::lxdebug->enter_sub();

  my ($self, @columns) = @_;

  $main::lxdebug->leave_sub();

  return @columns;
}
#
sub format_amount {
  $main::lxdebug->enter_sub(2);

  my ($self, $myconfig, $amount, $places, $dash) = @_;

  if ($amount eq "") {
    $amount = 0;
  }

  # Hey watch out! The amount can be an exponential term like 1.13686837721616e-13

  my $neg = ($amount =~ s/^-//);
  my $exp = ($amount =~ m/[e]/) ? 1 : 0;

  if (defined($places) && ($places ne '')) {
    if (not $exp) {
      if ($places < 0) {
        $amount *= 1;
        $places *= -1;

        my ($actual_places) = ($amount =~ /\.(\d+)/);
        $actual_places = length($actual_places);
        $places = $actual_places > $places ? $actual_places : $places;
      }
    }
    $amount = $self->round_amount($amount, $places);
  }

  my @d = map { s/\d//g; reverse split // } my $tmp = $myconfig->{numberformat}; # get delim chars
  my @p = split(/\./, $amount); # split amount at decimal point

  $p[0] =~ s/\B(?=(...)*$)/$d[1]/g if $d[1]; # add 1,000 delimiters

  $amount = $p[0];
  $amount .= $d[0].$p[1].(0 x ($places - length $p[1])) if ($places || $p[1] ne '');

  $amount = do {
    ($dash =~ /-/)    ? ($neg ? "($amount)"                            : "$amount" )                              :
    ($dash =~ /DRCR/) ? ($neg ? "$amount " . $main::locale->text('DR') : "$amount " . $main::locale->text('CR') ) :
                        ($neg ? "-$amount"                             : "$amount" )                              ;
  };


  $main::lxdebug->leave_sub(2);
  return $amount;
}

sub format_amount_units {
  $main::lxdebug->enter_sub();

  my $self             = shift;
  my %params           = @_;

  my $myconfig         = \%main::myconfig;
  my $amount           = $params{amount} * 1;
  my $places           = $params{places};
  my $part_unit_name   = $params{part_unit};
  my $amount_unit_name = $params{amount_unit};
  my $conv_units       = $params{conv_units};
  my $max_places       = $params{max_places};

  if (!$part_unit_name) {
    $main::lxdebug->leave_sub();
    return '';
  }

  AM->retrieve_all_units();
  my $all_units        = $main::all_units;

  if (('' eq ref $conv_units) && ($conv_units =~ /convertible/)) {
    $conv_units = AM->convertible_units($all_units, $part_unit_name, $conv_units eq 'convertible_not_smaller');
  }

  if (!scalar @{ $conv_units }) {
    my $result = $self->format_amount($myconfig, $amount, $places, undef, $max_places) . " " . $part_unit_name;
    $main::lxdebug->leave_sub();
    return $result;
  }

  my $part_unit  = $all_units->{$part_unit_name};
  my $conv_unit  = ($amount_unit_name && ($amount_unit_name ne $part_unit_name)) ? $all_units->{$amount_unit_name} : $part_unit;

  $amount       *= $conv_unit->{factor};

  my @values;
  my $num;

  foreach my $unit (@$conv_units) {
    my $last = $unit->{name} eq $part_unit->{name};
    if (!$last) {
      $num     = int($amount / $unit->{factor});
      $amount -= $num * $unit->{factor};
    }

    if ($last ? $amount : $num) {
      push @values, { "unit"   => $unit->{name},
                      "amount" => $last ? $amount / $unit->{factor} : $num,
                      "places" => $last ? $places : 0 };
    }

    last if $last;
  }

  if (!@values) {
    push @values, { "unit"   => $part_unit_name,
                    "amount" => 0,
                    "places" => 0 };
  }

  my $result = join " ", map { $self->format_amount($myconfig, $_->{amount}, $_->{places}, undef, $max_places), $_->{unit} } @values;

  $main::lxdebug->leave_sub();

  return $result;
}

sub format_string {
  $main::lxdebug->enter_sub(2);

  my $self  = shift;
  my $input = shift;

  $input =~ s/(^|[^\#]) \#  (\d+)  /$1$_[$2 - 1]/gx;
  $input =~ s/(^|[^\#]) \#\{(\d+)\}/$1$_[$2 - 1]/gx;
  $input =~ s/\#\#/\#/g;

  $main::lxdebug->leave_sub(2);

  return $input;
}

#

sub parse_amount {
  $main::lxdebug->enter_sub(2);

  my ($self, $myconfig, $amount) = @_;

  if (   ($myconfig->{numberformat} eq '1.000,00')
      || ($myconfig->{numberformat} eq '1000,00')) {
    $amount =~ s/\.//g;
    $amount =~ s/,/\./;
  }

  if ($myconfig->{numberformat} eq "1'000.00") {
    $amount =~ s/\'//g;
  }

  $amount =~ s/,//g;

  $main::lxdebug->leave_sub(2);

  return ($amount * 1);
}

sub round_amount {
  $main::lxdebug->enter_sub(2);

  my ($self, $amount, $places) = @_;
  my $round_amount;

  # Rounding like "Kaufmannsrunden" (see http://de.wikipedia.org/wiki/Rundung )

  # Round amounts to eight places before rounding to the requested
  # number of places. This gets rid of errors due to internal floating
  # point representation.
  $amount       = $self->round_amount($amount, 8) if $places < 8;
  $amount       = $amount * (10**($places));
  $round_amount = int($amount + .5 * ($amount <=> 0)) / (10**($places));

  $main::lxdebug->leave_sub(2);

  return $round_amount;

}

sub parse_template {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig) = @_;
  my $out;

  local (*IN, *OUT);

  my $userspath = $::lx_office_conf{paths}->{userspath};

  $self->{"cwd"} = getcwd();
  $self->{"tmpdir"} = $self->{cwd} . "/${userspath}";

  my $ext_for_format;

  my $template_type;
  if ($self->{"format"} =~ /(opendocument|oasis)/i) {
    $template_type  = 'OpenDocument';
    $ext_for_format = $self->{"format"} =~ m/pdf/ ? 'pdf' : 'odt';

  } elsif ($self->{"format"} =~ /(postscript|pdf)/i) {
    $ENV{"TEXINPUTS"} = ".:" . getcwd() . "/" . $myconfig->{"templates"} . ":" . $ENV{"TEXINPUTS"};
    $template_type    = 'LaTeX';
    $ext_for_format   = 'pdf';

  } elsif (($self->{"format"} =~ /html/i) || (!$self->{"format"} && ($self->{"IN"} =~ /html$/i))) {
    $template_type  = 'HTML';
    $ext_for_format = 'html';

  } elsif (($self->{"format"} =~ /xml/i) || (!$self->{"format"} && ($self->{"IN"} =~ /xml$/i))) {
    $template_type  = 'XML';
    $ext_for_format = 'xml';

  } elsif ( $self->{"format"} =~ /elster(?:winston|taxbird)/i ) {
    $template_type = 'XML';

  } elsif ( $self->{"format"} =~ /excel/i ) {
    $template_type  = 'Excel';
    $ext_for_format = 'xls';

  } elsif ( defined $self->{'format'}) {
    $self->error("Outputformat not defined. This may be a future feature: $self->{'format'}");

  } elsif ( $self->{'format'} eq '' ) {
    $self->error("No Outputformat given: $self->{'format'}");

  } else { #Catch the rest
    $self->error("Outputformat not defined: $self->{'format'}");
  }

  my $template = SL::Template::create(type      => $template_type,
                                      file_name => $self->{IN},
                                      form      => $self,
                                      myconfig  => $myconfig,
                                      userspath => $userspath);

  # Copy the notes from the invoice/sales order etc. back to the variable "notes" because that is where most templates expect it to be.
  $self->{"notes"} = $self->{ $self->{"formname"} . "notes" };

  if (!$self->{employee_id}) {
    map { $self->{"employee_${_}"} = $myconfig->{$_}; } qw(email tel fax name signature company address businessnumber co_ustid taxnumber duns);
  }

  map { $self->{"${_}"} = $myconfig->{$_}; } qw(co_ustid);
  map { $self->{"myconfig_${_}"} = $myconfig->{$_} } grep { $_ ne 'dbpasswd' } keys %{ $myconfig };

  $self->{copies} = 1 if (($self->{copies} *= 1) <= 0);

  # OUT is used for the media, screen, printer, email
  # for postscript we store a copy in a temporary file
  my $fileid = time;
  my $prepend_userspath;

  if (!$self->{tmpfile}) {
    $self->{tmpfile}   = "${fileid}.$self->{IN}";
    $prepend_userspath = 1;
  }

  $prepend_userspath = 1 if substr($self->{tmpfile}, 0, length $userspath) eq $userspath;

  $self->{tmpfile} =~ s|.*/||;
  $self->{tmpfile} =~ s/[^a-zA-Z0-9\._\ \-]//g;
  $self->{tmpfile} = "$userspath/$self->{tmpfile}" if $prepend_userspath;

  if ($template->uses_temp_file() || $self->{media} eq 'email') {
    $out = $self->{OUT};
    $self->{OUT} = ">$self->{tmpfile}";
  }

  my $result;

  if ($self->{OUT}) {
    open OUT, "$self->{OUT}" or $self->error("$self->{OUT} : $!");
    $result = $template->parse(*OUT);
    close OUT;

  } else {
    $self->header;
    $result = $template->parse(*STDOUT);
  }

  if (!$result) {
    $self->cleanup();
    $self->error("$self->{IN} : " . $template->get_error());
  }

  if ($self->{media} eq 'file') {
    copy(join('/', $self->{cwd}, $userspath, $self->{tmpfile}), $out =~ m|^/| ? $out : join('/', $self->{cwd}, $out)) if $template->uses_temp_file;
    $self->cleanup;
    chdir("$self->{cwd}");

    $::lxdebug->leave_sub();

    return;
  }

  if ($template->uses_temp_file() || $self->{media} eq 'email') {

    if ($self->{media} eq 'email') {

      my $mail = new Mailer;

      map { $mail->{$_} = $self->{$_} }
        qw(cc bcc subject message version format);
      $mail->{charset} = $::lx_office_conf{system}->{dbcharset} || Common::DEFAULT_CHARSET;
      $mail->{to} = $self->{EMAIL_RECIPIENT} ? $self->{EMAIL_RECIPIENT} : $self->{email};
      $mail->{from}   = qq|"$myconfig->{name}" <$myconfig->{email}>|;
      $mail->{fileid} = "$fileid.";
      $myconfig->{signature} =~ s/\r//g;

      # if we send html or plain text inline
      if (($self->{format} eq 'html') && ($self->{sendmode} eq 'inline')) {
        $mail->{contenttype} = "text/html";

        $mail->{message}       =~ s/\r//g;
        $mail->{message}       =~ s/\n/<br>\n/g;
        $myconfig->{signature} =~ s/\n/<br>\n/g;
        $mail->{message} .= "<br>\n-- <br>\n$myconfig->{signature}\n<br>";

        open(IN, $self->{tmpfile})
          or $self->error($self->cleanup . "$self->{tmpfile} : $!");
        while (<IN>) {
          $mail->{message} .= $_;
        }

        close(IN);

      } else {

        if (!$self->{"do_not_attach"}) {
          my $attachment_name  =  $self->{attachment_filename} || $self->{tmpfile};
          $attachment_name     =~ s/\.(.+?)$/.${ext_for_format}/ if ($ext_for_format);
          $mail->{attachments} =  [{ "filename" => $self->{tmpfile},
                                     "name"     => $attachment_name }];
        }

        $mail->{message}  =~ s/\r//g;
        $mail->{message} .=  "\n-- \n$myconfig->{signature}";

      }

      my $err = $mail->send();
      $self->error($self->cleanup . "$err") if ($err);

    } else {

      $self->{OUT} = $out;

      my $numbytes = (-s $self->{tmpfile});
      open(IN, $self->{tmpfile})
        or $self->error($self->cleanup . "$self->{tmpfile} : $!");
      binmode IN;

      $self->{copies} = 1 unless $self->{media} eq 'printer';

      chdir("$self->{cwd}");
      #print(STDERR "Kopien $self->{copies}\n");
      #print(STDERR "OUT $self->{OUT}\n");
      for my $i (1 .. $self->{copies}) {
        if ($self->{OUT}) {
          open OUT, $self->{OUT} or $self->error($self->cleanup . "$self->{OUT} : $!");
          print OUT while <IN>;
          close OUT;
          seek IN, 0, 0;

        } else {
          $self->{attachment_filename} = ($self->{attachment_filename})
                                       ? $self->{attachment_filename}
                                       : $self->generate_attachment_filename();

          # launch application
          print qq|Content-Type: | . $template->get_mime_type() . qq|
Content-Disposition: attachment; filename="$self->{attachment_filename}"
Content-Length: $numbytes

|;

          $::locale->with_raw_io(\*STDOUT, sub { print while <IN> });
        }
      }

      close(IN);
    }

  }

  $self->cleanup;

  chdir("$self->{cwd}");
  $main::lxdebug->leave_sub();
}

sub get_formname_translation {
  $main::lxdebug->enter_sub();
  my ($self, $formname) = @_;

  $formname ||= $self->{formname};

  my %formname_translations = (
    bin_list                => $main::locale->text('Bin List'),
    credit_note             => $main::locale->text('Credit Note'),
    invoice                 => $main::locale->text('Invoice'),
    pick_list               => $main::locale->text('Pick List'),
    proforma                => $main::locale->text('Proforma Invoice'),
    purchase_order          => $main::locale->text('Purchase Order'),
    request_quotation       => $main::locale->text('RFQ'),
    sales_order             => $main::locale->text('Confirmation'),
    sales_quotation         => $main::locale->text('Quotation'),
    storno_invoice          => $main::locale->text('Storno Invoice'),
    sales_delivery_order    => $main::locale->text('Delivery Order'),
    purchase_delivery_order => $main::locale->text('Delivery Order'),
    dunning                 => $main::locale->text('Dunning'),
  );

  $main::lxdebug->leave_sub();
  return $formname_translations{$formname}
}

sub get_number_prefix_for_type {
  $main::lxdebug->enter_sub();
  my ($self) = @_;

  my $prefix =
      (first { $self->{type} eq $_ } qw(invoice credit_note)) ? 'inv'
    : ($self->{type} =~ /_quotation$/)                        ? 'quo'
    : ($self->{type} =~ /_delivery_order$/)                   ? 'do'
    :                                                           'ord';

  $main::lxdebug->leave_sub();
  return $prefix;
}

sub get_extension_for_format {
  $main::lxdebug->enter_sub();
  my ($self)    = @_;

  my $extension = $self->{format} =~ /pdf/i          ? ".pdf"
                : $self->{format} =~ /postscript/i   ? ".ps"
                : $self->{format} =~ /opendocument/i ? ".odt"
                : $self->{format} =~ /excel/i        ? ".xls"
                : $self->{format} =~ /html/i         ? ".html"
                :                                      "";

  $main::lxdebug->leave_sub();
  return $extension;
}

sub generate_attachment_filename {
  $main::lxdebug->enter_sub();
  my ($self) = @_;

  my $attachment_filename = $main::locale->unquote_special_chars('HTML', $self->get_formname_translation());
  my $prefix              = $self->get_number_prefix_for_type();

  if ($self->{preview} && (first { $self->{type} eq $_ } qw(invoice credit_note))) {
    $attachment_filename .= ' (' . $main::locale->text('Preview') . ')' . $self->get_extension_for_format();

  } elsif ($attachment_filename && $self->{"${prefix}number"}) {
    $attachment_filename .=  "_" . $self->{"${prefix}number"} . $self->get_extension_for_format();

  } else {
    $attachment_filename = "";
  }

  $attachment_filename =  $main::locale->quote_special_chars('filenames', $attachment_filename);
  $attachment_filename =~ s|[\s/\\]+|_|g;

  $main::lxdebug->leave_sub();
  return $attachment_filename;
}

sub generate_email_subject {
  $main::lxdebug->enter_sub();
  my ($self) = @_;

  my $subject = $main::locale->unquote_special_chars('HTML', $self->get_formname_translation());
  my $prefix  = $self->get_number_prefix_for_type();

  if ($subject && $self->{"${prefix}number"}) {
    $subject .= " " . $self->{"${prefix}number"}
  }

  $main::lxdebug->leave_sub();
  return $subject;
}

sub cleanup {
  $main::lxdebug->enter_sub();

  my $self = shift;

  chdir("$self->{tmpdir}");

  my @err = ();
  if (-f "$self->{tmpfile}.err") {
    open(FH, "$self->{tmpfile}.err");
    @err = <FH>;
    close(FH);
  }

  if ($self->{tmpfile} && !($::lx_office_conf{debug} && $::lx_office_conf{debug}->{keep_temp_files})) {
    $self->{tmpfile} =~ s|.*/||g;
    # strip extension
    $self->{tmpfile} =~ s/\.\w+$//g;
    my $tmpfile = $self->{tmpfile};
    unlink(<$tmpfile.*>);
  }

  chdir("$self->{cwd}");

  $main::lxdebug->leave_sub();

  return "@err";
}

sub datetonum {
  $main::lxdebug->enter_sub();

  my ($self, $date, $myconfig) = @_;
  my ($yy, $mm, $dd);

  if ($date && $date =~ /\D/) {

    if ($myconfig->{dateformat} =~ /^yy/) {
      ($yy, $mm, $dd) = split /\D/, $date;
    }
    if ($myconfig->{dateformat} =~ /^mm/) {
      ($mm, $dd, $yy) = split /\D/, $date;
    }
    if ($myconfig->{dateformat} =~ /^dd/) {
      ($dd, $mm, $yy) = split /\D/, $date;
    }

    $dd *= 1;
    $mm *= 1;
    $yy = ($yy < 70) ? $yy + 2000 : $yy;
    $yy = ($yy >= 70 && $yy <= 99) ? $yy + 1900 : $yy;

    $dd = "0$dd" if ($dd < 10);
    $mm = "0$mm" if ($mm < 10);

    $date = "$yy$mm$dd";
  }

  $main::lxdebug->leave_sub();

  return $date;
}

# Database routines used throughout

sub _dbconnect_options {
  my $self    = shift;
  my $options = { pg_enable_utf8 => $::locale->is_utf8,
                  @_ };

  return $options;
}

sub dbconnect {
  $main::lxdebug->enter_sub(2);

  my ($self, $myconfig) = @_;

  # connect to database
  my $dbh = SL::DBConnect->connect($myconfig->{dbconnect}, $myconfig->{dbuser}, $myconfig->{dbpasswd}, $self->_dbconnect_options)
    or $self->dberror;

  # set db options
  if ($myconfig->{dboptions}) {
    $dbh->do($myconfig->{dboptions}) || $self->dberror($myconfig->{dboptions});
  }

  $main::lxdebug->leave_sub(2);

  return $dbh;
}

sub dbconnect_noauto {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig) = @_;

  # connect to database
  my $dbh = SL::DBConnect->connect($myconfig->{dbconnect}, $myconfig->{dbuser}, $myconfig->{dbpasswd}, $self->_dbconnect_options(AutoCommit => 0))
    or $self->dberror;

  # set db options
  if ($myconfig->{dboptions}) {
    $dbh->do($myconfig->{dboptions}) || $self->dberror($myconfig->{dboptions});
  }

  $main::lxdebug->leave_sub();

  return $dbh;
}

sub get_standard_dbh {
  $main::lxdebug->enter_sub(2);

  my $self     = shift;
  my $myconfig = shift || \%::myconfig;

  if ($standard_dbh && !$standard_dbh->{Active}) {
    $main::lxdebug->message(LXDebug->INFO(), "get_standard_dbh: \$standard_dbh is defined but not Active anymore");
    undef $standard_dbh;
  }

  $standard_dbh ||= $self->dbconnect_noauto($myconfig);

  $main::lxdebug->leave_sub(2);

  return $standard_dbh;
}

sub date_closed {
  $main::lxdebug->enter_sub();

  my ($self, $date, $myconfig) = @_;
  my $dbh = $self->dbconnect($myconfig);

  my $query = "SELECT 1 FROM defaults WHERE ? < closedto";
  my $sth = prepare_execute_query($self, $dbh, $query, $date);
  my ($closed) = $sth->fetchrow_array;

  $main::lxdebug->leave_sub();

  return $closed;
}

sub update_balance {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $table, $field, $where, $value, @values) = @_;

  # if we have a value, go do it
  if ($value != 0) {

    # retrieve balance from table
    my $query = "SELECT $field FROM $table WHERE $where FOR UPDATE";
    my $sth = prepare_execute_query($self, $dbh, $query, @values);
    my ($balance) = $sth->fetchrow_array;
    $sth->finish;

    $balance += $value;

    # update balance
    $query = "UPDATE $table SET $field = $balance WHERE $where";
    do_query($self, $dbh, $query, @values);
  }
  $main::lxdebug->leave_sub();
}

sub update_exchangerate {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $curr, $transdate, $buy, $sell) = @_;
  my ($query);
  # some sanity check for currency
  if ($curr eq '') {
    $main::lxdebug->leave_sub();
    return;
  }
  $query = qq|SELECT curr FROM defaults|;

  my ($currency) = selectrow_query($self, $dbh, $query);
  my ($defaultcurrency) = split m/:/, $currency;


  if ($curr eq $defaultcurrency) {
    $main::lxdebug->leave_sub();
    return;
  }

  $query = qq|SELECT e.curr FROM exchangerate e
                 WHERE e.curr = ? AND e.transdate = ?
                 FOR UPDATE|;
  my $sth = prepare_execute_query($self, $dbh, $query, $curr, $transdate);

  if ($buy == 0) {
    $buy = "";
  }
  if ($sell == 0) {
    $sell = "";
  }

  $buy = conv_i($buy, "NULL");
  $sell = conv_i($sell, "NULL");

  my $set;
  if ($buy != 0 && $sell != 0) {
    $set = "buy = $buy, sell = $sell";
  } elsif ($buy != 0) {
    $set = "buy = $buy";
  } elsif ($sell != 0) {
    $set = "sell = $sell";
  }

  if ($sth->fetchrow_array) {
    $query = qq|UPDATE exchangerate
                SET $set
                WHERE curr = ?
                AND transdate = ?|;

  } else {
    $query = qq|INSERT INTO exchangerate (curr, buy, sell, transdate)
                VALUES (?, $buy, $sell, ?)|;
  }
  $sth->finish;
  do_query($self, $dbh, $query, $curr, $transdate);

  $main::lxdebug->leave_sub();
}

sub save_exchangerate {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $currency, $transdate, $rate, $fld) = @_;

  my $dbh = $self->dbconnect($myconfig);

  my ($buy, $sell);

  $buy  = $rate if $fld eq 'buy';
  $sell = $rate if $fld eq 'sell';


  $self->update_exchangerate($dbh, $currency, $transdate, $buy, $sell);


  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub get_exchangerate {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $curr, $transdate, $fld) = @_;
  my ($query);

  unless ($transdate) {
    $main::lxdebug->leave_sub();
    return 1;
  }

  $query = qq|SELECT curr FROM defaults|;

  my ($currency) = selectrow_query($self, $dbh, $query);
  my ($defaultcurrency) = split m/:/, $currency;

  if ($currency eq $defaultcurrency) {
    $main::lxdebug->leave_sub();
    return 1;
  }

  $query = qq|SELECT e.$fld FROM exchangerate e
                 WHERE e.curr = ? AND e.transdate = ?|;
  my ($exchangerate) = selectrow_query($self, $dbh, $query, $curr, $transdate);



  $main::lxdebug->leave_sub();

  return $exchangerate;
}

sub check_exchangerate {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $currency, $transdate, $fld) = @_;

  if ($fld !~/^buy|sell$/) {
    $self->error('Fatal: check_exchangerate called with invalid buy/sell argument');
  }

  unless ($transdate) {
    $main::lxdebug->leave_sub();
    return "";
  }

  my ($defaultcurrency) = $self->get_default_currency($myconfig);

  if ($currency eq $defaultcurrency) {
    $main::lxdebug->leave_sub();
    return 1;
  }

  my $dbh   = $self->get_standard_dbh($myconfig);
  my $query = qq|SELECT e.$fld FROM exchangerate e
                 WHERE e.curr = ? AND e.transdate = ?|;

  my ($exchangerate) = selectrow_query($self, $dbh, $query, $currency, $transdate);

  $main::lxdebug->leave_sub();

  return $exchangerate;
}

sub get_all_currencies {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my $myconfig = shift || \%::myconfig;
  my $dbh      = $self->get_standard_dbh($myconfig);

  my $query = qq|SELECT curr FROM defaults|;

  my ($curr)     = selectrow_query($self, $dbh, $query);
  my @currencies = grep { $_ } map { s/\s//g; $_ } split m/:/, $curr;

  $main::lxdebug->leave_sub();

  return @currencies;
}

sub get_default_currency {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig) = @_;
  my @currencies        = $self->get_all_currencies($myconfig);

  $main::lxdebug->leave_sub();

  return $currencies[0];
}

sub set_payment_options {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $transdate) = @_;

  return $main::lxdebug->leave_sub() unless ($self->{payment_id});

  my $dbh = $self->get_standard_dbh($myconfig);

  my $query =
    qq|SELECT p.terms_netto, p.terms_skonto, p.percent_skonto, p.description_long | .
    qq|FROM payment_terms p | .
    qq|WHERE p.id = ?|;

  ($self->{terms_netto}, $self->{terms_skonto}, $self->{percent_skonto},
   $self->{payment_terms}) =
     selectrow_query($self, $dbh, $query, $self->{payment_id});

  if ($transdate eq "") {
    if ($self->{invdate}) {
      $transdate = $self->{invdate};
    } else {
      $transdate = $self->{transdate};
    }
  }

  $query =
    qq|SELECT ?::date + ?::integer AS netto_date, ?::date + ?::integer AS skonto_date | .
    qq|FROM payment_terms|;
  ($self->{netto_date}, $self->{skonto_date}) =
    selectrow_query($self, $dbh, $query, $transdate, $self->{terms_netto}, $transdate, $self->{terms_skonto});

  my ($invtotal, $total);
  my (%amounts, %formatted_amounts);

  if ($self->{type} =~ /_order$/) {
    $amounts{invtotal} = $self->{ordtotal};
    $amounts{total}    = $self->{ordtotal};

  } elsif ($self->{type} =~ /_quotation$/) {
    $amounts{invtotal} = $self->{quototal};
    $amounts{total}    = $self->{quototal};

  } else {
    $amounts{invtotal} = $self->{invtotal};
    $amounts{total}    = $self->{total};
  }
  $amounts{skonto_in_percent} = 100.0 * $self->{percent_skonto};

  map { $amounts{$_} = $self->parse_amount($myconfig, $amounts{$_}) } keys %amounts;

  $amounts{skonto_amount}      = $amounts{invtotal} * $self->{percent_skonto};
  $amounts{invtotal_wo_skonto} = $amounts{invtotal} * (1 - $self->{percent_skonto});
  $amounts{total_wo_skonto}    = $amounts{total}    * (1 - $self->{percent_skonto});

  foreach (keys %amounts) {
    $amounts{$_}           = $self->round_amount($amounts{$_}, 2);
    $formatted_amounts{$_} = $self->format_amount($myconfig, $amounts{$_}, 2);
  }

  if ($self->{"language_id"}) {
    $query =
      qq|SELECT t.description_long, l.output_numberformat, l.output_dateformat, l.output_longdates | .
      qq|FROM translation_payment_terms t | .
      qq|LEFT JOIN language l ON t.language_id = l.id | .
      qq|WHERE (t.language_id = ?) AND (t.payment_terms_id = ?)|;
    my ($description_long, $output_numberformat, $output_dateformat,
      $output_longdates) =
      selectrow_query($self, $dbh, $query,
                      $self->{"language_id"}, $self->{"payment_id"});

    $self->{payment_terms} = $description_long if ($description_long);

    if ($output_dateformat) {
      foreach my $key (qw(netto_date skonto_date)) {
        $self->{$key} =
          $main::locale->reformat_date($myconfig, $self->{$key},
                                       $output_dateformat,
                                       $output_longdates);
      }
    }

    if ($output_numberformat &&
        ($output_numberformat ne $myconfig->{"numberformat"})) {
      my $saved_numberformat = $myconfig->{"numberformat"};
      $myconfig->{"numberformat"} = $output_numberformat;
      map { $formatted_amounts{$_} = $self->format_amount($myconfig, $amounts{$_}) } keys %amounts;
      $myconfig->{"numberformat"} = $saved_numberformat;
    }
  }

  $self->{payment_terms} =~ s/<%netto_date%>/$self->{netto_date}/g;
  $self->{payment_terms} =~ s/<%skonto_date%>/$self->{skonto_date}/g;
  $self->{payment_terms} =~ s/<%currency%>/$self->{currency}/g;
  $self->{payment_terms} =~ s/<%terms_netto%>/$self->{terms_netto}/g;
  $self->{payment_terms} =~ s/<%account_number%>/$self->{account_number}/g;
  $self->{payment_terms} =~ s/<%bank%>/$self->{bank}/g;
  $self->{payment_terms} =~ s/<%bank_code%>/$self->{bank_code}/g;

  map { $self->{payment_terms} =~ s/<%${_}%>/$formatted_amounts{$_}/g; } keys %formatted_amounts;

  $self->{skonto_in_percent} = $formatted_amounts{skonto_in_percent};

  $main::lxdebug->leave_sub();

}

sub get_template_language {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig) = @_;

  my $template_code = "";

  if ($self->{language_id}) {
    my $dbh = $self->get_standard_dbh($myconfig);
    my $query = qq|SELECT template_code FROM language WHERE id = ?|;
    ($template_code) = selectrow_query($self, $dbh, $query, $self->{language_id});
  }

  $main::lxdebug->leave_sub();

  return $template_code;
}

sub get_printer_code {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig) = @_;

  my $template_code = "";

  if ($self->{printer_id}) {
    my $dbh = $self->get_standard_dbh($myconfig);
    my $query = qq|SELECT template_code, printer_command FROM printers WHERE id = ?|;
    ($template_code, $self->{printer_command}) = selectrow_query($self, $dbh, $query, $self->{printer_id});
  }

  $main::lxdebug->leave_sub();

  return $template_code;
}

sub get_shipto {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig) = @_;

  my $template_code = "";

  if ($self->{shipto_id}) {
    my $dbh = $self->get_standard_dbh($myconfig);
    my $query = qq|SELECT * FROM shipto WHERE shipto_id = ?|;
    my $ref = selectfirst_hashref_query($self, $dbh, $query, $self->{shipto_id});
    map({ $self->{$_} = $ref->{$_} } keys(%$ref));
  }

  $main::lxdebug->leave_sub();
}

sub add_shipto {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $id, $module) = @_;

  my $shipto;
  my @values;

  foreach my $item (qw(name department_1 department_2 street zipcode city country
                       contact cp_gender phone fax email)) {
    if ($self->{"shipto$item"}) {
      $shipto = 1 if ($self->{$item} ne $self->{"shipto$item"});
    }
    push(@values, $self->{"shipto${item}"});
  }

  if ($shipto) {
    if ($self->{shipto_id}) {
      my $query = qq|UPDATE shipto set
                       shiptoname = ?,
                       shiptodepartment_1 = ?,
                       shiptodepartment_2 = ?,
                       shiptostreet = ?,
                       shiptozipcode = ?,
                       shiptocity = ?,
                       shiptocountry = ?,
                       shiptocontact = ?,
                       shiptocp_gender = ?,
                       shiptophone = ?,
                       shiptofax = ?,
                       shiptoemail = ?
                     WHERE shipto_id = ?|;
      do_query($self, $dbh, $query, @values, $self->{shipto_id});
    } else {
      my $query = qq|SELECT * FROM shipto
                     WHERE shiptoname = ? AND
                       shiptodepartment_1 = ? AND
                       shiptodepartment_2 = ? AND
                       shiptostreet = ? AND
                       shiptozipcode = ? AND
                       shiptocity = ? AND
                       shiptocountry = ? AND
                       shiptocontact = ? AND
                       shiptocp_gender = ? AND
                       shiptophone = ? AND
                       shiptofax = ? AND
                       shiptoemail = ? AND
                       module = ? AND
                       trans_id = ?|;
      my $insert_check = selectfirst_hashref_query($self, $dbh, $query, @values, $module, $id);
      if(!$insert_check){
        $query =
          qq|INSERT INTO shipto (trans_id, shiptoname, shiptodepartment_1, shiptodepartment_2,
                                 shiptostreet, shiptozipcode, shiptocity, shiptocountry,
                                 shiptocontact, shiptocp_gender, shiptophone, shiptofax, shiptoemail, module)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)|;
        do_query($self, $dbh, $query, $id, @values, $module);
      }
    }
  }

  $main::lxdebug->leave_sub();
}

sub get_employee {
  $main::lxdebug->enter_sub();

  my ($self, $dbh) = @_;

  $dbh ||= $self->get_standard_dbh(\%main::myconfig);

  my $query = qq|SELECT id, name FROM employee WHERE login = ?|;
  ($self->{"employee_id"}, $self->{"employee"}) = selectrow_query($self, $dbh, $query, $self->{login});
  $self->{"employee_id"} *= 1;

  $main::lxdebug->leave_sub();
}

sub get_employee_data {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my %params   = @_;

  Common::check_params(\%params, qw(prefix));
  Common::check_params_x(\%params, qw(id));

  if (!$params{id}) {
    $main::lxdebug->leave_sub();
    return;
  }

  my $myconfig = \%main::myconfig;
  my $dbh      = $params{dbh} || $self->get_standard_dbh($myconfig);

  my ($login)  = selectrow_query($self, $dbh, qq|SELECT login FROM employee WHERE id = ?|, conv_i($params{id}));

  if ($login) {
    my $user = User->new($login);
    map { $self->{$params{prefix} . "_${_}"} = $user->{$_}; } qw(address businessnumber co_ustid company duns email fax name signature taxnumber tel);

    $self->{$params{prefix} . '_login'}   = $login;
    $self->{$params{prefix} . '_name'}  ||= $login;
  }

  $main::lxdebug->leave_sub();
}

sub get_duedate {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $reference_date) = @_;

  $reference_date = $reference_date ? conv_dateq($reference_date) . '::DATE' : 'current_date';

  my $dbh         = $self->get_standard_dbh($myconfig);
  my $query       = qq|SELECT ${reference_date} + terms_netto FROM payment_terms WHERE id = ?|;
  my ($duedate)   = selectrow_query($self, $dbh, $query, $self->{payment_id});

  $main::lxdebug->leave_sub();

  return $duedate;
}

sub _get_contacts {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $id, $key) = @_;

  $key = "all_contacts" unless ($key);

  if (!$id) {
    $self->{$key} = [];
    $main::lxdebug->leave_sub();
    return;
  }

  my $query =
    qq|SELECT cp_id, cp_cv_id, cp_name, cp_givenname, cp_abteilung | .
    qq|FROM contacts | .
    qq|WHERE cp_cv_id = ? | .
    qq|ORDER BY lower(cp_name)|;

  $self->{$key} = selectall_hashref_query($self, $dbh, $query, $id);

  $main::lxdebug->leave_sub();
}

sub _get_projects {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $key) = @_;

  my ($all, $old_id, $where, @values);

  if (ref($key) eq "HASH") {
    my $params = $key;

    $key = "ALL_PROJECTS";

    foreach my $p (keys(%{$params})) {
      if ($p eq "all") {
        $all = $params->{$p};
      } elsif ($p eq "old_id") {
        $old_id = $params->{$p};
      } elsif ($p eq "key") {
        $key = $params->{$p};
      }
    }
  }

  if (!$all) {
    $where = "WHERE active ";
    if ($old_id) {
      if (ref($old_id) eq "ARRAY") {
        my @ids = grep({ $_ } @{$old_id});
        if (@ids) {
          $where .= " OR id IN (" . join(",", map({ "?" } @ids)) . ") ";
          push(@values, @ids);
        }
      } else {
        $where .= " OR (id = ?) ";
        push(@values, $old_id);
      }
    }
  }

  my $query =
    qq|SELECT id, projectnumber, description, active | .
    qq|FROM project | .
    $where .
    qq|ORDER BY lower(projectnumber)|;

  $self->{$key} = selectall_hashref_query($self, $dbh, $query, @values);

  $main::lxdebug->leave_sub();
}

sub _get_shipto {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $vc_id, $key) = @_;

  $key = "all_shipto" unless ($key);

  if ($vc_id) {
    # get shipping addresses
    my $query = qq|SELECT * FROM shipto WHERE trans_id = ?|;

    $self->{$key} = selectall_hashref_query($self, $dbh, $query, $vc_id);

  } else {
    $self->{$key} = [];
  }

  $main::lxdebug->leave_sub();
}

sub _get_printers {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $key) = @_;

  $key = "all_printers" unless ($key);

  my $query = qq|SELECT id, printer_description, printer_command, template_code FROM printers|;

  $self->{$key} = selectall_hashref_query($self, $dbh, $query);

  $main::lxdebug->leave_sub();
}

sub _get_charts {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $params) = @_;
  my ($key);

  $key = $params->{key};
  $key = "all_charts" unless ($key);

  my $transdate = quote_db_date($params->{transdate});

  my $query =
    qq|SELECT c.id, c.accno, c.description, c.link, c.charttype, tk.taxkey_id, tk.tax_id | .
    qq|FROM chart c | .
    qq|LEFT JOIN taxkeys tk ON | .
    qq|(tk.id = (SELECT id FROM taxkeys | .
    qq|          WHERE taxkeys.chart_id = c.id AND startdate <= $transdate | .
    qq|          ORDER BY startdate DESC LIMIT 1)) | .
    qq|ORDER BY c.accno|;

  $self->{$key} = selectall_hashref_query($self, $dbh, $query);

  $main::lxdebug->leave_sub();
}

sub _get_taxcharts {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $params) = @_;

  my $key = "all_taxcharts";
  my @where;

  if (ref $params eq 'HASH') {
    $key = $params->{key} if ($params->{key});
    if ($params->{module} eq 'AR') {
      push @where, 'taxkey NOT IN (8, 9, 18, 19)';

    } elsif ($params->{module} eq 'AP') {
      push @where, 'taxkey NOT IN (1, 2, 3, 12, 13)';
    }

  } elsif ($params) {
    $key = $params;
  }

  my $where = ' WHERE ' . join(' AND ', map { "($_)" } @where) if (@where);

  my $query = qq|SELECT * FROM tax $where ORDER BY taxkey|;

  $self->{$key} = selectall_hashref_query($self, $dbh, $query);

  $main::lxdebug->leave_sub();
}

sub _get_taxzones {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $key) = @_;

  $key = "all_taxzones" unless ($key);

  my $query = qq|SELECT * FROM tax_zones ORDER BY id|;

  $self->{$key} = selectall_hashref_query($self, $dbh, $query);

  $main::lxdebug->leave_sub();
}

sub _get_employees {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $default_key, $key) = @_;

  $key = $default_key unless ($key);
  $self->{$key} = selectall_hashref_query($self, $dbh, qq|SELECT * FROM employee ORDER BY lower(name)|);

  $main::lxdebug->leave_sub();
}

sub _get_business_types {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $key) = @_;

  my $options       = ref $key eq 'HASH' ? $key : { key => $key };
  $options->{key} ||= "all_business_types";
  my $where         = '';

  if (exists $options->{salesman}) {
    $where = 'WHERE ' . ($options->{salesman} ? '' : 'NOT ') . 'COALESCE(salesman)';
  }

  $self->{ $options->{key} } = selectall_hashref_query($self, $dbh, qq|SELECT DISTINCT ON (description) description as id, description, 
                                                                       customernumberinit, salesman, discount 
                                                                       FROM business $where ORDER BY description|);

  $main::lxdebug->leave_sub();
}

sub _get_languages {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $key) = @_;

  $key = "all_languages" unless ($key);

  my $query = qq|SELECT * FROM language ORDER BY id|;

  $self->{$key} = selectall_hashref_query($self, $dbh, $query);

  $main::lxdebug->leave_sub();
}

sub _get_dunning_configs {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $key) = @_;

  $key = "all_dunning_configs" unless ($key);

  my $query = qq|SELECT * FROM dunning_config ORDER BY dunning_level|;

  $self->{$key} = selectall_hashref_query($self, $dbh, $query);

  $main::lxdebug->leave_sub();
}

sub _get_currencies {
$main::lxdebug->enter_sub();

  my ($self, $dbh, $key) = @_;

  $key = "all_currencies" unless ($key);

  my $query = qq|SELECT curr AS currency FROM defaults|;

  $self->{$key} = [split(/\:/ , selectfirst_hashref_query($self, $dbh, $query)->{currency})];

  $main::lxdebug->leave_sub();
}

sub _get_payments {
$main::lxdebug->enter_sub();

  my ($self, $dbh, $key) = @_;

  $key = "all_payments" unless ($key);

  my $query = qq|SELECT * FROM payment_terms ORDER BY id|;

  $self->{$key} = selectall_hashref_query($self, $dbh, $query);

  $main::lxdebug->leave_sub();
}

sub _get_customers {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $key) = @_;

  my $options        = ref $key eq 'HASH' ? $key : { key => $key };
  $options->{key}  ||= "all_customers";
  my $limit_clause   = "LIMIT $options->{limit}" if $options->{limit};

  my @where;
  push @where, qq|business_id IN (SELECT description AS id FROM business WHERE salesman)| if  $options->{business_is_salesman};
  push @where, qq|NOT obsolete|                                            if !$options->{with_obsolete};
  my $where_str = @where ? "WHERE " . join(" AND ", map { "($_)" } @where) : '';

  my $query = qq|SELECT * FROM customer $where_str ORDER BY name $limit_clause|;
  $self->{ $options->{key} } = selectall_hashref_query($self, $dbh, $query);

  $main::lxdebug->leave_sub();
}

sub _get_vendors {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $key) = @_;

  $key = "all_vendors" unless ($key);

  my $query = qq|SELECT * FROM vendor WHERE NOT obsolete ORDER BY name|;

  $self->{$key} = selectall_hashref_query($self, $dbh, $query);

  $main::lxdebug->leave_sub();
}

sub _get_departments {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $key) = @_;

  $key = "all_departments" unless ($key);

  my $query = qq|SELECT * FROM department ORDER BY description|;

  $self->{$key} = selectall_hashref_query($self, $dbh, $query);

  $main::lxdebug->leave_sub();
}

sub _get_warehouses {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $param) = @_;

  my ($key, $bins_key);

  if ('' eq ref $param) {
    $key = $param;

  } else {
    $key      = $param->{key};
    $bins_key = $param->{bins};
  }

  my $query = qq|SELECT w.* FROM warehouse w
                 WHERE (NOT w.invalid) AND
                   ((SELECT COUNT(b.*) FROM bin b WHERE b.warehouse_id = w.id) > 0)
                 ORDER BY w.sortkey|;

  $self->{$key} = selectall_hashref_query($self, $dbh, $query);

  if ($bins_key) {
    $query = qq|SELECT id, description FROM bin WHERE warehouse_id = ?
                ORDER BY description|;
    my $sth = prepare_query($self, $dbh, $query);

    foreach my $warehouse (@{ $self->{$key} }) {
      do_statement($self, $sth, $query, $warehouse->{id});
      $warehouse->{$bins_key} = [];

      while (my $ref = $sth->fetchrow_hashref()) {
        push @{ $warehouse->{$bins_key} }, $ref;
      }
    }
    $sth->finish();
  }

  $main::lxdebug->leave_sub();
}

sub _get_simple {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $table, $key, $sortkey) = @_;

  my $query  = qq|SELECT * FROM $table|;
  $query    .= qq| ORDER BY $sortkey| if ($sortkey);

  $self->{$key} = selectall_hashref_query($self, $dbh, $query);

  $main::lxdebug->leave_sub();
}

#sub _get_groups {
#  $main::lxdebug->enter_sub();
#
#  my ($self, $dbh, $key) = @_;
#
#  $key ||= "all_groups";
#
#  my $groups = $main::auth->read_groups();
#
#  $self->{$key} = selectall_hashref_query($self, $dbh, $query);
#
#  $main::lxdebug->leave_sub();
#}

sub get_lists {
  $main::lxdebug->enter_sub();

  my $self = shift;
  my %params = @_;

  my $dbh = $self->get_standard_dbh(\%main::myconfig);
  my ($sth, $query, $ref);

  my $vc = $self->{"vc"} eq "customer" ? "customer" : "vendor";
  my $vc_id = $self->{"${vc}_id"};

  if ($params{"contacts"}) {
    $self->_get_contacts($dbh, $vc_id, $params{"contacts"});
  }

  if ($params{"shipto"}) {
    $self->_get_shipto($dbh, $vc_id, $params{"shipto"});
  }

  if ($params{"projects"} || $params{"all_projects"}) {
    $self->_get_projects($dbh, $params{"all_projects"} ?
                         $params{"all_projects"} : $params{"projects"},
                         $params{"all_projects"} ? 1 : 0);
  }

  if ($params{"printers"}) {
    $self->_get_printers($dbh, $params{"printers"});
  }

  if ($params{"languages"}) {
    $self->_get_languages($dbh, $params{"languages"});
  }

  if ($params{"charts"}) {
    $self->_get_charts($dbh, $params{"charts"});
  }

  if ($params{"taxcharts"}) {
    $self->_get_taxcharts($dbh, $params{"taxcharts"});
  }

  if ($params{"taxzones"}) {
    $self->_get_taxzones($dbh, $params{"taxzones"});
  }

  if ($params{"employees"}) {
    $self->_get_employees($dbh, "all_employees", $params{"employees"});
  }

  if ($params{"salesmen"}) {
    $self->_get_employees($dbh, "all_salesmen", $params{"salesmen"});
  }

  if ($params{"business_types"}) {
    $self->_get_business_types($dbh, $params{"business_types"});
  }

  if ($params{"dunning_configs"}) {
    $self->_get_dunning_configs($dbh, $params{"dunning_configs"});
  }

  if($params{"currencies"}) {
    $self->_get_currencies($dbh, $params{"currencies"});
  }

  if($params{"customers"}) {
    $self->_get_customers($dbh, $params{"customers"});
  }

  if($params{"vendors"}) {
    if (ref $params{"vendors"} eq 'HASH') {
      $self->_get_vendors($dbh, $params{"vendors"}{key}, $params{"vendors"}{limit});
    } else {
      $self->_get_vendors($dbh, $params{"vendors"});
    }
  }

  if($params{"payments"}) {
    $self->_get_payments($dbh, $params{"payments"});
  }

  if($params{"departments"}) {
    $self->_get_departments($dbh, $params{"departments"});
  }

  if ($params{price_factors}) {
    $self->_get_simple($dbh, 'price_factors', $params{price_factors}, 'sortkey');
  }

  if ($params{warehouses}) {
    $self->_get_warehouses($dbh, $params{warehouses});
  }

#  if ($params{groups}) {
#    $self->_get_groups($dbh, $params{groups});
#  }

  if ($params{partsgroup}) {
    $self->get_partsgroup(\%main::myconfig, { all => 1, target => $params{partsgroup} });
  }

  $main::lxdebug->leave_sub();
}

# this sub gets the id and name from $table
sub get_name {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $table) = @_;

  # connect to database
  my $dbh = $self->get_standard_dbh($myconfig);

  $table = $table eq "customer" ? "customer" : "vendor";
  my $arap = $self->{arap} eq "ar" ? "ar" : "ap";

  my ($query, @values);

  if (!$self->{openinvoices}) {
    my $where;
    if ($self->{customernumber} ne "") {
      $where = qq|(vc.customernumber ILIKE ?)|;
      push(@values, '%' . $self->{customernumber} . '%');
    } else {
      $where = qq|(vc.name ILIKE ?)|;
      push(@values, '%' . $self->{$table} . '%');
    }

    $query =
      qq~SELECT vc.id, vc.name,
           vc.street || ' ' || vc.zipcode || ' ' || vc.city || ' ' || vc.country AS address
         FROM $table vc
         WHERE $where AND (NOT vc.obsolete)
         ORDER BY vc.name~;
  } else {
    $query =
      qq~SELECT DISTINCT vc.id, vc.name,
           vc.street || ' ' || vc.zipcode || ' ' || vc.city || ' ' || vc.country AS address
         FROM $arap a
         JOIN $table vc ON (a.${table}_id = vc.id)
         WHERE NOT (a.amount = a.paid) AND (vc.name ILIKE ?)
         ORDER BY vc.name~;
    push(@values, '%' . $self->{$table} . '%');
  }

  $self->{name_list} = selectall_hashref_query($self, $dbh, $query, @values);

  $main::lxdebug->leave_sub();

  return scalar(@{ $self->{name_list} });
}

# the selection sub is used in the AR, AP, IS, IR and OE module
#
sub all_vc {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $table, $module) = @_;

  my $ref;
  my $dbh = $self->get_standard_dbh;

  $table = $table eq "customer" ? "customer" : "vendor";

  my $query = qq|SELECT count(*) FROM $table|;
  my ($count) = selectrow_query($self, $dbh, $query);

  # build selection list
  if ($count <= $myconfig->{vclimit}) {
    $query = qq|SELECT id, name, salesman_id
                FROM $table WHERE NOT obsolete
                ORDER BY name|;
    $self->{"all_$table"} = selectall_hashref_query($self, $dbh, $query);
  }

  # get self
  $self->get_employee($dbh);

  # setup sales contacts
  $query = qq|SELECT e.id, e.name
              FROM employee e
              WHERE (e.sales = '1') AND (NOT e.id = ?)|;
  $self->{all_employees} = selectall_hashref_query($self, $dbh, $query, $self->{employee_id});

  # this is for self
  push(@{ $self->{all_employees} },
       { id   => $self->{employee_id},
         name => $self->{employee} });

  # sort the whole thing
  @{ $self->{all_employees} } =
    sort { $a->{name} cmp $b->{name} } @{ $self->{all_employees} };

  if ($module eq 'AR') {

    # prepare query for departments
    $query = qq|SELECT id, description
                FROM department
                WHERE role = 'P'
                ORDER BY description|;

  } else {
    $query = qq|SELECT id, description
                FROM department
                ORDER BY description|;
  }

  $self->{all_departments} = selectall_hashref_query($self, $dbh, $query);

  # get languages
  $query = qq|SELECT id, description
              FROM language
              ORDER BY id|;

  $self->{languages} = selectall_hashref_query($self, $dbh, $query);

  # get printer
  $query = qq|SELECT printer_description, id
              FROM printers
              ORDER BY printer_description|;

  $self->{printers} = selectall_hashref_query($self, $dbh, $query);

  # get payment terms
  $query = qq|SELECT id, description
              FROM payment_terms
              ORDER BY sortkey|;

  $self->{payment_terms} = selectall_hashref_query($self, $dbh, $query);

  $main::lxdebug->leave_sub();
}

sub language_payment {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig) = @_;

  my $dbh = $self->get_standard_dbh($myconfig);
  # get languages
  my $query = qq|SELECT id, description
                 FROM language
                 ORDER BY id|;

  $self->{languages} = selectall_hashref_query($self, $dbh, $query);

  # get printer
  $query = qq|SELECT printer_description, id
              FROM printers
              ORDER BY printer_description|;

  $self->{printers} = selectall_hashref_query($self, $dbh, $query);

  # get payment terms
  $query = qq|SELECT id, description
              FROM payment_terms
              ORDER BY sortkey|;

  $self->{payment_terms} = selectall_hashref_query($self, $dbh, $query);

  # get buchungsgruppen
  $query = qq|SELECT id, description
              FROM buchungsgruppen|;

  $self->{BUCHUNGSGRUPPEN} = selectall_hashref_query($self, $dbh, $query);

  $main::lxdebug->leave_sub();
}

# this is only used for reports
sub all_departments {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $table) = @_;

  my $dbh = $self->get_standard_dbh($myconfig);
  my $where;

  if ($table eq 'customer') {
    $where = "WHERE role = 'P' ";
  }

  my $query = qq|SELECT id, description
                 FROM department
                 $where
                 ORDER BY description|;
  $self->{all_departments} = selectall_hashref_query($self, $dbh, $query);

  delete($self->{all_departments}) unless (@{ $self->{all_departments} || [] });

  $main::lxdebug->leave_sub();
}

sub create_links {
  $main::lxdebug->enter_sub();

  my ($self, $module, $myconfig, $table, $provided_dbh) = @_;

  my ($fld, $arap);
  if ($table eq "customer") {
    $fld = "buy";
    $arap = "ar";
  } else {
    $table = "vendor";
    $fld = "sell";
    $arap = "ap";
  }

  $self->all_vc($myconfig, $table, $module);

  # get last customers or vendors
  my ($query, $sth, $ref);

  my $dbh = $provided_dbh ? $provided_dbh : $self->get_standard_dbh($myconfig);
  my %xkeyref = ();

  if (!$self->{id}) {

    my $transdate = "current_date";
    if ($self->{transdate}) {
      $transdate = $dbh->quote($self->{transdate});
    }

    # now get the account numbers
    $query = qq|SELECT c.accno, c.description, c.link, c.taxkey_id, tk.tax_id
                FROM chart c, taxkeys tk
                WHERE (c.link LIKE ?) AND (c.id = tk.chart_id) AND tk.id =
                  (SELECT id FROM taxkeys WHERE (taxkeys.chart_id = c.id) AND (startdate <= $transdate) ORDER BY startdate DESC LIMIT 1)
                ORDER BY c.accno|;

    $sth = $dbh->prepare($query);

    do_statement($self, $sth, $query, '%' . $module . '%');

    $self->{accounts} = "";
    while ($ref = $sth->fetchrow_hashref("NAME_lc")) {

      foreach my $key (split(/:/, $ref->{link})) {
        if ($key =~ /\Q$module\E/) {

          # cross reference for keys
          $xkeyref{ $ref->{accno} } = $key;

          push @{ $self->{"${module}_links"}{$key} },
            { accno       => $ref->{accno},
              description => $ref->{description},
              taxkey      => $ref->{taxkey_id},
              tax_id      => $ref->{tax_id} };

          $self->{accounts} .= "$ref->{accno} " unless $key =~ /tax/;
        }
      }
    }
  }

  # get taxkeys and description
  $query = qq|SELECT id, taxkey, taxdescription FROM tax|;
  $self->{TAXKEY} = selectall_hashref_query($self, $dbh, $query);

  if (($module eq "AP") || ($module eq "AR")) {
    # get tax rates and description
    $query = qq|SELECT * FROM tax|;
    $self->{TAX} = selectall_hashref_query($self, $dbh, $query);
  }

  if ($self->{id}) {
    $query =
      qq|SELECT
           a.cp_id, a.invnumber, a.transdate, a.${table}_id, a.datepaid,
           a.duedate, a.ordnumber, a.taxincluded, a.curr AS currency, a.notes,
           a.intnotes, a.department_id, a.amount AS oldinvtotal,
           a.paid AS oldtotalpaid, a.employee_id, a.gldate, a.type,
           c.name AS $table,
           d.description AS department,
           e.name AS employee
         FROM $arap a
         JOIN $table c ON (a.${table}_id = c.id)
         LEFT JOIN employee e ON (e.id = a.employee_id)
         LEFT JOIN department d ON (d.id = a.department_id)
         WHERE a.id = ?|;
    $ref = selectfirst_hashref_query($self, $dbh, $query, $self->{id});

    foreach my $key (keys %$ref) {
      $self->{$key} = $ref->{$key};
    }

    my $transdate = "current_date";
    if ($self->{transdate}) {
      $transdate = $dbh->quote($self->{transdate});
    }

    # now get the account numbers
    $query = qq|SELECT c.accno, c.description, c.link, c.taxkey_id, tk.tax_id
                FROM chart c
                LEFT JOIN taxkeys tk ON (tk.chart_id = c.id)
                WHERE c.link LIKE ?
                  AND (tk.id = (SELECT id FROM taxkeys WHERE taxkeys.chart_id = c.id AND startdate <= $transdate ORDER BY startdate DESC LIMIT 1)
                    OR c.link LIKE '%_tax%' OR c.taxkey_id IS NULL)
                ORDER BY c.accno|;

    $sth = $dbh->prepare($query);
    do_statement($self, $sth, $query, "%$module%");

    $self->{accounts} = "";
    while ($ref = $sth->fetchrow_hashref("NAME_lc")) {

      foreach my $key (split(/:/, $ref->{link})) {
        if ($key =~ /\Q$module\E/) {

          # cross reference for keys
          $xkeyref{ $ref->{accno} } = $key;

          push @{ $self->{"${module}_links"}{$key} },
            { accno       => $ref->{accno},
              description => $ref->{description},
              taxkey      => $ref->{taxkey_id},
              tax_id      => $ref->{tax_id} };

          $self->{accounts} .= "$ref->{accno} " unless $key =~ /tax/;
        }
      }
    }


    # get amounts from individual entries
    $query =
      qq|SELECT
           c.accno, c.description,
           a.source, a.amount, a.memo, a.transdate, a.cleared, a.project_id, a.taxkey,
           p.projectnumber,
           t.rate, t.id
         FROM acc_trans a
         LEFT JOIN chart c ON (c.id = a.chart_id)
         LEFT JOIN project p ON (p.id = a.project_id)
         LEFT JOIN tax t ON (t.id= (SELECT tk.tax_id FROM taxkeys tk
                                    WHERE (tk.taxkey_id=a.taxkey) AND
                                      ((CASE WHEN a.chart_id IN (SELECT chart_id FROM taxkeys WHERE taxkey_id = a.taxkey)
                                        THEN tk.chart_id = a.chart_id
                                        ELSE 1 = 1
                                        END)
                                       OR (c.link='%tax%')) AND
                                      (startdate <= a.transdate) ORDER BY startdate DESC LIMIT 1))
         WHERE a.trans_id = ?
         AND a.fx_transaction = '0'
         ORDER BY a.acc_trans_id, a.transdate|;
    $sth = $dbh->prepare($query);
    do_statement($self, $sth, $query, $self->{id});

    # get exchangerate for currency
    $self->{exchangerate} =
      $self->get_exchangerate($dbh, $self->{currency}, $self->{transdate}, $fld);
    my $index = 0;

    # store amounts in {acc_trans}{$key} for multiple accounts
    while (my $ref = $sth->fetchrow_hashref("NAME_lc")) {
      $ref->{exchangerate} =
        $self->get_exchangerate($dbh, $self->{currency}, $ref->{transdate}, $fld);
      if (!($xkeyref{ $ref->{accno} } =~ /tax/)) {
        $index++;
      }
      if (($xkeyref{ $ref->{accno} } =~ /paid/) && ($self->{type} eq "credit_note")) {
        $ref->{amount} *= -1;
      }
      $ref->{index} = $index;

      push @{ $self->{acc_trans}{ $xkeyref{ $ref->{accno} } } }, $ref;
    }

    $sth->finish;
    $query =
      qq|SELECT
           d.curr AS currencies, d.closedto, d.revtrans,
           (SELECT c.accno FROM chart c WHERE d.fxgain_accno_id = c.id) AS fxgain_accno,
           (SELECT c.accno FROM chart c WHERE d.fxloss_accno_id = c.id) AS fxloss_accno
         FROM defaults d|;
    $ref = selectfirst_hashref_query($self, $dbh, $query);
    map { $self->{$_} = $ref->{$_} } keys %$ref;

  } else {

    # get date
    $query =
       qq|SELECT
            current_date AS transdate, d.curr AS currencies, d.closedto, d.revtrans,
            (SELECT c.accno FROM chart c WHERE d.fxgain_accno_id = c.id) AS fxgain_accno,
            (SELECT c.accno FROM chart c WHERE d.fxloss_accno_id = c.id) AS fxloss_accno
          FROM defaults d|;
    $ref = selectfirst_hashref_query($self, $dbh, $query);
    map { $self->{$_} = $ref->{$_} } keys %$ref;

    if ($self->{"$self->{vc}_id"}) {

      # only setup currency
      ($self->{currency}) = split(/:/, $self->{currencies});

    } else {

      $self->lastname_used($dbh, $myconfig, $table, $module);

      # get exchangerate for currency
      $self->{exchangerate} =
        $self->get_exchangerate($dbh, $self->{currency}, $self->{transdate}, $fld);

    }

  }

  $main::lxdebug->leave_sub();
}

sub lastname_used {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $myconfig, $table, $module) = @_;

  my ($arap, $where);

  $table         = $table eq "customer" ? "customer" : "vendor";
  my %column_map = ("a.curr"                  => "currency",
                    "a.${table}_id"           => "${table}_id",
                    "a.department_id"         => "department_id",
                    "d.description"           => "department",
                    "ct.name"                 => $table,
                    "current_date + ct.terms" => "duedate",
    );

  if ($self->{type} =~ /delivery_order/) {
    $arap  = 'delivery_orders';
    delete $column_map{"a.curr"};

  } elsif ($self->{type} =~ /_order/) {
    $arap  = 'oe';
    $where = "quotation = '0'";

  } elsif ($self->{type} =~ /_quotation/) {
    $arap  = 'oe';
    $where = "quotation = '1'";

  } elsif ($table eq 'customer') {
    $arap  = 'ar';

  } else {
    $arap  = 'ap';

  }

  $where           = "($where) AND" if ($where);
  my $query        = qq|SELECT MAX(id) FROM $arap
                        WHERE $where ${table}_id > 0|;
  my ($trans_id)   = selectrow_query($self, $dbh, $query);
  $trans_id       *= 1;

  my $column_spec  = join(', ', map { "${_} AS $column_map{$_}" } keys %column_map);
  $query           = qq|SELECT $column_spec
                        FROM $arap a
                        LEFT JOIN $table     ct ON (a.${table}_id = ct.id)
                        LEFT JOIN department d  ON (a.department_id = d.id)
                        WHERE a.id = ?|;
  my $ref          = selectfirst_hashref_query($self, $dbh, $query, $trans_id);

  map { $self->{$_} = $ref->{$_} } values %column_map;

  $main::lxdebug->leave_sub();
}

sub current_date {
  $main::lxdebug->enter_sub();

  my $self     = shift;
  my $myconfig = shift || \%::myconfig;
  my ($thisdate, $days) = @_;

  my $dbh = $self->get_standard_dbh($myconfig);
  my $query;

  $days *= 1;
  if ($thisdate) {
    my $dateformat = $myconfig->{dateformat};
    $dateformat .= "yy" if $myconfig->{dateformat} !~ /^y/;
    $thisdate = $dbh->quote($thisdate);
    $query = qq|SELECT to_date($thisdate, '$dateformat') + $days AS thisdate|;
  } else {
    $query = qq|SELECT current_date AS thisdate|;
  }

  ($thisdate) = selectrow_query($self, $dbh, $query);

  $main::lxdebug->leave_sub();

  return $thisdate;
}

sub like {
  $main::lxdebug->enter_sub();

  my ($self, $string) = @_;

  if ($string !~ /%/) {
    $string = "%$string%";
  }

  $string =~ s/\'/\'\'/g;

  $main::lxdebug->leave_sub();

  return $string;
}

sub redo_rows {
  $main::lxdebug->enter_sub();

  my ($self, $flds, $new, $count, $numrows) = @_;

  my @ndx = ();

  map { push @ndx, { num => $new->[$_ - 1]->{runningnumber}, ndx => $_ } } 1 .. $count;

  my $i = 0;

  # fill rows
  foreach my $item (sort { $a->{num} <=> $b->{num} } @ndx) {
    $i++;
    my $j = $item->{ndx} - 1;
    map { $self->{"${_}_$i"} = $new->[$j]->{$_} } @{$flds};
  }

  # delete empty rows
  for $i ($count + 1 .. $numrows) {
    map { delete $self->{"${_}_$i"} } @{$flds};
  }

  $main::lxdebug->leave_sub();
}

sub update_status {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig) = @_;

  my ($i, $id);

  my $dbh = $self->dbconnect_noauto($myconfig);

  my $query = qq|DELETE FROM status
                 WHERE (formname = ?) AND (trans_id = ?)|;
  my $sth = prepare_query($self, $dbh, $query);

  if ($self->{formname} =~ /(check|receipt)/) {
    for $i (1 .. $self->{rowcount}) {
      do_statement($self, $sth, $query, $self->{formname}, $self->{"id_$i"} * 1);
    }
  } else {
    do_statement($self, $sth, $query, $self->{formname}, $self->{id});
  }
  $sth->finish();

  my $printed = ($self->{printed} =~ /\Q$self->{formname}\E/) ? "1" : "0";
  my $emailed = ($self->{emailed} =~ /\Q$self->{formname}\E/) ? "1" : "0";

  my %queued = split / /, $self->{queued};
  my @values;

  if ($self->{formname} =~ /(check|receipt)/) {

    # this is a check or receipt, add one entry for each lineitem
    my ($accno) = split /--/, $self->{account};
    $query = qq|INSERT INTO status (trans_id, printed, spoolfile, formname, chart_id)
                VALUES (?, ?, ?, ?, (SELECT c.id FROM chart c WHERE c.accno = ?))|;
    @values = ($printed, $queued{$self->{formname}}, $self->{prinform}, $accno);
    $sth = prepare_query($self, $dbh, $query);

    for $i (1 .. $self->{rowcount}) {
      if ($self->{"checked_$i"}) {
        do_statement($self, $sth, $query, $self->{"id_$i"}, @values);
      }
    }
    $sth->finish();

  } else {
    $query = qq|INSERT INTO status (trans_id, printed, emailed, spoolfile, formname)
                VALUES (?, ?, ?, ?, ?)|;
    do_query($self, $dbh, $query, $self->{id}, $printed, $emailed,
             $queued{$self->{formname}}, $self->{formname});
  }

  $dbh->commit;
  $dbh->disconnect;

  $main::lxdebug->leave_sub();
}

sub save_status {
  $main::lxdebug->enter_sub();

  my ($self, $dbh) = @_;

  my ($query, $printed, $emailed);

  my $formnames  = $self->{printed};
  my $emailforms = $self->{emailed};

  $query = qq|DELETE FROM status
                 WHERE (formname = ?) AND (trans_id = ?)|;
  do_query($self, $dbh, $query, $self->{formname}, $self->{id});

  # this only applies to the forms
  # checks and receipts are posted when printed or queued

  if ($self->{queued}) {
    my %queued = split / /, $self->{queued};

    foreach my $formname (keys %queued) {
      $printed = ($self->{printed} =~ /\Q$self->{formname}\E/) ? "1" : "0";
      $emailed = ($self->{emailed} =~ /\Q$self->{formname}\E/) ? "1" : "0";

      $query = qq|INSERT INTO status (trans_id, printed, emailed, spoolfile, formname)
                  VALUES (?, ?, ?, ?, ?)|;
      do_query($self, $dbh, $query, $self->{id}, $printed, $emailed, $queued{$formname}, $formname);

      $formnames  =~ s/\Q$self->{formname}\E//;
      $emailforms =~ s/\Q$self->{formname}\E//;

    }
  }

  # save printed, emailed info
  $formnames  =~ s/^ +//g;
  $emailforms =~ s/^ +//g;

  my %status = ();
  map { $status{$_}{printed} = 1 } split / +/, $formnames;
  map { $status{$_}{emailed} = 1 } split / +/, $emailforms;

  foreach my $formname (keys %status) {
    $printed = ($formnames  =~ /\Q$self->{formname}\E/) ? "1" : "0";
    $emailed = ($emailforms =~ /\Q$self->{formname}\E/) ? "1" : "0";

    $query = qq|INSERT INTO status (trans_id, printed, emailed, formname)
                VALUES (?, ?, ?, ?)|;
    do_query($self, $dbh, $query, $self->{id}, $printed, $emailed, $formname);
  }

  $main::lxdebug->leave_sub();
}

#--- 4 locale ---#
# $main::locale->text('SAVED')
# $main::locale->text('DELETED')
# $main::locale->text('ADDED')
# $main::locale->text('PAYMENT POSTED')
# $main::locale->text('POSTED')
# $main::locale->text('POSTED AS NEW')
# $main::locale->text('ELSE')
# $main::locale->text('SAVED FOR DUNNING')
# $main::locale->text('DUNNING STARTED')
# $main::locale->text('PRINTED')
# $main::locale->text('MAILED')
# $main::locale->text('SCREENED')
# $main::locale->text('CANCELED')
# $main::locale->text('invoice')
# $main::locale->text('proforma')
# $main::locale->text('sales_order')
# $main::locale->text('pick_list')
# $main::locale->text('purchase_order')
# $main::locale->text('bin_list')
# $main::locale->text('sales_quotation')
# $main::locale->text('request_quotation')

sub save_history {
  $main::lxdebug->enter_sub();

  my $self = shift;
  my $dbh  = shift || $self->get_standard_dbh;

  if(!exists $self->{employee_id}) {
    &get_employee($self, $dbh);
  }

  my $query =
   qq|INSERT INTO history_erp (trans_id, employee_id, addition, what_done, snumbers) | .
   qq|VALUES (?, (SELECT id FROM employee WHERE login = ?), ?, ?, ?)|;
  my @values = (conv_i($self->{id}), $self->{login},
                $self->{addition}, $self->{what_done}, "$self->{snumbers}");
  do_query($self, $dbh, $query, @values);

  $dbh->commit;

  $main::lxdebug->leave_sub();
}

sub get_history {
  $main::lxdebug->enter_sub();

  my ($self, $dbh, $trans_id, $restriction, $order) = @_;
  my ($orderBy, $desc) = split(/\-\-/, $order);
  $order = " ORDER BY " . ($order eq "" ? " h.itime " : ($desc == 1 ? $orderBy . " DESC " : $orderBy . " "));
  my @tempArray;
  my $i = 0;
  if ($trans_id ne "") {
    my $query =
      qq|SELECT h.employee_id, h.itime::timestamp(0) AS itime, h.addition, h.what_done, emp.name, h.snumbers, h.trans_id AS id | .
      qq|FROM history_erp h | .
      qq|LEFT JOIN employee emp ON (emp.id = h.employee_id) | .
      qq|WHERE (trans_id = | . $trans_id . qq|) $restriction | .
      $order;

    my $sth = $dbh->prepare($query) || $self->dberror($query);

    $sth->execute() || $self->dberror("$query");

    while(my $hash_ref = $sth->fetchrow_hashref()) {
      $hash_ref->{addition} = $main::locale->text($hash_ref->{addition});
      $hash_ref->{what_done} = $main::locale->text($hash_ref->{what_done});
      $hash_ref->{snumbers} =~ s/^.+_(.*)$/$1/g;
      $tempArray[$i++] = $hash_ref;
    }
    $main::lxdebug->leave_sub() and return \@tempArray
      if ($i > 0 && $tempArray[0] ne "");
  }
  $main::lxdebug->leave_sub();
  return 0;
}

sub update_defaults {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $fld, $provided_dbh) = @_;

  my $dbh;
  if ($provided_dbh) {
    $dbh = $provided_dbh;
  } else {
    $dbh = $self->dbconnect_noauto($myconfig);
  }
  my $query = qq|SELECT $fld FROM defaults FOR UPDATE|;
  my $sth   = $dbh->prepare($query);

  $sth->execute || $self->dberror($query);
  my ($var) = $sth->fetchrow_array;
  $sth->finish;

  if ($var =~ m/\d+$/) {
    my $new_var  = (substr $var, $-[0]) * 1 + 1;
    my $len_diff = length($var) - $-[0] - length($new_var);
    $var         = substr($var, 0, $-[0]) . ($len_diff > 0 ? '0' x $len_diff : '') . $new_var;

  } else {
    $var = $var . '1';
  }

  $query = qq|UPDATE defaults SET $fld = ?|;
  do_query($self, $dbh, $query, $var);

  if (!$provided_dbh) {
    $dbh->commit;
    $dbh->disconnect;
  }

  $main::lxdebug->leave_sub();

  return $var;
}

sub update_business {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $business_id, $provided_dbh) = @_;

  my $dbh;
  if ($provided_dbh) {
    $dbh = $provided_dbh;
  } else {
    $dbh = $self->dbconnect_noauto($myconfig);
  }
  my $query =
    qq|SELECT customernumberinit FROM business
       WHERE description = ? FOR UPDATE|;
  my ($var) = selectrow_query($self, $dbh, $query, $business_id);

  return undef unless $var;

  if ($var =~ m/\d+$/) {
    my $new_var  = (substr $var, $-[0]) * 1 + 1;
    my $len_diff = length($var) - $-[0] - length($new_var);
    $var         = substr($var, 0, $-[0]) . ($len_diff > 0 ? '0' x $len_diff : '') . $new_var;

  } else {
    $var = $var . '1';
  }

  $query = qq|UPDATE business
              SET customernumberinit = ?
              WHERE description = ?|;
  do_query($self, $dbh, $query, $var, $business_id);

  if (!$provided_dbh) {
    $dbh->commit;
    $dbh->disconnect;
  }

  $main::lxdebug->leave_sub();

  return $var;
}

sub get_partsgroup {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $p) = @_;
  my $target = $p->{target} || 'all_partsgroup';

  my $dbh = $self->get_standard_dbh($myconfig);

  my $query = qq|SELECT DISTINCT pg.id, pg.partsgroup
                 FROM partsgroup pg
                 JOIN parts p ON (p.partsgroup_id = pg.id) |;
  my @values;

  if ($p->{searchitems} eq 'part') {
    $query .= qq|WHERE p.inventory_accno_id > 0|;
  }
  if ($p->{searchitems} eq 'service') {
    $query .= qq|WHERE p.inventory_accno_id IS NULL|;
  }
  if ($p->{searchitems} eq 'assembly') {
    $query .= qq|WHERE p.assembly = '1'|;
  }
  if ($p->{searchitems} eq 'labor') {
    $query .= qq|WHERE (p.inventory_accno_id > 0) AND (p.income_accno_id IS NULL)|;
  }

  $query .= qq|ORDER BY partsgroup|;

  if ($p->{all}) {
    $query = qq|SELECT id, partsgroup FROM partsgroup
                ORDER BY partsgroup|;
  }

  if ($p->{language_code}) {
    $query = qq|SELECT DISTINCT pg.id, pg.partsgroup,
                  t.description AS translation
                FROM partsgroup pg
                JOIN parts p ON (p.partsgroup_id = pg.id)
                LEFT JOIN translation t ON ((t.trans_id = pg.id) AND (t.language_code = ?))
                ORDER BY translation|;
    @values = ($p->{language_code});
  }

  $self->{$target} = selectall_hashref_query($self, $dbh, $query, @values);

  $main::lxdebug->leave_sub();
}

sub get_pricegroup {
  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $p) = @_;

  my $dbh = $self->get_standard_dbh($myconfig);

  my $query = qq|SELECT p.id, p.pricegroup
                 FROM pricegroup p|;

  $query .= qq| ORDER BY pricegroup|;

  if ($p->{all}) {
    $query = qq|SELECT id, pricegroup FROM pricegroup
                ORDER BY pricegroup|;
  }

  $self->{all_pricegroup} = selectall_hashref_query($self, $dbh, $query);

  $main::lxdebug->leave_sub();
}

sub all_years {
# usage $form->all_years($myconfig, [$dbh])
# return list of all years where bookings found
# (@all_years)

  $main::lxdebug->enter_sub();

  my ($self, $myconfig, $dbh) = @_;

  $dbh ||= $self->get_standard_dbh($myconfig);

  # get years
  my $query = qq|SELECT (SELECT MIN(transdate) FROM acc_trans),
                   (SELECT MAX(transdate) FROM acc_trans)|;
  my ($startdate, $enddate) = selectrow_query($self, $dbh, $query);

  if ($myconfig->{dateformat} =~ /^yy/) {
    ($startdate) = split /\W/, $startdate;
    ($enddate) = split /\W/, $enddate;
  } else {
    (@_) = split /\W/, $startdate;
    $startdate = $_[2];
    (@_) = split /\W/, $enddate;
    $enddate = $_[2];
  }

  my @all_years;
  $startdate = substr($startdate,0,4);
  $enddate = substr($enddate,0,4);

  while ($enddate >= $startdate) {
    push @all_years, $enddate--;
  }

  return @all_years;

  $main::lxdebug->leave_sub();
}

sub backup_vars {
  $main::lxdebug->enter_sub();
  my $self = shift;
  my @vars = @_;

  map { $self->{_VAR_BACKUP}->{$_} = $self->{$_} if exists $self->{$_} } @vars;

  $main::lxdebug->leave_sub();
}

sub restore_vars {
  $main::lxdebug->enter_sub();

  my $self = shift;
  my @vars = @_;

  map { $self->{$_} = $self->{_VAR_BACKUP}->{$_} if exists $self->{_VAR_BACKUP}->{$_} } @vars;

  $main::lxdebug->leave_sub();
}

sub prepare_for_printing {
  my ($self) = @_;

  $self->{templates} ||= $::myconfig{templates};
  $self->{formname}  ||= $self->{type};
  $self->{media}     ||= 'email';

  die "'media' other than 'email', 'file', 'printer' is not supported yet" unless $self->{media} =~ m/^(?:email|file|printer)$/;

  # set shipto from billto unless set
  my $has_shipto = any { $self->{"shipto$_"} } qw(name street zipcode city country contact);
  if (!$has_shipto && ($self->{type} =~ m/^(?:purchase_order|request_quotation)$/)) {
    $self->{shiptoname}   = $::myconfig{company};
    $self->{shiptostreet} = $::myconfig{address};
  }

  my $language = $self->{language} ? '_' . $self->{language} : '';

  my ($language_tc, $output_numberformat, $output_dateformat, $output_longdates);
  if ($self->{language_id}) {
    ($language_tc, $output_numberformat, $output_dateformat, $output_longdates) = AM->get_language_details(\%::myconfig, $self, $self->{language_id});
  } else {
    $output_dateformat   = $::myconfig{dateformat};
    $output_numberformat = $::myconfig{numberformat};
    $output_longdates    = 1;
  }

  # Retrieve accounts for tax calculation.
  IC->retrieve_accounts(\%::myconfig, $self, map { $_ => $self->{"id_$_"} } 1 .. $self->{rowcount});

  if ($self->{type} =~ /_delivery_order$/) {
    DO->order_details();
  } elsif ($self->{type} =~ /sales_order|sales_quotation|request_quotation|purchase_order/) {
    OE->order_details(\%::myconfig, $self);
  } else {
    IS->invoice_details(\%::myconfig, $self, $::locale);
  }

  # Chose extension & set source file name
  my $extension = 'html';
  if ($self->{format} eq 'postscript') {
    $self->{postscript}   = 1;
    $extension            = 'tex';
  } elsif ($self->{"format"} =~ /pdf/) {
    $self->{pdf}          = 1;
    $extension            = $self->{'format'} =~ m/opendocument/i ? 'odt' : 'tex';
  } elsif ($self->{"format"} =~ /opendocument/) {
    $self->{opendocument} = 1;
    $extension            = 'odt';
  } elsif ($self->{"format"} =~ /excel/) {
    $self->{excel}        = 1;
    $extension            = 'xls';
  }

  my $printer_code    = '_' . $self->{printer_code} if $self->{printer_code};
  my $email_extension = '_email' if -f "$self->{templates}/$self->{formname}_email${language}${printer_code}.${extension}";
  $self->{IN}         = "$self->{formname}${email_extension}${language}${printer_code}.${extension}";

  # Format dates.
  $self->format_dates($output_dateformat, $output_longdates,
                      qw(invdate orddate quodate pldate duedate reqdate transdate shippingdate deliverydate validitydate paymentdate datepaid
                         transdate_oe deliverydate_oe employee_startdate employee_enddate),
                      grep({ /^(?:datepaid|transdate_oe|reqdate|deliverydate|deliverydate_oe|transdate)_\d+$/ } keys(%{$self})));

  $self->reformat_numbers($output_numberformat, 2,
                          qw(invtotal ordtotal quototal subtotal linetotal listprice sellprice netprice discount tax taxbase total paid),
                          grep({ /^(?:linetotal|listprice|sellprice|netprice|taxbase|discount|paid|subtotal|total|tax)_\d+$/ } keys(%{$self})));

  $self->reformat_numbers($output_numberformat, undef, qw(qty price_factor), grep({ /^qty_\d+$/} keys(%{$self})));

  my ($cvar_date_fields, $cvar_number_fields) = CVar->get_field_format_list('module' => 'CT', 'prefix' => 'vc_');

  if (scalar @{ $cvar_date_fields }) {
    $self->format_dates($output_dateformat, $output_longdates, @{ $cvar_date_fields });
  }

  while (my ($precision, $field_list) = each %{ $cvar_number_fields }) {
    $self->reformat_numbers($output_numberformat, $precision, @{ $field_list });
  }

  return $self;
}

sub format_dates {
  my ($self, $dateformat, $longformat, @indices) = @_;

  $dateformat ||= $::myconfig{dateformat};

  foreach my $idx (@indices) {
    if ($self->{TEMPLATE_ARRAYS} && (ref($self->{TEMPLATE_ARRAYS}->{$idx}) eq "ARRAY")) {
      for (my $i = 0; $i < scalar(@{ $self->{TEMPLATE_ARRAYS}->{$idx} }); $i++) {
        $self->{TEMPLATE_ARRAYS}->{$idx}->[$i] = $::locale->reformat_date(\%::myconfig, $self->{TEMPLATE_ARRAYS}->{$idx}->[$i], $dateformat, $longformat);
      }
    }

    next unless defined $self->{$idx};

    if (!ref($self->{$idx})) {
      $self->{$idx} = $::locale->reformat_date(\%::myconfig, $self->{$idx}, $dateformat, $longformat);

    } elsif (ref($self->{$idx}) eq "ARRAY") {
      for (my $i = 0; $i < scalar(@{ $self->{$idx} }); $i++) {
        $self->{$idx}->[$i] = $::locale->reformat_date(\%::myconfig, $self->{$idx}->[$i], $dateformat, $longformat);
      }
    }
  }
}

sub reformat_numbers {
  my ($self, $numberformat, $places, @indices) = @_;

  return if !$numberformat || ($numberformat eq $::myconfig{numberformat});

  foreach my $idx (@indices) {
    if ($self->{TEMPLATE_ARRAYS} && (ref($self->{TEMPLATE_ARRAYS}->{$idx}) eq "ARRAY")) {
      for (my $i = 0; $i < scalar(@{ $self->{TEMPLATE_ARRAYS}->{$idx} }); $i++) {
        $self->{TEMPLATE_ARRAYS}->{$idx}->[$i] = $self->parse_amount(\%::myconfig, $self->{TEMPLATE_ARRAYS}->{$idx}->[$i]);
      }
    }

    next unless defined $self->{$idx};

    if (!ref($self->{$idx})) {
      $self->{$idx} = $self->parse_amount(\%::myconfig, $self->{$idx});

    } elsif (ref($self->{$idx}) eq "ARRAY") {
      for (my $i = 0; $i < scalar(@{ $self->{$idx} }); $i++) {
        $self->{$idx}->[$i] = $self->parse_amount(\%::myconfig, $self->{$idx}->[$i]);
      }
    }
  }

  my $saved_numberformat    = $::myconfig{numberformat};
  $::myconfig{numberformat} = $numberformat;

  foreach my $idx (@indices) {
    if ($self->{TEMPLATE_ARRAYS} && (ref($self->{TEMPLATE_ARRAYS}->{$idx}) eq "ARRAY")) {
      for (my $i = 0; $i < scalar(@{ $self->{TEMPLATE_ARRAYS}->{$idx} }); $i++) {
        $self->{TEMPLATE_ARRAYS}->{$idx}->[$i] = $self->format_amount(\%::myconfig, $self->{TEMPLATE_ARRAYS}->{$idx}->[$i], $places);
      }
    }

    next unless defined $self->{$idx};

    if (!ref($self->{$idx})) {
      $self->{$idx} = $self->format_amount(\%::myconfig, $self->{$idx}, $places);

    } elsif (ref($self->{$idx}) eq "ARRAY") {
      for (my $i = 0; $i < scalar(@{ $self->{$idx} }); $i++) {
        $self->{$idx}->[$i] = $self->format_amount(\%::myconfig, $self->{$idx}->[$i], $places);
      }
    }
  }

  $::myconfig{numberformat} = $saved_numberformat;
}

1;

__END__

=head1 NAME

SL::Form.pm - main data object.

=head1 SYNOPSIS

This is the main data object of Lx-Office.
Unfortunately it also acts as a god object for certain data retrieval procedures used in the entry points.
Points of interest for a beginner are:

 - $form->error            - renders a generic error in html. accepts an error message
 - $form->get_standard_dbh - returns a database connection for the

=head1 SPECIAL FUNCTIONS

=head2 C<_store_value()>

parses a complex var name, and stores it in the form.

syntax:
  $form->_store_value($key, $value);

keys must start with a string, and can contain various tokens.
supported key structures are:

1. simple access
  simple key strings work as expected

  id => $form->{id}

2. hash access.
  separating two keys by a dot (.) will result in a hash lookup for the inner value
  this is similar to the behaviour of java and templating mechanisms.

  filter.description => $form->{filter}->{description}

3. array+hashref access

  adding brackets ([]) before the dot will cause the next hash to be put into an array.
  using [+] instead of [] will force a new array index. this is useful for recurring
  data structures like part lists. put a [+] into the first varname, and use [] on the
  following ones.

  repeating these names in your template:

    invoice.items[+].id
    invoice.items[].parts_id

  will result in:

    $form->{invoice}->{items}->[
      {
        id       => ...
        parts_id => ...
      },
      {
        id       => ...
        parts_id => ...
      }
      ...
    ]

4. arrays

  using brackets at the end of a name will result in a pure array to be created.
  note that you mustn't use [+], which is reserved for array+hash access and will
  result in undefined behaviour in array context.

  filter.status[]  => $form->{status}->[ val1, val2, ... ]

=head2 C<update_business> PARAMS

PARAMS (not named):
 \%config,     - config hashref
 $business_id, - business id
 $dbh          - optional database handle

handles business (thats customer/vendor types) sequences.

special behaviour for empty strings in customerinitnumber field:
will in this case not increase the value, and return undef.

=head2 C<redirect_header> $url

Generates a HTTP redirection header for the new C<$url>. Constructs an
absolute URL including scheme, host name and port. If C<$url> is a
relative URL then it is considered relative to Lx-Office base URL.

This function C<die>s if headers have already been created with
C<$::form-E<gt>header>.

Examples:

  print $::form->redirect_header('oe.pl?action=edit&id=1234');
  print $::form->redirect_header('http://www.lx-office.org/');

=head2 C<header>

Generates a general purpose http/html header and includes most of the scripts
ans stylesheets needed.

Only one header will be generated. If the method was already called in this
request it will not output anything and return undef. Also if no
HTTP_USER_AGENT is found, no header is generated.

Although header does not accept parameters itself, it will honor special
hashkeys of its Form instance:

=over 4

=item refresh_time

=item refresh_url

If one of these is set, a http-equiv refresh is generated. Missing parameters
default to 3 seconds and the refering url.

=item stylesheet

=item stylesheets

If these are arrayrefs the contents will be inlined into the header.

=item landscape

If true, a css snippet will be generated that sets the page in landscape mode.

=item favicon

Used to override the default favicon.

=item title

A html page title will be generated from this

=back

=cut
