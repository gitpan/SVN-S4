#!/usr/bin/perl -w
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
#
# Copyright 2002-2010 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# Lesser General Public License Version 3 or the Perl Artistic License Version 2.0.

use strict;
use IO::File;
use Test::More;
use Cwd;

BEGIN { plan tests => 11 }
BEGIN { require "t/test_utils.pl"; }

system("/bin/rm -rf test_dir/view1");

chdir "test_dir" or die;
$ENV{CWD} = getcwd;
our $S4 = "${PERL} ../s4";

my $cmd;
my $out;

$cmd = "co $REPO/views/trunk/view1";
$out = `${S4} $cmd`;
like($out, qr/Checked out revision/, "s4 $cmd");

$out = `${S4} update`;
like($out, qr//, "cd view1; s4 update");

like($out, qr//, "s4 update view1");
ok(-e "view1/trunk_tdir1/tsub1", "added view1/trunk_tdir1/tsub1");

$out = `${S4} info-switches view1`;
like($out, qr!view1/trunk_tdir1!, "s4 info-switches view1");

# Add an entry
{
    my $fh = IO::File->new(">>view1/Project.viewspec") or die;
    $fh->print("view	^/top/trunk/tdir2	trunk_tdir2\n");
}
# Update and it should appear
$out = `${S4} update view1`;
print $out;
like($out, qr//, "s4 update view1");
ok(-e "view1/trunk_tdir1/tsub1",  "check still view1/trunk_tdir1/tsub1");
ok(-e "view1/trunk_tdir2/tfile2", "check added view1/trunk_tdir2/tfile2");

# Delete an entry (trunk_tdir1)
{
    my $fh = IO::File->new(">view1/Project.viewspec") or die;
    $fh->print("view	^/top/trunk/tdir2	trunk_tdir2\n");
}
$out = `${S4} update view1`;
print $out;
like($out, qr//, "s4 update view1");
ok(!-e "view1/trunk_tdir1/tsub1", "check deleted view1/trunk_tdir1/tsub1");
ok(-e "view1/trunk_tdir2/tfile2", "check still view1/trunk_tdir2/tfile2");
