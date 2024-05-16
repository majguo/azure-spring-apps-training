# Java on Azure Container Apps workshop

You will find here a full workshop that deploys and runs several microservices on Azure Container Apps, including:

* City service: Native executable of a Reactive Quarkus microservice using Azure Database for PostgreSQL Flexible Server
* Weather service: Native executable of a Micronault microservice using Azure Database For MySQL Flexible server
* Gateway: Nginx as a reverse proxy, [calling the above services in the same ACA environment using the container app name](https://learn.microsoft.com/azure/container-apps/connect-apps?tabs=bash)
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

Create a resource group and deploy an Azure Database for PostgreSQL Flexible Server and an Azure Database for MySQL Flexible Server in it.

```bash
let "randomIdentifier=$RANDOM*$RANDOM"
LOCATION=eastus
RESOURCE_GROUP_NAME=aca-lab-rg-$randomIdentifier
POSTGRESQL_SERVER_NAME=postgres$randomIdentifier
MYSQL_SERVER_NAME=mysql$randomIdentifier
DB_NAME=demodb
DB_ADMIN=demouser
DB_ADMIN_PWD='super$ecr3t'$RANDOM$RANDOM

az group create \
    --name $RESOURCE_GROUP_NAME \
    --location $LOCATION

az postgres flexible-server create \
    --name $POSTGRESQL_SERVER_NAME \
    --resource-group $RESOURCE_GROUP_NAME \
    --admin-user $DB_ADMIN \
    --admin-password $DB_ADMIN_PWD \
    --database-name $DB_NAME \
    --public-access 0.0.0.0 \
    --yes

az mysql flexible-server create \
    --name $MYSQL_SERVER_NAME \
    --resource-group $RESOURCE_GROUP_NAME \
    --admin-user $DB_ADMIN \
    --admin-password $DB_ADMIN_PWD \
    --database-name $DB_NAME \
    --public-access 0.0.0.0 \
    --yes
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

## Build a Reactive Quarkus microservice using Azure Database for PostgreSQL Flexible Server

Build a reactive [Quarkus](https://quarkus.io/) microservice that references guides [GETTING STARTED WITH REACTIVE](https://quarkus.io/guides/getting-started-reactive) and [SIMPLIFIED HIBERNATE REACTIVE WITH PANACHE](https://quarkus.io/guides/hibernate-reactive-panache). The service is bound to an [Azure Database for PostgreSQL Flexible Server](https://learn.microsoft.com/azure/postgresql/flexible-server/overview), and it uses [Liquibase](https://quarkus.io/guides/liquibase) to manage database schema migrations including initial data population.

The source code is in the [city-service](./city-service/) directory. The *city-service* exposes a REST API to retrieve cities from a PostgreSQL database using reractive programming.

Run the following commands to build a native executable, build a Docker image, push it to the Azure Container Registry, and deploy it to the Azure Container Apps.

```bash
# Build and push city-service image to ACR
cd $WORKING_DIR/city-service
mvn clean package -DskipTests -Dnative -Dquarkus.native.container-build

docker buildx build --platform linux/amd64 -f src/main/docker/Dockerfile.native -t city-service .
docker tag city-service ${ACR_LOGIN_SERVER}/city-service
docker push ${ACR_LOGIN_SERVER}/city-service

# Deploy city service to ACA
ACA_CITY_SERVICE_NAME=city-service
export QUARKUS_DATASOURCE_JDBC_URL=jdbc:postgresql://${POSTGRESQL_SERVER_NAME}.postgres.database.azure.com:5432/${DB_NAME}?sslmode=require
export QUARKUS_DATASOURCE_REACTIVE_URL=postgresql://${POSTGRESQL_SERVER_NAME}.postgres.database.azure.com:5432/${DB_NAME}?sslmode=require
export QUARKUS_DATASOURCE_USERNAME=${DB_ADMIN}
export QUARKUS_DATASOURCE_PASSWORD=${DB_ADMIN_PWD}

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
        QUARKUS_DATASOURCE_JDBC_URL=${QUARKUS_DATASOURCE_JDBC_URL} \
        QUARKUS_DATASOURCE_REACTIVE_URL=${QUARKUS_DATASOURCE_REACTIVE_URL} \
        QUARKUS_DATASOURCE_USERNAME=${QUARKUS_DATASOURCE_USERNAME} \
        QUARKUS_DATASOURCE_PASSWORD=${QUARKUS_DATASOURCE_PASSWORD} \
    --ingress 'internal' \
    --min-replicas 1
```

Notice that the type of ingress is `internal` because the *city-service* is not intended to be accessed directly from the internet, instead, it will be accessed by a gateway later.

## Build a Micronault microservice using Azure Database For MySQL Flexible server

Build a [Micronault](https://micronaut.io/) microserver that references guide [ACCESS A DATABASE WITH MICRONAUT DATA JDBC](https://guides.micronaut.io/latest/micronaut-data-jdbc-repository-maven-java.html). The service is bound to an [Azure Database For MySQL Flexible server](https://learn.microsoft.com/azure/mysql/flexible-server/overview), and it uses [Flyway](https://guides.micronaut.io/latest/micronaut-flyway-maven-java.html) to manage database schema migrations including initial data population.

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
DATASOURCES_DEFAULT_URL=jdbc:mysql://$MYSQL_SERVER_NAME.mysql.database.azure.com:3306/$DB_NAME
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

docker buildx build --platform linux/amd64 -t gateway .
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

### Troubleshooting

If you don't see the expected results, check `Monitoring > Log stream` in the Azure Portal to see the logs of the gateway. If you see the similar error message below, it means that the script `entrypoint.sh` under directory `gateway/nginx` has windows-style line endings.

```
/usr/bin/env: 'sh\r': No such file or directory
/usr/bin/env: use -[v]S to pass options in shebang lines
```

You can fix it by running `dos2unix gateway/nginx/entrypoint.sh` (see [this](https://stackoverflow.com/questions/18172405/getting-error-usr-bin-env-sh-no-such-file-or-directory-when-running-command-p)) or VS Code to open the file, click on the `CRLF` button in the status bar, and select `LF` to change the line endings to Unix-style.
Then run the above commands to build and deploy the gateway again.

## Putting it all together, a complete microservice stack

Build a front-end microservice to access the *gateway* and display the weather for given cities.

The source code is in the [weather-app](./weather-app/) directory. The *weather-app* is a simple Vue.js web app that uses the *gateway* to call the *city-service* and *weather-service* and display the result.

```bash
# Build and push weather-app image to ACR
cd $WORKING_DIR/weather-app

docker buildx build --platform linux/amd64 -t weather-app .
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
az group delete \
    --name $RESOURCE_GROUP_NAME \
    --yes --no-wait
```

## More resources

* [az postgres flexible-server create](https://learn.microsoft.com/cli/azure/postgres/flexible-server?view=azure-cli-latest#az-postgres-flexible-server-create)
* [az mysql flexible-server create](https://learn.microsoft.com/cli/azure/mysql/flexible-server?view=azure-cli-latest#az-mysql-flexible-server-create)
* [CONFIGURE DATA SOURCES IN QUARKUS](https://quarkus.io/guides/datasource)
* [MUTINY - ASYNC FOR BARE MORTAL](https://quarkus.io/guides/mutiny-primer)
* [What makes Mutiny different?](https://smallrye.io/smallrye-mutiny/latest/reference/what-makes-mutiny-different/)
