#!/usr/bin/perl -w
# $Id: 50_makerepo.t 48292 2007-12-05 16:48:44Z denney $
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
#
# Copyright 2006-2007 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.

use strict;
use Test;
use Cwd;

BEGIN { plan tests => 4 }
BEGIN { require "t/test_utils.pl"; }

# Blow old stuff away, if there was anything there
system("/bin/rm -rf test_dir/*");  # Ignore errors

print "If below svnadmin create hangs, you're out of random numbers.\n";
print "See http://www.linuxcertified.com/hw_random.html\n";

run_system("svnadmin create --fs-type fsfs $REPOFN");
ok(1);

run_system("svnadmin load $REPOFN < t/50_makerepo.dump");
ok(1);

run_system("svn co $REPO/top test_dir/top");
ok(1);

run_system("svn co $REPO/top/trunk test_dir/trunk");
ok(1);

print "If you need to change the initial repository, after this step\n";
print "make your changes to test_dir/top, then:\n";
print "   svnadmin dump test_dir/repo > t/50_makerepo.dump\n";

