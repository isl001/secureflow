from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from app.db import get_connection, init_db

app = FastAPI(title="SecureFlow API")
init_db()


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=100)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/tasks")
def list_tasks():
    with get_connection() as conn:
        rows = conn.execute("SELECT id, title, done FROM tasks").fetchall()
    return [dict(row) for row in rows]


@app.post("/tasks", status_code=201)
def create_task(task: TaskCreate):
    with get_connection() as conn:
        row = conn.execute(
            "INSERT INTO tasks (title) VALUES (%s) RETURNING id", (task.title,)
        ).fetchone()
        task_id = row["id"]
    return {"id": task_id, "title": task.title, "done": 0}

@app.delete("/tasks/{task_id}", status_code=204)
def delete_task(task_id: int):
    with get_connection() as conn:
        cursor = conn.execute("DELETE FROM tasks WHERE id = %s", (task_id,))
    if cursor.rowcount == 0:
        raise HTTPException(status_code=404, detail="Task not found")