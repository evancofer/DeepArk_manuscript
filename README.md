# DeepArk Manuscript Code
![logo](deepark_logo.png)

---

## Contents
1. [What is DeepArk?](#what_is_deepark)
2. [What is this repository for?](#what_is_this)
3. [Setup and installation](#setup)
4. [Training new models](#train_models)
5. [Downloading weights without training new models](#download_weights)

## <a name="what_is_deepark"></a>What is DeepArk?
DeepArk is a set of models of the worm, fish, fly, and mouse regulatory codes.
For each of these organism, we constructed a deep convolutional neural network that predict regulatory activities (i.e. histone modifications, transcription factor binding, and chromatin state) directly from genomic sequences.
Besidese accurately predicting a sequence's regulatory activity, DeepArk can predict the effects of variants on regulatory function and profile sequences regulatory potential with _in silico_ saturated mutagenesis.

## <a name="what_is_this"></a>What is this repository for?
This is the public reposity for the analyses in the DeepArk publication in Genome Research.
If you are looking for the code to run DeepArk and perform new analyses, please use [the DeepArk GitHub repository](https://github.com/functionlab/deepark).
If you would like to use DeepArk without writing any code, please consider using the [free GPU-accelerated DeepArk web server](https://deepark.princeton.edu/).


## <a name="setup"></a>Setup and installation
If you are downloading this code from GitHub, please use the following command to ensure that the DeepArk submodule has been downloaded:

```
git clone --recursive https://github.com/evancofer/DeepArk_manuscript.git
cd DeepArk_manuscript
```

If you are downloading the code from the Genome Research page, please make sure to run the following command in the base directory (i.e. within the `DeepArk_manuscript` directory):

```
git clone https://github.com/FunctionLab/DeepArk.git
```

To run the analysis, you will need to use the Anaconda environment we provide.
Please ensure you have [Anaconda](https://www.anaconda.com/) installed, and then run the following command:

```
conda env create -f environment.yml
conda activate DeepArk_manuscript
```

Finally, you will need to download all data associated with the manuscript.
This can be accomplished with the following command:

```
./download_data.sh
```

## <a name="train_models"></a>Training new models

For example, to train a new model for mouse, you would run the following commands:

```
cd 'train'
./train.sh 'mus_musculus'
```


## <a name="download_weights"></a>Downloading weights without training new models

We provide scripts to reproduce the training process for the DeepArk models, but provide users with the weights from our models if they would like to skip the lengthy training process.
This is strongly recommended for users without access to GPUs, as training the models using only CPUs will take a very long time.
To download the weights, please run the following commands:

```
cd DeepArk
./download_weights.sh
```

