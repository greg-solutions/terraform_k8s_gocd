#!/bin/bash
SERVICE_ACCOUNT_PATH=/var/run/secrets/kubernetes.io/serviceaccount
KUBE_TOKEN=$(<$${SERVICE_ACCOUNT_PATH}/token)
while true; do
  status_code=$(curl 'http://localhost:8153/go/api/v1/health' -o /dev/null -w "%%{http_code}")
  if [ $status_code == 200 ]; then
    break
  fi
  sleep 10
done
set -e
echo "checking if server has already been configured" >>/godata/logs/preconfigure.log
if [ -f /godata/logs/preconfigure_complete.log ]; then
  echo "Existing server configuration found in cruise-config.xml. Skipping preconfigure_server scripts." >>/godata/logs/preconfigure.log
  exit 0
fi
echo "No configuration found in cruise-config.xml. Using default preconfigure_server scripts to configure server" >>/godata/logs/preconfigure.log
echo "Trying to configure cluster profile." >>/godata/logs/preconfigure.log
(
  curl --fail -i 'http://localhost:8153/go/api/admin/elastic/cluster_profiles' \
  -H'Accept: application/vnd.go.cd+json' \
  -H 'Content-Type: application/json' \
  -X POST -d '{
        "id": "k8-cluster-profile",
        "plugin_id": "cd.go.contrib.elasticagent.kubernetes",
        "properties": [
              {
                "key": "go_server_url",
                "value": "http://${gocd_fullname}-server:${server_service_httpPort}/go"
            },
            {
                "key": "kubernetes_cluster_url",
                "value": "https://'$KUBERNETES_SERVICE_HOST':'$KUBERNETES_SERVICE_PORT_HTTPS'"
              },
              {
                "key": "namespace",
                "value": "${gocd_namespace}"
              },
              {
                "key": "security_token",
                "value": "'$KUBE_TOKEN'"
              }
          ]
      }' >>/godata/logs/preconfigure.log
)
echo "Trying to create an elastic profile now." >>/godata/logs/preconfigure.log
(
  curl --fail -i 'http://localhost:8153/go/api/elastic/profiles' \
  -H 'Accept: application/vnd.go.cd+json' \
  -H 'Content-Type: application/json' \
  -X POST -d '{
        "id": "demo-app",
        "cluster_profile_id": "k8-cluster-profile",
        "properties": [
          {
            "key": "Image",
            "value": "gocd/gocd-agent-docker-dind:v${AppVersion}"
          },
          {
            "key": "PodConfiguration",
            "value": "apiVersion: v1\nkind: Pod\nmetadata:\n  name: gocd-agent-{{ `{{ POD_POSTFIX }}` }}\n  labels:\n    app: web\nspec:\n  serviceAccountName: ${agentServiceAccountName}\n  containers:\n    - name: gocd-agent-container-{{ `{{ CONTAINER_POSTFIX }}` }}\n      image: gocd/gocd-agent-docker-dind:v${AppVersion}\n      securityContext:\n        privileged: true"
          },
          {
            "key": "PodSpecType",
            "value": "yaml"
          },
          {
            "key": "Privileged",
            "value": "true"
          }
        ]
      }' >>/godata/logs/preconfigure.log
)
echo "Trying to creating a hello world pipeline." >>/godata/logs/preconfigure.log
(
  curl --fail -i 'http://localhost:8153/go/api/admin/pipelines' \
  -H 'Accept: application/vnd.go.cd+json' \
  -H 'Content-Type: application/json' \
  -X POST -d '{ "group": "sample",
                    "pipeline": {
                      "label_template": "$${COUNT}",
                      "name": "getting_started_pipeline",
                      "materials": [
                        {
                          "type": "git",
                          "attributes": {
                            "url": "https://github.com/gocd-contrib/getting-started-repo",
                            "shallow_clone": true
                          }
                        }
                      ],
                      "stages": [
                        {
                          "name": "default_stage",
                          "jobs": [
                            {
                              "name": "default_job",
                              "elastic_profile_id": "demo-app",
                              "tasks": [
                                {
                                  "type": "exec",
                                  "attributes": {
                                    "command": "./build"
                                  }
                                }
                              ],
                              "tabs": [
                                {
                                  "name": "Sample",
                                  "path": "my-artifact.html"
                                }
                              ],
                              "artifacts": [
                                {
                                  "type": "build",
                                  "source": "my-artifact.html"
                                }
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  }' >>/godata/logs/preconfigure.log
)
echo "Done preconfiguring the GoCD server" >/godata/logs/preconfigure_complete.log