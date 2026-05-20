#!/usr/bin/perl
# Phase 1.5 performance harness — metrics parser and differ.
#
#   perf-report.pl <callgrind.txt> <massif.out> <sizes.txt>   -> JSON
#   perf-report.pl --diff <baseline.json> <current.json>      -> table
#
# Pure core Perl: no JSON module, no CPAN. The JSON we emit is flat
# enough that the differ re-reads it with a plain regex.

use strict;
use warnings;

if (@ARGV == 3 && $ARGV[0] eq '--diff') {
  diff($ARGV[1], $ARGV[2]);
  exit 0;
}
die "usage: perf-report.pl <callgrind.txt> <massif.out> <sizes.txt>\n"
  unless @ARGV == 3;

my %callgrind = parse_callgrind($ARGV[0]);
my $peak_heap = parse_massif($ARGV[1]);
my %size      = parse_sizes($ARGV[2]);

# Cachegrind's documented cycle estimate: each L1 miss ~10 cycles, each
# last-level miss ~100, each mispredicted branch ~10.
my $l1  = ($callgrind{i1mr}//0) + ($callgrind{d1mr}//0) + ($callgrind{d1mw}//0);
my $ll  = ($callgrind{ilmr}//0) + ($callgrind{dlmr}//0) + ($callgrind{dlmw}//0);
my $brm = ($callgrind{bcm}//0)  + ($callgrind{bim}//0);
my $cycles = ($callgrind{ir}//0) + 10*$l1 + 100*$ll + 10*$brm;

print "{\n";
print "  \"callgrind\": {\n";
print "    \"ir\": ",                $callgrind{ir}//0,   ",\n";
print "    \"estimated_cycles\": ",   $cycles,             ",\n";
print "    \"l1_misses\": ",          $l1,                 ",\n";
print "    \"llc_misses\": ",         $ll,                 ",\n";
print "    \"branch_mispredicts\": ", $brm,                "\n";
print "  },\n";
print "  \"massif\": {\n";
print "    \"peak_heap_bytes\": ",    $peak_heap,          "\n";
print "  },\n";
print "  \"size\": {\n";
print "    \"drizzled_bytes\": ",        $size{drizzled}//0,  ",\n";
print "    \"plugins_total_bytes\": ",   $size{plugins}//0,   ",\n";
print "    \"plugin_count\": ",          $size{plugin_count}//0, "\n";
print "  }\n";
print "}\n";
exit 0;

# --------------------------------------------------------------------
sub parse_callgrind {
  my ($file) = @_;
  open my $fh, '<', $file or die "perf-report: cannot read $file: $!\n";
  my @events;
  my %v;
  while (my $line = <$fh>) {
    if ($line =~ /^Events shown:\s+(.+?)\s*$/) {
      @events = map { lc } split ' ', $1;
    }
    if ($line =~ /\bPROGRAM TOTALS\s*$/) {
      (my $nums = $line) =~ s/\s*PROGRAM TOTALS\s*$//;
      my @n = grep { /\d/ } split ' ', $nums;
      s/,//g for @n;
      # Zip values onto event names positionally. Ir is always first,
      # so the headline metric survives even a column-count surprise.
      if (@events) {
        $v{$events[$_]} = $n[$_] for grep { defined $n[$_] } 0 .. $#events;
      } elsif (@n) {
        $v{ir} = $n[0];
      }
      last;
    }
  }
  close $fh;
  die "perf-report: no PROGRAM TOTALS in callgrind output\n" unless %v;
  return %v;
}

sub parse_massif {
  my ($file) = @_;
  open my $fh, '<', $file or die "perf-report: cannot read $file: $!\n";
  my ($peak, $heap, $extra) = (0, 0, 0);
  while (my $line = <$fh>) {
    $heap  = $1 if $line =~ /^mem_heap_B=(\d+)/;
    $extra = $1 if $line =~ /^mem_heap_extra_B=(\d+)/;
    if ($line =~ /^mem_stacks_B=/) {     # last field of a snapshot
      my $total = $heap + $extra;
      $peak = $total if $total > $peak;
    }
  }
  close $fh;
  return $peak;
}

sub parse_sizes {
  my ($file) = @_;
  open my $fh, '<', $file or die "perf-report: cannot read $file: $!\n";
  my %s = (drizzled => 0, plugins => 0, plugin_count => 0);
  while (my $line = <$fh>) {
    next unless $line =~ /^\s*(\d+)\s+(\d+)\s+(\d+)\s+\d+\s+\S+\s+(\S+)/;
    my ($text, $data, $bss, $path) = ($1, $2, $3, $4);
    my $bytes = $text + $data + $bss;
    if ($path =~ /drizzled$/) {
      $s{drizzled} = $bytes;
    } else {
      $s{plugins} += $bytes;
      $s{plugin_count}++;
    }
  }
  close $fh;
  return %s;
}

# --------------------------------------------------------------------
# Flatten a metrics JSON file into "section.key => number". The JSON is
# our own flat emission, so a line-wise regex is enough.
sub load_metrics {
  my ($file) = @_;
  open my $fh, '<', $file or die "perf-report: cannot read $file: $!\n";
  my %m;
  my $section = '';
  while (my $line = <$fh>) {
    if ($line =~ /^\s*"(\w+)":\s*\{/) { $section = $1; next; }
    if ($line =~ /^\s*"(\w+)":\s*(-?\d+)/) {
      $m{"$section.$1"} = $2;
    }
  }
  close $fh;
  return %m;
}

sub diff {
  my ($base_file, $cur_file) = @_;
  my %base = load_metrics($base_file);
  my %cur  = load_metrics($cur_file);

  printf "%-32s %18s %18s %10s\n", 'metric', 'baseline', 'current', 'delta';
  printf "%s\n", '-' x 80;
  for my $k (sort keys %cur) {
    my $c = $cur{$k};
    my $b = $base{$k};
    if (!defined $b) {
      printf "%-32s %18s %18d %10s\n", $k, '(new)', $c, '--';
      next;
    }
    my $delta = $b ? sprintf('%+.2f%%', 100 * ($c - $b) / $b) : '--';
    printf "%-32s %18d %18d %10s\n", $k, $b, $c, $delta;
  }
}
