import logging

import azure.functions as func
from azure.mgmt.compute import ComputeManagementClient

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request.')

    rg = req.params.get('rg')
    vm = req.params.get('vm')
    
    if rg != None and vm != None:
        return func.HttpResponse(f"Hello, {rg} and {vm}. This HTTP triggered function executed successfully.")
    else:
        return func.HttpResponse(
             "This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response.",
             status_code=200
        )
