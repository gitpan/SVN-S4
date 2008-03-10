# $Id: ViewSpec.pm 51887 2008-03-10 13:46:15Z wsnyder $
# Author: Bryce Denney <bryce.denney@sicortex.com>
######################################################################
#
# Copyright 2005-2008 by Bryce Denney.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
######################################################################
#

package SVN::S4::ViewSpec;
require 5.006_001;

use SVN::S4;
use strict;
use Carp;
use IO::Dir;
use IO::File;
use Cwd;
use Digest::MD5;
use vars qw($AUTOLOAD);

use SVN::S4::Path;

our $VERSION = '1.030';
our $Info = 1;


#######################################################################
# Methods

#######################################################################
#######################################################################
#######################################################################
#######################################################################
# OVERLOADS of S4 object
package SVN::S4;

our @list_actions;

sub vsdebug {
    if ($SVN::S4::Debug) {
        my $string = shift;
	print "s4: $string\n";
    }
}

sub info {
    if ($Info) {
        my $string = shift;
	print "s4: $string\n";
    }
}

sub error {
    my $string = shift;
    warn "%Error: $string\n";
    exit 1;
}

sub viewspec_hash {
    my $self = shift;
    my $text_to_hash = "";
    foreach (@list_actions) {
        $text_to_hash .= "$_->{cmd} $_->{url} $_->{dir}\n";
	# just omit rev.
    }
    my $viewspec_hash = Digest::MD5::md5_hex($text_to_hash);
    #print "s4: viewspec is $viewspec_hash\n";
    return $viewspec_hash;
}

sub viewspec_changed {
    my $self = shift;
    my %params = (#path=>
                  @_);
    my $vshash = $self->viewspec_hash;
    $self->read_viewspec_state (path=>$params{path});
    if (!defined $self->{prev_state}) { return 1; } # if not found, return true.
    my $oldhash = $self->{prev_state}->{viewspec_hash} || "not found";
    if (!defined $oldhash) { return 1; } # if not found, return true.
    print "s4: Compare hash '$vshash' against old '$oldhash'\n" if $self->debug;
    return ($vshash ne $oldhash);
}

sub parse_viewspec {
    my $self = shift;
    my %params = (#filename=>,
		  #revision=>,
                  @_);
    my $fn = $params{filename};
    # NOTE: parse_viewspec must be called with revision parameter.
    # But when a viewspec includes another viewspec, this function will be 
    # called again and revision will be undefined.
    $self->{revision} = $params{revision} if $params{revision};
    # Remember the top level viewspec file. When doing an include, the included
    # file is relative to the top level one.
    $self->{viewspec_path} = $params{filename} if !$self->{viewspec_path};
    print "s4: params{revision} = $params{revision}\n" if $self->debug && $params{revision};
    print "s4: now my revision variable is $self->{revision}\n" if $self->debug && $self->{revision};
    my $fh = new IO::File;
    if ($fn =~ m%://%) {
        # treat it as an svn url
	$fh->open ("svn cat $fn |") or die "%Error: cannot run svn cat $fn";
    } else {
	# When opening an include file, we search relative to the top level
	# viewspec filename.  If it's not an absolute path, prepend the directory
	# part of the top level viewspec name.
	if ($fn !~ m%^/%) {
	    my @dirs = File::Spec->splitdir ($self->{viewspec_path});
	    pop @dirs;
	    push @dirs, File::Spec->splitdir ($fn);
	    my $candidate = File::Spec->catdir (@dirs);
	    print "s4: Making $fn relative to $self->{viewspec_path}. candidate is $candidate\n" if $self->debug;
	    # if the file exists, accept the $candidate
	    $fn = $candidate if (-f $candidate);
	}
	$fh->open ("< $fn") or die "%Error: cannot open file $fn";
    }
    while (<$fh>) {
        s/#.*//;       # hash mark means comment to end of line
	s/^\s+//;      # remove leading space
	s/\s+$//;      # remove trailing space
	next if /^$/;  # remove empty lines
	#vsdebug ("viewspec: $_");
	$self->parse_viewspec_line ($_);
    }
    $fh->close;
}

sub parse_viewspec_line {
    my $self = shift;
    my $line = shift;
    my @args = split(/\s+/, $line);
    $self->expand_viewspec_vars (\@args);
    my $cmd = shift @args;
    if ($cmd eq 'view') {
        $self->viewspec_cmd_view (@args);
    } elsif ($cmd eq 'unview') {
        $self->viewspec_cmd_unview (@args);
    } elsif ($cmd eq 'include') {
        $self->viewspec_cmd_include (@args);
    } elsif ($cmd eq 'set') {
        $self->viewspec_cmd_set (@args);
    } else {
	if ($line =~ /(>>>>>>|<<<<<<|======)/) {
	    die "%Error: Error parsing viewspec. It looks like Project.viewspec has SVN conflict markers in it!";
	}
        die "%Error: Unrecognized command in Project.viewspec: '$cmd'";
    }
}

sub expand_viewspec_vars {
    my $self = shift;
    my $listref = shift;
    my %vars;
    for (my $i=0; $i<=$#$listref; $i++) {
	my $foo;
        #vsdebug "before substitution: $listref->[$i]";
	$listref->[$i] =~ s/\$([A-Za-z0-9_]+)/$self->{viewspec_vars}->{$1}/g;
	#vsdebug "after substitution: $listref->[$i]";
    }
}

sub viewspec_cmd_view {
    my $self = shift;
    my ($url, $dir, $revtype, $rev) = @_;
    $revtype = "" if !defined $revtype;
    $rev = "" if !defined $rev;
    vsdebug "cmd_view: url=$url  dir=$dir  revtype=$revtype  rev=$rev";
    if (!defined $url || !defined $dir) {
        error("view command requires URL and DIR argument");
    }
    # check syntax of revtype,rev
    if ($revtype eq 'rev') {
        # string in $rev should be a revision number
    } elsif ($revtype eq 'date') {
        $self->ensure_valid_date_string($rev);
	$rev = "{$rev}";
	$rev = $self->rev_on_date(url=>$url, date=>$rev);
    } elsif ($self->{revision}) {
	$rev = $self->{revision};
    } else {
        die "%Error: parsing view line in viewspec, but revision variable is missing";
    }
    $self->ensure_valid_rev_string($rev);
    # if there is already an action on this directory, abort.
    foreach (@list_actions) {
        if ($dir eq $_->{dir}) {
	    die "%Error: In Project.viewspec, one view line collides with a previous one for directory '$dir'. You must either remove one of the view commands or add an 'unview' command before it.";
	}
    }
    my $action;
    $action->{cmd} = "switch";
    $action->{url} = $url;
    $action->{dir} = $dir;
    $action->{rev} = $rev;
    push @list_actions, $action;
}

sub viewspec_cmd_unview {
    my $self = shift;
    my ($dir) = @_;
    vsdebug "viewspec_cmd_unview: dir=$dir";
    my $ndel = 0;
    for (my $i=0; $i <= $#list_actions; $i++) {
	my $cmd = $list_actions[$i]->{cmd};
	my $actdir = $list_actions[$i]->{dir};
	vsdebug "checking $cmd on $actdir";
        if ($cmd eq 'switch' && $actdir =~ /^$dir/) {
	    vsdebug "deleting action=$cmd on dir=$dir";
	    #vsdebug "before deleting, list was " . Dumper(\@list_actions);
	    splice (@list_actions, $i, 1);
	    #vsdebug "after deleting, list was " . Dumper(\@list_actions);
	    $ndel++;
	}
    }
}

sub viewspec_cmd_include {
    my $self = shift;
    my ($file) = @_;
    vsdebug "viewspec_cmd_include $file";
    $self->{parse_viewspec_include_depth}++;
    error "Excessive viewspec includes. Is this infinite recursion?" 
         if $self->{parse_viewspec_include_depth} > 100;
    $self->parse_viewspec (filename=>$file);
    $self->{parse_viewspec_include_depth}--;
}

sub viewspec_cmd_set {
    my $self = shift;
    my ($var,$value) = @_;
    vsdebug "viewspec_cmd_set $var = $value";
    $self->{viewspec_vars}->{$var} = $value;
}

# Call with $s4->viewspec_compare_rev($rev)
# Compares every action in the viewspec against $rev, and returns true
# if every part of the tree will be switched to $rev.  If any rev mismatches,
# returns false.
sub viewspec_compare_rev {
    my $self = shift;
    my ($rev_to_match) = @_;
    foreach my $action (@list_actions) {
	my $rev = $action->{rev};
	if ($rev ne $rev_to_match) {
	    return undef; # found inconsistent revs, return false
	}
    }
    return 1;  # all revs were the same, return true
}

sub sort_by_dir {
    return $a->{dir} cmp $b->{dir};
}

sub apply_viewspec {
    my $self = shift;
    my %params = (#path=>,
                  @_);
    vsdebug "revision is $self->{revision}" if $self->{revision};
    $self->{viewspec_managed_switches} = [];  # ref to empty array
    my $base_uuid;
    foreach my $action (sort sort_by_dir @list_actions) {
	my $dbg = "Action: ";
        foreach my $key (sort keys %$action) {
	    $dbg .= "$key=$action->{$key} ";
	}
	vsdebug ($dbg);
	unless ($base_uuid) {
	    my $base_url = $self->file_url (filename=>$params{path});
	    $base_uuid = $self->client->uuid_from_url ($base_url);
	    print "Base repository UUID is $base_uuid\n" if $self->debug;
	}
	my $cmd = "";
	if ($action->{cmd} eq 'switch') {
	    my $reldir = $action->{dir};
	    push @{$self->{viewspec_managed_switches}}, $reldir;
	    if (!-e "$params{path}/$reldir") {
	        # Directory does not exist yet. Use the voids trick to create
		# a versioned directory there that is switched to an empty dir.
		print "s4: Creating empty directory to switch into: $reldir\n";
		my $basedir = $params{path};
		$self->create_switchpoint_hierarchical($basedir, $reldir);
	    }
	    my $rev = $action->{rev};
	    if ($rev eq 'HEAD') {
	        die "%Error: with '-r HEAD' in the viewspec actions list, the tree can have inconsistent revision numbers. This should not happen.";
	    }

	    my $url = $self->file_url(filename=>"$params{path}/$reldir");
	    my $verb;
	    my $cleandir = $self->clean_filename("$params{path}/$reldir");
	    if ($url && $url eq $action->{url}) {
		$cmd = "$self->{svn_binary} update $cleandir -r$rev";
		$verb = "Updating";
	    } else {
		if (!$self->is_file_in_repo(url=>$action->{url}, revision=>$rev)) {
		    die "%Error: Cannot switch to nonexistent URL: $action->{url}";
		}
		my $uuid = $self->client->uuid_from_url($action->{url});
		if ($uuid ne $base_uuid) {
		    die "%Error: URL $action->{url} is in a different repository! What you need is an SVN external, which viewspecs presently do not support.";
		}
		$cmd = "$self->{svn_binary} switch $action->{url} $cleandir -r$rev";
		$verb = "Switching";
	    }
	    if (!$self->quiet) {
		print "s4: $verb $reldir";
		if ($verb eq 'Switching') {
		    print " to $action->{url}";
		    print " rev $rev" if $rev ne 'HEAD';
		}
		print "\n";
	    }
	} else {
	    error "unknown command '$action";
	}
	$self->run ($cmd);
    }
    # Look for any switch points that S4 __used to__ maintain, but no longer does.
    # Undo those switch points, if possible.
    $self->undo_switches (basepath=>$params{path});
    # Set viewspec hash in the S4 object.  The caller MAY decide to save the 
    # state by calling $self->save_viewspec_state, or not.
    $self->{viewspec_hash} = $self->viewspec_hash;
}

sub undo_switches {
    my $self = shift;
    my %params = (#basepath=>,
                  @_);
    # Find the list of switchpoints that S4 created
    # If it can't be found, just return.
    if (!$self->{prev_state}) {
        print "s4: undo_switches cannot find prev_state, giving up\n" if $self->debug;
	return;
    }
    if (!$self->{prev_state}->{viewspec_managed_switches}) {
        print "s4: undo_switches cannot find previous list of viewspec_managed_switches, giving up\n" if $self->debug;
	return;
    }
    my @prevlist = sort @{$self->{prev_state}->{viewspec_managed_switches}};
    my @thislist = sort @{$self->{viewspec_managed_switches}};
    print "s4: prevlist: ", join(' ',@prevlist), "\n" if $self->debug;
    print "s4: thislist: ", join(' ',@thislist), "\n" if $self->debug;
    foreach my $dir (@prevlist) {
	# I'm only interested in directories that were in @prevlist but
	# are not in @thislist.  If dir is in both lists, quit.
        next if grep(/^$dir$/, @thislist);
	if (grep(/^$dir/, @thislist)) {
	    # There is another mountpoint in @thislist that starts
	    # with $dir, in other words there is a mountpoint underneath
	    # this one.  We can't remove the dir, but leave it in the
	    # state file, so we can remove it when we have the chance.
	    print "s4: Remember that we manage $dir\n" if $self->debug;
	    push @{$self->{viewspec_managed_switches}}, $dir;
	    next;
	}
	print "s4: Remove unused switchpoint $dir\n";
	$self->remove_switchpoint (dir=>$dir, basepath=>$params{basepath});
    }
}

sub remove_switchpoint {
    my $self = shift;
    my %params = (#basepath=>,
		  #dir=>,
                  @_);
    # The algorithm is:
    # 1. svn switch it to an empty directory, e.g. REPO/void
    # 2. svn status --no-ignore in the directory.  If it is totally empty, then
    #    3. rm -rf directory, so that we forget that the dir was ever switched
    #    4. svn up directory, which makes it disappear from the parent
    my $dirpart = $params{dir};
    $dirpart =~ s/.*\///;
    my $path = "$params{basepath}/$params{dir}";
    my $abspath = $self->abs_filename($path);
    if (! -d $abspath) {
        print "Switchpoint $path has already been removed.\n" if $self->debug;
	return;
    }
    my $url = $self->file_url(filename=>$path);
    my $voidurl = $self->void_url(url => $url);
    my $cmd = qq{$self->{svn_binary} switch --quiet $voidurl $path};
    $self->run($cmd);
    # Is it totally empty?
    my $status_items = 0;
    print "s4: Checking if $path is completely empty\n" if $self->debug;
    my $stat = $self->client->status
	($abspath,			# path
	 "WORKING",			# revision
	 sub { $status_items++; print Dumper(@_) if $self->debug; }, 	# status func
	 1,				# recursive
	 1,				# get_all
	 0,				# update
	 1,				# no_ignore
     );
     print "status returned $status_items item(s)\n" if $self->debug;
     # For a totally empty directory, status returns just one thing: the
     # directory itself.
     if ($status_items==1) {
	print "s4: Removing $path from working area\n" if $self->debug;
	 # Do it gently to reduce chance of wiping out. Only use the big hammer on
	 # the .svn directory itself.  This may "fail" because of leftover .nfs crap;
	 # then what's the right answer?
         $self->run ("rm -rf $path/.svn");
         $self->run ("rmdir $path"); 
	 print "s4: running svn update -r $self->{revision} on $abspath\n" if $self->debug;
	 $self->run ("svn up -N --revision $self->{revision} $path");
     } else {
         print "s4: Ignoring obsolete switchpoint $path because there are still files under it.\n";
         print "s4: If you remove those files, you can remove the switchpoint manually, by deleting\n";
         print "s4: the directory and updating again.\n";
     }
}

sub create_switchpoint_hierarchical {
    my $self = shift;
    my ($basedir,$reldir) = @_;
    my $path = "";
    my @dirparts = split ('/', $reldir);
    for (my $i=0; $i <= $#dirparts; $i++) {
	my $dirpart = $dirparts[$i];
	my $last_time_through = ($i == $#dirparts);
	print "s4: does '$dirpart' exist in $basedir? if not, make it\n" if $self->debug;
	if (! -e "$basedir/$dirpart") {
	    # Q: Why is voidurl in a loop?  It takes 1-2 seconds!?
	    # A: I don't want to compute void_url unless it is
	    # really needed.  And the value gets cached, so the
	    # 2nd, 3rd, etc. call takes no time.
	    my $voidurl = $self->void_url(url => $self->file_url(filename=>$basedir));
	    $self->create_switchpoint ($basedir,$dirpart);
	    unless ($last_time_through) {
		$self->run ("$self->{svn_binary} switch --quiet $voidurl $basedir/$dirpart");
		$self->wait_for_existence (path=>"$basedir/$dirpart");
		push @{$self->{viewspec_managed_switches}},
		    $self->clean_filename("$basedir/$dirpart");
	    }
	}
	$basedir .= "/" . $dirpart;
    }
}

sub create_switchpoint {
    my $self = shift;
    my ($basedir,$targetdir) = @_;
    print "s4: create_switchpoint $targetdir from basedir $basedir\n" if $self->debug;
    # Ok, we're going to do something really bizarre to work around a
    # svn limitation.  We want to create an svn switched directory, even if
    # there is no such directory in our working area.  Normally SVN does not
    # allow this unless you svn mkdir a directory and check it in.  But if
    # you artifically add a directory in .svn/entries, then you can switch
    # it to anything you want.  Strange but useful.
    # This hack is specific to the working copy format, so check that the working
    # copy format is one that I recognize.
    my $format_file = "$basedir/.svn/format";
    open (FMT, $format_file) or die "%Error: $! opening $format_file";
    my $fmt = <FMT>;
    chomp $fmt;
    if ($fmt != 4 && $fmt != 8) {
        die "%Error: create_switchpoint: I only know how to create switchpoints in working copy format=4 or format=8. But this working copy is format " . (0+$fmt);
    }
    my $entries_file = "$basedir/.svn/entries";
    # hacky way first, to show if it works.
    # the right way is to use an XML parser.
    my $newfile = "$basedir/.svn/s4_tmp_$$";
    $self->run("rm -rf $basedir/.svn/s4_tmp_*");
    open (IN, $entries_file) or die "%Error: $! opening $entries_file";
    open (OUT, ">$newfile") or die "%Error: $! opening $newfile";
    die "%Error: can't make a switchpoint with a quote in it!" if $targetdir =~ /"/;
    while (<IN>) {
	if ($fmt == 4) {
	    if (/name="$targetdir"/) {
		die "%Error: create_switchpoint: an entry called '$targetdir' already exists in .svn/entries";
	    }
	    if (/<\/wc-entries>/) {
		# Fmt=4: Just before the </wc-entries> line, add this entry
		print OUT qq{<entry name="$targetdir" kind="dir"/> \n};
	    }
	} elsif ($fmt == 8) {
	    if (/^$targetdir/) {
		die "%Error: create_switchpoint: an entry called '$targetdir' already exists in .svn/entries";
	    }
	}
	print OUT;
    }
    if ($fmt == 8) {
	# Fmt=8: Right at the end, add this.
        print OUT "$targetdir\ndir\n" . chr(12) . "\n";
    }
    $self->run ("/bin/mv -f $newfile $entries_file");
}

######################################################################
### Package return
package SVN::S4::ViewSpec;
1;
__END__

=pod

=head1 NAME

SVN::S4::ViewSpec - behaviors related to viewspecs

=head1 SYNOPSIS

Scripts:
  use SVN::S4::ViewSpec;
  $svns4_object->parse_viewspec(filename=>I<filename>, revision=>I<revision>);
  $svns4_object->apply_viewspec(filename=>I<filename>);

=head1 DESCRIPTION

SVN::S4::ViewSpec implements parsing viewspec files and performing the
svn updates and svn switches required to make your working copy match the
viewspec file.

A viewspec file format is a text file containing a series of one-line
commands.  Anything after a # character is considered a comment. 
Whitespace and blank lines are ignored.  The commands must be one of:

  set  VAR   VALUE
    Set environment variable VAR to VALUE.  This is useful for
    making abbreviations to be used within the viewspec file, for
    frequently typed things such as the name of the svn repository.

  include FILE
    Read another file that contains viewspec commands.
    If the filename does not begin with a slash, it is considered
    to be relative to the directory containing the Project.viewspec.

  include URL
    Read a file out of the SVN repository that contains viewspec commands.

  view URL DIR
    Directory DIR will be svn switched to URL.

  view URL DIR rev REVNUM
    Directory DIR will be svn switched to URL at revision REVNUM.
    Note that this is not "sticky" the way CVS was.  Svn updates
    will override the revision number, while s4 update will not.

    REVNUM can also be a date in normal subversion format, as listed here:
    http://svnbook.red-bean.com/nightly/en/svn-book.html#svn.tour.revs.dates
    Example:  view URL DIR rev {2006-07-01}

  unview DIR
    Ignore any view/unview commands that came above, for directories
    that begin with DIR.  This may be useful if you have included
    a viewspec and want to override some of its view commands.

=head1 METHODS

=over 4

=item $s4->parse_viewspec(parse_viewspec(filename=>I<filename>, revision=>I<revision>);

Parse_viewspec reads the file specified by FILENAME, and builds up
a list of svn actions that are required to build the working area.
The actions are stored in @list_actions, and each one is a hash 
containing a command, a directory, etc.

The revision parameter is used as the default revision number for
all svn operations, unless the viewspec file has a "rev NUM" clause
that overrides the default.

=item $s4->apply_viewspec

For each of the svn actions in @list_actions, perform the actions.
An example of an action is to run svn switch on the Foo directory
the the URL Bar at revision 50.

=back

=head1 DISTRIBUTION

The latest version is available from CPAN and from L<http://www.veripool.org/>.

Copyright 2005-2008 by Bryce Denney.  This package is free software; you
can redistribute it and/or modify it under the terms of either the GNU
Lesser General Public License or the Perl Artistic License.

=head1 AUTHORS

Bryce Denney <bryce.denney@sicortex.com>

=head1 SEE ALSO

L<SVN::S4>

=cut
