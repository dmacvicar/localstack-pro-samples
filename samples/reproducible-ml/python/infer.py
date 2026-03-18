# simple Lambda function for inference on the digits classification dataset
# see https://scikit-learn.org/stable/auto_examples/classification/plot_digits_classification.html

import os

import boto3
import numpy
from joblib import load


BUCKET = os.environ.get("S3_BUCKET", "reproducible-ml")


def handler(event, context):
    # download the model and the test set from S3
    s3_client = boto3.client("s3")
    s3_client.download_file(Bucket=BUCKET, Key="test-set.npy", Filename="/tmp/test-set.npy")
    s3_client.download_file(Bucket=BUCKET, Key="model.joblib", Filename="/tmp/model.joblib")

    with open("/tmp/test-set.npy", "rb") as f:
        X_test = numpy.load(f)

    clf = load("/tmp/model.joblib")

    predicted = clf.predict(X_test)
    result = predicted.tolist()
    print("--> prediction result:", result[:10], "...")

    return {"predictions_count": len(result), "first_10": result[:10]}
