{{/*
Deployment and service helper functions
This file contains all deployment, service, and ingress base template helpers for the SpiceDB chart.
*/}}

{{/*
Base deployment template without patches applied
This generates the complete Deployment resource structure based on values
Used by the patch system to create a base that can be patched
*/}}
{{- define "spicedb.deployment.base" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "spicedb.fullname" . }}
  labels:
    {{- include "spicedb.labels" . | nindent 4 }}
spec:
  replicas: {{ include "spicedb.replicas" . }}
  {{- if .Values.updateStrategy }}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      {{- if and .Values.dispatch.enabled (gt (include "spicedb.replicas" . | int) 1) }}
      # When dispatch is enabled with multiple replicas, match spicedb-operator behavior:
      # maxUnavailable: 0 ensures all replicas stay available during rolling updates
      # This allows new pods to connect to existing dispatch cluster members
      maxUnavailable: 0
      maxSurge: {{ .Values.updateStrategy.rollingUpdate.maxSurge }}
      {{- else }}
      maxUnavailable: {{ .Values.updateStrategy.rollingUpdate.maxUnavailable }}
      maxSurge: {{ .Values.updateStrategy.rollingUpdate.maxSurge }}
      {{- end }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "spicedb.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      annotations:
        checksum/migration-config: {{ .Values.migrations | toJson | sha256sum }}
        {{- if .Values.monitoring.enabled }}
        prometheus.io/scrape: 'true'
        prometheus.io/port: '9090'
        prometheus.io/path: '/metrics'
        {{- end }}
        {{- if .Values.operatorCompatibility.enabled }}
        {{- if or (not (hasKey .Values.operatorCompatibility "annotations")) .Values.operatorCompatibility.annotations.version }}
        spicedb.authzed.com/version: {{ .Chart.AppVersion | quote }}
        {{- end }}
        {{- if or (not (hasKey .Values.operatorCompatibility "annotations")) .Values.operatorCompatibility.annotations.chartVersion }}
        spicedb.authzed.com/chart-version: {{ .Chart.Version | quote }}
        {{- end }}
        {{- if or (not (hasKey .Values.operatorCompatibility "annotations")) .Values.operatorCompatibility.annotations.datastoreEngine }}
        spicedb.authzed.com/datastore-engine: {{ include "spicedb.datastoreEngine" . | quote }}
        {{- end }}
        {{- if or (not (hasKey .Values.operatorCompatibility "annotations")) .Values.operatorCompatibility.annotations.migrationHash }}
        spicedb.authzed.com/migration-hash: {{ include "spicedb.migrationHash" . | quote }}
        {{- end }}
        spicedb.authzed.com/managed-by: helm-operator-compatible
        {{- end }}
        {{- with .Values.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      labels:
        {{- include "spicedb.labels" . | nindent 8 }}
        {{- with .Values.podLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "spicedb.serviceAccountName" . }}
      {{- with .Values.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if .Values.terminationGracePeriodSeconds }}
      terminationGracePeriodSeconds: {{ .Values.terminationGracePeriodSeconds }}
      {{- end }}
      containers:
      - name: spicedb
        {{- with .Values.securityContext }}
        securityContext:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        command:
        - spicedb
        - serve
        ports:
        - name: grpc
          containerPort: 50051
          protocol: TCP
        - name: http
          containerPort: 8443
          protocol: TCP
        - name: metrics
          containerPort: 9090
          protocol: TCP
        - name: dispatch
          containerPort: 50053
          protocol: TCP
        env:
        - name: SPICEDB_GRPC_PRESHARED_KEY
          value: {{ .Values.config.presharedKey | quote }}
        - name: SPICEDB_DATASTORE_ENGINE
          value: {{ include "spicedb.datastoreEngine" . }}
        - name: SPICEDB_LOG_LEVEL
          value: {{ .Values.logging.level }}
        - name: SPICEDB_LOG_FORMAT
          value: {{ .Values.logging.format }}
        {{- if ne (include "spicedb.datastoreEngine" .) "memory" }}
        - name: SPICEDB_DATASTORE_CONN_URI
          valueFrom:
            secretKeyRef:
              name: {{ include "spicedb.existingSecret" . | default (include "spicedb.fullname" .) }}
              key: datastore-uri
        {{- end }}
        {{- if include "spicedb.grpcTLSSecretName" . }}
        - name: SPICEDB_GRPC_TLS_CERT_PATH
          value: {{ .Values.tls.grpc.certPath | quote }}
        - name: SPICEDB_GRPC_TLS_KEY_PATH
          value: {{ .Values.tls.grpc.keyPath | quote }}
        - name: SPICEDB_GRPC_TLS_CA_PATH
          value: {{ .Values.tls.grpc.caPath | quote }}
        {{- end }}
        {{- if include "spicedb.httpTLSSecretName" . }}
        - name: SPICEDB_HTTP_TLS_CERT_PATH
          value: {{ .Values.tls.http.certPath | quote }}
        - name: SPICEDB_HTTP_TLS_KEY_PATH
          value: {{ .Values.tls.http.keyPath | quote }}
        {{- end }}
        {{- if include "spicedb.dispatchTLSSecretName" . }}
        - name: SPICEDB_DISPATCH_CLUSTER_TLS_CERT_PATH
          value: {{ .Values.tls.dispatch.certPath | quote }}
        - name: SPICEDB_DISPATCH_CLUSTER_TLS_KEY_PATH
          value: {{ .Values.tls.dispatch.keyPath | quote }}
        - name: SPICEDB_DISPATCH_CLUSTER_TLS_CA_PATH
          value: {{ .Values.tls.dispatch.caPath | quote }}
        {{- end }}
        {{- if .Values.dispatch.enabled }}
        - name: SPICEDB_DISPATCH_CLUSTER_ENABLED
          value: "true"
        - name: SPICEDB_DISPATCH_UPSTREAM_ADDR
          value: "kubernetes:///{{ include "spicedb.fullname" . }}.{{ .Release.Namespace }}:dispatch"
        {{- if include "spicedb.dispatchUpstreamCASecretName" . }}
        - name: SPICEDB_DISPATCH_UPSTREAM_CA_CERT_PATH
          value: /etc/dispatch-ca/ca.crt
        {{- end }}
        {{- end }}
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        {{- if include "spicedb.grpcTLSSecretName" . }}
        - name: tls-grpc-certs
          mountPath: /etc/spicedb/tls/grpc
          readOnly: true
        {{- end }}
        {{- if include "spicedb.httpTLSSecretName" . }}
        - name: tls-http-certs
          mountPath: /etc/spicedb/tls/http
          readOnly: true
        {{- end }}
        {{- if include "spicedb.dispatchTLSSecretName" . }}
        - name: tls-dispatch-certs
          mountPath: /etc/spicedb/tls/dispatch
          readOnly: true
        {{- end }}
        {{- if and .Values.tls.enabled .Values.tls.datastore.secretName }}
        - name: tls-datastore-certs
          mountPath: /etc/spicedb/tls/datastore
          readOnly: true
        {{- end }}
        {{- if and .Values.dispatch.enabled (include "spicedb.dispatchUpstreamCASecretName" .) }}
        - name: dispatch-upstream-ca
          mountPath: /etc/dispatch-ca
          readOnly: true
        {{- end }}
        {{- if .Values.probes.startup.enabled }}
        startupProbe:
          grpc:
            port: 50051
          initialDelaySeconds: {{ .Values.probes.startup.initialDelaySeconds }}
          periodSeconds: {{ .Values.probes.startup.periodSeconds }}
          timeoutSeconds: {{ .Values.probes.startup.timeoutSeconds }}
          successThreshold: {{ .Values.probes.startup.successThreshold }}
          failureThreshold: {{ .Values.probes.startup.failureThreshold }}
        {{- end }}
        {{- if .Values.probes.readiness.enabled }}
        readinessProbe:
          {{- if eq (.Values.probes.readiness.protocol | default "grpc") "http" }}
          httpGet:
            path: {{ .Values.probes.readiness.http.path }}
            port: {{ .Values.probes.readiness.http.port }}
            scheme: {{ .Values.probes.readiness.http.scheme }}
          {{- else }}
          grpc:
            port: 50051
          {{- end }}
          initialDelaySeconds: {{ .Values.probes.readiness.initialDelaySeconds }}
          periodSeconds: {{ .Values.probes.readiness.periodSeconds }}
          timeoutSeconds: {{ .Values.probes.readiness.timeoutSeconds }}
          successThreshold: {{ .Values.probes.readiness.successThreshold }}
          failureThreshold: {{ .Values.probes.readiness.failureThreshold }}
        {{- end }}
        {{- if .Values.probes.liveness.enabled }}
        livenessProbe:
          {{- if eq (.Values.probes.liveness.protocol | default "grpc") "http" }}
          httpGet:
            path: {{ .Values.probes.liveness.http.path }}
            port: {{ .Values.probes.liveness.http.port }}
            scheme: {{ .Values.probes.liveness.http.scheme }}
          {{- else }}
          grpc:
            port: 50051
          {{- end }}
          initialDelaySeconds: {{ .Values.probes.liveness.initialDelaySeconds }}
          periodSeconds: {{ .Values.probes.liveness.periodSeconds }}
          timeoutSeconds: {{ .Values.probes.liveness.timeoutSeconds }}
          successThreshold: {{ .Values.probes.liveness.successThreshold }}
          failureThreshold: {{ .Values.probes.liveness.failureThreshold }}
        {{- end }}
        {{- with .Values.resources }}
        resources:
          {{- toYaml . | nindent 10 }}
        {{- end }}
      {{- if .Values.affinity }}
      affinity:
        {{- toYaml .Values.affinity | nindent 8 }}
      {{- else if gt (int (include "spicedb.replicas" .)) 1 }}
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          # Prefer spreading pods across availability zones (highest priority)
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  {{- include "spicedb.selectorLabels" . | nindent 18 }}
              topologyKey: topology.kubernetes.io/zone
          # Prefer spreading pods across nodes (lower priority)
          - weight: 50
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  {{- include "spicedb.selectorLabels" . | nindent 18 }}
              topologyKey: kubernetes.io/hostname
      {{- end }}
      {{- if gt (int (include "spicedb.replicas" .)) 1 }}
      topologySpreadConstraints:
      # Spread pods evenly across availability zones
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            {{- include "spicedb.selectorLabels" . | nindent 12 }}
      # Spread pods evenly across nodes within zones
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            {{- include "spicedb.selectorLabels" . | nindent 12 }}
      {{- end }}
      volumes:
      - name: tmp
        emptyDir: {}
      {{- if include "spicedb.grpcTLSSecretName" . }}
      - name: tls-grpc-certs
        secret:
          secretName: {{ include "spicedb.grpcTLSSecretName" . }}
          defaultMode: 0400
      {{- end }}
      {{- if include "spicedb.httpTLSSecretName" . }}
      - name: tls-http-certs
        secret:
          secretName: {{ include "spicedb.httpTLSSecretName" . }}
          defaultMode: 0400
      {{- end }}
      {{- if include "spicedb.dispatchTLSSecretName" . }}
      - name: tls-dispatch-certs
        secret:
          secretName: {{ include "spicedb.dispatchTLSSecretName" . }}
          defaultMode: 0400
      {{- end }}
      {{- if and .Values.tls.enabled .Values.tls.datastore.secretName }}
      - name: tls-datastore-certs
        secret:
          secretName: {{ .Values.tls.datastore.secretName }}
          defaultMode: 0400
      {{- end }}
      {{- if and .Values.dispatch.enabled (include "spicedb.dispatchUpstreamCASecretName" .) }}
      - name: dispatch-upstream-ca
        secret:
          secretName: {{ include "spicedb.dispatchUpstreamCASecretName" . }}
          defaultMode: 0400
      {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end }}

{{/*
Base service template without patches applied
This generates the complete Service resource structure based on values
Used by the patch system to create a base that can be patched
*/}}
{{- define "spicedb.service.base" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "spicedb.fullname" . }}
  labels:
    {{- include "spicedb.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  {{- if .Values.service.headless }}
  clusterIP: None
  {{- end }}
  ports:
    - port: {{ .Values.service.grpcPort }}
      targetPort: grpc
      protocol: TCP
      name: grpc
    - port: {{ .Values.service.httpPort }}
      targetPort: http
      protocol: TCP
      name: http
    - port: {{ .Values.service.metricsPort }}
      targetPort: metrics
      protocol: TCP
      name: metrics
    - port: {{ .Values.service.dispatchPort }}
      targetPort: dispatch
      protocol: TCP
      name: dispatch
  selector:
    {{- include "spicedb.selectorLabels" . | nindent 4 }}
{{- end }}

{{/*
Base ingress template without patches applied
This generates the complete Ingress resource structure based on values
Used by the patch system to create a base that can be patched
*/}}
{{- define "spicedb.ingress.base" -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "spicedb.fullname" . }}
  labels:
    {{- include "spicedb.labels" . | nindent 4 }}
  {{- with .Values.ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- if .Values.ingress.className }}
  ingressClassName: {{ .Values.ingress.className }}
  {{- end }}
  {{- if .Values.ingress.tls }}
  tls:
    {{- range .Values.ingress.tls }}
    - hosts:
        {{- range .hosts }}
        - {{ . | quote }}
        {{- end }}
      {{- if .secretName }}
      secretName: {{ .secretName }}
      {{- end }}
    {{- end }}
  {{- end }}
  rules:
    {{- range .Values.ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            {{- if .pathType }}
            pathType: {{ .pathType }}
            {{- else }}
            pathType: Prefix
            {{- end }}
            backend:
              service:
                name: {{ include "spicedb.fullname" $ }}
                port:
                  {{- if .servicePort }}
                  {{- if kindIs "string" .servicePort }}
                  name: {{ .servicePort }}
                  {{- else }}
                  number: {{ .servicePort }}
                  {{- end }}
                  {{- else }}
                  name: grpc
                  {{- end }}
          {{- end }}
    {{- end }}
{{- end }}
