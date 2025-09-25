# Create a PowerPoint for a Team Briefing on Upcoming Changes to M365 Copilot

## Scenario
An IT lead needs to update their team on upcoming planned changes for Microsoft 365. The lead will leverage the Message Center Agent in combination with Copilot Chat to produce a briefing based on new features published to the Microsoft Message Center.

## Methodology
This process uses the Message Center Agent and Copilot’s generative AI capability to produce a team briefing for upcoming changes to Microsoft 365 Copilot and Copilot Chat. It combines the Message Center Agent and Copilot Chat’s ability to create a PowerPoint deck based on the agent’s output.

## Instructions

1.	Start in Copilot Chat

2.	@ mention the Message Center Agent

3.	Enter the following prompt:  
>Find 'Plan for change' messages. Filter on services containing Copilot. Show messages tagged as 'New Feature'. Show messages published since August 1. Sort by Date Last Updated In descending order with newest to oldest.  

Here is the prompt entered:
![Enter prompt](./images/IT%20Team%20Briefing1.png)

The output at this point should look similar to the following:
![Agent Output](./images/Agent%20Output.png)

4. Exit Message Center Agent

5. In Copilot Chat, enter the following prompt:

>I am an IT Lead. I need to review with my team this information. Please create a PowerPoint deck based on based on the consolidation of the content above. The deck should inform the reader, that this content is the latest information from Microsoft Message Center. It should also indicate the criteria used to generate the message list. Be sure to include the message id in each slide.  

Here is the prompt and the output:  
![PowerPoint deck generated](./images/PPT%20Generated.png)

Here is an example of the PowerPoint deck generated [Team Briefing on New Copilot Features](./other/Team%20Briefing%20on%20New%20Copilot%20Features.pptx)

**Note:**  
This process is designed to help IT leads and teams stay informed about Copilot-related changes and new features. 

## Author:
Mike Francis (mjfusa)