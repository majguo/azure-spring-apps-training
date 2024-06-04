# Please make sure you have navigated to the location of this script, then run the following command to deploy all infrastructure and services:
#   ./all-in-one.sh
WORKING_DIR=$(pwd)

# Define variables
let "randomIdentifier=$RANDOM*$RANDOM"
LOCATION=eastus
RESOURCE_GROUP_NAME=aca-lab-rg-$randomIdentifier
POSTGRESQL_SERVER_NAME=postgres$randomIdentifier
MYSQL_SERVER_NAME=mysql$randomIdentifier
DB_NAME=demodb
DB_ADMIN=demouser
DB_ADMIN_PWD='super$ecr3t'$RANDOM$RANDOM

# Create a resource group
az group create \
    --name $RESOURCE_GROUP_NAME \
    --location $LOCATION

# Create a PostgreSQL and MySQL server
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

# Create an Azure Container Registry and retrieve its connection information
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

# Create an Azure Container App environment
ACA_ENV=acaenv$randomIdentifier
az containerapp env create \
    --resource-group $RESOURCE_GROUP_NAME \
    --location $LOCATION \
    --name $ACA_ENV

# Retrieve the Log Analytics workspace and create an Application Insights instance
logAnalyticsWorkspace=$(az monitor log-analytics workspace list \
    -g $RESOURCE_GROUP_NAME \
    --query "[0].name" -o tsv | tr -d '\r\n')

APP_INSIGHTS=appinsights$randomIdentifier
az monitor app-insights component create \
    --app $APP_INSIGHTS \
    -g $RESOURCE_GROUP_NAME \
    -l $LOCATION \
    --workspace $logAnalyticsWorkspace

# Retrieve Application Insights connection string and enable OpenTelemetry for logs and traces in the ACA environment
appInsightsConn=$(az monitor app-insights component show \
    --app $APP_INSIGHTS \
    -g $RESOURCE_GROUP_NAME \
    --query 'connectionString' -o tsv)

az containerapp env telemetry app-insights set \
  --name $ACA_ENV \
  --resource-group $RESOURCE_GROUP_NAME \
  --connection-string $appInsightsConn \
  --enable-open-telemetry-logs true \
  --enable-open-telemetry-traces true

# Build and push city-service image to ACR
cd $WORKING_DIR/city-service
mvn clean package -DskipTests -Dnative -Dquarkus.native.container-build

docker buildx build --platform linux/amd64 -f src/main/docker/Dockerfile.native -t city-service .
docker tag city-service ${ACR_LOGIN_SERVER}/city-service
cd $WORKING_DIR
docker login $ACR_LOGIN_SERVER \
    -u $ACR_USER_NAME \
    -p $ACR_PASSWORD
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

# Build and push weather-service image to ACR
cd $WORKING_DIR/weather-service
mvn clean package -DskipTests=true

docker buildx build --platform linux/amd64 -f Dockerfile-otel-agent -t weather-service .
docker tag weather-service ${ACR_LOGIN_SERVER}/weather-service
cd $WORKING_DIR
docker login $ACR_LOGIN_SERVER \
    -u $ACR_USER_NAME \
    -p $ACR_PASSWORD
docker push ${ACR_LOGIN_SERVER}/weather-service

# Deploy weather service to ACA
ACA_WEATHER_SERVICE_NAME=weather-service
export DATASOURCES_DEFAULT_URL=jdbc:mysql://$MYSQL_SERVER_NAME.mysql.database.azure.com:3306/$DB_NAME
export DATASOURCES_DEFAULT_USERNAME=$DB_ADMIN
export DATASOURCES_DEFAULT_PASSWORD=$DB_ADMIN_PWD
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

# Build and push gateway image to ACR
cd $WORKING_DIR/gateway

docker buildx build --platform linux/amd64 -t gateway .
docker tag gateway ${ACR_LOGIN_SERVER}/gateway
cd $WORKING_DIR
docker login $ACR_LOGIN_SERVER \
    -u $ACR_USER_NAME \
    -p $ACR_PASSWORD
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

# You should see the list of cities returned by the city-service: [[{"name":"Paris, France"},{"name":"London, UK"}]]
echo $(curl $GATEWAY_URL/CITY-SERVICE/cities --silent)

# You should see the weather for London, UK returned by the weather-service: {"city":"London, UK","description":"Quite cloudy","icon":"weather-pouring"}
echo $(curl $GATEWAY_URL/WEATHER-SERVICE/weather/city?name=London%2C%20UK --silent)

# You should see the weather for Paris, France returned by the weather-service: {"city":"Paris, France","description":"Very cloudy!","icon":"weather-fog"}
echo $(curl $GATEWAY_URL/WEATHER-SERVICE/weather/city?name=Paris%2C%20France --silent)

# Build and push weather-app image to ACR
cd $WORKING_DIR/weather-app

docker buildx build --platform linux/amd64 -t weather-app .
docker tag weather-app ${ACR_LOGIN_SERVER}/weather-app
cd $WORKING_DIR
docker login $ACR_LOGIN_SERVER \
    -u $ACR_USER_NAME \
    -p $ACR_PASSWORD
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
