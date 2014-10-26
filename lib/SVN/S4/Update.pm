# See copyright, etc in below POD section.
######################################################################

package SVN::S4::Update;
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

sub update {
    my $self = shift;
    my %params = (#revision=>,		# NUM if user typed -rNUM, otherwise undef
                  #paths=>,		#listref
		  #fallback_cmd=>,	#listref
                  @_);
    DEBUG "update: my params are: ", Dumper(\%params), "\n" if $self->debug;
    my @paths = @{$params{paths}} if $params{paths};
    push @paths, "." if !@paths;
    if (!$params{fallback_cmd}) {  # used when called from within S4.
	die "s4: %Error: s4 update needs revision" unless defined $params{revision};
	my @cmd = ($self->{svn_binary}, 'update', @paths);
	push @cmd, ('--revision', $params{revision});
	$params{fallback_cmd} = \@cmd;
    }
    if ($#paths > 0) {
	#FIXME if any has a viewspec, barf.
        # punt on multiple params for now.
        DEBUG "update with more than one arg. update normally\n" if $self->debug;
	return $self->run ($params{fallback_cmd});
    }
    my $abspath = $self->abs_filename($paths[0]);

    # see if a viewspec file is present
    my $viewspec = "$abspath/" . $self->{viewspec_file};
    my $found_viewspec = (-d "$abspath" && -f $viewspec);
    if (!$found_viewspec) {
        DEBUG "update tree with no viewspec. update normally\n" if $self->debug;
	return $self->run ($params{fallback_cmd});
    }
    DEBUG "Found a viewspec file. First update the top directory only.\n" if $self->debug;

    # Make final decision about what revision to update to.  This will be used
    # for all viewspec operations, so that you get a coherent rev number.
    # (Exception: if s4 has to make a new void directory and it doesn't get
    # switched, e.g. path1/path2/path3 where only path3 is switched, then
    # path1 and path2 may have revision numbers that are higher than $rev.)
    my $rev = $params{revision};
    $rev = $self->which_rev (revision=>$rev, path=>$abspath);
    DEBUG "Using revision $rev for all viewspec operations\n" if $self->debug;
    $self->{revision} = $rev;  # Force/override any user --revision flag

    # Run update nonrecursively the first time.  The viewspec may replace
    # pieces of the tree, so it would sometimes be a big waste of time to
    # update it all.
    DEBUG "Updating the top\n" if $self->debug;
    my @cmd_nonrecursive = ($self->{svn_binary}, "update", "--non-recursive", $abspath);
    push @cmd_nonrecursive, "--quiet" if $self->quiet;
    push @cmd_nonrecursive, ("-r$rev");
    DEBUG "\t",join(' ',@cmd_nonrecursive),"\n" if $self->debug;
    local $! = undef;
    $self->run(@cmd_nonrecursive);

    # did viewspec just disappear???
    $found_viewspec = (-d $abspath && -f $viewspec);
    if (!$found_viewspec) {
        DEBUG "Viewspec disappeared. Do normal update.\n" if $self->debug;
        DEBUG "viewspec was here, but now it's gone! update normally.\n" if $self->debug;
	return $self->run ($params{fallback_cmd});
    }
    DEBUG "Parse the viewspec file $viewspec\n" if $self->debug;
    $self->parse_viewspec (filename=>$viewspec, revision=>$rev);
    # Test to see if a normal update will suffice, since it is a whole lot faster
    # than a bunch of individual updates.  For every successful checkout/update
    # we make an MD5s hash of the viewspec actions list (minus rev number) and
    # save it away.  Next time, if the viewspec hash is the same, and every
    # directory is scheduled to be updated to the same version (no rev NUM clauses),
    # then you can safely use a single update.
    if (!$self->viewspec_changed(path=>$abspath) && $self->viewspec_compare_rev($rev)) {
        DEBUG "viewspec is same as before. update normally.\n" if $self->debug;
	# We don't use fallback_cmd, as we want a specific revision
	# Also, it breaks when given a symlink as a target, instead of the symlink's target
	my $opt = SVN::S4::Getopt->new;
	my @cmd = $self->{svn_binary};
	push @cmd, $opt->formCmd('update', { %{$self},
					     revision => $rev,
					     path => [$abspath],
					 });
	return $self->run (@cmd);
    }
    $self->apply_viewspec (path=>$abspath);
    $self->save_viewspec_state (path=>$abspath);
}

sub checkout {
    my $self = shift;
    my %params = (#url=>,
                  #path=>,
		  #revision=>,
		  #fallback_cmd=>,
                  @_);
    if (!$params{fallback_cmd}) {  # used when called from within S4.
	die "s4: %Error: s4 checkout needs url,path,revision"
	   unless defined $params{url} && defined $params{path} && defined $params{revision};
	my @cmd = ($self->{svn_binary}, 'checkout', $params{url}, $params{path});
	push @cmd, ('--revision', $params{revision});
	$params{fallback_cmd} = \@cmd;
    }

    # see if the area we're about the check out has a viewspec file
    my $viewspec_url = "$params{url}/$self->{viewspec_file}";
    my $found_viewspec = $self->is_file_in_repo (url => $viewspec_url);

    # A checkout under an existing checkout is usually an error
    # Some scripts expect this to be allowed, so we make it configurable
    # However, viewspecs mess up, so never allow with a viewspec top
    my $co_under_co = $self->config_get_bool('s4', 'co-under-co');
    $co_under_co = 1 if !defined $co_under_co;
    if (-e "$params{path}/.svn"
	&& (!$co_under_co || $found_viewspec || -e "$params{path}/$self->{viewspec_file}")) {
	    die "s4: %Error: Stubbornly refusing to checkout under existing checkout; you probably wanted 'update'\n";
    }

    if (!$found_viewspec) {
        DEBUG "checkout tree with no viewspec. checkout normally\n" if $self->debug;
	return $self->run (@{$params{fallback_cmd}});
    }
    DEBUG "Found a viewspec file in repo. First checkout the top directory only.\n" if $self->debug;

    # Make final decision about what revision to update to.  This will be used
    # for all viewspec operations, so that you get a coherent rev number.
    # (Exception: if s4 has to make a new void directory and it doesn't get
    # switched, e.g. path1/path2/path3 where only path3 is switched, then
    # path1 and path2 may have revision numbers that are higher than $rev.)
    my $rev = $params{revision};
    $rev = $self->which_rev (revision=>$rev, path=>$params{url});
    DEBUG "Using revision $rev for all viewspec operations\n" if $self->debug;

    # Run checkout nonrecursively the first time.  The viewspec may replace
    # pieces of the tree, so it would sometimes be a big waste of time to
    # checkout it all.
    DEBUG "s4: Checkout the top view directory into $params{path}\n" if $self->debug;
    my @cmd_nonrecursive = ($self->{svn_binary}, "checkout", "--revision", $rev, "--non-recursive", $params{url}, $params{path});
    push @cmd_nonrecursive, "--quiet" if $self->quiet;
    DEBUG "\t",join(' ',@cmd_nonrecursive),"\n" if $self->debug;
    local $! = undef;
    $self->run(@cmd_nonrecursive);
    $self->wait_for_existence(path=>$params{path});

    # Did viewspec just disappear??? One hiopes not.
    my $viewspec = "$params{path}/$self->{viewspec_file}";
    $found_viewspec = (-d $params{path} && -f $viewspec);
    if (!$found_viewspec) {
	# I can only imagine this happening if checkout was interrupted, or somebody
	# deleted the viewspec from the repo in the last few seconds.
	die "s4: %Error: viewspec was in repo at $viewspec_url, but I could not find it in your checkout!";
    }
    DEBUG "Parse the viewspec file $viewspec\n" if $self->debug;
    $self->parse_viewspec (filename=>$viewspec, revision=>$rev);
    $self->apply_viewspec (path=>$params{path});
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

The latest version is available from CPAN and from L<http://www.veripool.org/>.

Copyright 2005-2011 by Bryce Denney.  This package is free software; you
can redistribute it and/or modify it under the terms of either the GNU
Lesser General Public License Version 3 or the Perl Artistic License Version 2.0.

=head1 AUTHORS

Bryce Denney <bryce.denney@sicortex.com>

=head1 SEE ALSO

L<SVN::S4>

=cut
