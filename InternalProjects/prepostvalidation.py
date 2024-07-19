import os

from config_parser import get_config
from modules.jira_handler import JiraHandler

# Select environment (e.g., 'dev' or 'prod')
environment = 'dev'
config = get_config(environment)
Source_Partition_Number = os.getenv('Source_Partition_Number')
Destination_Partition_Number = os.getenv('Destination_Partition_Number')
validationType = os.getenv('Destination_Partition_Number')
jiraPreSubtask=$4;
jiraPostSubtask=$5;
hydra_token=$6;
mysqlUser=$7; mysqlPass=$8; mysqlHost=${9}; mysqlDb=${10}
jiraUser=${11}; jiraPwd=${12}; jira_url=${13}; transition_id=${14}


# Initialize JiraHandler
jira = JiraHandler(os.getenv('jira_user'), os.getenv('jira_pwd'), config['jira_url'])

# Example usage:
jira_ticket = "JIRA-123"
component = "SomeComponent"
data = {"fields": {"summary": "New Summary"}}

# Update Jira issue
jira.jira_update(component, jira_ticket, data)

# Delete attachments
jira.jira_delete_attachments(jira_ticket)

# Upload attachments
files = {'file': open('file_path', 'rb')}
jira.jira_upload_attachments(component, jira_ticket, files)

# Close Jira issue
transition_id = "5"
jira.jira_closure(component, transition_id, jira_ticket)

# Mark issues as migrated
source = "SRC"
destination = "DST"
jira.jira_mark_as_migrated(source, destination)
