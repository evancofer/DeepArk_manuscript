#!/usr/bin/env bash

# Args.
SPECIES="${1}"

# Setup directories.
if [ ! -e 'outputs' ]; then
    mkdir 'outputs'
    if [ $? != 0 ]; then
        echo 'Failed to make directory for training outputs.'
        exit 1
    fi
fi

# Get initial learning rate for species.
case "${SPECIES}" in
    'caenorhabditis_elegans')
        LR='0.1'
    ;;
    'drosophila_melanogaster')
        LR='0.1'
    ;;
    'mus_musculus')
        LR='0.3'
    ;;
    'danio_rerio')
        LR='0.1'
    ;;
    *)
        echo 'Unknown species='"${SPECIES}"
        exit 1
    ;;
esac


# Check for species-specific output directories.
if [ ! -e 'outputs/'"${SPECIES}" ]; then
    mkdir 'outputs/'"${SPECIES}"
    if [ $? != 0 ]; then
        echo 'Failed to make output directory for species='"${SPECIES}"
        exit 1
    fi
fi

conda activate DeepArk_manuscript
if [ $? != 0 ]; then
    echo 'Failed to activate conda environment.'
    exit 1
fi

python -u '../selene/selene_cli.py' 'train.'"${SPECIES}"'.yml' --lr="${LR}"
if [ $? != 0 ]; then
    echo 'Failed to run selene command!'
    exit 1
fi

