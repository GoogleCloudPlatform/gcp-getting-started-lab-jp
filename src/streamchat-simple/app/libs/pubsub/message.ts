import { Message } from "@/app/types/message";
import { pubSubClient } from "./init";

export const postMessage = async (message: Message) => {
  const dataBuffer = Buffer.from(JSON.stringify(message));

  await pubSubClient
    .topic(process.env.PUBSUB_TOPIC as string)
    .publishMessage({ data: dataBuffer });
};
