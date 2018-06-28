#!/bin/bash

ZOO=zookeeper
KAFKA=kafka
TOPIC_1=foo
TOPIC_2=bar
TOPIC_3=c3-test
DELIM="-------------------------------------------------------------------------------"

sh run.sh

docker-compose ps
echo $DELIM
echo "ZOOKEEPER"
echo "check for zookeeper"
while [ $(docker-compose logs zookeeper | grep -i binding | wc -l) -lt 1 ]
do
    echo "Waiting for zookeeper to start";
done
echo $DELIM

echo "KAFKA"
echo "check for kafka"
docker-compose logs kafka | grep -i started
echo $DELIM

echo "create topic in kafka"

docker-compose exec kafka  \
kafka-topics --create --topic $TOPIC_1 --partitions 1 --replication-factor 1 --if-not-exists --zookeeper $ZOO:2181
echo $DELIM

echo "check if topic exists"

docker-compose exec kafka  \
  kafka-topics --describe --topic $TOPIC_1 --zookeeper $ZOO:2181
echo $DELIM

echo "produce messages"

docker-compose exec kafka  \
  bash -c "seq 42 | kafka-console-producer --request-required-acks 1 --broker-list $KAFKA:9092 --topic $TOPIC_1 && echo 'Produced 42 messages.'"
echo $DELIM

echo "consume messages"

docker-compose exec kafka  \
  kafka-console-consumer --bootstrap-server $KAFKA:9092 --topic $TOPIC_1 --from-beginning --max-messages 42
echo $DELIM
echo "SCHEMA-REGISTRY"
echo "schema-registry check"

docker-compose exec schema-registry bash -c "printf '{\"f1\": \"value1\"}\n{\"f1\": \"value2\"}\n{\"f1\": \"value3\"}\n' | /usr/bin/kafka-avro-console-producer \
  --broker-list kafka:9092 --topic bar \
  --property schema.registry.url=http://schema-registry:8081 \
  --property value.schema='{\"type\":\"record\",\"name\":\"myrecord\",\"fields\":[{\"name\":\"f1\",\"type\":\"string\"}]}'"
echo $DELIM
echo "KAFKA-REST PROXY"
echo "kafka rest proxy sends message"

docker-compose exec kafka-rest curl -X POST -H "Content-Type: application/vnd.kafka.v1+json" \
  --data '{"name": "my_consumer_instance", "format": "avro", "auto.offset.reset": "smallest"}' \
  http://kafka-rest:8082/consumers/my_avro_consumer
echo $DELIM

echo "kafka rest proxy retrieve message"

docker-compose exec kafka-rest curl -X GET -H "Accept: application/vnd.kafka.avro.v1+json" \
  http://kafka-rest:8082/consumers/my_avro_consumer/instances/my_consumer_instance/topics/$TOPIC_2
echo $DELIM

echo "MONITORING"
echo "create test topic for monitoring"
docker-compose exec kafka \
kafka-topics --create --topic c3-test --partitions 1 --replication-factor 1 --if-not-exists --zookeeper $ZOO:2181
echo $DELIM

echo "produce messages with kafka-connect"
docker-compose exec kafka-connect \
bash -c 'seq 10000 | kafka-console-producer --request-required-acks 1 --broker-list kafka:9092 --topic c3-test --producer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor --producer-property acks=1 && echo "Produced 10000 messages."'
sleep 1;
echo $DELIM

echo "read messages"
docker-compose exec kafka-connect \
bash -c 'kafka-console-consumer --consumer-property group.id=qs-consumer --consumer-property interceptor.classes=io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor --bootstrap-server kafka:9092 --topic c3-test --offset '0' --partition 0 --max-messages=10000'
sleep 1;
echo $DELIM

echo "KAFKA-CONNECT"
K_OFF=quickstart-offsets
K_DATA=quickstart-data

echo "create topic $K_OFF"
docker-compose exec kafka \
kafka-topics --create --topic $K_OFF --partitions 1 --replication-factor 1 --if-not-exists --zookeeper $ZOO:2181
echo $DELIM

echo "create topic $K_DATA"
docker-compose exec kafka \
  kafka-topics --create --topic $K_DATA --partitions 1 --replication-factor 1 --if-not-exists --zookeeper $ZOO:2181
echo $DELIM

echo "check topics are created"
docker-compose exec kafka \
   kafka-topics --describe --zookeeper $ZOO:2181
echo $DELIM

echo "creating input file"

docker-compose exec kafka-connect mkdir -p /tmp/quickstart/file
docker-compose exec kafka-connect bash -c 'seq 1000 > /tmp/quickstart/file/input.txt'
echo $DELIM

echo "creating file source connector"
docker-compose exec kafka-connect curl -s -X POST \
  -H "Content-Type: application/json" \
  --data '{"name": "quickstart-file-source", "config": {"connector.class":"org.apache.kafka.connect.file.FileStreamSourceConnector", "tasks.max":"1", "topic":"quickstart-data", "file": "/tmp/quickstart/file/input.txt"}}' \
  http://kafka-connect:8083/connectors
echo $DELIM

echo "check kafka connect file source status"
docker-compose exec kafka-connect curl -s -X GET http://kafka-connect:8083/connectors/quickstart-file-source/status
echo $DELIM

echo "read 10 messages from file source"
docker-compose exec kafka \
kafka-console-consumer --bootstrap-server $KAFKA:9092 --topic $K_DATA --from-beginning --max-messages 10
echo $DELIM

echo "write to file sink"
docker-compose exec kafka-connect curl -X POST -H "Content-Type: application/json" \
    --data '{"name": "quickstart-file-sink", "config": {"connector.class":"org.apache.kafka.connect.file.FileStreamSinkConnector", "tasks.max":"1", "topics":"quickstart-data", "file": "/tmp/quickstart/file/output.txt"}}' \
    http://kafka-connect:8083/connectors
echo $DELIM

echo "check state of file sink"
docker-compose exec kafka-connect curl -s -X GET http://kafka-connect:8083/connectors/quickstart-file-sink/status
echo $DELIM

sleep 10s;

echo "check it wrote to file system"
docker-compose exec kafka-connect cat /tmp/quickstart/file/output.txt
echo $DELIM

docker-compose down
