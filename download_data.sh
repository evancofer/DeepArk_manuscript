#!/usr/bin/env bash

# Setup directory.
if [ ! -e 'data' ]; then
    echo 'Making data directory.'
    mkdir 'data'
    if [ $? != 0 ]; then
        echo 'Failed to create data directory.'
        exit 1
    fi
fi

cd 'data'
if [ $? != 0 ]; then
    echo 'Failed to enter data directory.'
    exit 1
fi

# Download genomes.
declare -a GENOME_URLS=('https://hgdownload.soe.ucsc.edu/goldenPath/mm10/bigZips/mm10.2bit' 'https://hgdownload.soe.ucsc.edu/goldenPath/ce11/bigZips/ce11.2bit' 'https://hgdownload.soe.ucsc.edu/goldenPath/dm6/bigZips/dm6.2bit' 'https://hgdownload.soe.ucsc.edu/goldenPath/danRer11/bigZips/danRer11.2bit')

for URL in "${GENOME_URLS[@]}"; do
    echo "Downloading: $URL"

    wget "${URL}"  2>/dev/null || curl -O "${URL}"
    if [ $? != 0 ]; then
        echo 'Failed downloading the genome from '"${URL}"
        exit 1
    fi

    GENOME=$(basename "${URL}")
    if [ $? != 0 ]; then
        echo 'Failed getting genome name.'
        exit 1
    fi
    twoBitToFa "${GENOME}" "${GENOME%.*}"'.fa'
    if [ $? != 0 ]; then
        echo 'Failed running twoBitToFa on '"${GENOME}"
        exit 1
    fi
    faidx --no-output "${GENOME%.*}"'.fa'
    if [ $? != 0 ]; then
        echo 'Failed to index '"${GENOME%.*}"'.fa'
        exit 1
    fi
    echo 'Downloaded and processed '"${GENOME}"' successfully'
done

# Download genome blacklists.
declare -a BLACKLIST_URLS=('https://github.com/Boyle-Lab/Blacklist/raw/master/lists/dm3-blacklist.v2.bed.gz' 'https://github.com/Boyle-Lab/Blacklist/raw/master/lists/ce10-blacklist.v2.bed.gz' 'https://github.com/Boyle-Lab/Blacklist/raw/master/lists/mm10-blacklist.v2.bed.gz')

for URL in "${BLACKLIST_URLS[@]}"; do
    echo "Downloading: $URL"
    LOCAL_FILE=$(basename "${URL}")
    LOCAL_UNZIP_FILE="${LOCAL_FILE%.*}"
    GENOME="${LOCAL_FILE%-*}"
    LOCAL_FINAL_FILE="${GENOME}"'.blacklist.bed.gz'
    if [ ! -e "${LOCAL_FINAL_FILE}" ]; then
        if [ ! -e "${LOCAL_FINAL_FILE%.*}" ]; then
            if [ ! -e "${LOCAL_UNZIP_FILE}" ]; then
                if [ ! -e "${LOCAL_FILE}" ]; then
                    wget "${URL}"  2>/dev/null || curl -O "${URL}"
                    if [ $? != 0 ]; then
                        echo 'Failed downloading the blacklist from '"${URL}"
                        exit 1
                    fi
                fi
                gunzip "${LOCAL_FILE}"
                if [ $? != 0 ]; then
                    echo 'Failed to gunzip '"${LOCAL_FILE}"
                    exit 1
                fi
            fi
            cut -f 1,2,3 "${LOCAL_UNZIP_FILE}" >"${LOCAL_FINAL_FILE%.*}"
            if [ $? != 0 ]; then
                echo 'Failed to format '"${LOCAL_UNZIP_FILE}"' and store in '"${LOCAL_FINAL_FILE%.*}"
                exit 1
            fi
        fi
        bgzip "${LOCAL_FINAL_FILE%.*}"
        if [ $? != 0 ]; then
            echo 'Failed to bgzip '"${LOCAL_FINAL_FILE%.*}"
            exit 1
        fi
    fi
    if [ ! -e "${LOCAL_FINAL_FILE}"'.tbi' ]; then
        tabix -p bed "${LOCAL_FINAL_FILE}"
        if [ $? != 0 ]; then
            echo 'Failed to index the file at '"${LOCAL_FINAL_FILE}"
            exit 1
        fi
    fi
    if [ "${GENOME}" == 'mm10' ]; then
        gunzip -c "${LOCAL_FINAL_FILE}" >'mm10_prelift.bed'
        if [ $? != 0 ]; then
            echo 'Failed to create prelift file for mm10'
            exit 1
        fi
        # Download chain file.
        if [ ! -e 'mm10ToMm9.over.chain' ]; then
            if [ ! -e 'mm10ToMm9.over.chain.gz' ]; then
                wget 'http://hgdownload.soe.ucsc.edu/goldenPath/mm10/liftOver/mm10ToMm9.over.chain.gz'
                if [ $? != 0 ]; then
                    echo 'Failed to download mm10 to mm9 chain file.'
                    exit 1
                fi
            fi
            gunzip 'mm10ToMm9.over.chain.gz'
            if [ $? != 0 ]; then
                echo 'Failed to unzip mm10 to mm9 chain file.'
                exit 1
            fi
        fi
        if [ ! -e 'mm9.blacklist.bed.gz' ]; then
            if [ ! -e 'mm9.blacklist.bed' ]; then
                if [ ! -e 'mm9_postlift.bed' ]; then
                    # Perform liftover.
                    liftOver 'mm10_prelift.bed' 'mm10ToMm9.over.chain' 'mm9_postlift.bed' 'unmapped.bed'
                    if [ $? != 0 ]; then
                        echo 'Failed lifting mm10 to mm9 blacklist.'
                        exit 1
                    fi
                fi
                sort -k1V -k2n -k3n 'mm9_postlift.bed' >'mm9.blacklist.bed'
                if [ $? != 0 ]; then
                    echo 'Failed to sort post-lift mm9 blacklist.'
                    exit 1
                fi
            fi
            bgzip 'mm9.blacklist.bed'
            if [ $? != 0 ]; then
                echo 'Failed to compress mm9 blacklist.'
                exit 1
            fi
        fi
        if [ ! -e 'mm9.blacklist.bed.gz.tbi' ]; then
            tabix -p bed 'mm9.blacklist.bed.gz'
            if [ $? != 0 ]; then
                echo 'Failed to tabix index mm9 blacklist.'
                exit 1
            fi
        fi
    fi
done

# Download the training data.
# TODO
# Download ce10.sorted_data.all.bed.gz etc.

# Generate all the validation data.
conda deactivate
conda activate 'DeepArk_manuscript_train'
if [ $? != 0 ]; then
    echo 'Failed to activate training environment for generating validation data.'
    exit 1
fi
declare -a ORGANISMS=('mus_musculus' 'danio_rerio' 'caenorhabditis_elegans' 'drosophila_melanogaster')
declare -a GENOMES=('mm9' 'danRer11' 'ce10' 'dm3')
for i in "${!ORGANISMS[@]}"; do
    ORGANISM="${ORGANISMS[i]}"
    GENOME="${GENOMES[i]}"
    cd 'train'
    if [ $? != 0 ]; then
        echo 'Failed to enter training directory to generate validation data for '"${ORGANISM}"
        exit 1
    fi
    python ./train/write_h5.py 'train/validate.'"${ORGANISM}"'.yml' 'validate' '1000' '1337' True "${GENOME}"'.'
    if [ $? != 0 ]; then
        echo 'Failed to generate validation data for '"${ORGANISM}"
        exit 1
    fi
done


# Download test data.


# Download the MPRA data.
# TODO.

# Download the O. latipes data.
# Genome
# Raw data
# Process raw data.

# Download the conservation scores.
