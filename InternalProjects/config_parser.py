import configparser
import os

def get_config(environment):
    config = configparser.ConfigParser()
    config_path = os.path.join('config', f'config.{environment}.ini')
    config.read(config_path)

    if 'jira' not in config:
        raise ValueError(f"No 'jira' section in config file {config_path}")

    return {
        'jira_url': config['jira']['url'],
        'jira_user': config['jira']['user'],
        'jira_pwd': config['jira']['password']
    }
