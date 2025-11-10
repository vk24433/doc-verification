# CI/CD Flow Diagrams

## Complete Pipeline Flow

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Developer Workflow                             │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                    1. Edit Dockerfile/requirements.txt
                    2. git commit & push
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│                   STAGE 1: BUILD (GitLab Runner)                      │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │  docker build -t airflow-custom:abc123                     │     │
│  │  • Tags: commit-sha, latest, branch-name                   │     │
│  │  • Save as artifact: airflow-image.tar                     │     │
│  └────────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│              STAGE 2: PUSH TO NEXUS (GitLab Runner)                  │
│                                                                       │
│  ┌────────────────────────────────────────────────────────────┐     │
│  │  1. docker login nexus.yourcompany.com:8443               │     │
│  │  2. docker tag airflow-custom:abc123 nexus.../airflow:abc │     │
│  │  3. docker push (abc123, latest, branch-name)             │     │
│  │  4. Create deployment-metadata.json                        │     │
│  └────────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
                    ▼                             ▼
┌──────────────────────────────┐  ┌──────────────────────────────┐
│ STAGE 3A: DEPLOY SERVER 131 │  │ STAGE 3B: DEPLOY SERVER 130 │
│  (Runs in Parallel)          │  │  (Runs in Parallel)          │
├──────────────────────────────┤  ├──────────────────────────────┤
│ SSH to 172.10.17.131         │  │ SSH to 172.10.17.130         │
│                              │  │                              │
│ 1. Login to Nexus            │  │ 1. Login to Nexus            │
│ 2. Pull image:abc123         │  │ 2. Pull image:abc123         │
│ 3. Backup current metadata   │  │ 3. Backup current metadata   │
│ 4. Save new metadata         │  │ 4. Save new metadata         │
│ 5. Update compose file       │  │ 5. Update compose file       │
│ 6. docker-compose up -d      │  │ 6. docker-compose up -d      │
│ 7. Cleanup old images        │  │ 7. Cleanup old images        │
│                              │  │                              │
│ Services:                    │  │ Services:                    │
│ • MySQL                      │  │ • Webserver                  │
│ • Redis                      │  │ • Scheduler-1                │
│ • Scheduler-2                │  │                              │
└──────────────────────────────┘  └──────────────────────────────┘
                    │                             │
                    └──────────────┬──────────────┘
                                   ▼
                    ┌──────────────────────────────┐
                    │   Deployment Complete! 🎉    │
                    └──────────────────────────────┘
```

## Rollback Flow - Strategy 1 (Previous Version)

```
┌──────────────────────────────────────────────────────────────────────┐
│              Issue Detected in Production                             │
│              Need Quick Rollback!                                     │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│          GitLab Pipeline → Rollback Stage → Click Play ▶️            │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
                    ▼                             ▼
┌──────────────────────────────┐  ┌──────────────────────────────┐
│   Rollback Server 131        │  │   Rollback Server 130        │
├──────────────────────────────┤  ├──────────────────────────────┤
│ SSH to 172.10.17.131         │  │ SSH to 172.10.17.130         │
│                              │  │                              │
│ 1. Read previous-deployment  │  │ 1. Read previous-deployment  │
│    -131.json                 │  │    -130.json                 │
│    ↓                         │  │    ↓                         │
│    Get image: abc123         │  │    Get image: abc123         │
│                              │  │                              │
│ 2. Login to Nexus            │  │ 2. Login to Nexus            │
│ 3. Pull previous image       │  │ 3. Pull previous image       │
│ 4. Update compose file       │  │ 4. Update compose file       │
│ 5. docker-compose up -d      │  │ 5. docker-compose up -d      │
│ 6. Swap metadata files       │  │ 6. Swap metadata files       │
└──────────────────────────────┘  └──────────────────────────────┘
                    │                             │
                    └──────────────┬──────────────┘
                                   ▼
                    ┌──────────────────────────────┐
                    │  Rollback Complete! ✅       │
                    │  System restored to previous │
                    │  working version             │
                    └──────────────────────────────┘
```

## Rollback Flow - Strategy 2 (Specific Version)

```
┌──────────────────────────────────────────────────────────────────────┐
│          Need to rollback to specific version: def456                │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│   Option A: GitLab UI                                                │
│   - Go to Pipeline                                                   │
│   - Click rollback-to-version                                        │
│   - Set variable: ROLLBACK_TAG=def456                                │
│   - Run job                                                          │
│                                                                       │
│   Option B: Helper Script                                            │
│   - ./scripts/deployment-helper.sh rollback both def456              │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
                    ▼                             ▼
┌──────────────────────────────┐  ┌──────────────────────────────┐
│   Rollback Server 131        │  │   Rollback Server 130        │
│   to def456                  │  │   to def456                  │
├──────────────────────────────┤  ├──────────────────────────────┤
│ SSH to 172.10.17.131         │  │ SSH to 172.10.17.130         │
│                              │  │                              │
│ 1. Login to Nexus            │  │ 1. Login to Nexus            │
│ 2. Pull nexus.../            │  │ 2. Pull nexus.../            │
│    airflow:def456            │  │    airflow:def456            │
│ 3. Update compose file       │  │ 3. Update compose file       │
│ 4. docker-compose up -d      │  │ 4. docker-compose up -d      │
└──────────────────────────────┘  └──────────────────────────────┘
                    │                             │
                    └──────────────┬──────────────┘
                                   ▼
                    ┌──────────────────────────────┐
                    │  Rollback Complete! ✅       │
                    │  Both servers running def456 │
                    └──────────────────────────────┘
```

## Version Lifecycle

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Nexus Registry                                  │
│                                                                      │
│  airflow-custom:abc123  ←──┐                                        │
│  airflow-custom:def456     │ Tagged with commit SHA                 │
│  airflow-custom:ghi789     │ (permanent reference)                  │
│  airflow-custom:jkl012     │                                        │
│  airflow-custom:mno345     │                                        │
│  airflow-custom:latest   ──┘ Always points to newest                │
│                                                                      │
│  Retention Policy:                                                  │
│  • Keep minimum 10 versions                                         │
│  • Delete after 30 days if > 10 versions                            │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ docker pull
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Server 130 & 131                                  │
│                                                                      │
│  Local Images (keeps last 5):                                       │
│  1. nexus.../airflow:abc123  ← current                              │
│  2. nexus.../airflow:def456  ← previous (for rollback)              │
│  3. nexus.../airflow:ghi789                                         │
│  4. nexus.../airflow:jkl012                                         │
│  5. nexus.../airflow:mno345                                         │
│                                                                      │
│  Older versions deleted automatically                                │
│  (can still pull from Nexus if needed)                              │
└─────────────────────────────────────────────────────────────────────┘
```

## Deployment Metadata Tracking

```
┌────────────────────────────────────────────────────────────────┐
│              /data/airflow-deployments/                        │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  current-deployment-130.json          New Deployment          │
│  ┌──────────────────────────┐               │                │
│  │ image: nexus.../airflow  │               ▼                │
│  │ tag: abc123              │         ┌──────────┐           │
│  │ commit: abc123def...     │  Copy   │          │           │
│  │ pipeline_id: 12345       │  ──────▶│  Backup  │           │
│  │ deployed_at: 2025-11-10  │         │          │           │
│  └──────────────────────────┘         └──────────┘           │
│              │                              │                │
│              │                              ▼                │
│              │                    previous-deployment-130    │
│              │                    .json                      │
│              │                    ┌──────────────────┐      │
│              │                    │ image: old-image │      │
│              │                    │ tag: def456      │      │
│              │                    │ ...              │      │
│              │                    └──────────────────┘      │
│              │                              │                │
│              │    Rollback                  │                │
│              │    Triggered                 │                │
│              ▼                              ▼                │
│         ┌────────────────────────────────────────┐          │
│         │  Swap: previous becomes current        │          │
│         │  Services restart with old version     │          │
│         └────────────────────────────────────────┘          │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

## Image Tag Strategy

```
Git Commit: abc123def456789
     │
     │ CI/CD Pipeline
     │
     ├─────────────────────────────────────────────┐
     │                                             │
     ▼                                             ▼
Docker Image Tags:                    Nexus Storage:
                                      
1. abc123                             nexus.../airflow:abc123
   (Short SHA)                        ↑ Primary reference
   Primary version tag                │ Used in production
                                      
2. latest                             nexus.../airflow:latest
   Always newest build                ↑ Always points to newest
   Good for testing                   │ Good for dev/testing
                                      
3. feature-xyz                        nexus.../airflow:feature-xyz
   Branch-based tag                   ↑ For feature branch testing
   (if not main branch)               │ Auto-updated per branch

Why Multiple Tags?
• abc123: Immutable, precise version tracking
• latest: Quick access to newest version
• feature-xyz: Test branches before merge
```

## Helper Script Operations Flow

```
┌──────────────────────────────────────────────────────────────────┐
│           deployment-helper.sh Commands                          │
└──────────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐  ┌──────────────────┐  ┌─────────────────┐
│ Information  │  │   Actions        │  │  Maintenance    │
│ Commands     │  │   Commands       │  │  Commands       │
└──────────────┘  └──────────────────┘  └─────────────────┘
        │                   │                   │
        ├─ list-versions    ├─ rollback         ├─ cleanup
        │  • Show all       │  • Revert to      │  • Remove old
        │    available      │    version        │    images
        │    versions       │                   │
        │                   │                   │
        ├─ current-version  ├─ health-check     │
        │  • Show active    │  • Check services │
        │    deployment     │  • Container      │
        │                   │    status         │
        │                   │                   │
        └─ logs             │                   │
           • View service   │                   │
             logs           │                   │
                           │                   │
                           ▼                   ▼
                    ┌──────────────────────────────┐
                    │  Executes SSH commands to    │
                    │  Server 130 or 131          │
                    │  • Secure key-based auth    │
                    │  • sudo -u developer        │
                    │  • Docker operations        │
                    └──────────────────────────────┘
```

## Security & Authentication Flow

```
┌───────────────────────────────────────────────────────────────────┐
│                    GitLab CI/CD                                    │
│  Variables (Masked):                                              │
│  • NEXUS_USERNAME                                                 │
│  • NEXUS_PASSWORD                                                 │
└───────────────────────────────────────────────────────────────────┘
                            │
                            │ SSH (port 3535)
                            │ Private key: /home/dataeng99/.ssh/...
                            │
        ┌───────────────────┼───────────────────┐
        │                                       │
        ▼                                       ▼
┌─────────────────┐                   ┌─────────────────┐
│  Server 130     │                   │  Server 131     │
│  172.10.17.130  │                   │  172.10.17.131  │
└─────────────────┘                   └─────────────────┘
        │                                       │
        │ Docker login nexus.../               │ Docker login nexus.../
        │ (credentials passed via pipeline)    │ (credentials passed via pipeline)
        │                                       │
        └───────────────────┬───────────────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │   Nexus Registry      │
                │  Authentication OK ✅ │
                │  Pull image allowed   │
                └───────────────────────┘

Note: Nexus docker login ONLY works on servers 130 & 131
      CI/CD runner does NOT have direct Nexus access
      That's why we authenticate ON the target servers
```

## Complete Disaster Recovery Flow

```
┌──────────────────────────────────────────────────────────────────┐
│            DISASTER: Complete Environment Loss                    │
└──────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│  Step 1: Identify Last Known Good Version                        │
│  • Check GitLab pipelines for last successful deployment        │
│  • Find commit SHA from deployment logs                          │
│  • Example: abc123                                               │
└──────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│  Step 2: Restore Infrastructure                                  │
│  SSH to each server:                                             │
│  1. docker login nexus.../                                       │
│  2. docker pull nexus.../airflow:abc123                          │
│  3. Restore docker-compose files from git                        │
│  4. Update image tag in compose files                            │
│  5. docker-compose up -d                                         │
└──────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│  Step 3: Restore Airflow Database (if needed)                   │
│  • mysql -h 172.10.17.131 airflow < backup.sql                   │
│  • Or initialize fresh: airflow db init                          │
└──────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│  Step 4: Verify & Test                                           │
│  • ./scripts/deployment-helper.sh health-check both              │
│  • Access Airflow UI                                             │
│  • Test critical DAGs                                            │
│  • Monitor logs                                                  │
└──────────────────────────────────────────────────────────────────┘
                            │
                            ▼
                   ┌────────────────┐
                   │   Recovery     │
                   │   Complete ✅  │
                   └────────────────┘
```
