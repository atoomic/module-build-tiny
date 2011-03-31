package Module::Build::Tiny;
use strict;
use warnings;
use Exporter 5.57 'import';
our $VERSION = '0.006';
our @EXPORT  = qw/Build Build_PL/;

use CPAN::Meta;
use ExtUtils::BuildRC qw/read_config/;
use ExtUtils::Helpers qw/make_executable split_like_shell build_script/;
use ExtUtils::Install qw/pm_to_blib install/;
use ExtUtils::InstallPaths;
use File::Path qw/rmtree/;
use File::Find::Rule qw/find/;
use File::Slurp qw/read_file write_file/;
use File::Spec::Functions qw/catfile catdir rel2abs/;
use Getopt::Long qw/GetOptions/;
use JSON::PP qw/encode_json decode_json/;
use TAP::Harness;

my ($metafile) = grep { -e $_ } qw/META.json META.yml/ or die "No META information provided\n";
my $meta = CPAN::Meta->load_file($metafile);

sub _build {
	my %map = map { $_ => catfile('blib', $_) } find(file => name => [qw/*.pm *.pod/], in => 'lib'), find(file => in => 'script');
	pm_to_blib(\%map, catdir(qw/blib lib auto/));
	make_executable($_) for find(file => in => catdir(qw/blib script/));
}

my %actions = (
	build => \&_build,
	test  => sub {
		my %opt = @_;
		_build();
		my $tester = TAP::Harness->new({verbosity => $opt{verbose}, lib => rel2abs(catdir(qw/blib lib/)), color => -T STDOUT});
		$tester->runtests(sort +find(file => name => '*.t', in => 't'));
	},
	install => sub {
		my %opt = @_;
		_build();
		my $paths = ExtUtils::InstallPaths->new(%opt, module_name => $meta->name);
		install($paths->install_map, @opt{'verbose', 'dry_run', 'uninst'});
	},
	clean => sub {
		rmtree('blib');
	},
	realclean => sub {
		rmtree($_) for qw/blib Build _build_params MYMETA.yml MYMETA.json/;
	},
);

sub _get_options {
	my ($action, $bpl) = @_;
	my $rc_opts = read_config();
	my @env = defined $ENV{PERL_MB_OPT} ? split_like_shell($ENV{PERL_MB_OPT}) : ();
	unshift @ARGV, map { @{$_} } grep { defined } $rc_opts->{'*'}, $bpl, $rc_opts->{$action}, \@env;
	GetOptions(\my %opt, qw/install_base=s install_path=s% installdirs=s destdir=s prefix=s uninst:1 verbose:1 dry_run:1/);
	return %opt;
}

sub Build {
	my $bpl    = decode_json(read_file('_build_params'));
	my $action = @ARGV && $ARGV[0] =~ /\A\w+\z/ ? $ARGV[0] : 'build';
	$actions{$action} ? $actions{$action}->(_get_options($action, $bpl)) : die "No such action '$action'\n";
}

sub Build_PL {
	printf "Creating new 'Build' script for '%s' version '%s'\n", $meta->name, $meta->version;
	my $dir = $meta->name eq 'Module-Build-Tiny' ? 'lib' : 'inc';
	write_file(build_script(), "#!perl\n", "use lib '$dir';\nuse Module::Build::Tiny;\nBuild();\n");
	make_executable(build_script());
	write_file(qw/_build_params/, encode_json(\@ARGV));
	write_file("MY$_", read_file($_)) for grep { -f } qw/META.json META.yml/;
}

1;

__END__

=head1 NAME

Module::Build::Tiny - A tiny replacement for Module::Build

=head1 SYNOPSIS

 # First, install Module::Build::Tiny

 # Then copy this file into inc

 # Then create this Build.PL
 use lib 'inc';
 use Module::Build::Tiny;
 Build_PL();

 # That's it!

=head1 DESCRIPTION

Many Perl distributions use a Build.PL file instead of a Makefile.PL file
to drive distribution configuration, build, test and installation.
Traditionally, Build.PL uses Module::Build as the underlying build system.
This module provides a simple, lightweight, drop-in replacement.

Whereas Module::Build has over 6,700 lines of code; this module has under
200, yet supports the features needed by most pure-Perl distributions along
with some useful automation for lazy programmers.  Plus, it bundles itself
with the distribution, so end users don't even need to have it (or
Module::Build) installed.

=head2 Supported

  * Pure Perl distributions
  * Recursive test files
  * Automatic 'requires' and 'build_requires' detection (see below)
  * Automatic MANIFEST generation
  * Automatic MANIFEST.SKIP generation (if not supplied)
  * Automatically bundles itself in inc/
  * MYMETA

=head2 Not Supported

  * Dynamic prerequisites
  * Generated code from PL files
  * Building XS or C
  * Manpage or HTML documentation generation
  * Subclassing Module::Build::Tiny
  * Licenses in META.yml other than 'perl'

=head2 Other limitations

  * May only work on a Unix-like or Windows OS
  * This is an experimental module -- use at your own risk

=head2 Directory structure

Your .pm and .pod files must be in F<lib/>.  Any executables must be in
F<bin/>.  Test files must be in F<t/>.  Bundled test modules must be in
F<t/lib/>.

=head2 Automatic prequisite detection

Prerequisites of type 'requires' are automatically detected in *.pm files
in F<lib/> from lines that contain a C<use()> function with a version
number.  E.g.:

  use Carp 0 qw/carp croak/;
  use File::Spec 0.86 ();

Lines may have leading white space.  You may not have more than one
C<use()> function per line.  No other C<use()> or C<require()> functions
are detected.

Prerequisites of type 'build_requires' are automatically detected in a
similar fashion from any *.t files (recusively) in F<t/> and from any
*.pm files in F<t/lib/>.

=head1 USAGE

These all work pretty much like their Module::Build equivalents.

=head2 perl Build.PL

=head2 Build

=head2 Build test

=head2 Build install

This supports the following options:

=over

=item * install_base

=item * installdirs

=item * prefix

=item * install_path

=item * destdir

=item * uninst

=back


=head2 Build clean

=head2 Build realclean

=head2 Build distdir

=head2 Build dist

=head1 CONFIG FILE AND ENVIRONMENT

Options can be provided in a F<.modulebuildrc> file or in the C<PERL_MB_OPT>
environment variable the same way they can with Module::Build.

=head1 SEE ALSO

L<Module::Build>

=head1 AUTHOR

  David Golden <dagolden@cpan.org>
  Leon Timmermans <leont@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by David A. Golden, Leon Timmermans

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
# vi:et:sts=2:sw=2:ts=2
