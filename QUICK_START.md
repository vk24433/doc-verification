# Quick Start Guide - Airflow Custom Image Deployment

## Prerequisites

### 1. Configure GitLab CI Variables
Go to GitLab Project → Settings → CI/CD → Variables and add:

```
NEXUS_REGISTRY = nexus.yourcompany.com:8443
NEXUS_USERNAME = your-nexus-username  
NEXUS_PASSWORD = your-nexus-password (masked)
```

### 2. Update Dockerfile
Edit `airflow/docker/Dockerfile` with your custom requirements.

### 3. Update Requirements
Edit `airflow/requirements.txt` with your Python dependencies.

## First Deployment

### Step 1: Commit Your Changes
```bash
git add airflow/docker/Dockerfile airflow/requirements.txt
git commit -m "Add custom Airflow image configuration"
git push origin main
```

### Step 2: Watch Pipeline
1. Go to GitLab → CI/CD → Pipelines
2. Watch the pipeline progress:
   - ✅ Build stage (builds Docker image)
   - ✅ Push to Nexus stage (pushes to registry)
   - ✅ Deploy to Server 131
   - ✅ Deploy to Server 130

### Step 3: Verify Deployment
```bash
# Check current versions
./scripts/deployment-helper.sh current-version both

# Check service health
./scripts/deployment-helper.sh health-check both
```

## Common Operations

### Deploy Latest Changes
```bash
# Make your changes
vim airflow/docker/Dockerfile

# Commit and push
git add .
git commit -m "Update Airflow dependencies"
git push

# Pipeline runs automatically
```

### Rollback to Previous Version
**Option 1: GitLab UI (Easiest)**
1. Go to GitLab → CI/CD → Pipelines → Latest Pipeline
2. Find "Rollback" stage
3. Click ▶️ play button on `rollback-server-130` or `rollback-server-131`

**Option 2: Command Line**
```bash
# Rollback Server 130
./scripts/deployment-helper.sh rollback 130 abc123def

# Rollback both servers
./scripts/deployment-helper.sh rollback both abc123def
```

### Check Deployment Status
```bash
# View current deployed versions
./scripts/deployment-helper.sh current-version both

# View available image versions
./scripts/deployment-helper.sh list-versions

# Check service health
./scripts/deployment-helper.sh health-check both
```

### View Logs
```bash
# Webserver logs (Server 130)
./scripts/deployment-helper.sh logs 130 webserver

# Scheduler logs (Server 131)  
./scripts/deployment-helper.sh logs 131 scheduler

# MySQL logs (Server 131)
./scripts/deployment-helper.sh logs 131 mysql
```

## Troubleshooting

### Pipeline Fails at Build Stage
**Check**: Dockerfile syntax or missing dependencies
```bash
# Test build locally
cd airflow/docker
docker build -t test-airflow -f Dockerfile .
```

### Pipeline Fails at Push Stage
**Check**: Nexus credentials
- Verify `NEXUS_USERNAME` and `NEXUS_PASSWORD` in GitLab variables
- Ensure credentials have push permissions

### Deployment Fails
**Check**: SSH connectivity and docker-compose
```bash
# Test SSH connection
ssh -p3535 -i /home/dataeng99/.ssh/dataeng99_id_rsa dataeng99@172.10.17.130

# Check docker-compose on server
sudo -u developer docker-compose version
```

### Services Won't Start
**Check logs**:
```bash
./scripts/deployment-helper.sh logs 130 webserver
```

**Rollback if needed**:
```bash
./scripts/deployment-helper.sh rollback 130 previous-working-tag
```

## Emergency Rollback

If something goes wrong immediately after deployment:

### Using GitLab (Fastest)
1. Go to current pipeline
2. Click ▶️ on `rollback-server-130` 
3. Click ▶️ on `rollback-server-131`

### Using Command Line
```bash
# Set credentials
export NEXUS_USERNAME="your-username"
export NEXUS_PASSWORD="your-password"

# Rollback both servers
./scripts/deployment-helper.sh rollback both abc123def
```

### Manual Rollback (if script fails)
```bash
# SSH to server
ssh -p3535 -i /home/dataeng99/.ssh/dataeng99_id_rsa dataeng99@172.10.17.130

# Login to Nexus
echo 'PASSWORD' | sudo -u developer docker login nexus.yourcompany.com:8443 -u USERNAME --password-stdin

# Pull previous version
sudo -u developer docker pull nexus.yourcompany.com:8443/airflow-custom:abc123

# Update compose file
sudo -u developer sed -i 's|image:.*airflow.*|image: nexus.yourcompany.com:8443/airflow-custom:abc123|g' \
  /data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow/docker/docker-compose-server-130.yaml

# Redeploy
sudo -u developer /data/binaries/docker-compose \
  -f /data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow/docker/docker-compose-server-130.yaml \
  up -d
```

## Helper Script Reference

```bash
# List all commands
./scripts/deployment-helper.sh help

# Common commands
./scripts/deployment-helper.sh list-versions [130|131]
./scripts/deployment-helper.sh current-version [130|131|both]
./scripts/deployment-helper.sh rollback [130|131|both] [tag]
./scripts/deployment-helper.sh health-check [130|131|both]
./scripts/deployment-helper.sh logs [130|131] [service]
./scripts/deployment-helper.sh cleanup [130|131|both]
```

## Next Steps

1. Read full documentation: [DEPLOYMENT_STRATEGY.md](DEPLOYMENT_STRATEGY.md)
2. Set up monitoring and alerts
3. Test rollback process in non-production
4. Document your custom DAGs and configurations

## Support

- Data Engineering Team: [team-channel]
- Documentation: [wiki]
- On-call: [pager-duty]
