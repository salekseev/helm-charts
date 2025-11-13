{{/*
TLS certificate and configuration helper functions
This file contains all TLS-related helpers for the SpiceDB chart.
*/}}

{{/*
Check if TLS should be enabled considering operatorStyle override
Returns "true" if TLS should be enabled, empty string otherwise
*/}}
{{- define "spicedb.tlsEnabled" -}}
{{- if .Values.operatorStyle.enabled -}}
{{- if .Values.operatorStyle.tlsSecretName -}}
true
{{- end -}}
{{- else if .Values.tls.enabled -}}
true
{{- end -}}
{{- end -}}

{{/*
Resolve gRPC TLS secret name considering operatorStyle override
Returns the secret name for gRPC TLS certificates
*/}}
{{- define "spicedb.grpcTLSSecretName" -}}
{{- if .Values.operatorStyle.enabled -}}
{{- .Values.operatorStyle.tlsSecretName -}}
{{- else -}}
{{- .Values.tls.grpc.secretName -}}
{{- end -}}
{{- end -}}

{{/*
Resolve HTTP TLS secret name considering operatorStyle override
Returns the secret name for HTTP TLS certificates
*/}}
{{- define "spicedb.httpTLSSecretName" -}}
{{- if .Values.operatorStyle.enabled -}}
{{- .Values.operatorStyle.tlsSecretName -}}
{{- else -}}
{{- .Values.tls.http.secretName -}}
{{- end -}}
{{- end -}}

{{/*
Resolve dispatch TLS secret name considering operatorStyle override
Returns the secret name for dispatch TLS certificates
*/}}
{{- define "spicedb.dispatchTLSSecretName" -}}
{{- if .Values.operatorStyle.enabled -}}
{{- .Values.operatorStyle.tlsSecretName -}}
{{- else -}}
{{- .Values.tls.dispatch.secretName -}}
{{- end -}}
{{- end -}}

{{/*
Resolve dispatch upstream CA secret name considering operatorStyle override
Returns the secret name for dispatch upstream CA certificate
*/}}
{{- define "spicedb.dispatchUpstreamCASecretName" -}}
{{- if .Values.operatorStyle.enabled -}}
{{- .Values.operatorStyle.dispatchUpstreamCASecretName -}}
{{- else -}}
{{- .Values.dispatch.upstreamCASecretName -}}
{{- end -}}
{{- end -}}
