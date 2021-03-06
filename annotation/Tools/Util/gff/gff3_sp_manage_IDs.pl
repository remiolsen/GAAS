#!/usr/bin/env perl


use strict;
use Getopt::Long;
use Pod::Usage;
use Data::Dumper;
use Bio::Tools::GFF;
use BILS::Handler::GFF3handler qw(:Ok);
use BILS::Handler::GXFhandler qw(:Ok);

my $header = qq{
########################################################
# BILS 2016 - Sweden                                   #  
# jacques.dainat\@bils.se                               #
# Please cite BILS (www.bils.se) when using this tool. #
########################################################
};

my $gff = undef;
my $help= 0;
my @opt_tag=();
my $outfile=undef;
my $prefix=undef;

if ( !GetOptions(
    "help|h" => \$help,
    "gff|f=s" => \$gff,
    "prefix=s" => \$prefix,
    "p|t|l=s" => \@opt_tag,
    "output|outfile|out|o=s" => \$outfile))

{
    pod2usage( { -message => 'Failed to parse command line',
                 -verbose => 1,
                 -exitval => 1 } );
}

# Print Help and exit
if ($help) {
    pod2usage( { -verbose => 2,
                 -exitval => 2,
                 -message => "$header\n" } );
}
 
if ( ! (defined($gff)) ){
    pod2usage( {
           -message => "$header\nAt least 1 parameter is mandatory:\nInput reference gff file (--gff) \n\n",
           -verbose => 0,
           -exitval => 2 } );
}

my $gffout;
if ($outfile) {
  $outfile=~ s/.gff//g;
  open(my $fh, '>', $outfile.".gff") or die "Could not open file '$outfile' $!";
  $gffout= Bio::Tools::GFF->new(-fh => $fh, -gff_version => 3 );
}
else{
  $gffout = Bio::Tools::GFF->new(-fh => \*STDOUT, -gff_version => 3);
}

# Manage $primaryTag
my %ptagList;
if(! @opt_tag){
  print "We will work on attributes from all features\n";
  $ptagList{'level1'}++;
  $ptagList{'level2'}++;
  $ptagList{'level3'}++;
}
else{
  foreach my $tag (@opt_tag){
    if($tag eq ""){next;}
    if($tag eq "all"){
      print "We will work on attributes from all features\n";
      $ptagList{'level1'}++;
      $ptagList{'level2'}++;
      $ptagList{'level3'}++;
    }
    else{
      print "We will work on attributes from all the $tag features\n";
      $ptagList{lc($tag)}++;
    }
  }
}




                #####################
                #     MAIN          #
                #####################

my %keepTrack;
my %dynamicTrackExonToE;
my %dynamicTrackEtoExon;

######################
### Parse GFF input #
my ($hash_omniscient, $hash_mRNAGeneLink) = BILS::Handler::GXFhandler->slurp_gff3_file_JD($gff);
print ("GFF3 file parsed\n");

# sort by seq id
my %hash_sortBySeq;
foreach my $tag_level1 ( keys %{$hash_omniscient->{'level1'}}){
  foreach my $level1_id ( keys %{$hash_omniscient->{'level1'}{$tag_level1}}){
    my $position=$hash_omniscient->{'level1'}{$tag_level1}{$level1_id}->seq_id;
    push (@{$hash_sortBySeq{$position}{$tag_level1}}, $hash_omniscient->{'level1'}{$tag_level1}{$level1_id});
  }
}

#Read by seqId to sort properly for ID naming
foreach my $seqid (sort alphaNum keys %hash_sortBySeq){ # loop over all the feature level1

  foreach my $tag_l1 (sort {$a cmp $b} keys %{$hash_sortBySeq{$seqid}}){

    foreach my $feature_l1 ( sort {$a->start <=> $b->start} @{$hash_sortBySeq{$seqid}{$tag_l1}}){
      my $id_l1 = lc($feature_l1->_tag_value('ID'));
      my $l1_ID_modified=undef;

      $keepTrack{$tag_l1}++;
      if(exists ($ptagList{$tag_l1}) or  exists ($ptagList{'level1'}) ){ 
        manage_attributes($feature_l1,\%keepTrack, $prefix);

        $l1_ID_modified=$feature_l1->_tag_value('ID');
        $hash_omniscient->{'level1'}{$tag_l1}{lc($l1_ID_modified)} = delete $hash_omniscient->{'level1'}{$tag_l1}{$id_l1};    
      }

      #################
      # == LEVEL 2 == #
      #################
      foreach my $tag_l2 (sort {$a cmp $b}  keys %{$hash_omniscient->{'level2'}}){ # primary_tag_key_level2 = mrna or mirna or ncrna or trna etc...
        
        if ( exists ($hash_omniscient->{'level2'}{$tag_l2}{$id_l1} ) ){
          foreach my $feature_l2 ( sort {$a->start <=> $b->start} @{$hash_omniscient->{'level2'}{$tag_l2}{$id_l1}}) {
            
            my $l2_ID_modified=undef;
            my $level2_ID = lc($feature_l2->_tag_value('ID'));

            $keepTrack{$tag_l2}++;
            if(exists ($ptagList{$tag_l2}) or  exists ($ptagList{'level2'}) ){
              manage_attributes($feature_l2,\%keepTrack, $prefix);
              $l2_ID_modified=$feature_l2->_tag_value('ID');
            }

            #Modify parent if necessary
            if($l1_ID_modified){
               create_or_replace_tag($feature_l2,'Parent', $l1_ID_modified);
            }

            #################
            # == LEVEL 3 == #
            #################
            foreach my $tag_l3 (sort {$a cmp $b} keys %{$hash_omniscient->{'level3'}}){ # primary_tag_key_level3 = cds or exon or start_codon or utr etc...
              
              if ( exists_keys($hash_omniscient, ('level3', $tag_l3 , $level2_ID) ) ){

                foreach my $feature_l3 ( sort {$a->start <=> $b->start} @{$hash_omniscient->{'level3'}{$tag_l3}{$level2_ID}}) {
                  
                  $keepTrack{$tag_l3}++;
                  if(exists ($ptagList{$tag_l3}) or  exists ($ptagList{'level3'}) ){
                    manage_attributes($feature_l3,\%keepTrack, $prefix);
                  }

                  #Modify parent if necessary
                  if($l2_ID_modified){
                     create_or_replace_tag($feature_l3,'Parent', $l2_ID_modified);
                  }

                }

                if($l2_ID_modified){
                  $hash_omniscient->{'level3'}{$tag_l3}{lc($l2_ID_modified)} = delete $hash_omniscient->{'level3'}{$tag_l3}{$level2_ID};
                }
              }
            }
          }
          if($l1_ID_modified){
            $hash_omniscient->{'level2'}{$tag_l2}{lc($l1_ID_modified)} = delete $hash_omniscient->{'level2'}{$tag_l2}{$id_l1};
          }
        }
      }
    }
  }
}

# Print results
print_omniscient($hash_omniscient, $gffout); #print gene modified


#######################################################################################################################
        ####################
         #     methods    #
          ################
           ##############
            ############
             ##########
              ########
               ######
                ####
                 ##

sub  manage_attributes{
  my  ($feature, $keepTrack, $prefix)=@_;
  
  my $primary_tag = lc($feature->primary_tag);

  if ($prefix){

    my $nbName = $keepTrack->{$primary_tag};

    my $numberNum=11;
    my $GoodNum="";
    for (my $i=0; $i<$numberNum-length($nbName); $i++){
      $GoodNum.="0";
    }
    $GoodNum.=$nbName;

    my $abb = uc(select_abb($feature));
    
    my $result="$prefix$abb$GoodNum";
    create_or_replace_tag($feature,'ID', $result);
  }
  else{  
    create_or_replace_tag($feature,'ID', $primary_tag."-".$keepTrack->{$primary_tag});
  }
}

sub  select_abb{
  my  ($feature)=@_;

  
  my $primary_tag = lc($feature->primary_tag);

  if(exists_keys(\%dynamicTrackExonToE, ($primary_tag) ) ){
    return $dynamicTrackExonToE{$primary_tag};
  }
 else{
    my $cpt=1;
    my $letter = uc(substr($primary_tag, 0, $cpt));

    if(exists_keys(\%dynamicTrackEtoExon, ($letter) ) ){

      while (exists_keys (\%dynamicTrackEtoExon, ($letter) ) ){
          $cpt++;
          $letter = uc(substr($primary_tag, 0, $cpt));
      }
      $dynamicTrackExonToE{$primary_tag}=$letter;
      $dynamicTrackEtoExon{$letter}=$primary_tag;
    }
    else{
      $dynamicTrackExonToE{$primary_tag}=$letter;
      $dynamicTrackEtoExon{$letter}=$primary_tag;
    }
  return $letter;
  }
}

#Sorting mixed strings => Sorting alphabetically first, then numerically
# how to use: my @y = sort by_number @x;
sub alphaNum {
    my ( $alet , $anum ) = $a =~ /([^\d]+)(\d+)/;
    my ( $blet , $bnum ) = $b =~ /([^\d]+)(\d+)/;
    ( $alet || "a" ) cmp ( $blet || "a" ) or ( $anum || 0 ) <=> ( $bnum || 0 )
}

__END__

=head1 NAME

gff3_manageIDs.pl -
The script take a gff3 file as input. -
The script allows to give uniq ID. 

=head1 SYNOPSIS

    ./gff3_manageIDs.pl -gff file.gff -p level2 -p cds -p exon [ -o outfile ]
    ./gff3_manageIDs.pl --help

=head1 OPTIONS

=over 8

=item B<--gff> or B<-f>

Input GFF3 file that will be read (and sorted)

=item B<--prefix>

To add a specific prefix to the ID

=item B<-p>,  B<-t> or  B<-l>

primary tag option, case insensitive, list. Allow to specied the feature types that will be handled. 
You can specified a specific feature by given its primary tag name (column 3) as: cds, Gene, MrNa
You can specify directly all the feature of a particular level: 
      level2=mRNA,ncRNA,tRNA,etc
      level3=CDS,exon,UTR,etc
By default all feature are taking in account. fill the option by the value "all" will have the same behaviour.

=item B<-o> , B<--output> , B<--out> or B<--outfile>

Output GFF file.  If no output file is specified, the output will be
written to STDOUT.

=item B<-h> or B<--help>

Display this helpful text.

=back

=cut
