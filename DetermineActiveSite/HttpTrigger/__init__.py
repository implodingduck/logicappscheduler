import logging

import azure.functions as func
from azure.cosmos import exceptions, CosmosClient, PartitionKey

import os 
import json

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function (DetermineActiveSite) processed a request.')
    client = CosmosClient(os.environ.get('COSMOSDB_ENDPOINT'), os.environ.get('COSMOSDB_KEY'))
    db = client.get_database_client(os.environ.get('COSMOSDB_NAME'))
    container = db.get_container_client(os.environ.get('COSMOSDB_CONTAINER'))
    #query = "SELECT * FROM c WHERE c.id=@id"
    item = container.read_item(item='activesite', partition_key='activesite')

    return func.HttpResponse(f"Hello there! The DetermineActiveSite HTTP triggered function executed successfully. Active Site: {item['value']}")
    # name = req.params.get('name')
    # if not name:
    #     try:
    #         req_body = req.get_json()
    #     except ValueError:
    #         pass
    #     else:
    #         name = req_body.get('name')

    # if name:
    #     return func.HttpResponse(f"Hello, {name}. This HTTP triggered function executed successfully.")
    # else:
    #     return func.HttpResponse(
    #          "This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response.",
    #          status_code=200
    #     )
