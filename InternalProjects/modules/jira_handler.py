import requests
import json


class JiraHandler:
    def __init__(self, jira_user, jira_pwd, jira_url):
        self.jira_user = jira_user
        self.jira_pwd = jira_pwd
        self.jira_url = jira_url

    def handle_response_code(self, component, response, jira_ticket):
        if "HTTP/2 20" in response.text:
            print(f"{component} has been added/performed in {jira_ticket} successfully!")
        else:
            print(f"{component} failed with error: {response.text}")

    def jira_update(self, component, jira_ticket, data):
        response = requests.put(
            f"{self.jira_url}/issue/{jira_ticket}",
            auth=(self.jira_user, self.jira_pwd),
            data=json.dumps(data),
            headers={"Content-Type": "application/json"}
        )
        self.handle_response_code(component, response, jira_ticket)

    def jira_delete_attachments(self, jira_ticket):
        issue_details = requests.get(
            f"{self.jira_url}/issue/{jira_ticket}?fields=attachment",
            auth=(self.jira_user, self.jira_pwd),
            headers={"Content-Type": "application/json"}
        ).json()
        attachment_ids = [attachment['id'] for attachment in issue_details['fields']['attachment']]

        for attachment_id in attachment_ids:
            requests.delete(
                f"{self.jira_url}/attachment/{attachment_id}",
                auth=(self.jira_user, self.jira_pwd)
            )
            print("Deleting all existing attachments if any...")

    def jira_upload_attachments(self, component, jira_ticket, files):
        response = requests.post(
            f"{self.jira_url}/issue/{jira_ticket}/attachments",
            auth=(self.jira_user, self.jira_pwd),
            headers={"X-Atlassian-Token": "nocheck"},
            files=files
        )
        self.handle_response_code(component, response, jira_ticket)

    def jira_closure(self, component, transition_id, jira_ticket):
        data = {"transition": {"id": transition_id}}
        response = requests.post(
            f"{self.jira_url}/issue/{jira_ticket}/transitions",
            auth=(self.jira_user, self.jira_pwd),
            data=json.dumps(data),
            headers={"Content-Type": "application/json"}
        )
        self.handle_response_code(component, response, jira_ticket)

    def search_issues(self, source, destination, summary):
        jql_query = f"Project=EDE AND labels=90p AND labels={source} AND labels={destination} AND summary ~ '{summary}'"
        response = requests.get(
            f"{self.jira_url}/search",
            auth=(self.jira_user, self.jira_pwd),
            params={"jql": jql_query}
        ).json()
        if response.status_code == 200:
            issues = response.json().get('issues', [])
            return [issue['key'] for issue in issues]
        else:
            response.raise_for_status()

    def jira_mark_as_migrated(self, source, destination):
        jql_query = f"Project=EDE AND labels=90p AND labels={source} AND labels={destination}"
        start_at = 0
        max_results = 50

        while True:
            response = requests.get(
                f"{self.jira_url}/search",
                auth=(self.jira_user, self.jira_pwd),
                params={"jql": jql_query, "startAt": start_at, "maxResults": max_results}
            ).json()

            total_results = response['total']
            print(f"Total tickets which belongs to migrated partition: {total_results}")
            tasks = [issue['key'] for issue in response['issues']]

            for task_key in tasks:
                data = {"update": {"labels": [{"add": "90p_migrated"}]}}
                requests.put(
                    f"{self.jira_url}/issue/{task_key}",
                    auth=(self.jira_user, self.jira_pwd),
                    data=json.dumps(data),
                    headers={"Content-Type": "application/json"}
                )
            start_at += max_results
            if start_at >= total_results:
                break

        print(f"All {total_results} tickets have been marked as 90p_migrated")
