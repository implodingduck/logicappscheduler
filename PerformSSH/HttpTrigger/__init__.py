import logging

import azure.functions as func
import paramiko

import os
from datetime import datetime
def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python PerformSSH HTTP trigger function processed a request.')

    name = req.params.get('name')
    if not name:
        try:
            req_body = req.get_json()
        except ValueError:
            pass
        else:
            name = req_body.get('name')

    if name:
        ssh_password = os.environ.get('SSH_PASSWORD')
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(hostname=name,
                           username="adminuser",
                           password=ssh_password)
        now = datetime.now()
        stdin, stdout, stderr = client.exec_command(f'echo "<br />Hello from ssh: {now.strftime("%m/%d/%Y %H:%M:%S")}" >> /var/www/html/index.html')

        out = stdout.read().decode().strip()
        error = stderr.read().decode().strip()
        logging.info(out)
        if error:
            raise Exception('There was an error pulling the runtime: {}'.format(error))
        client.close()
        return func.HttpResponse(f"Hello, {name}. This HTTP triggered function executed successfully.")
    else:
        return func.HttpResponse(
             "This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response.",
             status_code=200
        )
