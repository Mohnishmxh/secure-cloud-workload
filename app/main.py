import os
import sys
from pathlib import Path
import psycopg2
from fastapi import FastAPI, HTTPException

app = FastAPI(title="Secure Cloud Workload API", version="1.0.0")

def get_db_password() -> str:
    """Read database password securely from a mounted secret file instead of plaintext env vars."""
    secret_path = Path(os.getenv("DB_PASSWORD_FILE", "/run/secrets/db_password"))
    if secret_path.exists():
        return secret_path.read_text().strip()
    return ""

@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "environment": os.getenv("APP_ENV", "production")
    }

@app.get("/info")
def system_info():
    return {
        "python_version": sys.version.split()[0],
        "running_uid": os.getuid(),
        "running_gid": os.getgid(),
        "working_directory": os.getcwd(),
        "secret_file_mounted": Path("/run/secrets/db_password").exists()
    }

@app.get("/db-check")
def check_database_connection():
    db_host = os.getenv("DB_HOST", "db")
    db_name = os.getenv("DB_NAME", "workload_db")
    db_user = os.getenv("DB_USER", "workload_user")
    db_password = get_db_password()

    if not db_password:
        raise HTTPException(status_code=500, detail="Database secret not found")

    try:
        conn = psycopg2.connect(
            host=db_host,
            dbname=db_name,
            user=db_user,
            password=db_password,
            connect_timeout=3
        )
        with conn.cursor() as cur:
            cur.execute("SELECT version();")
            db_version = cur.fetchone()[0]
        conn.close()
        return {
            "database_status": "connected",
            "database_host": db_host,
            "postgres_version": db_version.split(",")[0]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database connection failed: {str(e)}")
