import boto3
import json
from flask import Flask, request, jsonify

app = Flask(__name__)
sqs = boto3.client("sqs")
sns = boto3.client("sns")
queue_url = "your-sqs-queue-url"
sns_topic_arn = "your-sns-topic-arn"

@app.route("/orders", methods=["POST"])
def create_order():
    data = request.get_json()
    response = sqs.send_message(
        QueueUrl=queue_url,
        MessageBody=json.dumps(data)
    )
    sns.publish(
        TopicArn=sns_topic_arn,
        Message=json.dumps({"default": json.dumps(data)}),
        MessageStructure="json"
    )
    return jsonify({"message": "Order created!", "order_id": response["MessageId"]}), 201

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
