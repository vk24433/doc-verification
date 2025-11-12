# Image Build Strategy: Transfer vs Separate Builds

## 🤔 The Question

**Should we build the image once and transfer it, or build separately on each server?**

This is a critical architectural decision with significant implications for your deployment.

---

## 📊 Quick Comparison

| Aspect | **Transfer (Recommended)** | **Separate Builds** |
|--------|---------------------------|---------------------|
| **Image Consistency** | ✅ Guaranteed identical | ⚠️ May differ slightly |
| **Deployment Time** | ✅ Faster (build once) | ❌ Slower (2x build) |
| **Network Dependency** | ❌ Requires 131→130 connectivity | ✅ Independent servers |
| **Resource Usage** | ✅ Single build (CPU/memory) | ❌ Duplicate build effort |
| **Rollback Guarantee** | ✅ Known exact image | ⚠️ Must track per-server |
| **Scalability** | ✅ Easy to add servers | ❌ Each server builds |
| **Failure Isolation** | ⚠️ Build failure affects all | ✅ One build failure isolated |
| **Complexity** | ⚠️ Requires docker save/load | ✅ Simpler (no transfer) |

---

## 🎯 Approach 1: Transfer Image (Current/Recommended)

### How It Works

```
┌─────────────┐
│  Server 131 │  1. Build image
│             │  2. Tag as {sha}-temp
└──────┬──────┘
       │
       │ 3. docker save | ssh | docker load
       ↓
┌─────────────┐
│  Server 130 │  4. Use exact same image
└─────────────┘
```

### Why This Is Recommended

#### 1. **Guaranteed Image Consistency**

**Problem with separate builds:**
```dockerfile
# In your Dockerfile
RUN pip install awscli
RUN apt-get install clickhouse-client
```

**What can happen:**
- **10:00 AM** - Build on Server 131 → gets `awscli 1.29.50`
- **10:05 AM** - Build on Server 130 → gets `awscli 1.29.51` (just released!)

**Result**: Different packages, potentially different behavior!

**With transfer**: Both servers get the EXACT same bits.

#### 2. **Reproducible Deployments**

If a deployment works on Server 131, you have **100% confidence** it will work on Server 130 because it's the **same image**.

#### 3. **Easier Rollback**

```bash
# With transfer - simple
docker tag airflow-custom:abc123-stable airflow-custom:latest-stable
# Both servers have SAME abc123-stable image

# With separate builds - complex
# Need to track:
# - Server 131: abc123-stable-131
# - Server 130: abc123-stable-130
# Are these truly the same? 🤷
```

#### 4. **Scales to More Servers**

```
If you add Server 132, 133, 134...

Transfer: Build once on 131, distribute to all
Separate: Build on each = 5x the build time
```

#### 5. **Faster Total Pipeline Time**

```
Transfer Approach:
  Build on 131:    8 min
  Transfer to 130: 2 min
  Total:           10 min

Separate Build:
  Build on 131:    8 min (parallel)
  Build on 130:    8 min (parallel)
  Total:           8 min (but with risks)
```

**Note**: While separate builds CAN be parallel (faster), you lose the consistency guarantee.

### Drawbacks

❌ **Network Dependency**: If 131→130 network fails, deployment fails
❌ **Single Point of Failure**: If build fails on 131, both servers affected
❌ **Transfer Time**: Takes 1-2 minutes (though faster than building)

---

## 🔄 Approach 2: Separate Builds

### How It Works

```
┌─────────────┐          ┌─────────────┐
│  Server 131 │          │  Server 130 │
│             │          │             │
│ Build image │          │ Build image │
│ (parallel)  │          │ (parallel)  │
└─────────────┘          └─────────────┘
     ↓                        ↓
  Image A                 Image B
  (may differ!)          (may differ!)
```

### When This Makes Sense

#### 1. **Network Constraints**

If your servers are in different data centers with slow/unreliable connections:
```
Server 131: US East
Server 130: US West

Transfer: 2-3 GB over slow WAN = 10+ minutes
Build:    Each server uses local fast mirrors = 8 minutes
```

#### 2. **Complete Independence**

If you want each server to be 100% independent:
- No cross-server dependencies
- Can deploy to one server without the other
- Build failure on 131 doesn't block 130

#### 3. **Regulatory/Security Requirements**

Some environments prohibit moving images between servers:
- Each server must build from source
- No binary transfers allowed
- Audit trail must show local build

### How to Make It Safer

If you choose separate builds, **pin ALL versions**:

```dockerfile
FROM apache/airflow:2.11.0-python3.9

USER root

# Pin APT package versions
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        jq=1.6-2.1ubuntu3 \
        nano=6.2-1 \
        clickhouse-client=22.8.5.29 && \
    apt-get clean

USER airflow

# Pin Python package versions (CRITICAL!)
RUN pip install --no-cache-dir \
    PyMySQL==1.1.0 \
    awscli==1.29.50 \
    pymsteams==0.1.13 \
    kafka-python==2.0.2 \
    pika==1.3.2 \
    pyathena==3.0.10 \
    pyspark==3.3.0 \
    acryl-datahub==0.8.5.0
```

**Why**: This reduces (but doesn't eliminate) the chance of different images.

### Drawbacks

❌ **Consistency Risk**: Even with pinned versions, subtle differences can occur
❌ **Double Build Time**: Uses 2x CPU/memory/time
❌ **Rollback Complexity**: Must track which image on which server
❌ **Harder to Verify**: Can't be 100% sure images are identical

---

## 🎯 Recommended Decision Matrix

### Choose **Transfer** (Recommended) If:

✅ Your servers are in the same data center  
✅ Network is reliable between servers  
✅ You value consistency over independence  
✅ You might add more servers later  
✅ You want simple rollback  

### Choose **Separate Builds** If:

✅ Servers are geographically distant (slow network)  
✅ You need complete server independence  
✅ Regulatory requirements prohibit image transfer  
✅ You're willing to pin ALL package versions  
✅ You're okay with slightly longer pipeline time  

---

## 📁 Implementation Files

### Using Transfer (Default)
Use the original file:
- `airflow-ci.yml` - Builds on 131, transfers to 130

### Using Separate Builds
Use the alternative file:
- `airflow-ci-separate-builds.yml` - Builds on both servers in parallel

**To switch**: Just rename the file you want to `.gitlab-ci.yml`

---

## 🧪 Hybrid Approach (Best of Both Worlds)

You could also implement a **hybrid approach**:

```yaml
# Build on Server 131
build-master-image:
  stage: build
  script:
    - Build on 131
    - Save checksum of image

# Try to transfer, fallback to build
deploy-server-130:
  script:
    - |
      # Try transfer first
      if ! transfer_image_from_131; then
        echo "⚠️ Transfer failed, building locally..."
        build_image_on_130
      fi
      
      # Verify checksums match (if possible)
      verify_image_checksum
```

This gives you:
- ✅ Speed of transfer when network is good
- ✅ Fallback to local build if transfer fails
- ✅ Checksum verification for consistency

---

## 🔍 Real-World Example: Package Version Drift

### Scenario: You Deploy on Monday

**Server 131 (builds at 10:00 AM)**
```bash
pip install pyspark  # Gets 3.3.0
apt-get install jq   # Gets 1.6-2.1ubuntu3
```

**Server 130 (builds at 10:05 AM)**
```bash
pip install pyspark  # Gets 3.3.1 (JUST RELEASED!)
apt-get install jq   # Gets 1.6-2.1ubuntu3
```

### What Happens?

1. **Deployment succeeds** - Both builds pass health checks
2. **Week later** - DAG fails on Server 130 only
3. **Investigation** - Takes hours to find it's a pyspark version difference
4. **Fix** - Pin versions, redeploy
5. **Cost** - Wasted time, potential data issues

### With Transfer

Both servers have **pyspark 3.3.0** - consistent behavior guaranteed.

---

## 💡 Recommendation

For your use case (2 servers in same environment), I **strongly recommend the transfer approach** because:

1. ✅ **Your servers are close** (131 and 130 are in same network)
2. ✅ **Network is reliable** (internal network)
3. ✅ **Image size is reasonable** (~2-3 GB = 1-2 min transfer)
4. ✅ **Consistency is critical** (Airflow schedulers must be identical)
5. ✅ **Simpler operations** (one source of truth)

---

## 🚀 How to Switch Between Approaches

### Currently Using: Transfer (Recommended)

**File**: `airflow-ci.yml`

**Keep using this unless you have specific reasons to change.**

### Want to Use: Separate Builds

**Step 1**: Review and customize `airflow-ci-separate-builds.yml`

**Step 2**: Pin ALL package versions in Dockerfile:
```dockerfile
RUN pip install --no-cache-dir \
    PyMySQL==1.1.0 \
    awscli==1.29.50 \
    pymsteams==0.1.13 \
    # ... all others with versions
```

**Step 3**: Rename file
```bash
mv airflow-ci-separate-builds.yml .gitlab-ci.yml
```

**Step 4**: Update documentation to note you're using separate builds

---

## 📊 Performance Benchmarks (Estimated)

### Transfer Approach
```
┌─────────────────────────────────────┐
│ Build on 131         │  8 min       │
│ Transfer to 130      │  2 min       │
│ Deploy 131           │  3 min       │
│ Deploy 130           │  3 min       │
│ Total                │ ~12 min      │
└─────────────────────────────────────┘
```

### Separate Builds (Parallel)
```
┌─────────────────────────────────────┐
│ Build 131 + 130     │  8 min       │ (parallel)
│ Deploy 131          │  3 min       │
│ Deploy 130          │  3 min       │
│ Total               │ ~10 min      │
└─────────────────────────────────────┘
```

**Note**: Separate builds are ~2 minutes faster, but at the cost of consistency.

---

## ✅ Final Recommendation

**Use the transfer approach (`airflow-ci.yml`) UNLESS:**

- [ ] Servers are in different data centers with slow network
- [ ] You have regulatory requirements against image transfer
- [ ] You need complete server independence
- [ ] You're willing to maintain pinned versions of ALL packages

For **99% of use cases**, transfer is the right choice.

---

## 🤝 Questions?

- **Q**: What if the network is temporarily slow?
  - **A**: The transfer will take longer but still work. If it fails, the pipeline fails and triggers rollback.

- **Q**: Can I verify the images are identical?
  - **A**: Yes! Use `docker inspect` and compare image IDs/checksums.

- **Q**: What if I want to test on 131 before deploying to 130?
  - **A**: With transfer, you're already doing this! 131 deploys first, validates, then 130 gets the same image.

- **Q**: Can I add a third server later?
  - **A**: With transfer, just add another deploy stage. With separate builds, add another build job.

---

**Bottom Line**: Stick with the transfer approach unless you have compelling reasons to change. 🎯
