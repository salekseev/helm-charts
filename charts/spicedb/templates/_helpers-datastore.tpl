{{/*
Datastore configuration helper functions
This file contains all datastore connection and configuration helpers for the SpiceDB chart.
*/}}

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

{{/*
Resolve datastore engine considering operatorStyle override
Returns the effective datastore engine to use
*/}}
{{- define "spicedb.datastoreEngine" -}}
{{- if .Values.operatorStyle.enabled -}}
{{- .Values.operatorStyle.datastoreEngine -}}
{{- else -}}
{{- .Values.config.datastoreEngine -}}
{{- end -}}
{{- end -}}

{{/*
Resolve existing secret name considering operatorStyle override
Returns the effective secret name to use for credentials
*/}}
{{- define "spicedb.existingSecret" -}}
{{- if .Values.operatorStyle.enabled -}}
{{- .Values.operatorStyle.secretName -}}
{{- else -}}
{{- .Values.config.existingSecret -}}
{{- end -}}
{{- end -}}
