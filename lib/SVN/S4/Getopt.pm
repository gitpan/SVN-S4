# $Id: Getopt.pm 48237 2007-12-04 19:35:20Z wsnyder $
# Author: Wilson Snyder <wsnyder@wsnyder.org>
######################################################################
#
# Copyright 2002-2007 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
######################################################################

package SVN::S4::Getopt;
require 5.006_001;

use strict;
use vars qw($AUTOLOAD $Debug);
use Carp;
use IO::File;
use Cwd;
use Data::Dumper;

######################################################################
#### Configuration Section

our $VERSION = '1.020';

our %_Aliases =
    (
     'ann'	=> 'blame',
     'annotate'	=> 'blame',
     'ci'	=> 'commit',
     'co'	=> 'checkout',
     'cp'	=> 'copy',
     'del'	=> 'delete',
     'di'	=> 'diff',
     'h'	=> 'help',
     'ls'	=> 'list',
     'mv'	=> 'move',
     'pd'	=> 'propdel',
     'pdel'	=> 'propdel',
     'pe'	=> 'propedit',
     'pedit'	=> 'propedit',
     'pg'	=> 'propget',
     'pget'	=> 'propget',
     'pl'	=> 'proplist',
     'plist'	=> 'proplist',
     'praise'	=> 'blame',
     'ps'	=> 'propset',
     'pset'	=> 'propset',
     'remove'	=> 'delete',
     'ren'	=> 'move',
     'rename'	=> 'move',
     'rm'	=> 'delete',
     'snap'	=> 'snapshot',
     'st'	=> 'status',
     'stat'	=> 'status',
     'up'	=> 'update',
     );

# List of commands and arguments.
# Forms:
#    [-switch]
#    [-switch argument]
#    nonoptional		# One parameter
#    nonoptional...		# Many parameters
#    [optional]			# One parameter
#    [optional...]		# Many parameters
# The arguments "PATH*" are specially detected by s4 for filename parsing.

our %_Args =
 (
  'add'		=> {
      s4_changed => 1,
      args => (' [--targets FILENAME]'
	       .' [-N|--non-recursive]'
	       .' [-q|--quiet]'
	       .' [--config-dir DIR]'
	       .' [--auto-props]'
	       .' [--no-auto-props]'
	       .' [--force]'
	       .' [--svn]'			# S4 addition
	       .' PATH...')},
  'blame'	=> {
      args => (' [-r|--revision REV]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--config-dir DIR]'
	       .' [--verbose]'
	       .' [--force]'			# 1.4
	       .' [-x|--extensions ARGS]'	# 1.4
	       .' PATH...')},	# PATH[@REV]
  'cat'		=> {
      args => (' [-r|--revision REV]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--config-dir DIR]'
	       .' PATH...')},	# PATH[@REV]
  'checkout'	=> {
      s4_changed => 1,
      args => (' [-r|--revision REV]'
	       .' [-q|--quiet]'
	       .' [-N|--non-recursive]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--ignore-externals]'
	       .' [--config-dir DIR]'
	       .' URL... [PATH]')},  # URL[@REV]  path will parse to be last element in {url}
  'cleanup'	=> {
      args => (' [--diff3-cmd CMD]'
	       .' [--config-dir DIR]'
	       .' [PATH...]')},
  'commit'	=> {
      args => (' [-m|--message TEXT]'
	       .' [-F|--file FILE]'
	       .' [-q|--quiet]'
	       .' [--no-unlock]'
	       .' [-N|--non-recursive]'
	       .' [--targets FILENAME]'
	       .' [--force-log]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--encoding ENC]'
	       .' [--config-dir DIR]'
	       .' [PATH...]')},
  'copy'	=> {
      args => (' [-m|--message TEXT]'
	       .' [-F|--file FILE]'
	       .' [-r|--revision REV]'
	       .' [-q|--quiet]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--force-log]'
	       .' [--editor-cmd EDITOR]'
	       .' [--encoding ENC]'
	       .' [--config-dir DIR]'
	       .' SRC DST')},
  'delete'	=> {
      args => (' [--force]'
	       .' [--force-log]'
	       .' [-m|--message TEXT]'
	       .' [-F|--file FILE]'
	       .' [-q|--quiet]'
	       .' [--targets FILENAME]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--editor-cmd EDITOR]'
	       .' [--encoding ENC]'
	       .' [--config-dir DIR]'
	       .' PATHORURL...')},
  'diff'	=> {
      args => (# 'diff [-r N[:M]]       [PATH[@REV]...]'
	       # 'diff [-r N[:M]] --old OLD-TGT[@OLDREV] [--new NEW-TGT[@NEWREV]] [PATH...]'
	       # 'diff                  OLD-URL[@OLDREV]        NEW-URL[@NEWREV]'
	       ' [-r|--revision REVS]'	#OLDREV[:NEWREV]
	       .' [--old OLDPATH]'		#PATH[@REV]
	       .' [--new NEWPATH]'		#PATH[@REV]
	       .' [-x|--extensions ARGS]'
	       .' [-N|--non-recursive]'
	       .' [--diff-cmd CMD]'
	       .' [--notice-ancestry]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--no-diff-deleted]'
	       .' [--config-dir DIR]'
	       .' [-c|--change REV]'	# 1.4
	       .' [--summarize]'	# 1.4
	       .' [--diff-u|-u]'	# 1.4
	       .' [--diff-b|-b]'	# 1.4
	       .' [--diff-w|-w]'	# 1.4
	       .' [--ignore-eol-style]'	# 1.4
	       .' [PATHORURL...]')},
  'export'	=> {
      args => (' [-r|--revision REV]'
	       .' [-q|--quiet]'
	       .' [--force]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--non-recursive]'
	       .' [--config-dir DIR]'
	       .' [--native-eol EOL]'
	       .' [--ignore-externals]'
	       .' PATHORURL [PATH]')},  # [@PEGREV]
  'help'	=> {
      args => (' [--version]'
	       .' [-q|--quiet]'
	       .' [--config-dir DIR]'
	       .' [SUBCOMMAND...]')},
  'import'	=> {
      args => (' [-m|--message TEXT]'
	       .' [-F|--file FILE]'
	       .' [-q|--quiet]'
	       .' [-N|--non-recursive]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--force-log]'
	       .' [--editor-cmd EDITOR]'
	       .' [--encoding ENC]'
	       .' [--config-dir DIR]'
	       .' [--auto-props]'
	       .' [--no-auto-props]'
	       .' [--ignore-externals]'
	       .' [PATH] URL')},
  'info'	=> {
      args => (' [-r|--revision]'
	       .' [-R|--recursive]'
	       .' [--targets FILENAME]'
	       .' [--incremental]'
	       .' [--xml]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--config-dir DIR]'
	       .' [PATH...]')},
  'list'	=> {
      args => (' [-r|--revision REV]'
	       .' [-v|--verbose]'
	       .' [-R|--recursive]'
	       .' [--incremental]'
	       .' [--xml]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--config-dir DIR]'
	       .' [PATH...]')},		# PATH[@REV]...
  'lock'	=> {
      args => (' [--targets FILENAME]'
	       .' [-m|--message TEXT]'
	       .' [-F|--file FILE]'
	       .' [--force-log]'
	       .' [--encoding ENC]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--config-dir DIR]'
	       .' [--force]'
	       .' PATH...')},
  'log'		=> {
      args => (' [-r|--revision REV]'
	       .' [-q|--quiet]'
	       .' [-v|--verbose]'
	       .' [--targets FILENAME]'
	       .' [--stop-on-copy]'
	       .' [--incremental]'
	       .' [--limit NUM]'
	       .' [--xml]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--config-dir DIR]'
	       .' PATHORURL [PATH...]')},
  'merge'	=> {
      args => (#'merge        PATHORURL1[@N]  PATHORURL2[@M]  [WCPATH]'
	       #'merge -r N:M SOURCE[@REV]                    [WCPATH]'
	       ' [-r|--revision REV]'
	       .' [-N|--non-recursive]'
	       .' [-q|--quiet]'
	       .' [--force]'
	       .' [--dry-run]'
	       .' [--diff3-cmd CMD]'
	       .' [--ignore-ancestry]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--config-dir DIR]'
	       .' [-x|--extensions ARGS]'	# 1.4
	       .' [-c|--change REV]'		# 1.4
	       .' PATHORURL...')},
  'mkdir'	=> {
      args => (' [-m|--message TEXT]'
	       .' [-F|--file FILE]'
	       .' [-q|--quiet]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--editor-cmd EDITOR]'
	       .' [--encoding ENC]'
	       .' [--force-log]'
	       .' [--config-dir DIR]'
	       .' PATHORURL...')},
  'move'	=> {
      args => (' [-m|--message TEXT]'
	       .' [-F|--file FILE]'
	       .' [-r|--revision REV]'
	       .' [-q|--quiet]'
	       .' [--force]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--editor-cmd EDITOR]'
	       .' [--encoding ENC]'
	       .' [--force-log]'
	       .' [--config-dir DIR]'
	       .' SRC DST')},
  'propdel'	=> {
      args => (#'propdel PROPNAME [PATH...]'
	       #'propdel PROPNAME --revprop -r REV [URL]'
	       ' [-q|--quiet]'
	       .' [-R|--recursive]'
	       .' [-r|--revision REV]'
	       .' [--revprop]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--config-dir DIR]'
	       .' PROPNAME [PATHORURL...]')},
  'propedit'	=> {
      args => (#'propedit PROPNAME PATH...'
	       #'propedit PROPNAME --revprop -r REV [URL]'
	       ' [-r|--revision REV]'
	       .' [--revprop]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--encoding ENC]'
	       .' [--editor-cmd EDITOR]'
	       .' [--config-dir DIR]'
	       .' PROPNAME [PATHORURL...]')},
  'propget'	=> {
      args => (#'propget PROPNAME [PATH[@REV]...]'
	       #'propget PROPNAME --revprop -r REV [URL]'
	       ' [-R|--recursive]'
	       .' [-r|--revision REV]'
	       .' [--revprop]'
	       .' [--strict]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--config-dir DIR]'
	       .' PROPNAME [PATHORURL...]')},
  'proplist'	=> {
      args => (#'proplist [PATH[@REV]...]'
	       #'proplist -revprop -r REV [URL]'
	       ' [-v|--verbose]'
	       .' [-R|--recursive]'
	       .' [-r|--revision REV]'
	       .' [-q|--quiet]'
	       .' [--revprop]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--config-dir DIR]'
	       .' PROPNAME [PATHORURL...]')},
  'propset'	=> {
      args => (#'propset PROPNAME [PROPVAL | -F VALFILE] PATH...'
	       #'propset PROPNAME --revprop -r REV [PROPVAL | -F VALFILE] [URL]'
	       ' [-F|--file FILE]'
	       .' [-q|--quiet]'
	       .' [-r|--revision REV]'
	       .' [--targets FILENAME]'
	       .' [-R|--recursive]'
	       .' [--revprop]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--encoding ENC]'
	       .' [--force]'
	       .' [--config-dir DIR]'
	       .' PROPNAME [PATHORURL...]')},
  'resolved'	=> {
      args => (' [--targets FILENAME]'
	       .' [-R|--recursive]'
	       .' [-q|--quiet]'
	       .' [--config-dir DIR]'
	       .' PATH...')},
  'revert'	=> {
      args => (' [--targets FILENAME]'
	       .' [-R|--recursive]'
	       .' [-q|--quiet]'
	       .' [--config-dir DIR]'
	       .' PATH...')},
  'status'	=> {
      args => (' [-u|--show-updates]'
	       .' [-v|--verbose]'
	       .' [-N|--non-recursive]'
	       .' [-q|--quiet]'
	       .' [--no-ignore]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--config-dir DIR]'
	       .' [--ignore-externals]'
	       .' [PATH...]')},
  'switch'	=> {
      args => (#'switch URL [PATH]'
	       #'switch --relocate FROM TO [PATH...]'
	       ' [-r|--revision REV]'
	       .' [-N|--non-recursive]'
	       .' [-q|--quiet]'
	       .' [--diff3-cmd CMD]'
	       .' [--relocate]'   # technically [--relocate FROM TO] but parser below doesn't support
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--config-dir DIR]'
	       .' ARG...')},
  'unlock'	=> {
      args => (' [--targets FILENAME]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--config-dir DIR]'
	       .' [--force]'
	       .' PATH...')},
  'update'	=> {
      s4_changed => 1,
      args => (' [-r|--revision REV]'
	       .' [-N|--non-recursive]'
	       .' [-q|--quiet]'
	       .' [--diff3-cmd CMD]'
	       .' [--username USER]'
	       .' [--password PASS]'
	       .' [--no-auth-cache]'
	       .' [--non-interactive]'
	       .' [--config-dir DIR]'
	       .' [--ignore-externals]'
	       .' [PATH...]')},
  #####
  # Commands added in S4
  'fixprop'	=> {
      s4_addition => 1,
      args => (' [-q|--quiet]'
	       .' [-R|--recursive]'		# Ignored as is default
	       .' [-N|--non-recursive]'
	       .' [--dry-run]'
	       .' [--personal]'
	       .' [PATH...]')},
  'help-summary' => {
      s4_addition => 1,
      args => ('')},
  'info-switches' => {
      s4_addition => 1,
      args => (' [PATH...]')},
  'snapshot' => {
      s4_addition => 1,
      args => (' [--no-ignore]'
               .' PATH')},
  'scrub' => {
      s4_addition => 1,
      args => (' [-r|--revision REV]'
               .' [--url URL]'
               .' [-v|--verbose]'
               . ' PATH')},
  );

#######################################################################
#######################################################################
#######################################################################

sub new {
    @_ >= 1 or croak 'usage: SVN::S4::Getopt->new ({options})';
    my $class = shift;		# Class (Getopt Element)
    $class ||= __PACKAGE__;
    my $defaults = {pwd=>Cwd::getcwd(),
		    editor=>($ENV{SVN_EDITOR}||$ENV{VISUAL}||$ENV{EDITOR}||'emacs'),
		    ssh=>($ENV{SVN_SSH}),
		    # Ours
		    fileline=>'Command_Line:0',
		};
    my $self = {%{$defaults},
		defaults=>$defaults,
		@_,
	    };
    bless $self, $class;
    return $self;
}

#######################################################################
# Option parsing

sub parameter {
    my $self = shift;
    # Parse a parameter. Return list of leftover parameters

    my @new_params = ();
    foreach my $param (@_) {
	print " parameter($param)\n" if $Debug;
	$self->{_parameter_unknown} = 1;  # No global parameters
	if ($self->{_parameter_unknown}) {
	    push @new_params, $param;
	    next;
	}
    }
    return @new_params;
}

#######################################################################
# Accessors

sub commands_sorted {
    return (sort (keys %_Args));
}

sub command_arg_text {
    my $self = shift;
    my $cmd = shift;
    return ($_Args{$cmd}{args});
}

sub command_s4_addition {
    my $self = shift;
    my $cmd = shift;
    return ($_Args{$cmd}{s4_addition});
}

sub command_s4_changed {
    my $self = shift;
    my $cmd = shift;
    return ($_Args{$cmd}{s4_changed});
}

sub _param_changed {
    my $self = shift;
    my $param = shift;
    return (($self->{$param}||"") ne ($self->{defaults}{$param}||""));
}

#######################################################################
# Methods - help

sub command_help_summary {
    my $self = shift;
    my $cmd = shift;

    my $out = "";
    my $args = $self->command_arg_text($cmd);
    while ($args =~ / *(\[[^]]+\]|[^ ]+)/g) {
	$out .= "  $1\n";
    }
    return $out;
}

#######################################################################
# Methods - parsing

sub dealias {
    my $self = shift;
    my $cmd = shift;
    return $_Aliases{$cmd}||$cmd;
}

sub parseCmd {
    my $self = shift;
    my $cmd = shift;
    my @args = @_;

    #$Debug=1;
    $cmd = $self->dealias($cmd);

    # Returns an array elements for each parameter.
    #    It's what the given argument is
    #		Switch, The name of the switch, or unknown
    my $cmdTemplate = $_Args{$cmd}{args};
    print "parseCmd($cmd @args) -> $cmdTemplate\n" if $Debug;
    my %parser;  # Hash of switch and if it gets a parameter
    my $paramNum=0;
    my $tempElement = $cmdTemplate;
    while ($tempElement) {
	$tempElement =~ s/^\s+//;
	if ($tempElement =~ s/^\[(-\S+)\]//) {
	    my $switches = $1;
	    my $name = $1 if $switches =~ /(--[---a-zA-Z0-9_]+)/;
	    foreach my $sw (split /[|]/, $switches) {
		$parser{$sw} = {what=>$name, then=>undef, more=>0,};
		print "case1. added parser{$sw} = ", Dumper($parser{$sw}), "\n" if $Debug;
	    }
	} elsif ($tempElement =~ s/^\[(-\S+)\s+(\S+)\]//) {
	    my $switches = $1;  my $then=$2;
	    my $name = $1 if $switches =~ /(--[---a-zA-Z0-9_]+)/;
	    $then = lc $name; $then =~ s/^-+//;  $then =~ s/[^a-z0-9]+/_/g;
	    foreach my $sw (split /[|]/, $switches) {
		$parser{$sw} = {what=>$name, then=>$then, more=>0,};
		print "case2. added parser{$sw} = ", Dumper($parser{$sw}), "\n" if $Debug;
	    }
	} elsif ($tempElement =~ s/^\[(\S+)\.\.\.\]//) {
	    $parser{$paramNum} = {what=>lc $1, then=>undef, more=>1,};
	    print "case3. added parser{$paramNum} = ", Dumper($parser{$paramNum}), "\n" if $Debug;
	    $paramNum++;
	} elsif ($tempElement =~ s/^\[(\S+)\]//) {
	    $parser{$paramNum} = {what=>lc $1, then=>undef, more=>0,};
	    print "case4. added parser{$paramNum} = ", Dumper($parser{$paramNum}), "\n" if $Debug;
	    $paramNum++;
	} elsif ($tempElement =~ s/^(\S+)\.\.\.//) {
	    $parser{$paramNum} = {what=>lc $1, then=>undef, more=>1,};
	    print "case5. added parser{$paramNum} = ", Dumper($parser{$paramNum}), "\n" if $Debug;
	    $paramNum++;
	} elsif ($tempElement =~ s/^(\S+)//) {
	    $parser{$paramNum} = {what=>lc $1, then=>undef, more=>0,};
	    print "case6. added parser{$paramNum} = ", Dumper($parser{$paramNum}), "\n" if $Debug;
	    $paramNum++;
	} else {
	    die "Internal %Error: Bad Cmd Template $cmd/$paramNum: $cmdTemplate,";
	}
    }
    #use Data::Dumper; print "parseCmd: ",Dumper(\%parser) if $Debug||1;

    my @out;
    my $inSwitch;
    $paramNum = 0;
    my $inFlags = 1;
    foreach my $arg (@args) {
	if ($inFlags && $arg =~ /^-/) {
	    if ($arg eq "--") {
		$inFlags = 0;
	    } elsif ($parser{$arg}) {
		push @out, $parser{$arg}{what};
		$inSwitch = $parser{$arg}{then};
	    } else {
		push @out, "unknown";
	    }
	} else {
	    if ($inSwitch) {   # Argument to a switch
		push @out, $inSwitch;
		$inSwitch = 0;
	    } elsif ($parser{$paramNum}) {  # Named [optional?] argument
		push @out, $parser{$paramNum}{what};
		$paramNum++ if !$parser{$paramNum}{more};
	    } else {
		push @out, "unknown";
	    }
	}
    }
    return @out;
}

sub expand_single_dash_args {
    my $self = shift;
    my @out;
    #$Debug=1;
    foreach my $arg (@_) {
        if ($arg =~ /^(-[A-Za-z])(.+)/) {
	    print "Expanding single-dash arg: $arg\n" if $Debug;
	    push @out, ($1,$2);
	} elsif ($arg =~ /^(-[^=]+)=(.+)/) {
	    print "Expanding option argument with equals: $arg\n" if $Debug;
	    push @out, ($1,$2);
	} else {
	    push @out, $arg;
	}
    }
    return @out;
}

sub hashCmd {
    my $self = shift;
    my $cmd = shift;
    my @args = @_;

    # if any single-dash args like "-r2000", expand them into "-r" and "2000"
    # before parsing.
    @args = $self->expand_single_dash_args (@args);

    my %hashed;
    my @cmdParsed = $self->parseCmd($cmd, @args);
    #use Data::Dumper; print "hashCmd: ",Dumper(\@args, \@cmdParsed);
    for (my $i=0; $i<=$#cmdParsed; $i++) {
	die if !defined $cmdParsed[$i];
	if ($cmdParsed[$i] =~ /^(-.*)$/) {
	    $hashed{$1} = 1;
	} else {
	    if (!ref $hashed{$cmdParsed[$i]}) {
		$hashed{$cmdParsed[$i]} = [$args[$i]];
	    } else {
		push @{$hashed{$cmdParsed[$i]}}, $args[$i];
	    }
	}
    }
    return %hashed;
}

sub stripOneArg {
    my $self = shift;
    my $switch = shift;
    my @args = @_;
    my @out;
    foreach my $par (@args) {
	push @out, $par unless $par eq $switch;
    }
    return @out;
}

#######################################################################

sub AUTOLOAD {
    my $self = $_[0];
    my $func = $AUTOLOAD;
    $func =~ s/.*:://;
    if (exists $self->{$func}) {
	eval "sub $func { \$_[0]->{'$func'} = \$_[1] if defined \$_[1]; return \$_[0]->{'$func'}; }; 1;" or die;
	goto &$AUTOLOAD;
    } else {
	croak "Undefined ".__PACKAGE__." subroutine $func called,";
    }
}

sub DESTROY {}

######################################################################
### Package return
1;
__END__

=pod

=head1 NAME

SVN::S4::Getopt - Get Subversion command line options

=head1 SYNOPSIS

  use SVN::S4::Getopt;
  my $opt = new SVN::S4::Getopt;
  ...
=head1 DESCRIPTION

The L<SVN::S4::Getopt> package provides standardized handling of global options
for the front of svn commands.

=over 4

=item $opt = SVN::S4::Getopt->new ( I<opts> )

Create a new Getopt.

=back

=head1 ACCESSORS

There is a accessor for each parameter listed above.  In addition:

=over 4

=item $self->commands_sorted()

Return sorted list of all commands.

=item $self->command_arg_text(<cmd>)

Return textual description of the specified command.

=item $self->command_s4_addition(<cmd>)

Return true if the command is only in s4.

=item $self->command_s4_changed(<cmd>)

Return true if the command is modified from normal SVN operation by s4.

=item $self->fileline()

The filename and line number last parsed.

=item $self->hashCmd(<cmd>, <opts>)

Return a hash with one key for each option.  The value of the key is 1 if a
no-argument option was set, else it is an array with each value the option
was set to.

=item $self->parseCmd(<cmd>, <opts>)

Return a array with one element for each option.  The element is either
'switch', the name of the switch the option is specifying, or the name of
the parameter.

=item $self->stripOneArg(-<arg>, <opts>...)

Return the option list, with the specified matching argument removed.

=back

=head1 DISTRIBUTION

The latest version is available from CPAN and from L<http://www.veripool.com/>.

Copyright 2002-2007 by Wilson Snyder.  This package is free software; you
can redistribute it and/or modify it under the terms of either the GNU
Lesser General Public License or the Perl Artistic License.

=head1 AUTHORS

Wilson Snyder <wsnyder@wsnyder.org>

=head1 SEE ALSO

L<SVN::S4>

=cut
