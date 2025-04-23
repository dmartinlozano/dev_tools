{{- define "dashboard.name" -}}
dashboard
{{- end -}}

{{- define "dashboard.fullname" -}}
{{ .Release.Name }}
{{- end -}}
