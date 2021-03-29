import h5py
import numpy as np
import torch
import torch.utils.data as data
from torch.utils.data import DataLoader


class H5Dataset(data.Dataset):
    def __init__(self,
                 file_path,
                 size=None,
                 in_memory=False,
                 unpackbits=False,
                 seq_key="sequences",
                 tgt_key="targets"):
        super(H5Dataset, self).__init__()
        self.file_path = file_path
        self.db_len = None
        self.initialized = False
        self.in_memory = in_memory
        self.unpackbits = unpackbits
        self._seq_key = seq_key
        self._tgt_key = tgt_key
        self.size = size

    def init(func):
        # delay initialization to allow multiprocessing
        def dfunc(self, *args, **kwargs):
            if not self.initialized:
                self.db = h5py.File(self.file_path, 'r')
                self.s_len = self.db['{0}_length'.format(self._seq_key)][()]
                self.t_len = self.db['{0}_length'.format(self._tgt_key)][()]
                if self.in_memory:
                    self.sequences = np.asarray(self.db[self._seq_key])
                    self.targets = np.asarray(self.db[self._tgt_key])
                else:
                    self.sequences = self.db[self._seq_key]
                    self.targets = self.db[self._tgt_key]
                self.initialized = True
            return func(self, *args, **kwargs)
        return dfunc

    @init
    def __getitem__(self, index):
        if isinstance(index, int):
            index = index % self.sequences.shape[0]
        sequence = self.sequences[index, :, :]
        targets = self.targets[index, :]
        if self.unpackbits:
            sequence = np.unpackbits(sequence, axis=-2)
            nulls = np.sum(sequence, axis=-1) == 4
            sequence = sequence.astype(float)
            sequence[nulls, :] = 0.25
            targets = np.unpackbits(targets, axis=-1).astype(
                float)

        if sequence.ndim == 3:
            sequence = sequence[:, :self.s_len, :]
        else:
            sequence = sequence[:self.s_len, :]
        if targets.ndim == 2:
            targets = targets[:, :self.t_len]
        else:
            targets = targets[:self.t_len]
        return (torch.from_numpy(sequence.astype(np.float32)),
                torch.from_numpy(targets.astype(np.float32)))

    @init
    def __len__(self):
        if self.size is None:
            self.size = self.sequences.shape[0]
        return self.size

class H5DataLoader(DataLoader):
    def __init__(self,
                 filepath,
                 size=None,
                 in_memory=False,
                 num_workers=1,
                 use_subset=None,
                 batch_size=1,
                 shuffle=True,
                 unpackbits=False,
                 seq_key="sequences",
                 tgt_key="targets"):
        args = {
            "batch_size": batch_size,
            "num_workers": 0 if in_memory else num_workers,
            "pin_memory": True
        }
        if use_subset is not None:
            from torch.utils.data.sampler import SubsetRandomSampler
            if type(use_subset, int):
                use_subset = list(range(use_subset))
            args["sampler"] = SubsetRandomSampler(use_subset)
        else:
            args["shuffle"] = shuffle
        super(H5DataLoader, self).__init__(
            H5Dataset(filepath,
                      size=size,
                      in_memory=in_memory,
                      unpackbits=unpackbits,
                      seq_key=seq_key,
                      tgt_key=tgt_key),
            **args)

    def get_data_and_targets(self, batch_size, n_samples=None):
        sequences, targets = self.dataset[:n_samples]
        return sequences.numpy(), targets.numpy()


