use warnings;
use strict;
use Data::Dumper;

# use module
use MP3::Tag;

# set filename of MP3 track
my $filename = $ARGV[0];

# create new MP3-Tag object
my $mp3 = MP3::Tag->new($filename);
my @tags = $mp3->get_tags();
print Dumper ($mp3);

__END__
print Dumper (\@tags);

if (exists $mp3->{ID3v2}) {

    my $frameIDs_hash = $mp3->{ID3v2}->get_frame_ids('truename');
    foreach my $frame (keys %$frameIDs_hash) {
	my ($name, @info) = $mp3->{ID3v2}->get_frames($frame);
	print "Frame: $frame " . ($name ? "Name: $name" : "") . Dumper (\@info);
    }
}
__END__

    my @frameIDs = $mp3->{ID3v2}->getFrameIDS;

    foreach my $frame (@frameIDs) {
	my ($info, $name) = $mp3->{ID3v2}->getFrame($frame);
	print Dumper ($info);
	if (ref $info) {
	    print "$name ($frame):\n";
	    while(my ($key,$val)=each %$info) {
		print " * $key => $val\n";
	    }
	} else {
	    print "$name: $info\n";
	}
    }
}




__END__
$mp3->get_tags();
print Dumper ($mp3);

__END__
# if ID3v2 tags exists
if (exists $mp3->{ID3v2})
{
	# get a list of frames as a hash reference
	my $frames = $mp3->{ID3v2}->get_frame_ids();
	print Dumper ($frames);
}
__END__
	# iterate over the hash
	# process each frame
	foreach my $frame (keys %$frames) 
	{
		# for each frame
		# get a key-value pair of content-description
  		($value, $desc) = $mp3->{ID3v2}->get_frame($frame);
		print "$frame $desc: ";
		# sometimes the value is itself a hash reference containing more values
		# deal with that here
		if (ref $value)
		{
			while (($k, $v) = each (%$value))
			{
				print "\n     - $k: $v";
			}
			print "\n";
		}
		else
		{
			print "$value\n";
		}
	}
}

# clean up
$mp3->close();
