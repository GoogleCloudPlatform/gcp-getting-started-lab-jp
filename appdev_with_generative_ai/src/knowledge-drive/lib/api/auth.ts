export const signUpApi = async (request: SignUpRequest, csrfToken: string) => {
  await fetch("/api/register", {
    method: "POST",
    headers: {
      "X-CSRF-Token": csrfToken,
    },
    body: JSON.stringify(request),
  });
};
