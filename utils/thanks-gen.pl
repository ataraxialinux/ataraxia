#!/usr/bin/env perl

# This script is intended to generate a "THANKS" file. It lists all
# contributors in the current git repository, removes or replaces some names
# with others (for contributors who have different git author names), sorts
# them alphabetically and writes it to stdout!
#
# Usage:
# ./thanks-gen > THANKS
#
# Please only execute it inside the root repository. Otherwise it leads to
# undefined behavior as the git command won't work then.

use strict;
use warnings;

# Replace the names with the following
# Use 'undef' to unthankify someone
my %special_names = (
  'Isihimoto Shinobu' => 'Ishimoto Shinobu',
  'root' => 'Ishimoto Shinobu',
  'Your Name' => undef,
  'foo' => undef
);

my %used_names;

my $output = qx(git shortlog -sn);
my @lines = split /\n/, $output;

my @names;

foreach(@lines) {
  my ($name) = $_ =~ /^\s*\d+\s+(.+?)$/;

  # Check if the name is special or forbidden
  if(exists($special_names{$name})) {
    # Forbidden name
    if(!defined($special_names{$name})) {
      next;
    }

    # Replace name
    $name = $special_names{$name};
  }

  # Check if name is already in file
  if(exists($used_names{$name})) {
    next;
  }
  $used_names{$name} = undef;

  # Append name
  push @names, $name;
}

# Sort alphabetically
@names = sort { lc($a) cmp lc($b) } @names;

# Write to stdout
print "The following people have contributed to Ataraxia GNU/Linux:\n\n";

foreach(@names) {
  print $_ . "\n";
}
