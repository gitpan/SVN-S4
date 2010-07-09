# See copyright, etc in below POD section.
######################################################################

package SVN::S4;
require 5.006_001;
use File::Find;
use File::Spec;

use Carp;
use Data::Dumper;
use SVN::Client;
# Our stuff
use SVN::S4::CatOrMods;
use SVN::S4::FixProp;
use SVN::S4::Getopt;
use SVN::S4::Info;
use SVN::S4::Path;
use SVN::S4::Update;
use SVN::S4::ViewSpec;
use SVN::S4::QuickCommit;
use SVN::S4::Snapshot;
use SVN::S4::StrongRevert;
use vars qw($Debug);
use strict;

######################################################################
#### Configuration Section

our $VERSION = '1.034';

# SVN::Client methods
#       $ctx->add($path, $recursive, $pool);
#       $ctx->blame($target, $start, $end, \&receiver, $pool);
#       $ctx->cat(\*FILEHANDLE, $target, $revision, $pool);
#       $ctx->checkout($url, $path, $revision, $recursive, $pool);
#       $ctx->cleanup($dir, $pool);
#       $ctx->commit($targets, $nonrecursive, $pool);
#       $ctx->copy($src_target, $src_revision, $dst_target, $pool);
#       $ctx->delete($targets, $force, $pool);
#       $ctx->diff($diff_options, $target1, $revision1, $target2, $revision2, $recursive,
#                 $ignore_ancestry, $no_diff_deleted, $outfile, $errfile, $pool);
#       $ctx->export($from, $to, $revision, $force, $pool);
#       $ctx->import($path, $url, $nonrecursive, $pool);
#       $ctx->log($targets, $start, $end, $discover_changed_paths, $strict_node_history,
#                 \&log_receiver, $pool);
#       $ctx->ls($target, $revision, $recursive, $pool);
#       $ctx->merge($src1, $rev1, $src2, $rev2, $target_wcpath, $recursive, $ignore_ancestry,
#                 $force, $dry_run, $pool);
#       $ctx->mkdir($targets, $pool);
#       $ctx->move($src_path, $src_revision, $dst_path, $force, $pool);
#       $ctx->propget($propname, $target, $revision, $recursive, $pool);
#       $ctx->proplist($target, $revision, $recursive, $pool);
#       $ctx->propset($propname, $propval, $target, $recursive, $pool);
#       $ctx->relocate($dir, $from, $to, $recursive, $pool);
#       $ctx->resolved($path, $recursive, $pool);
#       $ctx->revert($paths, $recursive, $pool);
#       $ctx->revprop_get($propname, $url, $revision, $pool);
#       $ctx->revprop_list($url, $revision, $pool);
#       $ctx->revprop_set($propname, $propval, $url, $revision, $force, $pool);
#       $ctx->status($path, $revision, \&status_func, $recursive, $get_all, $update, $no_ignore, $pool);
#       $ctx->switch($path, $url, $revision, $recursive, $pool);
#       $ctx->update($path, $revision, $recursive, $pool)
#       $ctx->url_from_path($target, $pool); or SVN::Client::url_from_path($target, $pool);
#       $ctx->uuid_from_path($path, $adm_access, $pool);
#       $ctx->uuid_from_url($url, $pool);

######################################################################
#### Constants
our %WCSTAT_STRINGS = (
    $SVN::Wc::Status::none => 'none',
    $SVN::Wc::Status::unversioned => 'unversioned',
    $SVN::Wc::Status::normal => 'normal',
    $SVN::Wc::Status::added => 'added',
    $SVN::Wc::Status::missing => 'missing',
    $SVN::Wc::Status::deleted => 'deleted',
    $SVN::Wc::Status::replaced => 'replaced',
    $SVN::Wc::Status::modified => 'modified',
    $SVN::Wc::Status::merged => 'merged',
    $SVN::Wc::Status::conflicted => 'conflicted',
    $SVN::Wc::Status::ignored => 'ignored',
    $SVN::Wc::Status::obstructed => 'obstructed',
    $SVN::Wc::Status::external => 'external',
    $SVN::Wc::Status::incomplete => 'incomplete',
);
our %WCSTAT_LETTERS = (
    $SVN::Wc::Status::none		=> ' ',
    $SVN::Wc::Status::unversioned	=> '?',
    $SVN::Wc::Status::normal		=> ' ',
    $SVN::Wc::Status::added		=> 'A',
    $SVN::Wc::Status::missing		=> '!',
    $SVN::Wc::Status::deleted		=> 'D',
    $SVN::Wc::Status::replaced		=> 'R',
    $SVN::Wc::Status::modified		=> 'M',
    $SVN::Wc::Status::merged		=> 'G',
    $SVN::Wc::Status::conflicted	=> 'C',
    $SVN::Wc::Status::ignored		=> 'I',
    $SVN::Wc::Status::obstructed	=> '!', #?
    $SVN::Wc::Status::external		=> 'X',
    $SVN::Wc::Status::incomplete 	=> '!', #?
);
our %WCKIND_STRINGS = (
    $SVN::Node::none => 'none',
    $SVN::Node::file => 'file',
    $SVN::Node::dir => 'dir',
    $SVN::Node::unknown => 'unknown',
);

######################################################################
#### Creators

sub new {
    my $class = shift;
    my $self = {# Overridable by user
		quiet => 0,
		dryrun => undef,
		debug => $Debug,
		revision => undef,  # default rev for viewspec operations
		s4_binary => "s4",
		svn_binary => "svn",   # overridden by command line or env variable
		viewspec_file => "Project.viewspec",
		state_file => ".svn/s4_state",
		rev_on_date_cache => {},   # empty hash ref
		parse_viewspec_include_depth => 0,
		viewspec_vars => {}, # empty hash ref
		void_url => undef,   # cached copy of the URL of the void dir
		# Internals
		#_client => undef,
		#_pool => undef,
		@_};
    # Copy all environment variables into viewspec_vars. Later the viewspec
    # "set" command will either use them or override them.
    foreach (keys %ENV) {
        $self->{viewspec_vars}->{$_} = $ENV{$_};
    }
    my %client_params = %{$self};
    $self->{_client} = new SVN::Client
	(auth => [SVN::Client::get_simple_provider(),
	         SVN::Client::get_username_provider()],
	 %{$self});
    $self->{_pool} = SVN::Pool->new_default;
    bless ($self, $class);
    return $self;
}

sub args_to_params {
    my %args = (@_);
    my %outargs;
    $outargs{quiet}	= $args{"--quiet"}	if defined $args{"--quiet"};
    $outargs{dryrun}	= $args{"--dry-run"}	if defined $args{"--dry-run"};
    return %outargs;
}

######################################################################
#### Accessors

sub client { return $_[0]->{_client}; }
sub debug { return $_[0]->{debug}; }
sub quiet { return $_[0]->{quiet}; }
sub pool { return $_[0]->{_pool}; }

######################################################################
#### Methods

sub open {
    my $self = shift;
}

# remove ./ from the front of a filename
sub clean_filename {
    my $self = shift;
    my $filename = shift;
    $filename =~ s%^\./%%;  # Sometimes results in errors
    # Multiple slashes in pathname (foo//bar) works for many purposes,
    # but svn::client says:
    #   perl: subversion/libsvn_subr/path.c:113: svn_path_join: Assertion `is_canonical (base, blen)' failed.
    $filename =~ s%//+%/%g;
    # Remove slash at end
    $filename =~ s%/$%%;
    return $filename;
}

sub abs_filename {
    my $self = shift;
    my $filename = $self->clean_filename(shift);
    $filename = $ENV{PWD} if $filename eq '.';
    $filename = $ENV{PWD}."/".$filename if $filename !~ m%^/%;
    foreach (1..100) {
	# You may have to call readlink several times to resolve all the
	# symlinks, but I didn't want any chance of an infinite loop, so I chose
	# an arbitrary limit of calling readlink 100 times.
        my $try = readlink $filename;
	last if (!defined $try);
	print "replace filename $filename with readlink filename $try\n" if $self->debug;
	# We need to allow a symlink of just "foo -> bar", note bar has no dir name
	$filename =~ s!/[^/]*$!!;  # basedir(filename)
	$filename = File::Spec->rel2abs($try,$filename);
	print "    new filename $filename\n" if $self->debug;
    }
    return $filename;
}

# Wait N seconds for a certain file or directory to appear
# This is useful when you have created something on one NFS machine
# and you need to read it on another.
sub wait_for_existence {
    my $self = shift;
    my %params = (#path=>,
                  timeout=>20,
                  @_);
    my $max=$params{timeout};
    foreach (1..$max) {
	return 1 if (-d $params{path});
	print "Waiting for $params{path} to appear from file server\n" if $self->debug;
	die "%Error: after $max seconds, the directory $params{path} is still not present." if $_==$max;
	sleep 1;
    }
}

# call system function, and gripe if it returns nonzero exit status.
sub run {
    my $self = shift;
    if (ref $_[0] eq 'ARRAY') {
	# dereference if needed, so that you can pass in either a list
	# or a reference to a list.
        @_ = @{$_[0]};
    }
    print "+ '", join("' '",@_), "'\n" if $self->debug;
    local $! = undef;
    system @_;
    my $status = $?; my $msgx = $!;
    if (!$self->debug) {
	# Generally: Don't print a message, svn already did.
	if ($status == -1) {
	    exit(255);
	} elsif ($status & 127) {
	    print "%Error: child died with signal %d, %s coredump\n",
	       ($? & 127),  ($? & 128) ? 'with' : 'without';
	    exit(254);
	} elsif ($status != 0) {
	    exit ($status >> 8);
	}
    }
    ($status == 0) or croak "%Error: Command Failed $status $msgx, stopped";
}

sub run_s4 {
    my $self = shift;
    my @list = ($self->{s4_binary}, @_);
    $self->run (@list);
}

sub run_svn {
    my $self = shift;
    my @list = ($self->{svn_binary}, @_);
    $self->run (@list);
}

sub hide_all_output {
    my $self = shift;
    if ($self->debug) {
        print "hide_all_output: If I wasn't in debug mode, I would hide stdout and stderr now.\n";
	return;
    }
    CORE::open(SAVEOUT, ">& STDOUT") or croak "%Error: Can't dup stdout, stopped";
    CORE::open(SAVEERR, ">& STDERR") or croak "%Error: Can't dup stderr, stopped";
    if (0) {close(SAVEOUT); close(SAVEERR);}        # Prevent unused warning
    CORE::open(STDOUT, "/dev/null") or croak "%Error: Can't redirect stdout, stopped";
    CORE::open(STDERR, ">& STDOUT") or croak "%Error: Can't dup stdout, stopped";
}

sub restore_all_output {
    my $self = shift;
    if ($self->debug) {
        print "restore_all_output: If I wasn't in debug mode, I would restore stdout and stderr now.\n";
	return;
    }
    # put STDOUT,STDERR back where they belong
    CORE::open (STDOUT, ">&SAVEOUT");
    CORE::open (STDERR, ">&SAVEERR");
}

sub read_viewspec_state {
    my $self = shift;
    my %params = (#path=>
                  @_);
    my $file = "$params{path}/$self->{state_file}";
    undef $self->{prev_state};
    $self->hide_all_output();
    eval {
      our $VAR1;
      print "Requiring file $file\n" if $self->debug;
      require $file;
      $self->{prev_state} = $VAR1;
    };
    $self->restore_all_output();
    return $self->{prev_state};
}

sub save_viewspec_state {
    my $self = shift;
    my %params = (#path=>
                  @_);
    my $state_file = "$params{path}/$self->{state_file}";
    my $state = {
      viewspec_hash => $self->{viewspec_hash},
      viewspec_managed_switches => $self->{viewspec_managed_switches},
    };
    CORE::open (OUT, ">$state_file") or die "%Error: $! writing $state_file";
    print OUT "# S4 State File\n";
    print OUT Dumper($state);
    print OUT "1;  # so that require of this file will work\n";
    close OUT;
}

sub clear_viewspec_state {
    my $self = shift;
    my %params = (#path=>
                  @_);
    my $state_file = "$params{path}/$self->{state_file}";
    unlink $state_file;
}

######################################################################
#### Information retrieval

# file_url(filename=>FILE)
# Is FILE known by subversion?  If so return its URL, else undef.
sub file_url {
    my $self = shift;
    my %params = (#filename =>
                  assert_exists=>1,
		  @_);
    print "\tfile_url $params{filename}\n" if $Debug;
    my $filename = $self->abs_filename($params{filename});
    print "absolute filename = $filename\n" if $Debug;
    $self->open();
    return undef if $filename =~ m!\.old($|/)!;
    $self->hide_all_output();
    my $url;
    my $error = 1;
    eval {
	$url = $self->client->url_from_path($filename, $self->pool);
	$error = 0;
    };
    $self->restore_all_output();
    if ($params{assert_exists} && $error) {
        die "%Error: file_url: could not find url for path $filename";
    }
    print "url is $url\n" if $self->debug;
    return $url;
}

sub is_file_personal {
    my $self = shift;
    my %params = (#filename =>
		  user => $ENV{USER},
		  @_);
    # Is file owned by specified user?
    print "\tsvn_file_personal $params{filename}\n" if $Debug;
    my $filename = $self->clean_filename($params{filename});
    $self->open();
    my $status;
    $self->client->status($filename, "WORKING",
			  sub {
			      $status = $_[1];
			  },
			  0, 1, 0, 0);
    return undef if !$status;

    # Did the current user add it?
    my $added = $status->text_status == $SVN::Wc::Status::added;
    #print "Added\n" if $added;
    return 1 if $added;

    # Is it by the same author?
    my $entry = $status->entry;
    #print "LA ",$entry->cmt_author(),"\n";
    return 1 if $entry->cmt_author() eq $params{user};

    return undef;  # Nope.
}

# Test if file is in repository.
# The only thing that's tricky about this is not printing an error
# or crashing if the file is NOT present.  I run a system command
# and redirect output to /dev/null.
sub is_file_in_repo {
    my $self = shift;
    my %params = (#url=>,
                  revision=>'HEAD',
                  @_);
    my $url = $params{url};
    print "is_file_in_repo with url='$url'\n" if $self->debug;
    $self->hide_all_output();
    my $exists = 0;
    eval {
        my $proplist = $self->client->proplist($url, $params{revision}, 0);
	print "proplist returned, so the url must have existed\n" if $self->debug;
	$exists = 1;
    };
    $self->restore_all_output();
    return $exists;
}

# Given a date string and url, find the svn revision that was current at that time.
# If you pass in "HEAD" instead of a date string, it will return the head rev.
sub rev_on_date {
    my $self = shift;
    my %params = (date=>'HEAD',
                  #url=>,
		  @_);
    my $date = $params{date};
    my $cached = $self->{rev_on_date_cache}{$date};
    return $cached if $cached;

    my $url = $params{url};
    if (!SVN::S4::Path::isURL($params{url})) {
	$url = $self->file_url(filename=>$url);
    }
    if (!$url) {
	# If url is a file that doesn't exist, you can get undef $url.
	# If you pass the undef into revprop_list it will segfault.
	die "%Error: rev_on_date was called with a bad file or url: $params{url}";
    }
    $self->ensure_valid_rev_string ($date);
    print "about to call revprop_list with url=$url rev=$date\n" if $self->debug;
    my ($props,$rev) = $self->client->revprop_list($url, $date);
    if ($rev !~ /[0-9]+/) {
	die "%Error: failed to look up revision number for '$date'";
    }
    if ($rev > 0 && $rev < 9999999999 && $rev =~ /^[0-9]+$/) {
	$self->{rev_on_date_cache}->{$date} = $rev;
        return $rev;
    }
    die "%Error: failed to look up revision number for '$date'";
}

sub rev_of_head {
    my $self = shift;
    my %params = (#url=>,
    		  #path=>,
		  @_);
    my $url_or_path = $params{url} || $params{path};
    die "%Error: rev_of_head called without url or path param. either one is fine" if !$url_or_path;
    return $self->rev_on_date(url=>$url_or_path, date=>"HEAD");
}

sub which_rev {
    my $self = shift;
    my %params = (#s4=>,
		  #revision=>,
		  #url=>,
		  #path=>,
	    	  @_);
    if ($params{revision} && $params{revision} ne 'HEAD') {
	# We must change the string "HEAD" into a specific revision number,
	# or we can end up with a tree with a mix of revisions.
	return $params{revision};
    }
    return $self->rev_of_head(path=>$params{path}) if $params{path};
    return $self->rev_of_head(url=>$params{url})   if $params{url};
    die "%Error: which_rev called without url or path param";
}

# Given a URL in the repository, find the URL of the "void" directory.
# The void directory is an empty directory somewhere above the URL,
# but we don't know exactly where.  Too bad the URL string does not specify
# which parts are UNIX directories and which are SVN repository directories.
# Example with URL svn+ssh://svn.sicortex.com/svn/master/scx1000/trunk/
# - Try URL svn+ssh://svn.sicortex.com/void
# - Try URL svn+ssh://svn.sicortex.com/svn/void
# - Try URL svn+ssh://svn.sicortex.com/svn/master/void
# I decided to start with short URLs and grow them because it finds our
# void dir on the third try.  If I started with long URLs and shrank
# them, on deeper trees it would take more than three tries.
#
# Performance: Takes 1-2 seconds. But I'm not overly concerned because you only
# pay that penalty one time per checkout run, and only if you are using
# viewspecs.
sub void_url {
    my $self = shift;
    my %params = (#url=>,
                  @_);
    print "void_url url=$params{url}\n" if $self->debug;
    return $self->{void_url} if $self->{void_url};  # use cached copy
    my ($proto,$server,$path) = $params{url} =~ /(.*:\/{2,3})([^\/]+)(\/.*)/;
    die "%Error: could not parse url $params{url}" if !defined $proto || !defined $server || !defined $path;
    my $pathbuild = "$proto$server";
    # I wrote the above regexp so that $path has a slash in front. So the first
    # time through the loop, $pathpart="".
    foreach my $pathpart (split ('/', $path)) {
        $pathbuild .= "/" if $pathpart ne '';
	$pathbuild .= $pathpart;
	my $url = "$pathbuild/void";
	print "Try URL $url\n" if $self->debug;
	if ($self->is_file_in_repo(url=>$url)) {
	    $self->{void_url} = $url;  # found it! cache for next time.
	    return $url;                # I'm just gonna assume it's a directory
	}
    }
    die "%Error: Could not find void in any URL above $params{url}. To use viewspecs, you must create a top-level directory called void in the SVN repository.";
}

sub ensure_valid_rev_string {
    my $self = shift;
    my $rev = shift;
    return if $rev =~ /^[0-9]+$/;		# allow revision number
    return if $rev =~ /^{\d{4}-\d{2}-\d{2}}$/;	# allow {2006-01-01}
    return if $rev eq 'HEAD';			# allow HEAD keyword
    error "rev argument '$rev' must have the form: r2000 or r{2006-01-01} or HEAD";
}

sub ensure_valid_date_string {
    my $self = shift;
    my $date = shift;
    return if $date =~ /^\d{4}-\d{2}-\d{2}$/;	# allow 2006-01-01
    error "date argument '$date' must have the form: 2006-01-01";
}

######################################################################
#### Properties

sub propget_string {
    my $self = shift;
    my %params = (#filename =>
		  #propname =>
		  dryrun => $self->{dryrun},
		  quiet => $self->{quiet},
		  @_);
    # Return property value for given file/propname
    my $filename = $self->clean_filename($params{filename});
    print "\tsvn_propget $filename  $params{propname}\n" if $Debug;

    $self->open();
    my $pl = $self->client->proplist($filename, undef, 0);
    return undef if !$pl;
    foreach my $propitem (@{$pl}) {
	my $propval = $propitem->prop_hash->{$params{propname}};
	return $propval if defined $propval;
    }
    return undef;
}

sub propset_string {
    my $self = shift;
    my %params = (#filename =>
		  #propname =>
		  #propval =>
		  dryrun => $self->{dryrun},
		  quiet => $self->{quiet},
		  @_);
    # Set property name, only if not set yet
    my $filename = $self->clean_filename($params{filename});

    $self->open();
    my $stored = $self->propget_string(%params);
    if (!defined $stored || (($stored ne $params{propval})
			     && "$stored\n" ne $params{propval})) {
	print "    svn propset $params{propname} $filename\n" if !$params{quiet};
	$self->client->propset($params{propname}, $params{propval}, $params{filename}, 0) if !$params{dryrun};
    }
}

######################################################################
#### Package return
1;
=pod

=head1 NAME

SVN::S4 - Wrapper for Subversion

=head1 SYNOPSIS

  use SVN::S4;

=head1 DESCRIPTION

SVN::S4 is a derived class of SVN::Client.  The various SVN::S4::... classes
add member functions to this class to perform various functions.

=head1 METHODS

=over 4

=item $self->client

Return the SVN::Client object.

=item $self->propget_string(filename=>I<file>, propname=>I<prop>)

Return the string value of the property, or undef if not set or bad file.

=item $self->propset_string(filename=>I<file>, propname=>I<prop>, propval=>I<val>)

Set the string value of the property.

=item new (I<params>)

Create a new SVN::S4 object.

=back

=head1 DISTRIBUTION

The latest version is available from CPAN and from L<http://www.veripool.org/>.

Copyright 2002-2010 by Wilson Snyder.  This package is free software; you
can redistribute it and/or modify it under the terms of either the GNU
Lesser General Public License Version 3 or the Perl Artistic License Version 2.0.

=head1 AUTHORS

Bryce Denney <bryce.denney@sicortex.com> and
Wilson Snyder <wsnyder@wsnyder.org>

=head1 SEE ALSO

L<svn>, L<s4>

L<SVN::Client>,
L<SVN::S4::FixProp>,
L<SVN::S4::Getopt>,
L<SVN::S4::Info>,
L<SVN::S4::Path>,
L<SVN::S4::QuickCommit>,
L<SVN::S4::Snapshot>,
L<SVN::S4::StrongRevert>,
L<SVN::S4::Update>,
L<SVN::S4::ViewSpec>

=cut
######################################################################
