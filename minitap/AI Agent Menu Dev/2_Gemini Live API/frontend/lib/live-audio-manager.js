export class LiveAudioInputManager {
    constructor() {
        this.audioContext;
        this.processor = false;
        this.pcmData = [];
        this.interval = null;
        this.stream = null;
        this.onNewAudioRecordingChunk = (audioData) => {};
    }

    async connectMicrophone() {
        if (this.stream) return;
        console.log("connectMicrophone");
        this.audioContext = new AudioContext({
            sampleRate: 16000,
        });
        const constraints = {
            audio: {
                channelCount: 1,
                sampleRate: 16000,
            },
        };
        this.stream = await navigator.mediaDevices.getUserMedia(constraints);
        const source = this.audioContext.createMediaStreamSource(this.stream);
        this.processor = this.audioContext.createScriptProcessor(4096, 1, 1);

        // store audio input in this.pcmData.
        this.processor.onaudioprocess = (e) => {
            const inputData = e.inputBuffer.getChannelData(0);
            // Convert float32 to int16
            const pcm16 = new Int16Array(inputData.length);
            for (let i = 0; i < inputData.length; i++) {
                pcm16[i] = inputData[i] * 0x7fff;
            }
            this.pcmData.push(...pcm16);
        };

        source.connect(this.processor);
        this.processor.connect(this.audioContext.destination);

        // process audio input every second.
        this.interval = setInterval(this.recordChunk.bind(this), 1000);
    }

    recordChunk() {
        const buffer = new ArrayBuffer(this.pcmData.length * 2);
        const view = new DataView(buffer);
        this.pcmData.forEach((value, index) => {
            view.setInt16(index * 2, value, true);
        });
        const base64 = btoa(
            String.fromCharCode.apply(null, new Uint8Array(buffer)),
        );
        this.onNewAudioRecordingChunk(base64); // callback to handle audio input.
        this.pcmData = [];
    }

    disconnectMicrophone() {
        clearInterval(this.interval);
        if (this.stream) {
            this.stream.getTracks().forEach(track => {track.stop()});
        }
        if (this.processor) {
            this.processor.disconnect();
        }
        if (this.audioContext && this.audioContext.state != 'closed') {
            this.audioContext.close();
        }
        this.stream = null;
    }
}


export class LiveAudioOutputManager {
    constructor() {
        this.audioInputContext;
        this.workletNode;
        this.initialized = false;
        this.initializeAudioContext();
    }

    async playAudioChunk(base64AudioChunk) {
        try {
            if (!this.initialized) {
                await this.initializeAudioContext();
            }

            if (this.audioInputContext.state == "suspended") {
                await this.audioInputContext.resume();
            }

            const arrayBuffer =
                LiveAudioOutputManager.base64ToArrayBuffer(base64AudioChunk);
            const float32Data =
                LiveAudioOutputManager.convertPCM16LEToFloat32(arrayBuffer);

            this.workletNode.port.postMessage(float32Data);
        } catch (error) {
            console.error("Error processing audio chunk:", error);
        }
    }

    async initializeAudioContext() {
        if (this.initialized) return;
        console.log("initialize audio context.");
        this.audioInputContext = new (window.AudioContext ||
            window.webkitAudioContext)({ sampleRate: 24000 });
        await this.audioInputContext.audioWorklet.addModule("/pcm-processor.js");
        this.workletNode = new AudioWorkletNode(
            this.audioInputContext,
            "pcm-processor",
        );
        this.workletNode.connect(this.audioInputContext.destination);

        this.initialized = true;
    }

    static base64ToArrayBuffer(base64) {
        const binaryString = window.atob(base64);
        const bytes = new Uint8Array(binaryString.length);
        for (let i = 0; i < binaryString.length; i++) {
            bytes[i] = binaryString.charCodeAt(i);
        }
        return bytes.buffer;
    }

    static convertPCM16LEToFloat32(pcmData) {
        const inputArray = new Int16Array(pcmData);
        const float32Array = new Float32Array(inputArray.length);
        for (let i = 0; i < inputArray.length; i++) {
            float32Array[i] = inputArray[i] / 32768;
        }
        return float32Array;
    }
}
