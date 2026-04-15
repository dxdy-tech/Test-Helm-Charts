{{/*
Expand the name of the chart.
*/}}
{{- define "farmer-registry.name" -}}
{{- default .Chart.Name .Values.global.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "farmer-registry.fullname" -}}
{{- if .Values.global.fullnameOverride }}
{{- .Values.global.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.global.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Chart label values.
*/}}
{{- define "farmer-registry.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* ======================================================================
   Social Registry helpers
   ====================================================================== */}}

{{/*
Social Registry fullname
*/}}
{{- define "social-registry.fullname" -}}
{{- printf "%s-social-registry" (include "farmer-registry.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Social Registry common labels
*/}}
{{- define "social-registry.labels" -}}
helm.sh/chart: {{ include "farmer-registry.chart" . }}
{{ include "social-registry.selectorLabels" . }}
app.kubernetes.io/version: {{ (.Values.socialRegistry.image).tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ include "farmer-registry.name" . }}
{{- end }}

{{/*
Social Registry selector labels
*/}}
{{- define "social-registry.selectorLabels" -}}
app.kubernetes.io/name: {{ include "farmer-registry.name" . }}-social-registry
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: social-registry
{{- end }}

{{/*
Social Registry ServiceAccount name
*/}}
{{- define "social-registry.serviceAccountName" -}}
{{- if .Values.socialRegistry.serviceAccount.create }}
{{- default (include "social-registry.fullname" .) .Values.socialRegistry.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.socialRegistry.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Social Registry configmap name
*/}}
{{- define "social-registry.configmapName" -}}
{{- printf "%s-config" (include "social-registry.fullname" .) }}
{{- end }}

{{/*
Social Registry PVC name
*/}}
{{- define "social-registry.pvcName" -}}
{{- if .Values.socialRegistry.persistence.existingClaim }}
{{- .Values.socialRegistry.persistence.existingClaim }}
{{- else }}
{{- printf "%s-filestore" (include "social-registry.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Render the comma-separated Odoo module list from the values array.
Returns an empty string if the list is empty or nil.
*/}}
{{- define "social-registry.moduleList" -}}
{{- if .Values.socialRegistry.odoo.modules }}
{{- join "," .Values.socialRegistry.odoo.modules }}
{{- end }}
{{- end }}
