# simple Lambda function training a scikit-learn model on the digits classification dataset
# see https://scikit-learn.org/stable/auto_examples/classification/plot_digits_classification.html

import io
import os

import boto3
import numpy
from joblib import dump
from sklearn import svm
from sklearn.model_selection import train_test_split
from sklearn.utils import Bunch


BUCKET = os.environ.get("S3_BUCKET", "reproducible-ml")


def handler(event, context):
    digits = load_digits()

    # flatten the images
    n_samples = len(digits.images)
    data = digits.images.reshape((n_samples, -1))

    # Create a classifier: a support vector classifier
    clf = svm.SVC(gamma=0.001)

    # Split data into 50% train and 50% test subsets
    X_train, X_test, y_train, y_test = train_test_split(
        data, digits.target, test_size=0.5, shuffle=False
    )

    # Learn the digits on the train subset
    clf.fit(X_train, y_train)

    # Dump the trained model to S3
    s3_client = boto3.client("s3")
    buffer = io.BytesIO()
    dump(clf, buffer)
    s3_client.put_object(Body=buffer.getvalue(), Bucket=BUCKET, Key="model.joblib")

    # Save the test-set to the S3 bucket
    numpy.save("/tmp/test-set.npy", X_test)
    with open("/tmp/test-set.npy", "rb") as f:
        s3_client.put_object(Body=f, Bucket=BUCKET, Key="test-set.npy")

    return {"status": "trained", "samples": n_samples}


def load_digits(*, n_class=10):
    # download files from S3
    s3_client = boto3.client("s3")
    s3_client.download_file(Bucket=BUCKET, Key="digits.csv.gz", Filename="/tmp/digits.csv.gz")
    s3_client.download_file(Bucket=BUCKET, Key="digits.rst", Filename="/tmp/digits.rst")

    data = numpy.loadtxt("/tmp/digits.csv.gz", delimiter=",")
    with open("/tmp/digits.rst") as f:
        descr = f.read()
    target = data[:, -1].astype(int, copy=False)
    flat_data = data[:, :-1]
    images = flat_data.view()
    images.shape = (-1, 8, 8)

    if n_class < 10:
        idx = target < n_class
        flat_data, target = flat_data[idx], target[idx]
        images = images[idx]

    feature_names = [
        "pixel_{}_{}".format(row_idx, col_idx)
        for row_idx in range(8)
        for col_idx in range(8)
    ]

    return Bunch(
        data=flat_data,
        target=target,
        frame=None,
        feature_names=feature_names,
        target_names=numpy.arange(10),
        images=images,
        DESCR=descr,
    )
