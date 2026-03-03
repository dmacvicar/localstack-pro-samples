"""HTTP API Lambda handler for gaming scoreboard."""

import json
import logging
import os
import boto3
from datetime import datetime
from decimal import Decimal

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize clients
ENDPOINT_URL = os.environ.get("LOCALSTACK_HOSTNAME")
if ENDPOINT_URL:
    ENDPOINT_URL = f"http://{ENDPOINT_URL}:4566"

dynamodb = boto3.resource("dynamodb", endpoint_url=ENDPOINT_URL)
sqs = boto3.client("sqs", endpoint_url=ENDPOINT_URL)

TABLE_NAME = os.environ.get("TABLE_NAME", "game-scores")
QUEUE_URL = os.environ.get("QUEUE_URL", "")


class DecimalEncoder(json.JSONEncoder):
    """JSON encoder for Decimal types."""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)


def handler(event, context):
    """Handle HTTP API requests.

    Args:
        event: API Gateway event
        context: Lambda context

    Returns:
        dict: HTTP response
    """
    logger.info("Received event: %s", json.dumps(event))

    http_method = event.get("httpMethod", "GET")
    path = event.get("path", "/")
    path_params = event.get("pathParameters") or {}
    body = event.get("body")

    if body and isinstance(body, str):
        try:
            body = json.loads(body)
        except json.JSONDecodeError:
            pass

    # Route handling
    if path == "/scores" and http_method == "GET":
        return get_top_scores()
    elif path == "/scores" and http_method == "POST":
        return submit_score(body)
    elif path.startswith("/scores/") and http_method == "GET":
        player_id = path_params.get("playerId") or path.split("/")[-1]
        return get_player_scores(player_id)
    else:
        return response(404, {"error": "Not found"})


def get_top_scores():
    """Get top 10 scores."""
    try:
        table = dynamodb.Table(TABLE_NAME)
        result = table.scan(Limit=10)
        items = sorted(result.get("Items", []), key=lambda x: x.get("score", 0), reverse=True)
        return response(200, {"scores": items[:10]})
    except Exception as e:
        logger.error("Error getting scores: %s", e)
        return response(500, {"error": str(e)})


def submit_score(body):
    """Submit a new score."""
    if not body or not isinstance(body, dict):
        return response(400, {"error": "Invalid request body"})

    player_id = body.get("playerId")
    score = body.get("score")
    game = body.get("game", "default")

    if not player_id or score is None:
        return response(400, {"error": "playerId and score are required"})

    try:
        # Store score in DynamoDB
        table = dynamodb.Table(TABLE_NAME)
        item = {
            "playerId": player_id,
            "score": Decimal(str(score)),
            "game": game,
            "timestamp": datetime.utcnow().isoformat()
        }
        table.put_item(Item=item)

        # Queue for async validation
        if QUEUE_URL:
            sqs.send_message(
                QueueUrl=QUEUE_URL,
                MessageBody=json.dumps(item, cls=DecimalEncoder)
            )

        return response(201, {"message": "Score submitted", "item": item})
    except Exception as e:
        logger.error("Error submitting score: %s", e)
        return response(500, {"error": str(e)})


def get_player_scores(player_id):
    """Get scores for a specific player."""
    try:
        table = dynamodb.Table(TABLE_NAME)
        result = table.query(
            KeyConditionExpression="playerId = :pid",
            ExpressionAttributeValues={":pid": player_id}
        )
        return response(200, {"playerId": player_id, "scores": result.get("Items", [])})
    except Exception as e:
        logger.error("Error getting player scores: %s", e)
        return response(500, {"error": str(e)})


def response(status_code, body):
    """Create HTTP response."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
        },
        "body": json.dumps(body, cls=DecimalEncoder)
    }
