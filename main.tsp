// ============================================================================
// IMPORTS AND NAMESPACE DECLARATIONS
// ============================================================================
// Import necessary TypeSpec libraries for HTTP operations, OpenAPI 3.0 generation,
// and Microsoft 365 Copilot agent functionality
import "@typespec/http";
import "@typespec/openapi3";
import "@microsoft/typespec-m365-copilot";

// Enable TypeSpec features for HTTP operations, OpenAPI generation, and M365 Copilot
using TypeSpec.Http;
using TypeSpec.OpenAPI;
using TypeSpec.M365.Copilot.Agents;
using TypeSpec.M365.Copilot.Actions;

// ============================================================================
// AGENT CONFIGURATION
// ============================================================================
// Define the declarative agent with its name and description. This agent enables
// users to interact with Microsoft 365 Message Center and Roadmap data using
// natural language queries through Microsoft 365 Copilot.
@agent(
  "Message Center Agent",
  "This agent helps you search and summarize Microsoft 365 Admin Center messages using natural language. Works with the M365Roadmap Copilot Connector to provide related Microsoft 365 Roadmap information. Requires Message Center Reader role or higher."
)

// Load detailed instructions for the agent from an external markdown file.
// This file contains the system prompt and behavior guidelines for the agent.
@instructions("$[file('instructions.md')]")

// ============================================================================
// CONVERSATION STARTERS
// ============================================================================
// Define suggested prompts that users can click to quickly start common queries.
// These appear in the Copilot interface to help users discover agent capabilities.
@conversationStarter(#{
  title: "Search for Microsoft 365 Copilot Updates",
  text: "Find messages related to Microsoft 365 Copilot published in the last 30 days."
})

@conversationStarter(#{
  title: "Search by Message body",
  text: "Show messages with 'security update' in the message body."
})

@conversationStarter(#{
  title: "Inform the team regarding upcoming major changes in Microsoft 365 Copilot",
  text: "Show message regarding updates from the last month that are related to Copilot and marked as major changes."
})

@conversationStarter(#{
  title: "Access messages by service and tags",
  text: "Find messages tagged as User impact. Filter on services containing 'Copilot'. Show messages published in the last 30 days."
})

@conversationStarter(#{
  title: "Get Critical Updates",
  text: "Show all critical messages."
})

@conversationStarter(#{
  title: "What changed recently?",
  text: "What changed for Copilot since yesterday?"
})

// ============================================================================
// MESSAGE CENTER AGENT NAMESPACE
// ============================================================================
// Main namespace containing both the Message Center API and Roadmap API definitions
namespace MessageCenterAgent {
  
  // ==========================================================================
  // MESSAGE CENTER API SERVICE DEFINITION
  // ==========================================================================
  // This service provides access to Microsoft 365 Message Center messages via
  // Microsoft Graph API. It requires OAuth authentication and appropriate
  // permissions to access service announcements.
  @service
  @actions(#{
    nameForHuman: "Message Center Agent",
    descriptionForHuman: "API to obtain message center messages including OAuth authentication",
    descriptionForModel: "Retrieve the message center messages"
  })
  // Connect to Microsoft Graph v1.0 endpoint for service announcements
  @server("https://graph.microsoft.com/v1.0", "Microsoft Graph v1.0 endpoint")
  // Configure OAuth 2.0 authentication with authorization code flow
  // Requires ServiceMessage.Read.All scope for accessing message center data
  @useAuth(
    OAuth2Auth<[{
      type: OAuth2FlowType.authorizationCode,
      authorizationUrl: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
      tokenUrl: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
      refreshUrl: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
      scopes: ["https://graph.microsoft.com/ServiceMessage.Read.All"]
    }]>
  )
  namespace MessageCenterAPI {
    
    // ========================================================================
    // DATA MODELS - Message Center
    // ========================================================================
    // Define the structure of message center data returned from Microsoft Graph API
    
    // Represents the content and format of a message body
    model MessageBody {
      contentType: "html" | "text";  // Content can be HTML or plain text
      content: string;                // The actual message content
    }

    // Represents additional details about a message (e.g., RoadmapIds, ExternalLink)
    model MessageDetail {
      name: string;   // The type/name of the detail (e.g., "RoadmapIds")
      value: string;  // The detail value (e.g., "123456,789012")
    }

    // Core model representing a service announcement message from Message Center
    model ServiceAnnouncementMessage {
      id: string;                              // Unique message identifier
      title: string;                           // Message title/subject
      body: MessageBody;                       // Message content with content type
      tags?: string[];                         // Classification tags (e.g., "New feature", "User impact")
      details?: MessageDetail[];               // Additional metadata (e.g., RoadmapIds)
      services?: ("Basic Mobility and Security" | "Dynamics 365 Apps" | "Exchange Online" | "Microsoft 365 apps" | "Microsoft 365 Copilot Chat" | "Microsoft 365 for the web" | "Microsoft 365 suite" | "Microsoft Copilot (Microsoft 365)" | "Microsoft Copilot Chat" | "Microsoft Dataverse" | "Microsoft Defender XDR" | "Microsoft Entra" | "Microsoft Forms" | "Microsoft Intune" | "Microsoft OneDrive" | "Microsoft Power Automate" | "Microsoft Power Automate in Microsoft 365" | "Microsoft Purview" | "Microsoft Teams" | "Microsoft Viva" | "Planner" | "Power Apps" | "Power Apps in Microsoft 365" | "Power BI" | "Power Platform" | "Project for the web" | "SharePoint Online" | "Windows" | "Windows Autopatch")[];  // Affected Microsoft 365 services
      category?: "stayInformed" | "planForChange" | "preventOrFixIssue";  // Message category/action required
      severity?: "normal" | "high" | "critical";                          // Importance level
      startDateTime?: utcDateTime;             // When the message was first published
      lastModifiedDateTime?: utcDateTime;      // When the message was last updated
      isMajorChange?: boolean;                 // Whether this represents a major change
    }

    // Represents the response structure for message queries, including OData metadata
    model MessagesResponse {
      @doc("Context URL for the response data")
      `@odata.context`?: string;  // OData metadata URL
      
      @doc("Total number of records matching the filter. Always present when $count=true.")
      `@odata.count`: int32;  // Total count of matching messages
      
      @doc("Array of message objects. Empty when $top=0 (count-only queries).")
      value: ServiceAnnouncementMessage[];  // The actual message data
      
      @doc("Next page URL if more results are available")
      `@odata.nextLink`?: string;  // Pagination link for additional results
    }

    // ========================================================================
    // API OPERATIONS - Message Center
    // ========================================================================
    // Define the HTTP operations for querying message center data
    
    // GET operation to retrieve message center messages with extensive filtering capabilities
    @route("/admin/serviceAnnouncement/messages")
    @get
    @doc("Retrieve the message center messages or just the count")
    op getMessages(
      // Sort order parameter - defaults to newest messages first
      @query("$orderby") @doc("Order by clause for sorting results. Defaults to newest messages first (lastModifiedDateTime desc)") orderby?: string = "lastModifiedDateTime desc",
      
      // Include count in response - defaults to true
      @query("$count") @doc("Total number of records returned") count: boolean = true,
      
      // Pagination preference - limits page size to 5 results per page
      @header Prefer?: string = "odata.maxpagesize=5",
      
      // Number of results to return (set to 0 for count-only queries)
      @query("$top") @doc("Number of records to return. Set to 0 to retrieve only the count (@odata.count) without any message data. Useful for count-only queries like 'How many messages are there?'") top?: int32,
      
      // Skip parameter for pagination
      @query("$skip") @doc("Number of records to skip") skip?: int32,
      
      // Complex filter parameter with extensive filtering capabilities using OData syntax
      @query("$filter") @doc("Filter the results based on specific conditions. For count-only queries, combine with $top=0 to get just the total number of matching records. Use `contains(tolower(title),tolower('search term'))` to search within the title property for a specific term or phrase. For multi-word searches, include the entire phrase in quotes. For create time, use the 'startDateTime' property with a date format. For example, `startDateTime ge 2025-03-01T00:00:00Z` to filter messages created after March 1, 2025. For major change messages, use `isMajorChange eq true`. To combine filters, use `and` operator. For example, `contains(tolower(title),tolower('Copilot agent')) and startDateTime ge 2025-03-01T00:00:00Z`. For the 'Tags' field, here is an example of the a query segment for the tags field: tags/any(t: t eq 'New feature'). For the 'severity' field, you can filter by severity using `severity eq 'normal'` or `severity eq 'high'` or `severity eq 'critical'`. For the 'category' field, you can filter by category using `category eq 'stayInformed'` or `category eq 'planForChange'` or `category eq 'preventOrFixIssue'`. For the 'Services' field, here is an example of a query segment for the services field: services/any(s: contains(s, 'Copilot')). When searching an message center update for roadmap ids, these are found in the 'details' field. Here is an example of a query segment for the details field, when searching for RoadmapIds: details/any(d: d/name eq 'RoadmapIds' and contains(d/value, '501107')). Note the 'name' property is used to specify the type of detail being searched, in this case 'RoadmapIds'. The 'value' property is then used to search for the specific roadmap id. RoadmapIds is case sensitive and must be used exactly as shown. To filter by message body, use `contains(tolower(body/content),tolower('search term'))` to search within the body content.") filter?: string
    ): MessagesResponse | {
      // Error response: Unauthorized (401) - authentication failed or missing
      @statusCode statusCode: 401;
      @doc("Unauthorized. Please check your authentication credentials.")
      error: {
        code: string;
        message: string;
      };
    } | {
      // Error response: Forbidden (403) - insufficient permissions
      @statusCode statusCode: 403;
      @doc("Insufficient permissions. You need the Message Center Reader or the Global Admin role to access this agent.")
      error: {
        code: string;
        message: string;
      };
    } | {
      // Error response: Not Found (404) - resource doesn't exist
      @statusCode statusCode: 404;
      @doc("Not Found")
      error: {
        code: string;
        message: string;
      };
    };
  }

  // ==========================================================================
  // MICROSOFT 365 ROADMAP API SERVICE DEFINITION
  // ==========================================================================
  // This service provides access to Microsoft 365 Roadmap data via a public API.
  // Unlike the Message Center API, this requires NO authentication and provides
  // information about upcoming features and release plans for Microsoft 365 services.
  @service
  @actions(#{
    nameForHuman: "M365 Roadmap Connector",
    descriptionForHuman: "API for accessing Microsoft 365 roadmap items",
    descriptionForModel: "Retrieve Microsoft 365 roadmap information"
  })
  // Connect to the Microsoft 365 Roadmap public API (v2)
  @server("https://www.microsoft.com/releasecommunications/api/v2", "Microsoft 365 Roadmap API")
  namespace RoadmapAPI {
    
    // ========================================================================
    // DATA MODELS - Roadmap
    // ========================================================================
    // Define the structure of roadmap data returned from the Roadmap API
    
    // Core model representing a Microsoft 365 roadmap item/feature
    model RoadmapItem {
      id: string;                           // Unique roadmap item identifier (e.g., "123456")
      title: string;                        // Feature/item title
      created?: utcDateTime;                // When the roadmap item was created (use this for date filtering!)
      description?: string;                 // Detailed description of the feature
      category?: string;                    // Feature category (e.g., "Microsoft 365", "Teams")
      status?: string;                      // Current status (e.g., "In Development", "Launched")
      targetDate?: utcDateTime;             // Expected release date
      generalAvailabilityDate?: utcDateTime; // General availability date
      releasePhase?: string;                // Release phase (e.g., "Public Preview", "General Availability")
      platforms?: string[];                 // Target platforms (e.g., ["Web", "Desktop", "Mobile"])
    }

    // Represents the response structure for roadmap queries, including OData metadata
    model RoadmapResponse {
      @doc("Array of roadmap items")
      value: RoadmapItem[];  // The actual roadmap item data
      
      @doc("Total number of roadmap items matching the filter")
      `@odata.count`?: int32;  // Total count of matching items (when $count=true)
      
      @doc("Next page URL if more results are available")
      `@odata.nextLink`?: string;  // Pagination link for additional results
    }

    // ========================================================================
    // API OPERATIONS - Roadmap
    // ========================================================================
    // Define the HTTP operations for querying Microsoft 365 roadmap data
    
    // GET operation to retrieve roadmap items with OData query support
    // IMPORTANT: Use 'created' field for date operations (NOT 'createdDateTime')
    @route("/m365")
    @get
    @doc("Retrieve roadmap items with optional filtering, sorting, and pagination. Always use 'created' field for date operations, not 'createdDateTime'.")
    op getRoadmapItems(
      // OData filter parameter with extensive examples for various query patterns
      @query("$filter") 
      @doc("OData filter expression. IMPORTANT: Use 'created' field for date filtering (not 'createdDateTime'). Supports contains(), tolower(), and date comparisons.")
      @example("id eq 123456", #{ title: "Find roadmap item by id", description: "Find specific roadmap item by its unique ID. ALWAYS use 'eq' operator for ID lookups, never 'contains'." })
      @example("id in (123456, 789012, 345678)", #{ title: "Find multiple roadmap items by IDs", description: "When looking up multiple IDs use 'in' operator. ALWAYS use 'in' for multiple ID lookups." })
      @example("contains(tolower(title), 'copilot') and created ge 2025-10-08T00:00:00Z", #{ title: "Copilot items from last week", description: "Find roadmap items containing 'copilot' published in the last week" })
      @example("created ge 2025-10-08T00:00:00Z", #{ title: "Recent items (last 7 days)", description: "Items created in the last 7 days" })
      @example("contains(tolower(title), 'teams')", #{ title: "Search by title", description: "Search for items containing specific text in title" })
      @example("created ge 2025-10-01T00:00:00Z and created le 2025-10-15T00:00:00Z", #{ title: "Date range filter", description: "Items within a specific date range" })
      @example("status eq 'In Development'", #{ title: "Filter by status", description: "Items with specific status" })
      @example("category eq 'Microsoft 365' and created ge 2025-10-01T00:00:00Z", #{ title: "Category and date filter", description: "Items in specific category from recent date" })
      @example("contains(tolower(title), 'copilot') and category eq 'Microsoft 365' and created ge 2025-10-01T00:00:00Z", #{ title: "Complex multi-criteria filter", description: "Multiple conditions with title, category, and date" })
      filter?: string,
      
      // OData orderby parameter for sorting results
      @query("$orderby") 
      @doc("OData order by expression. Use 'created' field for date sorting.")
      @example("created desc", #{ title: "Newest items first", description: "Order by creation date, newest first" })
      @example("created asc", #{ title: "Oldest items first", description: "Order by creation date, oldest first" })
      @example("title asc", #{ title: "Alphabetical by title", description: "Order alphabetically by title" })
      @example("status asc, created desc", #{ title: "Status then date", description: "Order by status, then by creation date" })
      orderby?: string,
      
      // Limit number of results (pagination)
      @query("$top") 
      @doc("Number of items to return (1-100)")
      @example(10, #{ title: "Default count" })
      @example(50, #{ title: "Large result set" })
      @example(100, #{ title: "Maximum allowed" })
      top?: int32,
      
      // Skip parameter for pagination
      @query("$skip") 
      @doc("Number of items to skip for pagination") 
      skip?: int32,
      
      // Include total count in response
      @query("$count") 
      @doc("Include count of total items") 
      count?: boolean
    ): RoadmapResponse | {
      // Error response: Bad Request (400) - invalid query syntax or parameters
      @statusCode statusCode: 400;
      @doc("Bad request - invalid query parameters")
      error: {
        code: string;
        message: string;
      };
    } | {
      // Error response: Internal Server Error (500) - unexpected server error
      @statusCode statusCode: 500;
      @doc("Internal server error")
      error: {
        code: string;
        message: string;
      };
    };
  }
}

// ============================================================================
// END OF SPECIFICATION
// ============================================================================
