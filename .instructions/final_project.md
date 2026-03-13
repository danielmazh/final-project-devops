## Final Project – Full DevOps Lifecycle Implementation

**Objective:** Build a production■style DevOps platform around an existing real-world project while implementing CI/CD, containerization, infrastructure automation, Kubernetes deployment, and observability.


### Base Project

This exercise is based on the open■source repository: https://github.com/yuribernstein/seyoawe-community. Students will use this repository as the core application and build a full DevOps lifecycle around it.

The goal is to transform the project into a production■ready system by adding automated pipelines, infrastructure provisioning, container builds, Kubernetes deployment, monitoring, and versioning.


### Project Architecture Overview

- GitHub – source control and version management
- Jenkins – CI/CD pipelines
- Docker – application containerization
- Docker Hub – container registry
- Terraform – infrastructure provisioning
- Ansible – configuration management
- Kubernetes – application orchestration
- Prometheus & Grafana – monitoring and observability


### Project Tasks

1. **Containerization & Kubernetes Deployment**  
   Containerize the automation engine using Docker and deploy it into Kubernetes using a StatefulSet. Implement health probes, persistent storage, and service configuration.

2. **CI Pipeline for the Engine**  
   Create a Jenkins CI pipeline that performs linting, testing, Docker builds, semantic versioning, and publishes images to Docker Hub.

3. **CI Pipeline for the CLI Tool**  
   Build a separate pipeline for the CLI tool including unit tests, packaging, artifact publishing, and semantic version tagging.

4. **Version Coupling**  
   Ensure both engine and CLI share the same semantic version. Pipelines should detect which components changed and avoid unnecessary rebuilds.

5. **Continuous Deployment Pipeline**  
   Implement a CD pipeline that provisions infrastructure with Terraform, configures systems with Ansible, and deploys the application to Kubernetes.

6. **Observability (Bonus)**  
   Integrate monitoring and logging tools such as Prometheus and Grafana for metrics, dashboards, and alerting.


### Suggested Repository Structure

- engine/ – automation engine source code
- cli/ – CLI implementation
- docker/ – Dockerfiles
- k8s/ – Kubernetes manifests
- terraform/ – infrastructure provisioning
- ansible/ – configuration playbooks
- jenkins/ – CI/CD pipelines
- monitoring/ – Prometheus & Grafana configuration


### Bonus (Optional): AI RAG Extension

Students may extend the platform with an AI RAG (Retrieval Augmented Generation) service. This service can analyze workflow logs and documentation and provide troubleshooting assistance through a chatbot interface.


### Evaluation Criteria

| Category                          | Points |
|-----------------------------------|--------|
| Engine containerization           | 10     |
| CLI testing and packaging         | 10     |
| CI pipeline for engine            | 15     |
| CI pipeline for CLI               | 10     |
| Version coupling logic            | 15     |
| CD pipeline (Terraform + Ansible) | 20     |
| Code structure & documentation    | 10     |
| Bonus: Observability              | +10    |

**Total Possible Score:** 100

### Deliverables

- GitHub repository with CI/CD pipelines
- Docker images published to Docker Hub
- Kubernetes deployment manifests
- Terraform and Ansible infrastructure code
- Project documentation explaining architecture and pipeline flow

---

**DevOps Final Project Exercise**
