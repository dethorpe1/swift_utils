#! /usr/bin/perl -w

use warnings;
use strict;
use Carp;
use Getopt::Std;
use Pod::Usage;
use File::Basename;
use XML::Simple qw(:strict);
use Data::Dumper;
use constant {
	BLOCK1_BIC_START => 6,
	BLOCK2_OUTPUT_BIC_START => 46,
	BLOCK2_OUTPUT_BLOCK_BIC_START => 17,
	BLOCK2_INPUT_BIC_START => 36,
	BLOCK2_INPUT_BLOCK_BIC_START => 7,
	BLOCK2_MODE_START => 3,
	BLOCK2_TYPE_START => 4,
	SWIFT_EOL => "\x0D\x0A"
};

=head1 NAME    

update_swift_files.pl

=head1 SYNOPSIS

update_swift_files.pl [options]
                  
=head1 DESCRIPTION

Update swift files with various changes specified in XML file. Can be used to annonimise or otherwise bulk update 
a set of swift files

=head1 OPTIONS

=over

=item B<-c>

XML config file containing replacement rules

=item B<-s>

Source directory

=item B<-t>

Directory to write updated files to

=item B<-p>

Filename pattern to match in source dir. Optional, default is all files in curent dir

=item B<-d>

Enable debug output

=item B<-h>

Display usage and help.

=back

=cut

###############
### GLOBALS ###
###############
our $config;
our $debug = 0;

# Dispatch table of change types to subroutines
my %change_dispatch = (
   'substr' => \&change_substr,
   'nameaddress' => \&change_nameaddress,
   'nameaddress_linenumbers' => \&change_nameaddress_linenumbers,
   'replacelines' => \&change_replacelines,
   'delim' => \&change_delim
);

=head1 FUNCTIONS

=head2 update_file ($file,$out_dir)

Update a file with required changes from config.

Params:

=begin text

	$file: Name of file to update
	$out_dir: Direcotry to write updated file to
	
=end text

=cut

sub update_file {
	my ($file,$out_dir) = @_;
	open( my $fh, '<', $file ) || croak "Unable to open source file $file: $!";
	my $output_file = "${out_dir}/" . basename ($file);
	open (my $output_fh, '>', $output_file) || croak "Unable to open output file '$output_file': $!";
	# Set bin mode on in and out filehandles as need to maintain SWIFT CRLF endings
	# regardless of platform running on. If this isn't done then end of lines are converted
	# to the platforms one
	binmode ($fh);
	binmode ($output_fh);
	
	my @field = ();
	my $current_field = "UNDEF";
	my $msg_type = "";
	
	while ( my $line = <$fh> ) {
		# If header line
		if ($line =~ /\{1:/ ) {
			$msg_type = extract_field("{2:",BLOCK2_TYPE_START,3, $line );
			print " --> Processing header, message type $msg_type\n";
			print $output_fh update_header($line,$msg_type);
		}
		# If trailer line
		elsif ($line =~ /-\}/) {
			# Process the final field we have just completed capturing
			print " --> Processing final field before trailer: $current_field\n";
			print $output_fh update_field($msg_type, $current_field,\@field);
			print $output_fh $line;
			@field = ();
			last;
		}
		else {
			# body line
			# We read in whole field and update it in one as can be many changes per field
			if ($line =~ /^:([0-9]+[A-Z]*):/) {
				# Its a start field tag
				if ( @field > 0 ) {
					# Process the field we have just completed capturing, if there is one
					print " --> Processing field: $current_field\n";
					print $output_fh update_field($msg_type, $current_field,\@field);
				}
				#Start capturing the next field;
				$current_field = $1;
				@field = ($line);
			}
			else {
				# multi line field so add to current field
				push @field, $line;
			}
		}
	}
	
	if ( @field > 0 ) {
		# Process the last field capturing, if there is one
		# Should only happen if there is no trailer/block5
		print " --> Processing final field, no trailer: $current_field\n";
		print $output_fh update_field($msg_type, $current_field,\@field);
	}
	
	close $output_fh;
}

=head2 update_header ($line)

Update the header with required changes from config.

Params:

=begin text

	$line: header line to update
	return: Updated line
	
=end text

=cut

sub update_header {
	my ($line,$msg_type) = @_;
	if (exists $config->{header}) {
		if (exists $config->{header}{block1}{bic} ) {
			my $bic = extract_field("{1",BLOCK1_BIC_START,12,$line );
			# check override
			if (!exists($config->{header}{block1}{overrides}{$msg_type}{criteria}) || $bic !~ /$config->{header}{block1}{overrides}{$msg_type}{criteria}/) {
				dbg_print ("Replacing block1 bic '$bic' with " . $config->{header}{block1}{bic});
				$line = replace_substring($line,BLOCK1_BIC_START,$config->{header}{block1}{bic});
			}
			else {
				dbg_print ("NOT Replacing block1 bic '$bic' due to override: " . $config->{header}{block1}{overrides}{$msg_type}{criteria});
			}
		}
		if (exists $config->{header}{block2}{bic} ) {
			my $bic;
			my $bic_start;
			if (extract_field("{2:",BLOCK2_MODE_START,1,$line) eq "I") {
				$bic = extract_field("{2:",BLOCK2_INPUT_BLOCK_BIC_START,12,$line );
				$bic_start = BLOCK2_INPUT_BIC_START;
			}
			else {
				$bic = extract_field("{2:",BLOCK2_OUTPUT_BLOCK_BIC_START,12,$line );
				$bic_start = BLOCK2_OUTPUT_BIC_START;
			}
			# check override
			if (!exists($config->{header}{block2}{overrides}{$msg_type}{criteria}) || $bic !~ /$config->{header}{block2}{overrides}{$msg_type}{criteria}/) {
				dbg_print ("Replacing block2 bic '$bic' with " . $config->{header}{block2}{bic});
				$line = replace_substring($line,$bic_start,$config->{header}{block2}{bic});
			}
			else {
				dbg_print ("NOT Replacing block2 bic '$bic' due to override: " . $config->{header}{block2}{overrides}{$msg_type}{criteria});
			}
		}
	}
	return $line;
}


=head2 update_field ($msg_type, $field_name,$field_arrayref)

Update a field with required changes from config.

Params:

=begin text

	$msg_type: Message type being processed
	$field_name: Name of field to update
	$field_arrayref: Reference to array containing all the lines of the field
	return: String containing complete updated field
	
=end text


=cut

sub update_field {
	my ($msg_type, $field_name,$field_arrayref) = @_;
	my $updated_field = "";
	
	if (exists $config->{body}{fields}{$field_name} ) {
		dbg_print ("Updateing field $field_name ... ");
		my $changes_arrayref = $config->{body}{fields}{$field_name}{changes};
		foreach my $change_hashref (@$changes_arrayref) {
			# Set change line defaults if not set in config
			# Note: Config indexs are 1 based.			
			my $linestart = (exists $change_hashref->{linestart}) ? $change_hashref->{linestart} : 1;
			my $lineend = (exists $change_hashref->{lineend}) ? $change_hashref->{lineend} : @$field_arrayref;
			
			# Loop through all lines of field doing the change
			my $processed_lines = 1;
			for my $index (0 .. @$field_arrayref-1) {
				if ($index + 1  >= $linestart  && $index + 1 <= $lineend ) {
					# skip line if matches changes skipif pattern (excluding field tag if present)
			    	if (exists $change_hashref->{skipif}) {
			    		(my $line = $field_arrayref->[$index]) =~ s/^:[0-9]+[A-Z]*://;
			    		next if $line =~ /$change_hashref->{skipif}/;
			    	}
			    	# skip line if matching override in place for the message type
			    	next if (exists $change_hashref->{overrides}{$msg_type} &&
			    				$field_arrayref->[$index] =~ /$change_hashref->{overrides}{$msg_type}{criteria}/);
			    	dbg_print(" Doing change mode '$change_hashref->{mode}' on line '" . ($index+1) . "' Processed_line is $processed_lines");
			    	# Take of the eol before processing, then add it back
			    	(my $line = $field_arrayref->[$index]) =~ s/\x0D\x0A$//;
					$field_arrayref->[$index] = $change_dispatch{ $change_hashref->{mode} }->( $line, $field_name, $processed_lines, $change_hashref );
					$field_arrayref->[$index] .= SWIFT_EOL;
					$processed_lines++;
				}
			}			
		}
	}
	
	return join("",@$field_arrayref);
}

=head2 replace_substring ($line,$start,$replacement)

Replaces text in a lines at a particuler position with specified text
makes sure the line dosn't become any longer by tuncaating to original length if replacement 
text runs of the end

Params:

=begin text

	$line: Line to update
	$start: Start position in line to replace
	$replacement: text to replace
	return: updated line
	
=end text

=cut

sub replace_substring {
	my ($line,$start,$replacement) = @_;
	croak "Invalid substring, replacment would be past end of line. '$line',$start,$replacement" if ($start > length($line));
	my $out_line = substr ($line, 0, $start) . $replacement;
	# add back remaining line, if any left.
	$out_line .= substr ($line, $start + length($replacement)) if ($start + length($replacement) < length($line));

	# truncate to original length if its now longer and add back eol chars before returning
	return substr($out_line,0,length($line)	);
}
		
=head2 change_substr ($line, $field_name, $line_no, $change_hashref)

Handler for the 'substr' change type. Substitutes characters at specified position with replacement text.

Params:

=begin text

	$line: line toupdate
	$field_name: name of field being updated
	$line_no: line in field being updated
	$change_hashref: hash ref to change config
	return: updated line
	
=end text

=cut

sub change_substr {
	my ($line, $field_name, $line_no, $change_hashref) = @_;
	
	# Need to skip field name if line has one, so update charstart value accordingly if there is one.
	my $charstart = $change_hashref->{charstart} + length(get_fieldname_tag($line));
	$line = replace_substring($line, $charstart-1, $change_hashref->{newtext});
	return $line ;
}

=head2 change_nameaddress ($line, $field_name, $line_no, $change_hashref)

Handler for the 'nameaddress' change type. Sets name and address to default dummy values

Params:

=begin text

	$line: line toupdate
	$field_name: name of field being updated
	$line_no: Count of line being updated in field. Not the index within the whole field
	          but rather counting the lines actually being processed
	$change_hashref: hash ref to change config
	return: updated line
	
=end text

=cut

sub change_nameaddress {
	my ($line, $field_name, $line_no, $change_hashref) = @_;

	# Need to keep field name if line has one, so pull it as a prefix if there
	my $prefix = get_fieldname_tag($line);
	
	if ($line_no == 1) {
		$line = "${prefix}CUSTOMER NAME";
	}
	else {
		$line = "${prefix}ADDRESS LINE " . ($line_no - 1);
	}
	

	return $line ;
}

=head2 change_nameaddress_linenumbers ($line, $field_name, $line_no, $change_hashref)

Handler for the 'change_nameaddress_linenumbers' change type. For address fields with line numbers, 
sets name and address to default dummy values

Params:

=begin text

	$line: line to update
	$field_name: name of field being updated
	$line_no: Count of line being updated in field. Not the index within the whole field
	          but rather counting the lines actually being processed
	$change_hashref: hash ref to change config
	return: updated line
	
=end text

=cut

sub change_nameaddress_linenumbers {
	my ($line, $field_name, $line_no, $change_hashref) = @_;

	my @line_fields = split (/\//, $line);
	
	# we change the last field on the line, skip if only one field as this is the wrong type of update
	# or a sub-field within the set that dosn't have a line number so shouldn't be updated
	if (@line_fields > 1) {
		if ($line_no == 1) {
			$line_fields[-1] = "CUSTOMER NAME";
		}
		else {
			$line_fields[-1] = "ADDRESS LINE " . ($line_no - 1);
		}
	}

	return join ("/",@line_fields);
}

=head2 change_replacelines ($line, $field_name, $line_no, $change_hashref)
 
Handler for the 'replacelines' change type. Replaces the whole line with provided text

Params:

=begin text

	$line: line toupdate
	$field_name: name of field being updated
	$line_no: line in field being updated
	$change_hashref: hash ref to change config
	return: updated line
	
=end text

=cut

sub change_replacelines {
	my ($line, $field_name, $line_no, $change_hashref) = @_;
	# Need to keep field name if line has one, so pull it as a prefix if there
	my $prefix = get_fieldname_tag($line);
	$line = $prefix . $change_hashref->{text};
	$line .= " $line_no" if (exists $change_hashref->{appendcount} && $change_hashref->{appendcount} eq 'true');
	return $line;
}


=head2 change_delim ($line, $field_name, $line_no, $change_hashref)

Handler for the 'delim' change type. Changes particuler column in a delimited field to replacment text

Params:

=begin text

	$line: line toupdate
	$field_name: name of field being updated
	$line_no: line in field being updated
	$change_hashref: hash ref to change config
	return: updated line
	
=end text

=cut

sub change_delim {
	my ($line, $field_name, $line_no, $change_hashref) = @_;
	my @fields = split (/$change_hashref->{delim}/,$line);
	if ($change_hashref->{field} <= @fields ) {
		$fields[$change_hashref->{field}-1] = $change_hashref->{newtext};
		$fields[$change_hashref->{field}-1] .= " $line_no" if (exists $change_hashref->{appendcount} && $change_hashref->{appendcount} eq 'true');
	}
	else {
		dbg_print ("Line has less fields than config specifies, no change made");
	}
	return join ($change_hashref->{delim},@fields) ;
}

=head2 extract_field ($start_pattern,$start_index,$length,$text)

Extract a field from a swift message.

=begin text

	$start_pattern: pattern to start field search from
	$start_index: index from start_pattern position for field to extract
	$length: length of field to extract
	$text: text to extract from
	return: extracted text
	
=end text

=cut

sub extract_field {
	my ( $start_pattern, $start_index, $length, $text ) = @_;
	my $out = "";

	my $start_pos = index( $text, $start_pattern );
	$out = substr( $text, $start_pos + $start_index, $length ) if ( $start_pos != -1 );
	return $out;
}

=head2 get_fieldname_tag ($line)

Get the full swift field name tag from the line e.g :22A:
Returns empty string if no tag found

=begin text

	$line: line to extract from
	return: extracted tag
	
=end text

=cut

sub get_fieldname_tag {
	my $line = $_[0];
	return ($line =~ /^(:[0-9]+[A-Z]*:)/) ? $1: "";	
}

sub dbg_print {
	print " DEBUG: $_[0]\n" if $debug;
}

############
### MAIN ###
############

my %opts;
getopts( 'hs:t:p:c:d', \%opts );
pod2usage( -verbose => 2, -exitval => 0 ) if defined( $opts{'h'} );
pod2usage( -verbose => 1, -exitval => 1, -message => "\nERROR: mandatory parameter missing.\n" ) if !defined $opts{'s'} || !defined $opts{'t'} || !defined $opts{'c'};

$debug=1 if defined $opts{'d'};
my $source_dir  = $opts{'s'} if defined $opts{'s'};
my $config_file  = $opts{'c'} if defined $opts{'c'};
my $out_dir = $opts{'t'} if defined $opts{'t'};
my $opt_file_pattern = '*.*';
$opt_file_pattern = $opts{'p'} if defined $opts{'p'};

$config = XMLin($config_file, ForceArray => ['field','change','override'], KeyAttr => ['id','type'],GroupTags => { fields => 'field',changes => 'change',overrides => 'override' });
dbg_print ("Config = \n" . Dumper ($config));

for (glob ("$source_dir/$opt_file_pattern")) {
	print "## Updating file: $_\n";
	update_file($_,$out_dir);
}
