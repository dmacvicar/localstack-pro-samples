"""S3 event Lambda handler for processing game replays."""

import json
import logging
import os
import urllib.parse
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ENDPOINT_URL = os.environ.get("LOCALSTACK_HOSTNAME")
if ENDPOINT_URL:
    ENDPOINT_URL = f"http://{ENDPOINT_URL}:4566"

s3 = boto3.client("s3", endpoint_url=ENDPOINT_URL)
dynamodb = boto3.resource("dynamodb", endpoint_url=ENDPOINT_URL)

TABLE_NAME = os.environ.get("TABLE_NAME", "game-scores")


def handler(event, context):
    """Process S3 events for uploaded game replays.

    Args:
        event: S3 event notification
        context: Lambda context

    Returns:
        dict: Processing result
    """
    logger.info("Received S3 event: %s", json.dumps(event))

    processed = []

    for record in event.get("Records", []):
        bucket = record["s3"]["bucket"]["name"]
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        size = record["s3"]["object"].get("size", 0)

        logger.info("Processing replay: bucket=%s, key=%s, size=%d", bucket, key, size)

        try:
            # Get object metadata
            response = s3.head_object(Bucket=bucket, Key=key)
            metadata = response.get("Metadata", {})

            # Extract player info from metadata or key
            player_id = metadata.get("player-id", key.split("/")[0] if "/" in key else "unknown")
            game = metadata.get("game", "replay")

            # Log processing
            processed.append({
                "bucket": bucket,
                "key": key,
                "playerId": player_id,
                "game": game,
                "size": size,
                "status": "processed"
            })

            logger.info("Replay processed for player: %s", player_id)

        except Exception as e:
            logger.error("Error processing %s/%s: %s", bucket, key, e)
            processed.append({
                "bucket": bucket,
                "key": key,
                "status": "error",
                "error": str(e)
            })

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Replays processed",
            "count": len(processed),
            "results": processed
        })
    }
