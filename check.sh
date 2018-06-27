#!/bin/bash

ZOO=zookeeper
KAFKA=kafka

docker-compose ps


#check for zookeeper
while [ $(docker-compose logs zookeeper | grep -i binding | wc -l) -lt 1 ]
do
    echo "Waiting for zookeeper to start";
done



# check for kafka
docker-compose logs kafka | grep -i started


#create topic in kafka

docker-compose exec kafka  \
kafka-topics --create --topic foo --partitions 1 --replication-factor 1 --if-not-exists --zookeeper $ZOO:2181


#check if it exists

docker-compose exec kafka  \
  kafka-topics --describe --topic foo --zookeeper $ZOO:2181

#produce messages

docker-compose exec kafka  \
  bash -c "seq 42 | kafka-console-producer --request-required-acks 1 --broker-list $KAFKA:9092 --topic foo && echo 'Produced 42 messages.'"


#consume messages

docker-compose exec kafka  \
  kafka-console-consumer --bootstrap-server $KAFKA:9092 --topic foo --from-beginning --max-messages 42

