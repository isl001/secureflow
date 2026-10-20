from fastapi import FastAPI

app = FastAPI(title="SecureFlow API")


@app.get("/health")
def health():
    return {"status": "ok"}

tasks = [
    {"id": 1, "title": "Set up Gitleaks", "done": True},
    {"id": 2, "title": "Learn FastAPI", "done": False},
]


@app.get("/tasks")
def list_tasks():
    return tasks

from pydantic import BaseModel, Field


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=100)


@app.post("/tasks", status_code=201)
def create_task(task: TaskCreate):
    new_task = {"id": len(tasks) + 1, "title": task.title, "done": False}
    tasks.append(new_task)
    return new_task