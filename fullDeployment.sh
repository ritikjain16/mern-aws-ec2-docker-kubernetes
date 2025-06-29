#!/bin/bash
set -e

# ----------------------
# Default Configuration
# ----------------------
BACKEND_IMAGE="rj1608/nodejs-app-k8s"
FRONTEND_IMAGE="rj1608/react-vite-k8s"
NAMESPACE="nodejs-app"
ROOT_DIR="/home/ubuntu/kind-cluster/kube-in-one-shot/mern-aws-ec2-docker-kubernetes"

# ----------------------
# Detect EC2 Public IP
# ----------------------
EC2_IP=$(curl -s http://checkip.amazonaws.com)

# Component details
declare -A COMPONENTS=(
  [backend]="$BACKEND_IMAGE:$ROOT_DIR/backend"
  [frontend]="$FRONTEND_IMAGE:$ROOT_DIR/frontend"
)

# ----------------------
# CLI Argument Parsing
# ----------------------
for ARG in "$@"; do
  case $ARG in
    --backend-image=*)
      BACKEND_IMAGE="${ARG#*=}"
      ;;
    --frontend-image=*)
      FRONTEND_IMAGE="${ARG#*=}"
      ;;
    --namespace=*)
      NAMESPACE="${ARG#*=}"
      ;;
    *)
      echo "❌ Unknown argument: $ARG"
      exit 1
      ;;
  esac
done

# ----------------------
# Helper Functions
# ----------------------

pkill -f "kubectl port-forward service/nodejs-app-service"
pkill -f "kubectl port-forward service/react-vite-service"

function deploy_component() {
  local NAME=$1
  local IMAGE=$2
  local APP_DIR=$3
  local K8S_DIR="$APP_DIR/k8s"
  local PORT_FORWARD_LOG="$NAME-portforward.log"

  echo ""
  echo "===================================="
  echo "🚀 Deploying [$NAME] Component"
  echo "===================================="
  echo "🔧 Image       : $IMAGE"
  echo "📁 Directory   : $APP_DIR"

  # Cleanup Kubernetes resources
  echo "📁 Switching to K8s directory: $K8S_DIR"
  cd "$K8S_DIR"

  if [ "$NAME" == "backend" ]; then
    echo "🧹 Deleting old resources (namespace, deployment, service)..."
    kubectl delete -f namespace.yml -f deployment.yml -f service.yml || echo "⚠️ Continue even if delete fails."
  else
    echo "🧹 Deleting old resources (deployment, service)..."
    kubectl delete -f deployment.yml -f service.yml || echo "⚠️ Continue even if delete fails."
  fi

  # Build and push Docker image
  echo "🛠️ Building Docker image..."
  cd "$APP_DIR"
  docker build -t "$IMAGE" .
  echo "📤 Pushing Docker image..."
  docker push "$IMAGE"

  # Apply K8s manifests
  echo "📁 Applying Kubernetes manifests..."
  cd "$K8S_DIR"
  if [ "$NAME" == "backend" ]; then
    kubectl apply -f namespace.yml -f deployment.yml -f service.yml
  else
    kubectl apply -f deployment.yml -f service.yml
  fi

  # Wait for pods
  echo "🔍 Waiting for pods in namespace [$NAMESPACE]..."
  for i in {1..30}; do
    POD_COUNT=$(kubectl get pods -n "$NAMESPACE" --no-headers --ignore-not-found | wc -l)
    if [ "$POD_COUNT" -gt 0 ]; then
      echo "✅ Pods found: $POD_COUNT"
      break
    fi
    echo -n "."
    sleep 1
  done

  if [ "$POD_COUNT" -eq 0 ]; then
    echo "❌ No pods created for [$NAME] within 30 seconds."
    exit 1
  fi

  echo -n "⏳ Waiting for pods to be ready "
  kubectl wait --for=condition=ready pod --all -n "$NAMESPACE" --timeout=60s &
  spin='-\|/'
  while kill -0 $! 2>/dev/null; do
    for i in $(seq 0 3); do
      printf "\b${spin:$i:1}"
      sleep 0.1
    done
  done
  echo -e "\n✅ All pods are ready!"

  # Status checks
  echo "🔍 Getting status..."
  kubectl get pods -n "$NAMESPACE"
  kubectl get deployments -n "$NAMESPACE"
  kubectl get svc -n "$NAMESPACE"

  # Port forwarding
  echo "🌐 Starting port-forwarding for [$NAME]..."
  if [ "$NAME" == "backend" ]; then
    nohup kubectl port-forward service/nodejs-app-service -n "$NAMESPACE" 4000:6000 --address=0.0.0.0 > "$PORT_FORWARD_LOG" 2>&1 &
    echo "🌍 Backend available at: http://$EC2_IP:4000"
  else
    nohup kubectl port-forward service/react-vite-service -n "$NAMESPACE" 3000:80 --address=0.0.0.0 > "$PORT_FORWARD_LOG" 2>&1 &
    echo "🌍 Frontend available at: http://$EC2_IP:3000"
  fi

  echo "📋 kubectl processes:"
  ps aux | grep "[k]ubectl"
  echo "📝 Logs: $PORT_FORWARD_LOG"
  echo "===================================="
}

# ----------------------
# Deployment Flow
# ----------------------

echo "===================================="
echo "🚀 Starting Full Stack Deployment"
echo "===================================="

deploy_component backend "$BACKEND_IMAGE" "${COMPONENTS[backend]#*:}"
deploy_component frontend "$FRONTEND_IMAGE" "${COMPONENTS[frontend]#*:}"

echo "✅ Full Deployment Complete!"
