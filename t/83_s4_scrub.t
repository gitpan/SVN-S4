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

BEGIN { plan tests => 3 }
BEGIN { require "t/test_utils.pl"; }

our $S4 = "${PERL} ../../s4";

my $out;

chdir "test_dir/trunk" or die;

IO::File->new(">scrub_me")->close;
is(-e "scrub_me",1,"touch scrub_me");

$out = `${S4} scrub .`;
like($out,qr/Cleaning.*\nD .*scrub_me/, 's4 scrub');

is(!-e "scrub_me",1,"cleaned up scrub_me");
