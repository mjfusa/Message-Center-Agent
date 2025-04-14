Draft a README file for this project including the following sections:  Overview, Purpose, Prerequistives: TTK, App Registration, Teams Developer Portal resistration for oauth2.0, requried roles, Architecure, How to run, conculsion

# Microsoft 365 Copilot Center Message Agent

## Overview
 The M365 Copilot Message Center Agent allows you to search the **Microsoft 365 Admin Center** messages with Copilot chat using natural language prompts.

## M365 Message Center Agent Use Cases
Not only can you search for messages, but you can also use the power of generative AI to summarize them and draft internal communications. Here are some examples of what you can do:
- **Search for messages**: Find specific messages in the Microsoft 365 Admin Center message center.
- **Summarize messages**: Get a summary of the latest messages in the message center.
- **Draft internal communications**: Generate draft emails or messages to share information about updates with your team.
- **Get insights**: Gain insights regarding impact of updates for your organization.
- **Get alternatives** Get suggested alternatives for deprecated features.
- **Get suggested actions**: Get suggested actions for updates that require your attention.

## Architecture
### Zero Code
The declarative agent is built using the Microsoft Teams Toolkit for Visual Studio Code. It leverages the Microsoft Graph API to interact with the Microsoft 365 Admin Center and retrieve messages. Authentication is handled using OAuth2.0, and the agent is designed to work seamlessly with Microsoft 365 Copilot. The declarative agent is a zero-code solution, meaning you don't need to write any code to set it up or use it. The agent is designed to be easy to setup and requires no coding experience.

## Authentication and Graph API Permissions

The implementation of the authentication leverages the M365 Teams app authentication infrastructure that takes care of the OAuth2.0 flow and token management for you. See here:
[Configure authentication for API plugins in agents](https://learn.microsoft.com/en-us/microsoft-365-copilot/extensibility/api-plugin-authentication). Additionally, the Team Toolkit for Visual Studio Code is used to provision the app registration and deploy the app to Microsoft Teams. This eliminates the need for direct Microsoft 365 registration  using the [Teams Developer portal](https://dev.teams.microsoft.com/) and allows you to focus on building your app inside Visual Studio Code.

To support OAuth2.0 authentication, requires the following step:
1. Microsoft Entra App Registration
3. Update the openapi.json file with the security scheme.
4. Provision the app using the Teams Toolkit. 

Details of these steps are provided below.

### Microsoft Entra App Registration
To use the declarative agent, you need to register your app in the Entra portal and configure the necessary permissions. This app registration will be registered on the Teams Developer Portal. The app registration is required to authenticate users and authorize access to the Microsoft Graph API and Microsoft 365 Admin Center. The Teams developer portal provides a secure environment for managing your app's authentication settings and permissions.

Here are the steps to register your app:

1. Go to the [Microsoft Entra portal](https://entra.microsoft.com/) and sign in with your Microsoft account.
2. Click on Applications | "App registrations" and then "New registration".
3. Enter a name for your app registration and select the appropriate account type.
4. Set the redirect URI to the 'Web" platform and the URL to https://teams.microsoft.com/api/platform/v1.0/oAuthRedirect.
This is the URL that Microsoft Teams and M365 Copilot will redirect to after authentication.
5. Click "Register" to create the app.
6. Note the Application (client) ID and Directory (tenant) ID for later use.
7. Under "Certificates & secrets", create a new client secret and note it down.
8. Under "API permissions", add the following delegated permissions:
  - Microsoft Graph API: **User.Read**
  - Microsoft 365 Admin Center: **MessageCenter.Read.All**
9. Grant admin consent for the permissions.

### Update the openapi.json file with the security scheme
Updating the openapi.json file with the security scheme is a crucial step in configuring the declarative agent for OAuth2.0 authentication. The openapi.json file defines the API endpoints and their security requirements, allowing the agent to authenticate users and authorize access to the Microsoft Graph API and Microsoft 365 Admin Center.
1. Update openapi.json with **securitySchemes** as follows:

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

2. Update **authorizationUrl** and **tokenUrl** settings with the authorization and token endpoints from the app registration in the above step. Update the **scopes** setting with https://graph.microsoft.com/ and "Access Microsoft Graph API".

### Provision the app using the Teams Toolkit
The Teams Toolkit for Visual Studio Code streamlines app registration and deployment to Microsoft Teams. It automates OAuth2.0 setup, securely manages client credentials, and eliminates the need to handle infrastructure, letting you focus on app development.

1. Using the Teams Toolkit, in the LIFECYCLE section, select 'Provision'. Note that the Teams Toolkit will register the app in the Teams Developer Portal and update the OAUTH2_REGISTRATION_ID variable in your .env file with the value received from the Teams Developer Portal.

2. Navigate to the Teams Developer Portal, click on  Tools | 'OAuth Client Registration' to view the OAuth2.0 client registration.
Note that the Teams Toolkit updated the OAUTH2_REGISTRATION_ID variable in your .env file with the registration id received from here via the Teams Toolkit 'Provision' step above.

## Use the Message Center Agent in Copilot

Now that you have registered your app and configured the necessary permissions, you can use the Message Center Agent in Microsoft 365 Copilot.

### Starter Prompts
Here are some prompts to get you started with the Message Center Agent:
```C#
Find all message center updates related to Microsoft 365 Copilot created in the last 30 days.

Show me all messages with 'security update' in the title. 

Find all messages with 'Copilot' in the title that were created after March 1, 2025 that are Major Change messages.

Find all messages regarding Microsoft Teams that are 'stay informed' messages published in the last two weeks.

Draft an email about Microsoft Teams updates that are 'Plan for Change' messages published in the last two weeks.
```
### Key Files 
The following files are key to the implementation of the declarative agent:

- **openapi.json**: This file contains the OpenAPI specification for the Graph API ['https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages'](https://learn.microsoft.com/en-us/graph/api/serviceannouncement-list-messages?view=graph-rest-1.0&tabs=http) that the declarative agent will use to search and retrieve messages from the Microsoft 365 Admin Center. 

> NOTE: This file was generated using the following prompt in GitHub Copilot using model GPT 4.5:
Extract the openapi definition for the graph API /admin/messageCenter/messages from https://raw.githubusercontent.com/microsoftgraph/msgraph-metadata/refs/heads/master/openapi/v1.0/openapi.yaml. Covert YAML output to JSON.

- **declarativeCopilot.json**: This file contains the declarative agent configuration that defines the behavior and capabilities of the agent. No capabilities have been defined for this agent.
- **manifest.json**: This file contains the Teams application manifest that defines metadata for the declarative agent.This is what is displayed in the Teams app store.
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