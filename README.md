# Project-02: Automated CI/CD Deployment of Kanban Dashboard on AWS EC2 using Docker & Jenkins

## Architecture Overview
```text
GitHub Push (Webhook) ──▶ Jenkins (EC2 :8080) ──▶ Multi-Stage Docker Build
                                                          │
   Live App (:3000) ◀── Health Check & Rollback ◀── Docker Hub (Versioned Tag)
```

---

## Stage 1: Application Setup & Local Verification
1. Clone the repository and inspect configuration:
   ```bash
   git clone https://github.com/Vennilavanguvi/kanban-dashboard.git
   cd kanban-dashboard
   cat package.json
   ```
2. Install dependencies and start locally:
   ```bash
   npm install
   npm run dev   # or npm start (Default Vite port: 5173 | CRA port: 3000)
   ```
3. Verify local endpoint before containerization:
   ```bash
   curl -I http://localhost:5173
   ```
   > **Note:** If `package.json` uses Create React App (`react-scripts`), update `COPY --from=builder /app/dist` in `Dockerfile` to `/app/build`. For Vite apps, `/app/dist` is used by default.

---

## Stage 2 & 3: Docker Containerization & Security Hardening
- **Multi-Stage Build:** `node:20-alpine` compiles static assets; `nginx:1.27-alpine-slim` serves only built files.
- **Non-Root Execution:** Runs under dedicated UID/GID `1001` (`appuser:appgroup`).
- **Read-Only Root Filesystem:** Runtime container runs with `--read-only` and `tmpfs` mounts for Nginx PID/cache.
- **Healthcheck:** Built-in `HEALTHCHECK` queries `http://localhost:3000/health` every 30s.

### Build & Verify Locally:
```bash
docker build -t kanban-dashboard:1.0.0 .
docker run -d --name kanban-test -p 3000:3000 --memory="256m" --cpus="0.5" kanban-dashboard:1.0.0

# Verify non-root user
docker inspect --format='{{.Config.User}}' kanban-dashboard:1.0.0
# Expected Output: appuser

# Verify health status
docker inspect --format='{{.State.Health.Status}}' kanban-test
# Expected Output: healthy

# Verify endpoint
curl -i http://localhost:3000/health
```

---

## Stage 4: Container Registry & Immutable Versioning
Images are tagged with `${BUILD_NUMBER}-${GIT_SHORT_SHA}` (never relying solely on `latest`):
```bash
docker tag kanban-dashboard:1.0.0 <DOCKER_USER>/kanban-dashboard:1-a1b2c3d
docker login
docker push <DOCKER_USER>/kanban-dashboard:1-a1b2c3d
```

---

## Stage 5: AWS EC2 Infrastructure Setup
1. **Launch EC2 Instance:**
   - **AMI:** Ubuntu Server 24.04 LTS
   - **Instance Type:** `t3.small` (2 vCPU, 2 GB RAM — comfortably hosts Jenkins + Nginx + App container)
2. **Security Group Inbound Rules:**
   | Type | Protocol | Port | Source | Purpose |
   | :--- | :--- | :--- | :--- | :--- |
   | SSH | TCP | `22` | My IP | Server administration |
   | Custom TCP | TCP | `8080` | My IP / GitHub Webhook IPs | Jenkins UI & Webhook |
   | Custom TCP | TCP | `3000` | `0.0.0.0/0` | Public Kanban Dashboard |
3. **Run Bootstrap Script:**
   ```bash
   chmod +x scripts/ec2-setup.sh
   ./scripts/ec2-setup.sh
   ```

---

## Stage 6, 7 & 8: Jenkins Configuration & GitHub Webhook
1. **Required Jenkins Plugins:**
   - `Git`
   - `Docker Pipeline`
   - `Credentials Binding`
2. **Credentials Store (`Manage Jenkins -> Credentials -> Global`):**
   - **ID:** `dockerhub-credentials` (Kind: *Username with password* — Docker Hub username & Access Token).
3. **Pipeline Job Setup:**
   - Create **Pipeline** job (`kanban-dashboard-cicd`).
   - Under **Build Triggers**, enable **GitHub hook trigger for GITScm polling**.
   - Under **Pipeline**, select **Pipeline script from SCM** -> **Git** -> Repo URL -> Branch `*/main` -> Script Path `Jenkinsfile`.
4. **GitHub Webhook Setup:**
   - Go to GitHub Repo -> **Settings -> Webhooks -> Add webhook**.
   - **Payload URL:** `http://<EC2_PUBLIC_IP>:8080/github-webhook/`
   - **Content type:** `application/json`
   - **Event:** Just the `push` event.

---

## Stage 9, 10 & 11: Resource Limits & Zero-Downtime Blue-Green Deployment
### Resource Allocation Justification (`t3.small` — 2 vCPU, 2048 MB RAM)
- **Container Memory Limit (`--memory="256m"`):** Static Nginx serves pre-built React assets using ~15–25 MB RAM under load. Capping at 256 MB leaves >1.7 GB for Jenkins JVM and OS processes, preventing OOM kills.
- **Container CPU Limit (`--cpus="0.5"`):** Reserves 25% of total host CPU capacity so traffic spikes never starve Jenkins builds.

### Zero-Downtime Blue-Green Strategy (`scripts/deploy.sh`)
1. Detects currently active container (`kanban-blue` on `:3001` or `kanban-green` on `:3002`).
2. Starts the new image version on the idle slot alongside the live container.
3. Polls Docker `HEALTHCHECK` and HTTP `/health` up to 60 seconds.
4. **On Failure:** Immediately destroys the unhealthy new container and exits non-zero; active container remains untouched (**automatic rollback**).
5. **On Success:** Updates host Nginx reverse proxy (`:3000`) and runs `nginx -s reload` (zero dropped connections), then stops and removes the old container.

---

## Proof & Verification Checklist
- [ ] Local app screenshot / `curl` output before Dockerization
- [ ] `docker inspect` output showing `User: appuser` and `Health.Status: healthy`
- [ ] Docker Hub repository screenshot showing versioned tags (`<build>-<sha>`)
- [ ] AWS EC2 Security Group screenshot showing only ports `22`, `8080`, and `3000`
- [ ] GitHub Webhook recent deliveries green checkmark (`200 OK`)
- [ ] Jenkins Stage View screenshot showing end-to-end passing pipeline & a simulated failed health-check rollback log
- [ ] Live Application URL screenshot (`http://<EC2_PUBLIC_IP>:3000`)
