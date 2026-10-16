{{- define "ksvc.class.dragonflyNetworkPolicy" -}}
{{- $dfName := include "ksvc.dragonflyName" . -}}
{{- $np := .Values.dragonfly.networkPolicy -}}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: "{{ $dfName }}-network-policy"
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: {{ "cache" | quote }}
  {{- $globalAnnotations := include "ksvc.annotations" . -}}
  {{- if $globalAnnotations }}
  annotations:
    {{- $globalAnnotations | nindent 4 }}
  {{- end }}
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: dragonfly
      app.kubernetes.io/part-of: dragonfly
      app: {{ $dfName | quote }}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 6379
    {{- with $np.extraIngress }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- end }}
