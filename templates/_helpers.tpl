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

{{/* ======================================================================
   ODK Central helpers
   ====================================================================== */}}

{{/*
ODK Central fullname
*/}}
{{- define "odk-central.fullname" -}}
{{- printf "%s-odk-central" (include "farmer-registry.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
ODK Central common labels
*/}}
{{- define "odk-central.labels" -}}
helm.sh/chart: {{ include "farmer-registry.chart" . }}
{{ include "odk-central.selectorLabels" . }}
app.kubernetes.io/version: {{ (.Values.odkCentral.image).tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ include "farmer-registry.name" . }}
{{- end }}

{{/*
ODK Central selector labels (backend)
*/}}
{{- define "odk-central.selectorLabels" -}}
app.kubernetes.io/name: {{ include "farmer-registry.name" . }}-odk-central
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: odk-central
{{- end }}

{{/*
ODK Central frontend selector labels
*/}}
{{- define "odk-central.frontendSelectorLabels" -}}
app.kubernetes.io/name: {{ include "farmer-registry.name" . }}-odk-frontend
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: odk-frontend
{{- end }}

{{/*
ODK Central frontend labels
*/}}
{{- define "odk-central.frontendLabels" -}}
helm.sh/chart: {{ include "farmer-registry.chart" . }}
{{ include "odk-central.frontendSelectorLabels" . }}
app.kubernetes.io/version: {{ (.Values.odkCentral.frontend.image).tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ include "farmer-registry.name" . }}
{{- end }}

{{/*
ODK Central ServiceAccount name
*/}}
{{- define "odk-central.serviceAccountName" -}}
{{- if .Values.odkCentral.serviceAccount.create }}
{{- default (include "odk-central.fullname" .) .Values.odkCentral.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.odkCentral.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
ODK Central backend fullname
*/}}
{{- define "odk-central.backendFullname" -}}
{{- printf "%s-backend" (include "odk-central.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
ODK Central frontend fullname
*/}}
{{- define "odk-central.frontendFullname" -}}
{{- printf "%s-frontend" (include "odk-central.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
ODK Central Enketo fullname
*/}}
{{- define "odk-central.enketoFullname" -}}
{{- printf "%s-enketo" (include "odk-central.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
ODK Central Pyxform fullname
*/}}
{{- define "odk-central.pyxformFullname" -}}
{{- printf "%s-pyxform" (include "odk-central.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
ODK Central PVC name
*/}}
{{- define "odk-central.pvcName" -}}
{{- if .Values.odkCentral.persistence.existingClaim }}
{{- .Values.odkCentral.persistence.existingClaim }}
{{- else }}
{{- printf "%s-data" (include "odk-central.fullname" .) }}
{{- end }}
{{- end }}

{{/*
ODK Central internal PostgreSQL fullname
*/}}
{{- define "odk-central.postgresFullname" -}}
{{- printf "%s-postgresql" (include "odk-central.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Determine the ODK Central database host.
If internal PG is enabled, point to the internal StatefulSet service;
otherwise use the external host.
*/}}
{{- define "odk-central.dbHost" -}}
{{- if .Values.odkCentral.database.internal.enabled }}
{{- include "odk-central.postgresFullname" . }}
{{- else }}
{{- .Values.odkCentral.database.external.host }}
{{- end }}
{{- end }}

{{/*
Determine the ODK Central database port.
*/}}
{{- define "odk-central.dbPort" -}}
{{- if .Values.odkCentral.database.internal.enabled }}
{{- "5432" }}
{{- else }}
{{- .Values.odkCentral.database.external.port | default "5432" | toString }}
{{- end }}
{{- end }}

{{/*
Determine the ODK Central database name.
*/}}
{{- define "odk-central.dbName" -}}
{{- if .Values.odkCentral.database.internal.enabled }}
{{- .Values.odkCentral.database.external.database | default "odkdb" }}
{{- else }}
{{- .Values.odkCentral.database.external.database | default "odkdb" }}
{{- end }}
{{- end }}

{{/*
Determine the ODK Central database user.
*/}}
{{- define "odk-central.dbUser" -}}
{{- if .Values.odkCentral.database.internal.enabled }}
{{- .Values.odkCentral.database.external.username | default "odkuser" }}
{{- else }}
{{- .Values.odkCentral.database.external.username | default "odkuser" }}
{{- end }}
{{- end }}

{{/*
Determine the ODK Central database password secret name.
*/}}
{{- define "odk-central.dbPasswordSecretName" -}}
{{- if .Values.odkCentral.database.internal.enabled }}
{{- include "odk-central.postgresFullname" . }}
{{- else }}
{{- .Values.odkCentral.database.external.existingSecret }}
{{- end }}
{{- end }}

{{/*
Determine the ODK Central database password secret key.
*/}}
{{- define "odk-central.dbPasswordSecretKey" -}}
{{- if .Values.odkCentral.database.internal.enabled }}
{{- "postgres-password" }}
{{- else }}
{{- (.Values.odkCentral.database.external.secretKeys).password | default "password" }}
{{- end }}
{{- end }}

{{/*
ODK Central Enketo secret name (for the API key).
*/}}
{{- define "odk-central.enketoSecretName" -}}
{{- if .Values.odkCentral.enketo.existingSecret }}
{{- .Values.odkCentral.enketo.existingSecret }}
{{- else }}
{{- include "odk-central.enketoFullname" . }}
{{- end }}
{{- end }}
