#!/usr/bin/perl -w
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
#
# Copyright 2002-2010 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# Lesser General Public License Version 3 or the Perl Artistic License Version 2.0.

use strict;
use Test::More;
use Cwd;

BEGIN { plan tests => 4 }
BEGIN { require "t/test_utils.pl"; }

my $out;

write_text("test_dir/trunk/87file", 'Orig');
run_system("${PERL} s4 add test_dir/trunk/87file");
ok(1,'add');

$out = `${PERL} s4 ci -m 87file test_dir/trunk/87file`;
ok(1,'ci');

$out = `${PERL} s4 cat-or-mods test_dir/trunk/87file`;
is($out,"Orig",'cat-or-mods');

write_text("test_dir/trunk/87file", 'Newer');
$out = `${PERL} s4 cat-or-mods test_dir/trunk/87file`;
is($out,"Newer",'cat-or-mods');
