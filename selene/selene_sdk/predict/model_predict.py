"""
This module provides the `AnalyzeSequences` class and supporting
methods.
"""
import math
import os
import warnings

import numpy as np
import pyfaidx
import torch
import torch.nn as nn

from ._common import _pad_sequence
from ._common import _truncate_sequence
from ._common import predict
from ._in_silico_mutagenesis import _ism_sample_id
from ._in_silico_mutagenesis import in_silico_mutagenesis_sequences
from ._in_silico_mutagenesis import mutate_sequence
from ._variant_effect_prediction import _handle_long_ref
from ._variant_effect_prediction import _handle_standard_ref
from ._variant_effect_prediction import _handle_ref_alt_predictions
from ._variant_effect_prediction import _process_alts
from ._variant_effect_prediction import read_vcf_file
from .predict_handlers import AbsDiffScoreHandler
from .predict_handlers import DiffScoreHandler
from .predict_handlers import LogitScoreHandler
from .predict_handlers import WritePredictionsHandler
from .predict_handlers import WriteRefAltHandler
from ..sequences import Genome
from ..utils import load_model_from_state_dict


# TODO: MAKE THESE GENERIC:
ISM_COLS = ["pos", "ref", "alt"]
VARIANTEFFECT_COLS = ["chrom", "pos", "name", "ref", "alt"]


class AnalyzeSequences(object):
    """
    Score sequences and their variants using the predictions made
    by a trained model.

    Parameters
    ----------
    model : torch.nn.Module
        A sequence-based model architecture.
    trained_model_path : str
        The path to the weights file for a trained sequence-based model.
        Architecture must match `model`.
    sequence_length : int
        The length of sequences that the model is expecting.
    features : list(str)
        The names of the features that the model is predicting.
    batch_size : int, optional
        Default is 64. The size of the mini-batches to use.
    use_cuda : bool, optional
        Default is `False`. Specifies whether CUDA-enabled GPUs are available
        for torch to use.
    data_parallel : bool, optional
        Default is `False`. Specify whether multiple GPUs are available for
        torch to use during training.
    reference_sequence : class, optional
        Default is `selene_sdk.sequences.Genome`. The type of sequence on
        which this analysis will be performed. Please note that if you need
        to use variant effect prediction, you cannot only pass in the
        class--you must pass in the constructed `selene_sdk.sequences.Sequence`
        object with a particular sequence version (e.g. `Genome("hg19.fa")`).
        This version does NOT have to be the same sequence version that the
        model was trained on. That is, if the sequences in your variants file
        are hg19 but your model was trained on hg38 sequences, you should pass
        in hg19.
    write_mem_limit : int, optional
        Default is 5000. Specify, in MB, the amount of memory you want to
        allocate to storing model predictions/scores. When running one of
        _in silico_ mutagenesis, variant effect prediction, or prediction,
        prediction/score handlers will accumulate data in memory and only
        write this data to files periodically. By default, Selene will write
        to files when the total amount of data (across all handlers) takes up
        5000MB of space. Please keep in mind that Selene will not monitor the
        memory needed to actually carry out the operations (e.g. variant effect
        prediction) or load the model, so `write_mem_limit` should always be
        less than the total amount of CPU memory you have available on your
        machine. For example, for variant effect prediction, we load all
        the variants in 1 file into memory before getting the predictions, so
        your machine must have enough memory to accommodate that. Another
        possible consideration is your model size and whether you are
        using it on the CPU or a CUDA-enabled GPU (i.e. setting
        `use_cuda` to True).

    Attributes
    ----------
    model : torch.nn.Module
        A sequence-based model that has already been trained.
    sequence_length : int
        The length of sequences that the model is expecting.
    batch_size : int
        The size of the mini-batches to use.
    features : list(str)
        The names of the features that the model is predicting.
    use_cuda : bool
        Specifies whether to use a CUDA-enabled GPU or not.
    data_parallel : bool
        Whether to use multiple GPUs or not.
    reference_sequence : class
        The type of sequence on which this analysis will be performed.

    """

    def __init__(self,
                 model,
                 trained_model_path,
                 sequence_length,
                 features,
                 batch_size=64,
                 use_cuda=False,
                 data_parallel=False,
                 reference_sequence=Genome,
                 write_mem_limit=1500):
        """
        Constructs a new `AnalyzeSequences` object.
        """
        trained_model = torch.load(
            trained_model_path,
            map_location=lambda storage, location: storage)

        if "state_dict" not in trained_model:
            self.model = load_model_from_state_dict(
                trained_model, model)
        else:
            self.model = load_model_from_state_dict(
                trained_model["state_dict"], model)
        self.model.eval()

        self.data_parallel = data_parallel
        if self.data_parallel:
            self.model = nn.DataParallel(model)

        self.use_cuda = use_cuda
        if self.use_cuda:
            self.model.cuda()

        self.sequence_length = sequence_length

        self._start_radius = int(sequence_length / 2)
        self._end_radius = self._start_radius
        if sequence_length % 2 != 0:
            self._end_radius += 1

        self.batch_size = batch_size
        self.features = features
        self.reference_sequence = reference_sequence

        self._write_mem_limit = write_mem_limit

    def _initialize_reporters(self,
                              save_data,
                              output_path_prefix,
                              output_format,
                              colnames_for_ids,
                              mode="ism"):
        """
        Initialize the handlers to which Selene reports model predictions

        Parameters
        ----------
        save_data : list(str)
            A list of the data files to output. Must input 1 or more of the
            following options: ["abs_diffs", "diffs", "logits", "predictions"].
        output_path_prefix : str
            Path to which the reporters will output data files. Selene will
            add a prefix to the resulting filename, where the prefix is based
            on the name of the user-specified input file. This allows a user
            to distinguish between output files from different inputs when
            a user specifies the same output directory for multiple inputs.
        output_format : {'tsv', 'hdf5'}
            The desired output format. Currently Selene supports TSV and HDF5
            formats.
        colnames_for_ids : list(str)
            Specify the names of columns that will be used to identify the
            sequence for which Selene has made predictions (e.g. (chrom,
            pos, id, ref, alt) will be the column names for variant effect
            prediction outputs).
        mode : {'prediction', 'ism', 'varianteffect'}
            If saving model predictions, the handler Selene chooses for the
            task is dependent on the mode. For example, the reporter for
            variant effect prediction writes paired ref and alt predictions
            to different files.

        Returns
        -------
        list(selene_sdk.predict.predict_handlers.PredictionsHandler)
            List of reporters to update as Selene receives model predictions.

        """
        save_data = set(save_data) & set(
            ["diffs", "abs_diffs", "logits", "predictions"])
        if len(save_data) == 0:
            raise ValueError("'save_data' parameter must be a list that "
                             "contains one of ['diffs', 'abs_diffs', "
                             "'logits', 'predictions'].")
        reporters = []
        constructor_args = [self.features,
                            colnames_for_ids,
                            output_path_prefix,
                            output_format,
                            self._write_mem_limit // len(save_data)]
        if "diffs" in save_data:
            reporters.append(DiffScoreHandler(*constructor_args))
        if "abs_diffs" in save_data:
            reporters.append(AbsDiffScoreHandler(*constructor_args))
        if "logits" in save_data:
            reporters.append(LogitScoreHandler(*constructor_args))
        if "predictions" in save_data and mode != "varianteffect":
            reporters.append(WritePredictionsHandler(*constructor_args))
        elif "predictions" in save_data and mode == "varianteffect":
            reporters.append(WriteRefAltHandler(*constructor_args))
        return reporters

    def get_predictions_for_fasta_file(self,
                                       input_path,
                                       output_dir,
                                       output_format="tsv"):
        """
        Get model predictions for sequences in a FASTA file.

        Parameters
        ----------
        input_path : str
            Input path to the FASTA file.
        output_dir : str
            Output directory to write the model predictions.
        output_format : {'tsv', 'hdf5'}, optional
            Default is 'tsv'. Choose whether to save TSV or HDF5 output files.
            TSV is easier to access (i.e. open with text editor/Excel) and
            quickly peruse, whereas HDF5 files must be accessed through
            specific packages/viewers that support this format (e.g. h5py
            Python package). Choose

                * 'tsv' if your list of sequences is relatively small
                  (:math:`10^4` or less in order of magnitude) and/or your
                  model has a small number of features (<1000).
                * 'hdf5' for anything larger and/or if you would like to
                  access the predictions/scores as a matrix that you can
                  easily filter, apply computations, or use in a subsequent
                  classifier/model. In this case, you may access the matrix
                  using `mat["data"]` after opening the HDF5 file using
                  `mat = h5py.File("<output.h5>", 'r')`. The matrix columns
                  are the features and will match the same ordering as your
                  features .txt file (same as the order your model outputs
                  its predictions) and the matrix rows are the sequences.
                  Note that the row labels (FASTA description/IDs) will be
                  output as a separate .txt file (should match the ordering
                  of the sequences in the input FASTA).

        Returns
        -------
        None
            Writes the output to file(s) in `output_dir`.

        """
        os.makedirs(output_dir, exist_ok=True)

        _, filename = os.path.split(input_path)
        output_prefix = '.'.join(filename.split('.')[:-1])

        reporter = self._initialize_reporters(
            ["predictions"],
            os.path.join(output_dir, output_prefix),
            output_format,
            ["index", "name"],
            mode="prediction")[0]
        fasta_file = pyfaidx.Fasta(input_path)
        sequences = np.zeros((self.batch_size,
                              self.sequence_length,
                              len(self.reference_sequence.BASES_ARR)))
        batch_ids = []
        for i, fasta_record in enumerate(fasta_file):
            cur_sequence = str(fasta_record)

            if len(cur_sequence) < self.sequence_length:
                cur_sequence = _pad_sequence(cur_sequence,
                                             self.sequence_length,
                                             self.reference_sequence.UNK_BASE)
            elif len(cur_sequence) > self.sequence_length:
                cur_sequence = _truncate_sequence(cur_sequence, self._sequence_length)

            cur_sequence_encoding = self.reference_sequence.sequence_to_encoding(
                cur_sequence)
            batch_ids.append([i, fasta_record.name])

            if i and i % self.batch_size == 0:
                preds = predict(self.model, sequences, use_cuda=self.use_cuda)
                sequences = np.zeros((
                    self.batch_size, *cur_sequence_encoding.shape))
                reporter.handle_batch_predictions(preds, batch_ids)

            sequences[i % self.batch_size, :, :] = cur_sequence_encoding

        if i % self.batch_size != 0:
            sequences = sequences[:i % self.batch_size + 1, :, :]
            preds = predict(self.model, sequences, use_cuda=self.use_cuda)
            reporter.handle_batch_predictions(preds, batch_ids)

        fasta_file.close()
        reporter.write_to_file(close=True)


    def in_silico_mutagenesis_predict(self,
                                      sequence,
                                      base_preds,
                                      mutations_list,
                                      reporters=[]):
        """
        Get the predictions for all specified mutations applied
        to a given sequence and, if applicable, compute the scores
        ("abs_diffs", "diffs", "logits") for these mutations.

        Parameters
        ----------
        sequence : str
            The sequence to mutate.
        base_preds : numpy.ndarray
            The model's prediction for `sequence`.
        mutations_list : list(list(tuple))
            The mutations to apply to the sequence. Each element in
            `mutations_list` is a list of tuples, where each tuple
            specifies the `int` position in the sequence to mutate and what
            `str` base to which the position is mutated (e.g. (1, 'A')).
        reporters : list(PredictionsHandler)
            The list of reporters, where each reporter handles the predictions
            made for each mutated sequence. Will collect, compute scores
            (e.g. `AbsDiffScoreHandler` computes the absolute difference
            between `base_preds` and the predictions for the mutated
            sequence), and output these as a file at the end.

        Returns
        -------
        None
            Writes results to files corresponding to each reporter in
            `reporters`.

        """
        current_sequence_encoding = self.reference_sequence.sequence_to_encoding(
            sequence)
        for i in range(0, len(mutations_list), self.batch_size):
            start = i
            end = min(i + self.batch_size, len(mutations_list))

            mutated_sequences = np.zeros(
                (end - start, *current_sequence_encoding.shape))

            batch_ids = []
            for ix, mutation_info in enumerate(mutations_list[start:end]):
                mutated_seq = mutate_sequence(
                    current_sequence_encoding, mutation_info,
                    reference_sequence=self.reference_sequence)
                mutated_sequences[ix, :, :] = mutated_seq
                batch_ids.append(_ism_sample_id(sequence, mutation_info))
            outputs = predict(
                self.model, mutated_sequences, use_cuda=self.use_cuda)

            for r in reporters:
                if r.needs_base_pred:
                    r.handle_batch_predictions(outputs, batch_ids, base_preds)
                else:
                    r.handle_batch_predictions(outputs, batch_ids)

        for r in reporters:
            r.write_to_file(close=True)

    def in_silico_mutagenesis(self,
                              sequence,
                              save_data,
                              output_path_prefix="ism",
                              mutate_n_bases=1):
        """
        Applies *in silico* mutagenesis to a sequence.

        Parameters
        ----------
        sequence : str
            The sequence to mutate.
        save_data : list(str)
            A list of the data files to output. Must input 1 or more of the
            following options: ["abs_diffs", "diffs", "logits", "predictions"].
        output_path_prefix : str, optional
            The path to which the data files are written. If directories in
            the path do not yet exist they will be automatically created.
        mutate_n_bases : int, optional
            The number of bases to mutate at one time. We recommend leaving
            this parameter set to `1` at this time, as we have not yet
            optimized operations for double and triple mutations.

        Returns
        -------
        None
            Writes results to files corresponding to each reporter in
            `reporters`.

        """
        path_dirs, _ = os.path.split(output_path_prefix)
        os.makedirs(path_dirs, exist_ok=True)

        n = len(sequence)
        if n < self.sequence_length: # Pad string length as necessary.
             diff = (self.sequence_length - n) / 2
             pad_l = int(np.floor(diff))
             pad_r = math.ceil(diff)
             sequence = ((self.reference_sequence.UNK_BASE * pad_l) +
                         sequence +
                         (self.reference_sequence.UNK_BASE * pad_r))
        elif n > self.sequence_length:  # Extract center substring of proper length.
            start = int((n - self.sequence_length) // 2)
            end = int(start + self.sequence_length)
            sequence = sequence[start:end]

        sequence = str.upper(sequence)
        mutated_sequences = in_silico_mutagenesis_sequences(
            sequence, mutate_n_bases=1,
            reference_sequence=self.reference_sequence)

        reporters = self._initialize_reporters(
            save_data, output_path_prefix, "tsv", ISM_COLS)

        current_sequence_encoding = self.reference_sequence.sequence_to_encoding(
            sequence)

        base_encoding = current_sequence_encoding.reshape(
            (1, *current_sequence_encoding.shape))
        base_preds = predict(self.model, base_encoding, use_cuda=self.use_cuda)

        if "predictions" in save_data:
            predictions_reporter = reporters[-1]
            predictions_reporter.handle_batch_predictions(
                base_preds, [["NA", "NA", "NA"]])

        self.in_silico_mutagenesis_predict(
            sequence, base_preds, mutated_sequences, reporters=reporters)

    def in_silico_mutagenesis_from_file(self,
                                        input_path,
                                        save_data,
                                        output_dir,
                                        mutate_n_bases=1,
                                        use_sequence_name=True):
        """
        Apply *in silico* mutagenesis to all sequences in a FASTA file.

        Please note that we have not parallelized this function yet, so runtime
        increases exponentially when you increase `mutate_n_bases`.

        Parameters
        ----------
        input_path: str
            The path to the FASTA file of sequences.
        save_data : list(str)
            A list of the data files to output. Must input 1 or more of the
            following options: ["abs_diffs", "diffs", "logits", "predictions"].
        output_dir : str
            The path to the output directory. Directories in the path will be
            created if they do not currently exist.
        mutate_n_bases : int, optional
            Default is 1. The number of bases to mutate at one time in
            *in silico* mutagenesis.
        use_sequence_name : bool, optional.
            Default is True. If `use_sequence_name`, output files are prefixed
            by the sequence name/description corresponding to each sequence
            in the FASTA file. Spaces in the sequence name are replaced with
            underscores '_'. If not `use_sequence_name`, output files are
            prefixed with an index :math:`i` (starting with 0) corresponding
            to the :math:`i`th sequence in the FASTA file.

        Returns
        -------
        None
            Outputs data files from *in silico* mutagenesis to `output_dir`.

        """
        os.makedirs(output_dir, exist_ok=True)

        fasta_file = pyfaidx.Fasta(input_path)
        for i, fasta_record in enumerate(fasta_file):
            cur_sequence = str.upper(str(fasta_record))
            if len(cur_sequence) < self.sequence_length:
                cur_sequence = _pad_sequence(cur_sequence,
                                             self.sequence_length,
                                             self.reference_sequence.UNK_BASE)
            elif len(cur_sequence) > self.sequence_length:
                cur_sequence = _truncate_sequence(
                    cur_sequence, self.sequence_length)

            # Generate mut sequences and base preds.
            mutated_sequences = in_silico_mutagenesis_sequences(
                cur_sequence, mutate_n_bases=mutate_n_bases,
                reference_sequence=self.reference_sequence)
            cur_sequence_encoding = self.reference_sequence.sequence_to_encoding(
                cur_sequence)
            base_encoding = cur_sequence_encoding.reshape(
                1, *cur_sequence_encoding.shape)
            base_preds = predict(
                self.model, base_encoding, use_cuda=self.use_cuda)

            file_prefix = None
            if use_sequence_name:
                file_prefix = os.path.join(
                    output_dir, fasta_record.name.replace(' ', '_'))
            else:
                file_prefix = os.path.join(
                    output_dir, str(i))
            # Write base to file, and make mut preds.
            reporters = self._initialize_reporters(
                save_data, file_prefix, "tsv", ISM_COLS)

            if "predictions" in save_data:
                predictions_reporter = reporters[-1]
                predictions_reporter.handle_batch_predictions(
                    base_preds, [["NA", "NA", "NA"]])

            self.in_silico_mutagenesis_predict(
                cur_sequence, base_preds, mutated_sequences,
                reporters=reporters)
        fasta_file.close()

    def variant_effect_prediction(self,
                                  vcf_file,
                                  save_data,
                                  output_dir=None,
                                  output_format="tsv",
                                  strand_index=None):
        """
        Get model predictions and scores for a list of variants.

        Parameters
        ----------
        vcf_file : str
            Path to a VCF file. Must contain the columns
            [#CHROM, POS, ID, REF, ALT], in order. Column header does not need
            to be present.
        save_data : list(str)
            A list of the data files to output. Must input 1 or more of the
            following options: ["abs_diffs", "diffs", "logits", "predictions"].
        output_dir : str or None, optional
            Default is None. Path to the output directory. If no path is
            specified, will save files corresponding to the options in
            `save_data` to the current working directory.
        output_format : {'tsv', 'hdf5'}, optional
            Default is 'tsv'. Choose whether to save TSV or HDF5 output files.
            TSV is easier to access (i.e. open with text editor/Excel) and
            quickly peruse, whereas HDF5 files must be accessed through
            specific packages/viewers that support this format (e.g. h5py
            Python package). Choose

                * 'tsv' if your list of variants is relatively small
                  (:math:`10^4` or less in order of magnitude) and/or your
                  model has a small number of features (<1000).
                * 'hdf5' for anything larger and/or if you would like to
                  access the predictions/scores as a matrix that you can
                  easily filter, apply computations, or use in a subsequent
                  classifier/model. In this case, you may access the matrix
                  using `mat["data"]` after opening the HDF5 file using
                  `mat = h5py.File("<output.h5>", 'r')`. The matrix columns
                  are the features and will match the same ordering as your
                  features .txt file (same as the order your model outputs
                  its predictions) and the matrix rows are the sequences.
                  Note that the row labels (chrom, pos, id, ref, alt) will be
                  output as a separate .txt file.
        strand_index : int or None, optional.
            Default is None. If applicable, specify the column index (0-based)
            in the VCF file that contains strand information for each variant.

        Returns
        -------
        None
            Saves all files to `output_dir`. If any bases in the 'ref' column
            of the VCF do not match those at the specified position in the
            reference genome, the scores/predictions will be output to a
            file prefixed with `warning.`. If most of your variants show up
            in these warning files, please check that the reference genome
            you specified matches the one from which the VCF was created.
            The warning files can be used directly if you have verified that
            the 'ref' bases specified for these variants are correct (Selene
            will have substituted these bases for those in the reference
            genome). Finally, some variants may show up in an 'NA' file.
            This is because the surrounding sequence context ended up
            being out of bounds or the chromosome containing the variant
            did not show up in the reference genome FASTA file.

        """
        variants = read_vcf_file(vcf_file, strand_index=strand_index)

        # TODO: GIVE USER MORE CONTROL OVER PREFIX.
        path, filename = os.path.split(vcf_file)
        output_path_prefix = '.'.join(filename.split('.')[:-1])
        if output_dir:
            os.makedirs(output_dir, exist_ok=True)
        else:
            output_dir = path
        output_path_prefix = os.path.join(output_dir, output_path_prefix)
        reporters = self._initialize_reporters(
            save_data,
            output_path_prefix,
            output_format,
            VARIANTEFFECT_COLS,
            mode="varianteffect")

        batch_ref_seqs = []
        batch_alt_seqs = []
        batch_ids = []
        for (chrom, pos, name, ref, alt, strand) in variants:
            # centers the sequence containing the ref allele based on the size
            # of ref
            center = pos + len(ref) // 2
            start = center - self._start_radius
            end = center + self._end_radius

            if isinstance(self.reference_sequence, Genome):
                if "chr" not in chrom:
                    chrom = "chr" + chrom
                if "MT" in chrom:
                    chrom = chrom[:-1]

            if not self.reference_sequence.coords_in_bounds(chrom, start, end):
                for r in reporters:
                    r.handle_NA((chrom, pos, name, ref, alt, strand))
                continue

            seq_encoding = self.reference_sequence.get_encoding_from_coords(
                chrom, start, end, strand=strand)
            ref_encoding = self.reference_sequence.sequence_to_encoding(ref)
            all_alts = alt.split(',')
            alt_encodings = _process_alts(
                all_alts,
                ref,
                chrom,
                pos,
                center,
                strand,
                self._start_radius,
                self._end_radius,
                self.reference_sequence)

            match = True
            seq_at_ref = None
            if len(ref) < self.sequence_length:
                match, seq_encoding, seq_at_ref = _handle_standard_ref(
                    ref_encoding,
                    seq_encoding,
                    self._start_radius,
                    self.reference_sequence)
            else:
                match, seq_encoding, seq_at_ref = _handle_long_ref(
                    ref_encoding,
                    seq_encoding,
                    self._start_radius,
                    self._end_radius,
                    self.reference_sequence)
            if not match:
                warnings.warn("For variant ({0}, {1}, {2}, {3}, {4}), "
                              "reference does not match the reference genome. "
                              "Reference genome contains {5} instead. "
                              "Predictions/scores associated with this "
                              "variant--where we use '{3}' in the input "
                              "sequence--will be written to files where the "
                              "filename is prefixed by 'warning.'".format(
                                  chrom, pos, name, ref, alt, seq_at_ref))
                warn_batch_ids = [(chrom, pos, name, ref, a) for a in all_alts]
                warn_ref_seqs = [seq_encoding] * len(all_alts)
                _handle_ref_alt_predictions(
                    self.model,
                    warn_ref_seqs,
                    alt_encodings,
                    warn_batch_ids,
                    reporters,
                    warn=True,
                    use_cuda=self.use_cuda)
                continue

            batch_ids += [(chrom, pos, name, ref, a) for a in all_alts]
            batch_ref_seqs += [seq_encoding] * len(all_alts)
            batch_alt_seqs += alt_encodings

            if len(batch_ref_seqs) >= self.batch_size:
                _handle_ref_alt_predictions(
                    self.model,
                    batch_ref_seqs,
                    batch_alt_seqs,
                    batch_ids,
                    reporters,
                    warn=False,
                    use_cuda=self.use_cuda)
                batch_ref_seqs = []
                batch_alt_seqs = []
                batch_ids = []

        if batch_ref_seqs:
            _handle_ref_alt_predictions(
                self.model,
                batch_ref_seqs,
                batch_alt_seqs,
                batch_ids,
                reporters,
                warn=False,
                use_cuda=self.use_cuda)

        for r in reporters:
            r.write_to_file(close=True)
