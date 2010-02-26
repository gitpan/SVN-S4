#!/usr/bin/perl -w
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
#
# Copyright 2002-2010 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# Lesser General Public License Version 3 or the Perl Artistic License Version 2.0.

use strict;
use Test;
use Cwd;

BEGIN { plan tests => 4 }
BEGIN { require "t/test_utils.pl"; }

run_system("${PERL} s4 help");
ok(1);

run_system("${PERL} s4 help add");  # Modified cmd
ok(1);

run_system("${PERL} s4 help fixprop");  # New cmd
ok(1);

run_system("${PERL} s4 help rm");  # Unchanged cmd
ok(1);
