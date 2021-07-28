import logging

import azure.functions as func
from azure.mgmt.compute import ComputeManagementClient
from azure.identity import DefaultAzureCredential
import os 
from datetime import datetime

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request.')

    req_body = req.get_json()
    rg = req_body.get('rg')
    vm = req_body.get('vm')
    
    if rg != None and vm != None:
        subscription_id = os.environ.get('SUBSCRIPTION_ID')
        azure_credential = DefaultAzureCredential()
        compute_client = ComputeManagementClient(
            azure_credential,
            subscription_id
        )
        now = datetime.now()
        run_command_parameters = {
            'command_id': 'RunShellScript', # For linux, don't change it
            'script': [
                f'echo "<br />Hello from RunCommand: {now.strftime("%m/%d/%Y %H:%M:%S")}" | sudo tee -a /var/www/html/index.html'
            ]
        }
        poller = compute_client.virtual_machines.run_command(
            rg,
            vm,
            run_command_parameters
        )
        result = poller.result() 
        return func.HttpResponse(f"Hello, {rg} and {vm}. This HTTP triggered function executed successfully.")
    else:
        return func.HttpResponse(
             "This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response.",
             status_code=200
        )
