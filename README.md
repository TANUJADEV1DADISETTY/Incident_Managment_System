# Multi-Region Incident Management System with Vector Clocks

## Overview

This project implements a **distributed multi-region incident management backend** that guarantees **causal ordering of updates using vector clocks**.

The system simulates three geographically distributed regions:

- **US**
- **EU**
- **APAC**

Each region runs an independent backend service and its own PostgreSQL database.  
The regions replicate incident updates asynchronously using HTTP APIs.

Vector clocks are used to:

- Track **causal relationships between updates**
- Detect **concurrent modifications**
- Prevent **lost updates**
- Enable **eventual consistency**

This architecture demonstrates concepts used in real distributed systems such as:

- PagerDuty
- ServiceNow
- Amazon DynamoDB
- Apache Cassandra

---

# System Architecture

The system contains **six containers**:

| Service     | Description                     |
| ----------- | ------------------------------- |
| region-us   | Backend service for US region   |
| db-us       | PostgreSQL database for US      |
| region-eu   | Backend service for EU region   |
| db-eu       | PostgreSQL database for EU      |
| region-apac | Backend service for APAC region |
| db-apac     | PostgreSQL database for APAC    |

Each region:

- Handles its own API requests
- Stores incidents locally
- Replicates updates to peer regions

Replication occurs asynchronously through an internal endpoint.

---

# Architecture Diagram

```
             +------------------+
             |   Client Apps    |
             +---------+--------+
                       |
         +-------------+-------------+
         |                           |
     +---v----+                 +----v---+
     |Region US|                |Region EU|
     +---+----+                 +----+---+
         |                           |
      +--v---+                   +---v--+
      |DB-US |                   |DB-EU |
      +------+                   +------+
         |                           |
         +-------------+-------------+
                       |
                   +---v----+
                   |Region APAC|
                   +---+----+
                       |
                   +---v---+
                   |DB-APAC|
                   +-------+
```

All regions replicate incident updates using:

```
POST /internal/replicate
```

---

# Core Concepts

## Vector Clocks

A **vector clock** tracks the version of a record across regions.

Example:

```json
{
  "us": 2,
  "eu": 1,
  "apac": 0
}
```

Each component represents the number of updates performed by a region.

### Operations

#### Increment

When a region updates an incident:

```
vector_clock[region] += 1
```

#### Compare

Vector clocks determine causal relationships.

Possible results:

| Result     | Meaning                        |
| ---------- | ------------------------------ |
| BEFORE     | Incoming update is stale       |
| AFTER      | Incoming update is newer       |
| EQUAL      | Same version                   |
| CONCURRENT | Updates happened independently |

#### Merge

When clocks merge:

```
merged[i] = max(vc1[i], vc2[i])
```

---

# Database Schema

Each region contains an `incidents` table.

| Column           | Type      | Description                    |
| ---------------- | --------- | ------------------------------ |
| id               | UUID      | Incident identifier            |
| title            | VARCHAR   | Incident title                 |
| description      | TEXT      | Detailed description           |
| status           | VARCHAR   | OPEN / ACKNOWLEDGED / RESOLVED |
| severity         | VARCHAR   | LOW / MEDIUM / HIGH / CRITICAL |
| assigned_team    | VARCHAR   | Responsible team               |
| vector_clock     | JSONB     | Vector clock for causality     |
| version_conflict | BOOLEAN   | Conflict indicator             |
| updated_at       | TIMESTAMP | Last update time               |

---

# API Endpoints

## Create Incident

```
POST /incidents
```

### Request

```json
{
  "title": "Database outage",
  "description": "Primary DB unreachable",
  "severity": "HIGH"
}
```

### Response

```json
{
  "id": "uuid",
  "title": "Database outage",
  "description": "Primary DB unreachable",
  "status": "OPEN",
  "severity": "HIGH",
  "vector_clock": {
    "us": 1,
    "eu": 0,
    "apac": 0
  }
}
```

The vector clock initializes with the local region set to **1**.

---

## Update Incident

```
PUT /incidents/{id}
```

### Request

```json
{
  "status": "ACKNOWLEDGED",
  "assigned_team": "SRE-Team-A",
  "vector_clock": {
    "us": 1,
    "eu": 0,
    "apac": 0
  }
}
```

### Logic

1. Compare request vector clock with stored clock
2. Reject stale updates
3. Increment local region clock
4. Save updated incident

### Conflict Example

```
409 Conflict
```

Occurs when a stale update is detected.

---

## Internal Replication

```
POST /internal/replicate
```

Used only by region services.

Incoming incident data is compared with the local version.

### Cases

| Condition  | Action                 |
| ---------- | ---------------------- |
| AFTER      | Overwrite local record |
| BEFORE     | Ignore update          |
| CONCURRENT | Mark conflict          |
| EQUAL      | Ignore                 |

---

## Resolve Conflict

```
POST /incidents/{id}/resolve
```

Used when concurrent updates occur.

### Request

```json
{
  "status": "RESOLVED",
  "assigned_team": "SRE-Managers"
}
```

### Behavior

- Apply resolution
- Clear conflict flag
- Increment local vector clock

---

# Replication Strategy

Each region runs a background job that:

1. Reads local incidents
2. Sends them to peer regions
3. Calls `/internal/replicate`
4. Runs periodically

Replication is **idempotent**.

Duplicate updates do not change system state.

---

# Network Partition Simulation

The project includes a script:

```
simulate_partition.sh
```

This demonstrates distributed conflict handling.

### Scenario

1. Create incident in **US**
2. Replicate to **EU**
3. Simulate partition
4. Update incident in US
5. Update incident in EU
6. Restore connectivity
7. Replicate updates
8. Conflict detected

Expected result:

```
"version_conflict": true
```

---

# Project Structure

```
incident-vector-clock-system
│
├── docker-compose.yml
├── Dockerfile
├── .env.example
├── simulate_partition.sh
├── README.md
│
└── app
    ├── server.js
    ├── db.js
    ├── vectorClock.js
    ├── replication.js
    └── routes
        └── incidents.js
```

---

# Environment Variables

Example configuration:

```
DB_USER=postgres
DB_PASSWORD=postgres

PORT=3000

REGION=us

US_URL=http://region-us:3001
EU_URL=http://region-eu:3002
APAC_URL=http://region-apac:3003
```

---

# Running the System

## 1 Install Docker

Ensure Docker and Docker Compose are installed.

```
docker --version
docker-compose --version
```

---

## 2 Start the System

```
docker-compose up --build
```

All services start automatically.

Startup time: **under 3 minutes**.

---

## 3 Verify Health

```
http://localhost:3001/health
http://localhost:3002/health
http://localhost:3003/health
```

---

# Example Workflow

### Create Incident

```
POST localhost:3001/incidents
```

### Update Incident

```
PUT localhost:3001/incidents/{id}
```

### Replication

Automatic via background worker.

---

# Demonstrating Conflict Detection

Run:

```
./simulate_partition.sh
```

Expected output:

```
Incident created
Partition simulated
Concurrent updates performed
Replication restored
Conflict detected
```

Final JSON:

```json
{
  "id": "...",
  "version_conflict": true
}
```

---

# Idempotent Replication

If the same replication message arrives twice:

```
vc_in <= vc_local
```

The update is ignored.

This guarantees safe retry behavior.

---

# Causal Chain Example

```
US creates incident
vc = {us:1, eu:0, apac:0}

EU updates incident
vc = {us:1, eu:1, apac:0}

APAC updates incident
vc = {us:1, eu:1, apac:1}
```

Final vector clock reflects the entire causal history.

---

# Technologies Used

| Technology     | Purpose                     |
| -------------- | --------------------------- |
| Node.js        | Backend services            |
| Express        | REST API framework          |
| PostgreSQL     | Persistent storage          |
| Docker         | Containerization            |
| Docker Compose | Multi-service orchestration |
| Vector Clocks  | Causal ordering             |
| Bash           | Partition simulation        |

---

# Distributed Systems Concepts Demonstrated

- Eventual consistency
- Causal ordering
- Conflict detection
- Multi-region replication
- Idempotent updates
- Network partition tolerance
- Vector clocks

---

# Future Improvements

Possible enhancements:

- Add message queues (Kafka / RabbitMQ)
- Implement CRDT conflict resolution
- Add authentication
- Add monitoring (Prometheus / Grafana)
- Implement Web UI dashboard

---

# Author

Distributed Systems Project  
Multi-Region Incident Management System with Vector Clocks

---

# License

This project is for educational purposes.
