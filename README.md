# Airflow Custom Docker Image - CI/CD Pipeline

Complete CI/CD pipeline for building, deploying, and managing custom Airflow Docker images across multiple servers using Nexus as the Docker registry.

## 🚀 Features

- **Automated Build & Push**: Build custom Airflow images and push to Nexus registry
- **Multi-Server Deployment**: Deploy to Server 130 (Webserver + Scheduler1) and Server 131 (MySQL + Scheduler2)
- **Version Management**: Git SHA-based versioning for precise tracking
- **Easy Rollback**: Multiple rollback strategies (previous version, specific version, or manual)
- **Automated Cleanup**: Keep only last 5 versions on each server
- **Deployment Tracking**: JSON metadata for each deployment
- **Helper Scripts**: Command-line tools for common operations

## 📋 Quick Links

- **[Quick Start Guide](QUICK_START.md)** - Get started in 5 minutes
- **[Deployment Strategy](DEPLOYMENT_STRATEGY.md)** - Complete documentation

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│               GitLab CI/CD Pipeline                      │
├─────────────────────────────────────────────────────────┤
│  1. Build   │  2. Push    │  3. Deploy   │  4. Rollback│
│  Docker     │  to Nexus   │  to Servers  │  (Manual)   │
│  Image      │  Registry   │              │             │
└──────┬──────────────┬───────────┬─────────────┬─────────┘
       │              │           │             │
       │              ▼           │             │
       │    ┌─────────────────┐   │             │
       │    │ Nexus Registry  │   │             │
       │    │  Image Storage  │   │             │
       │    └────────┬────────┘   │             │
       │             │            │             │
       │    ┌────────┴────────┐   │             │
       │    │                 │   │             │
       ▼    ▼                 ▼   ▼             ▼
  ┌──────────────────┐   ┌──────────────────┐
  │   Server 130     │   │   Server 131     │
  ├──────────────────┤   ├──────────────────┤
  │ • Webserver      │   │ • MySQL DB       │
  │ • Scheduler-1    │   │ • Redis          │
  │                  │   │ • Scheduler-2    │
  └──────────────────┘   └──────────────────┘
```

## 🎯 Use Cases Solved

### ✅ Custom Image Management
- **Problem**: Using public Airflow images without custom dependencies
- **Solution**: Build custom images with your dependencies and push to private Nexus

### ✅ Version Control
- **Problem**: No tracking of which version is deployed
- **Solution**: Git SHA-based tagging + deployment metadata JSON files

### ✅ Rollback Strategy
- **Problem**: No easy way to revert bad deployments
- **Solution**: Three rollback methods:
  1. One-click rollback to previous version
  2. Rollback to any specific version
  3. Manual rollback via helper script

### ✅ Nexus Authentication
- **Problem**: Docker login only works on deployment servers (130, 131)
- **Solution**: Pipeline authenticates on target servers during deployment

### ✅ Disk Space Management
- **Problem**: Old images accumulate and fill disk
- **Solution**: Automatic cleanup keeping last 5 versions

## 📦 What's Included

```
.
├── .gitlab-ci.yml                          # Complete CI/CD pipeline
├── .env.example                            # Environment variables template
├── QUICK_START.md                          # Quick start guide
├── DEPLOYMENT_STRATEGY.md                  # Comprehensive documentation
├── scripts/
│   └── deployment-helper.sh                # Command-line helper tool
└── airflow/
    ├── docker/
    │   ├── Dockerfile                      # Custom Airflow image
    │   ├── docker-compose-server-130.example.yaml
    │   └── docker-compose-server-131.example.yaml
    └── requirements.txt                    # Python dependencies
```

## 🚀 Quick Start

### 1. Configure GitLab Variables
Set in GitLab → Settings → CI/CD → Variables:
```
NEXUS_REGISTRY = nexus.yourcompany.com:8443
NEXUS_USERNAME = your-username
NEXUS_PASSWORD = your-password (masked)
```

### 2. Customize Your Image
Edit `airflow/docker/Dockerfile` and `airflow/requirements.txt`

### 3. Deploy
```bash
git add .
git commit -m "Deploy custom Airflow image"
git push origin main
```

Pipeline runs automatically! 🎉

### 4. Verify
```bash
./scripts/deployment-helper.sh current-version both
./scripts/deployment-helper.sh health-check both
```

## 🔄 Common Operations

### Deploy Latest Changes
```bash
# Make changes, commit, and push
git add airflow/
git commit -m "Update dependencies"
git push
# Pipeline runs automatically
```

### Rollback to Previous Version
**Via GitLab UI:**
1. Go to Pipeline → Rollback stage
2. Click ▶️ on `rollback-server-130` or `rollback-server-131`

**Via Command Line:**
```bash
./scripts/deployment-helper.sh rollback both abc123def
```

### Check Status
```bash
# Current deployments
./scripts/deployment-helper.sh current-version both

# Service health
./scripts/deployment-helper.sh health-check both

# View logs
./scripts/deployment-helper.sh logs 130 webserver
```

## 📊 Rollback Strategies

### Strategy 1: Previous Version (Fastest)
- One-click rollback via GitLab
- Automatically saved previous deployment
- Best for: Quick revert of bad deployment

### Strategy 2: Specific Version (Most Flexible)
- Rollback to any tagged version
- Specify exact commit SHA
- Best for: Reverting to older known-good version

### Strategy 3: Manual (Emergency)
- Direct SSH access to servers
- Manual docker commands
- Best for: When automation fails

## 🛠️ Helper Script Commands

```bash
# Make script executable
chmod +x scripts/deployment-helper.sh

# Common commands
./scripts/deployment-helper.sh list-versions      # List available versions
./scripts/deployment-helper.sh current-version    # Show current deployment
./scripts/deployment-helper.sh rollback both TAG  # Rollback to version
./scripts/deployment-helper.sh health-check both  # Check service health
./scripts/deployment-helper.sh logs 130 webserver # View logs
./scripts/deployment-helper.sh cleanup both       # Remove old images
```

## 🔐 Security

- ✅ Nexus authentication on deployment servers only
- ✅ SSH key-based authentication
- ✅ Masked GitLab variables for credentials
- ✅ Service account for CI/CD
- ✅ Image vulnerability scanning (configure in Nexus)

## 📈 Benefits

| Feature | Before | After |
|---------|--------|-------|
| Image Source | Public images | Custom Nexus images |
| Versioning | None | Git SHA + tags |
| Rollback | Manual, error-prone | Automated, 3 strategies |
| Deployment Tracking | None | JSON metadata per deployment |
| Disk Management | Manual cleanup | Automatic retention (5 versions) |
| Authentication | Manual docker login | Automated in pipeline |

## 🔍 Monitoring

### Deployment Metadata
Each deployment stores metadata at:
- Server 130: `/data/airflow-deployments/current-deployment-130.json`
- Server 131: `/data/airflow-deployments/current-deployment-131.json`

```json
{
  "image": "nexus.yourcompany.com:8443/airflow-custom:abc123",
  "tag": "abc123",
  "commit": "abc123def456789",
  "branch": "main",
  "pipeline_id": "12345",
  "deployed_at": "2025-11-10T10:30:00Z"
}
```

## 🚨 Troubleshooting

### Issue: Pipeline Fails at Build
```bash
# Test locally
docker build -t test-airflow -f airflow/docker/Dockerfile airflow/
```

### Issue: Can't Pull from Nexus
```bash
# Re-login on server
ssh -p3535 dataeng99@172.10.17.130
echo 'PASSWORD' | sudo -u developer docker login nexus.yourcompany.com:8443 -u USERNAME --password-stdin
```

### Issue: Services Won't Start
```bash
# Check logs
./scripts/deployment-helper.sh logs 130 webserver

# Rollback if needed
./scripts/deployment-helper.sh rollback 130 previous-tag
```

## 📚 Documentation

- **[QUICK_START.md](QUICK_START.md)** - Get started quickly
- **[DEPLOYMENT_STRATEGY.md](DEPLOYMENT_STRATEGY.md)** - Complete strategy documentation
- **[.gitlab-ci.yml](.gitlab-ci.yml)** - Full pipeline configuration

## 🎓 Best Practices

1. ✅ **Always test in dev first** before production deployment
2. ✅ **Monitor logs** for 10-15 minutes after deployment
3. ✅ **Test rollback process** periodically
4. ✅ **Keep images clean** - run cleanup regularly
5. ✅ **Document changes** - use semantic commit messages
6. ✅ **Rotate credentials** regularly
7. ✅ **Backup deployment metadata** to external storage

## 🤝 Contributing

1. Make changes in feature branch
2. Test deployment to dev environment
3. Create merge request
4. After approval, merge to main
5. Pipeline deploys automatically

## 📞 Support

- Data Engineering Team: [your-team-channel]
- Documentation: [wiki-link]
- On-call: [pager-duty-link]

## 📝 License

[Your License Here]

---

**Ready to get started?** → Check out the [Quick Start Guide](QUICK_START.md)
