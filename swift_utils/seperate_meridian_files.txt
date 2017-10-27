#! /usr/bin/perl -w 

use warnings;
use strict;
use Carp;
use Getopt::Std;
use File::Copy qw(move);

# Script to split the swift messages in a meridian CSV dump into seperate files.
# Files are named with the transaciotn number and message type from each record
# adjusted according to options given on commandline

# source file format is:
# TRNO,MERIDIANMESSAGETYPE,NETWORKDEPENDENTFORMAT

# the swift message is in field NETWORKDEPENDENTFORMAT, it is mulliline with quotes

my %opts;
getopts('f:d:s:xm:u', \%opts);

# -f = The source csv file to split
my $sourcefile = $opts{'f'} if defined $opts{'f'};

# -d = The output directory for split files. Default is current dir
my $output_dir =".";
$output_dir = $opts{'d'} if defined $opts{'d'};

# -s = Suffix to use on files. Default is xml
my $output_suffix ="xml";
$output_suffix = $opts{'s'} if defined $opts{'s'};

# -x = Don't include mtype in file name. Default is to include
my $include_mtype = 1;
$include_mtype = 0 if defined $opts{'x'};

# -m 1 = Move duplicates to a seperate folder and use the session/sequence number in the name 
#        to difference them.
# -m 2 = Move duplicates to a seperate folder with -DUPx extension added to 
#        difference them.
# If not set duplicates remain in the main folder with -DUPx extension added to 
# difference them.
my $strip_dups = 0;
$strip_dups = $opts{'m'} if defined $opts{'m'};

# -u = Remove / characters. Default is to replace / with _ character. 
my $replace_slash = 1;
$replace_slash = 0 if defined $opts{'u'};

open (my $fh, '<', $sourcefile) || croak "Failed to open file: $!";

# skip header
my $line = <$fh>;
my $output_file;
my $dupcount=1;
my %dupHash;
if ($strip_dups == 1) {
	mkdir("$output_dir/dups") || croak "failed to make dup dir: $!";
}  

while ($line = <$fh>) {
	chomp $line;
	my @fields = split (/,/, $line);
	if ( @fields == 3 &&
		 ($fields[2] =~ m/\{1:/)) {
		 	# first line of a message
		 	# close last message
		 	close $output_file if defined $output_file;
		 	# get rid of the quotes
			for (@fields) {
			   s/"//g;
			}		 	
		 	my $type = $fields[1];
		 	$type =~s/SWIFT_//;
		 	my $id = $fields[0];
		 	# filename alterations: 
		 	#   Remove the :SEMA// prefix put on some calypso msg type ids
		 	$id =~ s/:SEME\/\///;
		 	#   Remove The /x extension used by xceptor
		 	$id =~ s/\/[0-9]$//;
		 	if ($replace_slash == 1) {
			 	# convert / to _
		 		$id =~ s/[\/]/_/g;
		 	}
		 	else {
		 		# remove /
		 		$id =~ s/[\/]//g;
		 	}
		 	#   Remove leftover invalid filename characters
		 	$id =~ s/[:]//g;
		 	
		 	my $filename =  $id;
		 	if ($include_mtype == 1) {
		 		$filename = "${type}_${filename}";
		 	}
		 	my $outputPath = "$output_dir/$filename.${output_suffix}";
		 	if (-e $outputPath) {
		 		print "Duplicate detected: $outputPath\n";
	 			# remember this dup (filename without suffix used in hash)
	 			$dupHash{$filename} = $filename;
	 			$dupcount+=1;
		 		if ($strip_dups == 0) {
		 			# add the dup extension in main folder
		 			$outputPath = "$output_dir/${filename}-DUP${dupcount}.$output_suffix";
		 		}
		 		else {
		 			if ($strip_dups == 1) {
			 			# get the sequence number from the 1: header
		 				my $seq = GetSeq($fields[2]);
			 			# write to dup folder instead with sequence number
		 				$outputPath = "$output_dir/dups/${filename}+${seq}.${output_suffix}";
		 			}
		 			else {
			 			# add the dup extension in dup folder
			 			$outputPath = "$output_dir/dups/${filename}-DUP${dupcount}.$output_suffix";
		 			}
		 		}
		 	}
		 	print "Creating file: $outputPath\n";
		 	open ( $output_file, '>', $outputPath) or croak ("Unable to open output file: $!");
		 	print $output_file "$fields[2]\n";
	}
	else {
		# get rid of the trailing quote on last line
		$line =~ s/"$//; 
		print $output_file "$line\n";
	}
}

close $fh;
close $output_file if defined $output_file;

# move original dups
if ($strip_dups != 0) {
	foreach my $key (keys %dupHash) {
		my $origDupFile = "$output_dir/$key.$output_suffix";
		print "Moving original dup '$origDupFile'\n";
		if ($strip_dups == 1) {
			# Move to dup folder with sequence number
			my $seq = GetSeqFromFile($origDupFile);
			move ($origDupFile, "$output_dir/dups/${key}+${seq}.$output_suffix") || croak "Failed to move dup file '$origDupFile'. $!";
		}
		else {
			# just move to dup folder as is
			move ($origDupFile, "$output_dir/dups/${key}.$output_suffix") || croak "Failed to move dup file '$origDupFile'. $!";
		}
	}
}

sub GetSeq {
	my $line = $_[0];
	my $headerStart = index ($line, "{1:");
	return substr($line,$headerStart + 18, 10);
}

sub GetSeqFromFile {
	my $filePath = $_[0];
	open (my $fh, '<', $filePath ) || croak("Failed to open file to get seq: $filePath. $!");
	my $line = <$fh>;
	close $fh;
	return GetSeq ($line);
}
