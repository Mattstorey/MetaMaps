use strict;
use warnings;
use Data::Dumper;
use FindBin;
use lib "$FindBin::Bin/../perlLib";
$| = 1;

use taxTree;
use simulation;

my $prefix_out = '../tmp/truthHMP7';

my $fn_out_reads = $prefix_out . '.perRead';
my $fn_out_distribution = $prefix_out . '.distribution';


my $targetDB = '../databases/miniSeq';

my $HMP_fastQ = '/scratch/tmp/hmp_set7_combined.fastq';
my $HMP_readIDs_href = getReadIDs($HMP_fastQ);

my $masterTaxonomy_dir = '/data/projects/phillippy/projects/MetaMap/downloads/taxonomy';
my $MetaMap_taxonomy = taxTree::readTaxonomy($masterTaxonomy_dir);
my $MetaMap_taxonomy_merged = taxTree::readMerged($masterTaxonomy_dir);

	
my %alignments_per_readID;
my %read_2_gis;
my $n_read_blasr = 0;
open(BLASRTRUTH, '<', '/data/projects/phillippy/projects/mash_map/Jobs/blasr/hmp/targetAll/all.m4') or die;
my %haveReadInFastQ;
my %noReadInFastQ;

while(<BLASRTRUTH>)
{
	my $line = $_;
	chomp($line);
	my @fields = split(/\s+/, $line);
	my $longReadID = $fields[0];
	die "Can't parse read ID $longReadID" unless($longReadID =~ /(^.+)\/\d+_\d+$/);
	my $readID = $1;
	if(exists $HMP_readIDs_href->{$readID})
	{
		#next;
		#die "Read ID $readID not in HMP FASTQ $HMP_fastQ";
		$haveReadInFastQ{$readID}++;
	}
	else
	{
		$noReadInFastQ{$readID}++;
		next;
	}
	# print join("\t", $longReadID, $readID), "\n";
	my $contigID = $fields[1];
	my $identity = $fields[3];
	die unless($identity >= 2); die unless($identity <= 100);
	
	my $alignment_read_start = $fields[5];
	my $alignment_read_stop = $fields[6];
	die unless($alignment_read_start < $alignment_read_stop);
	my $alignment_read_length = $alignment_read_stop - $alignment_read_start + 1;
	
	my $read_length = $fields[7];
	die Dumper($read_length, $alignment_read_stop) unless($read_length >= $alignment_read_stop);
	
	my $alignment_cover = $alignment_read_length/$read_length;
	#next unless($alignment_cover >= 0.7);
	$alignments_per_readID{$readID}++;
	
	die "Invalid contig ID - no GI! $contigID" unless($contigID =~ /gi\|(\d+)\|/);
	my $gi = $1;
	push(@{$read_2_gis{$readID}}, [$gi, $alignment_read_length * ($identity/100)]);
	
	$n_read_blasr++;
}
close(BLASRTRUTH);

print "haveReadInFastQ:", scalar(keys %haveReadInFastQ), "\n";
print "noReadInFastQ: ", scalar(keys %noReadInFastQ), "\n";



# statistics

my %histogram_n_alignments;
foreach my $readID (keys %alignments_per_readID)
{
	my $n_alignments = $alignments_per_readID{$readID};
	$histogram_n_alignments{$n_alignments}++;
}

print "Number of reads: ", scalar(keys %alignments_per_readID), "\n";
print "Number-of-alignments histogram:\n";
foreach my $n_alignment (sort keys %histogram_n_alignments)
{
	print "\t", $n_alignment, "\t", $histogram_n_alignments{$n_alignment}, "\n";
}

my %gis_present;
foreach my $readID (keys %read_2_gis)
{
	my @alignments = @{$read_2_gis{$readID}};
	my $sortAlignments = sub {
		my $a = shift;
		my $b = shift;
		if($a->[1] == $b->[1])
		{
			return ($a->[0] cmp $b->[0]);
		}
		else
		{
			return ($a->[1] <=> $b->[1]);
		}
	};	
	if(scalar(@alignments) > 1)
	{
		@alignments = sort {$sortAlignments->($a, $b)} @alignments;
		@alignments = reverse @alignments;
		die unless($alignments[0][1] >= $alignments[1][1]);
		
	}
	$read_2_gis{$readID} = $alignments[0][0];
	$gis_present{$alignments[0][0]}++;
}

# print "\nGIs present: ", scalar(keys %gis_present), "\n";

# gi 2 taxon ID

print "Reading gi-2-taxon...\n";
unless(-e '/data/projects/phillippy/projects/mashsim/db/gi_taxid_nucl.dmp.HMP')
{
	open(GI2TAXON, '<', '/data/projects/phillippy/projects/mashsim/db/gi_taxid_nucl.dmp') or die;
	open(GI2TAXONOUT, '>', '/data/projects/phillippy/projects/mashsim/db/gi_taxid_nucl.dmp.HMP') or die;
	while(<GI2TAXON>)
	{
		my $line = $_; 
		chomp($line);
		my @f = split(/\s+/, $line);
		die unless($#f == 1);	
		if($gis_present{$f[0]})
		{
			print GI2TAXONOUT $line, "\n";
		}
		if(($. % 100000) == 0)
		{
			print "\rGI line $. ...";
		}		
	}
	close(GI2TAXON);
	print "\n";
}

my %gi_2_taxon;
open(GI2TAXON, '<', '/data/projects/phillippy/projects/mashsim/db/gi_taxid_nucl.dmp.HMP') or die;
while(<GI2TAXON>)
{
	my $line = $_; 
	chomp($line);
	my @f = split(/\s+/, $line);
	die unless($#f == 1);	
	$gi_2_taxon{$f[0]} = $f[1];
}
close(GI2TAXON);

$gi_2_taxon{126640115} = '400667';
$gi_2_taxon{126640097} = '400667';
$gi_2_taxon{126640109} = '400667';
$gi_2_taxon{161510924} = '451516';
$gi_2_taxon{32470532} = '176280';
			
open(OUT_PERREAD, '>', $fn_out_reads) or die;
my %read_2_taxonID;
my %taxonID_read_counts;
foreach my $readID (keys %read_2_gis)
{
	my $gi = $read_2_gis{$readID};
	my $taxonID_original = $gi_2_taxon{$gi};
	die "No translation for GI number $gi" unless(defined $taxonID_original);
	my $taxonID_current = taxTree::findCurrentNodeID($MetaMap_taxonomy, $MetaMap_taxonomy_merged, $taxonID_original);
	print OUT_PERREAD join("\t", $readID, $taxonID_current), "\n";
	$read_2_taxonID{$readID} = $taxonID_current;
	$taxonID_read_counts{$taxonID_current}++;
}	

foreach my $readID (keys %$HMP_readIDs_href)
{
	next if(defined $read_2_taxonID{$readID});
	print OUT_PERREAD join("\t", $readID, 0), "\n";
	$taxonID_read_counts{0}++;
}

simulation::truthFileFromReadCounts($fn_out_distribution, \%taxonID_read_counts, $MetaMap_taxonomy);
close(OUT_PERREAD);

print "\n\nDone. Produced files:\n";
print "\t - $fn_out_reads \n";
print "\t - $fn_out_distribution \n";

sub getReadIDs
{
	my $fn = shift;
	
	my %forReturn;
	open(F, '<', $fn) or die;
	while(<F>)
	{
		chomp;
		next unless($_);
		my $readID = $_;
		die unless(substr($readID, 0, 1) eq '@');
		substr($readID, 0, 1) = '';
		<F>;
		my $plus = <F>;
		die unless(substr($plus, 0, 1) eq '+');
		<F>;
		$forReturn{$readID}++;
	}
	close(F);
	return \%forReturn;
}