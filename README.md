# TeleAmigo Softswitch

# Automatic Deployment

To deploy this scenario, click here: [![Deploy to Azure](https://azuredeploy.net/deploybutton.png)](https://azuredeploy.net/)

## Manual Deployment

From Azure CLI, follow next steps to deploy:

1. Create your subscriptions:

`az deployment create --location "East US" --template-file templates/01-resourcegroups.json`

2. Deploy your network:

`az group deployment create --resource-group taNetwork --template-file templates/02-network.json`
