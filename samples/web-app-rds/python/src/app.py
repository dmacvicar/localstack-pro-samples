"""Web application with RDS PostgreSQL backend."""

import json
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Database configuration
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ.get("DB_NAME", "appdb")
DB_USER = os.environ.get("DB_USER", "admin")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "password")

# Try to import psycopg2, fall back to simulated DB if not available
try:
    import psycopg2
    from psycopg2.extras import RealDictCursor
    HAS_PSYCOPG2 = True
except ImportError:
    HAS_PSYCOPG2 = False
    logger.warning("psycopg2 not available, using simulated database")

# In-memory storage for demo when psycopg2 is not available
ITEMS = {}


def get_connection():
    """Get database connection."""
    if not HAS_PSYCOPG2:
        return None

    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )


def init_database():
    """Initialize database schema."""
    if not HAS_PSYCOPG2:
        return

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS items (
                    id VARCHAR(50) PRIMARY KEY,
                    name VARCHAR(255) NOT NULL,
                    description TEXT,
                    category VARCHAR(100),
                    price DECIMAL(10, 2),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
        conn.commit()
    finally:
        conn.close()


def handler(event, context):
    """Handle HTTP requests.

    Args:
        event: API Gateway event
        context: Lambda context

    Returns:
        dict: HTTP response
    """
    logger.info("Received event: %s", json.dumps(event))

    # Initialize database on cold start
    try:
        init_database()
    except Exception as e:
        logger.warning("Database init failed: %s", e)

    http_method = event.get("httpMethod", "GET")
    path = event.get("path", "/")
    path_params = event.get("pathParameters") or {}
    body = event.get("body")

    if body and isinstance(body, str):
        try:
            body = json.loads(body)
        except json.JSONDecodeError:
            pass

    try:
        if path == "/items" and http_method == "GET":
            return list_items()
        elif path == "/items" and http_method == "POST":
            return create_item(body)
        elif path.startswith("/items/") and http_method == "GET":
            item_id = path_params.get("id") or path.split("/")[-1]
            return get_item(item_id)
        elif path.startswith("/items/") and http_method == "PUT":
            item_id = path_params.get("id") or path.split("/")[-1]
            return update_item(item_id, body)
        elif path.startswith("/items/") and http_method == "DELETE":
            item_id = path_params.get("id") or path.split("/")[-1]
            return delete_item(item_id)
        elif path == "/health":
            return health_check()
        else:
            return response(404, {"error": "Not found"})
    except Exception as e:
        logger.error("Error: %s", e)
        return response(500, {"error": str(e)})


def list_items():
    """List all items."""
    if HAS_PSYCOPG2:
        conn = get_connection()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT * FROM items ORDER BY created_at DESC")
                items = cur.fetchall()
                # Convert datetime and Decimal to string for JSON
                for item in items:
                    for key, value in item.items():
                        if isinstance(value, datetime):
                            item[key] = value.isoformat()
                        elif hasattr(value, '__float__'):
                            item[key] = float(value)
            return response(200, {"items": items})
        finally:
            conn.close()
    else:
        return response(200, {"items": list(ITEMS.values())})


def create_item(body):
    """Create a new item."""
    if not body or not isinstance(body, dict):
        return response(400, {"error": "Invalid request body"})

    item_id = body.get("id") or f"item-{datetime.utcnow().strftime('%Y%m%d%H%M%S%f')}"
    name = body.get("name", "")
    description = body.get("description", "")
    category = body.get("category", "general")
    price = body.get("price", 0)

    if HAS_PSYCOPG2:
        conn = get_connection()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("""
                    INSERT INTO items (id, name, description, category, price)
                    VALUES (%s, %s, %s, %s, %s)
                    RETURNING *
                """, (item_id, name, description, category, price))
                item = cur.fetchone()
                conn.commit()
                for key, value in item.items():
                    if isinstance(value, datetime):
                        item[key] = value.isoformat()
                    elif hasattr(value, '__float__'):
                        item[key] = float(value)
            return response(201, item)
        finally:
            conn.close()
    else:
        item = {
            "id": item_id,
            "name": name,
            "description": description,
            "category": category,
            "price": price,
            "created_at": datetime.utcnow().isoformat(),
            "updated_at": datetime.utcnow().isoformat()
        }
        ITEMS[item_id] = item
        return response(201, item)


def get_item(item_id):
    """Get a specific item."""
    if HAS_PSYCOPG2:
        conn = get_connection()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT * FROM items WHERE id = %s", (item_id,))
                item = cur.fetchone()
                if not item:
                    return response(404, {"error": f"Item {item_id} not found"})
                for key, value in item.items():
                    if isinstance(value, datetime):
                        item[key] = value.isoformat()
                    elif hasattr(value, '__float__'):
                        item[key] = float(value)
            return response(200, item)
        finally:
            conn.close()
    else:
        item = ITEMS.get(item_id)
        if not item:
            return response(404, {"error": f"Item {item_id} not found"})
        return response(200, item)


def update_item(item_id, body):
    """Update an existing item."""
    if not body or not isinstance(body, dict):
        return response(400, {"error": "Invalid request body"})

    if HAS_PSYCOPG2:
        conn = get_connection()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                # Check if exists
                cur.execute("SELECT * FROM items WHERE id = %s", (item_id,))
                if not cur.fetchone():
                    return response(404, {"error": f"Item {item_id} not found"})

                # Update
                updates = []
                values = []
                for field in ["name", "description", "category", "price"]:
                    if field in body:
                        updates.append(f"{field} = %s")
                        values.append(body[field])

                if updates:
                    updates.append("updated_at = CURRENT_TIMESTAMP")
                    values.append(item_id)
                    cur.execute(f"""
                        UPDATE items SET {', '.join(updates)}
                        WHERE id = %s
                        RETURNING *
                    """, values)
                    item = cur.fetchone()
                    conn.commit()
                    for key, value in item.items():
                        if isinstance(value, datetime):
                            item[key] = value.isoformat()
                        elif hasattr(value, '__float__'):
                            item[key] = float(value)
                    return response(200, item)
                else:
                    return response(400, {"error": "No fields to update"})
        finally:
            conn.close()
    else:
        if item_id not in ITEMS:
            return response(404, {"error": f"Item {item_id} not found"})
        item = ITEMS[item_id]
        for field in ["name", "description", "category", "price"]:
            if field in body:
                item[field] = body[field]
        item["updated_at"] = datetime.utcnow().isoformat()
        return response(200, item)


def delete_item(item_id):
    """Delete an item."""
    if HAS_PSYCOPG2:
        conn = get_connection()
        try:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM items WHERE id = %s RETURNING id", (item_id,))
                if not cur.fetchone():
                    return response(404, {"error": f"Item {item_id} not found"})
                conn.commit()
            return response(204, None)
        finally:
            conn.close()
    else:
        if item_id not in ITEMS:
            return response(404, {"error": f"Item {item_id} not found"})
        del ITEMS[item_id]
        return response(204, None)


def health_check():
    """Health check endpoint."""
    db_status = "connected" if HAS_PSYCOPG2 else "simulated"
    if HAS_PSYCOPG2:
        try:
            conn = get_connection()
            conn.close()
        except Exception as e:
            db_status = f"error: {e}"

    return response(200, {
        "status": "healthy",
        "database": db_status,
        "timestamp": datetime.utcnow().isoformat()
    })


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
        resp["body"] = json.dumps(body)
    return resp
