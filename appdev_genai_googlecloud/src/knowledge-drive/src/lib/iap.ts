import { OAuth2Client } from "google-auth-library";

type PublicKeys = Awaited<ReturnType<OAuth2Client["getIapPublicKeysAsync"]>>["pubkeys"];

const IAP_ISSUER = "https://cloud.google.com/iap";
const KEY_CACHE_TTL_MS = 60 * 60 * 1000; // 1 hour

const oauth2Client = new OAuth2Client();

let cachedPubkeys: PublicKeys | null = null;
let cachedPubkeysExpiresAt = 0;

const getIapPublicKeysCached = async (
  forceRefresh = false,
): Promise<PublicKeys> => {
  const now = Date.now();
  if (!forceRefresh && cachedPubkeys && now < cachedPubkeysExpiresAt) {
    return cachedPubkeys;
  }
  const response = await oauth2Client.getIapPublicKeys();
  cachedPubkeys = response.pubkeys;
  cachedPubkeysExpiresAt = now + KEY_CACHE_TTL_MS;
  return cachedPubkeys;
};

export const verifyIapJwt = async (
  iapJwt: string,
  client: Pick<
    OAuth2Client,
    "getIapPublicKeys" | "verifySignedJwtWithCertsAsync"
  > = oauth2Client,
): Promise<string> => {
  const requiredAudience = process.env.IAP_AUDIENCE || undefined;

  const verifyWithKeys = async (pubkeys: PublicKeys) => {
    return client.verifySignedJwtWithCertsAsync(
      iapJwt,
      pubkeys,
      requiredAudience,
      [IAP_ISSUER],
    );
  };

  let ticket;
  if (client === oauth2Client) {
    const pubkeys = await getIapPublicKeysCached(false);
    try {
      ticket = await verifyWithKeys(pubkeys);
    } catch (err) {
      // Retry once with fresh public keys in case IAP rotated signing keys.
      if (
        err instanceof Error &&
        err.message.includes("No pem found for envelope")
      ) {
        const refreshedPubkeys = await getIapPublicKeysCached(true);
        ticket = await verifyWithKeys(refreshedPubkeys);
      } else {
        throw err;
      }
    }
  } else {
    const { pubkeys } = await client.getIapPublicKeys();
    ticket = await verifyWithKeys(pubkeys);
  }

  const payload = ticket.getPayload();
  if (
    !payload ||
    typeof payload.aud !== "string" ||
    !payload.aud.startsWith("/projects/")
  ) {
    throw new Error("Invalid IAP JWT audience");
  }
  if (!payload.email) {
    throw new Error("IAP JWT payload does not contain an email claim");
  }
  return payload.email;
};
