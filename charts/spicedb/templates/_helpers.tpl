{{/*
Core naming and reference helper functions
This file contains the foundational naming helpers for the SpiceDB chart.

Additional helper functions are organized in focused files:
- _helpers-labels.tpl: Label and selector generation
- _helpers-datastore.tpl: Datastore connection and configuration
- _helpers-tls.tpl: TLS certificate and secret name resolution
- _helpers-operator.tpl: Operator compatibility and migration helpers
- _helpers-patches.tpl: Strategic merge patch validation
- _helpers-deployment.tpl: Deployment, service, and ingress base templates
*/}}

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
Create the name of the service account to use
*/}}
{{- define "spicedb.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "spicedb.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
