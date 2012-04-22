use warnings;
use strict;

use Audio::Scan;
use Data::Dumper;

my $filename = $ARGV[0];

# my $data = Audio::Scan->scan ($filename);
# print Dumper ($data);

# # Just file info
# my $info = Audio::Scan->scan_info ($filename);
# print Dumper ($info);

# Just tags
my $tags = Audio::Scan->scan_tags ($filename);
print Dumper ($tags);
