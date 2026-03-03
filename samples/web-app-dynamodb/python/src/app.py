"""Web application with DynamoDB backend."""

import json
import logging
import os
from datetime import datetime
from decimal import Decimal
import boto3
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ENDPOINT_URL = os.environ.get("LOCALSTACK_HOSTNAME")
if ENDPOINT_URL:
    ENDPOINT_URL = f"http://{ENDPOINT_URL}:4566"

dynamodb = boto3.resource("dynamodb", endpoint_url=ENDPOINT_URL)
TABLE_NAME = os.environ.get("TABLE_NAME", "items")


class DecimalEncoder(json.JSONEncoder):
    """JSON encoder for Decimal types."""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)


def handler(event, context):
    """Handle HTTP requests.

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
    query_params = event.get("queryStringParameters") or {}
    body = event.get("body")

    if body and isinstance(body, str):
        try:
            body = json.loads(body)
        except json.JSONDecodeError:
            pass

    table = dynamodb.Table(TABLE_NAME)

    # Route handling
    try:
        if path == "/items" and http_method == "GET":
            return list_items(table, query_params)
        elif path == "/items" and http_method == "POST":
            return create_item(table, body)
        elif path.startswith("/items/") and http_method == "GET":
            item_id = path_params.get("id") or path.split("/")[-1]
            return get_item(table, item_id)
        elif path.startswith("/items/") and http_method == "PUT":
            item_id = path_params.get("id") or path.split("/")[-1]
            return update_item(table, item_id, body)
        elif path.startswith("/items/") and http_method == "DELETE":
            item_id = path_params.get("id") or path.split("/")[-1]
            return delete_item(table, item_id)
        else:
            return response(404, {"error": "Not found"})
    except Exception as e:
        logger.error("Error: %s", e)
        return response(500, {"error": str(e)})


def list_items(table, query_params):
    """List items with optional filtering."""
    category = query_params.get("category")

    if category:
        # Query by category (requires GSI in real implementation)
        result = table.scan(
            FilterExpression="category = :cat",
            ExpressionAttributeValues={":cat": category}
        )
    else:
        result = table.scan()

    return response(200, {"items": result.get("Items", [])})


def create_item(table, body):
    """Create a new item."""
    if not body or not isinstance(body, dict):
        return response(400, {"error": "Invalid request body"})

    item_id = body.get("id") or f"item-{datetime.utcnow().strftime('%Y%m%d%H%M%S%f')}"

    item = {
        "id": item_id,
        "name": body.get("name", ""),
        "description": body.get("description", ""),
        "category": body.get("category", "general"),
        "price": Decimal(str(body.get("price", 0))),
        "createdAt": datetime.utcnow().isoformat(),
        "updatedAt": datetime.utcnow().isoformat()
    }

    table.put_item(Item=item)
    return response(201, item)


def get_item(table, item_id):
    """Get a specific item."""
    result = table.get_item(Key={"id": item_id})
    item = result.get("Item")

    if not item:
        return response(404, {"error": f"Item {item_id} not found"})

    return response(200, item)


def update_item(table, item_id, body):
    """Update an existing item."""
    if not body or not isinstance(body, dict):
        return response(400, {"error": "Invalid request body"})

    # Check if item exists
    result = table.get_item(Key={"id": item_id})
    if "Item" not in result:
        return response(404, {"error": f"Item {item_id} not found"})

    update_expr = "SET updatedAt = :ua"
    expr_values = {":ua": datetime.utcnow().isoformat()}

    if "name" in body:
        update_expr += ", #n = :n"
        expr_values[":n"] = body["name"]
    if "description" in body:
        update_expr += ", description = :d"
        expr_values[":d"] = body["description"]
    if "category" in body:
        update_expr += ", category = :c"
        expr_values[":c"] = body["category"]
    if "price" in body:
        update_expr += ", price = :p"
        expr_values[":p"] = Decimal(str(body["price"]))

    expr_names = {"#n": "name"} if "name" in body else None

    update_args = {
        "Key": {"id": item_id},
        "UpdateExpression": update_expr,
        "ExpressionAttributeValues": expr_values,
        "ReturnValues": "ALL_NEW"
    }
    if expr_names:
        update_args["ExpressionAttributeNames"] = expr_names

    result = table.update_item(**update_args)
    return response(200, result.get("Attributes"))


def delete_item(table, item_id):
    """Delete an item."""
    # Check if item exists
    result = table.get_item(Key={"id": item_id})
    if "Item" not in result:
        return response(404, {"error": f"Item {item_id} not found"})

    table.delete_item(Key={"id": item_id})
    return response(204, None)


def response(status_code, body):
    """Create HTTP response."""
    resp = {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
        }
    }
    if body is not None:
        resp["body"] = json.dumps(body, cls=DecimalEncoder)
    return resp
