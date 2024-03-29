#-----------------------------------------------------------------
# App::cleanmusictags
# Author: Martin Senger <martin.senger@gmail.com>
# For copyright and disclaimer see the POD.
#
# ABSTRACT: Check and clean music tags in the music files
# PODNAME: App::cleanmusictags
#-----------------------------------------------------------------
use warnings;
use strict;

package App::cleanmusictags;
use parent 'App::Cmdline';

# VERSION

use File::Find ();
use File::Spec;
use Audio::Scan;
use Music::Tag (traditional => 1);
use MP3::Tag;
use Data::Dumper;

my $actions = {
    MISSALB => 'Missing album name',
    AMBIALB => 'Ambiguous album names',
    MOREART => 'More artists within the album',
    NONEART => 'No artist, at all',
    ALBARTA => 'Ambiguous album artist',
    SETCOLL => 'Set all pieces as parts of a collection',
    MISSTRK => 'Missing all track numbers',
    SOMETRK => 'Some track numbers are missing or duplicated',
    # DELCOMM => 'Remove comments',   #TBD
};

my $musicdir;    # where is my music
my $ignore;      # what issues to ignore (keys are action codes)
my $report;      # where to report
my $input;       # what to change (file with a previoulsy created report)
my $options;     # command-line options

#-----------------------------------------------------------------
# Command-line arguments and script usage.
# -----------------------------------------------------------------
sub opt_spec {
    my $self = shift;
    return $self->check_for_duplicates (
        [ 'music|dir=s'   => '<starting-directory> with music files',{ default => '/c/My Music' } ],
        [ 'report=s'      => '<report-filename> - music files will NOT be changed (this is default)' ],
        [ 'input=s'       => '<input-filename>  - music files will be changed'        ],
	[ 'list'          => 'show available "issue-codes" and exit'                  ],
	[ 'only=s@{0,}'   => '<issue-code>... report/change only the given issues'    ],
	[ 'ignore=s@{0,}' => '<issue-code>... report/change all but the given issues' ],
	[ 'verbose'       => 'print detailed comments (to the report or to STDOUT)'   ],
	[ 'donotchange'   => 'do not modify any files, just report potential changes' ],
	[ 'repsuggest'    => 'report only changes that have some suggestions'         ],
	[],
	$self->composed_of (
	    'App::Cmdline::Options::Basic',
	)
        );
}

sub validate_args {
    my ($self, $opt, $args) = @_;

    # do this first so we do not create empty report files
    # if just -h or -version are given
    $self->SUPER::validate_args ($opt, $args);

    # show list and exit
    if ($opt->list) {
	verbose ("CODE  \tISSUE\n");
	foreach my $key (sort keys %$actions) {
	    msg (join ('', "$key\t", $actions->{$key}, "\n"));
	}
        exit (0);
    }

    # remember options in a global variable
    $options = $opt;

    # add the full path to the starting directory 
    $musicdir = File::Spec->rel2abs ($opt->music);

    # prepare the handlers for report OR input
    # (report and input are mutually exclusive)
    if ($opt->report) {
	open ($report, '>', $opt->report)
	    or die "Cannot create '" . $opt->report . "': $!\n";
	if ($opt->input) {
	    warn "Both '--report' and '--input' given. The '--input' will be ignored.\n";
	}
    } elsif ($opt->input) {
	open ($input, '<', $opt->input)
	    or die "Cannot open '" . $opt->input . "': $!\n";
    } else {
	$report = *STDOUT;
    }

    # set what to ignore or what to do exclusively
    if ($opt->ignore) {
	$ignore = { map { uc ($_) => 1 } split (m{,}, join (',', @{ $opt->ignore })) };
    } else {
	$ignore = {};
    }
    if ($opt->only) {
	my $only   = { map { uc ($_) => 1 } split (m{,}, join (',', @{ $opt->only   })) };
	foreach my $issue (keys %$actions) {
	    $ignore->{$issue} = 1
		unless exists $only->{$issue};
	}
    }
}

#-----------------------------------------------------------------
# We want to process only directories.
#-----------------------------------------------------------------
sub wanted {
    my ($dev,$ino,$mode,$nlink,$uid,$gid);
    (($dev,$ino,$mode,$nlink,$uid,$gid) = lstat($_)) &&
    -d _ &&
    process_dir ($File::Find::name);
}

#-----------------------------------------------------------------
# Everything starts here.
#-----------------------------------------------------------------
sub execute {
    my ($self, $opt, $args) = @_;

    local $| = 1;

    if ($report) {
	# traverse, process desired directories and report
	File::Find::find ({ wanted => \&wanted }, $musicdir);

    } else {
	# modify files
 	my $wanted_changes = read_report();
	foreach my $album (@$wanted_changes) {
	    my $album_dir = $album->[0];
	    if ($options->donotchange) {
		# print info
		msg ("$album_dir\n");
		foreach my $code (keys %{ $album->[1] }) {
		    my $value = $album->[1]->{$code};
		    $value =~ s{^\s*|\s*$}{}g;
		    if ($value) {
			verbose ("\t$code => $value\n");
		    }
		}

	    } else {
		# find every MP3 file in this album
		opendir (my $dh, $album_dir)
		    or die "Cannot read $album_dir: $!\n";
		my @mp3files = sort grep { /\.mp3$/i && -f File::Spec->catfile ($album_dir, $_) } readdir ($dh);
		closedir ($dh);

		# modify each MP3 file
		msg ("Album: $album_dir"); verbose ("\n");
		my $file_count = 0;
		my $changes = 0;
		foreach my $file (@mp3files) {
		    $file_count++;
		    my $full_filename = File::Spec->catfile ($album_dir, $file);
		    my $code_options = { file       => $file,
					 file_count => $file_count };
		    foreach my $code (keys %{ $album->[1] }) {
			next if exists $ignore->{$code};
			my $value = $album->[1]->{$code};
			$value =~ s{^\s*|\s*$}{}g;
			next unless $value;
			no strict;
			if (&$code ($full_filename, $value, $code_options)) {
			    $changes++;
			    verbose ("\t$code => $value [$file]\n");
			}
		    }
		}
		if (!$options->verbose or $changes == 0) {
		    msg ("\t$changes changes made\n");
		}
	    }
	}
    }
    exit (0);
}

sub MISSALB { # 'Missing album name',
    return AMBIALB (@_);
}

sub AMBIALB { # 'Ambiguous album names',
    my ($filename, $value) = @_;

    # reading the current value using Audio::Scan because it does not
    # trip the read value (as Music::tag does)
    my $data = Audio::Scan->scan_tags ($filename);
    my $tags = $data->{tags};
    my $album = $tags->{TALB};
    return 0 if is_eq ($album, $value);

    my $taggable = get_taggable ($filename);
    $taggable->album ($value);
    $taggable->set_tag();
    $taggable->close();
    return 1;
}

sub MOREART { # 'More artists within the album',
    my ($filename, $value) = @_;
    # TBD: should use here also Audio::Scan for reading the current value (as in AMBIALB)
    my $taggable = get_taggable ($filename);
    if (is_eq ($taggable->artist(), $value)) {
	$taggable->close();
	return 0;
    } else {
	$taggable->artist ($value);
	$taggable->set_tag();
	$taggable->close();
	return 1;
    }
}

sub NONEART { # 'No artist, at all',
    return MOREART (@_);
}

sub ALBARTA { # 'Ambiguous album artist',
    my ($filename, $value) = @_;

    # reading the current value using Audio::Scan because it does not
    # trip the read value (as Music::tag does)
    my $data = Audio::Scan->scan_tags ($filename);
    my $tags = $data->{tags};
    my $album_artist = $tags->{TPE2};
    return 0 if is_eq ($album_artist, $value);
    return add_tag_directly ($filename, 'TPE2', $value);
}

sub SETCOLL { # 'Set all pieces as parts of a collection (compilation)',
    my ($filename, $value) = @_;
    return 0 unless lc($value) eq 'yes';
    return add_tag_directly ($filename, "TCMP", "1");
}

sub MISSTRK { # 'Missing all track numbers',
    my ($filename, $value, $options) = @_;
    return 0 unless lc ($value) eq 'number all tracks';
    my $track = $options->{file_count};
    my $taggable = get_taggable ($filename);

    $taggable->track ($track);
    $taggable->set_tag();
    $taggable->close();
    return 1;

    # if (is_eq ($taggable->tracknum(), $track)) {
    # 	$taggable->close();
    # 	return 0;
    # } else {
    # 	$taggable->tracknum ($track);
    # 	$taggable->set_tag();
    # 	$taggable->close();
    # 	return 1;
    # }
}

sub SOMETRK { # 'Some track numbers are missing or duplicated',
    return MISSTRK (@_);
}

sub get_taggable {
    my $taggable = Music::Tag->new (shift(), { quiet => 1 }, "Auto");
    $taggable->get_tag();
    return $taggable;
}

sub is_eq {
    my ($old_value, $new_value) = @_;
    return 0 unless defined $old_value;
    $old_value eq $new_value;
}

# Max Baker
# 4/29/09
# sub add_compilation {
#     my $file = shift;
#     my $mp3 = MP3::Tag->new ($file);
#     $mp3->config ('write_v24' => 1);
 
#     # scan file for existing tags
#     $mp3->get_tags;
 
#     unless (exists $mp3->{ID3v2}) {
#         $mp3->new_tag ("ID3v2");
#     }
 
#     # check for existing tag
#     my ($info, $name, @rest) = $mp3->{ID3v2}->get_frame("TCMP");
#     if (defined ($info)) {
# 	return 0;
#     }   
 
#     $mp3->{ID3v2}->add_frame ("TCMP", "1")
# 	or die "$file : Adding TCMP frame failed.\n";
#     $mp3->{ID3v2}->write_tag;
#     $mp3->close();
#     return 1;
# }

sub add_tag_directly {
    my ($file, $tag, $value) = @_;
    my $mp3 = MP3::Tag->new ($file);
    $mp3->config ('write_v24' => 1);
 
    # scan file for existing tags
    $mp3->get_tags;
 
    unless (exists $mp3->{ID3v2}) {
        $mp3->new_tag ("ID3v2");
    }
 
    # check for existing tag
    my ($info, $name, @rest) = $mp3->{ID3v2}->get_frame ($tag);
    if (defined ($info)) {
	return 0;
    }   
    $mp3->{ID3v2}->add_frame ($tag, $value)
	or die "$file : Adding $tag frame failed.\n";
    $mp3->{ID3v2}->write_tag;
    $mp3->close();
    return 1;
}

#-----------------------------------------------------------------
# Read the $input file into this structure (an example):
# [
#   [
#     '/c/My Music/testdata/Hity 1964 vol.2',
#     {
#       'SETCOLL' => 'yes',
#       'MOREART' => '',
#       'ALBARTA' => 'Various artists',
#       'AMBIALB' => 'Hity 1964'
#     }
#   ],
#   [
#     '/c/My Music/testdata/30 let Ceske Country/3',
#     {
#       'SETCOLL' => 'yes',
#       'MOREART' => '',
#       'ALBARTA' => 'Various artists'
#     }
#   ],
# Return this structure.
#-----------------------------------------------------------------
sub read_report {
    my $wanted_changes = [];
    my $album = [undef, {}];
    while (my $line = <$input>) {
	chomp $line;
	if ($line =~ m{^\s*ALBUM:\s*(.*)}i) {
	    # e.g.: ALBUM: /c/My Music/Hity 1964 vol.2
	    my $new_album = $1;
	    push (@$wanted_changes, $album)  # finalize the previous album
		if album_exists ($album->[0]);
	    $album = [$new_album, {}];       # and start a new album

	} elsif ($line =~ m{^\s*Change\s+to\s*\[([^\]]*)\]\s*\(([^\)]+)\)}i) {
	    # e.g.: Change to [Various artists] (ALBARTA) Missing album artist
	    my $change_to = $1;
	    my $code = $2;
	    $album->[1]->{$code} = $change_to;
	}
    }
    # finalize the last album
    push (@$wanted_changes, $album)
	if album_exists ($album->[0]);
    return $wanted_changes;
}

sub album_exists {
    my $albumdir = shift;
    return 0 unless defined $albumdir;
    return -d $albumdir;
}

#-----------------------------------------------------------------
# The main REPORTING job is done here.
#-----------------------------------------------------------------
sub process_dir {
    my $dirname = shift;
    opendir (my $dh, $dirname)
	or die "Cannot read $dirname: $!\n";
    my @mp3files = grep { /\.mp3$/i && -f File::Spec->catfile ($dirname, $_) } readdir ($dh);
    closedir ($dh);
    my $piece_count = scalar @mp3files;

    # only dirs with more than one MP3 file are of interest
    return unless $piece_count > 1;

    # guess the default name of an album from its directory name
    my @dirs = File::Spec->splitdir ($dirname);
    my $album_dirname = $dirs[-1] || '';
    comment ("$album_dirname: $piece_count music files ($dirname)");

    my $album_names = {};
    my $missing_album = 0;

    my $artists = {};
    my $missing_artists_count = 0;
    my $tcmp_count = 0;
    my $album_artist = {};
    my $missing_album_artist_count = 0;

    my $tracks = {};
    my $comments = {};

    {
	local $ENV{AUDIO_SCAN_NO_ARTWORK} = 1;
	foreach my $mp3file (@mp3files) {
	    my $filename = File::Spec->catfile ($dirname, $mp3file);
	    my $data = Audio::Scan->scan_tags ($filename);
	    my $tags = $data->{tags};

	    # check album name
	    if (defined $tags->{TALB}) {
		$album_names->{ $tags->{TALB} }++;
	    } else {
		$missing_album++;
	    }

	    # check artists
	    if (defined $tags->{TPE1}) {
		$artists->{ $tags->{TPE1} }++;
	    } else {
		$missing_artists_count++;
	    }
	    if (defined $tags->{TCMP} and $tags->{TCMP} == 1) {
		$tcmp_count++;
	    }

	    # check the album artist
	    if (defined $tags->{TPE2}) {
		$album_artist->{ $tags->{TPE2} }++;
	    } else {
		$missing_album_artist_count++;
	    }

	    # check tracks numbers
	    if (defined $tags->{TRCK}) {
		$tracks->{ $tags->{TRCK} }++;
	    }

	    # # check comments
	    # if (defined $tags->{COMM}) {
	    # 	print Dumper ($tags->{COMM});
	    # 	$comments->{ $tags->{COMM} }++;
	    # }
	}
    }
    my $hinfo = { header_printed => 0, dir => $dirname };

    # report about album name
    my $album_names_count = scalar keys (%$album_names);
    unless ($album_names_count > 0) {
	out (suggest ($hinfo, $album_dirname, 'MISSALB', $actions->{MISSALB}));
    }
    if ($album_names_count > 1) {
	my $max_count = $missing_album || 0;
	my $suggested_name = $album_dirname;
	my @names_counts = ();
	while ( my ($album_name, $count) = each %$album_names) {
	    if ($count > $max_count) {
		$max_count = $count;
		$suggested_name = $album_name;
	    }
	    push (@names_counts, sprintf ("(%2d) %s", $count, $album_name));
	}
	out (suggest ($hinfo, $suggested_name, 'AMBIALB',
		      $actions->{AMBIALB} . ":\n\t" . join ("\n\t", @names_counts) ));
    }

    # report about artists
    my $artists_count = scalar keys (%$artists);
    my $suggested_artist = '';
    if ($artists_count > 1 and $tcmp_count < $piece_count) {
	# more than 1 artists but not all pieces are part of a collection
	my $max_count = 0;
	my @names_counts = ();
	while ( my ($artist, $count) = each %$artists) {
	    if ($count > $max_count) {
		$max_count = $count;
		$suggested_artist = $artist;
	    }
	    push (@names_counts, sprintf ("(%2d) %s", $count, $artist));
	}
	if ($max_count < $piece_count / 2) {
	    # do not make any suggestion if the most used artist is
	    # still < 50% of non-empty artists pieces
	    $suggested_artist = '';
	}
	out (suggest ($hinfo, $suggested_artist, 'MOREART',
		      $actions->{MOREART} . ":\n\t" . join ("\n\t", @names_counts) ));
	out (suggest ($hinfo, 'yes', 'SETCOLL', $actions->{SETCOLL}));
    }
    if ($artists_count == 0) {
	# no artist, at all
	out (suggest ($hinfo, 'Various artists', 'NONEART', $actions->{NONEART}));
    }

    # report about album artist
    if ( (keys (%$album_artist) == 1 and $missing_album_artist_count > 0) or
	 (keys (%$album_artist) > 1) ) {
	 # there is just one album artist but not everywhere OR
	 # there are more album artists

	# use the most frequent album artists
	my ($frequent_album_artist) =
	    sort { $album_artist->{$a} <=> $album_artist->{$b}} keys %$album_artist;
	out (suggest ($hinfo, $frequent_album_artist, 'ALBARTA', $actions->{ALBARTA}));
    }

    # report about tracks
    my $track_count = scalar keys (%$tracks);
    my $track_issue = '';
    if ($track_count == 0) {
	$track_issue = 'MISSTRK';
    } elsif ($track_count < $piece_count) {
	$track_issue = 'SOMETRK';
    }
    if ($track_issue) {
	# missing (all or some) track numbers
	out (suggest ($hinfo, 'number all tracks', $track_issue, $actions->{$track_issue}));
    }

    # # report about comments
    # foreach my $comment (%$comments) {
    # 	out (suggest ($hinfo, 'remove', 'DELCOMM', $actions->{DELCOMM} . ": $comment"));
    # }

    out ("\n") if $hinfo->{header_printed};
}

sub errmsg {
    my ($dirname, $msg) = @_;
    print STDERR "[$dirname] $msg\n";
}

# --------------------------------------------------------------------
# Combine various pieces into a message with a suggestion what to
# modify. Return the message.
#
# Return an empty message if the given $code should be ignored.
#
# Before returning a real message, print the header unless it was
# already printed before. The information about the header is in
# $hinfo = { header_printed => 0, dir => $dirname }.
#
# --------------------------------------------------------------------
sub suggest {
    my ($hinfo, $suggestion, $code, $text) = @_;
    return if exists $ignore->{$code};
    return if $options->repsuggest and not $suggestion;
    unless ($hinfo->{header_printed}) {
	header ($hinfo->{dir});
	$hinfo->{header_printed} = 1; # remember that header is already out
    }
    return "Change to [$suggestion] ($code) $text\n";
}

# --------------------------------------------------------------------
# Print header with the album directory.
# --------------------------------------------------------------------
sub header {
    my $dirname = shift;
    out ("ALBUM: $dirname\n");
}

# --------------------------------------------------------------------
# Output the given message to the output file (unless the message is
# empty).
# --------------------------------------------------------------------
sub out {
    my $msg = shift;
    print $report $msg
	if $msg;
}

sub comment {
    out '# ' . shift() . "\n"
	if $options->verbose;
}

sub verbose {
    msg (shift)
	if $options->verbose;
}

sub msg {
    print STDOUT shift();
}

1;
__END__
