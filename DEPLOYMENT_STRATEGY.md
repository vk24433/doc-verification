# Airflow CI/CD & Rollback Strategy

## Overview

This document describes the CI/CD pipeline strategy for deploying custom Airflow Docker images to two servers (130 and 131) using Nexus as the Docker registry.

## Architecture

```
┌─────────────────┐
│  GitLab CI/CD   │
│                 │
│  1. Build       │──┐
│  2. Push        │  │
│  3. Deploy      │  │
└─────────────────┘  │
                     │
                     ▼
         ┌─────────────────────┐
         │  Nexus Registry     │
         │  (Image Storage)    │
         └─────────────────────┘
                     │
            ┌────────┴────────┐
            ▼                 ▼
    ┌──────────────┐  ┌──────────────┐
    │  Server 130  │  │  Server 131  │
    │  Webserver   │  │  MySQL       │
    │  Scheduler1  │  │  Scheduler2  │
    └──────────────┘  └──────────────┘
```

## CI/CD Pipeline Stages

### Stage 1: Build
- Builds custom Airflow Docker image from Dockerfile
- Tags with:
  - Git commit SHA (for version tracking)
  - `latest` tag
  - Branch name (for feature branches)
- Saves as artifact for next stage

### Stage 2: Push to Nexus
- Loads built image from artifacts
- Authenticates to Nexus registry
- Pushes image with all tags
- Creates deployment metadata JSON file
- Stores metadata as artifact (30 days retention)

### Stage 3: Deploy to Servers
Two parallel deployment jobs:
- **deploy-ariflow-server-131**: MySQL + Scheduler2
- **deploy-ariflow-server-130**: Webserver + Scheduler1

Each deployment:
1. Authenticates to Nexus on target server
2. Pulls latest image from Nexus
3. Backs up current deployment metadata
4. Saves new deployment metadata
5. Updates docker-compose file with new image tag
6. Deploys using docker-compose
7. Cleans up old images (keeps last 5 versions)

### Stage 4: Rollback (Manual)
Three rollback options:
1. **rollback-server-130**: Rollback Server 130 to previous version
2. **rollback-server-131**: Rollback Server 131 to previous version
3. **rollback-to-version**: Rollback both servers to specific version

## Image Versioning Strategy

### Image Tags
Each image is tagged with multiple identifiers:

1. **Commit SHA Tag** (primary): `abc123def`
   - Used for tracking exact code version
   - Immutable reference to specific build

2. **Latest Tag**: `latest`
   - Always points to most recent build
   - Useful for quick testing

3. **Branch Tag**: `feature-new-dag`
   - Useful for testing feature branches
   - Automatically created for non-main branches

### Example Image Names
```
nexus.yourcompany.com:8443/airflow-custom:a1b2c3d
nexus.yourcompany.com:8443/airflow-custom:latest
nexus.yourcompany.com:8443/airflow-custom:feature-xyz
```

## Rollback Strategy

### Method 1: Rollback to Previous Deployment (Quickest)

**When to use**: When the latest deployment has issues and you need to quickly revert.

**How it works**:
- Each deployment stores metadata in `/data/airflow-deployments/`
- Previous deployment info is automatically backed up
- One-click rollback through manual pipeline job

**Steps**:
1. Go to GitLab pipeline
2. Click "Play" on `rollback-server-130` or `rollback-server-131`
3. Confirm the rollback

**What happens**:
- Reads previous deployment metadata
- Pulls that specific image version
- Redeploys using docker-compose
- Updates current deployment pointer

### Method 2: Rollback to Specific Version (Most Flexible)

**When to use**: When you need to rollback to a version older than the immediate previous one.

**How it works**:
- You specify exact image tag (commit SHA)
- Can rollback both servers or individual server
- Pulls specific version from Nexus

**Steps**:
1. Find the version you want to rollback to:
   ```bash
   ./scripts/deployment-helper.sh list-versions
   ```

2. Trigger rollback via GitLab:
   - Go to pipeline
   - Click "Play" on `rollback-to-version`
   - Set variable `ROLLBACK_TAG=abc123def`
   - Run the job

3. Or use helper script:
   ```bash
   ./scripts/deployment-helper.sh rollback both abc123def
   ```

### Method 3: Using Helper Script (Manual)

**When to use**: When GitLab is unavailable or for manual operations.

**Prerequisites**:
- Access to deployment server
- Nexus credentials set in environment

**Commands**:
```bash
# Check current versions
./scripts/deployment-helper.sh current-version both

# List available versions
./scripts/deployment-helper.sh list-versions 130

# Rollback single server
./scripts/deployment-helper.sh rollback 130 abc123def

# Rollback both servers
./scripts/deployment-helper.sh rollback both abc123def
```

## Deployment Metadata

Each deployment stores JSON metadata:

**Location**: 
- Server 130: `/data/airflow-deployments/current-deployment-130.json`
- Server 131: `/data/airflow-deployments/current-deployment-131.json`

**Format**:
```json
{
  "image": "nexus.yourcompany.com:8443/airflow-custom:abc123def",
  "tag": "abc123def",
  "commit": "abc123def456789",
  "branch": "main",
  "pipeline_id": "12345",
  "deployed_at": "2025-11-10T10:30:00Z"
}
```

**Backup**: Previous deployment automatically saved to `previous-deployment-{server}.json`

## Image Retention & Cleanup

### Automatic Cleanup
- Runs during each deployment
- Keeps last 5 image versions on each server
- Removes older versions to save disk space

### Manual Cleanup
```bash
./scripts/deployment-helper.sh cleanup both
```

### Nexus Retention
Configure in Nexus:
- Retention policy: 30 days
- Keep at least: 10 versions
- Cleanup task: Daily at 2 AM

## Helper Script Usage

### Installation
```bash
chmod +x scripts/deployment-helper.sh

# Set environment variables
export NEXUS_REGISTRY="nexus.yourcompany.com:8443"
export NEXUS_USERNAME="your-username"
export NEXUS_PASSWORD="your-password"
```

### Available Commands

#### List Available Versions
```bash
# List versions on specific server
./scripts/deployment-helper.sh list-versions 130

# List versions on both servers
./scripts/deployment-helper.sh list-versions
```

#### Check Current Deployment
```bash
# Check specific server
./scripts/deployment-helper.sh current-version 130

# Check both servers
./scripts/deployment-helper.sh current-version both
```

#### Health Check
```bash
# Check container health on both servers
./scripts/deployment-helper.sh health-check both

# Check specific server
./scripts/deployment-helper.sh health-check 130
```

#### View Logs
```bash
# View webserver logs on Server 130
./scripts/deployment-helper.sh logs 130 webserver

# View scheduler logs on Server 131
./scripts/deployment-helper.sh logs 131 scheduler
```

#### Cleanup Old Images
```bash
# Cleanup specific server
./scripts/deployment-helper.sh cleanup 130

# Cleanup both servers
./scripts/deployment-helper.sh cleanup both
```

## Configuration

### GitLab CI Variables
Set these in GitLab CI/CD settings:

| Variable | Description | Example |
|----------|-------------|---------|
| `NEXUS_REGISTRY` | Nexus Docker registry URL | `nexus.yourcompany.com:8443` |
| `NEXUS_USERNAME` | Nexus username | `ci-deployer` |
| `NEXUS_PASSWORD` | Nexus password (masked) | `*******` |
| `IMAGE_NAME` | Docker image name | `airflow-custom` |

### Docker Compose Update
Update your docker-compose files to use Nexus images:

**Before**:
```yaml
services:
  airflow-webserver:
    image: apache/airflow:2.7.3
```

**After**:
```yaml
services:
  airflow-webserver:
    image: nexus.yourcompany.com:8443/airflow-custom:${IMAGE_TAG}
```

Or use the CI pipeline to automatically update it.

## Deployment Workflow

### Normal Deployment
```
1. Developer commits code
   ↓
2. GitLab CI builds image
   ↓
3. Image pushed to Nexus with version tag
   ↓
4. Deployed to Server 131 (MySQL + Scheduler2)
   ↓
5. Deployed to Server 130 (Webserver + Scheduler1)
   ↓
6. Deployment metadata saved
   ↓
7. Old images cleaned up
```

### Rollback Workflow
```
1. Issue detected in production
   ↓
2. Trigger rollback job in GitLab
   ↓
3. Read previous deployment metadata
   ↓
4. Pull previous image from Nexus
   ↓
5. Redeploy using docker-compose
   ↓
6. Verify services are healthy
```

## Monitoring & Verification

### Post-Deployment Checks
```bash
# Check service health
./scripts/deployment-helper.sh health-check both

# Verify correct version deployed
./scripts/deployment-helper.sh current-version both

# Check logs for errors
./scripts/deployment-helper.sh logs 130 webserver
```

### Airflow UI Checks
1. Access Airflow UI: `http://server-130-ip:8080`
2. Verify DAGs are loaded
3. Check scheduler heartbeat
4. Test a sample DAG run

## Troubleshooting

### Issue: Image Pull Fails
**Symptoms**: `Error response from daemon: pull access denied`

**Solution**:
```bash
# Re-login to Nexus on target server
ssh -p3535 dataeng99@172.10.17.130
echo 'PASSWORD' | sudo -u developer docker login nexus.yourcompany.com:8443 -u USERNAME --password-stdin
```

### Issue: Docker Compose Fails
**Symptoms**: Service fails to start after deployment

**Solution**:
```bash
# Check logs
./scripts/deployment-helper.sh logs 130 webserver

# Verify docker-compose file
ssh -p3535 dataeng99@172.10.17.130 \
  "sudo -u developer cat /data/code/.../docker-compose-server-130.yaml"

# Manual rollback
./scripts/deployment-helper.sh rollback 130 previous-working-tag
```

### Issue: Metadata File Missing
**Symptoms**: Cannot rollback - no previous deployment found

**Solution**:
```bash
# Manually create metadata file with known good version
ssh -p3535 dataeng99@172.10.17.130
sudo -u developer bash -c "cat > /data/airflow-deployments/current-deployment-130.json << 'EOF'
{
  \"image\": \"nexus.yourcompany.com:8443/airflow-custom:abc123\",
  \"tag\": \"abc123\"
}
EOF"
```

## Best Practices

### 1. Always Test in Dev First
- Deploy to test environment before production
- Run smoke tests
- Verify DAG integrity

### 2. Monitor After Deployment
- Watch logs for 10-15 minutes post-deployment
- Check Airflow scheduler heartbeat
- Verify DAG runs

### 3. Keep Images Clean
- Run cleanup regularly
- Don't let disk space fill up
- Monitor Nexus storage

### 4. Document Changes
- Tag releases semantically
- Document breaking changes
- Update DAG documentation

### 5. Test Rollback Process
- Periodically test rollback
- Ensure metadata is being saved
- Verify old images are available

## Security Considerations

### Nexus Authentication
- Use service account for CI/CD
- Rotate credentials regularly
- Use masked variables in GitLab

### SSH Access
- Use SSH keys (not passwords)
- Restrict key permissions: `chmod 600`
- Audit SSH access logs

### Docker Security
- Scan images for vulnerabilities
- Use minimal base images
- Keep base images updated

## Disaster Recovery

### Complete Environment Loss

1. **Rebuild from scratch**:
   ```bash
   # Pull specific version from Nexus
   docker pull nexus.yourcompany.com:8443/airflow-custom:abc123
   
   # Redeploy infrastructure
   docker-compose up -d
   ```

2. **Restore Airflow metadata** (if backed up):
   ```bash
   # Restore from backup
   mysql -h 172.10.17.131 airflow < airflow_backup.sql
   ```

3. **Verify DAGs**:
   - Check DAG folder sync
   - Verify connections
   - Test critical DAGs

## Future Enhancements

1. **Blue-Green Deployment**
   - Run new version alongside old
   - Switch traffic after validation
   - Zero-downtime deployment

2. **Canary Deployment**
   - Deploy to subset of servers first
   - Monitor metrics
   - Gradually roll out

3. **Automated Testing**
   - Add integration tests in CI
   - Automated DAG validation
   - Smoke tests post-deployment

4. **Monitoring & Alerts**
   - Set up Prometheus/Grafana
   - Alert on deployment failures
   - Track deployment metrics

## Contact & Support

For issues or questions:
- Data Engineering Team: [your-team-channel]
- On-call: [pager-duty-link]
- Documentation: [wiki-link]
