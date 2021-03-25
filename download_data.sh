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
declare -a BLACKLIST_URLS=('https://github.com/Boyle-Lab/Blacklist/raw/master/lists/dm3-blacklist.v2.bed.gz' 'https://github.com/Boyle-Lab/Blacklist/raw/master/lists/ce10-blacklist.v2.bed.gz' 'https://github.com/Boyle-Lab/Blacklist/raw/master/lists/mm9-blacklist.v2.bed.gz')

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
done

# Download the training data.
# TODO
# Download ce10.sorted_data.all.bed.gz etc.
# Download validation data.
# Download test data.


# Download the MPRA data.
# TODO.

# Download the O. latipes data.
# Genome
# Raw data
# Process raw data.

# Download the conservation scores.
