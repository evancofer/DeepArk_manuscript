"""
This module provides the EvaluateModel class.
"""
import logging
import os

import numpy as np
import torch
import torch.nn as nn
from torch.autograd import Variable

from .utils import initialize_logger
from .utils import load_model_from_state_dict
from .utils import PerformanceMetrics


logger = logging.getLogger("selene")


class EvaluateModel(object):
    """
    Evaluate model on a test set of sequences with known targets.

    Parameters
    ----------
    model : torch.nn.Module
        The model architecture.
    criterion : torch.nn._Loss
        The loss function that was optimized during training.
    data_sampler : selene_sdk.samplers.Sampler
        Used to retrieve samples from the test set for evaluation.
    features : list(str)
        List of distinct features the model predicts.
    trained_model_path : str
        Path to the trained model file, saved using `torch.save`.
    output_dir : str
        The output directory in which to save model evaluation and logs.
    batch_size : int, optional
        Default is 64. Specify the batch size to process examples.
        Should be a power of 2.
    n_test_samples : int or None, optional
        Default is `None`. Use `n_test_samples` if you want to limit the
        number of samples on which you evaluate your model. If you are
        using a sampler of type `selene_sdk.samplers.OnlineSampler`,
        by default it will draw 640000 samples if `n_test_samples` is `None`.
    report_gt_feature_n_positives : int, optional
        Default is 10. In the final test set, each class/feature must have
        more than `report_gt_feature_n_positives` positive samples in order to
        be considered in the test performance computation. The output file that
        states each class' performance will report 'NA' for classes that do
        not have enough positive samples.
    use_cuda : bool, optional
        Default is `False`. Specify whether a CUDA-enabled GPU is available
        for torch to use during training.
    data_parallel : bool, optional
        Default is `False`. Specify whether multiple GPUs are available
        for torch to use during training.

    Attributes
    ----------
    model : torch.nn.Module
        The trained model.
    criterion : torch.nn._Loss
        The model was trained using this loss function.
    sampler : selene_sdk.samplers.Sampler
        The example generator.
    features : list(str)
        List of distinct features the model predicts.
    batch_size : int
        The batch size to process examples. Should be a power of 2.
    use_cuda : bool
        If `True`, use a CUDA-enabled GPU. If `False`, use the CPU.
    data_parallel : bool
        Whether to use multiple GPUs or not.

    """

    def __init__(self,
                 model,
                 criterion,
                 data_sampler,
                 features,
                 trained_model_path,
                 output_dir,
                 batch_size=64,
                 n_test_samples=None,
                 report_gt_feature_n_positives=10,
                 use_cuda=False,
                 data_parallel=False,
                 use_features=None):
        self.criterion = criterion

        trained_model = torch.load(
            trained_model_path, map_location=lambda storage, location: storage)
        self.model = load_model_from_state_dict(
            trained_model["state_dict"], model)
        self.model.eval()

        self.sampler = data_sampler

        self.features = features
        self._use_ixs = list(range(len(features)))
        self._use_features = features
        if use_features:
            feature_ixs = {f: ix for (ix, f) in enumerate(features)}
            self._use_ixs = []
            self._use_features = use_features
            for f in use_features:
                self._use_ixs.append(feature_ixs[f])
            assert len(self._use_ixs) > 0

        self.output_dir = output_dir
        os.makedirs(output_dir, exist_ok=True)

        initialize_logger(
            os.path.join(self.output_dir, "{0}.log".format(
                __name__)),
            verbosity=2)

        self.data_parallel = data_parallel
        if self.data_parallel:
            self.model = nn.DataParallel(model)
            logger.debug("Wrapped model in DataParallel")

        self.use_cuda = use_cuda
        if self.use_cuda:
            self.model.cuda()

        self.batch_size = batch_size

        self._metrics = PerformanceMetrics(
            self._get_feature_from_index,
            report_gt_feature_n_positives=report_gt_feature_n_positives)

        self._test_data, self._test_targets = \
            self.sampler.get_data_and_targets(self.batch_size, n_test_samples)

    def _get_feature_from_index(self, index):
        """
        Gets the feature at an index in the features list.

        Parameters
        ----------
        index : int

        Returns
        -------
        str
            The name of the feature/target at the specified index.

        """
        return self._use_features[index]

    def evaluate(self):
        """
        Passes all samples retrieved from the sampler to the model in
        batches and returns the predictions. Also reports the model's
        performance on these examples.

        Returns
        -------
        dict
            A dictionary, where keys are the features and the values are
            each a dict of the performance metrics (currently ROC AUC and
            AUPR) reported for each feature the model predicts.

        """
        batch_losses = []

        if self._test_targets.shape[1] > len(self._use_ixs):
            self._test_targets = self._test_targets[:, self._use_ixs]
        all_predictions = np.zeros((self._test_targets.shape[0], self._test_targets.shape[1]))

        count = 0
        while count < self._test_targets.shape[0]:
            remainder = min(self._test_targets.shape[0] - count, self.batch_size)
            inputs = self._test_data[count:count + remainder, :, :].astype(float)
            targets = self._test_targets[count:count + remainder, :].astype(float)
            inputs = torch.Tensor(inputs)
            targets = torch.Tensor(targets)

            if self.use_cuda:
                inputs = inputs.cuda()
                targets = targets.cuda()

            with torch.no_grad():
                inputs = Variable(inputs)
                targets = Variable(targets)
                predictions = self.model(
                    inputs.transpose(1, 2))
                loss = self.criterion(predictions[:, self._use_ixs], targets)

                all_predictions[count:count + remainder, :] = \
                    predictions.data.cpu().numpy()[:, self._use_ixs]

                batch_losses.append(loss.item())
            count += remainder

            del inputs
            del targets
            del predictions
            del loss
            torch.cuda.empty_cache()

        average_scores = self._metrics.update(
            all_predictions, self._test_targets)

        self._metrics.visualize(
            all_predictions, self._test_targets, self.output_dir)

        #del self._test_targets

        loss = np.average(batch_losses)
        logger.info("test loss: {0}".format(loss))
        for name, score in average_scores.items():
            logger.info("test {0}: {1}".format(name, score))

        test_performance = os.path.join(
            self.output_dir, "test_performance.txt")
        feature_scores_dict = self._metrics.write_feature_scores_to_file(
            test_performance)

        np.savez_compressed(
            os.path.join(self.output_dir, "test_predictions.npz"),
            data=all_predictions)

        np.savez_compressed(
            os.path.join(self.output_dir, "test_targets.npz"),
            data=self._test_targets)


        return feature_scores_dict
