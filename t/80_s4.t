#!/usr/bin/perl -w
# $Id: 80_s4.t 33487 2007-03-08 19:31:46Z wsnyder $
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
#
# Copyright 2002-2007 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.

use strict;
use Test;
use Cwd;

BEGIN { plan tests => 1 }
BEGIN { require "t/test_utils.pl"; }

run_system("${PERL} s4 info");
ok(1);
