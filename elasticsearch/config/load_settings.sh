#!/bin/bash
# Wazuh App Copyright (C) 2019 Wazuh Inc. (License GPLv2)

set -e

el_url=${ELASTICSEARCH_URL}

if [ "x${WAZUH_API_URL}" = "x" ]; then
  wazuh_url="https://wazuh"
else
  wazuh_url="${WAZUH_API_URL}"
fi


if [ ${SETUP_PASSWORDS} != "no" ]; then
  auth="-uelastic:${BOOTSTRAP_PASS}"
elif [ ${ENABLED_XPACK} != "true" || "x${ELASTICSEARCH_USERNAME}" = "x" || "x${ELASTICSEARCH_PASSWORD}" = "x" ]; then
  auth=""
else
  auth="--user ${ELASTICSEARCH_USERNAME}:${ELASTICSEARCH_PASSWORD}"
fi

until curl ${auth} -XGET $el_url; do
  >&2 echo "Elastic is unavailable - sleeping"
  sleep 5
done

>&2 echo "Elastic is up - executing command"

if [ $ENABLE_CONFIGURE_S3 ]; then
  #Wait for Elasticsearch to be ready to create the repository
  sleep 10
  IP_PORT="${ELASTICSEARCH_IP}:${ELASTICSEARCH_PORT}"

  if [ "x$S3_PATH" != "x" ]; then 

    if [ "x$S3_ELASTIC_MAJOR" != "x" ]; then 
      ./config/configure_s3.sh $IP_PORT $S3_BUCKET_NAME $S3_PATH $S3_REPOSITORY_NAME $S3_ELASTIC_MAJOR 

    else
      ./config/configure_s3.sh $IP_PORT $S3_BUCKET_NAME $S3_PATH $S3_REPOSITORY_NAME 

    fi

  fi

fi

#Insert default templates

sed -i 's|    "index.refresh_interval": "5s"|    "index.refresh_interval": "5s",    "number_of_shards" :   '"${ALERTS_SHARDS}"',    "number_of_replicas" : '"${ALERTS_REPLICAS}"'|' /usr/share/elasticsearch/config/wazuh-template.json

cat /usr/share/elasticsearch/config/wazuh-template.json | curl -XPUT "$el_url/_template/wazuh" ${auth} -H 'Content-Type: application/json' -d @-
sleep 5


API_PASS_Q=`echo "$API_PASS" | tr -d '"'`
API_USER_Q=`echo "$API_USER" | tr -d '"'`
API_PASSWORD=`echo -n $API_PASS_Q | base64`

echo "Setting API credentials into Wazuh APP"
CONFIG_CODE=$(curl -s -o /dev/null -w "%{http_code}" -XGET $el_url/.wazuh/wazuh-configuration/1513629884013 ${auth})
if [ "x$CONFIG_CODE" = "x404" ]; then
  curl -s -XPOST $el_url/.wazuh/wazuh-configuration/1513629884013 ${auth} -H 'Content-Type: application/json' -d'
  {
    "api_user": "'"$API_USER_Q"'",
    "api_password": "'"$API_PASSWORD"'",
    "url": "'"$wazuh_url"'",
    "api_port": "55000",
    "insecure": "true",
    "component": "API",
    "cluster_info": {
      "manager": "wazuh-manager",
      "cluster": "Disabled",
      "status": "disabled"
    },
    "extensions": {
      "oscap": true,
      "audit": true,
      "pci": true,
      "aws": true,
      "virustotal": true,
      "gdpr": true,
      "ciscat": true
    }
  }
  ' > /dev/null
else
  echo "Wazuh APP already configured"
fi
sleep 5

curl -XPUT "$el_url/_cluster/settings" ${auth} -H 'Content-Type: application/json' -d'
{
  "persistent": {
    "xpack.monitoring.collection.enabled": true
  }
}
'

# Set cluster delayed timeout when node falls
curl -X PUT "$el_url/_all/_settings" -H 'Content-Type: application/json' -d'
{
  "settings": {
    "index.unassigned.node_left.delayed_timeout": "'"$CLUSTER_DELAYED_TIMEOUT"'"
  }
}
'

if [[ $SETUP_PASSWORDS == "yes" ]]; then

  # curl -uelastic:${BOOTSTRAP_PASS} -XPUT -H 'Content-Type: application/json' 'http://localhost:9200/_xpack/security/user/elastic/_password ' -d '{ "password":"'$ELASTIC_PASS'" }'
  # curl -u elastic:${ELASTIC_PASS} -XPUT -H 'Content-Type: application/json' 'http://localhost:9200/_xpack/security/user/kibana/_password ' -d '{ "password":"'$KIBANA_PASS'" }'
  # curl -u elastic:${ELASTIC_PASS} -XPUT -H 'Content-Type: application/json' 'http://localhost:9200/_xpack/security/user/apm_system/_password ' -d '{ "password":"'$APM_SYSTEM_PASS'" }'
  # curl -u elastic:${ELASTIC_PASS} -XPUT -H 'Content-Type: application/json' 'http://localhost:9200/_xpack/security/user/beats_system/_password ' -d '{ "password":"'$BEATS_SYSTEM_PASS'" }'
  # curl -u elastic:${ELASTIC_PASS} -XPUT -H 'Content-Type: application/json' 'http://localhost:9200/_xpack/security/user/logstash_system/_password ' -d '{ "password":"'$LOGSTASH_PASS'" }'
  # curl -u elastic:${ELASTIC_PASS} -XPUT -H 'Content-Type: application/json' 'http://localhost:9200/_xpack/security/user/remote_monitoring_user/_password ' -d '{ "password":"'$REMOTE_USER_PASS'" }'

fi
echo "Elasticsearch is ready."
