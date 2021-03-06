#! /usr/bin/perl -w 

use warnings;
use strict;
use Carp;
use Getopt::Std;
use File::Copy qw(move copy);

# rename a set of files by removeing the sequence number and move to a target dir
# any duplicates created moved to seperate dups dir with original names 

my %opts;
getopts('t:s:m', \%opts);
my $sourcedir = $opts{'s'} if defined $opts{'s'};
my $targetdir =".";
$targetdir = $opts{'t'} if defined $opts{'t'};
# move duplicates to a seperate folder
my $strip_dups = 0;
$strip_dups = 1 if defined $opts{'m'};

opendir (my $dir, $sourcedir) || croak "Failed top open dir $sourcedir. $!";
 
my $dupcount=1;
my %dupHash;
if ($strip_dups == 1) {
	mkdir("$targetdir/dups") || croak "failed to make dup dir: $!";
}  

while (my $file = readdir ($dir)) {
	next if $file =~ m/\.$|\.\.$/;
	my $newfile;
	($newfile = $file) =~ s/_[0-9]+\.xml/.xml/;
 	
	my $outputPath = "$targetdir/$newfile";
	if ( -e $outputPath ) {
		print "Duplicate detected: $newfile\n";
	 	# remember this dup
	 	$dupHash{$newfile} = $newfile;
		if ($strip_dups == 1) {
			# write to dup folder instead with the original name
			$outputPath = "$targetdir/dups/$file"
			
	 	}
	}
	print "Copying file '$file' to: '$outputPath'\n";
	copy ("$sourcedir/$file", $outputPath) || croak "Failed to copy file $file to $outputPath.$!"; 

}

# move original dups
if ($strip_dups == 1) {
	foreach my $key (keys %dupHash) {
		print "Moving original dup '$key'\n";
		move ("$targetdir/$key", "$targetdir/dups/$key") || croak "Failed to move dup file '$targetdir/$key'. $!";
	}
}
