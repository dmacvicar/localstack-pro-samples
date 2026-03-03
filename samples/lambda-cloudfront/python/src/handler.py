"""Lambda function for CloudFront origin."""

import json
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    """Handle requests from CloudFront.

    Args:
        event: CloudFront or API Gateway event
        context: Lambda context

    Returns:
        dict: Response for CloudFront
    """
    logger.info("Received event: %s", json.dumps(event))

    # Handle different event formats
    path = "/"
    method = "GET"

    # API Gateway format
    if "httpMethod" in event:
        path = event.get("path", "/")
        method = event.get("httpMethod", "GET")
    # CloudFront Lambda@Edge format
    elif "Records" in event:
        cf_request = event["Records"][0]["cf"]["request"]
        path = cf_request.get("uri", "/")
        method = cf_request.get("method", "GET")

    response_body = {
        "message": "Hello from Lambda behind CloudFront!",
        "path": path,
        "method": method,
        "timestamp": datetime.utcnow().isoformat(),
        "origin": "lambda-cloudfront-sample"
    }

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "max-age=60",
            "X-Custom-Header": "LocalStack-Sample"
        },
        "body": json.dumps(response_body)
    }
