# This file has been auto-generated. Do not modify it; it will be overwritten
# by rose_auto_create_model.pl automatically.
package SL::DB::Gifi;

use strict;

use base qw(SL::DB::Object);

__PACKAGE__->meta->setup(
  table   => 'gifi',

  columns => [
    accno       => { type => 'text' },
    description => { type => 'text' },
    id          => { type => 'serial', not_null => 1 },
  ],

  primary_key_columns => [ 'id' ],

  unique_key => [ 'accno' ],
);

1;
;
