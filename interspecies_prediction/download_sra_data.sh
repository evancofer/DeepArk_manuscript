#!/usr/bin/env bash

CORES="${1}"

source "${HOME}"'/.bashrc'

if [ ! -e 'data' ]; then
    mkdir 'data'
    if [ $? != 0 ]; then
        echo 'Failed to make data dir for interspecies prediction.'
        exit 1
    fi
fi

conda activate DeepArk_manuscript
if [ $? != 0 ]; then
    echo 'Failed to activate conda environment.'
    exit 1
fi

# Download the data from SRA.
cut -f1 -d, 'interspecies_info.csv' | \
    tail -n +2 | \
    tr -d '\"' | \
    sort | \
    uniq | \
while read -r ACCESSION; do
    fastq-dump --split-3 --gzip "${ACCESSION}" --outdir './data'
    if [ $? != 0 ]; then
        echo 'Failed to download '"${ACCESSION}"
        exit 1
    fi
done

if [ ! -e 'data/SRX3353221_2.fastq.gz' ]; then
    if [ ! -e 'data/SRR6246047_2.fastq.gz' ]; then
        fastq-dump --split-3 --gzip 'SRR6246047' --outdir './data'
        if [ $? != 0 ]; then
            echo 'Failed to download data for SRX3353221'
            exit 1
        fi
    fi
    mv 'data/SRR6246047_1.fastq.gz' 'data/SRX3353221_1.fastq.gz'
    if [ $? != 0 ]; then
        echo 'Failed to rename fastq file 1 for SRX3353221'
        exit 1
    fi
    mv 'data/SRR6246047_2.fastq.gz' 'data/SRX3353221_2.fastq.gz'
    if [ $? != 0 ]; then
        echo 'Failed to rename fastq file 2 for SRX3353221'
        exit 1
    fi

fi


if [ ! -e 'data/SRX3353227.fastq.gz' ]; then
    if [ ! -e 'data/SRR6246053.fastq.gz' ]; then
        fastq-dump --split-3 --gzip 'SRR6246053' --outdir './data'
        if [ $? != 0 ]; then
            echo 'Failed to download data for SRX3353227'
            exit 1
        fi
    fi
    mv 'data/SRR6246053.fastq.gz' 'data/SRX3353227.fastq.gz'
    if [ $? != 0 ]; then
        echo 'Failed to rename fastq for SRX3353227'
    fi
fi
if [ ! -e 'data/oryLat2_prediction.bed' ]; then
    python 'get_random_positions.py' \
        --genome-file '../data/oryLat2.fa' \
        --filter-file '../data/oryLat2.conserved.merged.bed.gz' \
        --sequence-length 4095 \
        --max-unk 50 \
        --n-positions 1000000 >'data/oryLat2_prediction.bed'
    if [ $? != 0 ]; then
        echo 'Failed to generate random positions in oryLat2'
        exit 1
    fi
fi
snakemake --cores "${CORES}" --snakefile=process_data.smk
if [ $? != 0 ]; then
    echo 'Failed snakemake!'
    exit 1
fi
if [ ! -e 'distinct_features.txt' ]; then
    cut -f1 -d, interspecies_info.csv | sort | uniq | tr -d '\"' | tail -n+2 >distinct_features.txt
    if [ $? != 0 ]; then
        echo 'Failed to create distinct features for oryLat2.'
        exit 1
    fi
fi
if [ ! -e 'data/sorted_data.all.bed.gz' ]; then
    cat 'distinct_features.txt' | \
    while read -r ACCESSION; do
        cat 'data/'"${ACCESSION}"'.cleaned.rg.reorder.dedup_peaks.narrowPeak' | \
            cut -f1,2,3 | \
            awk -v ACC="${ACCESSION}" '{ print $1 "\t" $2 "\t" $3 "\t" ACC }'
    done | sort -k1V -k2n -k3n >'data/sorted_data.all.bed'
    if [ $? != 0 ]; then
        echo 'Failed to create data.'
        exit 1
    fi
    bgzip 'data/sorted_data.all.bed'
    if [ $? != 0 ]; then
        echo 'Failed to compress sorted data'
        exit 1
    fi
fi
if [ ! -e 'data/sorted_data.all.bed.gz.tbi' ]; then
    tabix -p bed 'data/sorted_data.all.bed.gz'
    if [ $? != 0 ]; then
        echo 'Failed to index sorted data with tabix.'
        exit 1
    fi
fi
if [ ! -e 'outputs/oryLat2_prediction.labels.h5' ]; then
    python 'get_cross_species_labels.py' \
        --feature-file 'distinct_features.txt' \
        --interval-file 'data/sorted_data.all.bed.gz' \
        --query-file 'data/oryLat2_prediction.bed' \
        --output-file 'data/oryLat2_prediction.labels.h5'
    if [ $? != 0 ]; then
        echo 'Failed to generate labels for oryLat2'
        exit 1
    fi
fi
