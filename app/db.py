import os
import psycopg
from psycopg.rows import dict_row

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL environment variable is required")

def get_connection():
    return psycopg.connect(DATABASE_URL, row_factory=dict_row)

def init_db():
    with get_connection() as conn:
        conn.execute("""CREATE TABLE IF NOT EXISTS tasks (
            id SERIAL PRIMARY KEY,
            title TEXT NOT NULL,
            done INTEGER NOT NULL DEFAULT 0)""")