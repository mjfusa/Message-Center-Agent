# Azure Container Apps deployment (Step 3)

This folder provisions:
- Log Analytics workspace + workspace-based Application Insights (optional, enabled by default)
- Container Apps Managed Environment
- Two Container Apps (external ingress):
  - Message Center MCP server (port 8080)
  - Roadmap MCP server (port 8081)

It also outputs both app FQDNs.

## Prereqs

- Azure CLI logged in: `az login`
- A resource group created (example):
  - `az group create -n <rg> -l <location>`

## Build + publish container images

You can host images in any registry accessible by Azure Container Apps (ACR, Docker Hub, GHCR).

At minimum you need two image references:
- `messageCenterImage`
- `roadmapImage`

### ACR helper script

This repo includes a helper script that creates/uses an Azure Container Registry (ACR) and runs `az acr build` for both servers.

```powershell
./infra/BuildAndPushImagesToAcr.ps1 -AcrName <globallyUniqueAcrName> -ResourceGroupName rg-mcp-messages-roadmap -Location westus -UpdateParameters
```

After it runs, your `infra/main.parameters.json` will have `messageCenterImage` and `roadmapImage` populated.

## Deploy

1) Copy/modify [infra/main.parameters.json](main.parameters.json):
- `namePrefix`
- `messageCenterImage`, `roadmapImage`
- `graphTenantId`, `graphClientId`, `graphClientSecret`

2) Deploy the Bicep:

```bash
az deployment group create \
  -g <rg> \
  -f infra/main.bicep \
  -p infra/main.parameters.json
```

3) Get outputs (FQDNs):

```bash
az deployment group show -g <rg> -n <deploymentName> --query properties.outputs -o json
```

## Verify

- Health endpoints:
  - `https://<messageCenterFqdn>/healthz`
  - `https://<roadmapFqdn>/healthz`
- MCP endpoints:
  - `https://<messageCenterFqdn>/mcp`
  - `https://<roadmapFqdn>/mcp`

## Notes

- Scale-to-zero is controlled by `minReplicas` (default `0`) and HTTP scaling rules.
- `PUBLIC_BASE_URL` is computed from the deployed Container Apps environment default domain unless you override it via the `publicBaseUrl` parameter.
- `APPLICATIONINSIGHTS_CONNECTION_STRING` is injected into both apps (you still need to add app-level telemetry SDKs if you want custom traces/metrics).

### ACR auth migration (admin creds -> managed identity)

This repo supports two ways for Azure Container Apps to pull private images from ACR:

- **Bootstrap mode** (ACR admin credentials): easiest to get running, but relies on ACR admin user.
- **Hardened mode** (system-assigned managed identity + `AcrPull`): preferred for production.

Because a container app must be able to pull its image *during provisioning*, switching directly to managed identity can fail on the first attempt (role assignment/identity propagation). The reliable approach is a **two-phase deployment**:

1) **Bootstrap deploy** (keeps ACR creds, creates identities + role assignments)

```bash
az deployment group create \
  -g <rg> \
  -f infra/main.bicep \
  -p infra/main.parameters.json \
  -p acrUseManagedIdentity=false
```

2) Wait briefly for RBAC to propagate (often 2-10 minutes), then **flip to managed identity pulls**

```bash
az deployment group create \
  -g <rg> \
  -f infra/main.bicep \
  -p infra/main.parameters.json \
  -p acrUseManagedIdentity=true
```

3) After you confirm both apps are healthy and can start new revisions, **disable the ACR admin user**

```bash
az acr update -g <rg> -n <acrName> --admin-enabled false
```

Verification checklist:

- `https://<messageCenterFqdn>/healthz` returns `200`.
- `https://<roadmapFqdn>/healthz` returns `200`.
- If step (2) fails with an image-pull error, retry after a few minutes (it's usually propagation delay).
