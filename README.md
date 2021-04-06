# DeepArk Manuscript Code
![logo](deepark_logo.png)

---

## Contents
1. [What is DeepArk?](#what_is_deepark)
2. [What is this repository for?](#what_is_this)
3. [Setup and installation](#setup)
4. [Generating figures from the manuscript](#figures)
5. [Why do the figure notebooks use data from the manuscript and Zenodo?](#why_data)
6. [Training new models](#train_models)
7. [Testing models](#test_models)
8. [Downloading weights without training new models](#download_weights)
9. [Reproducing the MPRA _in silico_ saturated mutagenesis predictions](#mpra)
10. [Reproducing the variant effect predictions for the _T48_ enhancer alleles](#t48)
11. [Reproducing the DCC analysis](#dcc)


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

The training portion of the manuscript (as well as some data generation steps) uses a different version of Selene than the rest of the manuscript.
This is because it uses some additional functionality that was never fully released with Selene.
This version of Selene has been packaged with this repository for reproducibility purposes.
However, we do not recommend using this version of Selene for anything other than training models.
To create the training environment, please run the following commands:

```
conda env create -f train_environment.yml
conda activate DeepArk_manuscript_train
cd selene
python setup.py build_ext --inplace
pip install -e .
```

Finally, you will need to download all data associated with the manuscript.
This can be accomplished with the following command:

```
./download_data.sh
```


## <a name="figures"></a>Generating manuscript figures
We have provided [Jupyter Notebooks](https://github.com/jupyter/notebook) for reproducing the figures from the manuscript.
We have placed these in the `figures` directory.
The code for the supplemental figures are in the `supplemental_figures` directory.


## <a href="why_data"></a>Why do the figure notebooks use data from the manuscript and Zenodo?
By default, the figure notebooks are written to use the data from the manuscript (i.e. from Genome Research and the associated Zenodo archives).
This is to make the figures easily reproducible.
However, we provide comments and clear instructions on how to modify these notebooks to instead use data output from a user-run step (e.g. reproducing the predictions for the T48 enhancer variants on their own GPU-accelerated machines).
However, each of these intermediate data-generation steps requires many hours and access to GPU computing resources.
By providing an alternative means of accessing the data (i.e. not repeating the predictions themselves etc.), we ensure that users can explore the manuscript's associated data without having to spend hundreds of hours of GPU compute time.


## <a name="train_models"></a>Training new models

Training a new model simply requires the use of the `train.sh` script in the `train` directory.
The only argument that this script requires is the species you would like to train a new model for.
The `train.sh` script should be run only within the `train` directory, or it will not function properly.
For example, to train a new model for mouse, you would run the following commands:

```
cd 'train'
./train.sh 'mus_musculus'
```


## <a name="test_models"></a>Testing models
To test models, simply run the following script:

```
cd 'train'
./evaluate.sh 'mus_musculus'
```

Note that this will only use the pre-trained models we provide.
If you want to test models using a different set of weights (e.g. the ones you learned during training), you need to change the configuration YML.
In the above case (i.e. for mouse), you would change the `checkpoint_resume` value in `train/evaluate.mus_musculus.yml` to point to the weights you learned.


## <a name="download_weights"></a>Downloading weights without training new models

We provide scripts to reproduce the training process for the DeepArk models, but provide users with the weights from our models if they would like to skip the lengthy training process.
This is strongly recommended for users without access to GPUs, as training the models using only CPUs will take a very long time.
To download the weights, please run the following commands:

```
cd DeepArk
./download_weights.sh
```


## <a name="mpra"></a>Reproducing the MPRA _in silico_ saturated mutagenesis predictions
To reproduce the _in silico_ saturated mutagenesis predictions for the MPRA experiment, simply run the following commands after downloading the manuscript data:

```
cd 'mpra'
./aldob_mpra_issm.sh
```

You can then use these results in notebook for Figure 2 or compare them with the predictions provided with the manuscript.


## <a name="t48"></a>Reproducing the variant effect predictions for the _T48_ enhancer alleles
To reproduce the variant effect predictions for the _T48_ enhancer alleles, simply run the following commands after downloading the manuscript data:

```
cd T48
./T48_enhancer_vep.sh
```

You can then use these results in the notebook for Figure 3 or compare them with the predictions provided with the manuscript.

## <a name="dcc"></a>Reproducing the DCC analysis
To reproduce the chromosome-wide prediction of DCC localization for the _C. elegans_ X Chromosome, run the following commands after downloading the manuscript data:

```
cd DCC
./c_elegans_chrX_prediction.sh'
```

To reproduce the predictions for the _in silico_ saturated mutagenesis of the top predicted DCC sites, rnu the following:

```
cd DCC
./c_elegans_dcc_issm.sh
```

Finally, to determine the _rex_ sites in the top predicted DCC sites, you will need to run the following:

```
cd DCC
./get_motif_hits.sh
```


##
