# Java on Azure Container Apps workshop

You will find here a full workshop that deploys and runs several microservices on Azure Container Apps, including:

* City service: Native executable of a Reactive Quarkus microservice using Azure Cosmos DB for MongoDB (vCore) 
* Weather service: Native executable of a Micronault microservice using Azure Database For MySQL Flexible server
* Gateway: Nginx as a reverse proxy, calling the above services in the same ACA environment using the container app name
* Weather app frontend: A simple web app using the above gateway to call the city and weather service and display the result

## Prerequisites

This workshop requires the following to be installed on your machine:

* Unix-like operating system installed. For example, Ubuntu, Azure Linux, macOS, WSL2.
* [Git](https://git-scm.com/downloads)
* [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli?view=azure-cli-latest)
* [JDK 17](https://docs.microsoft.com/java/openjdk/download?WT.mc_id=asa-java-judubois#openjdk-17)
* [Maven](https://maven.apache.org/download.cgi)
* [Docker](https://docs.docker.com/get-docker/)

## Prepare the source code

Prepare the source code of samples by cloning the repository and navigating to the `aca` directory:

```bash
git clone https://github.com/majguo/azure-spring-apps-training.git
cd azure-spring-apps-training/aca
WORKING_DIR=$(pwd)
```

## Set up databases

Create a resource group and deploy an Azure Cosmos DB for MongoDB (vCore) and an Azure Database for MySQL Flexible Server in it.

```bash
let "randomIdentifier=$RANDOM*$RANDOM"
LOCATION=westeurope
RESOURCE_GROUP_NAME=aca-lab-rg-$randomIdentifier
COSMOS_MONGODB_SERVER_NAME=cosmosmongo$randomIdentifier
MYSQL_SERVER_NAME=mysql$randomIdentifier
MYSQL_DB_NAME=demodb
DB_ADMIN=demouser
DB_ADMIN_PWD='super$ecr3t'$RANDOM$RANDOM

az group create \
    --name $RESOURCE_GROUP_NAME \
    --location $LOCATION
az deployment group create \
    --resource-group $RESOURCE_GROUP_NAME \
    --template-file $WORKING_DIR/setup-db/azuredeploy.json \
    --parameters cosmosMongoDBServerName=$COSMOS_MONGODB_SERVER_NAME \
    --parameters cosmosMongoDBAdminLogin=$DB_ADMIN \
    --parameters cosmosMongoDBAdminLoginPassword=$DB_ADMIN_PWD \
    --parameters mysqlServerName=$MYSQL_SERVER_NAME \
    --parameters mysqlAdminLogin=$DB_ADMIN \
    --parameters mysqlAdminLoginPassword=$DB_ADMIN_PWD \
    --parameters mysqlDatabaseName=$MYSQL_DB_NAME
```

These databases will be used by the microservices later.

## Create an Azure Container Registry

Create an Azure Container Registry and log in to it. 

```bash
REGISTRY_NAME=acr$randomIdentifier
az acr create \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $REGISTRY_NAME \
    --sku Basic \
    --admin-enabled
ACR_LOGIN_SERVER=$(az acr show \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $REGISTRY_NAME \
    --query 'loginServer' \
    --output tsv | tr -d '\r')
ACR_USER_NAME=$(az acr credential show \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $REGISTRY_NAME \
    --query 'username' \
    --output tsv | tr -d '\r')
ACR_PASSWORD=$(az acr credential show \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $REGISTRY_NAME \
    --query 'passwords[0].value' \
    --output tsv | tr -d '\r')
docker login $ACR_LOGIN_SERVER \
    -u $ACR_USER_NAME \
    -p $ACR_PASSWORD
```

You will build application images and push them to this registry.

## Create an Azure Container Apps Environment

Create an Azure Container Apps environment.

```bash
ACA_ENV=acaenv$randomIdentifier
az containerapp env create \
    --resource-group $RESOURCE_GROUP_NAME \
    --location westeurope \
    --name $ACA_ENV
```

The environment creates a secure boundary around a group of your container apps. You will deploy your microservices to this environment and they can able to communicate with each other.

## Build a Reactive Quarkus microservice using Azure Cosmos DB for MongoDB

Build a reactive [Quarkus](https://quarkus.io/) microservice that references guides [GETTING STARTED WITH REACTIVE](https://quarkus.io/guides/getting-started-reactive) and [SIMPLIFIED MONGODB WITH PANACHE](https://quarkus.io/guides/mongodb-panache#reactive) and is bound to an [Azure Cosmos DB for MongoDB vCore](https://learn.microsoft.com/azure/cosmos-db/mongodb/vcore/introduction).

The source code is in the [city-service](./city-service/) directory. The *city-service* exposes a REST API to retrieve cities from a MongoDB database using reractive programming.

Run the following commands to build a native executable, build a Docker image, push it to the Azure Container Registry, and deploy it to the Azure Container Apps.

```bash
# Build and push city-service image to ACR
cd $WORKING_DIR/city-service
mvn clean package -DskipTests -Dnative -Dquarkus.native.container-build

docker build -f src/main/docker/Dockerfile.native -t city-service .
docker tag city-service ${ACR_LOGIN_SERVER}/city-service
docker push ${ACR_LOGIN_SERVER}/city-service

# Deploy city service to ACA
ACA_CITY_SERVICE_NAME=city-service
QUARKUS_MONGODB_CONNECTION_STRING="mongodb+srv://$DB_ADMIN:$DB_ADMIN_PWD@$COSMOS_MONGODB_SERVER_NAME.mongocluster.cosmos.azure.com/?tls=true&authMechanism=SCRAM-SHA-256&retrywrites=false&maxIdleTimeMS=120000"
az containerapp create \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $ACA_CITY_SERVICE_NAME \
    --image ${ACR_LOGIN_SERVER}/city-service \
    --environment $ACA_ENV \
    --registry-server $ACR_LOGIN_SERVER \
    --registry-username $ACR_USER_NAME \
    --registry-password $ACR_PASSWORD \
    --target-port 8080 \
    --env-vars \
        QUARKUS_MONGODB_CONNECTION_STRING=${QUARKUS_MONGODB_CONNECTION_STRING} \
    --ingress 'internal' \
    --min-replicas 1
```

Notice that the type of ingress is `internal` because the *city-service* is not intended to be accessed directly from the internet, instead, it will be accessed by a gateway later.

## Build a Micronault microservice using Azure Database For MySQL Flexible server

Build a [Micronault](https://micronaut.io/) microserver that uses JPA to access an [Azure Database for PostgreSQL - Flexible Server](https://learn.microsoft.com/azure/postgresql/flexible-server/overview).

The source code is in the [weather-service](./weather-service/) directory. The *weather-service* exposes a REST API to retrieve weather information for a given city from a MySQL database.

Run the following commands to build a native executable, build a Docker image, push it to the Azure Container Registry, and deploy it to the Azure Container Apps.

```bash
# Build and push weather-service image to ACR
cd $WORKING_DIR/weather-service
mvn clean package -Dpackaging=docker-native -Pgraalvm -DskipTests=true

docker tag weather-service ${ACR_LOGIN_SERVER}/weather-service
docker push ${ACR_LOGIN_SERVER}/weather-service

# Deploy weather service to ACA
ACA_WEATHER_SERVICE_NAME=weather-service
DATASOURCES_DEFAULT_URL=jdbc:mysql://$MYSQL_SERVER_NAME.mysql.database.azure.com:3306/$MYSQL_DB_NAME
DATASOURCES_DEFAULT_USERNAME=$DB_ADMIN
DATASOURCES_DEFAULT_PASSWORD=$DB_ADMIN_PWD
az containerapp create \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $ACA_WEATHER_SERVICE_NAME \
    --image ${ACR_LOGIN_SERVER}/weather-service \
    --environment $ACA_ENV \
    --registry-server $ACR_LOGIN_SERVER \
    --registry-username $ACR_USER_NAME \
    --registry-password $ACR_PASSWORD \
    --target-port 8080 \
    --env-vars \
        DATASOURCES_DEFAULT_URL=${DATASOURCES_DEFAULT_URL} \
        DATASOURCES_DEFAULT_USERNAME=${DATASOURCES_DEFAULT_USERNAME} \
        DATASOURCES_DEFAULT_PASSWORD=${DATASOURCES_DEFAULT_PASSWORD} \
    --ingress 'internal' \
    --min-replicas 1
```

Notice that the type of ingress is `internal` because the *weather-service* is not intended to be accessed directly from the internet, instead, it will be accessed by a gateway later too.

## Build a gateway

Build a gateway that uses [NGINX Reverse Proxy](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/) to route HTTP requests to internal services running in the same Azure Container Apps environment.

The source code is in the [gateway](./gateway/) directory. The *gateway* listens on port `8080` and routes requests to the *city-service* and *weather-service*.

Run the following commands to build a Docker image, push it to the Azure Container Registry, and deploy it to the Azure Container Apps.

```bash
# Build and push gateway image to ACR
cd $WORKING_DIR/gateway

docker build -t gateway .
docker tag gateway ${ACR_LOGIN_SERVER}/gateway
docker push ${ACR_LOGIN_SERVER}/gateway

# Deploy gateway
ACA_GATEWAY_NAME=gateway
az containerapp create \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $ACA_GATEWAY_NAME \
    --image ${ACR_LOGIN_SERVER}/gateway \
    --environment $ACA_ENV \
    --registry-server $ACR_LOGIN_SERVER \
    --registry-username $ACR_USER_NAME \
    --registry-password $ACR_PASSWORD \
    --target-port 8080 \
    --env-vars \
        CITY_SERVICE_URL=http://${ACA_CITY_SERVICE_NAME} \
	WEATHER_SERVICE_URL=http://${ACA_WEATHER_SERVICE_NAME} \
    --ingress 'external' \
    --min-replicas 1

GATEWAY_URL=https://$(az containerapp show \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $ACA_GATEWAY_NAME \
    --query properties.configuration.ingress.fqdn \
    --output tsv | tr -d '\r')
echo "Gateway URL: $GATEWAY_URL"
```

Notice that the type of ingress is `external` because the *gateway* is intended to be publicly accessible, it will be accessed by the weather app frontend later.

You can test the gateway by calling the `/CITY-SERVICE/cities` and `/WEATHER-SERVICE/weather/city` endpoints.

```bash
# You should see the list of cities returned by the city-service: [[{"name":"Paris, France"},{"name":"London, UK"}]]
echo $(curl $GATEWAY_URL/CITY-SERVICE/cities --silent)

# You should see the weather for London, UK returned by the weather-service: {"city":"London, UK","description":"Quite cloudy","icon":"weather-pouring"}
echo $(curl $GATEWAY_URL/WEATHER-SERVICE/weather/city?name=London%2C%20UK --silent)

# You should see the weather for Paris, France returned by the weather-service: {"city":"Paris, France","description":"Very cloudy!","icon":"weather-fog"}
echo $(curl $GATEWAY_URL/WEATHER-SERVICE/weather/city?name=Paris%2C%20France --silent)
```

Write down the gateway URL, you will use it in the weather app frontend later.

## Putting it all together, a complete microservice stack

Build a front-end microservice to access the *gateway* and display the weather for given cities.

The source code is in the [weather-app](./weather-app/) directory. The *weather-app* is a simple Vue.js web app that uses the *gateway* to call the *city-service* and *weather-service* and display the result.

```bash
# Build and push weather-app image to ACR
cd $WORKING_DIR/weather-app

docker build -t weather-app .
# docker run -it --rm -p 8080:8080 weather-app
docker tag weather-app ${ACR_LOGIN_SERVER}/weather-app
docker push ${ACR_LOGIN_SERVER}/weather-app

# Deploy weather-app to ACA
ACA_WEATHER_APP_NAME=weather-app
az containerapp create \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $ACA_WEATHER_APP_NAME \
    --image ${ACR_LOGIN_SERVER}/weather-app \
    --environment $ACA_ENV \
    --registry-server $ACR_LOGIN_SERVER \
    --registry-username $ACR_USER_NAME \
    --registry-password $ACR_PASSWORD \
    --target-port 8080 \
    --ingress 'external' \
    --min-replicas 1

WEATHER_APP_URL=https://$(az containerapp show \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $ACA_WEATHER_APP_NAME \
    --query properties.configuration.ingress.fqdn \
    --output tsv)
echo "Weather app URL: $WEATHER_APP_URL"
```

Open the weather app URL in a web browser, enter the gateway URL you wrote down before for **Gateway URL**, and select **Go**. You should see the weather for the cities.

## Clean up

Congratulations! You have successfully deployed a complete microservice stack to Azure Container Apps. 

Now you can clean up the resources to avoid incurring charges if they are not needed. Run the following command to delete the resource group and all resources created in this workshop.

```bash
az group delete --name $RESOURCE_GROUP_NAME --yes --no-wait
```
