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
declare -a GENOME_URLS=('https://hgdownload.soe.ucsc.edu/goldenPath/mm9/bigZips/mm9.2bit' 'https://hgdownload.soe.ucsc.edu/goldenPath/ce10/bigZips/ce10.2bit' 'http://hgdownload.soe.ucsc.edu/goldenPath/ce11/bigZips/ce11.2bit' 'https://hgdownload.soe.ucsc.edu/goldenPath/dm3/bigZips/dm3.2bit' 'https://hgdownload.soe.ucsc.edu/goldenPath/dm6/bigZips/dm6.2bit' 'https://hgdownload.soe.ucsc.edu/goldenPath/danRer11/bigZips/danRer11.2bit' 'https://hgdownload.soe.ucsc.edu/goldenPath/danRer10/bigZips/danRer10.2bit' 'http://hgdownload.soe.ucsc.edu/goldenPath/oryLat2/bigZips/oryLat2.2bit')
for URL in "${GENOME_URLS[@]}"; do
    echo "Downloading: $URL"
    GENOME=$(basename "${URL}")
    if [ $? != 0 ]; then
        echo 'Failed getting genome name.'
        exit 1
    fi
    if [ ! -e "${GENOME%.*}"'.fa' ]; then
        if [ ! -e "${GENOME%.*}"'.2bit' ]; then
            wget "${URL}"  2>/dev/null || curl -O "${URL}"
            if [ $? != 0 ]; then
                echo 'Failed downloading the genome from '"${URL}"
                exit 1
            fi
        fi
        twoBitToFa "${GENOME}" "${GENOME%.*}"'.fa'
        if [ $? != 0 ]; then
            echo 'Failed running twoBitToFa on '"${GENOME}"
            exit 1
        fi
    fi
    if [ ! -e "${GENOME%.*}"'.fa.fai' ]; then
        faidx --no-output "${GENOME%.*}"'.fa'
        if [ $? != 0 ]; then
            echo 'Failed to index '"${GENOME%.*}"'.fa'
            exit 1
        fi
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
    DST=$(basename "${URL}")
    if [ ! -e "${DST}" ]; then
        wget "${URL}"
        if [ $? != 0 ]; then
            echo 'Failed to download from '"${URL}"
            exit 1
        fi
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
    VAL_FILE='../data/'"${GENOME}"'.validate.seed=1337,N=64000,sequence_length=4095,bins_start=2047,bins_end=2048,bin_size=1,step_size=1,feature_thresholds=100.h5'
    if [ ! -e "${VAL_FILE}" ]; then
        python ./write_h5.py 'validate.'"${ORGANISM}"'.yml' 'validate' '1000' '1337' True '../data/'"${GENOME}"'.'
        if [ $? != 0 ]; then
            echo 'Failed to generate validation data for '"${ORGANISM}"
            exit 1
        fi
    fi
    TEST_FILE='../data/'"${GENOME}"'.test.seed=1337,N=1000000,sequence_length=4095,bins_start=2047,bins_end=2048,bin_size=1,step_size=1,feature_thresholds=100.h5'
    if [ ! -e "${TEST_FILE}" ]; then
        python ./write_h5.py 'test.'"${ORGANISM}"'.yml' 'test' '15625' '1337' 'True' '../data/'"${GENOME}"'.'
        if [ $? != 0 ]; then
            echo 'Failed to generate test data for '"${ORGANISM}"
            exit 1
        fi
    fi
done

conda deactivate
if [ $? != 0 ]; then
    echo 'Failed to deactivate conda environment.'
    exit 1
fi

# Download the MPRA data.
cd '../data'
if [ $? != 0 ]; then
    echo 'Failed to cd to data.'
    exit 1
fi
if [ ! -e 'mpra_data.tsv' ]; then
    if [ -e 'data.tsv.gz' ]; then
        rm 'data.tsv.gz'
        if [ $? != 0 ]; then
            echo 'Failed to remove existing data.tsv.gz file.'
            exit 1
        fi
    fi
    wget 'https://zenodo.org/record/4060298/files/data.tsv.gz'
    if [ $? != 0 ]; then
        echo 'Failed to download MPRA data.'
        exit 1
    fi
    gunzip -c 'data.tsv.gz' >'mpra_data.tsv'
    if [ $? != 0 ]; then
        echo 'Failed to unzip MPRA data.'
        rm 'mpra_data.tsv'
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

# Download coordinates for C elegans DCC scan of chrX.
if [ ! -e 'dcc_data.tsv' ]; then
    if [ -e 'data.tsv.gz' ]; then
        rm 'data.tsv.gz'
        if [ $? != 0 ]; then
            echo 'Failed to remove existing data.tsv.gz file.'
            exit 1
        fi
    fi
    wget 'https://zenodo.org/record/4663161/files/data.tsv.gz'
    if [ $? != 0 ]; then
        echo 'Failed to download DCC data.'
        exit 1
    fi
    gunzip -c 'data.tsv.gz' >'dcc_data.tsv'
    if [ $? != 0 ]; then
        echo 'Failed to unzip DCC data.'
        rm 'dcc_data.tsv'
        exit 1
    else
        rm 'data.tsv.gz'
        if [ $? != 0 ]; then
            echo 'Failed to cleanup DCC data download.'
            exit 1
        fi
    fi
fi
if [ ! -e 'c_elegans_chrX.bed' ]; then
    tail -n +2 'dcc_data.tsv' | \
        cut -f1,2,3 | sort -k1V -k2n -k3n | uniq >'c_elegans_chrX.bed'
    if [ $? != 0 ]; then
        echo 'Failed to create c_elegans_chrX.bed'
        rm 'c_elegans_chrX.bed'
        exit 1
    fi
fi

# Setup interspecies prediction data.
conda activate DeepArk_manuscript
if [ $? != 0 ]; then
    echo 'Failed to activate onda environment for interspecies prediction.'
    exit 1
fi
if [ ! -e 'oryLat2.normalized.fa' ]; then
    picard -Xmx32G -Xms8G NormalizeFasta INPUT='oryLat2.fa' OUTPUT='oryLat2.normalized.fa'
    if [ $? != 0 ]; then
        echo 'Failed to normalize oryLat2.fa with picard.'
        exit 1
    fi
    if [ -e 'oryLat2.normalized.fa.fai' ]; then
        rm 'oryLat2.normalized.fa.fai'
        if [ $? != 0 ]; then
            echo 'Failed to remove old index for oryLat2.'
            exit 1
        fi
    fi
    samtools faidx 'oryLat2.normalized.fa'
    if [ $? != 0 ]; then
        echo 'Failed to index normalized oryLat2 fasta.'
        exit 1
    fi
fi
if [ ! -e 'oryLat2.normalized.dict' ]; then
    picard -Xmx32G -Xms8G CreateSequenceDictionary REFERENCE='oryLat2.normalized.fa' OUTPUT='oryLat2.normalized.dict'
    if [ $? != 0 ]; then
        echo 'Failed to create sequence dictionary for normalized oryLat2 fasta.'
        exit 1
    fi
fi
if [ ! -e 'oryLat2.normalized.fa.bwt' ]; then
    bwa index 'oryLat2.normalized.fa'
    if [ $? != 0 ]; then
        echo 'Failed to index oryLat2 normalized fasta.'
        exit 1
    fi
fi
if [ ! -e 'multiz8way.maf.gz' ]; then
    wget 'http://hgdownload.soe.ucsc.edu/goldenPath/danRer7/multiz8way/multiz8way.maf.gz'
    if [ $? != 0 ]; then
        echo 'Failed to download multiway alignment for O. latipes and D. rerio.'
        exit 1
    fi
fi
if [ ! -e 'oryLat2.conserved.merged.bed.gz' ]; then
    if [ ! -e 'oryLat2.conserved.bed' ]; then
        python '../interspecies_prediction/get_conserved_regions.py' \
            --input-file  'multiz8way.maf.gz' \
            --output-file 'oryLat2.conserved.bed' \
            --organism 'oryLat2'
    fi
    if [ ! -e 'oryLat2.conserved.merged.bed' ]; then
        bedtools merge \
            -i 'oryLat2.conserved.bed' \
             >'oryLat2.conserved.merged.bed'
        if [ $? != 0 ]; then
            echo 'Failed to merge oryLat2 conserved regions.'
            exit 1
        fi
    fi
    bgzip 'oryLat2.conserved.merged.bed'
    if [ $? != 0 ]; then
        echo 'Failed to compress oryLat2 conserved merged regions.'
        exit 1
    fi
    if [ -e 'oryLat2.conserved.merged.bed.gz.tbi' ]; then
        rm 'oryLat2.conserved.merged.bed.gz.tbi'
        if [ $? != 0 ]; then
            echo 'Failed to remove old tabix index.'
            exit 1
        fi
    fi
fi
if [ ! -e 'oryLat2.conserved.merged.bed.gz.tbi' ]; then
    tabix -p bed 'oryLat2.conserved.merged.bed.gz'
    if [ $? != 0 ]; then
        echo 'Failed to tabix index the compressed oryLat2 conserved merged regions.'
        exit 1
    fi
fi
if [ ! -e 'danRer10ToOryLat2.over.chain' ]; then
    if [ ! -e 'danRer10ToOryLat2.over.chain.gz' ]; then
        wget 'http://hgdownload.soe.ucsc.edu/goldenPath/danRer10/liftOver/danRer10ToOryLat2.over.chain.gz'
    fi
    gunzip 'danRer10ToOryLat2.over.chain.gz'
    if [ $? != 0 ]; then
        echo 'Failed to unzip the danRer10 to oryLat2 chain.'
        exit 1
    fi
fi
# Download annotations.
ORGANISMS=('oryLat2' 'danRer10')
URLS=('http://ftp.ensembl.org/pub/release-80/gtf/oryzias_latipes/Oryzias_latipes.MEDAKA1.80.gtf.gz' 'http://ftp.ensembl.org/pub/release-80/gtf/danio_rerio/Danio_rerio.GRCz10.80.gtf.gz')
for i in "${!ORGANISMS[@]}"; do
    ORGANISM="${ORGANISMS[i]}"
    URL="${URLS[i]}"
    if [ ! -e "${ORGANISM}"'.gtf' ]; then
        if [ ! -e $(basename "${URL}") ]; then
            wget "${URL}"
            if [ $? != 0 ]; then
                echo 'Failed to download the '"${ORGANISM}"' annotations.'
                exit 1
            fi
        fi
        gunzip -c $(basename "${URL}") >"${ORGANISM}"'.gtf'
        if [ $? != 0 ]; then
            echo 'Failed to decompress the downloaded '"${ORGANISM}"' data.'
            exit 1
        fi
    fi
done
declare -a ORGANISMS=('oryLat2' 'danRer10')
for ORGANISM in "${ORGANISMS[@]}"; do
    if [ ! -e "${ORGANISM}"'.exon' ]; then
        hisat2_extract_exons.py "${ORGANISM}"'.gtf' >"${ORGANISM}"'.exon'
        if [ $? != 0 ]; then
            echo 'Failed to get exons for '"${ORGANISM}"
            exit 1
        fi

    fi
    if [ ! -e "${ORGANISM}"'.ss' ]; then
        hisat2_extract_splice_sites.py "${ORGANISM}"'.gtf' >"${ORGANISM}"'.ss'
        if [ $? != 0 ]; then
            echo 'Failed to extract splice sites for '"${ORGANISM}"
            exit 1
        fi
    fi
    if [ ! -e "${ORGANISM}"'.1.ht2' ]; then
        hisat2-build -p 16 --ss "${ORGANISM}"'.ss' --exon "${ORGANISM}"'.exon' "${ORGANISM}"'.fa' "${ORGANISM}"
        if [ $? != 0 ]; then
            echo 'Failed to buld index for '"${ORGANISM}"
            exit 1
        fi
    fi
done

if [ ! -e 'danRer10.pdia4.bed' ]; then
    seq 0 5 10000 | awk '{print "chr24\t" $1+17187212 "\t" $1+17187212+4095 "\tENSDARG00000018491_" $1 / 5}' >'danRer10.pdia4.bed'
    if [ $? != 0 ]; then
        echo 'Failed to genereate danRer10.pdia4.bed'
        exit 1
    fi
fi
if [ ! -e 'oryLat2.pdia4.bed' ]; then
    seq 0 5 10000 | awk '{print "chr20\t" $1+13068360 "\t" $1+13068360+4095 "\tENSORLG00000007272_" $1 / 5 }' >'oryLat2.pdia4.bed'
    if [ $? != 0 ]; then
        echo 'Failed to generate oryLat2.pdia4.bed'
        exit 1
    fi
fi
