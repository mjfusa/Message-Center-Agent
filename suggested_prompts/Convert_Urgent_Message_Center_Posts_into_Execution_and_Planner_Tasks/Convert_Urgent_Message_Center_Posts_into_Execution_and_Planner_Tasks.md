# Convert Urgent Message Center Posts into Execution and Planner Tasks

## Use Case
An M365 operations team needs to rapidly convert urgent Microsoft Message Center posts into immediate execution actions, including technical remediation steps, communications drafts, and operational tracking in Microsoft Planner. This use case uses the Message Center Agent to identify and structure the highest-priority issues, then uses the Planner agent to convert that output into production-ready Planner tasks without losing any implementation detail.

## Methodology
This process combines two agent stages. In stage one, the Message Center Agent identifies and ranks the five most urgent issues from the last 30 days, classifies each issue by action type, and produces detailed action guidance including links, deadlines, portal steps, scripts, and communication drafts. In stage two, the Planner agent consumes that output exactly as provided and creates deterministic, execution-ready tasks in the existing Planner plan and buckets.

## Instructions

1. Start in Copilot Chat

2. @ mention the Message Center Agent

3. Enter the following prompt:

> Goal: Convert urgent Message Center messages in to action including step-by-step instructions, comms drafts, Admin Center (portal) steps, and draft scripts for configuration changes or settings listing.
> 
> Methodology:
> 
> 1) Find the 5 most urgent issues. Categorize by action topics, for example Configuration, Comms, Other. Suggest action that should be taken. If comms, draft communication to appropriate audience for example Admin or Users. If configuration include the steps, portals and draft scripts needed to remediate. Hint: posts that are marked as Major Change and have a planForChange or preventOrFixIssue category or have a critical or high severity should be ranked highly. Timeframe: Created or Modified in last 30 days. Show the highest ranked issues first. Be sure to include links to the Message Center message. If an Action Required By date is provided, include it in the output.

4. Close Message Center Agent

5. @ mention Planner agent

6. Enter the following prompt:

> Role and Objective
> You are an M365 Service Operations Project Manager responsible for transforming the output from the Message Center agent into fully executable Microsoft Planner tasks.
> Your output must be production-ready and saved immediately into Planner using existing artifacts only.
> You must fully consume and preserve every relevant detail from the provided Message Center Agent context, including:
> - Deadlines and rollout windows
> - Impacted workloads and admin roles
> - Exact remediation steps
> - Entire scripts, queries, and commands
> - Entire draft communications
> No information loss, summarization, or interpretation is permitted.
> 
> Target Planner Configuration (Authoritative)
> - Planner Plan: M365 Actions and Change Readiness
> - Buckets (pre-created; do not modify):
>   - Action Required (Action Required By date is provided)
>   - Action Needed (No firm deadline yet)
>   - In Validation / Testing
>   - Completed / Closed
> - Goal (must be applied to every task created):
>   April-May 2026 Microsoft 365 Changes
> 
> Source Data (Authoritative)
> Use only the above output from the Message Center Agent which includes 5 most urgent Microsoft 365 Message Center items, including:
> - Message Center ID and URL
> - Severity, Major Change flag, and category
> - Action Required By date (if present)
> - Impacted admin and user roles
> - Draft communications (subject + full body)
> - Exact PowerShell, KQL, Graph API, and portal navigation steps
> If a detail exists in the source, it must appear in at least one task.
> 
> Task Creation Rules (Deterministic)
> For each of the 5 Message Center items:
> 1) Task Breakdown
> - Create separate tasks for:
>   - Configuration / Technical execution
>   - Communications / Notifications
> - If only one action type exists, create one task only.
> 2) Bucket Assignment (Urgency Only)
> - Deadline explicitly stated -> Action Required
> - No firm deadline -> Action Needed
> - Testing or validation phase -> In Validation / Testing
> - Fully implemented -> Completed / Closed
> 3) Priority
> - Any deadline-driven task -> Urgent
> - Non-deadline tasks -> Medium
> 4) Goal Association
> - Associate all April-May 2026 items to:
>   April-May 2026 Microsoft 365 Changes
> 
> Task Content Requirements (Zero-Tolerance)
> Task Title (Exact Format Required):
> <Workload> - <Action> (<Task Type>) - Due <MMM DD, YYYY>
> 
> Examples:
> - M365 Apps - Update deployment configs to remove SAEC (Config) - Due Apr 15, 2026
> - Teams - Notify users about AI meeting recaps (Comms) - Due May 15, 2026
> 
> Task Description / Notes (Required for ALL Tasks)
> Include all of the following sections:
> - What and Why: Clear explanation of the change and its business or technical impact
> - Suggested Action: Explicit execution or decision required
> - Message Center Link: Clickable URL using the MC ID
> 
> Configuration / Technical Tasks (Mandatory When Applicable)
> - Exact portal navigation paths (for example: Microsoft 365 admin center -> Copilot and AI controls)
> - All scripts copied:
>   - PowerShell
>   - KQL
>   - Graph API
> - Do not summarize, reformat, or improve scripts.
> 
> Communications Tasks (Mandatory When Applicable)
> - Paste the full draft email, including:
>   - Subject
>   - Body
> - Explicitly state the target audience, for example:
>   - All Users
>   - Exchange Admins
>   - Endpoint / Intune Admins
> 
> Execution Constraints (Hard Rules)
> - Create tasks immediately: no previews, no drafts, no confirmation prompts
> - Do not summarize, paraphrase, or infer missing content
> - Buckets represent urgency only; progress reflects execution status
> - Tasks must be Planner-ready with zero manual edits required
> - Assume tasks will be actioned immediately by an operations team
> - Lack of explicit Planner identifiers must never block execution if the plan can be deterministically located via Planner search
> 
> Output Requirements
> - Tasks must be created and saved in Planner
> - No commentary, analysis, or recommendations
> - No prose explanations
> - Output reflects a fully executable Planner board
> 
> Closing Summary
> - Indicate the total number of tasks created
> - List the tasks created by title and classification

## Author
mjfusa
