import { pubSubClient } from "./init";

export const saveMessage = async (
  username: string,
  text: string,
  profilePicUrl: string
) => {
  const message = {
    name: username,
    text: text,
    profilePicUrl: profilePicUrl,
  };

  const dataBuffer = Buffer.from(JSON.stringify(message));

  await pubSubClient
    .topic(process.env.PUBSUB_TOPIC as string)
    .publishMessage({ data: dataBuffer });
};
