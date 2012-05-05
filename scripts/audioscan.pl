#!/usr/bin/env perl
# Usage: audioscan [-info] *.mp3
#
# May 2012
# Martin Senger <martin.senger@gmail.com>
# ----------------------------------------
use warnings;
use strict;

use Audio::Scan;
use Data::Dump qw(dump);

my $info = 0;
foreach my $filename (@ARGV) {
    if ($filename eq '-info') {
	$info = 1;
	next;
    }
    my $data;
    if ($info) {
	$data = Audio::Scan->scan ($filename);
    } else {
	$data = Audio::Scan->scan_tags ($filename);
	delete $data->{info};
    }
    show ($filename, $data);
}

sub show {
    my ($filename, $data) = @_;
    print STDOUT "$filename\n";
    foreach my $key (keys %$data) {
	print STDOUT "\t$key\n";
	foreach my $name (sort keys %{ $data->{$key} }) {
	    my $value = $data->{$key}->{$name};
	    if (ref ($value)) {
		$value = dump ($value);
	    }
	    print STDOUT sprintf ("\t\t%-20s => %s\n", $name, $value);
	}
    }
}

__END__
