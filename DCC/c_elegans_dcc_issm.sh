#!/usr/bin/env bash

source "${HOME}"'/.bashrc'

# Setup directories.
if [ ! -e 'outputs' ]; then
    mkdir 'outputs'
    if [ $? != 0 ]; then
        echo 'Failed to make directory for training outputs.'
        exit 1
    fi
fi

conda activate DeepArk_manuscript
if [ $? != 0 ]; then
    echo 'Failed to activate conda environment.'
    exit 1
fi

python -u '../DeepArk/DeepArk.py' 'issm' \
    --checkpoint-file '../DeepArk/data/caenorhabditis_elegans.pth.tar' \
    --input-file 'top_sites.fa' \
    --output-dir 'outputs' \
    --output-format 'hdf5' \
    --batch-size '256'
if [ $? != 0 ]; then
    echo 'Failed to run selene command!'
    exit 1
fi

