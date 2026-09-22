vault {
  address = "http://127.0.0.1:8200"
}

auto_auth {
  method {
    type = "token_file"

    config = {
      token_file_path = "/root/.openbao-token"
    }
  }
}

template {
  destination = "/run/openbao/secrets/opentelemetry-collector.env"
  perms       = "0640"
  contents    = <<-EOT
    # Rendered by OpenBao Agent.
    {{ with secret "secret/data/example" -}}
    SAMPLE_HEADER_VALUE=Basic {{ printf "%s:%s" .Data.data.username .Data.data.token | base64Encode }}
    SAMPLE_PRECEDENCE_VALUE={{ .Data.data.precedence }}
    SAMPLE_LITERAL_VALUE={{ .Data.data.literal }}
    SAMPLE_EMPTY_VALUE={{ .Data.data.empty }}
    {{- end }}
  EOT
}

template {
  destination = "/run/openbao/secrets/dagu.env"
  perms       = "0640"
  contents    = <<-EOT
    {{ with secret "secret/data/example" -}}
    SAMPLE_DAGU_VALUE={{ .Data.data.precedence }}
    {{- end }}
  EOT
}

# A mention that is not a destination assignment does not declare a file.
# destination = "/run/openbao/secrets/commented-feature.env"
// destination = "/run/openbao/secrets/slashed-feature.env"
/*
template {
  destination = "/run/openbao/secrets/blocked-feature.env"
}
*/
template {
  destination = "/root/.openbao-notes"
  contents    = "see /run/openbao/secrets/mentioned-feature.env and an unclosed /* in a string"
}

template {
  destination = "/run/openbao/secrets/string-feature.env"
  contents    = "a */ in a string does not end a comment, and # is not one either {{ with secret \"secret/data/example\" }}{{ .Data.data.precedence }}{{ end }}"
}

template {
  destination = "/root/.openbao-heredoc"
  contents    = <<-EOT
    destination = "/run/openbao/secrets/heredoc-feature.env"
  EOT
}

template {
  destination = "/run/openbao/secrets/backup-feature.env.backup"
  contents    = "a longer path that contains the conventional one"
}
