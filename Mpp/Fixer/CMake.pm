# $Id: CMake.pm,v 1.2 2011/08/06 11:43:31 pfeiffer Exp $

=head1 NAME

Mpp::Fixer::CMake - Fix CMake Makefiles so they become nice

=head1 DESCRIPTION

CMake generates a highly recursive build system that causes deep recursion.
This is replaced by include and load_makefile statements for everything and
marks the highest Makefile as though it were a RootMakeppfile.  This is
activated automatically whenever we detect a makefile that was generated by
CMake.

=cut

package Mpp::Fixer::CMake;

use Mpp::File;
use Mpp::Glob 'zglob';

#
# This subroutine rewrites all the highly recursive CMmake makefiles, as best as we can.
# Arguments: the variable containing the makefile contents and the makefile object.
#
sub fix {
  my( $ROOT ) = $_[0] =~ /^CMAKE_BINARY_DIR\s*=\s*(.+)/m # Just a flags file or so
    or return;
  Mpp::log LOAD_CMAKE => $_[1]
    if $Mpp::log_level;
  $ROOT = path_file_info $ROOT;
  my $is_root = $ROOT == $_[1]{'..'};
  $_[0] =~ s!^(default_target) *: *all\n\.PHONY *: *\1!\$(phony $1):all\nload_makefile $ROOT->{FULLNAME}/Makefile!m
				# Insert this after default target (to not change it) but before everything else
    unless $is_root || $ROOT->{ROOT} || $_[1]{NAME} ne 'Makefile';
  $_[0] = join "\n",
    map /:.*\n\t/ ? ($is_root ? &fix_rule : /\Acmake_check_build_system:/ ? '' : &fix_rule) : $_,
				# check_bs is performed only by root Makefile
    split /\n(?![\t])/, $_[0];
  if( $is_root ) {
    $ROOT->{ROOT} = $ROOT;
    undef $_[1]{'..'}{xNO_IMPLICIT_LOAD};
    $_[0] .= '
prebuild cmake_check_build_system
include CMakeFiles/Makefile2
load_makefile ' . join ' ', zglob '*/**/build.make', $_[1]{'..'};
  			# glob early because CMake marks some dirs phony, then it's too late
  } elsif( $_[1]{NAME} eq 'build.make' ) {
    $_[1]{'..'}{MAKEINFO}{CWD} = $ROOT; # Each build.make can have different FLAGS, but they all pertain to the same dir
  }
}


# If the rule just recurses with the same target, drop it, because we load the makefile with the real rule.
# If the rule recurses with a different target, add it as a dependency instead.
sub fix_rule {
  s/:\s*cmake_check_build_system/:/; # Gets prebuilt, so don't have everyone depend on it
  s/\A(.*?): *(.*)\n\t//m;
  my( $output, $deps, @deps ) = ($1, $2);
  my @cmds = split "\n\t";
  my $empty = 0;
  for( my $i = 0; $i < @cmds; ) {
    if( $cmds[$i] =~ /^\$\(MAKE\) -f .+ (.+)/ ) { # Turn recursion into dependency
      push @deps, $1 if $1 ne $output;
      splice @cmds, $i, 1;
      ++$empty;
    } elsif( $cmds[$i] =~ /^cd (.+?) *&& *\$\(MAKE\) -f .+ (.+)/ ) { # Turn recursion into dependency
      my $dep = relative_filename path_file_info( "$1/$2", $_[1]{'..'} ), $_[1]{'..'};
      push @deps, $dep if $dep ne $output;
      splice @cmds, $i, 1;
      ++$empty;
    } elsif( $cmds[$i] =~ /\$\(CMAKE_COMMAND\) -E cmake_(?:depends|progress_(?:start|report)) / ) {
				# Do dependencies ourself.  The undocumented progress stuff wrapped the
				# recursive invocations.  As we elimate those, progrss marks don't appear
				# anymore...  So eliminate the waste of time.
      splice @cmds, $i, 1;
      ++$empty;
    } else {
      ++$i;
    }
  }
  $deps .= " $deps[-1]" if @deps;
  if( $deps || @cmds ) {
    $_ = join "\n\t", "$output:$deps", @cmds;
  } else {
    $_ = '';
  }
  while( @deps > 1 ) {
    $_ .= "\n" . pop @deps;
    $_ .= ":$deps[-1]";
    --$empty;
  }
  $_ .= "\n" x $empty;
  $_;
}

1;
