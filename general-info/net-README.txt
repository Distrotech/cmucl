CMU Common Lisp is a public domain implementation of Common Lisp.  Both
sources and executables are freely available via anonymous FTP; this software
is "as is", and has no warranty of any kind.  CMU and the authors assume no
responsibility for the consequences of any use of this software.  See
doc/release-notes.txt for a description of the state of the release you have.

The CMU Common Lisp project's goal is to develop a high quality public domain
system, so we want your bug reports, bug fixes and enhancements.  However,
staff limitations prevent us from providing extensive support to people outside
of CMU.  We are looking for university and industrial affiliates to help us
with porting and maintenance for hardware and software that is not widely used
at CMU.

See "man cmucl" (man/man1/cmucl.1) for other general information.

Distribution:

CMU Common Lisp is only available via anonymous FTP.  We don't have the
manpower to make tapes.  These are our distribution machines:
    lisp-rt1.slisp.cs.cmu.edu (128.2.217.9)
    lisp-rt2.slisp.cs.cmu.edu (128.2.217.10)

Log in with the user "anonymous" and "username@host" as password (i.e. your
EMAIL address.)  When you log in, the current directory should be set to the
CMU CL release area.  If you have any trouble with FTP access, please send mail
to slisp@cs.cmu.edu.

The release area holds compressed tar files with names of the form:
    <version>-<machine>_<os>.tar.Z
    <version>-extra-<machine>_<os>.tar.Z

FTP compressed tar archives in binary mode.  To extract, "cd" to the
directory that is to be the root of the tree, then type:
    uncompress <file.tar.Z | tar xf - .

As of 5/27/92, the latest SunOS Sparc release is:
    16d-sun4c_41.tar.Z (6.5 meg)
    16d-extra-sun4c_41.tar.Z (3.5 meg)

The first file holds binaries and documentation for the basic Lisp system,
while the second `-extra' file contains the Hemlock editor, the graphical
inspector and the CLX interface to X11.  The basic configuration takes 16
megabytes of disk space; adding the extras takes another 8 megabytes.  For
installation directions, see the section "site initialization" in README file
at the root of the tree.

If poor network connections make it difficult to transfer a 10 meg file, the
release is also available split into 2 megabyte chunks, suffixed `.0', `.1',
etc.  To extract from multiple files, use:
    cat file.tar.Z.* | uncompress | tar xf - .

The release area also contains source distributions and other binary
distributions.  A listing of the current contents of the release area is in
FILES.  Major release announcements will be made to comp.lang.lisp until there
is enough volume to warrant a comp.lang.lisp.cmu.

SunOS credit:

The SunOS support was written by Miles Bader and Ted Dunning.

SPARC Notes:

We have not done much SPARC-specific tuning.  Performance will improve from
10-30% when we add low-level optimizations such as instruction scheduling.  At
least 16 meg of memory is recommended, and more is better.

Site initialization:

To run CMU CL, place bin/ in PATH and setenv CMUCLLIB to point to lib/.  The
file lib/site-init.lisp contains site-specific initialization, such as setting
of the site name.  Any site-specific initialization should be placed in this
file; this file can be compiled.  See bin/sample-wrapper for a shell script
template that sets up environment variables and then runs CMU CL.  You may
want to have your EMACS maintainer place doc/cmu-user.info in the info root, or
you can setenv INFOPATH to include the doc/ directory.

To load in Hemlock or CLX and save an augmented Lisp image, run lib/config.
This runs `lisp' on `lib/config.lisp', which uses an interactive dialog to
determine what systems to load and where to save the result.  The default
output is to overwrite library:lisp.core.  To avoid overwriting the running
Lisp image, any existing image is renamed to `lisp.core.BAK'; this file may be
manually deleted to save disk space.

TMPFS NOTE:

It is not possible to mmap a file in a tmpfs filesystem.  If /tmp is a "tmpfs"
filesystem, then you must setenv CMUCL_EMPTYFILE to the pathname of some file
(in a normal filesystem) that can be used instead of /tmp/empty.  The "df"
command will show tmpfs filesystems as mounted on "swap".  If this problem
exists on your system, lisp will get an error like:
    mapin: mmap: Invalid argument
    ensure_space: Failed to validate 67108864 bytes at 0x01000000


Running CMU CL:

Run "lisp".  If Hemlock is loaded, you can also "lisp -edit".  Hemlock will
use X if the DISPLAY environment variable is defined, otherwise it will use
terminal i/o based on TERM and /etc/termcap.

Source availability:

Lisp and documentation sources are available via anonymous FTP ftp to any CMU
CS machine.  [See the "Distribution" section for FTP instructions.]  All CMU
written code is public domain, but CMU CL also makes use of two imported
packages: PCL and CLX.  Although these packages are copyrighted, they may be
freely distributed without any licensing agreement or fee.

The release area contains a source distribution, which is an image of all the
".lisp" source files used to build version 16d:
    16d-source.tar.Z (3.6 meg)

All of our files (including the release area) are actually in the AFS file
system.  On the release machines, the FTP server's home is the release
directory: /afs/cs.cmu.edu/project/clisp/release.  The actual working source
areas are in other subdirectories of "clisp", and you can directly "cd" to
those directories if you know the name.  Due to the way anonymous FTP
access control is done, it is important to "cd" to the source directory with a
single command, and then do a "get" operation.

Totally machine-independent compiler code:
    /afs/cs/project/clisp/src/beta/compiler/*.lisp
See especially node.lisp and ir1tran.lisp for the front end.  vop.lisp,
vmdef.lisp and ir2tran.lisp for the back end.

Stuff that is dependent on our choice of object format, but not
particularly machine-dependent:
    /afs/cs/project/clisp/src/beta/compiler/generic/*.lisp

Compiler back-end for the PMAX and SPARC:
    /afs/cs/project/clisp/src/beta/compiler/mips/*.lisp
    /afs/cs/project/clisp/src/beta/compiler/sparc/*.lisp

Miscellaneous Lisp run-time code:
    /afs/cs/project/clisp/src/beta/code/*.lisp

C run-time code:
    /afs/cs/project/clisp/src/beta/ldb/*

A very drafty version of an internal design document: (160 pages) Some of
the "tex" files may be more humanly readable, since many formatting
commands need to be added.  There is some inaccurate (dated) material in
the compiler description.
    /afs/cs/project/clisp/hackers/ram/docs/internals/*.tex
    /afs/cs/project/clisp/hackers/ram/docs/internals/design.ps

See hackers/ram/docs/internals/architecture.tex (the System Architecture
chapter in the internals document) for more information on the source tree
organization.
