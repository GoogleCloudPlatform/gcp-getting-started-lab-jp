import datetime
import time
from google import auth
from google.cloud import pubsub_v1


def main():
    _, project_id = auth.default()
    subscription_id = "keda-echo-read"

    subscriber = pubsub_v1.SubscriberClient()
    subscription_path = subscriber.subscription_path(project_id, subscription_id)

    def callback(message):
        print(f"[{datetime.datetime.now()}] Received: {message.data.decode()}")
        time.sleep(3)
        message.ack()
        print(f"[{datetime.datetime.now()}] Acked: {message.message_id}")

    streaming_pull_future = subscriber.subscribe(subscription_path, callback=callback)
    print(f"Pulling messages from {subscription_path}...")

    with subscriber:
        try:
            streaming_pull_future.result()
        except Exception as e:
            print(e)


if __name__ == "__main__":
    main()
