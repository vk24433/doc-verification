# Setup Checklist

Use this checklist to set up the deployment pipeline in your environment.

## ☑️ Pre-requisites

### Access & Permissions
- [ ] SSH access to Server 131 (172.10.17.131)
- [ ] SSH access to Server 130 (172.10.17.130)
- [ ] SSH key file available: `/home/dataeng99/.ssh/dataeng99_id_rsa`
- [ ] User `dataeng99` can SSH to both servers
- [ ] User `developer` has Docker permissions on both servers
- [ ] GitLab repository access with CI/CD enabled

### Infrastructure
- [ ] Docker installed on both servers
- [ ] Docker Compose binary at `/data/binaries/docker-compose`
- [ ] Code base path exists: `/data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow`
- [ ] Git repository accessible from both servers
- [ ] Nexus registry accessible (optional for MVP)

### Network & Connectivity
- [ ] Server 131 can reach Server 130 via SSH
- [ ] Port 39100 open on Server 130 (Webserver)
- [ ] Port 33307 open on Server 131 (MySQL)
- [ ] Outbound internet access for Docker Hub (base images)
- [ ] Outbound internet access for PyPI (pip packages)

---

## ☑️ File Setup

### 1. Copy Files to Repository
- [ ] Copy `airflow-ci.yml` to repository root or `.gitlab-ci.yml`
- [ ] Copy `Dockerfile` to `airflow/docker/Dockerfile`
- [ ] Copy `docker-compose-server-130.yaml` to `airflow/docker/`
- [ ] Copy `docker-compose-server-131.yaml` to `airflow/docker/`
- [ ] Copy `deploy-helper.sh` to repository root
- [ ] Make `deploy-helper.sh` executable: `chmod +x deploy-helper.sh`
- [ ] Copy `.env.example` to `.env` and customize (for local testing)

### 2. Update Configuration
- [ ] Update `airflow-ci.yml` variables (if needed):
  - `NEXUS_REGISTRY`
  - `SERVER_131_HOST` / `SERVER_130_HOST`
  - `SSH_PORT`, `SSH_USER`, `SSH_KEY`
  - `CODE_BASE_PATH`
  - `DOCKER_COMPOSE_BIN`

- [ ] Update `docker-compose-server-130.yaml`:
  - Verify volume paths match your environment
  - Update webserver health check URL if needed
  - Confirm ports are correct

- [ ] Update `docker-compose-server-131.yaml`:
  - Verify MySQL volume paths
  - Confirm database credentials match your setup
  - Check MySQL port (33307)

- [ ] Update `Dockerfile`:
  - Review Python package versions
  - Add any additional dependencies
  - Update timezone if needed

---

## ☑️ GitLab CI/CD Configuration

### 1. GitLab Variables (Settings → CI/CD → Variables)

Add these variables (mark as **protected** and **masked** where appropriate):

#### Required for Nexus Push (Optional for MVP)
- [ ] `NEXUS_REGISTRY` - Your Nexus registry URL
  - Example: `nexus.yourcompany.com:8082`
  - Type: Variable
  - Masked: No

- [ ] `NEXUS_REPO` - Nexus repository name
  - Example: `docker-releases`
  - Type: Variable
  - Masked: No

- [ ] `NEXUS_USERNAME` - Nexus authentication username
  - Type: Variable
  - Protected: Yes
  - Masked: Yes

- [ ] `NEXUS_PASSWORD` - Nexus authentication password
  - Type: Variable
  - Protected: Yes
  - Masked: Yes

#### Optional Variables (can override CI file defaults)
- [ ] `IMAGE_NAME` - Custom image name (default: `airflow-custom`)
- [ ] `SERVER_131_HOST` - Override Server 131 IP
- [ ] `SERVER_130_HOST` - Override Server 130 IP

### 2. GitLab Runner Configuration
- [ ] Verify GitLab runner has network access to servers
- [ ] Verify runner has SSH key or can access SSH key path
- [ ] Test runner can execute SSH commands:
  ```bash
  ssh -p3535 dataeng99@172.10.17.131 "echo test"
  ```

### 3. Pipeline Rules
- [ ] Review `rules:` section in `airflow-ci.yml`
- [ ] Pipeline triggers on changes to:
  - `airflow/docker/**`
  - `airflow/config/**`
  - `airflow/dags/**`
  - `airflow/airflow-ci.yml`
- [ ] Adjust if needed for your repository structure

---

## ☑️ Initial Setup on Servers

### Server 131 (172.10.17.131)

```bash
# Connect to server
ssh -p3535 dataeng99@172.10.17.131

# Verify Docker
sudo -u developer docker --version
sudo -u developer docker-compose --version

# Verify code base path
cd /data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow
git status

# Create required directories (if not exist)
sudo -u developer mkdir -p mysql_8.0/mysqldb
sudo -u developer mkdir -p mysql_8.0/blogs
sudo -u developer mkdir -p mysql_8.0/config
sudo -u developer mkdir -p mysql_8.0/init
sudo -u developer mkdir -p logs
sudo -u developer mkdir -p dags

# Verify permissions
ls -la mysql_8.0/
ls -la logs/

# Test Docker Compose
cd /data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow
export CUSTOM_IMAGE_TAG=2.11.0-python3.9  # Use public image for test
sudo -u developer /data/binaries/docker-compose -f docker/docker-compose-server-131.yaml config
```

### Server 130 (172.10.17.130)

```bash
# Connect to server
ssh -p3535 dataeng99@172.10.17.130

# Verify Docker
sudo -u developer docker --version
sudo -u developer docker-compose --version

# Verify code base path
cd /data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow
git status

# Create required directories (if not exist)
sudo -u developer mkdir -p logs
sudo -u developer mkdir -p dags

# Verify permissions
ls -la logs/

# Test Docker Compose
cd /data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow
export CUSTOM_IMAGE_TAG=2.11.0-python3.9  # Use public image for test
sudo -u developer /data/binaries/docker-compose -f docker/docker-compose-server-130.yaml config
```

---

## ☑️ Test Basic Connectivity

### From GitLab Runner (or your workstation)

```bash
# Test SSH to Server 131
ssh -p3535 -i /home/dataeng99/.ssh/dataeng99_id_rsa dataeng99@172.10.17.131 "echo OK"

# Test SSH to Server 130
ssh -p3535 -i /home/dataeng99/.ssh/dataeng99_id_rsa dataeng99@172.10.17.130 "echo OK"

# Test Docker access on Server 131
ssh -p3535 -i /home/dataeng99/.ssh/dataeng99_id_rsa dataeng99@172.10.17.131 \
  "sudo -u developer docker ps"

# Test Docker access on Server 130
ssh -p3535 -i /home/dataeng99/.ssh/dataeng99_id_rsa dataeng99@172.10.17.130 \
  "sudo -u developer docker ps"

# Test image transfer (Server 131 → 130)
ssh -p3535 dataeng99@172.10.17.131 \
  "sudo -u developer docker pull hello-world && \
   sudo -u developer docker save hello-world | \
   ssh -p3535 dataeng99@172.10.17.130 'sudo -u developer docker load'"
```

---

## ☑️ First Deployment (Manual Test)

### 1. Build Custom Image

```bash
# On Server 131
ssh -p3535 dataeng99@172.10.17.131
cd /data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow/docker

sudo -u developer docker build \
  --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --build-arg VCS_REF="$(git rev-parse --short HEAD)" \
  --build-arg VERSION="test-$(date +%Y%m%d)" \
  -t airflow-custom:test-$(date +%Y%m%d) \
  -t airflow-custom:latest-temp \
  -f Dockerfile .

# Verify image
sudo -u developer docker images | grep airflow-custom
```

### 2. Test Deploy on Server 131

```bash
# On Server 131
cd /data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow

export CUSTOM_IMAGE_NAME=airflow-custom
export CUSTOM_IMAGE_TAG=latest-temp

# Stop old containers (if any)
sudo -u developer /data/binaries/docker-compose \
  -f docker/docker-compose-server-131.yaml down

# Start with new image
sudo -u developer /data/binaries/docker-compose \
  -f docker/docker-compose-server-131.yaml up -d

# Check status
sudo -u developer docker ps

# Check logs
sudo -u developer docker logs airflow_2.11-scheduler_2
sudo -u developer docker logs airflow_2.11-mysql_8.0

# Wait for health (manually check)
watch 'sudo -u developer docker ps'
```

### 3. Test Deploy on Server 130

```bash
# Transfer image from 131 to 130
ssh -p3535 dataeng99@172.10.17.131 \
  "sudo -u developer docker save airflow-custom:latest-temp | \
   ssh -p3535 dataeng99@172.10.17.130 'sudo -u developer docker load'"

# On Server 130
ssh -p3535 dataeng99@172.10.17.130
cd /data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow

export CUSTOM_IMAGE_NAME=airflow-custom
export CUSTOM_IMAGE_TAG=latest-temp

# Stop old containers (if any)
sudo -u developer /data/binaries/docker-compose \
  -f docker/docker-compose-server-130.yaml down

# Start with new image
sudo -u developer /data/binaries/docker-compose \
  -f docker/docker-compose-server-130.yaml up -d

# Check status
sudo -u developer docker ps

# Check logs
sudo -u developer docker logs airflow_2.11-webserver
sudo -u developer docker logs airflow_2.11-scheduler_1

# Test webserver
curl http://localhost:39100/health
```

### 4. Verify Airflow is Working

```bash
# Access webserver
open http://172.10.17.130:39100

# Login with admin/airflow (default)

# Check that:
# - Login works
# - DAGs are visible
# - Scheduler is running
# - Can trigger a DAG
```

---

## ☑️ First Automated Deployment

### 1. Prepare Code
- [ ] Commit all changes to Git
- [ ] Push to GitLab
- [ ] Verify pipeline starts automatically

### 2. Monitor Pipeline
- [ ] Go to GitLab → CI/CD → Pipelines
- [ ] Watch each stage:
  1. validate-docker-config
  2. backup-current-state
  3. update-code-servers
  4. build-docker-image
  5. deploy-server-131
  6. deploy-server-130
  7. promote-and-push-image

### 3. Verify Success
- [ ] All stages pass (green)
- [ ] Check webserver: http://172.10.17.130:39100
- [ ] Verify new image tagged as stable:
  ```bash
  ssh dataeng99@172.10.17.131 "sudo -u developer docker images | grep stable"
  ```

---

## ☑️ Test Rollback Mechanism

### 1. Trigger a Failure (Controlled Test)

```bash
# Option 1: Break Dockerfile temporarily
# Add invalid syntax to Dockerfile
RUN thiswillfail

# Commit and push
git add airflow/docker/Dockerfile
git commit -m "Test: Trigger rollback"
git push
```

### 2. Watch Rollback
- [ ] Pipeline should fail at build stage
- [ ] Rollback stage should trigger automatically
- [ ] Verify services still running on stable image

### 3. Clean Up
- [ ] Revert bad commit
- [ ] Push fix
- [ ] Verify deployment succeeds

---

## ☑️ Helper Script Setup

### 1. Local Setup

```bash
# Copy script to your workstation
scp -P 3535 dataeng99@172.10.17.131:/path/to/deploy-helper.sh .

# Make executable
chmod +x deploy-helper.sh

# Test commands
./deploy-helper.sh status both
```

### 2. Server Setup (Optional)

```bash
# On Server 131
cd /data/code/99acres_analytics/data_lake_tools/data-platform-applications/airflow
chmod +x deploy-helper.sh

# Test
./deploy-helper.sh status 131
```

---

## ☑️ Monitoring & Alerts

### Set Up Monitoring (Recommended)
- [ ] Create Grafana dashboard for:
  - Container health status
  - Deployment frequency
  - Success/failure rate
  - Rollback frequency

- [ ] Set up alerts for:
  - Failed deployments
  - Unhealthy containers
  - Scheduler not running
  - Webserver not responding

### Notifications
- [ ] Configure Slack webhook (if using)
- [ ] Add notification job to pipeline
- [ ] Test notifications

---

## ☑️ Documentation & Training

### Team Onboarding
- [ ] Share documentation with team:
  - [README.md](./README.md)
  - [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md)
  - [QUICK_REFERENCE.md](./QUICK_REFERENCE.md)

- [ ] Conduct training session covering:
  - Deployment flow
  - How to trigger deployment
  - How to check status
  - How to rollback manually
  - Troubleshooting basics

- [ ] Add contacts and escalation paths to docs

### Runbook
- [ ] Create runbook for common scenarios:
  - Failed deployment
  - Database issues
  - Performance problems
  - Emergency rollback

---

## ☑️ Security Review

### Access Control
- [ ] Review SSH key permissions
- [ ] Verify only necessary users have access
- [ ] Check GitLab CI/CD variable protection
- [ ] Review sudo permissions for `developer` user

### Secrets Management
- [ ] Ensure no secrets in code
- [ ] All secrets in GitLab CI/CD variables
- [ ] Database passwords properly secured
- [ ] AWS credentials properly mounted (read-only)

### Network Security
- [ ] Verify firewall rules
- [ ] Check container network isolation
- [ ] Review exposed ports
- [ ] Ensure MySQL not publicly accessible

---

## ☑️ Backup & Recovery

### Database Backup
- [ ] Set up regular MySQL backups
- [ ] Test restore procedure
- [ ] Document backup location and retention

### Image Backup
- [ ] Verify Nexus registry is working (if using)
- [ ] Keep stable images on both servers
- [ ] Document image retention policy

### Configuration Backup
- [ ] Ensure all config in Git
- [ ] Backup `/data/code` directory
- [ ] Document recovery procedure

---

## ☑️ Performance Tuning

### Initial Benchmarks
- [ ] Measure deployment time
- [ ] Measure health check time
- [ ] Measure image transfer time
- [ ] Document baseline metrics

### Optimization (Optional)
- [ ] Consider image layer caching
- [ ] Evaluate parallel operations
- [ ] Review health check intervals
- [ ] Optimize Dockerfile build

---

## ☑️ Final Checks

### Deployment Verification
- [ ] Run full deployment end-to-end
- [ ] Verify all stages complete successfully
- [ ] Check all containers healthy
- [ ] Test Airflow functionality

### Documentation
- [ ] All placeholders updated (`{your-nexus-url}`, etc.)
- [ ] Team contacts added
- [ ] Runbook complete
- [ ] FAQ addresses common issues

### Handoff
- [ ] Knowledge transfer to operations team
- [ ] On-call procedures documented
- [ ] Escalation paths defined
- [ ] Success criteria agreed upon

---

## 🎉 Ready for Production

Once all items are checked:
- [ ] Mark this setup as production-ready
- [ ] Schedule first production deployment
- [ ] Ensure on-call coverage
- [ ] Monitor closely for first week

---

## 📝 Notes & Issues

Use this section to track any issues or customizations during setup:

```
Date: ___________
Issue: 
Resolution:

Date: ___________
Issue:
Resolution:

```

---

**Setup Date**: _____________
**Setup By**: _____________
**Reviewed By**: _____________
**Production Date**: _____________
