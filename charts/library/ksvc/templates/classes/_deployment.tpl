{{/*
ksvc.class.deployment — Render an apps/v1 Deployment for a service entry.
Used when services.<key>.workload.type is Deployment.
Expects context: dict with "root" (top-level context), "key" (service map key),
and "svc" (the merged service config dict).
*/}}
{{- define "ksvc.class.deployment" -}}
{{- $serviceName := include "ksvc.serviceName" (dict "root" .root "key" .key "svc" .svc) -}}
{{- $svc := .svc -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $serviceName }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "ksvc.serviceLabels" (dict "root" .root "key" .key "svc" $svc) | nindent 4 }}
  {{- $globalAnnotations := include "ksvc.annotations" .root -}}
  {{- if or $globalAnnotations $svc.annotations }}
  annotations:
    {{- with $globalAnnotations }}
    {{- . | nindent 4 }}
    {{- end }}
    {{- with $svc.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- end }}
spec:
  replicas: {{ $svc.workload.replicas }}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: {{ $svc.workload.strategy.maxUnavailable }}
      maxSurge: {{ $svc.workload.strategy.maxSurge }}
  selector:
    matchLabels:
      {{- include "ksvc.serviceSelectorLabels" (dict "root" .root "key" .key "svc" $svc) | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "ksvc.serviceLabels" (dict "root" .root "key" .key "svc" $svc) | nindent 8 }}
      {{- with $svc.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    spec:
      {{- with $svc.image.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      terminationGracePeriodSeconds: {{ $svc.workload.terminationGracePeriodSeconds }}
      containers:
        - name: service
          {{- if $svc.image.fluxImagePolicy }}
          image: {{ $svc.image.repository }}:{{ $svc.image.tag }} # {{ printf "{\"$imagepolicy\": \"%s\"}" $svc.image.fluxImagePolicy }}
          {{- else }}
          image: {{ $svc.image.repository }}:{{ $svc.image.tag }}
          {{- end }}
          {{- if $svc.image.pullPolicy }}
          imagePullPolicy: {{ $svc.image.pullPolicy }}
          {{- end }}
          ports:
            - containerPort: {{ $svc.port }}
              protocol: TCP
          {{- with $svc.env }}
          env:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with $svc.envFrom }}
          envFrom:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          resources:
            {{- toYaml $svc.resources | nindent 12 }}
          livenessProbe:
            httpGet:
              path: {{ $svc.probes.liveness.path }}
              port: {{ $svc.probes.liveness.port }}
            initialDelaySeconds: {{ $svc.probes.liveness.initialDelaySeconds }}
            periodSeconds: {{ $svc.probes.liveness.periodSeconds }}
            timeoutSeconds: {{ $svc.probes.liveness.timeoutSeconds }}
            failureThreshold: {{ $svc.probes.liveness.failureThreshold }}
          readinessProbe:
            httpGet:
              path: {{ $svc.probes.readiness.path }}
              port: {{ $svc.probes.readiness.port }}
            initialDelaySeconds: {{ $svc.probes.readiness.initialDelaySeconds }}
            periodSeconds: {{ $svc.probes.readiness.periodSeconds }}
            timeoutSeconds: {{ $svc.probes.readiness.timeoutSeconds }}
            failureThreshold: {{ $svc.probes.readiness.failureThreshold }}
          securityContext:
            {{- toYaml $svc.securityContext | nindent 12 }}
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            {{- with $svc.volumeMounts }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
          {{- if gt (int $svc.workload.preStopSleepSeconds) 0 }}
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep {{ int $svc.workload.preStopSleepSeconds }}"]
          {{- end }}
      volumes:
        - name: tmp
          emptyDir: {}
        {{- with $svc.volumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
{{- end }}
