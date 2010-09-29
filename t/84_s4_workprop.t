#!/usr/bin/perl -w
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
#
# Copyright 2002-2010 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# Lesser General Public License Version 3 or the Perl Artistic License Version 2.0.

use strict;
use Test::More;
use Cwd;

BEGIN { plan tests => 6 }
BEGIN { require "t/test_utils.pl"; }

our $S4 = "${PERL} ../../s4";

my $out;

chdir "test_dir/trunk";

$out = `${S4} workpropset testprop value`;
print "---\n$out\n";
is($out,'', 'workpropset');

$out = `${S4} workpropget testprop`;
print "---\n$out\n";
like($out,qr/value/, 'workpropget');

$out = `${S4} workproplist -v`;
print "---\n$out\n";
like($out,qr/testprop\n\s+value/, 'workproplist -v');

$out = `${S4} workproplist --xml -v`;
print "---\n$out\n";
like($out,qr/name=/, 'workproplist -xml');

$out = `${S4} workpropdel testprop`;
print "---\n$out\n";
is($out,'', 'workpropdel');

$out = `${S4} workpropget testprop`;
print "---\n$out\n";
is($out,'', 'workpropget empty');
