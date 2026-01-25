# Restaurant Agent

An ADK (Agent Development Kit) demo that finds restaurants and extracts menus using Google Maps and Vertex AI.

## Quick Start

### 1. Setup Environment

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2. Configure Environment Variables

```bash
cat <<EOF > .env
GOOGLE_GENAI_USE_VERTEXAI=1
GOOGLE_CLOUD_PROJECT="YOUR_PROJECT_ID"
GOOGLE_CLOUD_LOCATION="us-central1"
AGENT_ENGINE_ID="YOUR_AGENT_ENGINE_ID"
GOOGLE_MAPS_API_KEY="YOUR_GOOGLE_MAPS_API_KEY"
EOF
```

### 3. Setup Agent Engine (First Time Only)

```bash
python deploy_agent_engine.py
```

This creates the Agent Engine in Vertex AI for session and memory management.

### 4. Run the Web Server

```bash
python main.py
```

Open http://localhost:8080 in your browser.

---

## Understanding Session State vs Memory Bank

### The Problem: Agents That Forget

Without memory, every conversation starts fresh. The agent has no context about who you are, what you've told it before, or what matters to you.

| Scenario | Without Memory | With Memory |
|----------|----------------|-------------|
| "Find me dinner" | Generic restaurant list | "Since you're vegetarian now and Sam loves Italian, here are options that work for both of you" |
| "Restaurant for Friday" | "What's the occasion?" | "Is this for your anniversary with Sam? I remember you mentioned it's coming up!" |
| "Thai food nearby" | Standard results | "I've filtered out places with peanuts given your severe allergy" |

### Session State: Short-Term Context

**Session state** persists only within a single conversation session.

```
┌─────────────────────────────────────────┐
│            SESSION 1                     │
│  User: "I'm vegetarian"                  │
│  Agent: "Got it!"                        │
│  User: "Find me restaurants"             │
│  Agent: ✅ Shows vegetarian options      │
└─────────────────────────────────────────┘
                    ↓
            [Session Ends]
                    ↓
┌─────────────────────────────────────────┐
│            SESSION 2                     │
│  User: "Find me restaurants"             │
│  Agent: ❌ Shows ALL options (forgot!)   │
└─────────────────────────────────────────┘
```

**Use case:** Within a single chat, the agent remembers context. But close the browser or start a new session? Everything is gone.

### Memory Bank: Long-Term Persistence

**Memory Bank** extracts and stores important facts across sessions, creating persistent user knowledge.

```
┌─────────────────────────────────────────┐
│            SESSION 1                     │
│  User: "I'm vegetarian"                  │
│  Agent: "Got it!"                        │
│         [Saves to Memory Bank]           │
└─────────────────────────────────────────┘
                    ↓
            [Days Later...]
                    ↓
┌─────────────────────────────────────────┐
│            SESSION 2                     │
│  [Agent retrieves from Memory Bank]      │
│  User: "Find me restaurants"             │
│  Agent: ✅ Shows vegetarian options      │
│         "Since you're vegetarian..."     │
└─────────────────────────────────────────┘
```

### Why Memory Bank Matters

| Feature | Session State | Memory Bank |
|---------|---------------|-------------|
| **Persistence** | Single session only | Across all sessions forever |
| **Storage** | In-memory, temporary | Vertex AI cloud storage |
| **Knowledge** | Raw conversation | Extracted facts & insights |
| **Feel** | Talking to a stranger | Talking to an old friend |

**Memory Bank transforms agents from tools into companions** - assistants that truly know you and improve over time.

---

## Demo Scenarios (日本語版)

These demos showcase the power of cross-session memory for Japanese users. Each scenario requires multiple sessions to demonstrate the "magic moment."

### Demo 1: 「心を読む」 - The Mind Reader

**Session 1 - 情報を伝える:**
```
来週の金曜日に妻の美咲との結婚5周年記念日をお祝いします。
美咲は京都出身で、時々故郷の料理が恋しくなるみたいです。
初デートは東京タワーが見えるレストランでした。
```

**Session 2 - 魔法の瞬間（新しいセッション）:**
```
金曜日のディナーにおすすめのレストランはありますか？
```

**Expected:** Agent suggests restaurants with Tokyo Tower views or Kyoto cuisine, mentions the anniversary, without any reminders!

---

### Demo 2: 「アレルギーの守護者」 - The Allergy Guardian

**Session 1 - 重要な安全情報:**
```
私はそばアレルギーがあります。少量でも重篤な反応が出るので、
絶対に気をつけなければなりません。
```

**Session 2 - レストラン検索:**
```
新宿で和食のお店を探して
```

**Expected:** Agent proactively warns about soba/buckwheat risks in Japanese cuisine, filters results, acts as a protective guardian.

---

### Demo 3: 「好みの変化」 - The Preference Evolution

**Session 1:**
```
私の名前は健太です。焼肉が大好きで、特にカルビが最高！週に2回は焼肉屋に行っています。
```

**Session 2（新しいセッション）:**
```
健康診断の結果が悪かったので、今日からベジタリアンに完全に切り替えることにしました。
もう肉は一切食べません。野菜中心の食生活にします。
```

*（サーバーログで `memories:generate` が完了したことを確認してから次へ進む）*

**Session 3（新しいセッション）:**
```
新宿でディナーのおすすめを探して
```

**Expected:** Agent recommends vegetarian options and mentions the dietary change: 「ベジタリアンに切り替えられたとのことでしたので、野菜中心のお店をお探ししました...」

> **Tip:** Memory generation takes a moment. After each session ends, wait for the `memories:generate` log message before starting the next session.

---

## How It Works

1. **Session ends** → `after_agent_callback` triggers memory generation
2. **Memory Bank** extracts key facts (names, dates, preferences, relationships)
3. **New session starts** → `PreloadMemoryTool` retrieves relevant memories
4. **Agent responds** with personalized, context-aware recommendations

Check server logs for `memories:retrieve` and `memories:generate` calls to verify memory operations.

---

## Resources

- [ADK + Vertex AI Memory Engine Tutorial](https://medium.com/google-cloud/manage-your-user-sessions-with-adk-and-vertex-ai-memory-engine-447c53b189df)
- [Live Demo](https://restaurantfinder-85469421903.us-central1.run.app/)
