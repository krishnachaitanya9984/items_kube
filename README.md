# Node.js + DynamoDB + Docker + Kubernetes (EKS) — Complete Setup Guide

A step-by-step guide to building a Node.js REST API, connecting it to AWS DynamoDB, containerizing it with Docker, and deploying it on AWS EKS (Kubernetes).

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Prerequisites](#prerequisites)
3. [Phase 1 — Build the Web Service](#phase-1--build-the-web-service)
4. [Phase 2 — Dockerize the App](#phase-2--dockerize-the-app)
5. [Phase 3 — Push Image to AWS ECR](#phase-3--push-image-to-aws-ecr)
6. [Phase 4 — Create EKS Cluster](#phase-4--create-eks-cluster)
7. [Phase 5 — Deploy on Kubernetes](#phase-5--deploy-on-kubernetes)
8. [Testing the Live API](#testing-the-live-api)
9. [Updating Your App](#updating-your-app)
10. [Useful Commands](#useful-commands)
11. [Cleanup](#cleanup)

---

## Project Structure

```
my-app/
├── src/
│   └── index.js              # Main Express application
├── k8s/
│   ├── configmap.yaml        # Kubernetes environment config
│   ├── deployment.yaml       # Kubernetes deployment spec
│   └── service.yaml          # Kubernetes load balancer
├── .dockerignore             # Files to exclude from Docker image
├── .env                      # Local environment variables (never commit)
├── .gitignore                # Files to exclude from Git
├── Dockerfile                # Docker image build instructions
└── package.json              # Node.js project config and dependencies
```

---

## Prerequisites

### Tools to Install

| Tool | Purpose | Download |
|---|---|---|
| Node.js (LTS) | Run JavaScript on server | https://nodejs.org |
| Docker Desktop | Build and run containers | https://www.docker.com/products/docker-desktop |
| AWS CLI | Talk to AWS from terminal | https://aws.amazon.com/cli/ |
| kubectl | Talk to Kubernetes cluster | See install steps below |
| eksctl | Create and manage EKS clusters | See install steps below |

### Install kubectl (Windows)

```powershell
# Download
curl.exe -LO "https://dl.k8s.io/release/v1.29.0/bin/windows/amd64/kubectl.exe"

# Move to a permanent folder
New-Item -ItemType Directory -Force -Path "C:\kubectl"
Move-Item kubectl.exe C:\kubectl\kubectl.exe

# Add to PATH
[System.Environment]::SetEnvironmentVariable(
  "Path",
  $env:Path + ";C:\kubectl",
  [System.EnvironmentVariableTarget]::Machine
)
```

### Install eksctl (Windows)

```powershell
# Download
curl.exe -LO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Windows_amd64.zip"

# Unzip
Expand-Archive eksctl_Windows_amd64.zip -DestinationPath C:\eksctl

# Add to PATH
[System.Environment]::SetEnvironmentVariable(
  "Path",
  $env:Path + ";C:\eksctl",
  [System.EnvironmentVariableTarget]::Machine
)
```

> Close and reopen PowerShell after PATH changes.

### Verify All Tools

```powershell
node --version
docker --version
aws --version
kubectl version --client
eksctl version
```

### Configure AWS CLI

```powershell
aws configure
# Enter: Access Key ID, Secret Access Key, Region (ap-south-1), Output format (json)
```

Verify:
```powershell
aws sts get-caller-identity
```

### VSCode Extensions to Install

- Docker
- Kubernetes
- AWS Toolkit
- Thunder Client (for API testing)

---

## Phase 1 — Build the Web Service

### Step 1 — Initialize Project

```powershell
mkdir my-app
cd my-app
npm init -y
```

### Step 2 — Install Dependencies

```powershell
npm install express @aws-sdk/client-dynamodb @aws-sdk/lib-dynamodb dotenv
npm install --save-dev nodemon
```

### Step 3 — Update package.json scripts

```json
"scripts": {
  "start": "node src/index.js",
  "dev": "nodemon src/index.js"
}
```

### Step 4 — Create .gitignore

```
node_modules/
.env
*.log
```

### Step 5 — Create .env

```
PORT=3000
AWS_REGION=ap-south-1
DYNAMO_TABLE=my-items
```

### Step 6 — Create src/index.js

```javascript
require('dotenv').config();

const express = require('express');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const {
  DynamoDBDocumentClient,
  PutCommand,
  GetCommand,
  ScanCommand,
  DeleteCommand
} = require('@aws-sdk/lib-dynamodb');

const PORT = process.env.PORT || 3000;
const AWS_REGION = process.env.AWS_REGION || 'ap-south-1';
const TABLE_NAME = process.env.DYNAMO_TABLE || 'my-items';

const dynamoClient = new DynamoDBClient({ region: AWS_REGION });
const dynamo = DynamoDBDocumentClient.from(dynamoClient);

const app = express();
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.post('/items', async (req, res) => {
  try {
    const { id, name } = req.body;
    if (!id || !name) return res.status(400).json({ error: 'id and name are required' });
    await dynamo.send(new PutCommand({
      TableName: TABLE_NAME,
      Item: { id, name, createdAt: new Date().toISOString() }
    }));
    res.status(201).json({ message: 'Item created', id });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.get('/items', async (req, res) => {
  try {
    const result = await dynamo.send(new ScanCommand({ TableName: TABLE_NAME }));
    res.json(result.Items || []);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.get('/items/:id', async (req, res) => {
  try {
    const result = await dynamo.send(new GetCommand({
      TableName: TABLE_NAME,
      Key: { id: req.params.id }
    }));
    if (!result.Item) return res.status(404).json({ error: 'Not found' });
    res.json(result.Item);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.delete('/items/:id', async (req, res) => {
  try {
    await dynamo.send(new DeleteCommand({
      TableName: TABLE_NAME,
      Key: { id: req.params.id }
    }));
    res.json({ message: 'Item deleted', id: req.params.id });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
```

### Step 7 — Create DynamoDB Table

```powershell
aws dynamodb create-table `
  --table-name my-items `
  --attribute-definitions AttributeName=id,AttributeType=S `
  --key-schema AttributeName=id,KeyType=HASH `
  --billing-mode PAY_PER_REQUEST `
  --region ap-south-1
```

Verify table exists:
```powershell
aws dynamodb list-tables --region ap-south-1
```

### Step 8 — Run Locally

```powershell
npm run dev
```

### Step 9 — Test API (PowerShell)

```powershell
# Health check
Invoke-WebRequest -Uri "http://localhost:3000/health" -Method GET

# Create item
Invoke-WebRequest -Uri "http://localhost:3000/items" `
  -Method POST `
  -Headers @{"Content-Type" = "application/json"} `
  -Body '{"id":"1","name":"Office Chair"}'

# Get all items
Invoke-WebRequest -Uri "http://localhost:3000/items" -Method GET

# Get one item
Invoke-WebRequest -Uri "http://localhost:3000/items/1" -Method GET

# Delete item
Invoke-WebRequest -Uri "http://localhost:3000/items/1" -Method DELETE
```

---

## Phase 2 — Dockerize the App

### Step 1 — Create .dockerignore

```
node_modules
.env
*.log
.git
npm-debug.log
```

### Step 2 — Create Dockerfile

```dockerfile
FROM node:20-alpine

WORKDIR /app

COPY package*.json ./

RUN npm install --production

COPY src/ ./src/

EXPOSE 3000

CMD ["node", "src/index.js"]
```

### Step 3 — Build Docker Image

```powershell
docker build -t my-app:v1 .
```

Verify image was created:
```powershell
docker images
```

### Step 4 — Run Container Locally

```powershell
docker run -d `
  --name my-app-container `
  -p 3000:3000 `
  -e AWS_REGION=ap-south-1 `
  -e DYNAMO_TABLE=my-items `
  -e AWS_ACCESS_KEY_ID=your_actual_key `
  -e AWS_SECRET_ACCESS_KEY=your_actual_secret `
  my-app:v1
```

### Step 5 — Verify Container is Running

```powershell
docker ps
docker logs my-app-container
```

---

## Phase 3 — Push Image to AWS ECR

### Step 1 — Get Your AWS Account ID

```powershell
aws sts get-caller-identity
```

Copy the `Account` value (12-digit number).

### Step 2 — Create ECR Repository

```powershell
aws ecr create-repository `
  --repository-name my-app `
  --region ap-south-1
```

Copy the `repositoryUri` from the output.

### Step 3 — Authenticate Docker to ECR

```powershell
aws ecr get-login-password --region ap-south-1 | `
  docker login `
  --username AWS `
  --password-stdin `
  YOUR_ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com
```

You should see: `Login Succeeded`

### Step 4 — Tag the Image

```powershell
docker tag my-app:v1 `
  YOUR_ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com/my-app:v1
```

### Step 5 — Push to ECR

```powershell
docker push YOUR_ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com/my-app:v1
```

### Step 6 — Verify Image in ECR

```powershell
aws ecr list-images `
  --repository-name my-app `
  --region ap-south-1
```

---

## Phase 4 — Create EKS Cluster

### Step 1 — Create the Cluster

> This takes approximately 15 minutes.

```powershell
eksctl create cluster `
  --name my-cluster `
  --region ap-south-1 `
  --nodegroup-name workers `
  --node-type t3.medium `
  --nodes 2 `
  --nodes-min 1 `
  --nodes-max 3 `
  --managed
```

### Step 2 — Connect kubectl to Cluster

```powershell
aws eks update-kubeconfig `
  --name my-cluster `
  --region ap-south-1
```

### Step 3 — Verify Nodes are Ready

```powershell
kubectl get nodes
```

Both nodes should show `Ready` status.

### Step 4 — Enable OIDC Provider

```powershell
eksctl utils associate-iam-oidc-provider `
  --cluster my-cluster `
  --region ap-south-1 `
  --approve
```

### Step 5 — Create IAM Service Account for DynamoDB Access

```powershell
eksctl create iamserviceaccount `
  --cluster my-cluster `
  --namespace default `
  --name my-app-sa `
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess `
  --approve `
  --region ap-south-1
```

### Step 6 — Verify Service Account

```powershell
kubectl get serviceaccount my-app-sa
```

### Step 7 — Attach ECR Pull Permission to Node Group

```powershell
# Get node group role name
aws eks describe-nodegroup `
  --cluster-name my-cluster `
  --nodegroup-name workers `
  --region ap-south-1 `
  --query "nodegroup.nodeRole" `
  --output text

# Attach ECR read policy (replace role name with output from above)
aws iam attach-role-policy `
  --role-name YOUR_NODE_ROLE_NAME `
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

---

## Phase 5 — Deploy on Kubernetes

### Step 1 — Create k8s/configmap.yaml

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-app-config
  namespace: default
data:
  AWS_REGION: "ap-south-1"
  DYNAMO_TABLE: "my-items"
  PORT: "3000"
```

### Step 2 — Create k8s/deployment.yaml

> Replace `YOUR_ACCOUNT_ID` with your actual AWS Account ID.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-app
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: my-app
    spec:
      serviceAccountName: my-app-sa
      containers:
        - name: my-app
          image: YOUR_ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com/my-app:v1
          ports:
            - containerPort: 3000
          envFrom:
            - configMapRef:
                name: my-app-config
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 15
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 5
            periodSeconds: 10
```

### Step 3 — Create k8s/service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-service
  namespace: default
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 3000
```

### Step 4 — Apply All Manifests

```powershell
kubectl apply -f k8s/
```

### Step 5 — Verify Pods are Running

```powershell
kubectl get pods
```

Both pods should show `1/1 Running` status.

### Step 6 — Get Public URL

```powershell
kubectl get service my-app-service
```

Wait 2-3 minutes for the `EXTERNAL-IP` column to populate. That is your public API URL.

---

## Testing the Live API

Replace `YOUR_EXTERNAL_IP` with the value from `kubectl get service my-app-service`.

```powershell
# Health check
Invoke-WebRequest -Uri "http://YOUR_EXTERNAL_IP/health" -Method GET

# Create item
Invoke-WebRequest -Uri "http://YOUR_EXTERNAL_IP/items" `
  -Method POST `
  -Headers @{"Content-Type" = "application/json"} `
  -Body '{"id":"1","name":"Office Chair"}'

# Get all items
Invoke-WebRequest -Uri "http://YOUR_EXTERNAL_IP/items" -Method GET

# Get one item
Invoke-WebRequest -Uri "http://YOUR_EXTERNAL_IP/items/1" -Method GET

# Delete item
Invoke-WebRequest -Uri "http://YOUR_EXTERNAL_IP/items/1" -Method DELETE
```

---

## Updating Your App

When you make code changes and want to deploy a new version:

```powershell
# 1. Build new image with incremented tag
docker build -t my-app:v2 .

# 2. Tag for ECR
docker tag my-app:v2 YOUR_ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com/my-app:v2

# 3. Push to ECR
docker push YOUR_ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com/my-app:v2

# 4. Update the deployment (zero downtime rolling update)
kubectl set image deployment/my-app my-app=YOUR_ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com/my-app:v2

# 5. Watch the rollout
kubectl rollout status deployment/my-app
```

---

## Useful Commands

### Docker

```powershell
# List running containers
docker ps

# List all containers including stopped
docker ps -a

# View container logs
docker logs my-app-container

# Follow logs in real time
docker logs -f my-app-container

# Stop container
docker stop my-app-container

# Start container
docker start my-app-container

# Remove container
docker rm my-app-container

# List all images
docker images

# Remove image
docker rmi my-app:v1

# Open shell inside container
docker exec -it my-app-container sh
```

### Kubernetes

```powershell
# List all pods
kubectl get pods

# List pods with more details
kubectl get pods -o wide

# Describe a pod (shows events and errors)
kubectl describe pod POD_NAME

# View pod logs
kubectl logs POD_NAME

# Follow pod logs in real time
kubectl logs -f POD_NAME

# View logs from all pods with a label
kubectl logs -f -l app=my-app

# List all services
kubectl get services

# List deployments
kubectl get deployments

# Scale replicas manually
kubectl scale deployment my-app --replicas=4

# Roll back to previous version
kubectl rollout undo deployment/my-app

# Restart all pods in a deployment
kubectl rollout restart deployment/my-app

# View cluster info
kubectl cluster-info

# View all resources in default namespace
kubectl get all
```

### AWS

```powershell
# List DynamoDB tables
aws dynamodb list-tables --region ap-south-1

# List ECR repositories
aws ecr describe-repositories --region ap-south-1

# List images in a repository
aws ecr list-images --repository-name my-app --region ap-south-1

# List EKS clusters
aws eks list-clusters --region ap-south-1

# Check current AWS identity
aws sts get-caller-identity
```

---

## Cleanup

> Run these commands when you are done to avoid ongoing AWS charges.

```powershell
# Delete Kubernetes resources
kubectl delete -f k8s/

# Delete EKS cluster (takes ~10 minutes)
eksctl delete cluster --name my-cluster --region ap-south-1

# Delete DynamoDB table
aws dynamodb delete-table --table-name my-items --region ap-south-1

# Delete ECR repository and all images
aws ecr delete-repository `
  --repository-name my-app `
  --force `
  --region ap-south-1
```

---

## Cost Estimate While Running

| Resource | Cost |
|---|---|
| EKS Control Plane | ~$0.10/hour |
| 2 x t3.medium EC2 nodes | ~$0.08/hour |
| DynamoDB (on-demand) | Pay per request |
| ECR storage | ~$0.10/GB/month |
| **Total (approx)** | **~$0.18/hour (~$4.30/day)** |

Always delete the cluster when not in use.
