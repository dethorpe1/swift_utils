#! /usr/bin/perl -w

use warnings;
use strict;
use Carp;
use Getopt::Std;
use File::Find;
use Pod::Usage;

=head1 NAME    

extract_swift_headers.pl

=head1 SYNOPSIS

extract_swift_headers.pl [options]
                  
=head1 DESCRIPTION

Extract the main header fields from all swift files in a directory tree and write to a CSV file

=head1 OPTIONS

=over

=item B<-s>

Directory to start file scan from

=item B<-t>

File to write results to

=item B<-p>

Filename pattern to match. Reguler expression NOT file glob pattern. Optional, default is all files 

=item B<-u>

Only output unique combinations of header fields. Optional, default is to output all headers

=item B<-a>

Include acks in extract, the fields extracted are for the message being acked, as long as it is present in the ack body.
Will prefix mode with 'A' in output to indicate it is an ack. Optional, default is to not include

=item B<-h>

Display usage and help.

=back

=cut

###############
### GLOBALS ###
###############
our %headers;
our $opt_include_acks = 0;
our $opt_only_unique  = 0;
our $output_fh;

=head1 FUNCTIONS

=head2 extract_headers($file)

Extract the headers for a given file and write to the CSV file.

=begin text

      $file: Name of file to extract headers from

=end text

=cut

sub extract_headers {
	my $file = $_[0];
	open( my $fh, '<', $file ) || croak "Unable to open source file $file: $!";
	while ( my $line = <$fh> ) {
		if ( $line =~ /{1:/ ) {
			my $is_ack = extract_field( "{1:", 4, 2, $line ) eq "21";
			if ( !$opt_include_acks && $is_ack ) {
				print " --> Skipping ACK $file\n";
				last;
			}
			print " --> Extracting file: $file\n";

			my $type = extract_field( '{2:', 4, 3, $line );
			my $mode = extract_field( '{2:', 3, 1, $line );
			$mode = 'A' . $mode if $is_ack;
			my $block1_bic = extract_field( '{1:F01', 6, 9, $line );
			my $block2_bic = extract_field( '{2:', ( $mode eq 'I' ) ? 7 : 17, 9, $line );
			my $values = join( ',', $type, $mode, $block1_bic, $block2_bic );

			print $output_fh $values . "\n" if ( !$opt_only_unique || !exists $headers{$values} );
			$headers{$values} = 1;
			last;
		}
	}
	close $fh;
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
getopts( 'auhs:t:p:', \%opts );
pod2usage( -verbose => 2, -exitval => 0 ) if defined( $opts{'h'} );
pod2usage( -verbose => 1, -exitval => 1, -message => "\nERROR: mandatory parameter missing.\n" ) if !defined $opts{'s'} || !defined $opts{'t'};

my $source_dir  = $opts{'s'} if defined $opts{'s'};
my $target_file = $opts{'t'} if defined $opts{'t'};
$opt_only_unique  = 1 if defined $opts{'u'};
$opt_include_acks = 1 if defined $opts{'a'};
my $opt_file_pattern = '.*';
$opt_file_pattern = $opts{'p'} if defined $opts{'p'};

open( $output_fh, '>', $target_file ) || croak "Unable to open output file $target_file: $!";
print $output_fh "TYPE,MODE,BLOCK1_BIC,BLOCK2_BIC\n";

find(
	sub {
		extract_headers($_) if ( -f and /$opt_file_pattern/ );
	},
	$source_dir
);

close $output_fh;

