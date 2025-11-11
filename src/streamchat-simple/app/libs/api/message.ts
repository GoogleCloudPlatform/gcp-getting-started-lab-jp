import { MessagePostRequest } from "@/app/types/message";
import axios from "axios";

const MESSAGE_ENDPOINT = "/api/pubsub";

export const postMessageApi = async (
  request: MessagePostRequest,
  idToken: string,
  csrfToken: string
) => {
  try {
    await axios.post<MessagePostRequest>(MESSAGE_ENDPOINT, request, {
      headers: {
        Authorization: "Bearer " + idToken,
        "X-CSRF-Token": csrfToken,
      },
    });
  } catch (e) {
    console.error(e);
  }
};
