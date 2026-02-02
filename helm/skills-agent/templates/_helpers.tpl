{{/*
Expand the name of the chart.
*/}}
{{- define "skills-agent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "skills-agent.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "skills-agent.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "skills-agent.labels" -}}
helm.sh/chart: {{ include "skills-agent.chart" . }}
{{ include "skills-agent.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "skills-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "skills-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Secret name
*/}}
{{- define "skills-agent.secretName" -}}
{{- if .Values.credentials.create }}
{{- include "skills-agent.fullname" . }}-credentials
{{- else }}
{{- .Values.credentials.existingSecretName }}
{{- end }}
{{- end }}

{{/*
Create the name of the service account to use
Note: serviceAccountName in Pod/Job spec only accepts name, not namespace/name format
The namespace field in serviceAccount configuration is used only when creating
RoleBindings or for documentation purposes - pods cannot use service accounts
from other namespaces directly
*/}}
{{- define "skills-agent.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "skills-agent.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Build the command based on agent type
*/}}
{{- define "skills-agent.command" -}}
{{- if eq .Values.agent "claude" }}
- /bin/sh
- -c
- |
  WORK_DIR="/tmp/agent-logs"
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  LOG_DIR="${WORK_DIR}/${TIMESTAMP}"
  
  echo "Creating log directory: ${LOG_DIR}"
  mkdir -p "${LOG_DIR}"
  
  mkdir -p /home/bun/.claude
  cp /secrets/claude-credentials.json /home/bun/.claude/.credentials.json
  chmod 600 /home/bun/.claude/.credentials.json
  cd /workspace
  
  echo "Starting agent execution..."
  set +e
  claude --dangerously-skip-permissions -p "/{{ .Values.skillName }} {{ .Values.prompt }}" 2>&1 | tee "${LOG_DIR}/agent-execution.log"
  EXIT_CODE=$?
  set -e
  
  echo "Agent execution completed with exit code: ${EXIT_CODE}"
  
  {{- if .Values.storeResults.enabled }}
  if [ ${EXIT_CODE} -eq 0 ]; then
    echo "Uploading results to S3..."
    S3_BUCKET="{{ .Values.storeResults.s3Bucket }}"
    S3_PREFIX="{{ .Values.storeResults.s3Prefix }}"
    S3_PATH="s3://${S3_BUCKET}/${S3_PREFIX}/${TIMESTAMP}/"
    
    {{- if not .Values.storeResults.iamRoleArn }}
    export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
    export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
    export AWS_DEFAULT_REGION="{{ .Values.storeResults.awsRegion }}"
    {{- end }}
    
    aws s3 cp "${LOG_DIR}/" "${S3_PATH}" --recursive
    echo "Results uploaded to: ${S3_PATH}"
  else
    echo "Agent execution failed (exit code ${EXIT_CODE}), skipping S3 upload"
  fi
  {{- else }}
  echo "S3 storage is disabled, logs remain in ${LOG_DIR}"
  {{- end }}
  
  exit ${EXIT_CODE}
{{- else if eq .Values.agent "codex" }}
- /bin/sh
- -c
- |
  WORK_DIR="/tmp/agent-logs"
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  LOG_DIR="${WORK_DIR}/${TIMESTAMP}"
  
  echo "Creating log directory: ${LOG_DIR}"
  mkdir -p "${LOG_DIR}"
  
  mkdir -p /home/bun/.codex
  cp /secrets/codex-auth.json /home/bun/.codex/auth.json
  chmod 600 /home/bun/.codex/auth.json
  cd /workspace
  
  echo "Starting agent execution..."
  set +e
  codex --dangerously-skip-permissions "${{ .Values.skillName }} {{ .Values.prompt }}" 2>&1 | tee "${LOG_DIR}/agent-execution.log"
  EXIT_CODE=$?
  set -e
  
  echo "Agent execution completed with exit code: ${EXIT_CODE}"
  
  {{- if .Values.storeResults.enabled }}
  if [ ${EXIT_CODE} -eq 0 ]; then
    echo "Uploading results to S3..."
    S3_BUCKET="{{ .Values.storeResults.s3Bucket }}"
    S3_PREFIX="{{ .Values.storeResults.s3Prefix }}"
    S3_PATH="s3://${S3_BUCKET}/${S3_PREFIX}/${TIMESTAMP}/"
    
    {{- if not .Values.storeResults.iamRoleArn }}
    export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
    export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
    export AWS_DEFAULT_REGION="{{ .Values.storeResults.awsRegion }}"
    {{- end }}
    
    aws s3 cp "${LOG_DIR}/" "${S3_PATH}" --recursive
    echo "Results uploaded to: ${S3_PATH}"
  else
    echo "Agent execution failed (exit code ${EXIT_CODE}), skipping S3 upload"
  fi
  {{- else }}
  echo "S3 storage is disabled, logs remain in ${LOG_DIR}"
  {{- end }}
  
  exit ${EXIT_CODE}
{{- end }}
{{- end }}
