# See copyright, etc in below POD section.
######################################################################

package SVN::S4::QuickCommit;
require 5.006_001;

use strict;
use Carp;
use IO::Dir;
use IO::File;
use Cwd;
use Digest::MD5;
use MIME::Base64;
use vars qw($AUTOLOAD);

use SVN::S4;
use SVN::S4::Debug qw (DEBUG is_debug);
use SVN::S4::Path;

our $VERSION = '1.053';

our @Quick_Commit_status_data;
our $Quick_Commit_self;

#######################################################################
# Methods

#######################################################################
#######################################################################
#######################################################################
#######################################################################
# OVERLOADS of S4 object
package SVN::S4;
use SVN::S4::Debug qw (DEBUG is_debug);

######################################################################
### Package return
#package SVN::S4::QuickCommit;

sub quick_commit {
    my $self = shift;
    # Self contains:
    #		debug
    #		quiet
    #		dryrun
    my %params = (#path=>,
		  recurse => 1,
		  file => [],
		  message => [],
                  @_);

    #DEBUG ("IN self ",Dumper($self), "params ",Dumper(\%params)) if $self->debug;
    $Quick_Commit_self = $self;

    my @newpaths;
    foreach my $path ($params{path}) {
	push @newpaths, $self->abs_filename($path);
    }

    my @files;
    foreach my $path (@newpaths) {
	push @files, $self->find_commit_stuff ($path, \%params);
    }

    if ($#files >= 0) {
	my @args = (($self->{quiet} ? "--quiet" : ()),
		    ($self->{dryrun} ? "--dry-run" : ()),
		    #
		    "commit",
		    "--non-recursive",	# We've expanded files already
		    (defined $params{message}[0] ? ("-m", $params{message}[0]) : ()),
		    (defined $params{file}[0] ? ("-F", $params{file}[0]) : ()),
		    @files);
	DEBUG Dumper(\@args) if $self->debug;
	if (!$self->{dryrun}) {  # svn doesn't accept ci --dry-run
	    $self->run_svn(@args);
	}
    }
}

sub find_commit_stuff {
    my ($self, $path, $params) = @_;
    # do svn status and record anything that looks strange.
    DEBUG "find_commit_stuff '$path'...\n" if $self->debug;

    undef @Quick_Commit_status_data;
    my $stat = $self->client->status (
	    $path,		# canonical path
	    "WORKING",		# revision
	    \&Quick_Commit_statfunc,	# status func
	    ($params->{recurse}?1:0),	# recursive
	    0,			# get_all
	    0,			# update
	    0,			# no_ignore
	    );
    return @Quick_Commit_status_data;
}

sub Quick_Commit_statfunc {
    my ($path, $status) = @_;
    my $stat = $status->text_status;

    my $text_status_name = $SVN::S4::WCSTAT_STRINGS{$stat};
    die "s4: %Error: text_status code $stat not recognized" if !defined $text_status_name;
    my $pstat = $status->prop_status;
    my $prop_status_name = $SVN::S4::WCSTAT_STRINGS{$pstat};
    die "s4: %Error: prop_status code $pstat not recognized" if !defined $prop_status_name;
    if ($Quick_Commit_self->debug) {
	print "================================\n";
	print "path = $path\n";
	print "text_status = $text_status_name\n";
	print "prop_status = $prop_status_name\n";
    }
    if ($Quick_Commit_self->{debug}) {  # Was {quiet} but commit will also print msg
	printf +("%s%s     %s\n",
		 $SVN::S4::WCSTAT_LETTERS{$stat},
		 $SVN::S4::WCSTAT_LETTERS{$pstat},
		 $path);
    }

    if ($status->text_status != $SVN::Wc::Status::ignored
	&& $status->text_status != $SVN::Wc::Status::unversioned) {
	push @Quick_Commit_status_data, $path;
    }

    return 0;
}

1;
__END__

=pod

=head1 NAME

SVN::S4::QuickCommit - commit only changed files

=head1 SYNOPSIS

Scripts:
  use SVN::S4::QuickCommit;
  $svns4_object->quick_commit (path=>I<path>);

=head1 DESCRIPTION

SVN::S4::QuickCommit

=head1 METHODS

=over 4

=item $s4->quick_commit(path=>I<path>);

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
