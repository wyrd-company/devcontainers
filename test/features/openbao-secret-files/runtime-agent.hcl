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
    {{- end }}
  EOT
}

# template { destination = "/run/openbao/secrets/dagu.env" }
