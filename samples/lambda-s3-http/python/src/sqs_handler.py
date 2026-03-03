"""SQS event Lambda handler for score validation."""

import json
import logging
import os
import boto3
from decimal import Decimal

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ENDPOINT_URL = os.environ.get("LOCALSTACK_HOSTNAME")
if ENDPOINT_URL:
    ENDPOINT_URL = f"http://{ENDPOINT_URL}:4566"

dynamodb = boto3.resource("dynamodb", endpoint_url=ENDPOINT_URL)
TABLE_NAME = os.environ.get("TABLE_NAME", "game-scores")

# Score validation rules
MAX_SCORE = 1000000
MIN_SCORE = 0


def handler(event, context):
    """Process SQS messages for score validation.

    Args:
        event: SQS event with messages
        context: Lambda context

    Returns:
        dict: Processing result
    """
    logger.info("Received SQS event: %s", json.dumps(event))

    validated = []
    failed = []

    for record in event.get("Records", []):
        try:
            body = json.loads(record["body"])
            player_id = body.get("playerId")
            score = body.get("score")

            logger.info("Validating score: player=%s, score=%s", player_id, score)

            # Validate score
            if score is None:
                raise ValueError("Score is required")

            score_val = float(score)
            if score_val < MIN_SCORE or score_val > MAX_SCORE:
                raise ValueError(f"Score {score_val} out of valid range [{MIN_SCORE}, {MAX_SCORE}]")

            # Mark as validated in DynamoDB
            table = dynamodb.Table(TABLE_NAME)
            table.update_item(
                Key={"playerId": player_id},
                UpdateExpression="SET validated = :v",
                ExpressionAttributeValues={":v": True}
            )

            validated.append({
                "playerId": player_id,
                "score": score_val,
                "status": "validated"
            })

        except Exception as e:
            logger.error("Validation error: %s", e)
            failed.append({
                "messageId": record.get("messageId"),
                "error": str(e)
            })

    return {
        "statusCode": 200,
        "body": json.dumps({
            "validated": len(validated),
            "failed": len(failed),
            "results": validated,
            "errors": failed
        })
    }
