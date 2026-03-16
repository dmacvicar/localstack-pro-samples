#!/usr/bin/env python3
"""
Route53 DNS Failover CDK application.
"""

from aws_cdk import (
    App,
    CfnOutput,
    Duration,
    Stack,
    aws_route53 as route53,
)
from constructs import Construct


class Route53DnsFailoverStack(Stack):
    """Stack for Route53 DNS failover with health checks."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        zone_name = self.node.try_get_context("zone_name") or "failover-cdk.example.com"

        # Hosted zone
        zone = route53.HostedZone(
            self,
            "HostedZone",
            zone_name=zone_name,
        )

        # Health check (using CfnHealthCheck for full control)
        health_check = route53.CfnHealthCheck(
            self,
            "HealthCheck",
            health_check_config=route53.CfnHealthCheck.HealthCheckConfigProperty(
                fully_qualified_domain_name="localhost.localstack.cloud",
                port=4566,
                resource_path="/_localstack/health",
                type="HTTP",
                request_interval=10,
            ),
        )

        # Target 1: primary CNAME
        route53.CnameRecord(
            self,
            "Target1",
            zone=zone,
            record_name="target1",
            domain_name="primary.example.com",
            ttl=Duration.seconds(60),
        )

        # Target 2: secondary CNAME
        route53.CnameRecord(
            self,
            "Target2",
            zone=zone,
            record_name="target2",
            domain_name="secondary.example.com",
            ttl=Duration.seconds(60),
        )

        # Failover primary record
        route53.CfnRecordSet(
            self,
            "FailoverPrimary",
            hosted_zone_id=zone.hosted_zone_id,
            name=f"app.{zone_name}",
            type="CNAME",
            set_identifier="primary",
            alias_target=route53.CfnRecordSet.AliasTargetProperty(
                hosted_zone_id=zone.hosted_zone_id,
                dns_name=f"target1.{zone_name}",
                evaluate_target_health=True,
            ),
            health_check_id=health_check.ref,
            failover="PRIMARY",
        )

        # Failover secondary record
        route53.CfnRecordSet(
            self,
            "FailoverSecondary",
            hosted_zone_id=zone.hosted_zone_id,
            name=f"app.{zone_name}",
            type="CNAME",
            set_identifier="secondary",
            alias_target=route53.CfnRecordSet.AliasTargetProperty(
                hosted_zone_id=zone.hosted_zone_id,
                dns_name=f"target2.{zone_name}",
                evaluate_target_health=True,
            ),
            failover="SECONDARY",
        )

        # Outputs
        CfnOutput(self, "HostedZoneId", value=zone.hosted_zone_id)
        CfnOutput(self, "HostedZoneName", value=zone_name)
        CfnOutput(self, "HealthCheckId", value=health_check.ref)
        CfnOutput(self, "FailoverRecord", value=f"app.{zone_name}")
        CfnOutput(self, "Target1Record", value=f"target1.{zone_name}")
        CfnOutput(self, "Target2Record", value=f"target2.{zone_name}")


app = App()
Route53DnsFailoverStack(app, "Route53DnsFailoverStack")
app.synth()
