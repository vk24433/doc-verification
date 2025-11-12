# Airflow Multi-Server Deployment Guide

## Overview

This deployment strategy provides a robust CI/CD pipeline for deploying custom Airflow images across two servers (130 and 131) with automatic health checks, rollback capabilities, and image promotion to a Nexus registry.

## Architecture

### Server Configuration

- **Server 131 (172.10.17.131)**: MySQL Database + Scheduler 2
- **Server 130 (172.10.17.130)**: Webserver + Scheduler 1

### Deployment Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     1. Validate & Backup                        │
│  • Validate Dockerfile and compose files                       │
│  • Backup current deployment state                             │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                     2. Update Code                              │
│  • Pull latest code on Server 131                              │
│  • Pull latest code on Server 130                              │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                     3. Build Image                              │
│  • Build custom Docker image on Server 131                     │
│  • Tag as [commit-sha]-temp                                    │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                4. Deploy Server 131                             │
│  • Stop existing containers                                    │
│  • Start with new image                                        │
│  • Health check: MySQL + Scheduler 2                           │
│  • Check restart count, health status                          │
│  • Rollback on failure                                         │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                5. Deploy Server 130                             │
│  • Transfer image from Server 131                              │
│  • Stop existing containers                                    │
│  • Start with new image                                        │
│  • Health check: Webserver + Scheduler 1                       │
│  • Verify webserver responding (HTTP 200)                      │
│  • Rollback on failure                                         │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                6. Promote & Push                                │
│  • Tag image as [commit-sha]-stable                            │
│  • Tag as latest-stable                                        │
│  • Push to Nexus registry                                      │
│  • Cleanup old temp images                                     │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│              7. Automatic Rollback (on failure)                 │
│  • Revert code to previous commit                              │
│  • Deploy previous stable image on both servers                │
│  • Notify team of failure                                      │
└─────────────────────────────────────────────────────────────────┘
```

## Deployment Stages

### Stage 1: Validate & Backup

**Purpose**: Ensure all configuration files are present and backup current state

**Actions**:
- Validate Dockerfile exists
- Validate docker-compose files exist
- Capture current image tags
- Record container states
- Create backup metadata

**Success Criteria**: All validation checks pass

---

### Stage 2: Update Code

**Purpose**: Synchronize code on both servers with the latest commit

**Actions**:
- Update Server 131 to commit SHA
- Update Server 130 to commit SHA
- Verify git checkout successful

**Success Criteria**: Code updated on both servers

**Rollback**: If update fails, deployment stops (code remains at previous version)

---

### Stage 3: Build Image

**Purpose**: Create custom Docker image with all dependencies

**Actions**:
- Build Docker image on Server 131 (master build server)
- Tag as `{IMAGE_NAME}:{COMMIT_SHA}-temp`
- Tag as `{IMAGE_NAME}:latest-temp`
- Verify image created successfully

**Custom Image Includes**:
- Base: `apache/airflow:2.11.0-python3.9`
- Timezone: Asia/Calcutta
- System packages: jq, nano, clickhouse-client
- Python packages: PyMySQL, awscli, pymsteams, kafka-python, pika, pyathena, pyspark, acryl-datahub

**Success Criteria**: Image built and tagged

**Rollback**: If build fails, deployment stops

---

### Stage 4: Deploy Server 131

**Purpose**: Deploy and validate on Server 131 (MySQL + Scheduler 2)

**Actions**:
1. Stop existing containers gracefully
2. Start containers with temp image
3. Wait 30s for initialization
4. Perform health checks (5 retries, 15s interval)

**Health Checks**:
- ✅ Restart count = 0
- ✅ No unhealthy containers
- ✅ No exited/dead containers
- ✅ Expected containers running (2/2)
- ✅ Scheduler job is active

**Containers Monitored**:
- `airflow_2.11-mysql_8.0`
- `airflow_2.11-scheduler_2`

**Success Criteria**: All health checks pass

**Rollback**: On failure, revert to stable image on Server 131

---

### Stage 5: Deploy Server 130

**Purpose**: Deploy and validate on Server 130 (Webserver + Scheduler 1)

**Actions**:
1. Transfer image from Server 131 to Server 130
2. Stop existing containers gracefully
3. Start containers with temp image
4. Wait 30s for initialization
5. Perform health checks (5 retries, 15s interval)

**Health Checks**:
- ✅ Restart count = 0
- ✅ No unhealthy containers
- ✅ No exited/dead containers
- ✅ Expected containers running (2/2)
- ✅ Webserver responding (HTTP 200 on `/health`)
- ✅ Scheduler job is active

**Containers Monitored**:
- `airflow_2.11-webserver`
- `airflow_2.11-scheduler_1`

**Success Criteria**: All health checks pass

**Rollback**: On failure, revert to stable image on both servers

---

### Stage 6: Promote & Push

**Purpose**: Mark deployment as stable and publish to registry

**Actions**:
1. Tag image as `{IMAGE_NAME}:{COMMIT_SHA}-stable`
2. Tag image as `{IMAGE_NAME}:latest-stable`
3. Tag for Nexus: `{NEXUS_REGISTRY}/{NEXUS_REPO}/{IMAGE_NAME}:{COMMIT_SHA}`
4. Push to Nexus registry
5. Clean up old temp images (keep last 3)

**Success Criteria**: Image pushed to Nexus

---

### Stage 7: Automatic Rollback

**Purpose**: Restore previous stable state on any failure

**Trigger**: When any previous stage fails

**Actions**:
1. Identify previous stable commit
2. Checkout previous commit on both servers
3. Find latest stable image
4. Deploy stable image on Server 131
5. Deploy stable image on Server 130
6. Exit pipeline with failure status

**Success Criteria**: Both servers running previous stable version

---

## Health Check Details

### What We Check

1. **Restart Count**: Containers should not be restarting
   - Uses Docker's restart count metric
   - Sum across all monitored containers must be 0

2. **Container Health**: All containers must be healthy
   - No containers in "unhealthy" state
   - No containers in "exited" or "dead" state
   - All expected containers in "running" state

3. **Application Health**: Services must be functional
   - Schedulers: `airflow jobs check --job-type SchedulerJob`
   - Webserver: HTTP GET to `/health` endpoint returns 200

### Health Check Script Logic

```bash
for i in $(seq 1 $MAX_RETRIES); do
    # Check restarts
    RESTARTS=$(docker inspect --format '{{.RestartCount}}' | sum)
    
    # Check unhealthy
    UNHEALTHY=$(docker ps --filter health=unhealthy)
    
    # Check exited
    EXITED=$(docker ps -a --filter status=exited)
    
    # Count running
    RUNNING_COUNT=$(docker ps --filter status=running | count)
    
    if [ $RESTARTS -eq 0 ] && 
       [ -z "$UNHEALTHY" ] && 
       [ -z "$EXITED" ] && 
       [ $RUNNING_COUNT -eq EXPECTED ]; then
        ✅ SUCCESS
    else
        ⚠️ RETRY after sleep
    fi
done
```

---

## Configuration

### Docker Compose Changes

**Before** (using public image):
```yaml
x-airflow-common: &common_airflow
  image: apache/airflow:2.11.0-python3.9
```

**After** (using custom image):
```yaml
x-airflow-common: &common_airflow
  image: ${CUSTOM_IMAGE_NAME:-airflow-custom}:${CUSTOM_IMAGE_TAG:-latest-stable}
```

### Environment Variables

Set these in your GitLab CI/CD variables or `.env` file:

```bash
# Image configuration
CUSTOM_IMAGE_NAME=airflow-custom
CUSTOM_IMAGE_TAG=latest-stable  # or specific tag like 20240112-stable

# Server configuration
SERVER_131_HOST=172.10.17.131
SERVER_130_HOST=172.10.17.130

# Nexus registry
NEXUS_REGISTRY=your-nexus-registry.com
NEXUS_REPO=docker-releases
```

---

## Manual Deployment

### Using Helper Script

The `deploy-helper.sh` script provides manual deployment utilities:

```bash
# Build image
./deploy-helper.sh build

# Deploy to a server
./deploy-helper.sh deploy 131 20240112-temp
./deploy-helper.sh deploy 130 20240112-temp
./deploy-helper.sh deploy both 20240112-temp

# Check health
./deploy-helper.sh health-check 131
./deploy-helper.sh health-check 130

# Check status
./deploy-helper.sh status both

# Rollback
./deploy-helper.sh rollback 131
./deploy-helper.sh rollback both

# Cleanup old images
./deploy-helper.sh cleanup both
```

### Manual Step-by-Step

1. **Build Image on Server 131**:
```bash
ssh -p3535 dataeng99@172.10.17.131
cd /data/code/.../airflow/docker
sudo -u developer docker build -t airflow-custom:$(date +%Y%m%d)-temp -f Dockerfile .
```

2. **Deploy Server 131**:
```bash
cd /data/code/.../airflow
export CUSTOM_IMAGE_TAG="20240112-temp"
sudo -u developer docker-compose -f docker/docker-compose-server-131.yaml down
sudo -u developer docker-compose -f docker/docker-compose-server-131.yaml up -d
```

3. **Transfer Image to Server 130**:
```bash
ssh dataeng99@172.10.17.131
sudo -u developer docker save airflow-custom:20240112-temp | \
  ssh dataeng99@172.10.17.130 'sudo -u developer docker load'
```

4. **Deploy Server 130**:
```bash
ssh -p3535 dataeng99@172.10.17.130
cd /data/code/.../airflow
export CUSTOM_IMAGE_TAG="20240112-temp"
sudo -u developer docker-compose -f docker/docker-compose-server-130.yaml down
sudo -u developer docker-compose -f docker/docker-compose-server-130.yaml up -d
```

---

## Improvements & Best Practices

### ✅ Implemented

1. **Immutable Image Tags**: Each build uses commit SHA, preventing tag confusion
2. **Two-Stage Tagging**: temp → stable promotion ensures validation before commitment
3. **Comprehensive Health Checks**: Multi-layered validation (Docker + application level)
4. **Automatic Rollback**: On any failure, automatically restore previous state
5. **Code Synchronization**: Ensures code and image are aligned
6. **Backup Metadata**: Creates audit trail of deployments
7. **Image Cleanup**: Automatically removes old images
8. **Docker Compose Dependencies**: Proper `depends_on` with health checks

### 🎯 Recommended Additions

1. **Pre-deployment Testing**:
   ```yaml
   test-image:
     stage: test
     script:
       - Run smoke tests on built image
       - Test DAG validation
       - Check Python import errors
   ```

2. **Slack/Teams Notifications**:
   ```yaml
   after_script:
     - Send notification to team channel
     - Include deployment status, image tag, commit SHA
   ```

3. **Database Migration Safety**:
   ```yaml
   # Before deployment
   - Backup Airflow database
   - Test migration in staging
   - Run `airflow db check-migrations`
   ```

4. **Canary Deployment** (Advanced):
   - Deploy to single scheduler first
   - Monitor for 5-10 minutes
   - Then deploy to remaining services

5. **Blue-Green Deployment** (Advanced):
   - Maintain two complete environments
   - Switch traffic after validation
   - Instant rollback by switching back

6. **Monitoring Integration**:
   - Export metrics to Prometheus
   - Create Grafana dashboards
   - Set up alerts for failed deployments

7. **Manual Approval Gate**:
   ```yaml
   promote-to-production:
     stage: promote
     when: manual  # Requires manual trigger
     script:
       - Promote image to production
   ```

8. **Deployment Windows**:
   ```yaml
   rules:
     - if: '$CI_PIPELINE_SOURCE == "schedule"'
       when: never  # Prevent auto-deploy during business hours
   ```

---

## Troubleshooting

### Deployment Fails at Build Stage

**Symptoms**: Docker build fails

**Solutions**:
- Check Dockerfile syntax
- Verify base image is accessible
- Check network connectivity to package repositories
- Review build logs for specific errors

### Health Check Fails - Containers Restarting

**Symptoms**: Restart count > 0

**Solutions**:
- Check container logs: `docker logs airflow_2.11-scheduler_2`
- Verify database connectivity
- Check resource limits (CPU/memory)
- Verify environment variables

### Health Check Fails - Webserver Unhealthy

**Symptoms**: Webserver returns non-200 status

**Solutions**:
- Check webserver logs
- Verify port 39100 is accessible
- Check firewall rules
- Verify database connection string

### Rollback Fails - No Stable Image

**Symptoms**: No previous stable image found

**Solutions**:
- Manually tag a working image as stable
- Pull from Nexus registry
- Rebuild from previous commit

### Image Transfer Fails (131 → 130)

**Symptoms**: `docker save | docker load` fails

**Solutions**:
- Check SSH connectivity between servers
- Verify disk space on both servers
- Check network bandwidth
- Try manual transfer and load

---

## Security Considerations

1. **SSH Keys**: Use dedicated SSH keys with limited permissions
2. **Docker Sudo**: Consider Docker socket permissions instead of sudo
3. **Secrets Management**: Use GitLab CI/CD variables (masked)
4. **Nexus Credentials**: Store in GitLab variables, never commit
5. **Image Scanning**: Add security scanning stage before promotion
6. **Network Segmentation**: Ensure servers can only communicate on required ports

---

## Monitoring & Metrics

### Key Metrics to Track

1. **Deployment Duration**: Target < 10 minutes
2. **Success Rate**: Target > 95%
3. **Rollback Frequency**: Monitor and investigate
4. **Health Check Duration**: Target < 2 minutes
5. **Image Size**: Monitor for bloat

### Logging

Collect logs from:
- GitLab CI/CD pipeline
- Container logs (webserver, schedulers)
- MySQL logs
- Health check outputs

---

## Maintenance

### Weekly Tasks

- Review deployment logs
- Check disk usage on servers
- Verify backup integrity

### Monthly Tasks

- Clean up old images (automated)
- Review and update dependencies
- Test rollback procedure

### Quarterly Tasks

- Review and update deployment strategy
- Update base image version
- Security audit of custom image

---

## FAQ

**Q: How long does a deployment take?**
A: Approximately 8-12 minutes for a full deployment across both servers.

**Q: Can I deploy to just one server?**
A: Yes, use the manual helper script with specific server parameter.

**Q: What happens if MySQL container fails health check?**
A: The deployment will fail and automatically rollback to the previous stable image.

**Q: How do I check current deployed version?**
A: Run `./deploy-helper.sh status both` or check GitLab CI/CD pipeline history.

**Q: Can I skip a stage?**
A: Not recommended. Each stage has dependencies on previous stages.

**Q: How do I emergency rollback manually?**
A: Run `./deploy-helper.sh rollback both`

**Q: What if both servers fail simultaneously?**
A: The rollback stage will restore both servers to previous stable state.

---

## Support

For issues or questions:
1. Check troubleshooting section
2. Review GitLab CI/CD logs
3. Check server logs: `/data/code/.../airflow/logs`
4. Contact DevOps team

---

## Changelog

### Version 1.0 (2024-01-12)
- Initial deployment strategy
- Multi-server deployment with health checks
- Automatic rollback capability
- Image promotion to Nexus
- Helper scripts for manual operations
