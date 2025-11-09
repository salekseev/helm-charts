{{/*
Expand the name of the chart.
*/}}
{{- define "spicedb.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "spicedb.fullname" -}}
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
{{- define "spicedb.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "spicedb.labels" -}}
helm.sh/chart: {{ include "spicedb.chart" . }}
{{ include "spicedb.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "spicedb.selectorLabels" -}}
app.kubernetes.io/name: {{ include "spicedb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "spicedb.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "spicedb.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Generate datastore connection string for PostgreSQL and CockroachDB
Returns a properly formatted connection URI with SSL parameters
Supports both legacy config.datastore.ssl* fields and new tls.datastore configuration
*/}}
{{- define "spicedb.datastoreConnectionString" -}}
{{- if .Values.config.datastoreURI -}}
{{- .Values.config.datastoreURI -}}
{{- else if or (eq .Values.config.datastoreEngine "postgres") (eq .Values.config.datastoreEngine "cockroachdb") -}}
{{- $username := .Values.config.datastore.username | urlquery -}}
{{- $password := .Values.config.datastore.password | urlquery -}}
{{- $hostname := .Values.config.datastore.hostname -}}
{{- $port := .Values.config.datastore.port -}}
{{- $database := .Values.config.datastore.database -}}
{{- $sslMode := .Values.config.datastore.sslMode -}}
{{- $sslRootCert := .Values.config.datastore.sslRootCert -}}
{{- $sslCert := .Values.config.datastore.sslCert -}}
{{- $sslKey := .Values.config.datastore.sslKey -}}
{{- if and .Values.tls.enabled .Values.tls.datastore.secretName -}}
{{- $sslMode = "verify-full" -}}
{{- $sslRootCert = .Values.tls.datastore.caPath -}}
{{- end -}}
{{- printf "postgresql://%s:%s@%s:%v/%s?sslmode=%s" $username $password $hostname $port $database $sslMode -}}
{{- if $sslRootCert -}}
{{- printf "&sslrootcert=%s" ($sslRootCert | urlquery) -}}
{{- end -}}
{{- if $sslCert -}}
{{- printf "&sslcert=%s" ($sslCert | urlquery) -}}
{{- end -}}
{{- if $sslKey -}}
{{- printf "&sslkey=%s" ($sslKey | urlquery) -}}
{{- end -}}
{{- end -}}
{{- end }}
