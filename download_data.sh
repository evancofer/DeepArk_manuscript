#!/usr/bin/env bash

source "${HOME}"'/.bashrc' # This is because conda will not work otherwise..

conda activate 'DeepArk_manuscript'
if [ $? != 0 ]; then
    echo 'Failed to activate the DeepArk_manuscript conda environment.'
    exit 1
fi


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
declare -a GENOME_URLS=('https://hgdownload.soe.ucsc.edu/goldenPath/mm9/bigZips/mm9.2bit' 'https://hgdownload.soe.ucsc.edu/goldenPath/ce10/bigZips/ce10.2bit' 'https://hgdownload.soe.ucsc.edu/goldenPath/dm3/bigZips/dm3.2bit' 'https://hgdownload.soe.ucsc.edu/goldenPath/dm6/bigZips/dm6.2bit' 'https://hgdownload.soe.ucsc.edu/goldenPath/danRer11/bigZips/danRer11.2bit')

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
declare -a ZENODO_URLS=('https://zenodo.org/record/4647691/files/ce10.sorted_data.all.bed.gz' 'https://zenodo.org/record/4647691/files/ce10.sorted_data.all.bed.gz.tbi' 'https://zenodo.org/record/4647691/files/danRer11.sorted_data.all.bed.gz' 'https://zenodo.org/record/4647691/files/danRer11.sorted_data.all.bed.gz.tbi' 'https://zenodo.org/record/4647691/files/dm3.sorted_data.all.bed.gz' 'https://zenodo.org/record/4647691/files/dm3.sorted_data.all.bed.gz.tbi' 'https://zenodo.org/record/4647691/files/mm9.sorted_data.all.bed.gz' 'https://zenodo.org/record/4647691/files/mm9.sorted_data.all.bed.gz.tbi')
for URL in "${ZENODO_URLS[@]}"; do
    wget "${URL}"
    if [ $? != 0 ]; then
        echo 'Failed to download from '"${URL}"
        exit 1
    fi
done

# Generate all the validation and testing data.
cd '../train'
if [ $? != 0 ]; then
    echo 'Failed to exit the data directory and enter the training directory.'
    exit 1
fi
conda deactivate
if [ $? != 0 ]; then
    echo 'Failed to deactivate conda environment.'
    exit 1
fi
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
    python ./write_h5.py 'validate.'"${ORGANISM}"'.yml' 'validate' '1000' '1337' True '../data/'"${GENOME}"'.'
    if [ $? != 0 ]; then
        echo 'Failed to generate validation data for '"${ORGANISM}"
        exit 1
    fi
    python ./write_h5.py 'test.'"${ORGANISM}"'.yml' 'test' '15625' '1337' 'True' '../data/'"${GENOME}"'.'
    if [ $? != 0 ]; then
        echo 'Failed to generate test data for '"${ORGANISM}"
        exit 1
    fi
done

# Download the MPRA data.
cd '../data'
if [ $? != 0 ]; then
    echo 'Failed to cd to data.'
    exit 1
fi
wget 'https://zenodo.org/record/4060298/files/data.tsv.gz'
if [ $? != 0 ]; then
    echo 'Failed to download MPRA data.'
    exit 1
fi
if [ ! -e 'mpra_data.tsv' ]; then
    gunzip -c 'data.tsv.gz' >'mpra_data.tsv'
    if [ $? != 0 ]; then
        echo 'Failed to unzip MPRA data.'
        exit 1
    else
        rm 'data.tsv.gz'
        if [ $? != 0 ]; then
            echo 'Failed to cleanup MPRA data download.'
            exit 1
        fi
    fi
fi
#samtools faidx ~/data/genomes/hg19.fa chr9:104193652-104197746

# Download the O. latipes data.
# Genome
# Raw data
# Process raw data.

# Download the conservation scores.
