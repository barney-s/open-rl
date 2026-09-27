TORN-DOWN

## Teardown Information
- **Instance ID:** rel1
- **Runbook:** `docs-exploration/runbooks/deploy-rel.md`
- **Resource Prefix:** `or-rel1`
- **GCP Project:** `barni-cnrm-20260529`
- **Region / Zone:** `us-central1` / `us-central1-a`
- **Cluster Name:** `or-rel1-gke-rel`
- **Teardown Timestamp:** `2026-09-27T04:06:00Z`

---

## Verification Checklist & Removal Evidence

### 1. GKE Cluster & Node Pools
- **Target:** `or-rel1-gke-rel` (regional cluster in `us-central1` with default pool and GPU DRA pool `gpu-dra`)
- **Status:** REMOVED
- **Evidence:**
  ```text
  $ gcloud container clusters describe or-rel1-gke-rel --location=us-central1
  ERROR: (gcloud.container.clusters.describe) ResponseError: code=404, message=Not found: projects/barni-cnrm-20260529/locations/us-central1/clusters/or-rel1-gke-rel.
  ```
  Completed GKE delete operation:
  `operation-1790391382970-c73ef0fd-8e0a-456a-af50-806d75ac4db2` (DELETE_CLUSTER target `or-rel1-gke-rel`, status DONE at 2026-09-26T03:01:00Z).

### 2. Filestore Storage Instances
- **Target:** 1TiB Filestore instance `pvc-d74f3662-94a7-4ad4-a081-430457a8fed8` in `us-central1-a` created dynamically by Filestore CSI driver for `open-rl-shared-pvc`
- **Status:** REMOVED
- **Evidence:**
  ```text
  $ gcloud filestore instances list --project=barni-cnrm-20260529
  Listed 0 items.
  ```
  Completed Filestore delete operation:
  `operation-1790391681135-65c5a0c29b49a-8608be2d-5f1828a6` (delete target `pvc-d74f3662-94a7-4ad4-a081-430457a8fed8`, status DONE at 2026-09-26T03:01:21Z).

### 3. Compute Engine Instances & Disks
- **Target:** VMs and persistent disks named or labeled `or-rel1` / `repo-agent-instance=or-rel1`
- **Status:** REMOVED
- **Evidence:**
  ```text
  $ gcloud compute instances list --project=barni-cnrm-20260529 --filter="name ~ or-rel1 OR labels.repo-agent-instance=or-rel1"
  Listed 0 items.

  $ gcloud compute disks list --project=barni-cnrm-20260529 --filter="name ~ or-rel1 OR labels.repo-agent-instance=or-rel1"
  Listed 0 items.
  ```

### 4. Networking Rules & Forwarding
- **Target:** Firewalls, forwarding rules, and routes matching `or-rel1`
- **Status:** REMOVED
- **Evidence:**
  ```text
  $ gcloud compute firewall-rules list --filter="name ~ or-rel1" --format="value(name)"
  (empty)

  $ gcloud compute forwarding-rules list --filter="name ~ or-rel1"
  Listed 0 items.
  ```

---

## Remaining Resources
None. All cloud infrastructure, compute resources, GKE node pools, workloads, and Filestore shares associated with instance `rel1` / prefix `or-rel1` are fully destroyed.

---

## Script Adjustments
- Updated `docs-exploration/agent-runs/rel1/teardown.sh` to check cluster existence before invoking `gcloud container clusters delete`, guaranteeing idempotent execution when resources are already deleted.
