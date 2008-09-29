#!/usr/bin/perl -w
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
#
# Copyright 2002-2008 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.

use strict;
use Test;
use Cwd qw(getcwd);
use File::Spec::Functions;

BEGIN { plan tests => 4 }
BEGIN { require "t/test_utils.pl"; }

my $uppwd = getcwd();
mkdir 'test_dir', 0777;
chdir 'test_dir';

use SVN::S4::Path;
ok(1);

#$SVN::S4::Path::Debug = 1;

ok (SVN::S4::Path::fileNoLinks('.')
    eq getcwd());
ok (SVN::S4::Path::fileNoLinks(catfile(catdir('bebop','.','uptoo','..','..'),'down1'))
    eq catfile(getcwd(),"down1"));

if ($^O =~ /win/i) {
    skip(1,1); # symlink not supported on windows
} else {
    eval { symlink ('..', 'to_dot_dot') ; };
    ok (SVN::S4::Path::fileNoLinks(catfile('to_dot_dot','down1'))
	eq catfile($uppwd,"down1"));
}
