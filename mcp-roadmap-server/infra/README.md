# Roadmap MCP Server (infra)

This folder is a **standalone** Azure Container Apps deployment for the Roadmap MCP server.

## Deploy

- Build/push your image to ACR (or use an existing image reference)
- Update `infra/main.parameters.json` with your image reference and settings
- Deploy:

```pwsh
az deployment group create \
  -g <resourceGroup> \
  -f infra/main.bicep \
  -p infra/main.parameters.json
```

## Notes

- This deployment expects the ACR in your image reference to already exist (it uses it as an `existing` resource).
- No secrets are committed.
