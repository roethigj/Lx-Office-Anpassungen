### Delete user
diag("Delete test user '$lxtest->{testuserlogin}'");
$sel->open_ok($lxtest->{lxadmin});
$sel->title_is("Lx-Office ERP Administration -");
$sel->click_ok("link=$lxtest->{testuserlogin}");
$sel->wait_for_page_to_load_ok($lxtest->{timeout});
$sel->title_is("Lx-Office ERP Administration / Benutzerdaten bearbeiten -");
$sel->click_ok("//input[(\@name=\"action\") and (\@value=\"L�schen\")]");
$sel->wait_for_page_to_load_ok($lxtest->{timeout});
