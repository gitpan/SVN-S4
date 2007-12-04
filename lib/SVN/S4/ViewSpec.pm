# $Id: ViewSpec.pm 48237 2007-12-04 19:35:20Z wsnyder $
# Author: Bryce Denney <bryce.denney@sicortex.com>
######################################################################
#
# Copyright 2005-2007 by Bryce Denney.  This program is free software;
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
# One of the important data structures in this file is the viewspec_tree,
# which is a tree of directory objects, one for each item described in
# the viewspec file.  Later, when we're deciding which checkout/update/switch
# operations are needed, some other directory objects are added that represent
# other dirs in the repository.  Here is the structure
#
# Top of tree is: $self->{viewspec_tree}
#
# Each node is a hashref with a few common keys:
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

use SVN::S4;
use SVN::S4::Path;

our $VERSION = '1.020';


#######################################################################
# Methods

#######################################################################
#######################################################################
#######################################################################
#######################################################################
# OVERLOADS of S4 object
package SVN::S4;

our @vsmap;

sub viewspec_hash {
    my $self = shift;
    my $text_to_hash = "";
    foreach (@vsmap) {
        $text_to_hash .= ($_->{cmd}||"") . ($_->{url}||"") . ($_->{dir}||"");
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
    # called recursively and revision will be undefined.
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
	#$self->dbg ("viewspec: $_");
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
        #$self->dbg ("before substitution: $listref->[$i]");
	$listref->[$i] =~ s/\$([A-Za-z0-9_]+)/$self->{viewspec_vars}->{$1}/g;
	#$self->dbg ("after substitution: $listref->[$i]");
    }
    # FIXME: One ugly thing about the way it works is that if the user uses a variable 
    # that's undefined, you get unhelpful perl warnings instead of a good error message.
}

sub add_to_vsmap {
    my $self = shift;
    my %params = (#item=>,
                  #override=>,
                  @_);
    # This item replaces any previous item that matches it, e.g.
    #  1. map a/b/c to url1
    #  2. map a/b to url2    replaces #1
    #  3. map a/b/c to url3  does not replace
    # Delete any item whose directory matches this one.
    my @delete_indices;
    my $i;
    for ($i=0; $i <= $#vsmap; $i++) {
	my $cmd = $vsmap[$i]->{cmd};
	my $actdir = $vsmap[$i]->{dir};
	$self->dbg ("checking $cmd on $actdir");
        if ($actdir =~ /^$params{item}->{dir}/) {
	    if ($params{override} || $cmd eq 'unmap') {
		# If override is set, then you are allowed to override.
		# Anybody is allowed to override an unmap command.
		$self->dbg ("deleting action=$cmd on dir=$actdir");
		push @delete_indices, $i;
	    } else {
	        $self->error("view line for dir '$params{item}->{dir}' collides with previous line for dir '$vsmap[$i]->{dir}'");
	    }
	}
    }
    foreach $i (sort {$b<=>$a} @delete_indices) {
	splice (@vsmap, $i, 1);
    }
    push @vsmap, $params{item};
    #### add to viewspec tree
}

sub viewspec_cmd_view {
    my $self = shift;
    my ($url, $dir, $revtype, $rev) = @_;
    $revtype = "" if !defined $revtype;
    $rev = "" if !defined $rev;
    $self->dbg ("cmd_view: url=$url  dir=$dir  revtype=$revtype  rev=$rev");
    if (!defined $url || !defined $dir) {
        $self->error("view command requires URL and DIR argument");
    }
    # check syntax of revtype,rev
    if ($revtype eq 'rev') {
        # string in $rev should be a revision number
    } elsif ($revtype eq 'date') {
        $self->ensure_valid_date_string($rev);
	$rev = "{$rev}";
	$rev = $self->rev_on_date(url=>$url, date=>$rev);
    } elsif ($revtype ne '') {
	$self->error("Illegal syntax of view line 'view " . join(" ",@_) ."'. Expected view URL DIR [rev REVNUM].");
    } elsif (!defined $self->{revision}) {
        die "%Error: parsing view line in viewspec, but revision variable is missing";
    } else {
	# no revnum argument, so use the default rev for this run
	$rev = $self->{revision};
    }
    $self->ensure_valid_rev_string($rev);
    my $item = { cmd=>'map', url=>$url, dir=>$dir, rev=>$rev };
    $self->add_to_vsmap(item=>$item, override=>0);
}

sub viewspec_cmd_unview {
    my $self = shift;
    my ($dir) = @_;
    $self->dbg ("viewspec_cmd_unview: dir=$dir");
    my $ndel = 0;
    my $item = { cmd=>'unmap', dir=>$dir };
    $self->add_to_vsmap (item=>$item, override=>1);
}

sub viewspec_cmd_include {
    my $self = shift;
    my ($file) = @_;
    $self->dbg ("viewspec_cmd_include $file");
    $self->{parse_viewspec_include_depth}++;
    $self->error ("Excessive viewspec includes. Is this infinite recursion?")
         if $self->{parse_viewspec_include_depth} > 100;
    $self->parse_viewspec (filename=>$file);
    $self->{parse_viewspec_include_depth}--;
}

sub viewspec_cmd_set {
    my $self = shift;
    my ($var,$value) = @_;
    $self->dbg ("viewspec_cmd_set $var = $value");
    $self->{viewspec_vars}->{$var} = $value;
}

########################################################################

# Call with $s4->viewspec_compare_rev($rev)
# Compares every action in the viewspec against $rev, and returns true
# if every part of the tree will be switched to $rev.  If any rev mismatches,
# returns false.
sub viewspec_compare_rev {    # DEPRECATED
    my $self = shift;
    my ($rev_to_match) = @_;
    foreach my $action (@vsmap) {
	my $rev = $action->{rev};
	if ($rev ne $rev_to_match) {
	    return undef; # found inconsistent revs, return false
	}
    }
    return 1;  # all revs were the same, return true
}

sub lookup_mapping {
    my $self = shift;
    my %params = (#wcpath=>,
                  @_);
    my $longest_match = -1;
    my $match;
    my $url;
    my $rev;
    foreach my $item (@vsmap) {
        print "Comparing $params{wcpath} with map item: ", Dumper($item), "\n" if $self->debug>1;
	if ($params{wcpath} =~ /^$item->{dir}/) {
	    if (length $item->{dir} > $longest_match) {
	        $longest_match = length $item->{dir};
		$match = $item;
		if ($item->{cmd} eq 'map') {
		    # it's a match. is it the longest match?
		    my $nonmatching = substr ($params{wcpath}, $longest_match);
		    $nonmatching =~ s/^\/*//;  # remove leading slash
		    $self->dbg("nonmatching part is $nonmatching");
		    $url = $item->{url};
		    $url .= "/" . $nonmatching if length $nonmatching > 0;
		    $rev = $item->{rev};
		} elsif ($item->{cmd} eq 'unmap') {
		    undef $url;
		    undef $rev;
		} else {
		    $self->error ("unknown cmd in vsmap '$item->{cmd}'");
		}
	    }
	}
    }
    if (!defined $url || !defined $rev) {
	return;
        #$self->error("wcpath '$params{wcpath}': did not match anything");
    }
    $self->dbg("wcpath '$params{wcpath}' matched '", Dumper($match), "'. returning url=$url and rev=$rev\n");
    return ($url, $rev);
}

sub has_submappings {
    my $self = shift;
    my %params = (#wcpath=>,
                  @_);
    # Search for any mappings underneath $params{wcpath}, by looking for any
    # dir that matches wcpath and is LONGER.
    foreach my $item (@vsmap) {
	if ((length $item->{dir} > length $params{wcpath})
	    && ($item->{dir} =~ /^$params{wcpath}/)) 
	{
	    return 1;  # found one!
	}
    }
    return 0;
}

sub list_subdirs_on_disk {
    my $self = shift;
    my %params = (#path=>,
                  @_);
    opendir DIR, $params{path};
    my @items = readdir DIR;
    closedir DIR;
    # stat each one to see which is a dir
    my @dirs;
    foreach my $item (@items) {
	next if $item eq '.' || $item eq '..' || $item eq '.svn';
	push @dirs, $item if -d $item;
    }
    return @dirs;
}

sub list_subdirs_in_repo {
    my $self = shift;
    my %params = (#path=>,
                  #revision=>,
                  @_);
    my $path = $self->abs_filename($params{path});
    # svn ls --nonrecursive
    my $dirents = $self->client->ls ($path, $params{revision}, 0);
    my @dirs;
    foreach my $key (keys %$dirents) {
	my $ent = $dirents->{$key};
        #print Dumper($ent), "\n" if $self->debug;
	my $kind = $SVN::S4::WCKIND_STRINGS{$ent->kind};
	if ($kind eq 'dir') {
	    $self->dbg ("in $path, found dir $key");
	    push @dirs, $key if $kind eq 'dir';
	}
    }
    return @dirs;
}

sub list_switchpoints_at {
    my $self = shift;
    my %params = (#wcpath=>,
                  @_);
    # Find switchpoints that branch directly off of wcpath.
    # E.g. list of switchpoints = A, A/B, A/B/C, and A/B/D/F.
    # The switchpoints at A/B are C and D.
    my %switchpoints;  # use hash to avoid the dups
    foreach my $item (@vsmap) {
	my $dir = $item->{dir};
	$self->dbg("checking if '$dir' matches $params{wcpath}");
	if ($dir =~ s/^$params{wcpath}//) {
	    $self->dbg("found match '$dir' under $params{wcpath}");
	    $dir =~ s%^/%%g;   # remove leading slashes
	    $dir =~ s%/.*%%g;  # remove slash and anything after it
	    $switchpoints{$dir}=1 if length $dir > 0;
	}
    }
    return keys %switchpoints;
}

sub remove_duplicates_from_list {
    my @list = @_;
    my %hash;
    foreach (@list) {  $hash{$_} = 1; }
    return sort keys %hash;
}

sub fix_urls_recurse {
    my $self = shift;
    my %params = (#wctop=>,
                  #wcpath=>,
                  #basepath=>,
		  #node=>,
                  @_);
    $self->dbg("BEGIN fix_urls_recurse wcpath=$params{wcpath} basepath=$params{basepath}");
    my $path = $params{basepath};
    $path .= "/" if length $path > 0 && length $params{wcpath} > 0;
    $path .= $params{wcpath} if length $params{wcpath} > 0;
    my $current_url = $self->file_url (filename=>$path, assert_exists=>0);
    my ($desired_url,$desired_rev) = $self->lookup_mapping (wcpath=>$params{wcpath});
    if (!defined $desired_url) {
        $self->dbg("desired_url is null for $path");
    }
    my $inrepo = $desired_url && $self->is_file_in_repo(url=>$desired_url);
    my $has_submappings = $self->has_submappings(wcpath=>$params{wcpath});
    my $disappear = !defined $desired_url && !$has_submappings && !$inrepo && !(-e $path);
    if (!$inrepo) {
        $desired_url = $self->void_url;
    }
    $self->dbg ("for $params{wcpath}, inrepo=$inrepo, has_submap=$has_submappings, disappear=$disappear");
    $desired_rev ||= $self->{revision};   # needed for unviews
    $params{node}->{url} = $desired_url;
    $params{node}->{rev} = $desired_rev;
    if ($disappear) {
        $self->dbg("making path $params{wcpath} disappear");
	$params{node}->{disappear} = 1;
    } elsif ($current_url && $current_url eq $desired_url) {
        $self->dbg("url is right for '$params{wcpath}'");
    } else {
	my @cmd = ('switch', $desired_url, $path, '--revision', $desired_rev);
	if ($desired_url eq $self->void_url) {
	    print "s4: Creating empty directory $params{wcpath}\n";
	    push @cmd, "--quiet" unless $self->debug;
	    $params{node}->{url} = 'void';
	} else {
	    print "s4: Switching $params{wcpath} to $desired_url\n";
	    $params{node}->{has_submappings} = $has_submappings;
	    if ($params{node}->{has_submappings}) {
	        push @cmd, "--non-recursive";
	    }
	}
	$self->create_switchpoint_hierarchical($params{basepath}, $params{wcpath});
	$self->run_svn(@cmd);
    }
    if (!$disappear) {
	my @disk = $self->list_subdirs_on_disk (path=>$path);
	my @repo = $self->list_subdirs_in_repo (path=>$path, revision=>$self->{revision});
	my @switches = $self->list_switchpoints_at (wcpath=>$params{wcpath});
	print "disk=", Dumper(\@disk) if $self->debug > 1;
	print "repo=", Dumper(\@repo) if $self->debug > 1;
	print "switches=", Dumper(\@switches) if $self->debug > 1;
	my @all = remove_duplicates_from_list (@disk, @repo, @switches);
	foreach my $subdir (@all) {
	    $self->dbg("Recurse into $subdir");
	    my $newdir = $params{wcpath};
	    $newdir .= "/" unless $newdir eq "";
	    $newdir .= $subdir;
	    $params{node}->{dirs}->{$subdir} ||= {};   # set to empty hash, if not defined
		$self->fix_urls_recurse(wctop=>$params{wctop}, wcpath=>$newdir, basepath=>$params{basepath},
			node=>$params{node}->{dirs}->{$subdir});
	}
    }
    $self->dbg("RETURN FROM fix_urls_recurse wcpath=$params{wcpath} basepath=$params{basepath}");
}

sub apply_viewspec_new {
    my $self = shift;
    my %params = (#path=>,
                  @_);
    $self->dbg ("revision is $self->{revision}") if $self->{revision};
    $self->read_viewspec_state (path=>$params{path});
    # build list of viewspec_managed_switches
    # FIXME: Really it's just a list of the dir entries in the @vsmap.
    # So there's not much reason to have a separate variable for it.
    # To fix this, put @vsmap into $self, and make a method
    # to extract the list of viewspec_managed_switches out of it.
    # Then I don't need $self->{viewspec_managed_switches} anymore.
    $self->{viewspec_managed_switches} = [];  # ref to empty array
    foreach (@vsmap) {
	push @{$self->{viewspec_managed_switches}}, $_->{dir}
	    if ($_->{cmd} eq 'map');
    }
    # Look for any switch points that S4 __used to__ maintain, but no longer does.
    # Undo those switch points, if possible.
    $self->remove_unused_switchpoints (basepath=>$params{path});
    # add one more map item, which defines the url mapping of the top level.
    my $base_url = $self->file_url (filename=>$params{path});
    my $item = { cmd=>'map', url=>$base_url, dir=>'', rev=>$self->{revision} };
    push @vsmap, $item;
    my $base_uuid;
    # compute voids url once
    $self->void_url(url => $self->file_url(filename=>$params{path}));
    $self->{mytree} = {};
    $self->fix_urls_recurse (wctop=>$params{path}, basepath=>$params{path}, wcpath=>'', node=>$self->{mytree});
    $self->dbg("mytree = ", Dumper($self->{mytree}));
    $self->dbg("done with apply_viewspec_new");
    # now do an update?
    $self->minimal_update_tree (path=>$params{path});
    #$self->print("Updating the whole tree");
    #$self->update(paths=>[$params{path}], revision=>$self->{revision}, regular_svn=>1);
    # Set viewspec hash in the S4 object.  The caller MAY decide to save the 
    # state by calling $self->save_viewspec_state, or not.
    $self->{viewspec_hash} = $self->viewspec_hash;
}

# Update everything to the revision number given in the viewspec.
# Sometimes the viewspec does not specify any revision numbers, and you
# can just update the whole tree in one shot.  Other times, some deep
# directory has a "rev NUM" in the viewspec different from the rest, and we
# have to do lots of nonrecursive updates in order to avoid making that
# one directory flipflop.
sub minimal_update_tree {
    my $self = shift;
    my %params = (#path=>,
	    @_);
    # Call recursive function to generate a minimal list of update commands
    # that are needed.
    my $needed = $self->minimal_update_tree_recurse (
	    path=>$params{path},
	    node=>$self->{mytree},
	    );
    $self->dbg ("minimal_update_tree needed = ", Dumper($needed));
    # do the commands
    foreach my $path (sort keys %{$needed}) {
	my $rev = $needed->{$path}->{rev};
	my $recurse = $needed->{$path}->{recurse};
	$self->print("Updating $path to rev $rev");
        my @cmd = ('update', $path, '--revision', $rev);
	push @cmd, "--non-recursive" if !$recurse;
	$self->run_svn(@cmd);
    }
}

# Call minimal_update_tree_recurse with a node and a path.  The
# node is a reference to a piece of $self->{mytree} and path is
# the path that leads to it, e.g. "A/B/C".  This method examines
# its rev and the revs of its children, and returns a hashref
# with entries that describe how to update the node and its children.
# If everything underneath has the same target rev, we return a 
# hashref with one element, e.g. { 'A/B' => 8 }.  But if some children
# have different target rev numbers, the hashref may have N elements,
# e.g. { 'A/B/C' => 8, 'A/B/F' => 8, 'A/B/G' => 4}
sub minimal_update_tree_recurse {
    my $self = shift;
    my %params = (#node=>,
                  #path=>,
                  @_);
    my $node = $params{node};
    # If this dir, and all its subdirs, have the same rev target, then it can
    # use recursive update.
    my $rev = $node->{rev};
    my $hash = {};
    $self->dbg("BEGIN minimal_update_tree_recurse with path $params{path}");
    #$self->dbg("and node is ", Dumper($node));
    my $coherent = 1;
    foreach my $dir (keys %{$node->{dirs}}) {
        $self->dbg("there is a dir $dir");
	next if $node->{dirs}->{$dir}->{disappear};
	my $subhash = $self->minimal_update_tree_recurse(
	  node=>$node->{dirs}->{$dir},
	  path=>$params{path} . "/$dir");
	# copy all data from subhash to hash.
	foreach my $path (keys %{$subhash}) {
            $hash->{$path} = $subhash->{$path};
	    my $childrev = $subhash->{$path}->{rev};
	    $coherent = 0 if ($rev != $childrev);
	}
    }
    if ($coherent) {
	# Since they all had the same revision number, throw them all away
	# and only return a hash with one entry in it.
	undef $hash;
	$hash->{$params{path}} = {rev=>$rev, recurse=>1};
    } else {
	$hash->{$params{path}} = {rev=>$rev, recurse=>0};
    }
    $self->dbg("END minimal_update_tree_recurse with path $params{path}");
    return $hash;
}

sub remove_unused_switchpoints {
    my $self = shift;
    my %params = (#basepath=>,
                  @_);
    # Find the list of switchpoints that S4 created
    # If it can't be found, just return.
    if (!$self->{prev_state}) {
        print "s4: remove_unused_switchpoints cannot find prev_state, giving up\n" if $self->debug;
	return;
    }
    if (!$self->{prev_state}->{viewspec_managed_switches}) {
        print "s4: remove_unused_switchpoints cannot find previous list of viewspec_managed_switches, giving up\n" if $self->debug;
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
    my $quiet = $self->debug ? "" : "--quiet";
    my $cmd = qq{$self->{svn_binary} switch $quiet $voidurl $path};
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
    $self->dbg("create_switchpoint_hierarchical basedir=$basedir, reldir=$reldir");
    my $path = "";
    my @dirparts = split ('/', $reldir);
    for (my $i=0; $i <= $#dirparts; $i++) {
	my $dirpart = $dirparts[$i];
	my $last_time_through = ($i == $#dirparts);
	print "s4: does '$dirpart' exist in $basedir? if not, make it\n" if $self->debug > 2;
	if (! -e "$basedir/$dirpart") {
	    # Q: Why is voidurl in a loop?  It takes 1-2 seconds!?
	    # A: I don't want to compute void_url unless it is
	    # really needed.  And the value gets cached, so the
	    # 2nd, 3rd, etc. call takes no time.
	    my $voidurl = $self->void_url(url => $self->file_url(filename=>$basedir));
	    $self->create_switchpoint ($basedir,$dirpart);
	    unless ($last_time_through) {
		my $quiet = $self->debug ? "" : "--quiet";
		$self->run ("$self->{svn_binary} switch $quiet $voidurl $basedir/$dirpart");
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
    if ($fmt != 4) {
        die "%Error: create_switchpoint: I only know how to create switchpoints in working copy format=4. But this working copy is format " . (0+$fmt);
    }
    my $entries_file = "$basedir/.svn/entries";
    # hacky way first, to show if it works.
    # the right way is to use an XML parser.
    my $newfile = "$basedir/.svn/s4_tmp_$$";
    unlink($newfile);
    open (IN, $entries_file) or die "%Error: $! opening $entries_file";
    open (OUT, ">$newfile") or die "%Error: $! opening $newfile";
    die "%Error: can't make a switchpoint with a quote in it!" if $targetdir =~ /"/;
    my $replace_entries_file = 1;
    while (<IN>) {
	if (/name="$targetdir"/) {
	    $self->dbg ("create_switchpoint: an entry called '$targetdir' already exists in .svn/entries");
	    $replace_entries_file = 0;
	    last;
	}
	if (/<\/wc-entries>/) {
	    # just before the last line, add this entry
	    print OUT qq{<entry name="$targetdir" kind="dir"/> \n};
	}
        print OUT;
    }
    $self->run ("/bin/mv -f $newfile $entries_file") if $replace_entries_file;
    unlink($newfile);
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
The actions are stored in @vsmap, and each one is a hash 
containing a command, a directory, etc.

The revision parameter is used as the default revision number for
all svn operations, unless the viewspec file has a "rev NUM" clause
that overrides the default.

=item $s4->apply_viewspec

For each of the svn actions in @vsmap, perform the actions.
An example of an action is to run svn switch on the Foo directory
the the URL Bar at revision 50.

=back

=head1 DISTRIBUTION

The latest version is available from CPAN and from L<http://www.veripool.com/>.

Copyright 2005-2007 by Bryce Denney.  This package is free software; you
can redistribute it and/or modify it under the terms of either the GNU
Lesser General Public License or the Perl Artistic License.

=head1 AUTHORS

Bryce Denney <bryce.denney@sicortex.com>

=head1 SEE ALSO

L<SVN::S4>

=cut
