{{/*
ksvc.utils.toStringMap — Copy a map with every value coerced to a string and
return it as YAML.

CloudNativePG declares `parameters` fields as `map[string]string`, so a
consumer-supplied integer or boolean (e.g. `max_connections: 300`) renders as a
YAML scalar and is rejected by the API server. Coercing at render time keeps
the rendered manifest valid regardless of the consumer's scalar type. String
values pass through unchanged, so existing rendered output does not change.
*/}}
{{- define "ksvc.utils.toStringMap" -}}
{{- $out := dict -}}
{{- range $k, $v := . -}}
{{- $_ := set $out $k (toString $v) -}}
{{- end -}}
{{- toYaml $out -}}
{{- end }}
