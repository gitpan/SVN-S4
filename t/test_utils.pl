# DESCRIPTION: Perl ExtUtils: Common routines required by package tests
#
# Copyright 2002-2013 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# Lesser General Public License Version 3 or the Perl Artistic License Version 2.0.

use File::Find;
use IO::File;
use Cwd;
use vars qw($PERL $REPO $REPOFN);

if ($ENV{S4_SVN}) {
    print "unsetenv S4_SVN\n";
    delete $ENV{S4_SVN};   # Don't complicate matters
}

$PERL = "$^X -Iblib/arch -Iblib/lib";
$REPOFN = getcwd()."/test_dir/repo";
$REPO = "file://localhost$REPOFN";

mkdir 'test_dir',0777;

if (!$ENV{HARNESS_ACTIVE}) {
    use lib '.';
    use lib '..';
    use lib "blib/lib";
    use lib "blib/arch";
}

sub run_system {
    # Run a system command, check errors
    my $command = shift;
    print "\t$command\n";
    system "$command";
    my $status = $?;
    ($status == 0) or die "%Error: Command Failed $command, $status, stopped";
}

sub wholefile {
    my $file = shift;
    my $fh = IO::File->new ($file) or die "%Error: $! $file";
    my $wholefile = join('',$fh->getlines());
    $fh->close();
    return $wholefile;
}

sub files_identical {
    my $fn1 = shift;
    my $fn2 = shift;
    my $f1 = IO::File->new ($fn1) or die "%Error: $! $fn1,";
    my $f2 = IO::File->new ($fn2) or die "%Error: $! $fn2,";
    my @l1 = $f1->getlines();
    my @l2 = $f2->getlines();
    my $nl = $#l1;  $nl = $#l2 if ($#l2 > $nl);
    for (my $l=0; $l<$nl; $l++) {
	if (($l1[$l]||"") ne ($l2[$l]||"")) {
	    warn ("%Warning: Line ".($l+1)." mismatches; $fn1 != $fn2\n"
		  ."F1: ".($l1[$l]||"*EOF*\n")
		  ."F2: ".($l2[$l]||"*EOF*\n"));
	    return 0;
	}
    }
    return 1;
}

sub write_text {
    my $filename = shift;
    my $text = shift;

    my $fh = IO::File->new($filename,"w");
    if (!$fh) {
	warn "%Warning: $! $filename,";
    }
    print $fh $text;
    $fh->close();
}

sub file_list {
    my $dir = shift;
    local %files;
    find({ wanted => sub {
	return if /\.svn/;
	$files{$_} = 1;
    }, follow => 0, no_chdir => 1 }, $dir);
    my @out = sort keys %files;
    return \@out;
}

sub like_cmd ($$) {
    my $cmd = shift;
    my $regexp = shift;
    my $tb = Test::More->builder;
    my $out = `$cmd`;
    (my $tell_cmd = $cmd) =~ s/^${PERL} *//;
    $tb->like($out, $regexp, $tell_cmd);
}

sub is_cmd ($$) {
    my $cmd = shift;
    my $regexp = shift;
    my $tb = Test::More->builder;
    my $out = `$cmd`;
    (my $tell_cmd = $cmd) =~ s/^${PERL} *//;
    $tb->is_eq($out, $regexp, $tell_cmd);
}

1;
