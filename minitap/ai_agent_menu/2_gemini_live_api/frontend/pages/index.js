import Head from "next/head";
import VoiceClient from "components/VoiceClient";

export default function Index() {
  const element = (
    <>
      <Head>
        <title>Starlight Cafe - Live API Demo</title>
        <link rel="icon" href="/favicon.ico" />
      </Head>
      <VoiceClient />
    </>
  );

  return element;
}
