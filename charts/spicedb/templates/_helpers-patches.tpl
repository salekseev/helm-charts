{{/*
Strategic merge patch helper functions
This file contains all patch validation and application helpers for the SpiceDB chart.
*/}}

{{/*
Validate that patches are valid YAML objects
Fails template rendering if patches contain invalid data
*/}}
{{- define "spicedb.validatePatches" -}}
{{- if .Values.patches }}
{{- if .Values.patches.deployment }}
{{- range $index, $patch := .Values.patches.deployment }}
{{- if not (kindIs "map" $patch) }}
{{- fail (printf "patches.deployment[%d] must be a YAML object (map), got %s" $index (kindOf $patch)) }}
{{- end }}
{{- end }}
{{- end }}
{{- if .Values.patches.service }}
{{- range $index, $patch := .Values.patches.service }}
{{- if not (kindIs "map" $patch) }}
{{- fail (printf "patches.service[%d] must be a YAML object (map), got %s" $index (kindOf $patch)) }}
{{- end }}
{{- end }}
{{- end }}
{{- if .Values.patches.ingress }}
{{- range $index, $patch := .Values.patches.ingress }}
{{- if not (kindIs "map" $patch) }}
{{- fail (printf "patches.ingress[%d] must be a YAML object (map), got %s" $index (kindOf $patch)) }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
