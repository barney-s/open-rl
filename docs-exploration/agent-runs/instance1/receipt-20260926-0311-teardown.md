TORN-DOWN

## Summary
All infrastructure, workloads, and cloud storage associated with run instance `or-instance1` have been completely torn down and verified.

## Teardown Evidence

### 1. GKE Cluster & Node Pools
- **Target:** Cluster `or-instance1-gke-dra` (regional `us-central1`, default pool `default-pool` and GPU pool `gpu-dra` with 2x NVIDIA L4 GPUs)
- **Action:** Checked and confirmed deleted via `gcloud container clusters list --project="barni-cnrm-20260529"`
- **Result:**
  ```text
  NAME                   LOCATION       MASTER_VERSION      MASTER_IP       MACHINE_TYPE   NODE_VERSION        NUM_NODES  STATUS   STACK_TYPE
  agentenv-k8s1-cluster  us-central1-a  1.35.8-gke.1036000  34.68.55.64     n2-standard-4  1.35.8-gke.1036000  3          RUNNING  IPV4
  ax-instance5           us-central1-a  1.35.8-gke.1036000  34.45.168.90    c3-standard-4  1.35.8-gke.1036000  2          RUNNING  IPV4
  kcc-instance1-cluster  us-central1-a  1.35.8-gke.1036000  104.154.143.24  e2-standard-4  1.35.8-gke.1036000  2          RUNNING  IPV4
  substrat-instance1     us-central1-a  1.36.4-gke.1391000  35.226.195.58   c3-standard-4  1.36.4-gke.1391000  2          RUNNING  IPV4
  ```
  Cluster `or-instance1-gke-dra` does not exist.

### 2. Compute Engine VMs and Persistent Disks
- **Action:** Searched for instances and disks matching prefix `or-instance1` or label `repo-agent-instance=or-instance1`.
- **Verification Query:**
  - `gcloud compute instances list --project="barni-cnrm-20260529" --filter="name ~ or-instance1 OR labels.repo-agent-instance = or-instance1"`
  - `gcloud compute disks list --project="barni-cnrm-20260529" --filter="name ~ or-instance1 OR labels.repo-agent-instance = or-instance1"`
- **Result:**
  ```text
  Listed 0 items.
  Listed 0 items.
  ```

### 3. Google Cloud Filestore Instances
- **Action:** Listed all Filestore instances in project `barni-cnrm-20260529`.
- **Verification Query:** `gcloud filestore instances list --project="barni-cnrm-20260529"`
- **Result:**
  ```text
  Listed 0 items.
  ```

### 4. Networking and Forwarding Rules
- **Action:** Searched for forwarding rules, static IPs, and firewall rules matching `or-instance1`.
- **Verification Query:**
  - `gcloud compute forwarding-rules list --project="barni-cnrm-20260529" --filter="name ~ or-instance1"`
  - `gcloud compute addresses list --project="barni-cnrm-20260529" --filter="name ~ or-instance1"`
  - `gcloud compute firewall-rules list --project="barni-cnrm-20260529" --filter="name ~ or-instance1"`
- **Result:**
  ```text
  Listed 0 items.
  Listed 0 items.
  Listed 0 items.
  ```

## Remaining Resources
None. All compute, cluster, storage, and networking resources for `or-instance1` have been decommissioned.

## Procedure amended
- **File:** `docs-exploration/runbooks/deploy-gke.md`
- **Changes:** Updated the `## Teardown` section to explicitly include `kubectl -n openrl-system delete pvc --all --ignore-not-found` prior to deleting the cluster.
- **Reason:** Deleting the PVC while the cluster is still active triggers the Filestore CSI driver to cleanly remove the underlying Google Cloud Filestore instance, preventing orphaned storage instances and associated costs.
