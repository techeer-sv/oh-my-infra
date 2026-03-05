# contains logging related stacks and scripts

Alloy (logs)
     │
     ▼
loki-write (ingesters)
     │
     ▼
MinIO (object storage)

Grafana queries
     │
     ▼
query-frontend
     │
     ▼
query-scheduler
     │
     ▼
loki-read (queriers)
     │
     ▼
loki-backend (compactor / index / store)
     │
     ▼
MinIO