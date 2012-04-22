use warnings;
use strict;
use Data::Dumper;

use Music::Tag (traditional => 1);
my $info = Music::Tag->new ($ARGV[0], "Auto");
$info->get_tag();
print Dumper ($info);
   
#print 'Performer is ', $info->artist(), "\n";
#print 'Album is ', $info->album(), "\n";
#print 'Compilation is ', $info->compilation(), "\n";

my $bighash = $info->data();
print Dumper($bighash);
