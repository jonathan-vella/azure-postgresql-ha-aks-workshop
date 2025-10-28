# DevContainer Setup Guide

## What is a DevContainer?

A DevContainer (Development Container) is a Docker container that includes all development tools and dependencies for a project. It provides a **consistent, reproducible environment** across Windows, macOS, and Linux.

**Benefits**:
- ✅ All tools pre-installed (Azure CLI, kubectl, Helm, jq, OpenSSL)
- ✅ Consistent environment for all developers
- ✅ No PATH issues or version conflicts
- ✅ Works seamlessly with VS Code
- ✅ Nothing installed on your host machine
- ✅ Easy to update tools
- ✅ Clean development experience

---

## Prerequisites

### Required
- **Docker Desktop** (Windows/Mac) or **Docker Engine** (Linux)
  - Download: https://www.docker.com/products/docker-desktop
  - Installation: Follow Docker's official guide for your OS

- **VS Code** (Visual Studio Code)
  - Download: https://code.visualstudio.com/

### Recommended
- **VS Code Extensions** (auto-installed):
  - Remote - Containers
  - Azure Account
  - Bicep
  - Kubernetes Tools
  - Terraform

---

## Quick Start

### Step 1: Install Docker Desktop

**Windows 11**:
1. Download Docker Desktop from https://www.docker.com/products/docker-desktop
2. Run the installer
3. Follow the setup wizard
4. Restart your computer
5. Open PowerShell and verify: `docker --version`

**macOS**:
```bash
# Using Homebrew
brew install docker
brew install docker-desktop
# Or download from https://www.docker.com/products/docker-desktop
```

**Linux**:
```bash
sudo apt-get update
sudo apt-get install docker.io docker-compose
sudo usermod -aG docker $USER
newgrp docker
```

### Step 2: Install VS Code Extension

1. Open VS Code
2. Go to Extensions (Ctrl+Shift+X)
3. Search for: `Remote - Containers`
4. Click Install on the Microsoft extension

### Step 3: Open Project in DevContainer

1. Open the project folder in VS Code
2. Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac)
3. Type: `Dev Containers: Reopen in Container`
4. Select it and wait for container build (2-5 minutes first time)
5. ✅ Container starts with all tools ready!

---

## What's Installed in the Container

| Tool | Version | Purpose |
|------|---------|---------|
| **Azure CLI** | 2.56.0+ | Azure resource management |
| **kubectl** | 1.31.0+ | Kubernetes cluster management |
| **Helm** | 3.13.0+ | Kubernetes package manager |
| **jq** | 1.7.1+ | JSON query and processing |
| **OpenSSL** | 1.1.1+ | Cryptography and SSL tools |
| **Git** | Latest | Version control |
| **Make** | Latest | Build automation |
| **curl/wget** | Latest | HTTP tools |
| **nano/vim** | Latest | Text editors |

---

## Using the DevContainer

### Terminal Access

Once inside the DevContainer, you have full terminal access:

```bash
# Check tools are installed
az --version
kubectl version --client
helm version
jq --version
openssl version

# Navigate to project
cd /workspaces/azure-postgresql-ha-aks-workshop

# Run deployment script (via bash/shell inside container)
./scripts/deploy-postgresql-ha.sh
```

### VS Code Features

1. **Integrated Terminal**: Automatically opens inside container
2. **File Explorer**: Full access to project files
3. **Extensions**: All extensions work inside container
4. **Debugging**: Full debug capabilities
5. **Port Forwarding**: Automatically set up for PostgreSQL (5432), Grafana (3000), etc.

### Running Deployment

**Bash (Recommended)**:
```bash
# Load environment variables
source config/environment-variables.sh

# Deploy all components
./scripts/deploy-all.sh
```

---

## Configuration Files

### `.devcontainer/devcontainer.json`
Main configuration file that defines:
- Base image (Ubuntu 22.04)
- Features (Azure CLI, kubectl, Helm)
- VS Code extensions
- Port forwarding
- Environment setup

### `.devcontainer/post-create.sh`
Script that runs after container creation:
- Installs additional tools
- Verifies installations
- Shows quick reference

---

## Common Commands

### DevContainer Management

```bash
# Reopen in container (from VS Code command palette)
Ctrl+Shift+P -> "Dev Containers: Reopen in Container"

# Rebuild container (if devcontainer.json changed)
Ctrl+Shift+P -> "Dev Containers: Rebuild Container"

# Reopen locally (exit container)
Ctrl+Shift+P -> "Dev Containers: Reopen Locally"

# Clone Repository in Container
Ctrl+Shift+P -> "Dev Containers: Clone Repository in Container Volume"
```

### Inside Container Terminal

```bash
# Verify tools
az version
kubectl version --client
helm version
jq --version

# Navigate to project
cd /workspaces/azure-postgresql-ha-aks-workshop

# Load environment variables
source config/environment-variables.sh

# Review configuration
echo "Region: $PRIMARY_CLUSTER_REGION"
echo "AKS Version: $AKS_CLUSTER_VERSION"

# Run deployment (Azure CLI automation)
./scripts/deploy-all.sh
```

---

## Port Forwarding

The DevContainer automatically configures port forwarding for:

| Port | Service | Access |
|------|---------|--------|
| 5432 | PostgreSQL | localhost:5432 |
| 3000 | Grafana | localhost:3000 |
| 8080 | Kubernetes API | localhost:8080 |
| 9090 | Prometheus | localhost:9090 |

Access from host machine:
```bash
# PostgreSQL
psql -h localhost -U app -d appdb

# Grafana
curl http://localhost:3000

# Prometheus
curl http://localhost:9090
```

---

## Troubleshooting

### Issue: Docker Desktop not running
**Solution**: Start Docker Desktop application from start menu or:
```powershell
# Windows PowerShell
Start-Process "Docker Desktop"
```

### Issue: Container build fails
**Solution**: 
1. Check Docker is running: `docker ps`
2. Rebuild container: `Ctrl+Shift+P` -> "Rebuild Container"
3. Check available disk space (need ~5GB)

### Issue: Tools not found in container
**Solution**:
1. Container may still be building (check terminal)
2. Verify installation: `docker exec -it container_name bash`
3. Rebuild: `Ctrl+Shift+P` -> "Rebuild Container"

### Issue: Azure CLI authentication fails
**Solution**:
Azure credentials are mounted from host:
1. Ensure logged in on host: `az login`
2. Container auto-mounts `~/.azure` folder
3. Inside container: `az account show`

### Issue: Port forwarding not working
**Solution**:
1. Check port in devcontainer.json (forwardPorts section)
2. Verify service is running inside container
3. From host terminal: `netstat -an | findstr 5432`

---

## Working with Teams

### Sharing the DevContainer

All team members use the same devcontainer.json:
```bash
# Everyone gets identical environment
# Just open in VS Code: "Reopen in Container"
# All tools automatically installed
```

### Updating Tools

To update tool versions:
1. Edit `.devcontainer/devcontainer.json`
2. Update feature versions
3. Run `Ctrl+Shift+P` -> "Rebuild Container"
4. Commit changes to git
5. All team members get updates automatically

---

## Performance Tips

### Reduce Container Build Time
- First build: 2-5 minutes (downloads base image)
- Subsequent builds: <1 minute (uses cache)

### Improve Disk Space
- Docker images: ~1.5GB
- Container: ~500MB
- Total: ~2GB with tools

### Speed Optimization
- Use SSD for Docker images
- Allocate sufficient CPU/Memory in Docker Desktop settings
- Don't mount large folders unnecessarily

---

## Cleanup

### Remove Container
```bash
# From VS Code: Ctrl+Shift+P -> "Dev Containers: Delete Container"

# Or from terminal:
docker rm -f container_name
```

### Free Disk Space
```bash
# Remove unused images
docker image prune

# Remove all unused containers
docker system prune

# Full cleanup (warning: removes all images/containers)
docker system prune -a
```

---

## Next Steps

1. ✅ Install Docker Desktop
2. ✅ Install VS Code Remote - Containers extension
3. ✅ Open project folder in VS Code
4. ✅ Run "Dev Containers: Reopen in Container"
5. ✅ Wait for container build to complete
6. ✅ Verify tools: `az version`, `kubectl version`, etc.
7. ✅ Start deploying!

---

## Additional Resources

- **Docker Documentation**: https://docs.docker.com/
- **VS Code Remote Development**: https://code.visualstudio.com/docs/remote/remote-overview
- **Dev Containers Specification**: https://containers.dev/
- **PostgreSQL HA Documentation**: See `docs/README.md`

---

**Status**: ✅ DevContainer ready for PostgreSQL HA on AKS deployment
