# Nexus Registry Approach - Recommended Strategy 🎯

## Overview

Using Nexus as a central image registry is a **production best practice** and **highly recommended** for your deployment. This approach combines the best aspects of consistency, scalability, and enterprise-grade image management.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Nexus Registry                              │
│                 (Single Source of Truth)                        │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Images:                                                  │  │
│  │  - airflow-custom:abc123-temp    (testing)              │  │
│  │  - airflow-custom:abc123-stable  (production)           │  │
│  │  - airflow-custom:latest-stable  (latest prod)          │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────┬──────────────────────┬─────────────────────────┘
                 │                      │
        ┌────────▼────────┐    ┌───────▼────────┐
        │   Server 131    │    │   Server 130   │
        │                 │    │                │
        │ 1. Build image  │    │ 1. Pull image  │
        │ 2. Push to Nexus│    │    from Nexus  │
        │ 3. Use locally  │    │ 2. Deploy      │
        └─────────────────┘    └────────────────┘
```

---

## ✅ Why This Approach is Excellent

### 1. **Central Image Registry** (Single Source of Truth)

**Before**: Images scattered across servers
**After**: All images in one place (Nexus)

Benefits:
- ✅ One location to audit all images
- ✅ Easy to see what's deployed where
- ✅ Compliance-friendly (centralized artifact management)
- ✅ Disaster recovery (images backed up in Nexus)

### 2. **No Server-to-Server Dependency**

**Before**: Server 131 must be able to SSH to Server 130
**After**: Both servers only talk to Nexus

```
Transfer Approach:
  Server 131 ---SSH---> Server 130  ❌ Tight coupling

Nexus Approach:
  Server 131 ---HTTPS---> Nexus
  Server 130 ---HTTPS---> Nexus     ✅ Loosely coupled
```

Benefits:
- ✅ Servers don't need to know about each other
- ✅ Can deploy to Server 130 even if 131 is down
- ✅ Network firewall rules are simpler
- ✅ Better security posture

### 3. **Guaranteed Image Consistency**

**Same image SHA-256** deployed to all servers:
```bash
# On Server 131
docker inspect airflow-custom:abc123-temp
# SHA256: 9d3f4e2a1b5c...

# On Server 130 (pulled from Nexus)
docker inspect airflow-custom:abc123-temp
# SHA256: 9d3f4e2a1b5c...  ✅ Identical!
```

### 4. **Scalability**

**Adding more servers is trivial:**

```yaml
# Just add another deploy stage
deploy-server-132:
  script:
    - Pull from Nexus
    - Deploy
```

**No changes needed to build stage!**

### 5. **Audit Trail & Compliance**

Nexus provides built-in features:
- 📋 Who pushed which image and when
- 📋 Download history (who pulled what)
- 📋 Image vulnerability scanning (if enabled)
- 📋 Retention policies
- 📋 Cleanup policies for old images

### 6. **Easy Rollback**

**All stable images are in Nexus:**
```bash
# Rollback to any previous version
docker pull nexus.com/airflow-custom:def456-stable
docker pull nexus.com/airflow-custom:abc123-stable
docker pull nexus.com/airflow-custom:xyz789-stable
```

### 7. **Temp Image Cleanup**

**Built-in lifecycle management:**
- ✅ Temp images automatically deleted on failure
- ✅ Nexus cleanup policies remove old temp images
- ✅ Only stable images retained long-term
- ✅ Saves storage space

### 8. **Multi-Environment Support**

**Easy to extend to multiple environments:**
```
Nexus Repositories:
  - docker-dev        (development images)
  - docker-staging    (staging images)
  - docker-production (production images)
  - docker-temp       (temporary/testing images)
```

---

## 📊 Comparison: All Three Approaches

| Aspect | Transfer (SSH) | Separate Builds | **Nexus Registry** ⭐ |
|--------|----------------|-----------------|---------------------|
| Image Consistency | ✅ Guaranteed | ⚠️ May differ | ✅ Guaranteed |
| Build Time | ✅ Build once | ❌ 2x build | ✅ Build once |
| Network Dependency | ❌ 131→130 SSH | ✅ Independent | ✅ Independent |
| Scalability | ⚠️ N-to-N transfers | ❌ N builds | ✅ Pull from registry |
| Audit Trail | ❌ None | ❌ None | ✅ Complete |
| Disaster Recovery | ❌ Local only | ❌ Local only | ✅ Backed up in Nexus |
| Rollback | ✅ Good | ⚠️ Complex | ✅ Excellent |
| Image Cleanup | ⚠️ Manual | ⚠️ Manual | ✅ Automatic |
| Multi-Environment | ❌ Hard | ❌ Hard | ✅ Easy |
| Compliance | ⚠️ Limited | ⚠️ Limited | ✅ Enterprise-grade |
| Cost | ✅ Free | ✅ Free | ⚠️ Nexus license |

---

## 🚀 Deployment Flow

### Success Path

```
1. Validate
   └─> Check Dockerfile exists
   
2. Backup
   └─> Save current state
   
3. Update Code
   └─> Pull latest on 131 & 130
   
4. Build & Push
   └─> Build on 131
   └─> Push to Nexus as abc123-temp
   
5. Deploy 131
   └─> Use local image (already built)
   └─> Health check ✅
   
6. Deploy 130
   └─> Pull abc123-temp from Nexus
   └─> Health check ✅
   
7. Promote
   └─> Tag as abc123-stable in Nexus
   └─> Push stable tag to Nexus
   
8. Cleanup
   └─> Delete abc123-temp from Nexus (optional)
   └─> Or keep for audit trail
   
✅ SUCCESS
```

### Failure Path

```
1-4. (same as success)

5. Deploy 131
   └─> Health check ❌ FAILED
   
→ ROLLBACK TRIGGERED

9. Rollback
   └─> Delete abc123-temp from Nexus
   └─> Revert code on 131 & 130
   └─> Pull latest-stable from Nexus
   └─> Deploy stable image
   
❌ DEPLOYMENT FAILED, ROLLED BACK
```

---

## 🔧 Configuration

### Nexus Setup Required

#### 1. Create Docker Repository in Nexus

```
Repository Type: docker (hosted)
Repository Name: docker-releases
HTTP Port: 8082
Enable Docker V1 API: No
Enable Docker V2 API: Yes
```

#### 2. Create Service Account

```
Username: gitlab-ci
Password: <strong-password>
Role: nx-docker-push (push) + nx-docker-pull (pull)
```

#### 3. Configure GitLab CI/CD Variables

```bash
Settings → CI/CD → Variables → Add Variable

NEXUS_REGISTRY     = nexus.yourcompany.com:8082
NEXUS_REPO         = docker-releases
NEXUS_USERNAME     = gitlab-ci
NEXUS_PASSWORD     = <password>  (masked, protected)
```

### Server Setup Required

#### Both Servers Need Docker Login

```bash
# On Server 131 & 130
echo "$NEXUS_PASSWORD" | docker login \
  -u "$NEXUS_USERNAME" \
  --password-stdin \
  nexus.yourcompany.com:8082
```

**Pro Tip**: Add this to server startup scripts or use Docker credential helpers.

---

## 🔒 Security Considerations

### 1. **Nexus Authentication**

```yaml
# Never hardcode credentials!
❌ BAD:
docker login -u myuser -p mypassword nexus.com

✅ GOOD:
echo "$NEXUS_PASSWORD" | docker login -u "$NEXUS_USERNAME" --password-stdin
```

### 2. **Use TLS/HTTPS**

```bash
# Always use HTTPS for Nexus
✅ nexus.yourcompany.com:8082  (HTTPS on port 8082)
❌ nexus.yourcompany.com:5000  (HTTP)
```

### 3. **Separate Repos for Temp/Stable**

**Best Practice**:
```
docker-temp        → Temp images, auto-cleanup after 7 days
docker-releases    → Stable images, keep forever
```

### 4. **Image Signing** (Advanced)

```bash
# Sign images before pushing
export DOCKER_CONTENT_TRUST=1
docker trust sign nexus.com/airflow-custom:abc123-stable
```

---

## 📝 Nexus Cleanup Policies

### Automatic Cleanup of Temp Images

**Nexus UI → Repository → Cleanup Policies**

```yaml
Policy Name: Cleanup-Temp-Images
Criteria:
  - Name matches: *-temp
  - Last downloaded: > 7 days ago
  - OR Last modified: > 30 days ago
Action: Delete
```

This automatically removes:
- Old temp images
- Temp images from failed deployments
- Unused temp images

**Stable images are NEVER deleted** (no `-temp` suffix)

---

## 🎯 When to Use Each Approach

### ✅ Use Nexus (Recommended) If:

- ✅ You already have Nexus (or can set it up)
- ✅ You want enterprise-grade artifact management
- ✅ Compliance/audit trail is important
- ✅ You plan to scale to more servers
- ✅ You want disaster recovery for images
- ✅ You have multiple environments (dev/staging/prod)

### ⚠️ Use Transfer (SSH) If:

- You don't have Nexus and can't set it up
- Budget constraints prevent registry setup
- Only 2 servers, no plans to scale
- Servers are on same LAN (fast transfer)
- Simple setup is priority

### ❌ Use Separate Builds If:

- Servers are in different regions (slow network)
- Regulatory requirements prohibit image transfer
- You're willing to maintain pinned versions

---

## 💰 Cost Considerations

### Nexus Options

#### 1. **Nexus OSS (Free)**
- ✅ Docker repository support
- ✅ Unlimited storage (your hardware)
- ✅ Basic cleanup policies
- ❌ No high availability
- ❌ No support

#### 2. **Nexus Pro ($$$)**
- ✅ All OSS features
- ✅ High availability
- ✅ Professional support
- ✅ Advanced features

#### 3. **Cloud Alternatives**
- **Docker Hub** (free tier available)
- **AWS ECR** (~$0.10/GB/month)
- **Google GCR** (~$0.026/GB/month)
- **Azure ACR** (~$0.10/GB/month)

**Recommendation**: Start with Nexus OSS (free) if you don't already have a registry.

---

## 🚀 Migration Path

### From Direct SSH Transfer to Nexus

**Phase 1: Setup (Week 1)**
- Install Nexus (or use existing)
- Create Docker repository
- Configure authentication
- Test push/pull manually

**Phase 2: Pilot (Week 2)**
- Switch to `airflow-ci-nexus.yml`
- Deploy to dev environment first
- Monitor and validate

**Phase 3: Production (Week 3)**
- Deploy to production servers
- Keep SSH transfer as backup (temporarily)
- Monitor for issues

**Phase 4: Finalize (Week 4)**
- Remove SSH transfer code
- Set up cleanup policies
- Document process

---

## 🔍 Troubleshooting

### Issue: "Failed to push image to Nexus"

**Causes**:
1. Network connectivity to Nexus
2. Authentication failed
3. Disk space on Nexus server
4. Repository doesn't exist

**Solutions**:
```bash
# Test connectivity
curl -u $NEXUS_USERNAME:$NEXUS_PASSWORD https://nexus.com:8082/v2/

# Test authentication
docker login nexus.com:8082

# Check Nexus logs
# Check repository exists
```

### Issue: "Failed to pull image from Nexus"

**Causes**:
1. Image doesn't exist (build failed)
2. Wrong image tag
3. Network issue
4. Authentication failed

**Solutions**:
```bash
# List available images
curl -u $USER:$PASS "https://nexus.com:8082/v2/airflow-custom/tags/list"

# Verify image exists in Nexus UI
# Check image tag matches

# Pull manually to test
docker pull nexus.com:8082/docker-releases/airflow-custom:abc123-temp
```

### Issue: "Temp image not cleaned up"

**Causes**:
1. Nexus API credentials not configured
2. Cleanup policy not set up
3. Manual intervention required

**Solutions**:
```bash
# Option 1: Use Nexus UI to delete manually
# Repository → Browse → Select image → Delete

# Option 2: Use Nexus REST API
curl -X DELETE -u $USER:$PASS \
  "https://nexus.com:8082/service/rest/v1/components/..."

# Option 3: Set up automatic cleanup policies
```

---

## 📊 Monitoring & Metrics

### Key Metrics to Track

1. **Push Success Rate**
   - Target: >99%
   - Alert if: <95%

2. **Pull Success Rate**
   - Target: >99%
   - Alert if: <95%

3. **Nexus Storage Usage**
   - Monitor disk space
   - Alert if: >80% full

4. **Image Size**
   - Track growth over time
   - Optimize if: increasing rapidly

5. **Push/Pull Duration**
   - Baseline: 2-3 minutes
   - Alert if: >10 minutes

### Nexus Metrics (Built-in)

Nexus provides metrics at:
```
https://nexus.com:8082/service/rest/v1/metrics
```

Track:
- Repository storage
- Request count
- Error rate
- Bandwidth usage

---

## 🎓 Best Practices

### 1. **Tag Strategy**

```bash
# Development/Testing
airflow-custom:abc123-temp          # Temporary, auto-cleanup

# Production/Stable
airflow-custom:abc123-stable        # Specific version (immutable)
airflow-custom:latest-stable        # Latest prod version (mutable)
airflow-custom:v2.11.0-abc123       # Semantic version

# Environment-specific
airflow-custom:dev-abc123
airflow-custom:staging-abc123
airflow-custom:prod-abc123
```

### 2. **Repository Organization**

```
Nexus Repositories:
  docker-temp       → Temp images (auto-cleanup 7 days)
  docker-dev        → Dev environment
  docker-staging    → Staging environment  
  docker-production → Production only
```

### 3. **Access Control**

```
Roles:
  ci-push   → Can push to docker-temp, docker-dev
  ci-deploy → Can pull from all, push to docker-staging
  ops-admin → Full access to docker-production
```

### 4. **Backup Strategy**

- ✅ Backup Nexus data directory daily
- ✅ Test restore procedure monthly
- ✅ Keep stable images for 90 days minimum
- ✅ Document image retention policy

---

## ✅ Final Recommendation

**Use the Nexus approach (`airflow-ci-nexus.yml`) for production.**

### Why?

1. ✅ **Industry Best Practice** - This is how enterprises do it
2. ✅ **Scalable** - Easy to add more servers
3. ✅ **Reliable** - No server-to-server dependencies
4. ✅ **Auditable** - Complete trail of images
5. ✅ **Maintainable** - Automatic cleanup
6. ✅ **Secure** - Centralized access control

### Effort Required

- **Setup Time**: 2-4 hours (one-time)
- **Learning Curve**: Low (if familiar with Docker)
- **Maintenance**: Minimal (mostly automated)
- **ROI**: High (pays off immediately)

---

## 📚 Additional Resources

- [Nexus Repository Manager 3 Docs](https://help.sonatype.com/repomanager3)
- [Docker Registry Specification](https://docs.docker.com/registry/spec/api/)
- [Best Practices for Container Registries](https://docs.docker.com/registry/deploying/)

---

## 🤝 Need Help?

**Common Questions**:

1. **Q**: Can I use this with Docker Hub instead of Nexus?
   - **A**: Yes! Just change `NEXUS_REGISTRY` to `docker.io` and use Docker Hub credentials.

2. **Q**: What if Nexus is down?
   - **A**: Deployment will fail. Implement Nexus HA or manual rollback procedures.

3. **Q**: How much disk space does Nexus need?
   - **A**: ~5-10GB per image × number of versions you keep. Plan for 100-200GB minimum.

4. **Q**: Can I have multiple Nexus repositories for different environments?
   - **A**: Absolutely! Recommended for prod/staging/dev separation.

---

**Ready to implement? Use `airflow-ci-nexus.yml` as your `.gitlab-ci.yml`!** 🚀
