#!/usr/bin/env bash

source "${HOME}"'/.bashrc'

# Setup directories.
if [ ! -e 'outputs' ]; then
    mkdir 'outputs'
    if [ $? != 0 ]; then
        echo 'Failed to make directory for prediction outputs.'
        exit 1
    fi
fi

conda activate 'DeepArk_manuscript'
if [ $? != 0 ]; then
    echo 'Failed to activate conda environment.'
    exit 1
fi

python -u '../DeepArk/DeepArk.py' 'predict' \
    --checkpoint-file '../DeepArk/data/danio_rerio.pth.tar' \
    --input-file '../data/danRer10.pdia4.bed' \
    --genome-file '../data/danRer10.fa' \
    --output-dir 'outputs' \
    --output-format 'hdf5' \
    --batch-size '256'
if [ $? != 0 ]; then
    echo 'Failed to run selene command for danRer10 pdia4!'
    exit 1
fi

python -u '../DeepArk/DeepArk.py' 'predict' \
    --checkpoint-file '../DeepArk/data/danio_rerio.pth.tar' \
    --input-file '../data/oryLat2.pdia4.bed' \
    --genome-file '../data/oryLat2.fa' \
    --output-dir 'outputs' \
    --output-format 'hdf5' \
    --batch-size '256'
if [ $? != 0 ]; then
    echo 'Failed to run selene command for oryLat2 pdia4!'
    exit 1
fi

# Convert outputs.
declare -a ORGANISMS=('danRer10' 'oryLat2')
for ORGANISM in "${ORGANISMS[@]}"; do
    python 'extract_bw_from_h5.py' \
        --input-h5 'outputs/'"${ORGANISM}"'.pdia4_predictions.h5' \
        --input-bed '../data/'"${ORGANISM}"'.pdia4.bed' \
        --genome-file '../data/'"${ORGANISM}"'.fa' \
        --feature-file '../train/distinct_features.danio_rerio.txt' \
        --target-feature 'DCD000648SQ' \
        --output-file 'outputs/'"${ORGANISM}"'.DCD000648SQ.bw'
    if [ $? != 0 ]; then
        echo 'Failed to create bigWig for '"${ORGANISM}"
        exit 1
    fi
done
i
