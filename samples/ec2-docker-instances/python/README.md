# EC2 Docker Instances

This sample demonstrates LocalStack's EC2 Docker backend, which runs EC2 instances as Docker containers.

## Overview

LocalStack can emulate EC2 instances using Docker containers as the backend. This allows you to:

1. Run actual compute workloads in your local environment
2. Test EC2 and SSM functionality
3. Create AMIs from running instances

## Architecture

```
Docker Image (ubuntu:focal)
    └── Tagged as AMI (ami-00a001)
         └── EC2 Instance (Docker container)
              └── SSM Agent (command execution)
```

## Prerequisites

- LocalStack Pro with **EC2_VM_MANAGER=docker** enabled
- Docker
- Python 3.10+

## Important: Enable EC2 Docker Backend

Start LocalStack with the EC2 Docker backend:

```bash
LOCALSTACK_AUTH_TOKEN=... EC2_VM_MANAGER=docker localstack start
```

Or with Docker:

```bash
docker run -d \
  -p 4566:4566 \
  -e LOCALSTACK_AUTH_TOKEN \
  -e EC2_VM_MANAGER=docker \
  -v /var/run/docker.sock:/var/run/docker.sock \
  localstack/localstack-pro
```

**Note**: The Docker socket mount (`-v /var/run/docker.sock:/var/run/docker.sock`) is required for LocalStack to create Docker containers for EC2 instances.

## IaC Methods

| Method | Status | Notes |
|--------|--------|-------|
| scripts | Supported | AWS CLI deployment |
| terraform | Not implemented | |
| cloudformation | Not implemented | |
| cdk | Not implemented | |

## Deployment

```bash
cd samples/ec2-docker-instances/python

# Deploy (creates Docker-backed EC2 instance)
./scripts/deploy.sh

# Teardown
./scripts/teardown.sh
```

## Testing

```bash
# Run tests (will skip EC2 Docker tests if backend not enabled)
uv run pytest samples/ec2-docker-instances/python/ -v
```

## How It Works

1. **AMI Preparation**: The deploy script tags `ubuntu:focal` as `localstack-ec2/ubuntu-focal-docker-ami:ami-00a001`

2. **Instance Launch**: Creates an EC2 instance using the tagged AMI, which launches a Docker container

3. **SSM Commands**: Tests can send shell commands to the instance via SSM

4. **AMI Creation**: Tests can snapshot the running instance into a new AMI

## Resources Created

- Docker-backed AMI: `ami-00a001`
- EC2 Instance running as Docker container
- Any AMIs created from snapshots

## Environment Variables

After deployment, the following variables are written to `scripts/.env`:

- `AMI_ID`: AMI used for the instance
- `INSTANCE_ID`: EC2 instance ID
- `INSTANCE_NAME`: Instance name tag
- `PRIVATE_IP`: Instance private IP
- `PUBLIC_IP`: Instance public IP
- `EC2_DOCKER_ENABLED`: Whether EC2 Docker backend was detected

## Troubleshooting

### Tests skipped with "EC2 Docker backend not enabled"

Start LocalStack with `EC2_VM_MANAGER=docker`:

```bash
EC2_VM_MANAGER=docker localstack start
```

### Instance fails to start

Ensure Docker socket is mounted:

```bash
docker run ... -v /var/run/docker.sock:/var/run/docker.sock ...
```

### AMI not found

The deploy script automatically tags the Ubuntu image. If needed, manually prepare:

```bash
docker pull ubuntu:focal
docker tag ubuntu:focal localstack-ec2/ubuntu-focal-docker-ami:ami-00a001
```

## License

Apache 2.0
