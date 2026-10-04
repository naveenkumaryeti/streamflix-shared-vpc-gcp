import os, time
import psycopg2
from flask import Flask, jsonify

app = Flask(__name__)

def get_conn():
    return psycopg2.connect(
        host=os.environ["DB_HOST"], dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"], password=os.environ["DB_PASSWORD"],
    )

@app.get("/api/health")
def health():
    return jsonify(status="ok")

@app.get("/api/movies")
def movies():
    for _ in range(5):                      # small retry if DB is still starting
        try:
            with get_conn() as conn, conn.cursor() as cur:
                cur.execute("SELECT id, title, genre, year FROM movies ORDER BY id")
                rows = cur.fetchall()
            return jsonify([dict(id=r[0], title=r[1], genre=r[2], year=r[3]) for r in rows])
        except psycopg2.OperationalError:
            time.sleep(2)
    return jsonify(error="database unavailable"), 503

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
