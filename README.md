# TeleAmigo Softswitch

## Automatic Deployment

To deploy this scenario, click here: [![Deploy to Azure](https://azuredeploy.net/deploybutton.png)](https://azuredeploy.net/)

## Manual Deployment

From Azure CLI, follow next steps to deploy:

1. Create your resource groups:

`az deployment create --location "East US" --template-file templates/01-resourcegroups.json`

2. Deploy your network:

`az group deployment create --resource-group taNetwork --template-file templates/02-network.json`

3. Deploy your databases:

`az group deployment create --resource-group taDatabases --template-file templates/03-databases.json`

4. Deploy your worker machines:

`az group deployment create --resource-group taworkers --template-file templates/04-workers.json`
