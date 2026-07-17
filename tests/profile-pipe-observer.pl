#!/usr/bin/env perl
use strict;
use warnings;
use Time::HiRes qw(time);

my ($marker_file, $pattern) = @ARGV;
die "usage: $0 MARKER_FILE PATTERN\n" unless defined $marker_file && defined $pattern;

my $buffer = '';
while (sysread(STDIN, my $chunk, 4096)) {
    $buffer .= $chunk;
    if ($buffer =~ /\Q$pattern\E/) {
        open my $marker, '>', $marker_file or exit 1;
        printf {$marker} "%.6f\n", time();
        close $marker;
        exit 0;
    }
    substr($buffer, 0, -128) = '' if length($buffer) > 4096;
}

exit 0;
