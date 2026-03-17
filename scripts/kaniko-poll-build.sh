#!/usr/bin/env bash
set -euo pipefail

# Poll microservices-app main branch and trigger Kaniko builds for changed services.
# Designed to run as a CronJob in-cluster.

REPO_URL="https://github.com/hackz-megalo-cup/microservices-app.git"
REGISTRY="ghcr.io/hackz-megalo-cup"
NAMESPACE="ci"
STATE_DIR="/state"

CURRENT_SHA=$(git ls-remote "$REPO_URL" refs/heads/main | awk '{print $1}')
PREV_SHA=""

if [ -f "${STATE_DIR}/last-sha" ]; then
  PREV_SHA=$(cat "${STATE_DIR}/last-sha")
fi

if [ "$CURRENT_SHA" = "$PREV_SHA" ]; then
  echo "No changes (${CURRENT_SHA:0:8}). Skipping."
  exit 0
fi

echo "Change detected: ${PREV_SHA:0:8} -> ${CURRENT_SHA:0:8}"

# Clone to check which services changed
WORKDIR=$(mktemp -d)
git clone --depth=50 "$REPO_URL" "$WORKDIR" 2>/dev/null

cd "$WORKDIR"

# Determine changed paths
if [ -n "$PREV_SHA" ] && git cat-file -e "$PREV_SHA" 2>/dev/null; then
  CHANGED=$(git diff --name-only "$PREV_SHA" "$CURRENT_SHA")
else
  echo "First run or shallow clone — building all services."
  CHANGED="frontend/ game-server/ services/"
fi

# Map changed paths to services and their Dockerfiles
declare -A SERVICES=(
  ["frontend"]="deploy/docker/frontend"
  ["game-server"]="deploy/docker/game-server"
  ["auth-service"]="deploy/docker/auth-service"
  ["gateway"]="deploy/docker/gateway"
  ["greeter"]="deploy/docker/greeter"
  ["caller"]="deploy/docker/caller"
  ["item"]="deploy/docker/item"
  ["masterdata"]="deploy/docker/masterdata"
  ["custom-lang-service"]="deploy/docker/custom-lang-service"
)

declare -A TRIGGERS=(
  ["frontend"]="frontend/"
  ["game-server"]="game-server/"
  ["auth-service"]="node-services/auth"
  ["gateway"]="services/gateway"
  ["greeter"]="services/greeter"
  ["caller"]="services/caller"
  ["item"]="services/item"
  ["masterdata"]="services/masterdata"
  ["custom-lang-service"]="node-services/custom-lang"
)

BUILT=0
for SERVICE in "${!TRIGGERS[@]}"; do
  TRIGGER="${TRIGGERS[$SERVICE]}"
  DOCKERFILE="${SERVICES[$SERVICE]}"

  if echo "$CHANGED" | grep -q "^${TRIGGER}\|^proto/\|^deploy/docker/${SERVICE}"; then
    echo "==> Building ${SERVICE} (matched: ${TRIGGER})"
    TIMESTAMP=$(date +%s)
    JOB_NAME="kaniko-${SERVICE}-${TIMESTAMP}"

    cat <<EOF | kubectl create -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: kaniko-builder
    service: ${SERVICE}
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      initContainers:
        - name: git-clone
          image: alpine/git:latest
          command: ["git", "clone", "--depth=1", "${REPO_URL}", "/workspace"]
          volumeMounts:
            - name: workspace
              mountPath: /workspace
      containers:
        - name: kaniko
          image: gcr.io/kaniko-project/executor:latest
          args:
            - --dockerfile=/workspace/${DOCKERFILE}/Dockerfile
            - --context=/workspace/.
            - --destination=${REGISTRY}/${SERVICE}:latest
            - --cache=true
            - --cache-repo=${REGISTRY}/${SERVICE}-cache
            - --snapshot-mode=redo
            - --compressed-caching=false
          volumeMounts:
            - name: workspace
              mountPath: /workspace
            - name: docker-config
              mountPath: /kaniko/.docker
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: "1"
              memory: 2Gi
      volumes:
        - name: workspace
          emptyDir: {}
        - name: docker-config
          secret:
            secretName: ghcr-push-secret
            items:
              - key: .dockerconfigjson
                path: config.json
EOF
    BUILT=$((BUILT + 1))
  fi
done

rm -rf "$WORKDIR"

if [ "$BUILT" -eq 0 ]; then
  echo "No service changes detected. Skipping builds."
fi

# Save current SHA
echo "$CURRENT_SHA" > "${STATE_DIR}/last-sha"
echo "Done. Built ${BUILT} service(s)."
