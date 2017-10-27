#! /usr/bin/perl -w

use warnings;
use strict;
use Carp;
use Getopt::Std;
use Pod::Usage;
use File::Basename;
use XML::Simple qw(:strict);

=head1 NAME    

split_swift_files.pl

=head1 SYNOPSIS

split_swift_files.pl [options]
                  
=head1 DESCRIPTION

Split file containing multiple SOH/ETX delimited swift messages into one or more files named by message type and bics
Removing the SOH/ETX chars

=head1 OPTIONS

=over

=item B<-s>

Source directory

=item B<-t>

Directory to write split files to

=item B<-p>

Filename pattern to match in source dir. Optional, default is all files in curent dir

=item B<-a>

Skip acks in extract. For acks the fields extracted are for the message being acked, as long as it is present in the ack body.
Will prefix type with with 'ACK_' in filename to indicate it is an ack (Note: option 'r' overrides this behaviour). 
Optional, default is to include acks inaxtract 

=item B<-r>

Remove the ack header in acks leaving the original message being ACKed and create as an original msg file 
without the ACK/NACK prefix. Optional, default is to not remove and create file as an ACK/NACK file.

=item B<-h>

Display usage and help.

=back

=cut

###############
### GLOBALS ###
###############
our $opt_include_acks = 1;
our $opt_remove_ack_header = 0;
our $out_dir;

=head1 FUNCTIONS

=head2 split_and_rename($file)

Extract the headers for a given file and write to the CSV file.

=begin text

      $file: Name of file to extract headers from

=end text

=cut

sub split_and_rename {
	my ($file) = @_;
	open( my $fh, '<', $file ) || croak "Unable to open source file $file: $!";
	my $output_file;
	my $output_fh;
	my $skipping_ack = 0;
	my $is_writeing = 0;
	my $count = 0;

	while ( my $orig_line = <$fh> ) {
		# Split by SOH as there can be are multiple messages on same line either as single line messages or
		# the ETX for one and SOH for the next, then process each line individually
		my @lines = split (/\x01/, $orig_line);
		foreach my $line (@lines) {
			# Skip blanks
			next if $line eq "";
			# Check for start of message
			if ( $line =~ /{1:/ ) {
				my $is_ack = extract_field( "{1:", 4, 2, $line ) eq "21";
				if ( !$opt_include_acks && $is_ack ) {
					print " --> Skipping ACK : $file\n";
					$skipping_ack = 1;
					next;
				}
				$skipping_ack = 0;
				$count++;
				print " --> START: Extracting message $count from file: $file\n";
	
				my $type = extract_field( '{2:', 4, 3, $line );
				my $mode = extract_field( '{2:', 3, 1, $line );
				if ($is_ack) {
					if ($opt_remove_ack_header) {
						$line =~ s/{1:.21.*?{1:/{1:/;
					}
					else {
						my $prefix = (extract_field('{451:', 5, 1, $line ) eq "0")?'ACK_':'NACK_';
						$type = $prefix . $type;
					}
				}
				my $block1_bic = extract_field( '{1:F01', 6, 9, $line );
				$block1_bic = extract_field( '{1:A01', 6, 9, $line ) if $block1_bic eq "";
				my $block2_bic = extract_field( '{2:', ( $mode eq 'I' ) ? 7 : 17, 9, $line );
	
				my $filename = basename ($file); 
				open ($output_fh, '>', "$out_dir/${type}${mode}_${block1_bic}_${block2_bic}_${count}_${filename}") || croak "Unable to open output file: $!";
				# Strip off everything before the message start
				$line =~ s/^.*?{1:/{1:/;
				$is_writeing = 1;
			}
			# Check for end of current message, can be same line as start.
			if (!$skipping_ack && $is_writeing && $line =~ /\x03/) {
				# Strip of everything after ETX and write it
				print " --> FINISH: Extracting message $count from file: $file\n";
				$line =~ s/\x03.*//;
				print ($output_fh $line );
				close $output_fh;
				$is_writeing = 0;
			}
			
			# print the line to the current output file if we are still writing
			print $output_fh $line if !$skipping_ack && $is_writeing;
		}
	}
	close $output_fh if $is_writeing;
}

=head2 extract_field($start_pattern,$start_index,$length,$text)

Extract a field from a swift message.

=begin text

      $start_pattern: pattern to start field search from
      $start_index: index from start_pattern position for field to extract
      $length: length of field to extract
      $text: text to extract from
  
=end text

=cut

sub extract_field {
	my ( $start_pattern, $start_index, $length, $text ) = @_;
	my $out = "";

	my $start_pos = index( $text, $start_pattern );
	$out = substr( $text, $start_pos + $start_index, $length ) if ( $start_pos != -1 );
	return $out;
}

############
### MAIN ###
############

my %opts;
getopts( 'hars:t:p:', \%opts );
pod2usage( -verbose => 2, -exitval => 0 ) if defined( $opts{'h'} );
pod2usage( -verbose => 1, -exitval => 1, -message => "\nERROR: mandatory parameter missing.\n" ) if !defined $opts{'s'} || !defined $opts{'t'};

my $source_dir  = $opts{'s'} if defined $opts{'s'};
$out_dir = $opts{'t'} if defined $opts{'t'};
$opt_include_acks = 0 if defined $opts{'a'};
$opt_remove_ack_header = 1 if defined $opts{'r'};
my $opt_file_pattern = '*.*';
$opt_file_pattern = $opts{'p'} if defined $opts{'p'};

chdir $source_dir || die "Can't change to $source_dir: $!";
for (glob ($opt_file_pattern)) {
	split_and_rename($_);

}
