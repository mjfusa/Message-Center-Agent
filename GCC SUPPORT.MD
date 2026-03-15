# Message Center Agent Deployment Guide for Microsoft 365 GCC

## Purpose

This document explains how to deploy this project to a Microsoft 365 Government Community Cloud Moderate (GCC) environment using the latest Microsoft 365 Agents Toolkit (ATK) support for sovereign clouds.

This guide is specific to this repository:

- Repo: `mjfusa/Message-Center-Agent`
- Agent type: Microsoft 365 Copilot declarative agent
- Toolkit config: `m365agents.yml`
- Environment file location: `env/.env.production`

## Key Point

You do **not** need to recreate the agent project from scratch to deploy it to GCC.

You **do** need to create a new GCC-scoped deployment boundary:

- a new app registration in the GCC tenant
- a new ATK provisioning run against the GCC tenant
- a new GCC deployment environment and manifest binding
- new secrets and environment values tied to GCC

Your existing code, prompts, OpenAPI files, manifest structure, and declarative agent definition can stay the same.

## What Changed

The latest Microsoft 365 Agents Toolkit releases now include support for government cloud environments, including GCC.

Microsoft states that ATK is expanding support for:

- GCC
- GCC High
- DoD
- Teams operated by 21Vianet

For the latest details, review the toolkit changelog:

- Changelog: https://marketplace.visualstudio.com/items/TeamsDevApp.ms-teams-vscode-extension/changelog

At the time this guidance was provided, rerunning the repo install script installs the latest supported ATK CLI, expected to be version `1.1.5`.

## GCC Migration Model

### What must be recreated

- App registration in the GCC tenant
- Client secret for the GCC app registration
- ATK provisioning in the GCC tenant
- GCC-specific environment values written during provision/publish
- Any secrets or variables that still point to commercial cloud resources

### What does not need to be recreated

- This repository
- The declarative agent definition
- The OpenAPI plugin definition
- Prompts, instructions, and logic
- Your MCP server, if you use one separately

## Why a New GCC Deployment Is Required

GCC is a separate sovereign cloud boundary. That means commercial and GCC environments do not share the same identity, endpoint, and compliance boundary.

In practice, that means the following commercial resources cannot simply be reused in GCC:

- Entra app registration
- Teams/Developer Portal app bindings
- Toolkit environment state
- OAuth registration created during provisioning

The correct approach is to point the same codebase at a new GCC tenant and provision it again there.

## Prerequisites

Before you begin, confirm the following:

1. You have access to a **GCC tenant**, not a commercial tenant.
2. You have a user account in that GCC tenant with the permissions required to:
   - create app registrations
   - provision/publish Teams or Copilot apps
3. Custom app upload is enabled in the GCC tenant if you intend to sideload for testing.
4. The app registration you will use is created in the **same GCC tenant** where the agent will be deployed.
5. Node.js LTS is installed, version `20` or later.

### Recommended roles

For app registration:

- Application Administrator
- Cloud Application Administrator
- Global Administrator

For Teams/Copilot app provisioning and publishing:

- Teams Administrator
- Global Administrator

For agent usage after deployment, users need a role that can read Message Center data, typically:

- Message Center Reader
- Global Reader
- Service Support Administrator
- Service Administrator
- Global Administrator

## Start from Scratch: Recommended GCC Deployment Path

If this repo was previously used in a commercial tenant, use a clean refresh path before provisioning to GCC.

### 1. Get a fresh copy of the repository

Clone a fresh copy of the latest project from the repository:

- `mjfusa/Message-Center-Agent`

If you are already working in an older local clone, replacing it with a fresh clone is the cleanest option because it avoids carrying forward stale environment values and old generated artifacts.

### 2. Reinstall or update Node.js and the ATK CLI

From the repository, open PowerShell and run:

```powershell
cd prereqs
.\InstallNodeAtk.ps1
```

What this script does in this repo:

- checks for Node.js
- installs or updates Node.js if needed
- installs or updates the global `atk` CLI with `npm install -g @microsoft/m365agentstoolkit-cli`

After the script finishes, verify the installed version:

```powershell
atk --version
```

Expected result for this guidance: `1.1.5` or greater.

If you get a later version, that is usually fine as long as it includes GCC support and does not introduce a breaking change for this project.

### 3. Install or update the Microsoft 365 Agents Toolkit VS Code extension

If you are using Visual Studio Code for provisioning instead of CLI-only flow, make sure the Microsoft 365 Agents Toolkit extension is updated to the latest release that includes sovereign cloud support.

Marketplace page:

- https://marketplace.visualstudio.com/items?itemName=TeamsDevApp.ms-teams-vscode-extension

## Required VS Code Setting for GCC

After updating the toolkit, update your Visual Studio Code user settings file:

- `C:\Users\<YOUR USER NAME>\AppData\Roaming\Code\User\settings.json`

Add this setting:

```json
"M365AgentsToolkit.sovereignCloudEnvironment": "GCC M",
```

Example in context:

```json
{
	"workbench.colorTheme": "Default Light Modern",
	"git.autofetch": true,
	"[xml]": {
		"editor.defaultFormatter": "DotJoshJohnson.xml"
	},
	"M365AgentsToolkit.sovereignCloudEnvironment": "GCC M",
	"M365AgentsToolkit.enableCustomFunctionShortcutInOfficeAddIn": false
}
```

Save the file and restart Visual Studio Code.

## Create the GCC App Registration

This project uses a separate Entra app registration for OAuth.

From the repo:

```powershell
cd prereqs
.\CreateAppReg.ps1
```

What the script does in this repo:

- creates an app registration named `MessageCenterAgent-reg`
- creates a service principal
- configures the Microsoft Teams OAuth redirect URI
- requests the Microsoft Graph delegated permission `ServiceMessage.Read.All`
- creates a client secret

The script outputs:

- `clientId`
- `tenantId`
- `clientSecret`

Important GCC requirement:

- Run this while signed in to the **GCC tenant**.
- Do not reuse a client ID or secret from a commercial tenant.
- The Azure CLI tenant and Entra tenant must match when the script runs.

If you already created a GCC-scoped app registration earlier, you can reuse that **GCC** client ID and secret instead of creating another one.

## Prepare the Environment File

This repo expects a production environment file under `env`.

Create the working file by copying:

- from: `env/.env.production.sample`
- to: `env/.env.production`

The sample currently contains:

- `AGENT_VERSION=2.0.3`
- `AGENT_SCOPE=personal`

Do not store commercial tenant secrets in the GCC environment file.

## Provision the Agent in GCC

This project’s `m365agents.yml` provisions the app by:

1. creating the Teams app
2. registering OAuth using `appPackage/apiSpecificationFile/openapi.json`
3. building the app package
4. validating the package
5. updating the Developer Portal app definition
6. extending the app to Microsoft 365

From the root of the repository, run:

```powershell
atk provision --env production
```

During provisioning, enter the **GCC** values when prompted:

- Client ID from the GCC app registration
- Client secret from the GCC app registration

When prompted that the toolkit will upload the OAuth client ID and secret for the registration, confirm the prompt.

Provisioning writes environment-specific values into `env/.env.production`, including values such as:

- `TEAMS_APP_ID`
- `OAUTH2_REGISTRATION_ID`
- `M365_TITLE_ID`
- `M365_APP_ID`

## Test the Agent in GCC

After a successful provision:

1. Open Microsoft 365 Copilot or the supported GCC client experience available in your tenant.
2. Locate **Message Center Agent**.
3. Test with a simple prompt such as:

```text
Show me recent message center posts about Microsoft 365 Copilot.
```

If the agent loads but returns authorization or data access errors, verify that the signed-in test user has the **Message Center Reader** role or a higher role that can read Message Center content.

## Publish to the GCC Organization

If you want to distribute the agent beyond private testing, run:

```powershell
atk publish --env production
```

This builds and validates the package again, updates the app definition, and submits the package for organizational publication.

Approval and distribution still depend on your Teams or Microsoft 365 app governance process in the GCC tenant.

## Existing Commercial Deployment: Do You Need to Recreate the Agent?

Short answer: **No**.

You do not need to rebuild the agent project itself.

You do need to establish a new GCC deployment boundary:

- new GCC tenant context
- new GCC app registration
- new GCC client secret
- new GCC provision/publish run
- new GCC environment values

That is the correct and supportable migration model for sovereign cloud deployment.

## Recommended Migration Workflow

Use this sequence when taking an existing commercial deployment of this repo into GCC:

1. Get a fresh clone of the repository.
2. Run `prereqs\InstallNodeAtk.ps1` to update Node.js and ATK.
3. Update VS Code settings with `"M365AgentsToolkit.sovereignCloudEnvironment": "GCC M"`.
4. Sign in to the GCC tenant.
5. Create a new GCC app registration, or reuse an existing GCC registration created for this project.
6. Copy `env/.env.production.sample` to `env/.env.production`.
7. Run `atk provision --env production`.
8. Test the agent in the GCC tenant.
9. Run `atk publish --env production` when ready for broader distribution.

## Troubleshooting

### Provisioning still appears to target commercial cloud

- Confirm VS Code was restarted after updating `settings.json`.
- Confirm the toolkit extension is current.
- Confirm you are signed into the correct GCC tenant account.

### App registration works, but provisioning fails

- Confirm the app registration was created in the same GCC tenant used for provisioning.
- Confirm the client ID and secret entered during `atk provision` are the GCC values.
- Confirm the account used for provisioning has the required Teams or admin permissions.

### Users cannot retrieve Message Center data

- Assign the **Message Center Reader** role or higher.
- Use the scripts in `prereqs` if needed, especially `AssignMessageCenterReaderRole.ps1`.

### Old local environment values interfere with GCC deployment

- Delete or replace stale local environment files.
- Start from a fresh clone if there is any doubt about residual commercial settings.

## Repo-Specific Notes

- The main deployment workflow for this project is defined in `m365agents.yml`.
- The OAuth registration uses `appPackage/apiSpecificationFile/openapi.json`.
- The production environment file for this repo is `env/.env.production`.
- The installer script in this repo is `prereqs/InstallNodeAtk.ps1`.
- The app registration helper script in this repo is `prereqs/CreateAppReg.ps1`.

## Conclusion

Deploying this project to GCC does **not** require rebuilding the agent. It requires updating the toolkit, switching the toolkit to GCC mode, creating or reusing a **GCC-scoped** app registration, and provisioning the project again in the GCC tenant.

If you follow the clean deployment path in this document, the current Message Center Agent project can be deployed to GCC using the same codebase and a new sovereign-cloud deployment boundary.
