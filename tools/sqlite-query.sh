#!/bin/env bash


DIR="$(dirname "$(realpath "$0")")"

DB_FILE="$DIR/../build/store.sqlite3"


CONTENT_TOPIC="/waku/1/0x35cd47c5/rfc26"
# CONTENT_TOPIC="/toy-chat/2/huilong/proto"
CONTENT_TOPIC_HEX=$(printf "$CONTENT_TOPIC" | xxd -p -c 256)
CONTENT_TOPIC_QUERY="x'$CONTENT_TOPIC_HEX'"

PUBSUB_TOPIC="/waku/2/default-waku/proto"
PUBSUB_TOPIC_HEX=$(printf "$PUBSUB_TOPIC" | xxd -p -c 256)
PUBSUB_TOPIC_QUERY="x'$PUBSUB_TOPIC_HEX'"

START_TIME=1661155200500000000
END_TIME=1662124449000000000


COUNT_MESSAGES_QUERY="SELECT count(*) FROM Message"
TOTAL_MESSAGES="$(sqlite3 --readonly $DB_FILE "$COUNT_MESSAGES_QUERY" ".exit")"

echo ""
echo "DB file: $DB_FILE"
echo "Messages count: ${TOTAL_MESSAGES}"
echo ""

EQP_CMD=".eqp full"
TRACE_CMD=".trace stdout --profile"
TIMER_CMD=".timer on"

QUERY="SELECT receiverTimestamp, contentTopic, pubsubTopic, version, senderTimestamp FROM Message WHERE (contentTopic = ($CONTENT_TOPIC_QUERY)) AND pubsubTopic = ($PUBSUB_TOPIC_QUERY) AND (senderTimestamp >= ($START_TIME) AND senderTimestamp <= ($END_TIME)) ORDER BY senderTimestamp DESC, id DESC, pubsubTopic DESC, receiverTimestamp DESC LIMIT 50;"
COUNT_QUERY="SELECT count(*) FROM Message WHERE (contentTopic = ($CONTENT_TOPIC_QUERY)) AND pubsubTopic = ($PUBSUB_TOPIC_QUERY) AND (senderTimestamp >= ($START_TIME) AND senderTimestamp <= ($END_TIME)) ORDER BY senderTimestamp DESC, id DESC, pubsubTopic DESC, receiverTimestamp DESC LIMIT 50;"

echo ""
echo "SQL query:"
echo ""
echo $QUERY
echo ""

sqlite3 --readonly $DB_FILE ".eqp full" "$TRACE_CMD" "$QUERY" ".exit"
# sqlite3 --readonly $DB_FILE ".trace stdout --profile" "$QUERY" ".exit"