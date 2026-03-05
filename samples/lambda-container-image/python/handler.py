"""Lambda handler for container image demo."""

import json


def handler(event, context):
    """Simple handler that echoes the event."""
    print("Hello from LocalStack Lambda container image!")

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Hello from Lambda container image!",
            "event": event
        })
    }
