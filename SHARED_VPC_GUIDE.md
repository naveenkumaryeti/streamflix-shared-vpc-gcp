# StreamFlix on GCP Shared VPC - Exact Procedure

Deploys the 3 tiers of this project onto 3 VMs, each in its **own service project**, all using subnets of **one Shared VPC** owned by a **host project**.

```
streamflix-network (HOST)  ── streamflix-shared-vpc 10.10.0.0/16
   web-subnet  10.10.1.0/24 ── sf-web  10.10.1.10  (project: web)   nginx + index.html
   app-subnet  10.10.2.0/24 ── sf-app  10.10.2.10  (project: app)   Flask :5000
   data-subnet 10.10.3.0/24 ── sf-db   10.10.3.10  (project: data)  PostgreSQL :5432
```
Traffic: Internet -> sf-web:80 -> sf-app:5000 -> sf-db:5432 (each hop allowed only from the previous subnet).

## 0. Prerequisites
- Run in Cloud Shell (or gcloud installed) from the unzipped `streamflix/` folder.
- A GCP **Organization** (Shared VPC does not work without one) and a **billing account**.
- Your user needs: `roles/resourcemanager.projectCreator`, `roles/billing.user`, `roles/compute.xpnAdmin` (Shared VPC Admin) at org level.

```bash
gcloud auth login
gcloud organizations list            # note ORGANIZATION_ID   256045864843
gcloud billing accounts list         # note ACCOUNT_ID        011B0A-54E678-F5B554
```

## streamflix-shared-vpc           streamflix-shared-vpc  58439874113

## 1. Set variables (reuse the same shell for all steps)
Project IDs are global, so pick a unique 4-char suffix.
```bash
export SUF=nr01
export ORG_ID=<ORGANIZATION_ID>
export BILLING=<ACCOUNT_ID>
export HOST=streamflix-network-$SUF  WEB=streamflix-web-$SUF  APP=streamflix-app-$SUF  DATA=streamflix-data-$SUF
export REGION=asia-south1  ZONE=asia-south1-a
export VPC=streamflix-shared-vpc
export ME=$(gcloud config get-value account)
```

## 2. Create projects and link billing
Why: 1 host (owns network) + 3 service projects (own workloads). Billing is required to use Compute.
```bash
for P in $HOST $WEB $APP $DATA; do
  gcloud projects create $P --organization=$ORG_ID
  gcloud billing projects link $P --billing-account=$BILLING
done
gcloud projects list --filter="projectId~$SUF"
```

## 3. Enable APIs
```bash
for P in $HOST $WEB $APP $DATA; do
  gcloud services enable compute.googleapis.com iap.googleapis.com --project=$P
done
```

## 4. Create VPC and subnets (in HOST)
Why: custom mode = you define exact ranges.
```bash
gcloud compute networks create $VPC --subnet-mode=custom --project=$HOST

gcloud compute networks subnets create web-subnet  --project=$HOST --network=$VPC --region=$REGION --range=10.10.1.0/24
gcloud compute networks subnets create app-subnet  --project=$HOST --network=$VPC --region=$REGION --range=10.10.2.0/24
gcloud compute networks subnets create data-subnet --project=$HOST --network=$VPC --region=$REGION --range=10.10.3.0/24

gcloud compute networks subnets list --project=$HOST
```

## 5. Enable Shared VPC and attach service projects
Why: turns HOST into a host project and lets the 3 projects use its subnets.
```bash
gcloud compute shared-vpc enable $HOST
for P in $WEB $APP $DATA; do
  gcloud compute shared-vpc associated-projects add $P --host-project=$HOST
done
gcloud compute shared-vpc list-associated-resources $HOST
```
Expected: the 3 service projects listed.

## 6. IAM - allow yourself to use each subnet
Why: creating a VM in a service project on a host subnet needs `compute.networkUser` **on that subnet** (least privilege) plus VM rights in the service project. For a real team, replace `user:$ME` with the team's group.
```bash
for S in web-subnet app-subnet data-subnet; do
  gcloud compute networks subnets add-iam-policy-binding $S \
    --project=$HOST --region=$REGION \
    --member="user:$ME" --role="roles/compute.networkUser"
done
for P in $WEB $APP $DATA; do
  gcloud projects add-iam-policy-binding $P \
    --member="user:$ME" --role="roles/compute.instanceAdmin.v1" --condition=None
done
```

## 7. Firewall rules (in HOST - central control)
Why: the network team controls traffic for all projects. Rules target VMs by network tag.
```bash
F="--project=$HOST --network=$VPC --direction=INGRESS --action=ALLOW"
gcloud compute firewall-rules create sf-allow-web $F --rules=tcp:80   --source-ranges=0.0.0.0/0     --target-tags=web
gcloud compute firewall-rules create sf-allow-app $F --rules=tcp:5000 --source-ranges=10.10.1.0/24  --target-tags=app
gcloud compute firewall-rules create sf-allow-db  $F --rules=tcp:5432 --source-ranges=10.10.2.0/24  --target-tags=db
gcloud compute firewall-rules create sf-allow-iap $F --rules=tcp:22   --source-ranges=35.235.240.0/20 --target-tags=web,app,db
```

## 8. Cloud Router + NAT (in HOST)
Why: app and db VMs have no public IP, but need internet once to `apt install` packages.
```bash
gcloud compute routers create sf-router --project=$HOST --network=$VPC --region=$REGION
gcloud compute routers nats create sf-nat --project=$HOST --router=sf-router --region=$REGION \
  --auto-allocate-nat-external-ips --nat-all-subnet-ip-ranges
```

## 9. Deploy the tiers (order: DB -> App -> Web)
Each VM lives in a **service project** but takes its IP from a **host project subnet** (`--subnet=projects/$HOST/...`). Startup scripts install software and pull this project's own files (`init.sql`, `app.py`, `index.html`, `nginx.conf`) from instance metadata.

```bash
SUBNET=projects/$HOST/regions/$REGION/subnetworks
IMG="--image-family=debian-12 --image-project=debian-cloud --machine-type=e2-small"

# Tier 3 - database (no public IP)
gcloud compute instances create sf-db --project=$DATA --zone=$ZONE $IMG \
  --subnet=$SUBNET/data-subnet --private-network-ip=10.10.3.10 --no-address --tags=db \
  --metadata-from-file=startup-script=scripts/db-startup.sh,init-sql=database/init.sql

# Tier 2 - backend (no public IP)
gcloud compute instances create sf-app --project=$APP --zone=$ZONE $IMG \
  --subnet=$SUBNET/app-subnet --private-network-ip=10.10.2.10 --no-address --tags=app \
  --metadata-from-file=startup-script=scripts/app-startup.sh,app-py=backend/app.py

# Tier 1 - frontend (public IP)
gcloud compute instances create sf-web --project=$WEB --zone=$ZONE $IMG \
  --subnet=$SUBNET/web-subnet --private-network-ip=10.10.1.10 --tags=web \
  --metadata-from-file=startup-script=scripts/web-startup.sh,index-html=frontend/index.html,nginx-conf=frontend/nginx.conf
```
Wait ~3 minutes for startup scripts to finish.

## 10. Verify Shared VPC behaviour
```bash
# VMs in 3 different projects, IPs from host subnets
for P in $DATA $APP $WEB; do gcloud compute instances list --project=$P; done
```
Expected INTERNAL_IP: 10.10.3.10, 10.10.2.10, 10.10.1.10.

## 11. Test the application
```bash
WEB_IP=$(gcloud compute instances describe sf-web --project=$WEB --zone=$ZONE \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
curl http://$WEB_IP/api/health     # {"status":"ok"}  web -> app
curl http://$WEB_IP/api/movies     # JSON, 4 movies   web -> app -> db
echo http://$WEB_IP                # open in browser
```

## 12. Prove isolation (optional)
```bash
# web VM can reach app (allowed)
gcloud compute ssh sf-web --project=$WEB --zone=$ZONE --tunnel-through-iap \
  --command="curl -s 10.10.2.10:5000/api/health"
# web VM cannot reach DB (blocked: only app-subnet allowed)
gcloud compute ssh sf-web --project=$WEB --zone=$ZONE --tunnel-through-iap \
  --command="timeout 5 bash -c '</dev/tcp/10.10.3.10/5432' && echo OPEN || echo BLOCKED"
```
Expected: `{"status":"ok"}` then `BLOCKED`.

## 13. Troubleshooting
| Symptom | Check |
|---|---|
| `/api/movies` 503 | DB not ready/blocked: `gcloud compute ssh sf-db --project=$DATA --zone=$ZONE --tunnel-through-iap --command="sudo systemctl status postgresql"` |
| Startup script problems | `gcloud compute instances get-serial-port-output sf-app --project=$APP --zone=$ZONE \| tail -50` |
| Permission denied on subnet | Step 6 missing `compute.networkUser` |
| Cannot create external IP | Org policy `compute.vmExternalIpAccess`; ask admin to allow for `sf-web` |
| Shared VPC enable fails | Missing `compute.xpnAdmin` or no Organization |

## 14. Cleanup (avoid charges) - order matters
```bash
gcloud compute instances delete sf-db  --project=$DATA --zone=$ZONE -q
gcloud compute instances delete sf-app --project=$APP  --zone=$ZONE -q
gcloud compute instances delete sf-web --project=$WEB  --zone=$ZONE -q
gcloud compute routers nats delete sf-nat --router=sf-router --region=$REGION --project=$HOST -q
gcloud compute routers delete sf-router --region=$REGION --project=$HOST -q
for R in sf-allow-web sf-allow-app sf-allow-db sf-allow-iap; do gcloud compute firewall-rules delete $R --project=$HOST -q; done
for S in web-subnet app-subnet data-subnet; do gcloud compute networks subnets delete $S --region=$REGION --project=$HOST -q; done
gcloud compute networks delete $VPC --project=$HOST -q
for P in $WEB $APP $DATA; do gcloud compute shared-vpc associated-projects remove $P --host-project=$HOST; done
gcloud compute shared-vpc disable $HOST
for P in $WEB $APP $DATA $HOST; do gcloud projects delete $P -q; done
```
