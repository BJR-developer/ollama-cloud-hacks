***

# Ollama Cloud on Render (Mac + SSH key method)

Run **Ollama Cloud models** (like `nemotron-3-super:cloud`) on **Render** using your **Mac’s authenticated Ollama identity**.  
This repo shows how to bake your `~/.ollama` SSH keys into a Docker image so a headless Render instance can talk to `ollama.com` as if it were your Mac. [notes.kodekloud](https://notes.kodekloud.com/docs/Running-Local-LLMs-With-Ollama/Customising-Models-With-Ollama/Uploading-Custom-Models/page)

> ⚠️ This guide assumes:
> - You’re on macOS.
> - You already have a Render account.
> - You’re comfortable with Docker, git, and basic cloud deployment.

***

## How it works (high level)

- When you run `ollama signin` on your Mac, Ollama creates an SSH key pair in `~/.ollama` and links the **public** key to your Ollama account. [notes.kodekloud](https://notes.kodekloud.com/docs/Running-Local-LLMs-With-Ollama/Customising-Models-With-Ollama/Demo-Uploading-Custom-Models/page)
- A headless server (like a Docker container on Render) normally can’t complete that browser login flow.
- In this setup, we:
  - Copy the **private** and **public** key from your Mac into **Render environment variables**.
  - Use a **custom Dockerfile** whose entrypoint writes those env vars into `/root/.ollama/id_ed25519*` before starting `ollama serve`. [docs.ollama](https://docs.ollama.com/docker)
  - The Render instance now looks to Ollama Cloud like your signed‑in Mac and can run `:cloud` models.

***

## 1. Sign in to Ollama Cloud on your Mac

On your MacBook:

```bash
ollama signin
```

If the browser doesn’t open, paste the printed `https://ollama.com/connect?...` URL into your browser manually and **click Connect**. [docs.ollama](https://docs.ollama.com/api/authentication)

Confirm sign‑in in the Ollama UI or web account.

***

## 2. Grab your Mac Ollama keys

On your Mac, run:

```bash
cat ~/.ollama/id_ed25519
cat ~/.ollama/id_ed25519.pub
```

You’ll get:

- A **multi‑line private key**:

  ```text
  -----BEGIN OPENSSH PRIVATE KEY-----
  ...
  -----END OPENSSH PRIVATE KEY-----
  ```

- A **single‑line public key**:

  ```text
  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... yourname@host
  ``` [notes.kodekloud](https://notes.kodekloud.com/docs/Running-Local-LLMs-With-Ollama/Customising-Models-With-Ollama/Uploading-Custom-Models/page)

Keep this terminal window open; you’ll paste both into Render later.

***

## 3. Dockerfile used in this repo

This repo’s `Dockerfile` is minimal and does three things:

- Creates `/root/.ollama`.
- On container start, writes the env vars into the key files.
- Starts `ollama serve`.

```dockerfile
FROM ollama/ollama:latest

# Create the internal Ollama directory
RUN mkdir -p /root/.ollama

# Pre-create key files and secure permissions
RUN touch /root/.ollama/id_ed25519 && \
    touch /root/.ollama/id_ed25519.pub && \
    chmod 600 /root/.ollama/id_ed25519

# At runtime, inject keys from env vars, then start Ollama
ENTRYPOINT ["/bin/sh", "-c", "echo \"$OLLAMA_PRIVATE_KEY\" > /root/.ollama/id_ed25519 && echo \"$OLLAMA_PUBLIC_KEY\" > /root/.ollama/id_ed25519.pub && exec ollama serve"]
```

Ollama’s API will be served on port `11434` inside the container as usual. [docs.ollama](https://docs.ollama.com/docker)

***

## 4. Deploy to Render

1. Push this repo to GitHub (public or private).
2. In Render Dashboard:
   - **New → Web Service**.
   - Connect your GitHub repo.
   - **Runtime**: Docker.
   - **Instance type**: pick according to your needs.
3. In **Environment Variables**, add:

   | KEY                | VALUE                                                                 |
   |--------------------|-----------------------------------------------------------------------|
   | `OLLAMA_PRIVATE_KEY` | Paste the full multi‑line private key block (BEGIN…END).             |
   | `OLLAMA_PUBLIC_KEY`  | Paste the single‑line public key (starting with `ssh-ed25519`).      |

   Render supports multi‑line env vars; just paste as‑is. [docs.ollama](https://docs.ollama.com/faq)

4. Optionally, if you want your own HTTP auth in front of the API, also add:

   - `PROXY_BEARER` or similar, and implement it in a reverse proxy (not included here).

5. Click **Deploy Web Service**.

Render builds the Docker image, then launches `ollama serve` with your keys in `/root/.ollama`.

***

## 5. Test the deployed instance

Assume your Render URL is:

```text
https://YOUR-SERVICE.onrender.com
```

### 5.1 Check that Ollama is up

```bash
curl https://YOUR-SERVICE.onrender.com/api/version
```

You should see a JSON object with the running Ollama version. [docs.ollama](https://docs.ollama.com/api/introduction)

### 5.2 Pull a cloud model

Example: Nemotron 3 Super cloud model:

```bash
curl -X POST https://YOUR-SERVICE.onrender.com/api/pull \
  -H "Content-Type: application/json" \
  -d '{"name": "nemotron-3-super:cloud", "stream": false}'
```

You should get:

```json
{"status":"success"}
```

### 5.3 Verify the model is registered

```bash
curl https://YOUR-SERVICE.onrender.com/api/tags
```

Expected output includes:

```json
{
  "name": "nemotron-3-super:cloud",
  "remote_host": "https://ollama.com:443",
  ...
}
```

### 5.4 Run a cloud inference

```bash
curl https://YOUR-SERVICE.onrender.com/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nemotron-3-super:cloud",
    "prompt": "Explain hybrid MoE architecture in 3 concise sentences.",
    "stream": false
  }'
```

If your keys are wired correctly and linked to your Ollama account, you’ll get a JSON response with a `response` field containing the model output. [docs.ollama](https://docs.ollama.com/api/authentication)

***

## 6. Common errors & fixes

### `{"error":"unauthorized"}` on `generate`

If `pull` and `tags` work but `generate` returns `unauthorized`, it usually means:

- The SSH keys in `/root/.ollama` do **not** match the key you connected at `ollama.com`, or
- You didn’t complete the browser `connect` flow for the exact key you baked in, or
- Your account/plan doesn’t have access to that specific `:cloud` model. [github](https://github.com/ollama/ollama/issues/15074)

Checklist:

- Open `cat ~/.ollama/id_ed25519.pub` again on your Mac and verify it matches exactly the public key you pasted to `OLLAMA_PUBLIC_KEY` and the one shown in your Ollama account settings. [notes.kodekloud](https://notes.kodekloud.com/docs/Running-Local-LLMs-With-Ollama/Customising-Models-With-Ollama/Demo-Uploading-Custom-Models/page)
- Make sure the private key is complete (no missing lines, no extra spaces).
- Redeploy the service after updating env vars.

### `pull` fails for some `:cloud` models

If you see `{"error":"pull model manifest: file does not exist"}`, the tag might not exist or not be available to your account yet (e.g. `qwen3:cloud` vs specific variants). [datacamp](https://www.datacamp.com/tutorial/qwen3-ollama)

Check the Ollama library for valid model names and tags, then use those. [ollama](https://ollama.com/search?c=cloud)

***

## 7. Using a different cloud model

Once the identity plumbing is working, you can swap models freely by changing the `"model"` / `"name"` field:

```bash
# Pull another cloud model
curl -X POST https://YOUR-SERVICE.onrender.com/api/pull \
  -H "Content-Type: application/json" \
  -d '{"name": "gpt-oss:120b-cloud", "stream": false}'

# Generate
curl https://YOUR-SERVICE.onrender.com/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss:120b-cloud",
    "prompt": "Give me 3 ideas for automating Reddit scraping.",
    "stream": false
  }'
```

***

## 8. Notes on security

- **Never commit your keys** to git. In this setup, keys only live in Render env vars, not in the repo. [linkedin](https://www.linkedin.com/pulse/securing-ollama-authentication-alen-joses-r-yawhf)
- Consider **rotating** your keys or generating a dedicated Ollama identity just for Render, rather than reusing your main workstation identity. [github](https://github.com/ollama/ollama/issues/11567)
- If you want additional protection, put your Render service behind:
  - A private network / VPN, or
  - An API gateway that validates its own auth token before forwarding to `ollama serve`. [linkedin](https://www.linkedin.com/pulse/securing-ollama-authentication-alen-joses-r-yawhf)

***
