# Quick Reference Guide

## 🚀 Common Commands

### Check Deployment Status
```bash
# Check both servers
./deploy-helper.sh status both

# Check specific server
./deploy-helper.sh status 131
./deploy-helper.sh status 130
```

### Manual Deployment
```bash
# Build new image
./deploy-helper.sh build
# Output: IMAGE_TAG=20240112-163045

# Deploy to Server 131
./deploy-helper.sh deploy 131 20240112-163045-temp

# Deploy to Server 130
./deploy-helper.sh deploy 130 20240112-163045-temp

# Deploy to both (after testing)
./deploy-helper.sh deploy both 20240112-163045-temp
```

### Health Checks
```bash
# Check Server 131
./deploy-helper.sh health-check 131

# Check Server 130
./deploy-helper.sh health-check 130
```

### Rollback
```bash
# Rollback single server
./deploy-helper.sh rollback 131

# Rollback both servers
./deploy-helper.sh rollback both
```

### Cleanup
```bash
# Clean old images on both servers
./deploy-helper.sh cleanup both
```

---

## 📋 Container Names

### Server 131 (172.10.17.131)
- `airflow_2.11-mysql_8.0` - MySQL database
- `airflow_2.11-scheduler_2` - Scheduler 2
- `airflow_2.11-init` - One-time init container

### Server 130 (172.10.17.130)
- `airflow_2.11-webserver` - Web UI
- `airflow_2.11-scheduler_1` - Scheduler 1  
- `airflow_2.11-init` - One-time init container

---

## 🔍 Debugging Commands

### View Container Logs
```bash
# On Server 131
ssh -p3535 dataeng99@172.10.17.131
sudo -u developer docker logs -f airflow_2.11-scheduler_2
sudo -u developer docker logs -f airflow_2.11-mysql_8.0

# On Server 130
ssh -p3535 dataeng99@172.10.17.130
sudo -u developer docker logs -f airflow_2.11-webserver
sudo -u developer docker logs -f airflow_2.11-scheduler_1
```

### Check Container Health
```bash
# List all containers with health status
sudo -u developer docker ps --format 'table {{.Names}}\t{{.Status}}'

# Check specific container
sudo -u developer docker inspect airflow_2.11-webserver | jq '.[0].State.Health'
```

### Verify Image
```bash
# List all Airflow images
sudo -u developer docker images | grep airflow-custom

# Check image details
sudo -u developer docker inspect airflow-custom:latest-stable
```

### Database Connection
```bash
# Connect to MySQL
ssh -p3535 dataeng99@172.10.17.131
sudo -u developer docker exec -it airflow_2.11-mysql_8.0 mysql -uairflow -pairflow airflow

# Check Airflow DB version
SELECT * FROM alembic_version;
```

---

## 🌐 Service URLs

- **Webserver**: http://10.10.17.130:39100 or http://172.10.17.130:39100
- **Health Check**: http://10.10.17.130:39100/health
- **MySQL**: 172.10.17.131:33307

---

## 🏷️ Image Tags

### Development
- `airflow-custom:latest-temp` - Latest temporary build
- `airflow-custom:{commit-sha}-temp` - Specific commit temp build

### Production
- `airflow-custom:latest-stable` - Latest stable release
- `airflow-custom:{commit-sha}-stable` - Specific commit stable

### Nexus Registry
- `{registry}/{repo}/airflow-custom:latest` - Latest in Nexus
- `{registry}/{repo}/airflow-custom:{commit-sha}` - Specific version

---

## 🔧 Environment Variables

### For docker-compose
```bash
export CUSTOM_IMAGE_NAME=airflow-custom
export CUSTOM_IMAGE_TAG=latest-stable
export AIRFLOW_UID=50000
export AIRFLOW_GID=50000
```

### For CI/CD
Set in GitLab CI/CD → Settings → CI/CD → Variables:
- `NEXUS_REGISTRY`
- `NEXUS_USERNAME`
- `NEXUS_PASSWORD`

---

## 📝 CI/CD Pipeline Stages

1. **validate** - Check Dockerfile and compose files exist
2. **backup** - Backup current state
3. **update-code** - Pull latest code on both servers
4. **build-image** - Build Docker image on Server 131
5. **deploy-server-131** - Deploy and health check Server 131
6. **deploy-server-130** - Deploy and health check Server 130
7. **promote-image** - Tag as stable and push to Nexus
8. **rollback** - Auto-rollback on failure (when: on_failure)

---

## ⚠️ Troubleshooting

### Container Won't Start
```bash
# Check logs
docker logs airflow_2.11-scheduler_2 --tail 100

# Check if port is in use
sudo netstat -tulpn | grep 39100

# Check disk space
df -h

# Check permissions
ls -la /data/code/.../airflow/logs
```

### Health Check Failing
```bash
# Manual health check
curl http://localhost:39100/health

# Check scheduler job
docker exec airflow_2.11-scheduler_1 airflow jobs check --job-type SchedulerJob --hostname $(hostname)

# Check database connection
docker exec airflow_2.11-scheduler_1 airflow db check
```

### Deployment Stuck
```bash
# Check pipeline in GitLab CI/CD
# Look for stage that's hanging

# Check SSH connectivity
ssh -p3535 dataeng99@172.10.17.131 "echo OK"

# Check if previous containers are stopping
sudo -u developer docker ps -a
```

### Rollback Not Working
```bash
# List available stable images
sudo -u developer docker images | grep stable

# Manually rollback
export CUSTOM_IMAGE_TAG="{specific-stable-tag}"
sudo -u developer docker-compose -f docker/docker-compose-server-131.yaml down
sudo -u developer docker-compose -f docker/docker-compose-server-131.yaml up -d
```

---

## 🚨 Emergency Procedures

### Complete Service Outage
```bash
# 1. Stop all containers
./deploy-helper.sh rollback both

# 2. Check logs
ssh to servers and check docker logs

# 3. If rollback fails, manually deploy last known good version
# See manual deployment section above
```

### Database Corruption
```bash
# 1. Stop all Airflow services
docker-compose down

# 2. Restore from backup
# (Have backup procedure documented separately)

# 3. Restart with stable image
./deploy-helper.sh rollback both
```

### Disk Full
```bash
# 1. Clean old images
./deploy-helper.sh cleanup both

# 2. Clean logs (on each server)
find /data/code/.../airflow/logs -mtime +30 -delete

# 3. Clean docker system
sudo -u developer docker system prune -a
```

---

## 📊 Health Check Criteria

### Container Level
- ✅ Restart count = 0
- ✅ No unhealthy containers
- ✅ No exited/dead containers
- ✅ All expected containers running

### Application Level
- ✅ Webserver returns HTTP 200 on /health
- ✅ Scheduler job check passes
- ✅ No errors in recent logs

### Timing
- Initial wait: 30 seconds
- Check interval: 15 seconds
- Max retries: 5
- Total timeout: ~2 minutes

---

## 📞 Contacts

**DevOps Team**: [Your team contact]
**On-Call**: [On-call rotation]
**Escalation**: [Manager/Senior engineer]

---

## 🔗 Related Documentation

- [Full Deployment Guide](./DEPLOYMENT_GUIDE.md)
- [Improvements Summary](./IMPROVEMENTS_SUMMARY.md)
- GitLab CI/CD: [Your GitLab URL]
- Nexus Registry: [Your Nexus URL]
- Airflow Documentation: https://airflow.apache.org/

---

## 💡 Tips

1. **Always check status before deploying**
   ```bash
   ./deploy-helper.sh status both
   ```

2. **Test in Server 131 first** (it's more isolated)
   ```bash
   ./deploy-helper.sh deploy 131 {tag}
   ```

3. **Keep last 3 stable versions** (for quick rollback)

4. **Monitor during deployment** (watch GitLab CI/CD pipeline)

5. **Check logs after deployment**
   ```bash
   docker logs airflow_2.11-webserver --tail 50
   ```

6. **Use tags, not 'latest'** (for reproducibility)
   ```bash
   airflow-custom:20240112-stable  # Good
   airflow-custom:latest           # Avoid
   ```

---

## ⌨️ Bash Aliases (Optional)

Add to your `~/.bashrc`:

```bash
alias airflow-status='./deploy-helper.sh status both'
alias airflow-health='./deploy-helper.sh health-check'
alias airflow-logs-131='ssh -p3535 dataeng99@172.10.17.131 "sudo -u developer docker logs -f airflow_2.11-scheduler_2"'
alias airflow-logs-130='ssh -p3535 dataeng99@172.10.17.130 "sudo -u developer docker logs -f airflow_2.11-webserver"'
```

---

**Last Updated**: 2025-11-12
**Version**: 1.0
