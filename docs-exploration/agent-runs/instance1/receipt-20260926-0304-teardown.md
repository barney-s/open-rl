TORN-DOWN

## Summary
All infrastructure, workloads, and cloud storage associated with run instance `or-instance1` have been completely torn down and verified.

## Teardown Evidence

### 1. GKE Cluster & Node Pools
- **Target:** Cluster `or-instance1-gke-dra` (regional `us-central1`, default pool `default-pool` and GPU pool `gpu-dra` with 2x L4 GPUs)
- **Action:** Deleted via `gcloud container clusters delete or-instance1-gke-dra --location=us-central1 --project=barni-cnrm-20260529 --quiet`
- **Verification Query:** `gcloud container clusters list --project="barni-cnrm-20260529"`
- **Result:**
  ```text
  NAME                   LOCATION       MASTER_VERSION      MASTER_IP       MACHINE_TYPE   NODE_VERSION        NUM_NODES  STATUS   STACK_TYPE
  agentenv-k8s1-cluster  us-central1-a  1.35.8-gke.1036000  34.68.55.64     n2-standard-4  1.35.8-gke.1036000  3          RUNNING  IPV4
  ax-instance5           us-central1-a  1.35.8-gke.1036000  34.45.168.90    c3-standard-4  1.35.8-gke.1036000  2          RUNNING  IPV4
  kcc-instance1-cluster  us-central1-a  1.35.8-gke.1036000  104.154.143.24  e2-standard-4  1.35.8-gke.1036000  2          RUNNING  IPV4
  substrat-instance1     us-central1-a  1.36.4-gke.1391000  35.226.195.58   c3-standard-4  1.36.4-gke.1391000  2          RUNNING  IPV4
  ```
  Cluster `or-instance1-gke-dra` is completely removed.

### 2. Compute Engine VMs and Persistent Disks
- **Action:** Checked for orphaned VMs and disks matching `or-instance1` or `repo-agent-instance=or-instance1`.
- **Verification Query:**
  `gcloud compute instances list --project="barni-cnrm-20260529" --filter="name ~ or-instance1 OR labels.repo-agent-instance = or-instance1"`
  `gcloud compute disks list --project="barni-cnrm-20260529" --filter="name ~ or-instance1 OR labels.repo-agent-instance = or-instance1"`
- **Result:**
  ```text
  Listed 0 items.
  Listed 0 items.
  ```

### 3. Cloud Filestore Instance
- **Target:** `pvc-1c437079-1b02-48ab-890b-4664bf9d915b` (1TiB standard-rwx Filestore created for `open-rl-shared-pvc` in `us-central1-a`)
- **Action:** Explicitly deleted via `gcloud filestore instances delete pvc-1c437079-1b02-48ab-890b-4664bf9d915b --project="barni-cnrm-20260529" --zone="us-central1-a" --quiet`
- **Verification Query:** `gcloud filestore instances list --project="barni-cnrm-20260529" --zone="us-central1-a"`
- **Result:**
  ```text
  INSTANCE_NAME                             LOCATION       TIER      CAPACITY_GB  FILE_SHARE_NAME  IP_ADDRESS    STATE     CREATE_TIME
  pvc-d74f3662-94a7-4ad4-a081-430457a8fed8  us-central1-a  STANDARD  1024         vol1             10.223.3.242  DELETING  2026-09-25T21:39:58
  ```
  Instance `pvc-1c437079-1b02-48ab-890b-4664bf9d915b` is completely deleted and no longer exists.

## Remaining Resources
None. All compute, cluster, storage, and networking resources for `or-instance1` have been decommissioned.

## Procedure amended
- **File:** `docs-exploration/runbooks/deploy-gke.md`
- **Changes:** Updated the `## Teardown` section to include `kubectl -n openrl-system delete pvc --all --ignore-not-found` prior to cluster deletion.
- **Reason:** Deleting the PVC while the cluster is still running signals the Filestore CSI driver to delete the underlying Google Cloud Filestore instance, preventing orphaned storage billing. Also updated `docs-exploration/runs/instance1/teardown.sh` to include PVC deletion and orphaned Filestore instance cleanup.
