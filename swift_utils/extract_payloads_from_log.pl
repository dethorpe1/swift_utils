#! /usr/bin/perl -w 

use warnings;
use strict;
use Carp;
use Getopt::Std;
use File::Copy qw(move);
use Pod::Usage;


=head1 NAME    

extract_payloads_from_log.pl

=head1 SYNOPSIS

extract_payloads_from_log.pl [options]
                  
=head1 OPTIONS

=over

=item B<-f>

Payload log file to extract from

=item B<-t>

Type of message to extract. Default is 'r'.
       r = Recieved
       t = Translated

=item B<-i>

Restrict extract to the specified interface. This is indicated in the logs like this [ jmsInputSwift2Cam-1 ], set the 
parameter to the required interface e.g: jmsInputSwift2Cam. 

=item B<-p>

Restrict extract to logs entries matching the provided regex pattern in the first line.

e.g: 
   To specify a particuler month: ^\[ 2017-08
   To specify a particuler ID: \[ID:170824C525966/01

=item B<-d>

The output directory for extracted files. Default is current dir.

=item B<-s>

Suffix to use on files. Default is xml.

=item B<-x>

Don't include mtype in file name. Default is to include.

=item B<-u>

Remove invalid characters in id for filename. Default is to replace with _ character. 

=item B<-m>

Move duplicates to a seperate folder with -DUPx extension added to difference them.
If not set duplicates remain in the main folder with -DUPx extension added to difference them.

=item B<-h>

Display usage and help.

=back

=head1 DESCRIPTION

Program to extract payloads from payload file wrriten from spring integration adaptor. 
Writes files as <messagetype>_<id>.<suffix>

=cut


my %extract_types = ( 'r' => '\[ Received Message',
					  't' => '\[ Translated Message' );

my (%opts,$line,$output_file,%dupHash,$source_file);
my $extract_type = 'r';
my $output_dir =".";
my $output_suffix ="xml";
my $include_mtype = 1;
my $invalid_char_replacement = "_";
my $dupcount=1;
my $strip_dups = 0;
my $state = "SCANNING";
my $extract_interface;
my $extract_pattern;

getopts('hf:d:s:xut:mi:p:', \%opts);
pod2usage( -verbose => 2, -exitval => 0  ) if defined ($opts{'h'});

$extract_type = $opts{'t'} if defined $opts{'t'};
$extract_interface = $opts{'i'} if defined $opts{'i'};
$extract_pattern = $opts{'p'} if defined $opts{'p'};
$source_file = $opts{'f'} if defined $opts{'f'};
$output_dir = $opts{'d'} if defined $opts{'d'};
$output_suffix = $opts{'s'} if defined $opts{'s'};
$include_mtype = 0 if defined $opts{'x'};
$invalid_char_replacement = "" if defined $opts{'u'};
if (defined $opts{'m'}) {
	$strip_dups = 1; 
	if (! -e "$output_dir/dups" ) {
		mkdir("$output_dir/dups") || croak "failed to make dup dir: $!";
	}
}
pod2usage( -message => "ERROR: No Source file specified ", -verbose => 1, -exitval => 2 ) if (!defined $source_file );

open (my $fh, '<', $source_file) || croak "Failed to open file: $!";
while ($line = <$fh>) {
	chomp $line;
	if ($state eq "SCANNING") {
		if ($line =~ /$extract_types{$extract_type}/) {
			# Ignore payment image messages
			next if $line =~ /MessageType="MeridianPaymentImage"/;
			# Ignore if not the required interface 
			next if defined $extract_interface && $line !~ /\[ ${extract_interface}-/;
			# Ignore if dosn't match the provided extract pattern 
			next if defined $extract_pattern && $line !~ /${extract_pattern}/;
			# 1st line of a message to extract
			$line =~ /ID:(.*?),/;
			my $id = $1;
			$line =~ /Type:(.*?),/; 
			my $type = $1; 
			my $payload;
			if ($line =~ /\[Payload=(.*)$/) {
				# this is payload format in received messages 
				$payload = $1;
			}
			else {
				# this is payload format in translated messages
				$line =~ /, Payload:(.*)$/;
				$payload = $1;
			} 
			print "Extracting: $type, $id\n";
		 	# convert invalid filename chars and spaces
			$id =~ s/[\/: ]/${invalid_char_replacement}/g;
			 	
		 	my $filename = $id;
	 		$filename = "${type}_${filename}" if ($include_mtype == 1);

			my $output_path = "$output_dir/$filename.${output_suffix}";
		 	if (-e $output_path) {
		 		print " - Duplicate detected: $output_path\n";
	 			# remember this dup (filename without suffix used in hash)
	 			$dupHash{$filename} = $filename;
	 			$dupcount+=1;
		 		if ($strip_dups == 1) {
		 			# write to dup folder instead with dup extension
		 			$output_path = "$output_dir/dups/${filename}-DUP${dupcount}.$output_suffix";
		 		}
		 		else {
		 			# just add the dup extension
		 			$output_path = "$output_dir/${filename}-DUP${dupcount}.$output_suffix";
		 		}
		 	}
			
			print " - Creating file: $output_path\n";
			open ( $output_file, '>', $output_path) or croak ("Unable to open output file: $!");
			 
			# Check if message is all on one line
			if ($payload =~ /\] \] $/) {
				# get rid of the trailing delimiters on line
				$payload =~ s/\] \] $//; 
				# get rid of headers on line (received msgs)
				$payload =~ s/\]\[Headers=.*$//;
				print $output_file "$payload\n";
				close $output_file;
			}
			else {
				 print $output_file "$payload\n";
				 # Message is over multiple lines so go to extracting state to read them.
				 $state = "EXTRACTING";
			} 
		}
	} elsif ($state eq "EXTRACTING" ) {
		croak ("ERROR: Found new message start line before finding end of previous message, This is fatal. Line = \n$line")
			if ($line =~ /$extract_types{$extract_type}/);
		# look for last line
		if ($line =~ /\] \] $/) {
			# last line found
			# get rid of the trailing delimiters on last line
			$line =~ s/\] \] $//; 
			# get rid of headers on last line (received msgs)
			$line =~ s/\]\[Headers=.*$//; 
			print $output_file "$line\n";
			close $output_file;
			$state = "SCANNING";
		}
		else {
			print $output_file "$line\n";			
		}
	}
}

close $fh;

# move original dups
if ($strip_dups == 1) {
	foreach my $key (keys %dupHash) {
		my $origDupFile = "$output_dir/$key.$output_suffix";
		print "Moving original dup '$origDupFile'\n";
		move ($origDupFile, "$output_dir/dups/${key}.$output_suffix") || croak "Failed to move dup file '$origDupFile'. $!";
	}
}
