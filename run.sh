#!/bin/bash

docker network create confluent
docker run -d \
    --net=confluent \
    --name=zookeeper \
    -e ZOOKEEPER_CLIENT_PORT=2181 \
    confluentinc/cp-zookeeper:4.1.0