{{- define "ksvc.class.knativeService" -}}
{{- $fullname := include "ksvc.fullname" . -}}
{{- $svc := .Values.knativeService -}}
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: {{ $fullname }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: api
    {{- with $svc.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- $globalAnnotations := include "ksvc.annotations" . -}}
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
        {{- if $svc.scaling.class }}
        autoscaling.knative.dev/class: {{ $svc.scaling.class | quote }}
        {{- end }}
        {{- with $svc.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      containerConcurrency: {{ $svc.scaling.containerConcurrency }}
      timeoutSeconds: {{ $svc.scaling.timeoutSeconds }}
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
      volumes:
        - name: tmp
          emptyDir: {}
        {{- with $svc.volumes }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
{{- end }}
