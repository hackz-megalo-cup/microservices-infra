#!/usr/bin/env bash
set -euo pipefail

# Usage: kaniko-build.sh <service-name> [dockerfile-path] [context-path]
# Example: kaniko-build.sh frontend deploy/docker/frontend .
#          kaniko-build.sh game-server deploy/docker/game-server .
#          kaniko-build.sh greeter services/greeter .

SERVICE="${1:?Usage: kaniko-build.sh <service-name> [dockerfile-path] [context-path]}"
DOCKERFILE="${2:-deploy/docker/${SERVICE}}"
CONTEXT="${3:-.}"
REPO="hackz-megalo-cup"
REGISTRY="ghcr.io/${REPO}/${SERVICE}"
TIMESTAMP=$(date +%s)
JOB_NAME="kaniko-${SERVICE}-${TIMESTAMP}"

echo "==> Building ${SERVICE}"
echo "    Dockerfile: ${DOCKERFILE}/Dockerfile"
echo "    Context:    ${CONTEXT}"
echo "    Image:      ${REGISTRY}:latest"

cat <<EOF | kubectl create -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ci
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      initContainers:
        - name: git-clone
          image: alpine/git:latest
          command: ["git", "clone", "--depth=1", "https://github.com/${REPO}/microservices-app.git", "/workspace"]
          volumeMounts:
            - name: workspace
              mountPath: /workspace
      containers:
        - name: kaniko
          image: gcr.io/kaniko-project/executor:latest
          args:
            - --dockerfile=/workspace/${DOCKERFILE}/Dockerfile
            - --context=/workspace/${CONTEXT}
            - --destination=${REGISTRY}:latest
            - --cache=true
            - --cache-repo=${REGISTRY}-cache
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

echo "==> Job ${JOB_NAME} created. Waiting..."
if kubectl wait --for=condition=complete --timeout=600s "job/${JOB_NAME}" -n ci 2>/dev/null; then
  echo "==> Build succeeded!"
  kubectl logs "job/${JOB_NAME}" -n ci -c kaniko --tail=5
else
  echo "==> Build failed. Logs:"
  kubectl logs "job/${JOB_NAME}" -n ci -c kaniko --tail=30
  exit 1
fi
