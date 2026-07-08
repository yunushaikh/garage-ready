{{/*
Expand the name of the chart.
*/}}
{{- define "garage.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "garage.fullname" -}}
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
Chart label
*/}}
{{- define "garage.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "garage.labels" -}}
helm.sh/chart: {{ include "garage.chart" . }}
{{ include "garage.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "garage.selectorLabels" -}}
app.kubernetes.io/name: {{ include "garage.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "garage.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "garage.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
RPC secret resource name
*/}}
{{- define "garage.rpcSecretName" -}}
{{- printf "%s-rpc-secret" (include "garage.fullname" .) }}
{{- end }}

{{/*
Upload credentials secret name
*/}}
{{- define "garage.uploadSecretName" -}}
{{- printf "%s-upload-credentials" (include "garage.fullname" .) }}
{{- end }}

{{/*
Upload details configmap name
*/}}
{{- define "garage.uploadConfigMapName" -}}
{{- printf "%s-upload-details" (include "garage.fullname" .) }}
{{- end }}

{{/*
Returns n random hex characters.
*/}}
{{- define "garage.randHex" -}}
{{- $result := "" }}
{{- range $i := until 100 }}
{{- if lt (len $result) . }}
{{- $rand_list := randAlphaNum . | splitList "" -}}
{{- $reduced_list := without $rand_list "g" "h" "i" "j" "k" "l" "m" "n" "o" "p" "q" "r" "s" "t" "u" "v" "w" "x" "y" "z" "A" "B" "C" "D" "E" "F" "G" "H" "I" "J" "K" "L" "M" "N" "O" "P" "Q" "R" "S" "T" "U" "V" "W" "X" "Y" "Z" }}
{{- $rand_string := join "" $reduced_list }}
{{- $result = print $result $rand_string -}}
{{- end }}
{{- end }}
{{- $result | trunc . }}
{{- end }}

{{/*
Stable RPC secret across upgrades.
*/}}
{{- define "garage.rpcSecret" -}}
{{- $name := include "garage.rpcSecretName" . -}}
{{- $prev := (lookup "v1" "Secret" .Release.Namespace $name) | default dict -}}
{{- $prevData := $prev.data | default dict -}}
{{- $prevValue := $prevData.rpcSecret | default "" | b64dec -}}
{{- .Values.garage.rpcSecret | default $prevValue | default (include "garage.randHex" 64) -}}
{{- end }}

{{/*
Stable admin token across upgrades.
*/}}
{{- define "garage.adminToken" -}}
{{- $name := include "garage.rpcSecretName" . -}}
{{- $prev := (lookup "v1" "Secret" .Release.Namespace $name) | default dict -}}
{{- $prevData := $prev.data | default dict -}}
{{- $prevValue := $prevData.adminToken | default "" | b64dec -}}
{{- .Values.garage.adminToken | default $prevValue | default (randAlphaNum 48) -}}
{{- end }}

{{/*
Stable S3 access key id across upgrades.
*/}}
{{- define "garage.upload.accessKeyId" -}}
{{- $name := include "garage.uploadSecretName" . -}}
{{- $prev := (lookup "v1" "Secret" .Release.Namespace $name) | default dict -}}
{{- $prevData := $prev.data | default dict -}}
{{- $prevValue := $prevData.AWS_ACCESS_KEY_ID | default "" | b64dec -}}
{{- .Values.upload.accessKeyId | default $prevValue | default (printf "GK%s" (include "garage.randHex" 32)) -}}
{{- end }}

{{/*
Stable S3 secret access key across upgrades.
*/}}
{{- define "garage.upload.secretAccessKey" -}}
{{- $name := include "garage.uploadSecretName" . -}}
{{- $prev := (lookup "v1" "Secret" .Release.Namespace $name) | default dict -}}
{{- $prevData := $prev.data | default dict -}}
{{- $prevValue := $prevData.AWS_SECRET_ACCESS_KEY | default "" | b64dec -}}
{{- .Values.upload.secretAccessKey | default $prevValue | default (include "garage.randHex" 64) -}}
{{- end }}

{{/*
In-cluster S3 endpoint URL.
*/}}
{{- define "garage.s3Endpoint" -}}
http://{{ include "garage.fullname" . }}.{{ .Release.Namespace }}.svc.cluster.local:{{ .Values.service.s3.api.port }}
{{- end }}

{{/*
Garage server container args.
*/}}
{{- define "garage.serverArgs" -}}
{{- if .Values.garage.singleNode }}
- --single-node
- --default-bucket
{{- end }}
{{- end }}
