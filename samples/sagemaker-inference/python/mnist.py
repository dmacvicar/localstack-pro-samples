import gzip
import os

import numpy as np


def mnist_to_numpy(data_dir="/tmp/data", train=False):
    """Load MNIST dataset from local files and convert to numpy arrays."""
    if train:
        images_file = "train-images-idx3-ubyte.gz"
        labels_file = "train-labels-idx1-ubyte.gz"
    else:
        images_file = "t10k-images-idx3-ubyte.gz"
        labels_file = "t10k-labels-idx1-ubyte.gz"

    return _convert_to_numpy(data_dir, images_file, labels_file)


def _convert_to_numpy(data_dir, images_file, labels_file):
    """Byte string to numpy arrays."""
    with gzip.open(os.path.join(data_dir, images_file), "rb") as f:
        images = np.frombuffer(f.read(), np.uint8, offset=16).reshape(-1, 28, 28)

    with gzip.open(os.path.join(data_dir, labels_file), "rb") as f:
        labels = np.frombuffer(f.read(), np.uint8, offset=8)

    return (images, labels)


def normalize(x, axis):
    eps = np.finfo(float).eps
    mean = np.mean(x, axis=axis, keepdims=True)
    std = np.std(x, axis=axis, keepdims=True) + eps
    return (x - mean) / std
