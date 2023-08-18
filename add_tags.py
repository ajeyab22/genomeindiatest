import pysam
import sys

input_file = "decompression_outputs/"+sys.argv[1]+"/"+ sys.argv[1] + "_merged.bam"
temp_file = "decompression_outputs/" + sys.argv[1]+"_compressed/"+sys.argv[1] + "_tags.bam"
line_file = "decompression_outputs/" + sys.argv[1]+"_compressed/"+sys.argv[1] + "_map.txt"
output_file = "decompression_outputs/"+sys.argv[1]+"/" + sys.argv[1] + ".bam"

numbers_list = []

with open(line_file, 'r') as file:
    for line in file:
        numbers_list.append(int(line))

replacement_reads = []
with pysam.AlignmentFile(temp_file, "rb", check_sq=False) as replacement_bam:
    for read in replacement_bam.fetch(until_eof=True):
        replacement_reads.append(read)

count=0
replacement_len=len(replacement_reads)
with pysam.AlignmentFile(input_file, "rb", check_sq=False) as input_bam, pysam.AlignmentFile(temp_file, "rb", check_sq=False) as replacement_bam,\
        pysam.AlignmentFile(output_file, "wb", header=replacement_bam.header) as output_bam:
    for i, read in enumerate(input_bam):
        if count<replacement_len and i==numbers_list[count]:
            output_bam.write(replacement_reads[count])
            count+=1
        else:
            output_bam.write(read)

