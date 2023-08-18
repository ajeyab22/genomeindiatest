import pysam
import sys

input_file=sys.argv[1]
genome_id=input_file.split("/")[-1].split("_")[0]
output_file="compression_outputs/"+genome_id+"/"+genome_id+"_tags.bam"
line_file="compression_outputs/"+genome_id+"/"+genome_id+"_map.txt"
line_list=[]
with pysam.AlignmentFile(input_file, "rb",check_sq=False) as input_bam:
    with pysam.AlignmentFile(output_file, "wb", header=input_bam.header) as output_bam:
        current_line=0
        for alignment in input_bam.fetch(until_eof=True):
            al_str=str(alignment)
            if "XT" in al_str or "XN" in al_str:
                output_bam.write(alignment)
                line_list.append(current_line)
            current_line+=1

with open(line_file, 'w') as file:
    for item in line_list:
        file.write(str(item) + '\n')
