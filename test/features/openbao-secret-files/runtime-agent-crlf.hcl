template {
  destination = "/root/.openbao-crlf"
  contents    = <<-EOT
    destination = "/run/openbao/secrets/crlf-heredoc-feature.env"
  EOT
}

template {
  destination = "/run/openbao/secrets/crlf-feature.env"
  contents    = "{{ with secret \"secret/data/example\" }}{{ .Data.data.precedence }}{{ end }}"
}
