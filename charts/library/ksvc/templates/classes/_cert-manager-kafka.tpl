{{/*
ksvc.class.certManagerKafka — Render the cert-manager chain used by the
chart-managed Kafka cluster when cluster.tls.enabled and
cluster.tls.certManager.enabled are true.

The chart creates a self-signed Issuer, a CA Certificate, and a CA Issuer. Both
the Strimzi and Redpanda providers consume the CA Issuer for end-entity
certificates, and clients trust the CA Secret exposed by
ksvc.kafkaCASecretName.
*/}}
{{- define "ksvc.class.certManagerKafka" -}}
{{- $cluster := .Values.kafka.cluster -}}
{{- $tls := $cluster.tls -}}
{{- $cm := $tls.certManager | default dict -}}
{{- $name := include "ksvc.fullname" . -}}
{{- $selfSignedName := include "ksvc.kafkaTLSIssuerName" . -}}
{{- $caSecretName := include "ksvc.kafkaCASecretName" . -}}
{{- $caIssuerName := include "ksvc.kafkaCAIssuerName" . -}}
{{- $issuerName := $cm.issuerRef.name | default "" -}}
{{- $issuerKind := $cm.issuerRef.kind | default "ClusterIssuer" -}}
{{- $issuerGroup := $cm.issuerRef.group | default "cert-manager.io" -}}
{{- if not $issuerName -}}
{{- $issuerName = $selfSignedName -}}
{{- $issuerKind = "Issuer" -}}
{{- $issuerGroup = "cert-manager.io" -}}
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: {{ $selfSignedName }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: kafka-tls
spec:
  selfSigned: {}
{{- end }}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ printf "%s-kafka-ca" $name | trunc 63 | trimSuffix "-" }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: kafka-tls
spec:
  secretName: {{ $caSecretName }}
  isCA: true
  commonName: {{ printf "%s-kafka-ca" $name | quote }}
  usages:
    - cert sign
    - crl sign
  privateKey:
    algorithm: ECDSA
    encoding: PKCS8
    size: 256
  issuerRef:
    name: {{ $issuerName }}
    kind: {{ $issuerKind }}
    group: {{ $issuerGroup }}
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: {{ $caIssuerName }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: kafka-tls
spec:
  ca:
    secretName: {{ $caSecretName }}
{{- if $cm.clientAuth }}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ printf "%s-kafka-client" $name | trunc 63 | trimSuffix "-" }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "ksvc.labels" . | nindent 4 }}
    app.kubernetes.io/component: kafka-tls
spec:
  secretName: {{ include "ksvc.kafkaClientTLSSecretName" . }}
  commonName: {{ printf "%s-kafka-client" $name | quote }}
  usages:
    - client auth
  privateKey:
    algorithm: ECDSA
    encoding: PKCS8
    size: 256
  issuerRef:
    name: {{ $caIssuerName }}
    kind: Issuer
    group: cert-manager.io
{{- end }}
{{- end }}
