#!/bin/bash

input_bam="$1"
if [ ! -f "${input_bam}" ]; then
    echo "Error: The file ${input_bam} does not exist."
    exit 1
fi
metadata_flag=0
retain_flag=0
restart_flag=0
for arg in "$@"; do
    if [ "$arg" = "--retain" ]; then
        retain_flag=1
    fi
    if [ "$arg" = "--restart" ]; then
        restart_flag=1
    fi

#    if [ "$arg" = "--nometadata" ]; then
#        metadata_flag=1
#    fi

done
thread_num=32
while [[ $# -gt 0 ]]; do
    case "$1" in
        --threads)
            shift
            if [[ $# -gt 0 ]]; then
                if [[ $1 =~ ^[0-9]+$ ]]; then
                    thread_num=$1
                else
                    echo "Threads arg is not an integer. Trying with the default count of 32 threads..."
                fi
            else
                echo "No argument found after --threads. Trying with the default count of 32 threads..."
            fi
            ;;
        *)
            shift
            ;;
    esac
done

filename=$(basename "$input_bam")
filename_without_extension="${filename%.*}"
input_arg="${filename_without_extension%%_*}"

if [ ! -d "compression_outputs" ]; then
    mkdir "compression_outputs"
fi

if [ ! -d "compression_outputs/${input_arg}" ]; then
    mkdir "compression_outputs/${input_arg}"
fi

checkpoint_file="compression_outputs/${input_arg}/${input_arg}_compress.checkpoint"
log_file="compression_outputs/${input_arg}/${input_arg}_compress.log"
spring_op="compression_outputs/${input_arg}/${input_arg}_SPRING.spring"
fastq1="compression_outputs/${input_arg}/${input_arg}_1.fastq"
fastq2="compression_outputs/${input_arg}/${input_arg}_2.fastq"
tag_file="compression_outputs/${input_arg}/${input_arg}_tags.bam"
map_file="compression_outputs/${input_arg}/${input_arg}_map.txt"

compress_cmd="tools/spring -c -i ${fastq1} ${fastq2} -o ${spring_op} -t ${thread_num} > std.out 2>&1"
if [ "$restart_flag" -eq 1 ] && [ -f "$checkpoint_file" ]; then
    rm "$checkpoint_file"
fi
if [ ! -f "$checkpoint_file" ]; then
    touch "$checkpoint_file"
fi

if [ ! -f "$log_file" ]; then
    touch "$log_file"
fi

convert_cmd="java -jar tools/picard.jar SamToFastq --I ${input_bam} --F ${fastq1} --F2 ${fastq2} --VERBOSITY ERROR"

if ! grep -qF "Paired fastq files created" "$checkpoint_file"; then
    start=$(date +%s.%N)
    
    echo "Starting to create paired fastq files..."
    if $convert_cmd >> "$log_file" 2>&1; then
        end=$(date +%s.%N)
        runtime=$(echo "$end - $start" | bc)
        formatted_runtime=$(printf "%.2f" "$runtime")
        echo "Paired fastq files created. Time taken: $formatted_runtime seconds." >> "$checkpoint_file"
        echo "Paired fastq files created. Time taken: $formatted_runtime seconds. 15% of compression complete."
    else
	echo "Unknown error while creating fastq files. Exiting..."
        exit 1
    fi
else
    echo "Paired fastq files already created. Skipping step..."
fi

if ! grep -qF "Spring file created" "$checkpoint_file" || grep -qF "Compressed file created" "$checkpoint_file" ; then
    start=$(date +%s.%N)
    compress_cmd="tools/spring -c -i ${fastq1} ${fastq2} -o ${spring_op} -t ${thread_num} > std.out 2>&1"
    
    echo "Starting to create compressed file..."
    if $compress_cmd >> "$log_file"; then
        end=$(date +%s.%N)
        runtime=$(echo "$end - $start" | bc)
        formatted_runtime=$(printf "%.2f" "$runtime")
        echo "Compressed file created. Time taken: $formatted_runtime seconds." >> "$checkpoint_file"
        echo "Compressed file created. Time taken: $formatted_runtime seconds. 50% of compression complete."
    else
	echo "Unknown error while creating compressed file. Exiting..."
        exit 1 
    fi
else
    echo "Spring file already created. Skipping step..."
fi

if ! grep -qF "Bam file for tags created" "$checkpoint_file"; then
    #if [ "$metadata_flag" -eq 0 ];then 
    start=$(date +%s.%N)
    tag_cmd="python3 write_tag_lines.py ${input_bam}"
    echo "Starting to fetch reads with tags..."
    if $tag_cmd >> "$log_file" 2>&1; then
        end=$(date +%s.%N)
        runtime=$(echo "$end - $start" | bc)
        formatted_runtime=$(printf "%.2f" "$runtime")
        echo "Bam file for tags created. Time taken : $formatted_runtime seconds." >>  "$checkpoint_file"
        echo "Bam file for tags created. Time taken : $formatted_runtime seconds. 99% compression complete"
    else
        echo "Unknown error while creating bam file for tags. Exiting..."
        exit 1
    fi
    #else
    #    echo "Not creating files to store metadata. Deleting stale metadata files..."
    #    if [ -f "$tag_file" ];then
    #     rm $tag_file
    #    fi
    #    if [ -f "$map_file" ];then
    #     rm $map_file
    #    fi
    #fi
else
    echo "Bam file for tags already created. Skipping step..."
fi

if ! grep -qF "md5sum for SPRING file stored" "$checkpoint_file"; then
    if [ -f "$spring_op" ];then	
	start=$(date +%s.%N)
    	md5_cmd="md5sum ${spring_op} > compression_outputs/${input_arg}/${input_arg}_spring.md5"
    	eval $md5_cmd
    	if [ $? -eq 0 ]; then
            end=$(date +%s.%N)
            runtime=$(echo "$end - $start" | bc)
            formatted_runtime=$(printf "%.2f" "$runtime")
            echo "md5sum for SPRING file stored. Time taken: $formatted_runtime seconds." >> "$checkpoint_file"
    	fi
    else
	echo "SPRING file not present. Not able to calculate md5sum. Exiting..."
	exit 1
    fi
else
    echo "md5sum for SPRING file already stored. Skipping step..."
fi

if ! grep -qF "md5sum for input file stored" "$checkpoint_file"; then
    start=$(date +%s.%N)
    md5_cmd="md5sum ${input_bam} > compression_outputs/${input_arg}/${input_arg}_input.md5"
    eval $md5_cmd
    if [ $? -eq 0 ]; then
        end=$(date +%s.%N)
        runtime=$(echo "$end - $start" | bc)
        formatted_runtime=$(printf "%.2f" "$runtime")
        echo "md5sum for input file stored. Time taken: $formatted_runtime seconds." >> "$checkpoint_file"
        echo "Wrapping up..."
    fi
else
    echo "md5sum for input file already stored. Skipping step..."
    echo "Wrapping up."
fi

if [ "$retain_flag" -eq 0 ] && [ -f "$spring_op" ] && [ -f "$fastq1" ] && [ -f "$fastq2" ]; then
    rm "$fastq1"
    rm "$fastq2"
fi

source_folder="compression_outputs/${input_arg}"
output_file="compression_outputs/${input_arg}.gi"
if [ "$retain_flag" -eq 0 ];then
    tar_cmd="tar -czf ${output_file} ${source_folder}"
    if ! $tar_cmd; then
    	echo "Error while finishing the compression process. Try again..."
        exit 1
    fi
else
    tar_cmd="tar -czf ${output_file} --exclude='*.fastq' ${source_folder}"
    if ! $tar_cmd; then
        echo "Error while finishing the compression process. Try again..."
        exit 1
    fi
fi

if [ "$retain_flag" -eq 0 ];then
    rm_cmd="rm -rf ${source_folder}"
    if ! $rm_cmd; then
        echo "Error while removing temporary directory..."
	exit 1
    fi
fi

