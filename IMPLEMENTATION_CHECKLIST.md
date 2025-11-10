# Implementation Checklist

Use this checklist to implement the CI/CD pipeline for your Airflow deployment.

## Phase 1: Initial Setup

### ☐ 1.1 Configure GitLab CI/CD Variables
Go to GitLab → Your Project → Settings → CI/CD → Variables

Add the following variables:

| Variable Name | Value | Masked | Protected |
|---------------|-------|--------|-----------|
| `NEXUS_REGISTRY` | `nexus.yourcompany.com:8443` | No | No |
| `NEXUS_USERNAME` | Your Nexus service account username | No | Yes |
| `NEXUS_PASSWORD` | Your Nexus service account password | Yes | Yes |

**Action Items:**
- [ ] Create Nexus service account with push/pull permissions
- [ ] Add all three variables to GitLab
- [ ] Verify variables are saved correctly

---

### ☐ 1.2 Update Dockerfile
File: `airflow/docker/Dockerfile`

**Action Items:**
- [ ] Review the example Dockerfile
- [ ] Update base image version if needed: `FROM apache/airflow:2.7.3-python3.10`
- [ ] Add any system dependencies (apt packages)
- [ ] Customize environment variables

**Test locally:**
```bash
cd airflow
docker build -t test-airflow -f docker/Dockerfile .
docker run --rm test-airflow airflow version
```

---

### ☐ 1.3 Update Requirements
File: `airflow/requirements.txt`

**Action Items:**
- [ ] Add all Python packages your DAGs need
- [ ] Specify versions for stability
- [ ] Test locally:
```bash
pip install -r airflow/requirements.txt
```

---

### ☐ 1.4 Update Docker Compose Files

**Server 130** (`airflow/docker/docker-compose-server-130.yaml`):
- [ ] Copy from example file
- [ ] Update database connection string
- [ ] Update volume paths
- [ ] Set correct AIRFLOW_UID
- [ ] Update image reference to use Nexus:
  ```yaml
  image: nexus.yourcompany.com:8443/airflow-custom:latest
  ```

**Server 131** (`airflow/docker/docker-compose-server-131.yaml`):
- [ ] Copy from example file
- [ ] Update MySQL credentials
- [ ] Update volume paths
- [ ] Set correct AIRFLOW_UID
- [ ] Update image reference to use Nexus

---

### ☐ 1.5 Update GitLab CI Pipeline
File: `.gitlab-ci.yml`

**Action Items:**
- [ ] Update `NEXUS_REGISTRY` variable (if not using variables)
- [ ] Update `IMAGE_NAME` if you want different name
- [ ] Verify SSH paths match your setup:
  - SSH key: `/home/dataeng99/.ssh/dataeng99_id_rsa`
  - SSH port: `3535`
- [ ] Update docker-compose paths on servers
- [ ] Test SSH connection manually first:
```bash
ssh -p3535 -i /home/dataeng99/.ssh/dataeng99_id_rsa dataeng99@172.10.17.130 "echo 'Connection OK'"
```

---

## Phase 2: First Deployment

### ☐ 2.1 Commit Initial Changes
```bash
git add .gitlab-ci.yml
git add airflow/docker/Dockerfile
git add airflow/requirements.txt
git add airflow/docker/docker-compose-server-*.yaml
git commit -m "feat: Add Nexus-based CI/CD pipeline for Airflow"
git push origin main
```

---

### ☐ 2.2 Monitor Pipeline
1. Go to GitLab → CI/CD → Pipelines
2. Watch your pipeline:
   - [ ] ✅ Build stage completes
   - [ ] ✅ Push to Nexus completes
   - [ ] ✅ Deploy to Server 131 completes
   - [ ] ✅ Deploy to Server 130 completes

**If any stage fails:**
- Check the job logs
- Review the error messages
- Fix issues and re-push

---

### ☐ 2.3 Verify Deployment

**Check via helper script:**
```bash
chmod +x scripts/deployment-helper.sh
./scripts/deployment-helper.sh current-version both
./scripts/deployment-helper.sh health-check both
```

**Manual verification on servers:**

Server 130:
```bash
ssh -p3535 -i /home/dataeng99/.ssh/dataeng99_id_rsa dataeng99@172.10.17.130
sudo -u developer docker ps | grep airflow
```

Server 131:
```bash
ssh -p3535 -i /home/dataeng99/.ssh/dataeng99_id_rsa dataeng99@172.10.17.131
sudo -u developer docker ps | grep airflow
```

**Checklist:**
- [ ] All containers are running
- [ ] Airflow webserver accessible (http://server-130:8080)
- [ ] DAGs are visible in UI
- [ ] Scheduler is active (check heartbeat)
- [ ] Database connection working

---

## Phase 3: Test Rollback

### ☐ 3.1 Test Rollback to Previous Version

**Action Items:**
- [ ] Make a small change and deploy (create version 2)
- [ ] Go to GitLab pipeline
- [ ] Click "Play" on `rollback-server-130`
- [ ] Verify server 130 reverted to version 1
- [ ] Check logs: `./scripts/deployment-helper.sh logs 130 webserver`
- [ ] Verify services are healthy
- [ ] Redeploy version 2 when satisfied

---

### ☐ 3.2 Test Rollback to Specific Version

**Action Items:**
- [ ] Deploy multiple versions (3-4 deployments)
- [ ] List versions: `./scripts/deployment-helper.sh list-versions`
- [ ] Note a specific commit SHA (e.g., `abc123`)
- [ ] Go to GitLab → Pipeline → rollback-to-version
- [ ] Set variable: `ROLLBACK_TAG=abc123`
- [ ] Run the job
- [ ] Verify both servers are on specified version
- [ ] Confirm via: `./scripts/deployment-helper.sh current-version both`

---

## Phase 4: Configure Monitoring

### ☐ 4.1 Set Up Metadata Backup

**Create backup script on each server:**

```bash
# On Server 130
ssh -p3535 dataeng99@172.10.17.130
sudo -u developer crontab -e
# Add: 0 2 * * * cp /data/airflow-deployments/*.json /data/backups/airflow-deployments/$(date +\%Y\%m\%d)/
```

**Action Items:**
- [ ] Create backup directory on Server 130
- [ ] Create backup directory on Server 131
- [ ] Set up cron job for daily backups
- [ ] Test backup script manually

---

### ☐ 4.2 Configure Nexus Retention Policy

**In Nexus Repository Manager:**
- [ ] Go to Repository → Cleanup Policies
- [ ] Create new policy:
  - Name: `airflow-image-retention`
  - Criteria: Keep last 10 versions
  - Criteria: Delete after 30 days
- [ ] Apply to airflow-custom repository
- [ ] Schedule cleanup task (daily at 2 AM)

---

### ☐ 4.3 Set Up Alerts (Optional)

**GitLab Integration:**
- [ ] Configure Slack/Teams webhook for pipeline failures
- [ ] Go to GitLab → Settings → Integrations
- [ ] Add webhook URL
- [ ] Test notification

**Server Monitoring:**
- [ ] Set up disk space alerts (keep > 20% free)
- [ ] Monitor Docker daemon health
- [ ] Alert on container restart failures

---

## Phase 5: Documentation & Training

### ☐ 5.1 Team Documentation

**Action Items:**
- [ ] Share `README.md` with team
- [ ] Share `QUICK_START.md` for daily operations
- [ ] Document custom DAG requirements
- [ ] Create runbook for common issues

---

### ☐ 5.2 Update Team Runbooks

**Add to your runbooks:**
- [ ] Deployment procedures → Link to `QUICK_START.md`
- [ ] Rollback procedures → Link to `DEPLOYMENT_STRATEGY.md`
- [ ] Troubleshooting → Common issues section
- [ ] Emergency contacts

---

### ☐ 5.3 Train Team Members

**Training Checklist:**
- [ ] Walk through deployment process
- [ ] Demonstrate rollback (all 3 methods)
- [ ] Show helper script usage
- [ ] Practice emergency scenarios
- [ ] Assign backup personnel

---

## Phase 6: Advanced Configuration (Optional)

### ☐ 6.1 Automated Testing

**Add to `.gitlab-ci.yml`:**
- [ ] Add test stage after build
- [ ] Run unit tests for DAGs
- [ ] Validate Airflow configuration
- [ ] Run security scans on image

**Example:**
```yaml
test-dags:
  stage: test
  script:
    - pytest airflow/tests/
    - airflow dags list-import-errors
```

---

### ☐ 6.2 Staging Environment

**Setup:**
- [ ] Create separate staging servers
- [ ] Add staging deployment jobs to pipeline
- [ ] Deploy to staging before production
- [ ] Add manual approval gate

---

### ☐ 6.3 Blue-Green Deployment

**Advanced rollback strategy:**
- [ ] Set up duplicate infrastructure
- [ ] Add load balancer
- [ ] Implement traffic switching
- [ ] Zero-downtime deployments

---

## Maintenance Checklist

### Weekly Tasks
- [ ] Check disk space on servers: `df -h`
- [ ] Review deployment metadata
- [ ] Check for failed pipelines
- [ ] Review Nexus storage usage

### Monthly Tasks
- [ ] Rotate Nexus credentials
- [ ] Review and cleanup old images
- [ ] Test disaster recovery process
- [ ] Update dependencies (security patches)
- [ ] Review and update documentation

### Quarterly Tasks
- [ ] Full disaster recovery drill
- [ ] Review and optimize pipeline
- [ ] Update Dockerfile base image
- [ ] Security audit
- [ ] Team training refresh

---

## Troubleshooting Quick Reference

### Pipeline Fails at Build
```bash
# Test locally
docker build -t test -f airflow/docker/Dockerfile airflow/
# Check logs for specific error
```

### Pipeline Fails at Push
```bash
# Verify Nexus credentials in GitLab variables
# Check Nexus repository permissions
# Test push manually from GitLab runner
```

### Deployment Fails
```bash
# Check SSH connectivity
ssh -p3535 -i /home/dataeng99/.ssh/dataeng99_id_rsa dataeng99@172.10.17.130

# Check docker-compose on server
sudo -u developer docker-compose version

# Check Nexus login on server
sudo -u developer docker login nexus.yourcompany.com:8443
```

### Services Won't Start
```bash
# Check logs
./scripts/deployment-helper.sh logs 130 webserver

# Check container status
./scripts/deployment-helper.sh health-check both

# Rollback if needed
./scripts/deployment-helper.sh rollback both previous-tag
```

---

## Success Criteria

✅ **Deployment is successful when:**
- [ ] Pipeline completes all stages without errors
- [ ] Both servers show healthy containers
- [ ] Airflow UI is accessible
- [ ] DAGs are loaded and schedulable
- [ ] Scheduler heartbeat is active
- [ ] Deployment metadata is saved correctly
- [ ] Previous deployment is backed up

✅ **Rollback is successful when:**
- [ ] Previous version is restored within 5 minutes
- [ ] All services start successfully
- [ ] No data loss occurred
- [ ] DAGs continue running
- [ ] Metadata reflects correct version

✅ **Maintenance is successful when:**
- [ ] Disk usage < 80%
- [ ] Old images cleaned up (keeping last 5)
- [ ] Nexus has < 10 versions stored
- [ ] No stale containers running
- [ ] All documentation is up to date

---

## Support & Resources

- **Quick Start:** [QUICK_START.md](QUICK_START.md)
- **Full Documentation:** [DEPLOYMENT_STRATEGY.md](DEPLOYMENT_STRATEGY.md)
- **Flow Diagrams:** [CICD_FLOW_DIAGRAM.md](CICD_FLOW_DIAGRAM.md)
- **Helper Script:** `scripts/deployment-helper.sh`

---

**Last Updated:** 2025-11-10
**Version:** 1.0
**Maintained By:** Data Engineering Team
