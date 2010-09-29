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

write_text("test_dir/trunk/tdir2/tfile_fixprop1", 'Hello');
write_text("test_dir/trunk/tdir2/tfile_fixprop2", '$'.'Id'.'$');
run_system("${PERL} s4 add test_dir/trunk/tdir2/tfile_fixprop*");
ok(1,'add');

$out = `${PERL} s4 status test_dir/trunk/tdir2/tfile_fixprop*`;
like($out, qr/^A /, 'status');

$out = `${PERL} s4 propget svn:keywords test_dir/trunk/tdir2/tfile_fixprop1`;
is($out, "", 'propget');
$out = `${PERL} s4 propget svn:keywords test_dir/trunk/tdir2/tfile_fixprop2`;
like($out, qr/id/, 'propget');
