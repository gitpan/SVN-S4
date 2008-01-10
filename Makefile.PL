# $Id: Makefile.PL 49466 2008-01-10 19:56:49Z wsnyder $
# DESCRIPTION: Perl ExtUtils: Type 'perl Makefile.PL' to create a Makefile for this package
#
# Copyright 2006-2008 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.

require 5.005;
use ExtUtils::MakeMaker;
use Carp;

sub MY::postamble {
"
README: readme.texi
	-rm -rf \$@
	makeinfo \$< --output \$@ --no-headers --no-validate

clean::
	-rm -rf test_dir

dist: maintainer-copy distcheck README

## Maintainer use:
preexist:
	test ! -r \$(HOME)/src/kits/\$(DISTVNAME).tar.gz
	test -s README

tag:
	svnorcvs tag  \$(DISTNAME)_\$(VERSION_SYM)

maintainer-diff:
	svnorcvs diff \$(DISTNAME)_\$(VERSION_SYM) 

maintainer-dist: preexist dist tag
	cp \$(DISTVNAME).tar.gz \$(HOME)/src/kits
	mv \$(DISTVNAME).tar.gz \$(HOME)/backpack

maintainer-copy:

maintainer-clean: distclean
	-rm -rf README Makefile MANIFEST.bak \$(MAKEFILE_OLD)
";
}

{
    local $! = undef;
    my $ver = `svn --version`; ($?==0) or die "\n%Error: 'svn' must be installed to be useful\n";
    $ver =~ s/\n.*$//omg;
    print "Installed subversion: $ver\n";
}

## Remember to upgrade version number!
WriteMakefile(
	      DISTNAME	=> 'SVN-S4',
	      NAME	=> 'SVN::S4',
	      AUTHOR	=> 'Wilson Snyder <wsnyder@wsnyder.org>',
	      ABSTRACT_FROM => 'lib/SVN/S4.pm',
	      VERSION_FROM  => 'lib/SVN/S4.pm',
	      NO_META	=> 1,
	      PREREQ_PM => {'SVN::Client' => 0,
			    'IO::AIO' => 0,
			    'Digest::MD5' => 0,
			    'MIME::Base64' => 0,
			},
	      EXE_FILES	=> [qw( s4 )],
	      'clean'	=> {FILES => qw(test_store test_dir), },
	      'dist'	=> {COMPRESS => 'gzip -9f',
			    SUFFIX   => '.gz', 
			    DIST_DEFAULT => 'README all tardist',
			},
	      );

