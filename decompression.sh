#!/bin/sh
input_file="$1"
if [ ! -f "${input_file}" ]; then
    echo "Error: The file ${input_file} does not exist."
    exit 1
fi
#metadata_files_flag=0
#metadata_flag=0
retain_flag=0
restart_flag=0
num_threads=32

for arg in "$@"; do
    if [ "$arg" = "--retain" ]; then
        retain_flag=1
    fi
    if [ "$arg" = "--restart" ]; then
        restart_flag=1
    fi
    #if [ "$arg" = "--nometadata" ]; then
    #    metadata_flag=1
    #fi
done
while [[ $# -gt 0 ]]; do
    case "$1" in
        --threads)
            shift
            if [[ $# -gt 0 ]]; then
                if [[ $1 =~ ^[0-9]+$ ]]; then
                    num_threads=$1
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
basename=$(basename "$input_file")
input_arg="${basename%.gi}"
compress_folder="${input_arg}_compressed"
folder="decompression_outputs"
if [ ! -d "decompression_outputs" ]; then
    mkdir "decompression_outputs"
fi
if [ ! -d "decompression_outputs/${compress_folder}" ]; then
    mkdir "decompression_outputs/${compress_folder}"
fi
if [ ! -d "decompression_outputs/${input_arg}" ]; then
    mkdir "decompression_outputs/${input_arg}"
fi
tar_cmd="tar -xzf ${input_file} -C ${folder}/${compress_folder} --transform='s/^.*\///'"
echo "Starting decompression on $basename."
eval $tar_cmd 
if ! [ $? -eq 0 ]; then
    echo "Error encountered while fetching details from .gi file. Exiting."
    exit 1
fi
var_num1="${folder}/${input_arg}/${input_arg}_1."
var_num2="${folder}/${input_arg}/${input_arg}_2."
var_input="${folder}/${compress_folder}/${input_arg}_SPRING.spring"
var_fastq1="${folder}/${input_arg}/${input_arg}_decompress_1.fastq"
var_fastq2="${folder}/${input_arg}/${input_arg}_decompress_2.fastq"
checkpoint_file="${folder}/${input_arg}/${input_arg}_decompress.checkpoint"
log_file="${folder}/${input_arg}/${input_arg}_decompress.log"
tag_file="${folder}/${compress_folder}/${input_arg}_tags.bam"
map_file="${folder}/${compress_folder}/${input_arg}_map.txt"

#if [ ! -f ${tag_file} ];then
#    metadata_files_flag=1
#fi
#if [ ! -f ${map_file} ];then
#    metadata_files_flag=1
#fi
if [ "$restart_flag" -eq 1 ] && [ -f ${folder}/${input_arg}/${input_arg}_decompress.checkpoint ]; then
    rm ${folder}/${input_arg}/${input_arg}_decompress.checkpoint
fi
if [ ! -f ${folder}/${input_arg}/${input_arg}_decompress.checkpoint ]; then
    touch ${folder}/${input_arg}/${input_arg}_decompress.checkpoint
fi
if [ ! -f ${folder}/${input_arg}/${input_arg}_decompress.log ]; then
    touch ${folder}/${input_arg}/${input_arg}_decompress.log
fi

if ! grep -qF "Paired fastq files" "$checkpoint_file"; then
    start=$(date +%s.%N)
    spring_cmd="tools/spring  -d  -i  ${var_input} -o ${var_fastq1} ${var_fastq2} -t ${num_threads}" 
    
    echo "Starting to create paired fastq files..."
    if $spring_cmd >> "$log_file" 2>&1; then
        end=$(date +%s.%N)
        runtime=$(echo "$end - $start" | bc)
	    formatted_runtime=$(printf "%.2f" "$runtime")
        echo "Paired fastq files created. Time taken : $formatted_runtime seconds.">>"$checkpoint_file"
        echo "Paired fastq files created. Time taken : $formatted_runtime seconds. 15% decompression complete."
    else
        echo "Unknown error while creating paired fastq files. Exiting..."
        exit 1
    fi
else
    echo "Paired fastq files already created. Skipping step..."
fi

if ! grep -qF "Lane files for fastq 1" "$checkpoint_file"; then
    start=$(date +%s.%N)
    awk_1="awk -v var=${var_num1} 'BEGIN {FS = \":\"} {lane=\$2 ; print >  (var lane \".fastq\") ; for (i = 1; i <= 3; i++) {getline ; print > (var lane \".fastq\")}}' < ${var_fastq1}"
    
    echo "Starting to create lane files for fastq file 1..."
    if eval "$awk_1"; then
    	end=$(date +%s.%N)
    	runtime=$(echo "$end - $start" | bc)
	formatted_runtime=$(printf "%.2f" "$runtime")
    	if [ "$retain_flag" -eq 0 ]; then
		    rm $var_fastq1
    	fi
    	echo "Lane files for fastq 1 created. Time taken : $formatted_runtime seconds." >> "$checkpoint_file"
        echo "Lane files for fastq 1 created. Time taken : $formatted_runtime seconds. 20% decompression complete."
    else
        echo "Unknown error while creating lane files for fastq 1. Exiting..."
        exit 1
    fi
else
    echo "Lane files for fastq 1 already created. Skipping step..."
fi

if ! grep -qF "Lane files for fastq 2" "$checkpoint_file"; then
    start=$(date +%s.%N)
    awk_2="awk -v var2=${var_num2} 'BEGIN {FS = \":\"} {lane=\$2 ; print > (var2 lane \".fastq\") ; for (i = 1; i <= 3; i++) {getline ; print >  (var2 lane \".fastq\")}}' < ${var_fastq2}"
    echo "Starting to create lane files for fastq file 2..."
    if eval "$awk_2"; then
        end=$(date +%s.%N)
        runtime=$(echo "$end - $start" | bc)
	formatted_runtime=$(printf "%.2f" "$runtime")
        if [ "$retain_flag" -eq 0 ]; then
		    rm $var_fastq2
        fi
	echo "Lane files for fastq 2 created. Time taken : $formatted_runtime seconds.">>"$checkpoint_file"
        echo "Lane files for fastq 2 created. Time taken : $formatted_runtime seconds. 25% decompression complete."
    else
        echo "Unknown error while creating lane files for fastq 2. Exiting..."
        exit 1
    fi
else
    echo "Lane files for fastq 2 already created. Skipping step..."
fi

fastq_file_count=$(ls "$folder"/"$input_arg"/"$input_arg"_1.*.fastq| wc -l)

if ! grep -qF "Bam files for each lane" "$checkpoint_file"; then
    start=$(date +%s.%N)
    process_lane() {
        i=$1
        folder="decompression_outputs"
	    input_arg=$2
        log_file="${folder}/${input_arg}/${input_arg}_decompress.log"
	    lane_var="Lane${i}.${i}"
        picard_cmd="java -jar tools/picard.jar FastqToSam --FASTQ ${folder}/${input_arg}/${input_arg}_1.${i}.fastq --FASTQ2 ${folder}/${input_arg}/${input_arg}_2.${i}.fastq --OUTPUT ${folder}/${input_arg}/${input_arg}_${i}.bam -SM ${input_arg} --VERBOSITY ERROR -RG "$lane_var""
        if $picard_cmd >> "$log_file" 2>&1 ; then
            echo "Bam file for lane ${i} created..."
        else
            echo "Unknown error while creating lane bam file for lane ${i}. Exiting..."
            exit 1
        fi
    }

    export -f process_lane
    
    echo "Starting to create bam files for each lane..."
    seq 1 $fastq_file_count | parallel -j 4 process_lane {} $input_arg

    end=$(date +%s.%N)
    runtime=$(echo "$end - $start" | bc)
    formatted_runtime=$(printf "%.2f" "$runtime")
    if [ $(printf "%.0f" "$runtime") -gt 1000 ]; then
        echo "Bam files for each lane created. Time taken : $formatted_runtime seconds." >> "$checkpoint_file"
        echo "Bam files for each lane created. Time taken : $formatted_runtime seconds. 40% decompression complete."
    fi
else
    echo "Bam files for each lane already created. Skipping step..."
fi

if ! grep -qF "Bam files merged" "$checkpoint_file"; then
    concatenated="samtools merge -@ ${num_threads} -f ${folder}/${input_arg}/${input_arg}_merged.bam"
    for ((i=1; i<=fastq_file_count; i++)); do
        concatenated+=" ${folder}/${input_arg}/${input_arg}_${i}.bam"
    done
    start=$(date +%s.%N)
    
    echo "Starting to merge bam files..."
    if $concatenated; then
        end=$(date +%s.%N)
        runtime=$(echo "$end - $start" | bc)
	    formatted_runtime=$(printf "%.2f" "$runtime")
        if [ "$retain_flag" -eq 0 ]; then
            for ((i=1; i<=fastq_file_count; i++)); do
                        rm ${folder}/${input_arg}/${input_arg}_${i}.bam
                done
            rm -f ${folder}/${input_arg}/*.fastq
        fi
        echo "Bam files merged. Time taken for merging : $formatted_runtime seconds.">>"$checkpoint_file"
        echo "Bam files merged. Time taken for merging : $formatted_runtime seconds. 45% decompression complete."
    else
        echo "Unknown error while merging bam files. Exiting..."
        exit 1
    fi
else
    echo "Bam files already merged. Skipping step..."
fi

if ! grep -qF "Index file created" "$checkpoint_file"; then
    start=$(date +%s.%N)
    index_cmd="samtools index ${folder}/${input_arg}/${input_arg}_merged.bam"

    echo "Starting to create index file..."
    if $index_cmd; then
       end=$(date +%s.%N)
       runtime=$(echo "$end - $start" | bc)
       formatted_runtime=$(printf "%.2f" "$runtime")
       echo "Index file created for merged bam file. Time taken : $formatted_runtime seconds.">>"$checkpoint_file"
       echo "Index file created for merged bam file. Time taken : $formatted_runtime seconds. 50% decompression complete."
    else
        echo "Unknown error while creating index file. Exiting..."
        exit 1
    fi
else
    echo "Index file already created for merged bam file. Skipping step..."
fi

if ! grep -qF "Missing tags added" "$checkpoint_file"; then
    #if [ "$metadata_flag" -eq 1 ]; then
    #	echo "Not adding tags as specified in command..."
    #elif [ "$metadata_files_flag" -eq 1 ]; then
    #    echo "Not adding tags as required metadata files missing. Run compression again without metadata flag to obtain metadata files..."
    #else
	start=$(date +%s.%N)

    	echo "Starting to add missing tags..."
    	tag_cmd="python3 add_tags.py $input_arg" 
    	if $tag_cmd >> "$log_file" 2>&1; then
            end=$(date +%s.%N)
            runtime=$(echo "$end - $start" | bc)
	    formatted_runtime=$(printf "%.2f" "$runtime")
	    if [ "$retain_flag" -eq 0 ]; then	
		rm ${folder}/${input_arg}/${input_arg}_merged.bam
		rm ${folder}/${input_arg}/${input_arg}_merged.bam.bai
	    fi
	    echo "Missing tags added. Time taken : $formatted_runtime seconds.">>"$checkpoint_file"
	    echo "Missing tags added. Time taken : $formatted_runtime seconds. 100% decompression complete."
        else
            echo "Unknown error while adding missing tags. Exiting..."
            exit 1
        fi
    #fi
else
    echo "Missing tags already added. Skipping step..."
fi

if ! grep -qF "md5sum for BAM file stored" "$checkpoint_file"; then
    start=$(date +%s.%N)
    tag_cmd="md5sum ${folder}/${input_arg}/${input_arg}.bam > ${folder}/${input_arg}/${input_arg}.md5"
    eval $tag_cmd
    if [ $? -eq 0 ]; then
        end=$(date +%s.%N)
        runtime=$(echo "$end - $start" | bc)
	formatted_runtime=$(printf "%.2f" "$runtime")
        echo "md5sum for BAM file stored. Time taken: $formatted_runtime seconds." >> "$checkpoint_file"
	echo "Wrapping up..."
    else
        echo "Unknown error while calculating md5sum for BAM file. Exiting..."
        exit 1
    fi
else
    echo "md5sum for BAM file already stored. Skipping step..."
    echo "Wrapping up..."
fi
remove_folder_cmd="rm -rf decompression_outputs/${compress_folder}"
copy_md5_cmd="cp ${folder}/${compress_folder}/${input_arg}_input.md5 ${folder}/${input_arg}/${input_arg}_input.md5"

if ! $copy_md5_cmd; then
    echo "Could not copy input md5 file. Try again."
    exit 1
fi

if ! $remove_folder_cmd; then
    echo "Could not delete temporary folder."
    exit 1
fi

