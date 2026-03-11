#!/usr/bin/env python3
"""
Neptune Graph Database CDK application.
"""

import os

from aws_cdk import (
    App,
    CfnOutput,
    Stack,
    aws_neptune as neptune,
)
from constructs import Construct


class NeptuneGraphDbStack(Stack):
    """Stack for Neptune Graph Database cluster."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        cluster_id = os.environ.get("CLUSTER_ID", "neptune-test-cluster")

        # Neptune cluster
        cluster = neptune.CfnDBCluster(
            self,
            "NeptuneCluster",
            db_cluster_identifier=cluster_id,
        )

        # Outputs (ARN not available via CfnDBCluster attrs, fetched via CLI)
        CfnOutput(self, "ClusterId", value=cluster_id)
        CfnOutput(self, "ClusterEndpoint", value=cluster.attr_endpoint)
        CfnOutput(self, "ClusterPort", value=cluster.attr_port)


app = App()
NeptuneGraphDbStack(app, "NeptuneGraphDbStack")
app.synth()
