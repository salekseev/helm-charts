{{/*
Operator compatibility helper functions
This file contains all operator-compatibility and migration-related helpers for the SpiceDB chart.
*/}}

{{/*
Resolve replica count considering operatorStyle override
Returns the effective number of replicas to use
*/}}
{{- define "spicedb.replicas" -}}
{{- if .Values.operatorStyle.enabled -}}
{{- .Values.operatorStyle.replicas -}}
{{- else -}}
{{- .Values.replicaCount -}}
{{- end -}}
{{- end -}}

{{/*
Generate hash of migration configuration
Returns a SHA256 hash of the migration settings to detect configuration changes
Used by operator-compatible annotations to track migration state
*/}}
{{- define "spicedb.migrationHash" -}}
{{- $migrationsConfig := dict -}}
{{- $_ := set $migrationsConfig "enabled" .Values.migrations.enabled -}}
{{- $_ := set $migrationsConfig "targetMigration" (.Values.migrations.targetMigration | default "") -}}
{{- $_ := set $migrationsConfig "targetPhase" (.Values.migrations.targetPhase | default "") -}}
{{- $_ := set $migrationsConfig "datastoreEngine" (include "spicedb.datastoreEngine" .) -}}
{{- $_ := set $migrationsConfig "logLevel" (.Values.migrations.logLevel | default .Values.logging.level) -}}
{{- $migrationsConfig | toJson | sha256sum -}}
{{- end -}}

{{/*
Compare migration hashes to detect configuration changes
Returns "true" if migration configuration has changed, empty string otherwise
*/}}
{{- define "spicedb.migrationHashChanged" -}}
{{- $currentHash := include "spicedb.migrationHash" . -}}
{{- $previousHash := .Values.previousMigrationHash | default "" -}}
{{- ne $currentHash $previousHash -}}
{{- end -}}

{{/*
Generate a cryptographically secure random preshared key
Returns a base64-encoded 32-byte random value
This meets SpiceDB's minimum requirement and uses cryptographically secure random bytes
*/}}
{{- define "spicedb.generatePresharedKey" -}}
{{- randBytes 32 | b64enc -}}
{{- end -}}
