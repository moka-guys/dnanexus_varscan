#!/bin/bash

# The following line causes bash to exit at any point if there is any error
# and to output each line as it is executed -- useful for debugging
set -e -x -o pipefail

#Grab inputs
dx-download-all-inputs --except ref_genome --parallel

# Move inputs to home
# mv ~/in/bam_file/* ~/*

echo $min_coverage
echo $min_reads2
echo $min_avg_qual
echo $min_var_freq
echo $min_freq_for_hom
echo $p_value
echo $strand_filter
echo $output_vcf
echo $variants

opts=" --min-coverage $min_coverage --min-reads2 $min_reads2"

if [ "$min_avg_qual" != "" ]; then
  opts="$opts --min_avg_qual $min_avg_qual"
fi

if [ "$min_var_freq" != "" ]; then
	opts="$opts --min-var-freq $min_var_freq" 
fi

if [ "$min_freq_for_hom" != "" ]; then
	opts="$opts --min-freq-for-hom $min_freq_for_hom" 
fi

if [ "$p_value" != "" ]; then
	opts="$opts --p-value $p_value" 
fi 

if [ "$strand_filter" == "true" ]; then
	opts="$opts --strand-filter 1"
else
	opts="$opts --strand-filter 0"
fi

if [ "$output_vcf" == "true" ]; then
	opts="$opts --output-vcf 1"
else
	opts="$opts --output-vcf 0"
fi

if [ "$variants" == "true" ]; then
	opts="$opts --variants"
fi


mkdir genome
dx cat "$ref_genome" | tar zxvf - -C genome  
# => genome/<ref>, genome/<ref>.ann, genome/<ref>.bwt, etc.


# rename genome files to grch37 so that the VCF header states the reference to be grch37.fa, which then allows Ingenuity to accept the VCFs (otherwise VCF header would have reference as genome.fa which Ingenuity won't accept)
mv  genome/*.fa  genome/grch37.fa
mv  genome/*.fa.fai  genome/grch37.fa.fai
# mv genome.dict grch37.dict
genome_file=`ls genome/*.fa`

# Show the java version the worker is using
# Note: Have only specified java8 in json 
echo $(java -version)


# Calculate 80% of memory size, for java
head -n1 /proc/meminfo | awk '{print int($2*0.8/1024)}' >.mem_in_mb.txt
java="java -Xmx$(<.mem_in_mb.txt)m"

# Run variant annotator
mark-section "Run Varscan VariantAnnotator"
for (( i=0; i<${#bam_file_path[@]}; i++ )); 
do echo ${bam_file_prefix[i]}
samtools mpileup -f $genome_file -B -d 500000 -q 1 ${bam_file_path[i]}| \
$java -jar /usr/bin/VarScan.v2.4.3.jar mpileup2cns $opts > ${bam_file_prefix[i]}.varscan.vcf
sed -i 's/Sample1/'"${bam_file_prefix}"'/' ${bam_file_prefix[i]}.varscan.vcf

#filter vcf based on bed file input.
if [ "$bed_file" != "" ]; then
	 sed 's/chr//' ${bam_file_prefix[i]}.varscan.vcf > ${bam_file_prefix[i]}.temp.vcf
	 /usr/bin/bedtools2/bin/bedtools intersect -header -a ${bam_file_prefix[i]}.temp.vcf -b ${bed_file_path} > ${bam_file_prefix[i]}.varscan.bedfiltered.vcf
fi
done 

# Send output back to DNAnexus project
mark-section "Upload output"
mkdir -p ~/out/varscan_vcf/
mkdir -p ~/out/varscan_vcf_bed/
mv ./*.varscan.vcf ~/out/varscan_vcf/
mv ./*.varscan.bedfiltered.vcf ~/out/varscan_vcf_bed/

dx-upload-all-outputs --parallel

mark-success