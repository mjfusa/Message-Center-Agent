# Prompting Guide for Message Center Agent

Below are concise natural-language query patterns that can be used with the Message Center Agent. Use these patterns as templates you can paste into the Message Center Agent.

## Overview
- value[] (message object) — per-property patterns
  - id
    - Natural language: "Get message MC172851" / "Show message with id MC172851"
  - title
    - Natural language: "Messages whose title contains 'PowerPoint'" 
  - startDateTime / endDateTime / lastModifiedDateTime
    - Natural language: 
    - "Messages from March 1, 2021 to June 1, 2021" / "Modified since Jan 1, 2022"
  - category
    - Natural language: "Messages in category 'Stay Informed'" or "Show Stay Informed posts"
  - severity
    - Natural language: "Show high-severity messages" / "Only Normal severity"
  - tags (collection)
    - Natural language: "Messages tagged 'Updated message'" / "Show messages tagged with 'Preview' or 'Updated message'"
    - Important phrasing: use "tagged" or "with tag" in NL to target tags.
  - isMajorChange (boolean)
    - Natural language: "Show only major changes" / "Only messages that are a major change"
  - actionRequiredByDateTime (nullable datetime)
    - Natural language: "Actions required by after May 1, 2021" / "Messages requiring action by June 15, 2024"
  - services (array)
    - Natural language: "Filter on services containing 'Copilot'" / "Messages for Microsoft Teams"
    - Important phrasing: say "for service" or "services containing" to target array elements.
  - details (array of name/value pairs)
    - Natural language: "Messages with an ExternalLink" / "Where details contain an ExternalLink equal to '...'"
  - body.content
    - Natural language:
      - "Messages with HTML bodies" -> target `body.contentType`
      - "Search body for 're-start the rollout'" -> search `body.content`
  
- Combined / compound queries
  - Natural language: "Show the top 10 recent major change messages for Copilot modified since Jan 1, 2024"

- Pagination / next page
  - Natural language: "Show next page" or "Give me the next 10 items"

- Tips / phrasing guidance (short)
  - Use "tagged" or "with tag" when you mean the `tags` array.
  - Use "for service" or "services containing" for the `services` array 
  - Use "modified since / before" to target `lastModifiedDateTime`.
  - Use "major change" to target `isMajorChange eq true`.

