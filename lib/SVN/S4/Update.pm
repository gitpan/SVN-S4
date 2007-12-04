# $Id: Update.pm 48237 2007-12-04 19:35:20Z wsnyder $
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

package SVN::S4::Update;
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

our $VERSION = '1.020';
our $Info = 1;


#######################################################################
# Methods

#######################################################################
#######################################################################
#######################################################################
#######################################################################
# OVERLOADS of S4 object
package SVN::S4;

sub update {
    my $self = shift;
    my %params = (#revision=>,		# NUM if user typed -rNUM, otherwise undef
                  #paths=>,		#listref
		  #fallback_cmd=>,	#listref
		  #regular_svn=>,       #if 1, always use fallback command
                  @_);
    print "update: my params are: ", Dumper(\%params), "\n" if $self->debug;
    my @paths = @{$params{paths}} if $params{paths};
    push @paths, "." if !@paths;
    if (!$params{fallback_cmd}) {  # used when called from within S4.
	die "%Error: s4 update needs revision" unless defined $params{revision};
	my @cmd = ($self->{svn_binary}, 'update', @paths);
	push @cmd, ('--revision', $params{revision});
	$params{fallback_cmd} = \@cmd;
    }
    if ($#paths > 0) {
	#FIXME if any has a viewspec, barf.
        # punt on multiple params for now.
        print "update with more than one arg. update normally\n" if $self->debug;
	return $self->run ($params{fallback_cmd});
    }
    if ($params{regular_svn}) {
	return $self->run ($params{fallback_cmd});
    }

    # see if a viewspec file is present
    my $viewspec = "$paths[0]/" . $self->{viewspec_file};
    my $found_viewspec = (-d "$paths[0]" && -f $viewspec);
    if (!$found_viewspec) {
        print "update tree with no viewspec. update normally\n" if $self->debug;
	return $self->run ($params{fallback_cmd});
    }
    print "Found a viewspec file. First update the top directory only.\n" if $self->debug;

    # Make final decision about what revision to update to.  This will be used
    # for all viewspec operations, so that you get a coherent rev number.
    my $rev = $params{revision};
    $rev = $self->which_rev (revision=>$rev, path=>$paths[0]);
    print "Using revision $rev for all viewspec operations\n" if $self->debug;

    # Run update nonrecursively the first time.  The viewspec may replace
    # pieces of the tree, so it would sometimes be a big waste of time to
    # update it all.
    print "s4: Updating the top\n" if !$self->quiet;
    my @cmd_nonrecursive = ($self->{svn_binary}, "update", "--non-recursive", @paths);
    push @cmd_nonrecursive, "--quiet" if $self->quiet;
    push @cmd_nonrecursive, ("--revision", $rev);
    print "\t",join(' ',@cmd_nonrecursive),"\n" if $self->debug;
    local $! = undef;
    $self->run(@cmd_nonrecursive);

    # did viewspec just disappear???
    $found_viewspec = (-d "$paths[0]" && -f $viewspec);
    if (!$found_viewspec) {
        print "Viewspec disappeared. Do normal update.\n" if !$self->quiet;
        print "viewspec was here, but now it's gone! update normally.\n" if $self->debug;
	return $self->run ($params{fallback_cmd});
    }
    print "Parse the viewspec file $viewspec\n" if $self->debug;
    $self->parse_viewspec (filename=>$viewspec, revision=>$rev);
    $self->apply_viewspec_new (path=>$paths[0]);
    $self->save_viewspec_state (path=>$paths[0]);
}

sub switch {
    my $self = shift;
    my %params = (#revision=>,		# NUM if user typed -rNUM, otherwise undef
		  #url=>,
                  #path=>,		#listref
		  #fallback_cmd=>,	#listref
		  #regular_svn=>,       #if 1, always use fallback command
                  @_);
    print "switch: my params are: ", Dumper(\%params), "\n" if $self->debug;
    my $path = $params{path};
    $path = "." if !defined $path;
    if (!$params{fallback_cmd}) {  # used when called from within S4.
	die "%Error: s4 switch needs revision" unless defined $params{revision};
	my @cmd = ($self->{svn_binary}, 'switch', $params{url}, $path);
	push @cmd, ('--revision', $params{revision});
	$params{fallback_cmd} = \@cmd;
    }
    if ($params{regular_svn}) {
	return $self->run ($params{fallback_cmd});
    }

    if (! -d $path) {
        return $self->switch_create_switchpoint (
	    path=>$path,
	    fallback_cmd=>$params{fallback_cmd},
	    revision=>$params{revision});
    }

    # see if a viewspec file is present
    my $viewspec = "$path/" . $self->{viewspec_file};
    my $found_viewspec = (-d $path && -f $viewspec);
    if (!$found_viewspec) {
        print "Switch tree with no viewspec. switch normally\n" if $self->debug;
	return $self->run ($params{fallback_cmd});
    }
    print "Found a viewspec file. First switch the top directory only.\n" if $self->debug;

    # Make final decision about what revision to switch to.  This will be used
    # for all viewspec operations, so that you get a coherent rev number.
    my $rev = $params{revision};
    $rev = $self->which_rev (revision=>$rev, path=>$path);
    print "Using revision $rev for all viewspec operations\n" if $self->debug;

    # Run switch nonrecursively the first time.  The viewspec may replace
    # pieces of the tree, so it would sometimes be a big waste of time to
    # switch it all.
    print "s4: Switching the top\n" if !$self->quiet;
    my @cmd_nonrecursive = ($self->{svn_binary}, "switch", "--non-recursive", $params{url}, $path);
    push @cmd_nonrecursive, "--quiet" if $self->quiet;
    push @cmd_nonrecursive, ("--revision", $rev);
    print "\t",join(' ',@cmd_nonrecursive),"\n" if $self->debug;
    local $! = undef;
    $self->run(@cmd_nonrecursive);

    # did viewspec just disappear???
    $found_viewspec = (-d $path && -f $viewspec);
    if (!$found_viewspec) {
        print "Viewspec disappeared. Do normal switch.\n" if !$self->quiet;
        print "viewspec was here, but now it's gone! switch normally.\n" if $self->debug;
	return $self->run ($params{fallback_cmd});
    }
    print "Parse the viewspec file $viewspec\n" if $self->debug;
    $self->parse_viewspec (filename=>$viewspec, revision=>$rev);
    $self->apply_viewspec_new (path=>$path);
    $self->save_viewspec_state (path=>$path);
}

# This is called when you do "s4 switch URL PATH" and PATH does not exist.
# If it turns out that the PATH is somewhere in a working copy, S4 actually
# DOES know how to create a directory that you can switch into.  This 
# method finds the working copy, decides if it can, and does it.
sub switch_create_switchpoint {
    my $self = shift;
    my %params = (#path=>,
                  #revision=>,
                  #fallback_cmd=>,
                  @_);
    my $path = $params{path};
    $self->error("switch_create_switchpoint should not have been called") if -d $path;
    # Aha, now we can help out by making the switchpoint at $path.  Identify
    # the lowest-level directory that is a working copy, and start building
    # switchpoints until you reach path.
    my @basedirs = File::Spec->splitdir ($path);
    my @reldirs;
    my $basedir;
    while (@basedirs) {
	unshift @reldirs, (pop @basedirs);  # start at parent of $path.
        my $candidate = File::Spec->catdir (@basedirs);
	last if ($candidate eq '/');  # please don't touch the root!
	$candidate = "." if length $candidate < 1;
	print "Is $candidate a working copy?\n" if $self->debug;
	if (-d $candidate && -d "$candidate/.svn") {
	    $basedir = $candidate;
	    last;
	}
    }
    if (!defined $basedir) {
        print "Cannot find working copy at any point above $path. Run normal command.\n" if $self->debug;
	$self->run ($params{fallback_cmd});
	$self->clear_viewspec_state (path=>$path);  # switch wipes out switches
	return check_viewspec_after_svn_cmd (path=>$path, revision=>$params{revision});
    }
    $self->print("s4: Creating empty directory to switch into: $path");
    my $reldir = File::Spec->catdir (@reldirs);
    #die "%Error: create_switchpoint_hierarchical with basedir=$basedir, reldir=$reldir";
    $self->create_switchpoint_hierarchical ($basedir, $reldir);
    # Now that we made the switchpoint, run the normal command.
    $self->run($params{fallback_cmd});
    $self->clear_viewspec_state (path=>$path);  # switch wipes out switches
    $self->check_viewspec_after_svn_cmd (path=>$path, revision=>$params{revision});
}

# FIXME: this should be in S4 module probably!
sub check_viewspec_after_svn_cmd {
    my $self = shift;
    my %params = (#path=>,
                  #revision=>,
                  @_);
    my $path = $params{path};
    # Is there a viewspec file? If so parse and update accordingly.
    my $viewspec = "$path/" . $self->{viewspec_file};
    my $found_viewspec = (-d $path && -f $viewspec);
    if (!$found_viewspec) {
        print "after switch, there is no viewspec. done.\n" if $self->debug;
        return;
    }
    my $rev = $params{revision};
    $rev = $self->which_rev (revision=>$rev, path=>$path);
    print "Using revision $rev for all viewspec operations\n" if $self->debug;
    print "Parse the viewspec file $viewspec\n" if $self->debug;
    $self->parse_viewspec (filename=>$viewspec, revision=>$rev);
    # Test to see if a normal update will suffice, since it is a whole lot faster
    # than a bunch of individual updates.  For every successful checkout/update
    # we make an MD5s hash of the viewspec actions list (minus rev number) and
    # save it away.  Next time, if the viewspec hash is the same, and every
    # directory is scheduled to be updated to the same version (no rev NUM clauses),
    # then you can safely use a single update.
    #
    #FIXME: once recursive checking for URL and REV is done, this should be removed.
    if (!$self->viewspec_changed(path=>$path) && $self->viewspec_compare_rev($rev)) {
        print "No viewspec changes. Done.\n" if !$self->quiet;
	return;
    }
    $self->apply_viewspec_new (path=>$path);
    $self->save_viewspec_state (path=>$path);
}


sub checkout {
    my $self = shift;
    my %params = (#url=>,
                  #path=>,
		  #revision=>,
		  #fallback_cmd=>,
                  @_);
    if (!$params{fallback_cmd}) {  # used when called from within S4.
	die "%Error: s4 checkout needs url,path,revision" 
	   unless defined $params{url} && defined $params{path} && defined $params{revision};
	my @cmd = ($self->{svn_binary}, 'checkout', $params{url}, $params{path});
	push @cmd, ('--revision', $params{revision});
	$params{fallback_cmd} = \@cmd;
    }
    # see if the area we're about the check out has a viewspec file
    my $viewspec_url = "$params{url}/$self->{viewspec_file}";
    my $found_viewspec = $self->is_file_in_repo (url => $viewspec_url);
    if (!$found_viewspec) {
        print "checkout tree with no viewspec. checkout normally\n" if $self->debug;
	return $self->run (@{$params{fallback_cmd}});
    }
    print "Found a viewspec file in repo. First checkout the top directory only.\n" if $self->debug;

    # Make final decision about what revision to update to.  This will be used
    # for all viewspec operations, so that you get a coherent rev number.
    my $rev = $params{revision};
    $rev = $self->which_rev (revision=>$rev, path=>$params{url});
    print "Using revision $rev for all viewspec operations\n" if $self->debug;

    # Run checkout nonrecursively the first time.  The viewspec may replace
    # pieces of the tree, so it would sometimes be a big waste of time to
    # checkout it all.
    print "s4: Checkout the top level directory into $params{path}\n";
    my @cmd_nonrecursive = ($self->{svn_binary}, "checkout", "--revision", $rev, "--non-recursive", $params{url}, $params{path});
    push @cmd_nonrecursive, "--quiet" if $self->quiet;
    print "\t",join(' ',@cmd_nonrecursive),"\n" if $self->debug;
    local $! = undef;
    $self->run(@cmd_nonrecursive);
    $self->wait_for_existence(path=>$params{path});

    # Did viewspec just disappear??? One hopes not.
    my $viewspec = "$params{path}/$self->{viewspec_file}";
    $found_viewspec = (-d $params{path} && -f $viewspec);
    if (!$found_viewspec) {
	# I can only imagine this happening if checkout was interrupted, or somebody 
	# deleted the viewspec from the repo in the last few seconds.
	die "%Error: viewspec was in repo at $viewspec_url, but I could not find it in your checkout!";
    }
    print "Parse the viewspec file $viewspec\n" if $self->debug;
    $self->parse_viewspec (filename=>$viewspec, revision=>$rev);
    $self->apply_viewspec_new (path=>$params{path});
    $self->save_viewspec_state (path=>$params{path});
}

######################################################################
### Package return
package SVN::S4::Update;
1;
__END__

=pod

=head1 NAME

SVN::S4::Update - Enhanced update and checkout methods

=head1 SYNOPSIS

Shell:
  s4 update PATH URL
  s4 checkout PATH URL

Scripts:
  use SVN::S4::Update;
  $svns4_object->update
  $svns4_object->checkout

=head1 DESCRIPTION

SVN::S4::Update 

=head1 METHODS

=over 4

=item TBD

TBD

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
