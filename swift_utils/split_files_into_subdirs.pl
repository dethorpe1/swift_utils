#! /usr/bin/perl -w 

use warnings;
use strict;
use Carp;
use Getopt::Std;
use File::Copy qw(move copy);

# split a set of files into seperate sub-dirs containing configured 
# amount of files in each dir
 
my %opts;
getopts('s:', \%opts);
my $sourcedir = $opts{'s'} if defined $opts{'s'};
my $set_size = 10000;

opendir (my $dir, $sourcedir) || croak "Failed to open dir $sourcedir. $!";
 
my $setcount=1;
mkdir("$sourcedir/set${setcount}") || croak "failed to make dir: $!";

my $filecount=0;
while (my $file = readdir ($dir)) {
	next if $file =~ m/\.$|\.\.$/ || -d "$sourcedir/$file";
	print "Copying file '$file' to: 'set${setcount}'\n";
	copy ("$sourcedir/$file", "$sourcedir/set${setcount}/$file") || croak "Failed to copy file $file. $!"; 
 	$filecount +=1;
 	if ($filecount % $set_size == 0 ) {
 		$setcount++;
		mkdir("$sourcedir/set${setcount}") || croak "failed to make dir: $!";
 	}
}

