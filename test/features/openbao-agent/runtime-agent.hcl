vault {
  address = "http://127.0.0.1:8200"
}

auto_auth {
  method {
    type = "token_file"

    config = {
      token_file_path = "/home/vscode/.openbao-token"
    }
  }

  sink "file" {
    config = {
      path = "/home/vscode/.openbao-agent-token"
    }
  }
}

template {
  contents = "{{ with secret \"secret/data/example\" }}{{ .Data.data.value }}{{ end }}"
  destination = "/home/vscode/.openbao-rendered-secret"
}
