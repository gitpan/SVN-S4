# $Id: FixProp.pm 49466 2008-01-10 19:56:49Z wsnyder $
# Author: Wilson Snyder <wsnyder@wsnyder.org>
######################################################################
#
# Copyright 2005-2008 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
######################################################################

package SVN::S4::FixProp;
require 5.006_001;

use SVN::S4;
use strict;
use Carp;
use IO::Dir;
use IO::File;
use Cwd;
use vars qw($AUTOLOAD);

use SVN::S4::Path;

our $VERSION = '1.022';

# Basenames we should ignore, because they contain large files of no relevance
our %_SkipBasenames = (
		      CVS => 1,
		      '.svn' => 1,
		      blib => 1,
		      );

#######################################################################
# Methods

sub skip_filename {
    my $filename = shift;
    (my $basename = $filename) =~ s!.*/!!;
    return $_SkipBasenames{$basename}
}

sub file_has_keywords {
    my $filename = shift;
    # Return true if there's a svn metacomment in $filename

    return undef if readlink $filename;
    my $fh = IO::File->new("<$filename") or return undef;
    my $lineno = 0;
    while (defined(my $line = $fh->getline)) {
	$lineno++; last if $lineno>1000;
	if ($line =~ /[\001\002\003\004\005\006]/) {
	    # Binary file.
	    $fh->close;
	    return 0;
	}
	if ($line =~ /\$(LastChangedDate|Date|LastChangedRevision|Revision|Rev|LastChangedBy|Author|HeadURL|URL|Id)[: \$]/) {
	    $fh->close;
	    return 1;
	}
	if ($lineno==1 && $line =~ /^SVN-fs-dump-format/) {
	    return 0;
	}
    }
    $fh->close;
    return 0;
}

#######################################################################
#######################################################################
#######################################################################
#######################################################################
# OVERLOADS of S4 object
package SVN::S4;

sub fixprops {
    my $self = shift;
    my %params = (#filename=>,
		  keyword_propval => 'author date id revision',
		  recurse => 1,
		  personal => undef,
		  @_);

    my $filename = $params{filename};
    $filename = $ENV{PWD}."/".$filename if $filename !~ m%^/%;
    _fixprops_recurse($self,\%params,$filename);
}

sub _fixprops_recurse {
    my $self = shift;
    my $param = shift;
    my $filename = shift;

    if (-d $filename) {
	my $dir = $filename;
	print "In $dir\n" if $self->debug;
	if (!-r "$dir/.svn") {
	    # silently ignore a non a subversion directory
	} else {
	    my $dh = new IO::Dir $dir or die "%Error: Could not directory $dir.\n";
	    while (defined (my $basefile = $dh->read)) {
		next if $basefile eq '.' || $basefile eq '..';
		my $file = $dir."/".$basefile;
		next if SVN::S4::FixProp::skip_filename($file);
		if (-d $file) {
		    if ($param->{recurse} && !readlink $file) {
			_fixprops_recurse($self,$param,$file);
		    }
		} else {
		    if ($param->{recurse} || $file =~ m!/\.cvsignore$!) {
			# If not recursing, we did a dir with -N; process the dir's ignore
			_fixprops_recurse($self,$param,$file);
		    }
		}
	    }
	    $dh->close();
	}
    }
    else {
	# File
	if ($filename =~ m!^(.*)/\.cvsignore$!) {
	    my $dir = $1;
	    print ".cvsignore check $dir\n" if $self->debug;
	    if ($self->file_url(filename=>$dir)) {
		$self->_fixprops_add_ignore($dir);
	    }
	}
	elsif (SVN::S4::FixProp::file_has_keywords($filename)) {
	    if ($self->file_url(filename=>$filename)
		&& !defined ($self->propget_string(filename=>$filename,
						   propname=>"svn:keywords"))
		&& (!$param->{personal}
		    || $self->is_file_personal(filename=>$filename))) {
		$self->propset_string(filename=>$filename, propname=>"svn:keywords",
				      propval=>$param->{keyword_propval});
	    }
	}
    }
}

sub _fixprops_add_ignore {
    my $self = shift;
    my $dir = shift;
 
    my $ignores = SVN::S4::Path::wholefile("$dir/.cvsignore");
    if (defined $ignores) { # else not found
	$ignores .= "\n";
	$ignores =~ s/[ \t\n\r\f]+/\n/g;
	$self->propset_string(filename=>$dir, propname=>"svn:ignore", propval=>$ignores);
    }
}

######################################################################
### Package return
package SVN::S4::FixProp;
1;
__END__

=pod

=head1 NAME

SVN::S4::FixProp - Fix svn:ignore and svn:keywords properties

=head1 SYNOPSIS

Shell:
  s4 fixprop {files_or_directories}

Scripts:
  use SVN::S4::FixProp;
  $svns4_object->fixprop(filename=>I<filename>);

=head1 DESCRIPTION

SVN::S4::FixProp provides utilities for changing properties on a file-by-file basis.

=head1 METHODS

=over 4

=item file_has_keywords(I<filename>)

Return true if the filename contains a SVN metacomment.

=item skip_filename(I<filename>)

Return true if the filename has a name which shouldn't be recursed on.

=back

=head1 METHODS ADDED TO SVN::S4

The following methods extend to the global SVN::S4 class.

=over 4

=item $s4->fixprops

Recurse the specified files, searching for .cvsignore or keywords that need
repair.

=back

=head1 DISTRIBUTION

The latest version is available from CPAN and from L<http://www.veripool.com/>.

Copyright 2005-2008 by Wilson Snyder.  This package is free software; you
can redistribute it and/or modify it under the terms of either the GNU
Lesser General Public License or the Perl Artistic License.

=head1 AUTHORS

Wilson Snyder <wsnyder@wsnyder.org>

=head1 SEE ALSO

L<SVN::S4>

=cut
