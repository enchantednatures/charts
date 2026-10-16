{{- define "ksvc.class.cnpgNetworkPolicy" -}}
{{- $pgName := include "ksvc.postgresName" . -}}
{{- $np := .Values.postgres.networkPolicy -}}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: "{{ $pgName }}-network-policy"
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: {{ "database" | quote }}
  {{- $globalAnnotations := include "ksvc.annotations" . -}}
  {{- if $globalAnnotations }}
  annotations:
    {{- $globalAnnotations | nindent 4 }}
  {{- end }}
spec:
  podSelector:
    matchLabels:
      cnpg.io/cluster: {{ $pgName | quote }}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 5432
    {{- with $np.extraIngress }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- end }}
