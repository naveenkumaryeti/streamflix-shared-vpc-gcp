# StreamFlix - Tiny 3-Tier Demo

A minimal movie catalogue showing the classic 3-tier architecture.
Runs locally with Docker Compose. Subnets mirror the StreamFlix Shared VPC design (web 10.10.1.0/24, app 10.10.2.0/24, data 10.10.3.0/24).

## 1. Architecture

```
 Browser
    |  http://localhost:8080
    v
+-----------------+   web-net 10.10.1.0/24
| TIER 1 Frontend |   (nginx + HTML/JS)
+--------+--------+
         | /api/*     app-net 10.10.2.0/24
         v
+-----------------+
| TIER 2 Backend  |   (Python Flask REST API)
+--------+--------+
         | SQL        data-net 10.10.3.0/24 (internal, no internet)
         v
+-----------------+
| TIER 3 Database |   (PostgreSQL 16)
+-----------------+
```

Rule: each tier only talks to the tier next to it. The browser never reaches the backend or DB directly.

<img width="3840" height="2160" alt="StreamFlix_Architecture_4K" src="https://github.com/user-attachments/assets/1158ee0f-7ca1-47fd-859b-177bd5f577cc" />




## 2. Folder structure

```
streamflix/
├── docker-compose.yml     # defines the 3 tiers + 3 networks
├── frontend/
│   ├── Dockerfile         # builds nginx image
│   ├── nginx.conf         # serves page, proxies /api to backend
│   └── index.html         # UI that calls /api/movies
├── backend/
│   ├── Dockerfile         # builds Python image
│   ├── requirements.txt   # Flask + psycopg2
│   └── app.py             # API: /api/health, /api/movies
└── database/
    └── init.sql           # creates table + sample data
```

## 3. Step-by-step explanation

### Step 1 - Database tier (`database/init.sql`, `db` service)
- Uses the official `postgres:16-alpine` image.
- `init.sql` is mounted into `/docker-entrypoint-initdb.d/`; Postgres runs it automatically on first start, creating the `movies` table and 4 sample rows.
- A `healthcheck` (`pg_isready`) tells Compose when the DB is truly ready.
- A named volume `db-data` keeps data after restarts.
- It sits only on `data-net`, which is `internal: true` (no internet, not reachable from the frontend).

### Step 2 - Backend tier (`backend/`)
- `requirements.txt`: installs Flask (web framework) and psycopg2 (Postgres driver).
- `app.py`:
  - `get_conn()` reads DB host/user/password from environment variables (no secrets in code).
  - `GET /api/health` returns `{"status":"ok"}` - used for quick checks.
  - `GET /api/movies` runs `SELECT` on the table and returns JSON. It retries a few times if the DB is slow to start.
- `Dockerfile`: starts from `python:3.12-slim`, installs requirements, copies code, runs `python app.py` on port 5000.
- It sits on `app-net` (to talk to frontend) and `data-net` (to talk to DB).

### Step 3 - Frontend tier (`frontend/`)
- `index.html`: a simple page; JavaScript calls `fetch('/api/movies')` and draws a card per movie.
- `nginx.conf`: serves the HTML and forwards any `/api/` request to `http://backend:5000/api/` (Docker DNS resolves `backend`). This avoids CORS issues and hides the backend.
- `Dockerfile`: nginx:alpine image with the config and HTML copied in.
- It sits on `web-net` (user-facing) and `app-net` (to reach backend).

### Step 4 - Wiring everything (`docker-compose.yml`)
- **services**: `frontend`, `backend`, `db` = the three tiers.
- **ports**: only the frontend publishes `8080:80`. Backend and DB have no published ports, so they are not reachable from your machine/internet.
- **depends_on**: DB starts first (waits until healthy), then backend, then frontend.
- **networks**: three networks with the same CIDRs as the Shared VPC subnets, so tier isolation matches the cloud design.
- **environment**: DB credentials are shared between `backend` and `db` here (demo only - use Secret Manager/Kubernetes secrets in real life).

## 4. How to run

Prerequisite: Docker + Docker Compose installed.

```bash
unzip streamflix.zip
cd streamflix
docker compose up --build
```

Open http://localhost:8080 - you should see 4 movie cards.

## 5. How to verify each tier

```bash
# Tier 1 + 2 together (through nginx proxy)
curl http://localhost:8080/api/health
curl http://localhost:8080/api/movies

# Tier 3 - query DB directly
docker compose exec db psql -U streamflix -d streamflix -c "SELECT * FROM movies;"

# Prove isolation: backend is NOT exposed to host
curl http://localhost:5000/api/health    # should fail
```

## 6. Stop and clean up

```bash
docker compose down        # stop
docker compose down -v     # stop + delete DB data
```

## 7. Mapping to GCP (next step)

| Demo | GCP equivalent |
|---|---|
| frontend container | VM / GKE / Cloud Run in `streamflix-web`, subnet `web-subnet` |
| backend container | VM / GKE in `streamflix-app`, subnet `app-subnet` |
| db container | Cloud SQL / VM in `streamflix-data`, subnet `data-subnet` |
| Docker networks | Shared VPC subnets in host project `streamflix-network` |
| internal: true | no external IP + firewall rules / Private Google Access |

## 8. Deploy on GCP Shared VPC
See `SHARED_VPC_GUIDE.md` (exact gcloud procedure using `scripts/`).

## 9. Troubleshooting

- Page says "Could not load movies": run `docker compose logs backend`.
- Port 8080 busy: change `"8080:80"` in `docker-compose.yml`.
- Changed `init.sql` but no effect: it only runs on an empty volume; use `docker compose down -v`.
# streamflix-shared-vpc-gcp
