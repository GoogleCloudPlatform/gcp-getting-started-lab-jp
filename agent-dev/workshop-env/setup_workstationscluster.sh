echo "#########################################"
echo "1. Google Cloud 機能 (API) 有効化"
echo "#########################################"
gcloud services enable  run.googleapis.com \
                        cloudbuild.googleapis.com \
                        workstations.googleapis.com \
                        artifactregistry.googleapis.com \
                        apikeys.googleapis.com \
                        storage.googleapis.com \
                        iam.googleapis.com \
                        compute.googleapis.com \
                        aiplatform.googleapis.com \
                        cloudresourcemanager.googleapis.com \
                        weather.googleapis.com \
                        geocoding-backend.googleapis.com
echo

echo "#########################################"
echo "2. VPC ネットワークの作成"
echo "#########################################"
gcloud compute networks create ws-network \
  --subnet-mode custom
echo

echo "#########################################"
echo "3. サブネットの作成"
echo "#########################################"
gcloud compute networks subnets create ws-subnet \
  --network ws-network \
  --region asia-northeast1 \
  --range "192.168.1.0/24"
echo

echo "#########################################"
echo "4. Cloud Router の作成"
echo "#########################################"
gcloud compute routers create ws-router \
  --network ws-network \
  --region asia-northeast1
echo

echo "#########################################"
echo "5. Cloud NAT の作成"
echo "#########################################"
gcloud compute routers nats create ws-nat \
  --router ws-router \
  --auto-allocate-nat-external-ips \
  --nat-all-subnet-ip-ranges \
  --region asia-northeast1
echo

echo "#########################################"
echo "6. ワークステーションクラスタの作成"
echo "#########################################"
gcloud workstations clusters create workshop-cluster \
  --network "projects/$GOOGLE_CLOUD_PROJECT/global/networks/ws-network" \
  --subnetwork "projects/$GOOGLE_CLOUD_PROJECT/regions/asia-northeast1/subnetworks/ws-subnet" \
  --region asia-northeast1 \
  --async
echo

sleep 5

echo "#########################################"
echo "7. ワークステーションクラスタの作成開始を確認"
echo "#########################################"
gcloud workstations clusters describe workshop-cluster --region asia-northeast1 \
  && echo -e "\nSuccessfully started a cluster creation :)" \
  || echo -e "\nFailed to start a cluster creation :("
  