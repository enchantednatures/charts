{{/*
ksvc.class.objectBucketClaim — Render an ObjectBucketClaim for one objectBuckets entry.
Expects context: dict with "root" (top-level context), "key" (bucket map key),
and "bucket" (the merged bucket entry config dict).
The referenced StorageClass provisions the bucket on the object store (Rook/Ceph);
storageClassName is required and only referenced, never rendered.
*/}}
{{- define "ksvc.class.objectBucketClaim" -}}
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: {{ include "ksvc.objectBucketName" (dict "root" .root "key" .key) | quote }}
  namespace: {{ .root.Release.Namespace }}
  labels:
    {{- include "ksvc.labels" .root | nindent 4 }}
    app.kubernetes.io/component: {{ "object-bucket" | quote }}
spec:
  storageClassName: {{ .bucket.storageClassName | quote }}
  bucketName: {{ .bucket.bucketName | quote }}
{{- end }}
