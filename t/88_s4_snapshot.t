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

$out = `${PERL} s4 revert test_dir/trunk/tdir2/tfile1`;
ok(1,'setup area - s4 revert');

write_text("test_dir/trunk/tdir2/tfile1", 'text_to_appear_in_diff');
ok(1,'write_text');

$out = `${PERL} s4 snapshot test_dir/trunk/tdir2`;
ok($out,"s4 snapshot");
like($out, qr/text_to_appear_in_diff/, "diff contains magic");
