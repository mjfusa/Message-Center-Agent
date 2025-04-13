Draft a README file for this project including the following sections:  Overview, Purpose, Prerequistives: TTK, App Registration, Teams Developer Portal resistration for oauth2.0, requried roles, Architecure, How to run, conculsion

# Admin Center Message Agent - Declarative Agent 

## Overview
 The Admin Center Message Agent allows you to search Microsoft 365 Admin Center messages with Copilot chat using natural language prompts.

## Admin Center Message Agent Use Cases
Not only can you search for messages, but you can also use the power of AI to summarize them and draft internal communications. Here are some examples of what you can do with the Admin Center Message Agent:
- **Search for messages**: Find specific messages in the Microsoft 365 Admin Center message center.
- **Summarize messages**: Get a summary of the latest messages in the message center.
- **Draft internal communications**: Generate draft emails or messages to share information about updates with your team.
- **Get insights**: Gain insights regarding impact of updates for your organization.
- **Get alternatives** Get suggested alternatives for deprecated features.
- **Get suggested actions**: Get suggested actions for updates that require your attention.

## Starter Prompts
Here are some starter prompts to get you started with the Admin Center Message Agent:
```C#
Find all message center updates related to Microsoft 365 Copilot created in the last 30 days.

Show me all messages with 'security update' in the title. 

Find all messages with 'Copilot' in the title that were created after March 1, 2025 that are Major Change messages.

Find all messages regarding Microsoft Teams that are 'stay informed' messages published in the last two weeks.

Draft an email about Microsoft Teams updates that are 'Plan for Change' messages published in the last two weeks.
```


## Architecture
### Zero Code
The declarative agent is built using the Microsoft Teams Toolkit for Visual Studio Code. It leverages the Microsoft Graph API to interact with the Microsoft 365 Admin Center and retrieve messages. Authentication is handled using OAuth2.0, and the agent is designed to work seamlessly with Microsoft 365 Copilot. 

## Authentication and Graph API Permissions

The implementation of the authentication leverages the M365 Teams app authentication infrastructure that takes care of the OAuth2.0 flow and token management for you. See here:
[Configure authentication for API plugins in agents](https://learn.microsoft.com/en-us/microsoft-365-copilot/extensibility/api-plugin-authentication)

### App Registration

+++++++++++++++++++++++++++++++
1. Create a new app registration in the Azure portal.
2. Update openapi.json with securitySchemes.

```json
"components": {
    "securitySchemes": {
      "OAuth2": {
        "type": "oauth2",
        "flows": {
          "authorizationCode": {
            "authorizationUrl": "",
            "tokenUrl": "",
            "scopes": {
              "https://graph.microsoft.com": "Access Microsoft Graph API"
            }
          }
        }
      }
    }
}
```
   

1.  Update authorizationUrl and tokenUrl with the authorization and token endpoints from the app registration. Update the scopes with https://graph.microsoft.com/.

2. Provision the app using the Teams Toolkit. Note that the Teams Toolkit will register the app in the Teams Developer Portal and update the OAUTH2_REGISTRATION_ID variable in your .env file with the value received from the Teams Developer Portal.
3. Navigate to the Teams Developer Portal, click on  Tools | 'OAuth Client Registration' to view the OAuth2.0 client registration.
++++++++++++++++++++++++++++++++




To use the declarative agent, you need to register your app in the Azure portal and configure the necessary permissions. This app registration will be registered on the Teams Developer Portal. The app registration is required to authenticate users and authorize access to the Microsoft Graph API and Microsoft 365 Admin Center. The Teams developer portal provides a secure environment for managing your app's authentication settings and permissions.

Here are the steps to register your app:
1. Go to the [Microsoft Entra portal](https://entra.microsoft.com/) and sign in with your Microsoft account.
2. Click on Applications | "App registrations" and then "New registration".
3. Enter a name for your app and select the appropriate account type.
4. Set the redirect URI to the 'Web" platform and the URL to `https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect`.  
   - This is the URL that Microsoft Teams will redirect to after authentication.
5. Click "Register" to create the app.
6. Note the Application (client) ID and Directory (tenant) ID for later use.
7. Under "Certificates & secrets", create a new client secret and note it down.
8. Under "API permissions", add the following delegated permissions:
   - Microsoft Graph API: `User.Read`
   - Microsoft 365 Admin Center: `MessageCenter.Read.All`
9. Grant admin consent for the permissions.
    
### Teams Developer Portal Registration
To set up the OAuth2.0 authentication for your app, you need to register your app in the Teams Developer Portal. This registration will allow you to configure the OAuth2.0 settings and permissions for your app.
Here are the steps to register your app in the Teams Developer Portal:
1. Go to the [Teams Developer Portal](https://developer.microsoft.com/en-us/microsoft-365/dev-program) and sign in with your Microsoft account.
2. Click on 'OAuth client registration' and then 'New OAuth client registration'.
3. Provide a name for the registration.
4. For the base URL, enter `https://graph.microsoft.com/v1.0`.
5. Restrict usage by app: 'Existing Teams app'. Provide the 'id' from the `manifest.json` file.
6. OAuth settings
   1. Client ID: Enter the Application (client) ID from the Azure portal.
   2. Client secret: Enter the client secret you created in the Azure portal.
   3. Authorization Endpoint: from the App Registration. See Overview | Endpoints.
   4. Token Endpoint: from the App Registration. See Overview | Endpoints.
   5. Refresh Endpoint: from the App Registration. Same as Token Endpoint.
   6. Scope: https://graph.microsoft.com/ServiceHealth.Read.All
   7. Enable Proof Key for Code Exchange (PKCE): This is a security feature that adds an extra layer of protection to the OAuth2.0 flow. It is recommended to enable this option for your app. Leave as off.
7. Click "Save" to create the OAuth2.0 client registration.
8. Copy the OAuth client registration ID and assign it to the `OAUTH2_REGISTRATION_ID=` environment variable in the `.env` file.









- openapi.json: This file contains the OpenAPI specification for the Graph API 'https://graph.microsoft.com/v1.0/admin/messageCenter/messages' that the declarative agent will use to interact with the Microsoft 365 Admin Center. 
>Generate this file using the following prompt in GitHub Copilot using model GPT 4.5:
```
Extract the openapi definition for the graph API /admin/messageCenter/messages from https://raw.githubusercontent.com/microsoftgraph/msgraph-metadata/refs/heads/master/openapi/v1.0/openapi.yaml. Covert YAML output to JSON.
```

- declarativeCopilot.json: This file contains the declarative agent configuration that defines the behavior and capabilities of the agent.
- manifest.json: This file contains the Teams application manifest that defines metadata for the declarative agent.This is what is displayed in the Teams app store.
- teamsapp.yml: This file contains the Teams Toolkit project configuration, including the OAuth2 registration and other settings.
- .env: This file contains environment variables for the project, including the client ID and secret for OAuth2 authentication.
- Teams Developer Portal: This is where you register your app and configure the OAuth2 authentication settings.
- Entra Application Registration: This is where you register your app and configure the API permissions for the Microsoft Graph API and Microsoft 365 Admin Center.
- 

## Authentication and Permissions
MENTION TEASMS APP AUTHENTICATION INFRASTRUCTURE
The declarative agent uses OAuth2.0 for authentication and requires the following permissions to access the Microsoft 365 Admin Center messages:
- Microsoft Graph API: `User.Read`
- Microsoft 365 Admin Center: `MessageCenter.Read.All`


## Prerequisites
### Teams Toolkit (TTK)
- Install the [Teams Toolkit](https://marketplace.visualstudio.com/items?itemName=TeamsDevApp.ms-teams-toolkit) extension for Visual Studio Code.
### App Registration
- Register your app in the [Azure portal](https://portal.azure.com/).

Here are the steps to register your app:
1. Go to the [Microsoft Entra portal](https://entra.microsoft.com/) and sign in with your Microsoft account.
3. Click on Applications | "App registrations" and then "New registration".
4. Enter a name for your app and select the appropriate account type.
5. Set the redirect URI to the 'Web" platform and the URL to `https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect`.
6. Click "Register" to create the app.
7. Note the Application (client) ID and Directory (tenant) ID for later use.
8. Under "Certificates & secrets", create a new client secret and note it down.
9. Under "API permissions", add the following delegated permissions:
   - Microsoft Graph API: `User.Read`
   - Microsoft 365 Admin Center: `MessageCenter.Read.All`
10. Grant admin consent for the permissions.

## Required Roles - App Registration
To create an app registration in Microsoft Entra (Azure AD), you must have one of the following roles:

* Global Administrator
* Application Administrator
* Cloud Application Administrator

The recommended least-privileged role specifically for creating and managing app registrations is **Application Administrator**.

- **Global Administrator**: Required to grant admin consent for the app registration and API permissions.

## Required Roles - Agent Deployment  
The roles required to manage the Teams app (Agent) in Microsoft 365 and deploy it to the organization are:

* Teams Administrator: Required to manage and deploy Teams apps within the organization via the Teams Admin Center.
* Global Administrator: Can also manage and deploy Teams apps, but has broader permissions beyond Teams management.

The recommended least-privileged role specifically for managing and deploying Teams apps is **Teams Administrator**.

## Required Roles - Teams Developer Portal
To register your app in the Teams Developer Portal, you must have one of the following roles:
* Teams Administrator: Required to manage and deploy Teams apps within the organization via the Teams Admin Center.
* Global Administrator: Can also manage and deploy Teams apps, but has broader permissions beyond Teams management.

The recommended least-privileged role specifically for managing and deploying Teams apps is **Teams Administrator**.
Note: This role is required when using the Teams Toolkit to provision the app registration and deploy the app.

## Required Roles - Agent Usage
To read Microsoft 365 Message Center messages, and therefor use this agent, a user must have one of the following Microsoft 365 admin roles:

* Global Administrator
* Message Center Reader
* Service Support Administrator
* Service Administrator

The recommended least-privileged role specifically for reading Message Center messages is **Message Center Reader**.