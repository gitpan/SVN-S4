# $Id: Info.pm 51887 2008-03-10 13:46:15Z wsnyder $
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

package SVN::S4::Info;
require 5.006_001;

use SVN::S4;
use strict;
use Carp;
use IO::Dir;
use IO::File;
use Cwd;
use vars qw($AUTOLOAD);

use SVN::S4::Path;

our $VERSION = '1.030';

#######################################################################
# Methods

sub _status_switches_cb {
    my $s4 = shift;
    my ($path, $status) = @_;
    # Gets result from svn->status call; see SVN::Wc manpage
    if ($status->entry) {
	if (!$s4->{_info_cb_data}{files}  # First file
	    || $status->switched) {
	    printf "Path: %s\n",$path;
	    printf "URL: %s\n",$status->entry->url;
	    printf "Revision: %s\n", $status->entry->revision;
	    printf "Node Kind: %s\n", (($status->entry->kind == $SVN::Node::file) && "file"
				       || ($status->entry->kind == $SVN::Node::dir) && "directory"
				       || ($status->entry->kind == $SVN::Node::none) && "none"
				       || "unknown");
	    printf "Last Changed Author: %s\n", $status->entry->cmt_author;
	    printf "Last Changed Rev: %s\n", $status->entry->cmt_rev;
	    #printf "Last Changed Date: %s\n", $status->entry->cmt_date;

	    my $prop_rev = $s4->rev_on_date(url=>$status->entry->url,
					    date=>"HEAD");
	    printf "Head Rev: %s\n", $prop_rev;

	    print "\n";
	}
	$s4->{_info_cb_data}{files}++;
    }
}

#######################################################################
#######################################################################
#######################################################################
#######################################################################
# OVERLOADS of S4 object
package SVN::S4;

sub info_switches {
    my $self = shift;
    my %params = (#revision=>,
                  #paths=>,  # listref
                  @_);
    my @paths = @{$params{paths}};

    foreach my $path (@{$params{paths}}) {
	$path = $self->clean_filename($path);
	# State, for callback
	$self->{_info_cb_data} = {};
	# Do status
	my $stat = $self->client->status
	    ($path,		# path
	     "WORKING",		# revision
	     sub { SVN::S4::Info::_status_switches_cb($self,@_); }, # status func
	     1,			# recursive
	     1,			# get_all
	     0,			# update
	     0,			# no_ignore
	     );
    }
}

######################################################################
### Package return
package SVN::S4::Info;
1;
__END__

=pod

=head1 NAME

SVN::S4::Info - Enhanced update and checkout methods

=head1 SYNOPSIS

Shell:
  s4 info-switches PATH URL

Scripts:
  use SVN::S4::Info;
  $svns4_object->info_switches

=head1 DESCRIPTION

SVN::S4::Info 

=head1 METHODS

=over 4

=item info_switches

Perform a svn info on all of the switchpoints plus the trunk.

=back

=head1 DISTRIBUTION

The latest version is available from CPAN and from L<http://www.veripool.org/>.

Copyright 2006-2008 by Wilson Snyder.  This package is free software; you
can redistribute it and/or modify it under the terms of either the GNU
Lesser General Public License or the Perl Artistic License.

=head1 AUTHORS

Wilson Snyder <wsnyder@wsnyder.org>

=head1 SEE ALSO

L<SVN::S4>

=cut
