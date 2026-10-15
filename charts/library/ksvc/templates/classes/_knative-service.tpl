{{/*
ksvc.class.knativeService — Render a Knative Service.
Expects context: dict with "root" (top-level context), "key" (service map key),
and "svc" (the merged service config dict).
*/}}
{{- define "ksvc.class.knativeService" -}}
{{- $serviceName := include "ksvc.serviceName" (dict "root" .root "key" .key "svc" .svc) -}}
{{- $svc := .svc -}}
{{- /* Image reference: a digest pins the exact image (immutable, reproducible);
       otherwise fall back to the mutable tag. */ -}}
{{- $imageRef := printf "%s:%s" $svc.image.repository $svc.image.tag -}}
{{- if $svc.image.digest -}}
{{- $imageRef = printf "%s@%s" $svc.image.repository $svc.image.digest -}}
{{- end -}}
{{- /* `latest` is mutable, so a node may otherwise serve a stale cached image
       forever under IfNotPresent; force Always whenever the resolved reference
       is a `latest` tag (a digest is immutable and needs no forcing). */ -}}
{{- $pullPolicy := $svc.image.pullPolicy -}}
{{- if and (not $svc.image.digest) (eq $svc.image.tag "latest") -}}
{{- $pullPolicy = "Always" -}}
{{- end -}}
apiVersion: serving.knative.dev/v1
kind: Service
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
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/min-scale: {{ $svc.scaling.minScale | quote }}
        autoscaling.knative.dev/max-scale: {{ $svc.scaling.maxScale | quote }}
        autoscaling.knative.dev/target: {{ $svc.scaling.target | quote }}
        {{- if $svc.scaling.metric }}
        autoscaling.knative.dev/metric: {{ $svc.scaling.metric | quote }}
        {{- end }}
        {{- if $svc.scaling.class }}
        autoscaling.knative.dev/class: {{ $svc.scaling.class | quote }}
        {{- end }}
        {{- with $svc.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      {{- with $svc.image.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containerConcurrency: {{ $svc.scaling.containerConcurrency }}
      timeoutSeconds: {{ $svc.scaling.timeoutSeconds }}
      containers:
        - name: service
          {{- if $svc.image.fluxImagePolicy }}
          image: {{ $imageRef }} # {{ printf "{\"$imagepolicy\": \"%s\"}" $svc.image.fluxImagePolicy }}
          {{- else }}
          image: {{ $imageRef }}
          {{- end }}
          {{- if $pullPolicy }}
          imagePullPolicy: {{ $pullPolicy }}
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
      volumes:
        - name: tmp
          emptyDir: {}
        {{- with $svc.volumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
{{- end }}
