# Prompting Guide for Message Center Agent

Below are concise natural-language query patterns that can be used with the Message Center Agent. Use these patterns as templates you can paste into the Message Center Agent for both Message Center posts and Microsoft 365 Roadmap items.

## Message Center Posts Overview
- value[] (message object) — per-property patterns
  - **id**
    - Natural language: "Get message MC172851" / "Show message with id MC172851"
  - **title**
    - Natural language: "Messages whose title contains 'PowerPoint'" 
  - **startDateTime** / **endDateTime** / **lastModifiedDateTime**
    - Natural language: 
    - "Messages from March 1, 2021 to June 1, 2021" / "Modified since Jan 1, 2022"
  - **category**
    - Natural language: "Messages in category 'Stay Informed'" or "Show Stay Informed posts"
  - **severity**
    - Natural language: "Show high-severity messages" / "Only Normal severity"
  - **tags** (collection)
    - Natural language: "Messages tagged 'Updated message'" / "Show messages tagged with 'Preview' or 'Updated message'"
    - Important phrasing: use "tagged" or "with tag" in NL to target tags.
  - **isMajorChange** (boolean)
    - Natural language: "Show only major changes" / "Only messages that are a major change"
  - **actionRequiredByDateTime** (nullable datetime)
    - Natural language: "Actions required by after May 1, 2021" / "Messages requiring action by June 15, 2024"
  - **services** (array)
    - Natural language: "Filter on services containing 'Copilot'" / "Messages for Microsoft Teams"
    - Important phrasing: say "for service" or "services containing" to target array elements.
  - **details** (array of name/value pairs)
    - Natural language: "Messages with an ExternalLink" / "Where details contain an ExternalLink equal to '...'"
  - **body.content**
    - Natural language:
      - "Search body for 're-start the rollout'" -> search `body.content`
  
- **Combined / compound queries**
  - Natural language: "Show the top 10 recent major change messages for Copilot modified since Jan 1, 2024"

- **Pagination / next page**
  - Natural language: "Show more messages" or "Show next page" or "Give me the next 10 items"

- **Tips / phrasing guidance** (short)
  - Use "tagged" or "with tag" when you mean the `tags` array.
  - Use "for service" or "services containing" for the `services` array 
  - Use "modified since / before" to target `lastModifiedDateTime`.
  - Use "major change" to target `isMajorChange eq true`.

## Microsoft 365 Roadmap Items Overview
- value[] (roadmap item object) — per-property patterns
  - **id**
    - Natural language: "Get roadmap item 12345" / "Show roadmap item with id 12345"
    - Important: Use exact ID (numbers only) for specific item lookups
  - **title**
    - Natural language: "Roadmap items with 'Copilot' in the title" / "Show roadmap items containing 'Teams'"
  - **created** (creation date)
    - Natural language: "Roadmap items from last week" / "Items created since October 1, 2025" / "Recent roadmap items"
    - Important: Use "created" not "createdDateTime" for date filtering
  - **description**
    - Natural language: "Roadmap items about AI features" / "Items describing enhanced capabilities"
  - **category** 
    - Natural language: "Roadmap items in Microsoft 365 category" / "Show Power Platform roadmap items"
    - Available categories: Microsoft 365, Microsoft Teams, SharePoint, Exchange, OneDrive, Power Platform, Viva, Security & Compliance, Other
  - **status**
    - Natural language: "Show items in development" / "Rolling out features" / "Preview roadmap items"
    - Available statuses: In Development, Rolling Out, Launched, Preview, Planned, Cancelled
  - **targetDate** (expected release date)
    - Natural language: "Items releasing in December 2025" / "Features expected by end of year"
  - **platforms** (array)
    - Natural language: "Roadmap items for Web platform" / "Mobile-supported features"
    - Available platforms: Web, Desktop, Mobile, Mac, iOS, Android
  - **tags** (array)
    - Natural language: "Roadmap items tagged with 'AI'" / "Show items tagged 'Preview'"

- **Combined / compound roadmap queries**
  - Natural language: "Show recent Copilot roadmap items from last month"
  - Natural language: "Microsoft Teams features in development created since October 1"
  - Natural language: "Top 10 newest Power Platform roadmap items"
  - Natural language: "Preview status roadmap items for Web and Desktop platforms"

- **Pagination / next page** (roadmap)
  - Natural language: "Show more roadmap items" / "Next page of roadmap results" / "Give me 20 more roadmap items"

- **Tips / phrasing guidance for roadmap items**
  - Use "roadmap items" or "roadmap" to clearly target roadmap data vs message center
  - Use "created since/after/before" for date filtering (not "createdDateTime")
  - Use exact category names: "Microsoft 365", "Microsoft Teams", "Power Platform", etc.
  - Use exact status names: "In Development", "Rolling Out", "Preview", etc.
  - For specific items, use "roadmap item 12345" (ID only, no prefixes)
  - Combine multiple criteria: "Copilot roadmap items in Microsoft 365 category from last week"

