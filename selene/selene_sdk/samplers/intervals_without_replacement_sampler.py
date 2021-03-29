"""
This module provides the RandomPositionsSampler class.

TODO: Currently, only works with sequences from `selene_sdk.sequences.Genome`.
We would like to generalize this to `selene_sdk.sequences.Sequence` if possible.
"""
from collections import namedtuple, defaultdict
import logging
import random
from time import time

import numpy as np

from .online_sampler import OnlineSampler
from ..utils import get_indices_and_probabilities

logger = logging.getLogger(__name__)


SampleIndices = namedtuple(
    "SampleIndices", ["indices", "weights"])
"""
A tuple containing the indices for some samples, and a weight to
allot to each index when randomly drawing from them.

TODO: this is common to both the intervals sampler and the
random positions sampler. Can we move this to utils or
somewhere else?

Parameters
----------
indices : list(int)
    The numeric index of each sample.
weights : list(float)
    The amount of weight assigned to each sample.

Attributes
----------
indices : list(int)
    The numeric index of each sample.
weights : list(float)
    The amount of weight assigned to each sample.

"""


class IntervalsWithoutReplacementSampler(OnlineSampler):
    """This sampler randomly selects a position in the genome and queries for
    a sequence centered at that position for input to the model. This sampler
    will draw samples without replacement.

    TODO: generalize to selene_sdk.sequences.Sequence?

    Parameters
    ----------
    reference_sequence : selene_sdk.sequences.Genome
        A reference sequence from which to create examples.
    target_path : str
        Path to tabix-indexed, compressed BED file (`*.bed.gz`) of genomic
        coordinates mapped to the genomic features we want to predict.
    features : list(str)
        List of distinct features that we aim to predict.
    seed : int, optional
        Default is 436. Sets the random seed for sampling.
    validation_holdout : list(str) or float, optional
        Default is `['chr6', 'chr7']`. Holdout can be regional or
        proportional. If regional, expects a list (e.g. `['chrX', 'chrY']`).
        Regions must match those specified in the first column of the
        tabix-indexed BED file. If proportional, specify a percentage
        between (0.0, 1.0). Typically 0.10 or 0.20.
    test_holdout : list(str) or float, optional
        Default is `['chr8', 'chr9']`. See documentation for
        `validation_holdout` for additional information.
    sequence_length : int, optional
        Default is 1000. Model is trained on sequences of `sequence_length`
        where genomic features are annotated to the center regions of
        these sequences.
    center_bin_to_predict : int, optional
        Default is 200. Query the tabix-indexed file for a region of
        length `center_bin_to_predict`.
    feature_thresholds : float [0.0, 1.0], optional
        Default is 0.5. The `feature_threshold` to pass to the
        `GenomicFeatures` object.
    mode : {'train', 'validate', 'test'}
        Default is `'train'`. The mode to run the sampler in.
    save_datasets : list(str), optional
        Default is `['test']`. The list of modes for which we should
        save the sampled data to file.
    output_dir : str or None, optional
        Default is None. The path to the directory where we should
        save sampled examples for a mode. If `save_datasets` is
        a non-empty list, `output_dir` must be specified. If
        the path in `output_dir` does not exist it will be created
        automatically.

    Attributes
    ----------
    reference_sequence : selene_sdk.sequences.Genome
        The reference sequence that examples are created from.
    target : selene_sdk.targets.Target
        The `selene_sdk.targets.Target` object holding the features that we
        would like to predict.
    validation_holdout : list(str) or float
        The samples to hold out for validating model performance. These
        can be "regional" or "proportional". If regional, this is a list
        of region names (e.g. `['chrX', 'chrY']`). These regions must
        match those specified in the first column of the tabix-indexed
        BED file. If proportional, this is the fraction of total samples
        that will be held out.
    test_holdout : list(str) or float
        The samples to hold out for testing model performance. See the
        documentation for `validation_holdout` for more details.
    sequence_length : int
        The length of the sequences to  train the model on.
    bin_radius : int
        From the center of the sequence, the radius in which to detect
        a feature annotation in order to include it as a sample's label.
    surrounding_sequence_radius : int
        The length of sequence falling outside of the feature detection
        bin (i.e. `bin_radius`) center, but still within the
        `sequence_length`.
    modes : list(str)
        The list of modes that the sampler can be run in.
    mode : str
        The current mode that the sampler is running in. Must be one of
        the modes listed in `modes`.

    """
    def __init__(self,
                 reference_sequence,
                 target_path,
                 features,
                 intervals_path,
                 seed=436,
                 validation_holdout=['chr6', 'chr7'],
                 test_holdout=['chr8', 'chr9'],
                 sequence_length=1000,
                 bin_size=200,
                 step_size=100,
                 bins_start=200,
                 bins_end=800,
                 feature_thresholds=0.5,
                 mode="train",
                 save_datasets=[],
                 output_dir=None):
        super(IntervalsWithoutReplacementSampler, self).__init__(
            reference_sequence,
            target_path,
            features,
            seed=seed,
            validation_holdout=validation_holdout,
            test_holdout=test_holdout,
            sequence_length=sequence_length,
            bin_size=bin_size,
            step_size=step_size,
            bins_start=bins_start,
            bins_end=bins_end,
            feature_thresholds=feature_thresholds,
            mode=mode,
            save_datasets=save_datasets,
            output_dir=output_dir)
        self.intervals_path = intervals_path

        self._sample_from_mode = {}
        self._randcache = {}
        self._seen = {}
        for mode in self.modes:
            self._sample_from_mode[mode] = None
            self._randcache[mode] = {"cache_indices": [], "sample_next": 0}
            self._seen[mode] = defaultdict(set)

        self.sample_from_intervals = []
        self.interval_lengths = []
        if self._holdout_type == "chromosome":
            self._partition_genome_by_chromosome()
        else:
            self._partition_genome_by_proportion()
        # for mode in self.modes:
        for mode in ["test"]:
            self._update_randcache(mode=mode)

    def _partition_genome_by_proportion(self):
        for chrom, len_chrom in self.reference_sequence.get_chr_lens():
            self.sample_from_intervals.append(
                (chrom,
                 self.sequence_length,
                 len_chrom - self.sequence_length))
            self.interval_lengths.append(len_chrom)
        n_intervals = len(self.sample_from_intervals)

        select_indices = list(range(n_intervals))
        np.random.shuffle(select_indices)
        n_indices_validate = int(n_intervals * self.validation_holdout)
        val_indices, val_weights = get_indices_and_probabilities(
            self.interval_lengths, select_indices[:n_indices_validate])
        self._sample_from_mode["validate"] = SampleIndices(
            val_indices, val_weights)

        if self.test_holdout:
            n_indices_test = int(n_intervals * self.test_holdout)
            test_indices_end = n_indices_test + n_indices_validate
            test_indices, test_weights = get_indices_and_probabilities(
                self.interval_lengths,
                select_indices[n_indices_validate:test_indices_end])
            self._sample_from_mode["test"] = SampleIndices(
                test_indices, test_weights)

            tr_indices, tr_weights = get_indices_and_probabilities(
                self.interval_lengths, select_indices[test_indices_end:])
            self._sample_from_mode["train"] = SampleIndices(
                tr_indices, tr_weights)
        else:
            tr_indices, tr_weights = get_indices_and_probabilities(
                self.interval_lengths, select_indices[n_indices_validate:])
            self._sample_from_mode["train"] = SampleIndices(
                tr_indices, tr_weights)

    def _partition_genome_by_chromosome(self):
        for mode in self.modes:
            self._sample_from_mode[mode] = SampleIndices([], [])
        chrom_lens = {k: v for k, v in self.reference_sequence.get_chr_lens()}
        index = 0
        with open(self.intervals_path, "r") as read_file:
            for line in read_file:
                chrom, start, end = line.rstrip().split("\t")[:3]
                if chrom not in chrom_lens:
                    continue
                start = int(start)
                end = int(end)
                start, end = min(start, end), max(start, end)
                lhs = max(self.sequence_length, start)
                rhs = min(end, chrom_lens[chrom] - self.sequence_length)
                if rhs - lhs <= 0:
                    continue

                # save the good data.
                if chrom in self.validation_holdout:
                    # self._sample_from_mode["validation"].indices.append(index)
                    continue
                elif self.test_holdout and chrom in self.test_holdout:
                    self._sample_from_mode["test"].indices.append(index)
                else:
                    continue
                    # self._sample_from_mode["train"].indices.append(index)
                self.sample_from_intervals.append((chrom, lhs, rhs))
                self.interval_lengths.append(rhs - lhs)
                index += 1

        for mode in self.modes:
            sample_indices = self._sample_from_mode[mode].indices
            indices, weights = get_indices_and_probabilities(
                self.interval_lengths, sample_indices)
            self._sample_from_mode[mode] = \
                self._sample_from_mode[mode]._replace(
                    indices=indices, weights=weights)

    def _retrieve(self, chrom, position):
        bin_start = position - self._start_radius
        bin_end = position + self._end_radius
        window_start = bin_start - self._start_surrounding_sequence_radius
        window_end = bin_end + self._end_surrounding_sequence_radius
        if window_end - window_start != self.sequence_length:
            print(bin_start, bin_end,
                  self._start_radius, self._end_radius,
                  self.surrounding_sequence_radius)
            return None
        strand = self.STRAND_SIDES[random.randint(0, 1)]
        retrieved_seq = \
            self.reference_sequence.get_encoding_from_coords(
                chrom, window_start, window_end, strand)
        if retrieved_seq.shape[0] == 0:
            logger.info("Full sequence centered at {0} position {1} "
                        "could not be retrieved. Sampling again.".format(
                            chrom, position))
            return None
        if retrieved_seq.shape[0] < self.sequence_length:
            # TODO: remove after investigating this bug.
            print("Warning: sequence retrieved for {0}, {1}, {2}, {3} "
                  "had length less than required sequence length {4}. "
                  "This bug will be investigated and addressed in the next "
                  "version of Selene.".format(
                      chrom, window_start, window_end, strand,
                      self.sequence_length))
            return None

        retrieved_targets = self.target.get_feature_data(
            chrom, bin_start, bin_end)
        if self.mode in self._save_datasets:
            feature_indices = ';'.join(
                [str(f) for f in np.nonzero(retrieved_targets)[0]])
            self._save_datasets[self.mode].append(
                [chrom,
                 window_start,
                 window_end,
                 strand,
                 feature_indices])
            if len(self._save_datasets[self.mode]) > 200000:
                self.save_dataset_to_file(self.mode)
        return (retrieved_seq, retrieved_targets)

    def _update_randcache(self, mode=None):
        if not mode:
            mode = self.mode
        self._randcache[mode]["cache_indices"] = np.random.choice(
            self._sample_from_mode[mode].indices,
            size=200000,
            replace=True,
            p=self._sample_from_mode[mode].weights)
        self._randcache[mode]["sample_next"] = 0

    def sample(self, batch_size=1):
        """
        Randomly draws a mini-batch of examples and their corresponding
        labels.

        Parameters
        ----------
        batch_size : int, optional
            Default is 1. The number of examples to include in the
            mini-batch.

        Returns
        -------
        sequences, targets : tuple(numpy.ndarray, numpy.ndarray)
            A tuple containing the numeric representation of the
            sequence examples and their corresponding labels. The
            shape of `sequences` will be
            :math:`B \\times L \\times N`, where :math:`B` is
            `batch_size`, :math:`L` is the sequence length, and
            :math:`N` is the size of the sequence type's alphabet.
            The shape of `targets` will be :math:`B \\times F`,
            where :math:`F` is the number of features.

        """
        sequences = None
        targets = None
        n_samples_drawn = 0
        while n_samples_drawn < batch_size:
            sample_index = self._randcache[self.mode]["sample_next"]
            if sample_index == len(self._randcache[self.mode]["cache_indices"]):
                self._update_randcache()
                sample_index = 0

            rand_interval_index = \
                self._randcache[self.mode]["cache_indices"][sample_index]
            self._randcache[self.mode]["sample_next"] += 1

            # Only draw examples that we have not seen before.
            # print("About to draw", flush=True)
            interval_info = self.sample_from_intervals[rand_interval_index]
            interval_length = self.interval_lengths[rand_interval_index]
            chrom = interval_info[0]
            cur_seen = set()
            while True:
                position = int(np.random.randint(interval_info[1], interval_info[2]))
                cur_seen.add(position)
                # print(interval_info, interval_length, flush=True)
                if position not in self._seen[self.mode][chrom]:
                    self._seen[self.mode][chrom].add(position)
                    break
                if len(cur_seen) == interval_length:
                    position = None
                    break
            if position is None:
                continue
            # print(chrom, position, len(self._seen[self.mode][chrom]), flush=True)

            retrieve_output = self._retrieve(chrom, position)
            if not retrieve_output:
                continue
            seq, seq_targets = retrieve_output
            if sequences is None and targets is None:
                sequences = np.zeros((batch_size, seq.shape[0], seq.shape[1]), dtype=float)
                targets = np.zeros((batch_size, self.n_features * self.n_bins), dtype=float)
            sequences[n_samples_drawn, :, :] = seq
            targets[n_samples_drawn, :] = seq_targets
            n_samples_drawn += 1
        return (sequences, targets)
