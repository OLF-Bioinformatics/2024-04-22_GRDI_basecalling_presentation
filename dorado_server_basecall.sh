######################## Installation - Only run first time ######################


# Create folder to hold program
[ -d $HOME/prog ] || mkdir -p $HOME/prog
cd $HOME/prog

# Get dorado server
wget https://cdn.oxfordnanoportal.com/software/analysis/ont-dorado-server_7.3.9_linux64.tar.gz

# Extract archive
tar zxvf ont-dorado-server_7.3.9_linux64.tar.gz

# Remove archive
rm ont-dorado-server_7.3.9_linux64.tar.gz

# Make sure we can call dorado from anywhere
echo "export PATH=\$PATH:\$HOME/prog/ont-dorado-server/bin" | tee -a $HOME/.bashrc

# Apply changes
source $HOME/.bashrc


############################## End of installation ###############################



############################# User defined variables #############################

# Inputs
pod5="/data/my_pod5_folder"

# Outputs
baseDir="$HOME/my_basecall_folder"

# Basecalling
# Model can be selected automatically with more recent chemistries.
# See: https://github.com/nanoporetech/dorado?tab=readme-ov-file#automatic-model-selection-complex
dorado_model="dna_r10.4.1_e8.2_400bps_sup@v4.1.0"  #"dna_r9.4.1_e8_sup@v3.6"
bc_kit="VSK-VMK004"

# All config files can be displayed using:
# ls $HOME/prog/ont-dorado-server/data/*.cfg
config="dna_r10.4.1_e8.2_400bps_5khz_sup.cfg"  # dna_r9.4.1_450bps_sup.cfg
port=5555
min_qscore=9 # 9 for R10 and 7 for R9

# Barcode description
bc_desc="${pod5}"/barcode_description.txt
 
echo -e "barcode01\tsample1
barcode02\tsample2
barcode03\tsample3
barcode04\tsample4
barcode05\tsample5
barcode06\tsample6
" > "$bc_desc"

########################## End of user defined variables #########################


###############
#             #
# Performance #
#             #
###############


# Set CPU, memory
export cpu=$(nproc)
export mem=$(($(grep MemTotal /proc/meminfo | awk '{print $2}')*85/100000000)) #85% of total memory in GB
export memJava="-Xmx"$mem"g"
export maxProc=8


#############
#           #
# Other I/O #
#           #
#############


# Set folders
prog=$HOME/prog
models="${baseDir}"/dorado_models
export basecalled="${baseDir}"/dorado_sup
logs="${baseDir}"/logs
export demultiplexed="${baseDir}"/demultiplexed
pycoQC="${baseDir}"/pycoQC

# Create folders
[ -d "$baseDir" ] || mkdir -p "$baseDir"
[ -d "$models" ] || mkdir -p "$models"
[ -d "$basecalled" ] || mkdir -p "$basecalled"
[ -d "$logs" ] || mkdir -p "$logs"
[ -d "$demultiplexed" ] || mkdir -p "$demultiplexed"
[ -d "$pycoQC" ] || mkdir -p "$pycoQC"


######################
#                    #
# Dorado basecalling #
#                    #
######################


# Start server
# Note that this will lock your terminal
cd "$basecalled"

dorado_basecall_server \
    --config "$config" \
    --port "$port" \
    --log_path "${baseDir}"/logs \
    --device 'cuda:all' &


# Send files to basecalle to server
# Note that this has to be done in a new terminal window
# --bam_out
# ipc:///home/bioinfo/prog/ont-dorado-server/bin/"$port"
# --sample_sheet "$sample_sheet" \
ont_basecall_client \
    --port "$port" \
    --config "$config" \
    --input_path "$pod5" \
    --recursive \
    --save_path "$dorado_sup" \
    --calib_detect \
    --compress_fastq \
    --records_per_fastq 0 \
    --disable_pings \
    --min_qscore "$min_qscore" \
    --barcode_kits "$bc_kit" \
    --enable_trim_barcodes \
    --detect_primer \
    --trim_primers \
    --detect_adapter \
    --trim_adapters \
    --detect_mid_strand_adapter \
    --detect_mid_strand_barcodes

# The basecalling server can be stopped now


# Merge the demultiplexed fastq files into one file per barcode
for i in $(find "$basecalled" -mindepth 2 -maxdepth 2 -type d); do  # pass and fail
    barcode=$(basename "$i")
    flag=$(basename $(dirname "$i"))
 
    find "$i" -mindepth 1 -maxdepth 1 -type f -name "*.fastq.gz" -name "fastq_runid_*" \
        -exec cat {} \; > "${i}"/"${barcode}"_"${flag}".fastq.gz

    # Remove non compressed files
    find "$i" -type f -name "*fastq_runid_*" -exec rm {} \;
done

# Rename files
# Parse barcode descriptions into an array
declare -A myArray=()

# Read tab-separated file line by line
while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(sed -e 's/ /\t/' -e 's/\r//g' -e 's/\n//g' <<< "$line")"  # Transform the space output field separator from read into tabs, remove carriage return
    key="$(cut -f 1 <<< "$line")"  # Get barcode
    value="$(cut -f 2 <<< "$line")"  # Get alias
    if [[ -n "$key" ]]; then
        myArray["${key}"]="${value}"  # Add to array
    fi
done < "$bc_desc"

# Proceed to renaming
find "${basecalled}"/ -type f -name "*_pass*" -o -name "*_fail*" | while read i; do
    pathPart="$(dirname "$i")"
    oldName="$(basename "$i")"
 
    # For each file, check if a part of the name matches on
    for j in "${!myArray[@]}"; do
        if [ "$(echo "$oldName" | grep "$j")" ]; then
            newName="$(echo "$oldName" | sed "s/"$j"/"${myArray["$j"]}"/")"
            fullNewName=""${pathPart}"/"${newName}""
 
            if [ -e "$rename" ]; then
                echo "Cannot rename "$oldName" to "$newName", file already exists. Skipping"
                continue
            fi
 
            echo ""$i" -> "$fullNewName""
            mv "$i" "$fullNewName"
        fi
        if [ "$(echo "$pathPart" | grep "$j")" ]; then
            # Rename folder too
            echo ""$pathPart" -> $(dirname "$pathPart")/"${myArray["$j"]}""
            mv $pathPart $(dirname "$pathPart")/"${myArray["$j"]}"
        fi
    done
done

# Remove samples starting by "barcode"
# They were not renamed because we didn't added them to our run
# These files typically contain very few reads
find "$basecalled" -type d -name "*barcode*" -exec rm -rf {} \;


###########
#         #
# Read QC #
#         #
###########


# Follow installation instructions here:
# https://github.com/duceppemo/pycoQC

# Activate PycoQC virtual environment
conda activate pycoQC

# Create sequencing_summary from fastq
Fastq_to_seq_summary \
    -t $(nproc) \
    -f "$basecalled" \
   -s "${pycoQC}"/seq_summary_dorado.txt

# Run pycoQC
pycoQC \
    -f "${pycoQC}"/seq_summary_dorado.txt \
    -o "${pycoQC}"/pycoQC_dorado.html \
    --min_pass_qual "$min_qscore"

conda deactivate  # pycoQC
