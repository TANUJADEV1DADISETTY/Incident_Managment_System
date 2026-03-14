#!/bin/bash
set -e

# Sleep helper
wait_seconds() {
  echo "=> Waiting $1 seconds..."
  sleep "$1"
}

echo "=========================================================="
echo " Starting Multi-Region Incident Management Simulation     "
echo "=========================================================="

echo "=> Step 1: Create a new incident in US Region"
RESPONSE=$(curl -s -X POST http://localhost:8080/incidents \
  -H "Content-Type: application/json" \
  -d '{"title": "DB Outage", "description": "Primary DB unreachable", "severity": "CRITICAL"}')

INCIDENT_ID=$(echo $RESPONSE | jq -r '.id')
if [ "$INCIDENT_ID" = "null" ] || [ -z "$INCIDENT_ID" ]; then
    echo "ERROR: Failed to create incident. Response: $RESPONSE"
    exit 1
fi

echo "Created Incident ID: $INCIDENT_ID"
echo "US Region Initial State:"
echo $RESPONSE | jq .

wait_seconds 5

echo "=> Step 2: Verify replication to EU and APAC"
EU_INCIDENT=$(curl -s http://localhost:8081/incidents/$INCIDENT_ID)
APAC_INCIDENT=$(curl -s http://localhost:8082/incidents/$INCIDENT_ID)

echo "EU Region State:"
echo $EU_INCIDENT | jq .
echo "APAC Region State:"
echo $APAC_INCIDENT | jq .

echo "=> Step 3: Simulate Network Partition (Blocking US <-> EU links)"
# We update US to not replicate to EU, and update EU to not replicate to US
curl -s -X PUT http://localhost:8080/config/urls \
  -H "Content-Type: application/json" \
  -d '{"urls": ["http://region-apac:8082"]}' > /dev/null

curl -s -X PUT http://localhost:8081/config/urls \
  -H "Content-Type: application/json" \
  -d '{"urls": ["http://region-apac:8082"]}' > /dev/null

echo "Partition established between US and EU."

wait_seconds 2

echo "=> Step 4: Update the incident in US Region"
US_VC=$(echo $RESPONSE | jq -c '.vector_clock')
US_UPDATE_RES=$(curl -s -X PUT http://localhost:8080/incidents/$INCIDENT_ID \
  -H "Content-Type: application/json" \
  -d "{\"status\": \"ACKNOWLEDGED\", \"vector_clock\": $US_VC}")

echo "US Region Updated State:"
echo $US_UPDATE_RES | jq .

echo "=> Step 5: Update the SAME incident in EU Region (Concurrent Update)"
EU_UPDATE_RES=$(curl -s -X PUT http://localhost:8081/incidents/$INCIDENT_ID \
  -H "Content-Type: application/json" \
  -d "{\"status\": \"INVESTIGATING\", \"assigned_team\": \"EU-SRE\", \"vector_clock\": $US_VC}")

echo "EU Region Updated State:"
echo $EU_UPDATE_RES | jq .

wait_seconds 2

echo "=> Step 6: Remove Network Partition (Restore US <-> EU links)"
curl -s -X PUT http://localhost:8080/config/urls \
  -H "Content-Type: application/json" \
  -d '{"urls": ["http://region-eu:8081", "http://region-apac:8082"]}' > /dev/null

curl -s -X PUT http://localhost:8081/config/urls \
  -H "Content-Type: application/json" \
  -d '{"urls": ["http://region-us:8080", "http://region-apac:8082"]}' > /dev/null

echo "Partition removed. Waiting for replication to catch up..."

wait_seconds 5

echo "=> Step 7: Trigger replication (already running in the background)"
echo "=> Step 8: Fetch the incident from EU Region to verify Conflict Detection"

FINAL_EU_INCIDENT=$(curl -s http://localhost:8081/incidents/$INCIDENT_ID)
echo "Final EU Region Incident State:"
echo $FINAL_EU_INCIDENT | jq .

CONFLICT_FLAG=$(echo $FINAL_EU_INCIDENT | jq -r '.version_conflict')

if [ "$CONFLICT_FLAG" = "true" ]; then
    echo "=========================================================="
    echo " SUCCESS: version_conflict is set to true!"
    echo "=========================================================="
else
    echo "=========================================================="
    echo " FAILURE: version_conflict is NOT true. Something went wrong."
    echo "=========================================================="
    exit 1
fi
