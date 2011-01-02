# See copyright, etc in below POD section.
######################################################################

package SVN::S4::ViewSpec;
require 5.006_001;

use strict;
use Carp;
use IO::Dir;
use IO::File;
use Cwd;
use Digest::MD5;
use vars qw($AUTOLOAD);

use SVN::S4;
use SVN::S4::Debug qw (DEBUG is_debug);
use SVN::S4::Path;

our $VERSION = '1.051';
our $Info = 1;


#######################################################################
# Methods

#######################################################################
#######################################################################
#######################################################################
#######################################################################
# OVERLOADS of S4 object
package SVN::S4;
use SVN::S4::Debug qw (DEBUG is_debug);

our @list_actions;

sub viewspec_hash {
    my $self = shift;
    my $text_to_hash = "";
    foreach (@{$self->{vs_actions}}) {
        $text_to_hash .= "$_->{cmd} $_->{url} $_->{dir}\n";
	# just omit rev.
    }
    my $viewspec_hash = Digest::MD5::md5_hex($text_to_hash);
    #DEBUG "s4: viewspec is $viewspec_hash\n";
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
    DEBUG "s4: Compare hash '$vshash' against old '$oldhash'\n" if $self->debug;
    return ($vshash ne $oldhash);
}

sub parse_viewspec {
    my $self = shift;
    my %params = (#filename=>,
		  #revision=>,
                  @_);
    $self->{vs_actions} = [];
    $self->_parse_viewspec_recurse(%params);
}

sub _parse_viewspec_recurse {
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
    DEBUG "s4: params{revision} = $params{revision}\n" if $self->debug && $params{revision};
    DEBUG "s4: now my revision variable is $self->{revision}\n" if $self->debug && $self->{revision};
    my $fh = new IO::File;
    if ($fn =~ m%://%) {
        # treat it as an svn url
	$fh->open ("svn cat $fn |") or die "s4: %Error: cannot run svn cat $fn";
    } else {
	# When opening an include file, we search relative to the top level
	# viewspec filename.  If it's not an absolute path, prepend the directory
	# part of the top level viewspec name.
	if ($fn !~ m%^/%) {
	    my @dirs = File::Spec->splitdir ($self->{viewspec_path});
	    pop @dirs;
	    push @dirs, File::Spec->splitdir ($fn);
	    my $candidate = File::Spec->catdir (@dirs);
	    DEBUG "s4: Making $fn relative to $self->{viewspec_path}. candidate is $candidate\n" if $self->debug;
	    # if the file exists, accept the $candidate
	    $fn = $candidate if (-f $candidate);
	}
	$fh->open ("< $fn") or die "s4: %Error: cannot open file $fn";
    }
    while (<$fh>) {
        s/#.*//;       # hash mark means comment to end of line
	s/^\s+//;      # remove leading space
	s/\s+$//;      # remove trailing space
	next if /^$/;  # remove empty lines
	#DEBUG ("viewspec: $_\n") if $self->debug;
	$self->_parse_viewspec_line ($fn, $_);
    }
    $fh->close;
}

sub _parse_viewspec_line {
    my $self = shift;
    my $filename = shift;
    my $line = shift;
    my @args = split(/\s+/, $line);
    $self->_expand_viewspec_vars (\@args);
    my $cmd = shift @args;
    if ($cmd eq 'view') {
        $self->_viewspec_cmd_view (@args);
    } elsif ($cmd eq 'unview') {
        $self->_viewspec_cmd_unview (@args);
    } elsif ($cmd eq 'include') {
        $self->_viewspec_cmd_include (@args);
    } elsif ($cmd eq 'set') {
        $self->_viewspec_cmd_set (@args);
    } else {
	if ($line =~ /(>>>>>>|<<<<<<|======)/) {
	    die "s4: %Error: $filename:$.: It looks like Project.viewspec has SVN conflict markers in it\n";
	}
        die "s4: %Error: $filename:$.: Unrecognized command in Project.viewspec: '$cmd'\n";
    }
}

sub _expand_viewspec_vars {
    my $self = shift;
    my $listref = shift;
    my %vars;
    for (my $i=0; $i<=$#$listref; $i++) {
	my $foo;
        #DEBUG "before substitution: $listref->[$i]\n" if $self->debug;
	$listref->[$i] =~ s/\$([A-Za-z0-9_]+)/$self->{viewspec_vars}->{$1}/g;
	#DEBUG "after substitution: $listref->[$i]\n" if $self->debug;
    }
}

sub _viewspec_cmd_view {
    my $self = shift;
    my ($url, $dir, $revtype, $rev) = @_;
    $revtype = "" if !defined $revtype;
    $rev = "" if !defined $rev;
    DEBUG "_viewspec_cmd_view: url=$url  dir=$dir  revtype=$revtype  rev=$rev\n" if $self->debug;
    if (!defined $url || !defined $dir) {
        die "s4: %Error: view command requires URL and DIR argument\n";
    }
    # Replace ^
    if ($url =~ s!^\^!!) {
	my $root = $self->file_root(filename=>$self->{viewspec_path});
	$url = $root.$url;
	DEBUG "expanded url to $url\n" if $self->debug;
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
        die "s4: %Error: parsing view line in viewspec, but revision variable is missing";
    }
    $self->ensure_valid_rev_string($rev);
    # if there is already an action on this directory, abort.
    foreach (@{$self->{vs_actions}}) {
        if ($dir eq $_->{dir}) {
	    die "s4: %Error: In Project.viewspec, one view line collides with a previous one for directory '$dir'. You must either remove one of the view commands or add an 'unview' command before it.";
	}
    }
    my $action;
    $action->{cmd} = "switch";
    $action->{url} = $url;
    $action->{dir} = $dir;
    $action->{rev} = $rev;
    push @{$self->{vs_actions}}, $action;
}

sub _viewspec_cmd_unview {
    my $self = shift;
    my ($dir) = @_;
    DEBUG "_viewspec_cmd_unview: dir=$dir\n" if $self->debug;
    my $ndel = 0;
    for (my $i=0; $i <= $#{$self->{vs_actions}}; $i++) {
	my $cmd = $self->{vs_actions}[$i]->{cmd};
	my $actdir = $self->{vs_actions}[$i]->{dir};
	DEBUG "checking $cmd on $actdir\n" if $self->debug;
        if ($cmd eq 'switch' && $actdir =~ /^$dir/) {
	    DEBUG "deleting action=$cmd on dir=$dir\n" if $self->debug;
	    #DEBUG "before deleting, list was " . Dumper($vs_actions) if $self->debug;
	    splice (@{$self->{vs_actions}}, $i, 1);
	    #DEBUG "after deleting, list was " . Dumper($vs_actions) if $self->debug;
	    $ndel++;
	}
    }
}

sub _viewspec_cmd_include {
    my $self = shift;
    my ($file) = @_;
    DEBUG "_viewspec_cmd_include $file\n" if $self->debug;
    $self->{parse_viewspec_include_depth}++;
    die "s4: %Error: Excessive viewspec includes. Is this infinite recursion?"
         if $self->{parse_viewspec_include_depth} > 100;
    $self->_parse_viewspec_recurse (filename=>$file);
    $self->{parse_viewspec_include_depth}--;
}

sub _viewspec_cmd_set {
    my $self = shift;
    my ($var,$value) = @_;
    DEBUG "_viewspec_cmd_set $var = $value\n" if $self->debug;
    $self->{viewspec_vars}->{$var} = $value;
}

# Call with $s4->viewspec_compare_rev($rev)
# Compares every action in the viewspec against $rev, and returns true
# if every part of the tree will be switched to $rev.  If any rev mismatches,
# returns false.
sub viewspec_compare_rev {
    my $self = shift;
    my ($rev_to_match) = @_;
    foreach my $action (@{$self->{vs_actions}}) {
	my $rev = $action->{rev};
	if ($rev ne $rev_to_match) {
	    return undef; # found inconsistent revs, return false
	}
    }
    return 1;  # all revs were the same, return true
}

sub apply_viewspec {
    my $self = shift;
    my %params = (#path=>,
                  @_);
    DEBUG "revision is $self->{revision}\n" if $self->{revision} && $self->debug;
    $self->{viewspec_managed_switches} = [];  # ref to empty array
    my $base_uuid;
    foreach my $action (sort {$a->{dir} cmp $b->{dir}}
			@{$self->{vs_actions}}) {
	my $dbg = "Action: ";
        foreach my $key (sort keys %$action) {
	    $dbg .= "$key=$action->{$key} ";
	}
	DEBUG "$dbg\n" if $self->debug;
	unless ($base_uuid) {
	    my $base_url = $self->file_url (filename=>$params{path});
	    $base_uuid = $self->client->uuid_from_url ($base_url);
	    DEBUG "Base repository UUID is $base_uuid\n" if $self->debug;
	}
	my $cmd = "";
	if ($action->{cmd} eq 'switch') {
	    my $reldir = $action->{dir};
	    push @{$self->{viewspec_managed_switches}}, $reldir;
	    if (!-e "$params{path}/$reldir") {
	        # Directory does not exist yet. Use the voids trick to create
		# a versioned directory there that is switched to an empty dir.
		DEBUG "s4: Creating empty directory to switch into: $reldir\n" if $self->debug;
		my $basedir = $params{path};
		$self->_create_switchpoint_hierarchical($basedir, $reldir);
	    }
	    my $rev = $action->{rev};
	    if ($rev eq 'HEAD') {
	        die "s4: %Error: with '-r HEAD' in the viewspec actions list, the tree can have inconsistent revision numbers.  This is thus not allowed.\n";
	    }

	    my $url = $self->file_url(filename=>"$params{path}/$reldir");
	    my $verb;
	    my $cleandir = $self->clean_filename("$params{path}/$reldir");
	    if ($url && $url eq $action->{url}) {
		$cmd = "$self->{svn_binary} update $cleandir -r$rev";
		$verb = "Updating";
	    } else {
		if (!$self->is_file_in_repo(url=>$action->{url}, revision=>$rev)) {
		    die "s4: %Error: Cannot switch to nonexistent URL: $action->{url}";
		}
		my $uuid = $self->client->uuid_from_url($action->{url});
		if ($uuid ne $base_uuid) {
		    die "s4: %Error: URL $action->{url} is in a different repository! What you need is an SVN external, which viewspecs presently do not support.";
		}
		$cmd = "$self->{svn_binary} switch $action->{url} $cleandir -r$rev";
		$verb = "Switching";
	    }
	    if (!$self->quiet) {
		print "s4: $verb $reldir";
		if ($verb eq 'Switching') {
		    my $rootre = quotemeta($self->file_root(path=>$action->{url}));
		    (my $showurl = $action->{url}) =~ s/$rootre/^/;
		    print " to $showurl";
		    print " rev $rev" if $rev ne 'HEAD';
		}
		print "\n";
	    }
	} else {
	    die "s4: %Error: unknown s4 viewspec command: $action\n";
	}
	$self->run ($cmd);
    }
    # Look for any switch points that S4 __used to__ maintain, but no longer does.
    # Undo those switch points, if possible.
    $self->_undo_switches (basepath=>$params{path});
    # Set viewspec hash in the S4 object.  The caller MAY decide to save the
    # state by calling $self->save_viewspec_state, or not.
    $self->{viewspec_hash} = $self->viewspec_hash;
}

sub _undo_switches {
    my $self = shift;
    my %params = (#basepath=>,
                  @_);
    # Find the list of switchpoints that S4 created
    # If it can't be found, just return.
    if (!$self->{prev_state}) {
        DEBUG "s4: _undo_switches cannot find prev_state, giving up\n" if $self->debug;
	return;
    }
    if (!$self->{prev_state}->{viewspec_managed_switches}) {
        DEBUG "s4: _undo_switches cannot find previous list of viewspec_managed_switches, giving up\n" if $self->debug;
	return;
    }
    my @prevlist = sort @{$self->{prev_state}->{viewspec_managed_switches}};
    my @thislist = sort @{$self->{viewspec_managed_switches}};
    DEBUG "s4: prevlist: ", join(' ',@prevlist), "\n" if $self->debug;
    DEBUG "s4: thislist: ", join(' ',@thislist), "\n" if $self->debug;
    foreach my $dir (@prevlist) {
	# I'm only interested in directories that were in @prevlist but
	# are not in @thislist.  If dir is in both lists, quit.
        next if grep(/^$dir$/, @thislist);
	if (grep(/^$dir/, @thislist)) {
	    # There is another mountpoint in @thislist that starts
	    # with $dir, in other words there is a mountpoint underneath
	    # this one.  We can't remove the dir, but leave it in the
	    # state file, so we can remove it when we have the chance.
	    DEBUG "s4: Remember that we manage $dir\n" if $self->debug;
	    push @{$self->{viewspec_managed_switches}}, $dir;
	    next;
	}
	print "s4: Remove unused switchpoint $dir\n";
	$self->_remove_switchpoint (dir=>$dir, basepath=>$params{basepath});
    }
}

sub _remove_switchpoint {
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
        DEBUG "Switchpoint $path has already been removed.\n" if $self->debug;
	return;
    }
    my $url = $self->file_url(filename=>$path);
    my $voidurl = $self->void_url(url => $url);
    my $cmd = qq{$self->{svn_binary} switch --quiet $voidurl $path};
    $self->run($cmd);
    # Is it totally empty?
    my $status_items = 0;
    DEBUG "s4: Checking if $path is completely empty\n" if $self->debug;
    my $stat = $self->client->status
	($abspath,			# canonical path
	 "WORKING",			# revision
	 sub { $status_items++; DEBUG Dumper(@_) if $self->debug; }, 	# status func
	 1,				# recursive
	 1,				# get_all
	 0,				# update
	 1,				# no_ignore
     );
     DEBUG "status returned $status_items item(s)\n" if $self->debug;
     # For a totally empty directory, status returns just one thing: the
     # directory itself.
     if ($status_items==1) {
	DEBUG "s4: Removing $path from working area\n" if $self->debug;
	 # Do it gently to reduce chance of wiping out. Only use the big hammer on
	 # the .svn directory itself.  This may "fail" because of leftover .nfs crap;
	 # then what's the right answer?
         $self->run ("rm -rf $path/.svn");
         $self->run ("rmdir $path");
	 DEBUG "s4: running $self->{svn_binary} update -r $self->{revision} on $abspath\n" if $self->debug;
	 $self->run ("$self->{svn_binary} up -N --revision $self->{revision} $path");
     } else {
         print "s4: Ignoring obsolete switchpoint $path because there are still files under it.\n";
         print "s4: If you remove those files, you can remove the switchpoint manually, by deleting\n";
         print "s4: the directory and updating again.\n";
     }
}

sub _create_switchpoint_hierarchical {
    my $self = shift;
    my ($basedir,$reldir) = @_;
    my $path = "";
    my @dirparts = split ('/', $reldir);
    for (my $i=0; $i <= $#dirparts; $i++) {
	my $dirpart = $dirparts[$i];
	my $last_time_through = ($i == $#dirparts);
	DEBUG "s4: does '$dirpart' exist in $basedir? if not, make it\n" if $self->debug;
	if (! -e "$basedir/$dirpart") {
	    $self->_create_switchpoint ($basedir,$dirpart);
	    if (1) {  # Was $last_time_through, but fails for one level deep views
		# Q: Why is voidurl in a loop?  It takes 1-2 seconds!?
		# A: I don't want to compute void_url unless it is
		# really needed.  And the value gets cached, so the
		# 2nd, 3rd, etc. call takes no time.
		my $voidurl = $self->void_url(url => $self->file_url(filename=>$basedir));
		$self->run ("$self->{svn_binary} switch --quiet $voidurl $basedir/$dirpart");
		$self->wait_for_existence (path=>"$basedir/$dirpart");
		push @{$self->{viewspec_managed_switches}},
		    $self->clean_filename("$basedir/$dirpart");
	    }
	}
	$basedir .= "/" . $dirpart;
    }
}

sub _create_switchpoint {
    my $self = shift;
    my ($basedir,$targetdir) = @_;
    DEBUG "s4: create_switchpoint $targetdir from basedir $basedir\n" if $self->debug;
    # Ok, we're going to do something really bizarre to work around a
    # svn limitation.  We want to create an svn switched directory, even if
    # there is no such directory in our working area.  Normally SVN does not
    # allow this unless you svn mkdir a directory and check it in.  But if
    # you artifically add a directory in .svn/entries, then you can switch
    # it to anything you want.  Strange but useful.
    # This hack is specific to the working copy format, so check that the working
    # copy format is one that I recognize.
    my $format_file = "$basedir/.svn/format";
    my $entries_file = "$basedir/.svn/entries";
    my $fmt;
    {
	my $fp = (IO::File->new("<$format_file")
		  || IO::File->new("<$entries_file"));
	$fp or die "s4: %Error: $! opening $format_file or $entries_file";
	$fmt = $fp->getline;
	chomp $fmt;
    }
    if (!($fmt == 4 || ($fmt >= 8 && $fmt <= 10))) {
	die "s4: %Error: create_switchpoint: I only know how to create switchpoints in working copy format=4 or format=8. But this working copy is format " . (0+$fmt);
    }

    my $newfile = "$basedir/.svn/s4_tmp_$$";
    unlink(glob("$basedir/.svn/s4_tmp_*"));
    open (IN, $entries_file) or die "s4: %Error: $! opening $entries_file";
    die "s4: %Error: can't make a switchpoint with a quote in it!" if $targetdir =~ /\"/;
    my @out;
    if ($fmt == 4) {
	while (<IN>) {
	    if (/name="$targetdir"/) {
		die "s4: %Error: create_switchpoint: an entry called '$targetdir' already exists in .svn/entries";
	    }
	    if (/<\/wc-entries>/) {
		# Fmt=4: Just before the </wc-entries> line, add this entry
		push @out, qq{<entry name="$targetdir" kind="dir"/> \n};
	    }
	    push @out, $_;
	}
    }
    elsif ($fmt >= 8) {
	# See subversion sources: subversion/libsvn_wc/entries.c
	# Entries terminated by \f at next entry, then
	#   kind, revision, url path, repo_root, schedule, timestamp, checksum,
	#   cmt_date, cmt_rev, cmt_author, has_props, has_props_mod,
	#   cachable_done, present_props,
	#   prejfile, conflict_old, conflict_new, conflict_wrk,
	#   copied, copyfrom_url, copyfrom_rev, deleted, absent, incomplete
	#   uuid, lock_token, lock_owner, lock_comment, lock_creation_date,
	#   changelist, keep_local, size, depth, tree_conflict_data,
	#   external information
	while (<IN>) {
	    if (/^$targetdir/) {
		die "s4: %Error: create_switchpoint: an entry called '$targetdir' already exists in .svn/entries";
	    }
	    push @out, $_;
	}
	# Right at the end, add new entry.
	push @out, "$targetdir\ndir\n" . chr(12) . "\n";
    }
    open (OUT, ">$newfile") or die "s4: %Error: $! opening $newfile";
    print OUT join('',@out);
    close OUT;
    rename($newfile, $entries_file) or die "s4: Internal-%Error: $! on 'mv $newfile $entries_file',";
}

sub viewspec_urls {
    my $self = shift;
    # Return all URLs mentioned in this action set, for info-switches
    my %urls;
    foreach my $action (@{$self->{vs_actions}}) {
	next if !$action->{url};
	$urls{$action->{url}} = 1;
    }
    return sort keys %urls;
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

For viewspec documentation, see L<s4>.

=head1 METHODS

=over 4

=item $s4->parse_viewspec(parse_viewspec(filename=>I<filename>, revision=>I<revision>);

Parse_viewspec reads the file specified by FILENAME, and builds up
a list of svn actions that are required to build the working area.

The revision parameter is used as the default revision number for
all svn operations, unless the viewspec file has a "rev NUM" clause
that overrides the default.

=item $s4->apply_viewspec

For each of the svn actions, perform the actions.  An example of an action
is to run svn switch on the Foo directory the the URL Bar at revision 50.

=back

=head1 DISTRIBUTION

The latest version is available from CPAN and from L<http://www.veripool.org/>.

Copyright 2005-2011 by Bryce Denney.  This package is free software; you
can redistribute it and/or modify it under the terms of either the GNU
Lesser General Public License Version 3 or the Perl Artistic License Version 2.0.

=head1 AUTHORS

Bryce Denney <bryce.denney@sicortex.com>

=head1 SEE ALSO

L<SVN::S4>, L<s4>

=cut
