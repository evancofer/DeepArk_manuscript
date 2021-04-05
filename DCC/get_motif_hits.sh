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

fimo 'rex_motif.meme' 'top_sites.fa'
if [ $? != 0 ]; then
    echo 'Failed to run FIMO!'
    exit 1
fi

mv 'fimo_out' 'outputs/fimo_out'
if [ $? != 0 ]; then
    echo 'Failed to rename fimo output'
    exit 1
fi

