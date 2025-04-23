{{- define "dashboard-frontend.name" -}}
dashboard-frontend
{{- end }}

{{- define "dashboard-frontend.fullname" -}}
{{ .Release.Name }}
{{- end }}
