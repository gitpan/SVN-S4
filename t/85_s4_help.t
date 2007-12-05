#!/usr/bin/perl -w
# $Id: 85_s4_help.t 48292 2007-12-05 16:48:44Z denney $
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
#
# Copyright 2002-2007 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.

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
