# ROSA Cluster Sizing Guide
## Based on Updated Resource Requirements

This document provides node sizing recommendations for the ROSA Supply Chain Security deployment based on the optimized resource requirements in `rosa_deployment_enhanced.sh`.

---

## Total Resource Requirements

### Application Workloads (Requests)

| Component | Replicas | Memory Request | CPU Request | Notes |
|-----------|----------|----------------|-------------|-------|
| **ACS Central** | 1 | 2Gi | 500m | Main security console |
| **ACS Scanner** | 1 | ~1Gi | ~500m | Image scanning (typical) |
| **TPA Service** | 1 | 512Mi | 250m | SBOM/VEX analysis |
| **MLflow PostgreSQL** | 1 | 256Mi | 250m | AI/ML backend DB |
| **MLflow Server** | 1 | 512Mi | 250m | AI/ML tracking |
| **Quay Registry** | Multiple pods | ~4-6Gi | ~2-3 CPUs | Quay app + Clair + DB + Redis + ObjectStorage |
| **Tekton Operators** | Multiple pods | ~1Gi | ~500m | Pipelines operator + controllers |
| **Operators** | 3 operators | ~600Mi | ~300m | Quay, ACS, Tekton operators |

**Total Application Requests:**
- **Memory:** ~10-12Gi
- **CPU:** ~5-6 cores (5000-6000m)

### OpenShift System Overhead

| Component | Memory | CPU |
|-----------|--------|-----|
| **Infrastructure Pods** (DNS, routers, monitoring) | 2-3Gi | 1-2 cores |
| **OS & Kubelet** | 1-2Gi | ~500m |
| **Reserve for Node Capacity** | 15-20% overhead | 15-20% overhead |

**Total System Overhead:**
- **Memory:** ~3-5Gi
- **CPU:** ~1.5-2.5 cores

### Storage Requirements

| Component | Storage Type | Size |
|-----------|--------------|------|
| **ACS Database** | PVC | 20Gi |
| **TPA SBOM Storage** | PVC | 10Gi |
| **TPA VEX Storage** | PVC | 5Gi |
| **MLflow Artifacts** | emptyDir | 10Gi (ephemeral) |

**Total Persistent Storage: 35Gi**
**Note:** emptyDir storage is ephemeral and does not require persistent volumes

---

## Recommended Node Configurations

### Option 1: Minimal Cluster (Development/Demo)
**Best for:** Testing, demos, small teams

**Worker Nodes:**
- **Count:** 3 nodes
- **Size:** m5.xlarge or equivalent
  - **vCPUs:** 4 cores
  - **Memory:** 16 GiB
  - **Storage:** 100 GiB (OS) + additional for PVCs

**Total Cluster Capacity:**
- **vCPUs:** 12 cores (10.5 allocatable ≈ 10 cores usable)
- **Memory:** 48 GiB (≈40 GiB allocatable)

**Capacity Utilization:**
- CPU: ~50-60% (5-6 cores used / 10 available)
- Memory: ~60-70% (12-17 GiB used / 40 available)

**Notes:**
- Suitable for demos and light workloads
- Can handle all components with some headroom
- May experience performance limitations during peak scanning operations

---

### Option 2: Small Production Cluster (Recommended)
**Best for:** Small teams, pilot projects, staging environments

**Worker Nodes:**
- **Count:** 3 nodes
- **Size:** m5.2xlarge or equivalent
  - **vCPUs:** 8 cores
  - **Memory:** 32 GiB
  - **Storage:** 100 GiB (OS) + additional for PVCs

**Total Cluster Capacity:**
- **vCPUs:** 24 cores (≈21 allocatable cores)
- **Memory:** 96 GiB (≈85 GiB allocatable)

**Capacity Utilization:**
- CPU: ~25-30% (5-6 cores used / 21 available)
- Memory: ~30-40% (12-17 GiB used / 85 available)

**Notes:**
- Good balance of cost and performance
- Comfortable headroom for scaling
- Can handle concurrent operations smoothly

---

### Option 3: Medium Production Cluster
**Best for:** Production workloads, multiple teams, higher availability

**Worker Nodes:**
- **Count:** 4-5 nodes
- **Size:** m5.2xlarge or m5.4xlarge
  - **vCPUs:** 8-16 cores per node
  - **Memory:** 32-64 GiB per node
  - **Storage:** 200+ GiB per node

**Total Cluster Capacity:**
- **vCPUs:** 32-80 cores
- **Memory:** 128-320 GiB

**Notes:**
- High availability with node redundancy
- Can handle production traffic and scaling
- Suitable for multiple concurrent deployments

---

## AWS Instance Type Recommendations

### For Option 1 (Minimal):
```
m5.xlarge
- 4 vCPUs
- 16 GiB RAM
- Network: Up to 10 Gbps
- EBS Bandwidth: Up to 4,750 Mbps
```

### For Option 2 (Small Production - Recommended):
```
m5.2xlarge
- 8 vCPUs
- 32 GiB RAM
- Network: Up to 10 Gbps
- EBS Bandwidth: Up to 4,750 Mbps

Alternative: m6i.2xlarge (Intel Xeon, better price/performance)
```

### For Option 3 (Medium Production):
```
m5.4xlarge or m6i.4xlarge
- 16 vCPUs
- 64 GiB RAM
- Network: Up to 10 Gbps

Or for better cost optimization:
c6i.4xlarge (Compute optimized, if memory needs are lower)
```

---

## Control Plane Nodes (Standard ROSA Configuration)

ROSA managed control planes typically use:
- **3 control plane nodes** (managed by AWS)
- Each node: **4-8 vCPUs, 16-32 GiB RAM**
- Managed automatically - no sizing decisions needed

---

## Resource Breakdown by Component

### Red Hat Quay Registry
- **Typical pod count:** 6-8 pods (app, Clair, postgres, redis, objectstorage, mirror, routing)
- **Memory:** 4-6Gi total (requests)
- **CPU:** 2-3 cores total
- **Storage:** Managed internally via object storage

### Red Hat ACS
- **Central:** 2Gi memory, 500m CPU
- **Scanner:** ~1Gi memory, ~500m CPU (1 replica)
- **SecuredCluster:** Minimal overhead (~100-200Mi)
- **Storage:** 20Gi PVC

### Trusted Profile Analyzer (TPA)
- **Service:** 512Mi memory, 250m CPU (1 replica)
- **Storage:** 15Gi total (10Gi + 5Gi PVCs)

### MLflow (AI/ML)
- **PostgreSQL:** 256Mi memory, 250m CPU
- **MLflow Server:** 512Mi memory, 250m CPU
- **Storage:** 15Gi total (5Gi + 10Gi emptyDir)

### Tekton Pipelines
- **Operator:** ~200Mi memory, ~100m CPU
- **Controllers:** ~800Mi memory, ~400m CPU
- **Total:** ~1Gi memory, ~500m CPU

---

## Scaling Considerations

### When to Scale Up:
1. **High concurrent scanning:** Increase ACS Scanner replicas
2. **Heavy image registry usage:** Quay may need more resources
3. **Multiple concurrent pipelines:** Add Tekton controller resources
4. **Large SBOM processing:** TPA may need memory increase

### Horizontal vs Vertical Scaling:
- **Horizontal:** Add more worker nodes (recommended for HA)
- **Vertical:** Increase node sizes (simpler, but less fault-tolerant)

---

## Cost Estimates (AWS, approximate)

### Option 1 (Minimal):
- 3 × m5.xlarge workers: ~$300-400/month
- **Total:** ~$300-400/month

### Option 2 (Small Production - Recommended):
- 3 × m5.2xlarge workers: ~$600-700/month
- **Total:** ~$600-700/month

### Option 3 (Medium Production):
- 4-5 × m5.2xlarge workers: ~$800-1200/month
- **Total:** ~$800-1200/month

*Note: Prices vary by region and include instance costs only. Additional costs for EBS storage, networking, and ROSA cluster fees apply.*

---

## Recommendations Summary

✅ **For Demos/Testing:** Option 1 (3 × m5.xlarge)
✅ **For Small Teams/Production:** Option 2 (3 × m5.2xlarge) ⭐ **RECOMMENDED**
✅ **For Production Scale:** Option 3 (4-5 × m5.2xlarge or larger)

### Minimum Viable Configuration:
- **3 worker nodes** × **m5.xlarge** (4 vCPU, 16 GiB RAM each)
- This provides basic functionality but may have performance constraints

### Optimal Configuration:
- **3 worker nodes** × **m5.2xlarge** (8 vCPU, 32 GiB RAM each)
- Provides good performance with comfortable headroom for growth

---

## Verification Commands

After deployment, verify resource usage:

```bash
# Check total resource requests and usage
oc adm top nodes
oc describe nodes

# Check pod resource usage
oc get pods --all-namespaces -o wide

# Check resource quotas
oc get resourcequota --all-namespaces

# Check persistent volume usage
oc get pvc --all-namespaces
```

---

*Last updated based on: rosa_deployment_enhanced.sh v2.2 (optimized for small clusters)*

