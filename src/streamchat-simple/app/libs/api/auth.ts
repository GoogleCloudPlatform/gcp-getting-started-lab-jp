import axios from "axios";

export const signUpApi = async (request: SignUpRequest, csrfToken: string) => {
  await axios.post<SignUpRequest>("/api/register", request, {
    headers: {
      "X-CSRF-Token": csrfToken,
    },
  });
};
